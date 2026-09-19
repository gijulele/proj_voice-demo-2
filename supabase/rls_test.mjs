// ============================================================
// supabase/rls_test.mjs — RLS 동작을 터미널에서 검증한다
//
// 05_rls_test.sql 과 같은 내용을 Node 로 실행해서
// 사람이 눈으로 대조하는 대신 PASS / FAIL 로 판정한다.
//
// 실행:  node supabase/rls_test.mjs
// 종료코드: 0 = 전부 통과, 1 = 하나라도 실패 (CI 에 그대로 쓸 수 있다)
//
// 접속정보는 저장소 루트 .env.local 의 DATABASE_URL 에서 읽는다.
// (.env* 는 .gitignore 에 있으므로 커밋되지 않는다)
// ============================================================

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import pg from 'pg';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const DEMO_EMAIL = process.env.DEMO_EMAIL ?? 'demo@vocalfit.test';
const STRANGER = '00000000-0000-0000-0000-000000000099';

// ------------------------------------------------------------
// .env.local 에서 DATABASE_URL 읽기
// ------------------------------------------------------------
function loadDatabaseUrl() {
  if (process.env.DATABASE_URL) return process.env.DATABASE_URL;

  for (const name of ['.env.local', '.env']) {
    try {
      const text = readFileSync(join(ROOT, name), 'utf8');
      for (const line of text.split(/\r?\n/)) {
        const m = line.match(/^\s*(?:export\s+)?DATABASE_URL\s*=\s*(.*)$/);
        if (m) return m[1].trim().replace(/^["']|["']$/g, '');
      }
    } catch {
      /* 파일 없음 — 다음 후보로 */
    }
  }
  return null;
}

// ------------------------------------------------------------
// 결과 수집
// ------------------------------------------------------------
const results = [];
function record(name, ok, detail) {
  results.push({ name, ok, detail });
  const mark = ok ? '  PASS' : '  FAIL';
  console.log(`${mark}  ${name}`);
  if (detail) console.log(`        ${detail}`);
}

// 로그인 상태 흉내내기.
//   순서가 중요하다: set_config 를 postgres 권한으로 "먼저" 실행하고
//   그 다음에 역할을 바꾼다. 반대로 하면 auth.users 권한 에러가 난다.
async function becomeUser(client, uid) {
  const claims = JSON.stringify({ sub: uid, role: 'authenticated' });
  await client.query('select set_config($1, $2, true)', ['request.jwt.claims', claims]);
  await client.query('set local role authenticated');
}

async function becomeAnon(client) {
  await client.query('select set_config($1, null, true)', ['request.jwt.claims']);
  await client.query('set local role anon');
}

const counts = `
  select
    (select count(*)::int from public.recordings)  as recordings,
    (select count(*)::int from public.analyses)    as analyses,
    (select count(*)::int from public.key_results) as key_results,
    (select count(*)::int from public.profiles)    as profiles,
    (select count(*)::int from public.song_refs)   as song_refs,
    auth.uid()::text                               as uid
`;

// ------------------------------------------------------------
// 테스트 0. 정책이 붙어 있는가 / RLS 스위치가 켜져 있는가
// ------------------------------------------------------------
async function test0(client) {
  const expected = {
    profiles: 2, recordings: 3, analyses: 2, key_results: 2, song_refs: 1,
  };

  const { rows: pol } = await client.query(`
    select tablename, count(*)::int as n
    from pg_policies where schemaname = 'public'
    group by tablename order by tablename
  `);
  const actual = Object.fromEntries(pol.map((r) => [r.tablename, r.n]));

  const wrong = Object.entries(expected)
    .filter(([t, n]) => actual[t] !== n)
    .map(([t, n]) => `${t}: 기대 ${n} / 실제 ${actual[t] ?? 0}`);

  record(
    '0a. 정책 개수',
    wrong.length === 0,
    wrong.length ? wrong.join(', ') : `총 ${pol.reduce((s, r) => s + r.n, 0)}개`,
  );

  const { rows: rls } = await client.query(`
    select relname, relrowsecurity as on
    from pg_class
    where relnamespace = 'public'::regnamespace and relkind = 'r'
      and relname in ('profiles','recordings','analyses','key_results','song_refs')
    order by relname
  `);
  const off = rls.filter((r) => !r.on).map((r) => r.relname);
  record(
    '0b. RLS 스위치',
    rls.length === 5 && off.length === 0,
    off.length ? `꺼져 있음: ${off.join(', ')}` : '5개 테이블 모두 ON',
  );
}

// ------------------------------------------------------------
// 테스트 1. 로그인한 "나" — 내 데이터가 보여야 한다
// ------------------------------------------------------------
async function test1(client, demoUid) {
  await client.query('begin');
  try {
    await becomeUser(client, demoUid);
    const { rows: [r] } = await client.query(counts);

    const ok = r.uid === demoUid
      && r.recordings > 0 && r.analyses > 0 && r.key_results > 0
      && r.profiles === 1 && r.song_refs === 10;

    record(
      '1. 로그인한 나 — 내 데이터가 보인다',
      ok,
      `녹음 ${r.recordings}, 분석 ${r.analyses}, 키추천 ${r.key_results}, `
      + `프로필 ${r.profiles}(기대 1), 곡 ${r.song_refs}(기대 10)`,
    );
  } finally {
    await client.query('rollback');
  }
}

// ------------------------------------------------------------
// 테스트 2. 로그인한 "남" — 내 데이터가 하나도 안 보여야 한다
// ------------------------------------------------------------
async function test2(client) {
  await client.query('begin');
  try {
    await becomeUser(client, STRANGER);
    const { rows: [r] } = await client.query(counts);

    const leaked = ['recordings', 'analyses', 'key_results', 'profiles']
      .filter((k) => r[k] !== 0);

    record(
      '2. 로그인한 남 — 남의 데이터가 안 보인다',
      leaked.length === 0 && r.song_refs === 10,
      leaked.length
        ? `★ 새고 있다: ${leaked.map((k) => `${k}=${r[k]}`).join(', ')}`
        : `개인 데이터 0, 공용 곡 ${r.song_refs}개만 보임`,
    );
  } finally {
    await client.query('rollback');
  }
}

// ------------------------------------------------------------
// 테스트 3. 남의 이름으로 INSERT — 거부되어야 한다
// ------------------------------------------------------------
async function test3(client, demoUid) {
  await client.query('begin');
  try {
    await becomeUser(client, STRANGER);
    await client.query(
      `insert into public.recordings (user_id, file_path, duration_sec)
       values ($1, 'hack/attack.webm', 30)`,
      [demoUid],
    );
    record('3. 남의 user_id 로 INSERT — 차단', false,
      '★ 통과해 버렸다. recordings_insert_own 의 with check 를 확인할 것.');
  } catch (err) {
    // 42501 = insufficient_privilege — RLS 가 막았을 때 나오는 코드
    const blocked = err.code === '42501';
    record('3. 남의 user_id 로 INSERT — 차단', blocked,
      blocked ? err.message : `RLS 아닌 다른 에러(${err.code}): ${err.message}`);
  } finally {
    await client.query('rollback');
  }
}

// ------------------------------------------------------------
// 테스트 4. 비로그인(anon) — 아무것도 못 봐야 한다
// ------------------------------------------------------------
async function test4(client) {
  await client.query('begin');
  try {
    await becomeAnon(client);
    const { rows: [r] } = await client.query(`
      select
        (select count(*)::int from public.recordings) as recordings,
        (select count(*)::int from public.profiles)   as profiles,
        (select count(*)::int from public.song_refs)  as song_refs
    `);
    const ok = r.recordings === 0 && r.profiles === 0 && r.song_refs === 0;
    record(
      '4. 비로그인(anon) — 아무것도 안 보인다',
      ok,
      `녹음 ${r.recordings}, 프로필 ${r.profiles}, 곡 ${r.song_refs}`
      + (r.song_refs > 0
        ? '  (곡이 보이면 song_refs 정책이 anon 에게도 열려 있는 것 — 의도했다면 정상)'
        : ''),
    );
  } finally {
    await client.query('rollback');
  }
}

// ------------------------------------------------------------
// main
// ------------------------------------------------------------
const url = loadDatabaseUrl();
if (!url) {
  console.error(`
DATABASE_URL 이 없습니다.

  1) Supabase 대시보드 > Project Settings > Database
     > Connection string > URI 를 복사 (Session pooler 권장)
  2) ${join(ROOT, '.env.local')} 파일에 아래 한 줄로 저장

     DATABASE_URL=postgresql://postgres.xxxx:비밀번호@...pooler.supabase.com:5432/postgres

  (.env* 는 .gitignore 에 있어 커밋되지 않습니다)
`);
  process.exit(2);
}

const client = new pg.Client({
  connectionString: url,
  ssl: { rejectUnauthorized: false },
});

try {
  await client.connect();
} catch (err) {
  console.error(`\n접속 실패: ${err.message}\n`);
  console.error('비밀번호에 @ : / 같은 특수문자가 있으면 URL 인코딩이 필요합니다.');
  console.error('IPv6 오류라면 Direct connection 대신 Session pooler URI 를 쓰세요.\n');
  process.exit(2);
}

console.log(`\nRLS 검증 — ${DEMO_EMAIL}\n${'-'.repeat(52)}`);

try {
  const { rows } = await client.query(
    'select id from auth.users where email = $1', [DEMO_EMAIL],
  );
  const demoUid = rows[0]?.id;

  await test0(client);

  if (!demoUid) {
    console.log(`\n  SKIP  테스트 1~3 — ${DEMO_EMAIL} 계정이 없습니다.`);
    console.log('        Authentication > Users 에서 만들고 03_seed_demo_data.sql 을 Run 하세요.');
  } else {
    await test1(client, demoUid);
    await test2(client);
    await test3(client, demoUid);
  }

  await test4(client);
} finally {
  await client.end();
}

const failed = results.filter((r) => !r.ok);
console.log('-'.repeat(52));
console.log(
  failed.length === 0
    ? `전부 통과 (${results.length}/${results.length})\n`
    : `실패 ${failed.length}건 / 전체 ${results.length}건\n`,
);
process.exit(failed.length === 0 ? 0 : 1);
