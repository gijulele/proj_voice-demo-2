'use client';

import { createClient } from '@/lib/supabase/client';
import { useRouter } from 'next/navigation';
import { useState } from 'react';

export default function SignUp() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [nickname, setNickname] = useState('');
  const [message, setMessage] = useState('');
  const [busy, setBusy] = useState(false);
  const router = useRouter();

  const handleSignUp = async (e: React.FormEvent) => {
    e.preventDefault();
    setMessage('');
    setBusy(true);

    const supabase = createClient();
    const { error } = await supabase.auth.signUp({
      email,
      password,
      // 여기 넘긴 nickname 을 handle_new_user() 트리거가 받아서
      // profiles 행을 자동으로 만든다. (supabase/00_all_in_one.sql 참고)
      options: { data: { nickname } },
    });

    if (error) {
      setMessage(`오류: ${error.message}`);
      setBusy(false);
      return;
    }

    setMessage('가입 완료. 로그인 페이지로 이동합니다.');
    setTimeout(() => router.push('/login'), 1000);
  };

  return (
    <main className="mx-auto max-w-md p-8">
      <h1 className="mb-4 text-2xl font-bold">회원가입</h1>

      <form onSubmit={handleSignUp} className="space-y-4">
        <input
          type="email" placeholder="이메일" required
          value={email} onChange={(e) => setEmail(e.target.value)}
          className="w-full rounded border p-2"
        />
        <input
          type="text" placeholder="닉네임" required
          value={nickname} onChange={(e) => setNickname(e.target.value)}
          className="w-full rounded border p-2"
        />
        <input
          type="password" placeholder="비밀번호 (6자 이상)" required minLength={6}
          value={password} onChange={(e) => setPassword(e.target.value)}
          className="w-full rounded border p-2"
        />
        <button
          type="submit" disabled={busy}
          className="w-full rounded bg-black px-4 py-2 text-white disabled:opacity-50"
        >
          {busy ? '처리 중...' : '가입하기'}
        </button>
      </form>

      {message && <p className="mt-4 text-sm">{message}</p>}

      <p className="mt-4 text-sm">
        이미 계정이 있나요? <a href="/login" className="underline">로그인</a>
      </p>
    </main>
  );
}
