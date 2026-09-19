/**
 * ⚠️ 이 파일은 더 이상 쓰지 않는다.
 *
 * 로그인(Auth)을 붙이면서 클라이언트가 둘로 나뉘었다.
 * 세션을 쿠키에 저장해야 서버 컴포넌트도 로그인 상태를 읽을 수 있기 때문이다.
 *
 *   클라이언트 컴포넌트('use client')  →  import { createClient } from '@/lib/supabase/client'
 *   서버 컴포넌트 / 서버 액션          →  import { createClient } from '@/lib/supabase/server'
 *
 * 둘 다 함수다. 쓰기 전에 호출해야 한다.
 *
 *   const supabase = createClient();        // 브라우저
 *   const supabase = await createClient();  // 서버 (await 필요)
 */

export function supabaseDeprecated(): never {
  throw new Error(
    "'@/lib/supabase' 는 더 이상 쓰지 않습니다.\n"
    + "브라우저: import { createClient } from '@/lib/supabase/client'\n"
    + "서버:     import { createClient } from '@/lib/supabase/server'",
  );
}
