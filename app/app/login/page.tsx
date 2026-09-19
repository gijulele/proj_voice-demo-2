'use client';

import { createClient } from '@/lib/supabase/client';
import { useRouter } from 'next/navigation';
import { useState } from 'react';

export default function Login() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [message, setMessage] = useState('');
  const [busy, setBusy] = useState(false);
  const router = useRouter();

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setMessage('');
    setBusy(true);

    const supabase = createClient();
    const { error } = await supabase.auth.signInWithPassword({ email, password });

    if (error) {
      setMessage(`로그인 실패: ${error.message}`);
      setBusy(false);
      return;
    }

    // refresh() 로 서버 컴포넌트를 다시 그린다.
    // 이게 없으면 로그인은 됐는데 화면은 예전(비로그인) 상태로 남는다.
    router.push('/');
    router.refresh();
  };

  return (
    <main className="mx-auto max-w-md p-8">
      <h1 className="mb-4 text-2xl font-bold">로그인</h1>

      <form onSubmit={handleLogin} className="space-y-4">
        <input
          type="email" placeholder="이메일" required
          value={email} onChange={(e) => setEmail(e.target.value)}
          className="w-full rounded border p-2"
        />
        <input
          type="password" placeholder="비밀번호" required
          value={password} onChange={(e) => setPassword(e.target.value)}
          className="w-full rounded border p-2"
        />
        <button
          type="submit" disabled={busy}
          className="w-full rounded bg-black px-4 py-2 text-white disabled:opacity-50"
        >
          {busy ? '처리 중...' : '로그인'}
        </button>
      </form>

      {message && <p className="mt-4 text-sm">{message}</p>}

      <p className="mt-4 text-sm">
        계정이 없나요? <a href="/signup" className="underline">회원가입</a>
      </p>
    </main>
  );
}
