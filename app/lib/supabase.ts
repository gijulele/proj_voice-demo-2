import { createClient } from '@supabase/supabase-js';

/**
 * 브라우저에서 쓰는 Supabase 클라이언트.
 *
 * anon key 는 브라우저에 그대로 노출된다. 그래도 되는 이유는
 * 이 키로 무엇을 할 수 있는지를 DB 의 RLS 정책이 결정하기 때문이다.
 * (supabase/04_rls_policies.sql 참고)
 *
 * 환경변수는 app/.env.local 에서 읽는다. 저장소 루트의 .env.local 이
 * 아니다 — Next.js 는 자기 프로젝트 루트만 본다.
 */

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

// 값이 비면 조용히 undefined 로 흘러가 엉뚱한 곳에서 터진다.
// 여기서 먼저, 무엇을 어디에 넣어야 하는지와 함께 멈춘다.
if (!url || !anonKey) {
  const missing = [
    !url && 'NEXT_PUBLIC_SUPABASE_URL',
    !anonKey && 'NEXT_PUBLIC_SUPABASE_ANON_KEY',
  ].filter(Boolean).join(', ');

  throw new Error(
    `Supabase 환경변수가 없습니다: ${missing}\n`
    + 'app/.env.local 에 값을 넣고 dev 서버를 다시 시작하세요.\n'
    + '(app/.env.example 을 복사해서 쓰면 됩니다. 저장소 루트가 아니라 app/ 안입니다.)',
  );
}

export const supabase = createClient(url, anonKey);
