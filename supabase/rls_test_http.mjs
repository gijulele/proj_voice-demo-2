// ============================================================
// supabase/rls_test_http.mjs — RLS 를 "앱이 겪는 경로 그대로" 검증한다
//
// rls_test.mjs 와의 차이
//   rls_test.mjs      DB 에 직접 붙어 SQL 로 검사. DB 비밀번호 필요.
//   이 파일           REST API(PostgREST)로 검사. URL + anon key 만 있으면 된다.
//                     ★ 브라우저가 실제로 타는 경로라 이쪽이 진짜에 가깝다.
//
// 실행:  node supabase/rls_test_http.mjs
// 종료코드: 0 = 통과, 1 = 실패
//
// .env.local 에 필요한 값
//   NEXT_PUBLIC_SUPABASE_URL       (필수)
//   NEXT_PUBLIC_SUPABASE_ANON_KEY  (필수)
//   DEMO_EMAIL / DEMO_PASSWORD     (선택 — 없으면 로그인 검사는 건너뛴다)
// ============================================================

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

function loadEnv() {
  const env = {};
  for (const name of ['.env', '.env.local']) {
    try {
      const text = readFileSync(join(ROOT, name), 'utf8');
      for (const line of text.split(/\r?\n/)) {
        const m = line.match(/^\s*(?:export\s+)?([A-Z0-9_]+)\s*=\s*(.*)$/i);
        if (m) env[m[1]] = m[2].trim().replace(/^["']|["']$/g, '');
      }
    } catch { /* 파일 없음 */ }
  }
  return { ...env, ...process.env };
}

const env = loadEnv();
const URL_ = env.NEXT_PUBLIC_SUPABASE_URL ?? env.SUPABASE_URL;
const ANON = env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? env.SUPABASE_ANON_KEY;

if (!URL_ || !ANON) {
  console.error(`
NEXT_PUBLIC_SUPABASE_URL 과 NEXT_PUBLIC_SUPABASE_ANON_KEY 가 필요합니다.
${join(ROOT, '.env.local')} 에 넣어주세요.
대시보드 > Project Settings > API 에서 복사할 수 있습니다.
`);
  process.exit(2);
}

// ------------------------------------------------------------
// 결과 수집
// ------------------------------------------------------------
const results = [];
function record(name, ok, detail) {
  results.push({ name, ok });
  console.log(`${ok ? '  PASS' : '  FAIL'}  ${name}`);
  if (detail) console.log(`        ${detail}`);
}

// PostgREST 호출. token 이 없으면 비로그인(anon) 상태.
async function api(path, { token, method = 'GET', body, prefer } = {}) {
  const headers = {
    apikey: ANON,
    Authorization: `Bearer ${token ?? ANON}`,
  };
  if (body) headers['Content-Type'] = 'application/json';
  if (prefer) headers.Prefer = prefer;

  const res = await fetch(`${URL_}/rest/v1/${path}`, {
    method, headers, body: body ? JSON.stringify(body) : undefined,
  });

  const text = await res.text();
  let json = null;
  try { json = text ? JSON.parse(text) : null; } catch { /* 에러 본문이 JSON 이 아닐 수 있다 */ }
  return { status: res.status, json, text };
}

async function signIn(email, password) {
  const res = await fetch(`${URL_}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: { apikey: ANON, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password }),
  });
  const json = await res.json().catch(() => null);
  return res.ok
    ? { token: json.access_token, uid: json.user?.id }
    : { error: json?.error_description ?? json?.msg ?? `HTTP ${res.status}` };
}

const rows = (r) => (Array.isArray(r.json) ? r.json.length : null);

// ------------------------------------------------------------
console.log(`\nRLS 검증 (HTTP) — ${URL_}\n${'-'.repeat(56)}`);
console.log('[비로그인 상태에서 무엇이 보이는가]');

// 1. anon 이 개인 테이블을 읽으려 하면 빈 배열이어야 한다.
//    ※ 401/403 이 아니라 "0행"이 정상이다. RLS 는 막는 게 아니라 안 보이게 한다.
for (const table of ['recordings', 'analyses', 'key_results', 'profiles']) {
  const r = await api(`${table}?select=id`);
  const n = rows(r);
  record(
    `anon → ${table} 읽기`,
    r.status === 200 ? n === 0 : [401, 403].includes(r.status),
    r.status === 200
      ? (n === 0 ? '0행 (정상)' : `★ ${n}행이 보인다 — 개인정보 유출`)
      : `HTTP ${r.status} (접근 차단)`,
  );
}

// 2. song_refs — 정책이 "to authenticated" 라 anon 에게는 0행이 설계대로다.
{
  const r = await api('song_refs?select=id');
  const n = rows(r);
  record(
    'anon → song_refs 읽기',
    r.status === 200 || [401, 403].includes(r.status),
    n === 0 || r.status !== 200
      ? '0행 — 설계대로(로그인해야 곡 목록이 보임)'
      : `${n}행 공개 중 — 로그인 전 곡 목록 노출을 의도했다면 정상`,
  );
}

// 3. anon 이 데이터를 쓰려 하면 거부되어야 한다.
{
  const r = await api('recordings', {
    method: 'POST',
    body: {
      user_id: '00000000-0000-0000-0000-000000000099',
      file_path: 'hack/anon.webm',
      duration_sec: 30,
    },
    prefer: 'return=representation',
  });
  const blocked = r.status === 401 || r.status === 403
    || r.json?.code === '42501';
  record(
    'anon → recordings 쓰기 차단',
    blocked,
    blocked
      ? `HTTP ${r.status} — ${r.json?.message ?? '거부됨'}`
      : `★ HTTP ${r.status} — 비로그인 쓰기가 통과했다`,
  );
}

// ------------------------------------------------------------
// 로그인 상태 검사 (DEMO_PASSWORD 있을 때만)
// ------------------------------------------------------------
const email = env.DEMO_EMAIL ?? 'demo@vocalfit.test';
const password = env.DEMO_PASSWORD;

console.log('\n[로그인 상태에서 무엇이 보이는가]');

if (!password) {
  console.log(`  SKIP  .env.local 의 DEMO_PASSWORD 가 비어 있습니다.`);
  console.log(`        ${email} 계정 비밀번호를 넣으면 이 검사도 돌아갑니다.`);
} else {
  const auth = await signIn(email, password);

  if (auth.error) {
    record(`로그인 (${email})`, false, auth.error
      + '  — 계정이 없거나 비밀번호가 다릅니다. Authentication > Users 확인.');
  } else {
    record(`로그인 (${email})`, true, `uid ${auth.uid}`);
    const t = auth.token;

    // 내 데이터는 보여야 한다
    for (const table of ['recordings', 'analyses', 'key_results']) {
      const r = await api(`${table}?select=id`, { token: t });
      const n = rows(r);
      record(`로그인 → 내 ${table} 조회`, r.status === 200 && n > 0,
        r.status === 200
          ? `${n}행` + (n === 0 ? ' — 시드 데이터가 없다 (03_seed_demo_data.sql 실행 필요)' : '')
          : `HTTP ${r.status}: ${r.json?.message ?? r.text.slice(0, 80)}`);
    }

    // 프로필은 내 것 1개만
    {
      const r = await api('profiles?select=id,email', { token: t });
      const n = rows(r);
      record('로그인 → 프로필은 내 것만', r.status === 200 && n === 1,
        n === 1 ? `1행 (${r.json[0].email})` : `${n}행 — 1이 아니면 문제`);
    }

    // 곡 목록은 전부 보여야 한다
    {
      const r = await api('song_refs?select=id', { token: t });
      const n = rows(r);
      record('로그인 → 곡 목록 10개', n === 10, `${n}행 (기대 10)`);
    }

    // 남의 user_id 로 쓰기 시도 → 거부되어야 한다
    {
      const r = await api('recordings', {
        token: t,
        method: 'POST',
        body: {
          user_id: '00000000-0000-0000-0000-000000000099',
          file_path: 'hack/attack.webm',
          duration_sec: 30,
        },
        prefer: 'return=representation',
      });
      const blocked = r.status === 403 || r.json?.code === '42501';
      record('로그인 → 남의 user_id 로 쓰기 차단', blocked,
        blocked
          ? `HTTP ${r.status} — ${r.json?.message ?? 'RLS 가 거부'}`
          : `★ HTTP ${r.status} — 통과해 버렸다. recordings_insert_own 확인 필요`);
    }
  }
}

// ------------------------------------------------------------
const failed = results.filter((r) => !r.ok);
console.log('-'.repeat(56));
console.log(failed.length === 0
  ? `전부 통과 (${results.length}/${results.length})\n`
  : `실패 ${failed.length}건 / 전체 ${results.length}건\n`);
process.exit(failed.length === 0 ? 0 : 1);
