/**
 * 환경변수 읽기 — 브라우저용/서버용 클라이언트가 공유한다.
 *
 * 값이 비면 조용히 undefined 로 흘러가 엉뚱한 곳에서 터진다.
 * 여기서 먼저, 무엇을 어디에 넣어야 하는지와 함께 멈춘다.
 */
export function readSupabaseEnv() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

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

  return { url, anonKey };
}
