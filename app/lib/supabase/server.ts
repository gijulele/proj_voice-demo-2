import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';
import { readSupabaseEnv } from './env';

/**
 * 서버 컴포넌트 / 서버 액션에서 쓰는 Supabase 클라이언트.
 *
 * 브라우저가 보낸 쿠키에서 로그인 세션을 읽는다.
 * 그래서 서버에서도 auth.getUser() 가 실제 사용자를 돌려주고,
 * RLS 의 auth.uid() 가 동작한다.
 *
 * ※ 서버 컴포넌트에서는 쿠키를 쓸 수 없다(읽기만 된다).
 *   set 이 실패하는 건 정상이라 조용히 넘긴다. 세션 갱신은 미들웨어가 맡는다.
 */
export async function createClient() {
  const { url, anonKey } = readSupabaseEnv();
  const cookieStore = await cookies();

  return createServerClient(url, anonKey, {
    cookies: {
      getAll() {
        return cookieStore.getAll();
      },
      setAll(cookiesToSet) {
        try {
          cookiesToSet.forEach(({ name, value, options }) => {
            cookieStore.set(name, value, options);
          });
        } catch {
          // 서버 컴포넌트에서 호출된 경우. 미들웨어가 세션을 갱신하므로 무시해도 된다.
        }
      },
    },
  });
}
