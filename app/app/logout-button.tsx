'use client';

import { createClient } from '@/lib/supabase/client';
import { useRouter } from 'next/navigation';
import { useState } from 'react';

/** 로그아웃 버튼. 서버 컴포넌트인 page.tsx 안에 끼워 넣어 쓴다. */
export default function LogoutButton() {
  const [busy, setBusy] = useState(false);
  const router = useRouter();

  const handleLogout = async () => {
    setBusy(true);
    const supabase = createClient();
    await supabase.auth.signOut();
    router.push('/');
    router.refresh();
  };

  return (
    <button
      onClick={handleLogout}
      disabled={busy}
      className="text-sm text-zinc-500 underline disabled:opacity-50"
    >
      {busy ? '...' : '로그아웃'}
    </button>
  );
}
