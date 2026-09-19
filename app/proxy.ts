import { createServerClient } from '@supabase/ssr';
import { NextResponse, type NextRequest } from 'next/server';
import { readSupabaseEnv } from '@/lib/supabase/env';

/**
 * 로그인 세션 갱신 — 모든 요청 앞단에서 실행된다.
 *
 * ※ 이 프로젝트의 Next.js(16) 에서는 파일명이 proxy.ts 다.
 *   인터넷 예제와 해커톤 자료는 대부분 middleware.ts 로 되어 있는데,
 *   그 이름은 deprecated 라 경고가 뜬다. 내용은 같다.
 *
 * 왜 필요한가:
 *   Supabase 세션은 시간이 지나면 만료된다. 서버 컴포넌트는 쿠키를 쓸 수 없어
 *   스스로 갱신하지 못하므로 여기서 대신 갱신한다.
 *   이게 없으면 한참 뒤 새로고침했을 때 갑자기 로그아웃된 것처럼 보인다.
 */
export async function proxy(request: NextRequest) {
  let response = NextResponse.next({ request });

  const { url, anonKey } = readSupabaseEnv();

  const supabase = createServerClient(url, anonKey, {
    cookies: {
      getAll() {
        return request.cookies.getAll();
      },
      setAll(cookiesToSet) {
        cookiesToSet.forEach(({ name, value }) => {
          request.cookies.set(name, value);
        });
        response = NextResponse.next({ request });
        cookiesToSet.forEach(({ name, value, options }) => {
          response.cookies.set(name, value, options);
        });
      },
    },
  });

  // 이 호출이 세션을 갱신한다. 결과는 쓰지 않아도 된다.
  await supabase.auth.getUser();

  return response;
}

export const config = {
  matcher: [
    // 정적 파일과 이미지 요청은 건너뛴다 (불필요한 갱신 방지)
    '/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)',
  ],
};
