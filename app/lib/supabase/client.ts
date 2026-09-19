'use client';

import { createBrowserClient } from '@supabase/ssr';
import { readSupabaseEnv } from './env';

/**
 * 브라우저(클라이언트 컴포넌트)에서 쓰는 Supabase 클라이언트.
 *
 * 로그인 폼처럼 'use client' 가 붙은 파일에서 쓴다.
 * 로그인에 성공하면 세션을 쿠키에 저장하므로, 서버 컴포넌트도
 * 같은 로그인 상태를 읽을 수 있다. (이게 @supabase/ssr 을 쓰는 이유다)
 */
export function createClient() {
  const { url, anonKey } = readSupabaseEnv();
  return createBrowserClient(url, anonKey);
}
