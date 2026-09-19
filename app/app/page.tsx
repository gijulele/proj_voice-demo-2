import { createClient } from '@/lib/supabase/server';
import Link from 'next/link';
import LogoutButton from './logout-button';

export default async function Home() {
  const supabase = await createClient();

  // 쿠키에서 로그인 세션을 읽는다. 비로그인이면 user 가 null 이다.
  const { data: { user } } = await supabase.auth.getUser();

  // song_refs 는 공용 데이터라 로그인 없이도 보인다.
  const { data: songs } = await supabase
    .from('song_refs')
    .select('*')
    .order('ref_high_midi');

  // 개인 데이터. RLS 의 auth.uid() = user_id 가 걸려 있어서
  // 로그인해야 내 것만 나오고, 비로그인이면 0행이다.
  const { data: recordings } = await supabase
    .from('recordings')
    .select('id, file_path, duration_sec, created_at')
    .order('created_at', { ascending: false });

  return (
    <main className="mx-auto max-w-2xl p-8">
      <div className="mb-6 flex items-center justify-between">
        <h1 className="text-2xl font-bold">vocalfit</h1>

        {user ? (
          <div className="flex items-center gap-3">
            <span className="text-sm text-zinc-600">{user.email}</span>
            <LogoutButton />
          </div>
        ) : (
          <div className="flex items-center gap-3 text-sm">
            <Link href="/login" className="underline">로그인</Link>
            <Link href="/signup" className="underline">회원가입</Link>
          </div>
        )}
      </div>

      {/* 로그인한 사람에게만 보이는 영역 — RLS 가 실제로 동작하는 증거 */}
      {user && (
        <section className="mb-8 rounded border border-zinc-200 p-4">
          <h2 className="mb-2 font-semibold">내 녹음</h2>
          {recordings && recordings.length > 0 ? (
            <ul className="space-y-1 text-sm">
              {recordings.map((r) => (
                <li key={r.id} className="text-zinc-700">
                  {r.file_path}
                  <span className="ml-2 text-zinc-400">{r.duration_sec}초</span>
                </li>
              ))}
            </ul>
          ) : (
            <p className="text-sm text-zinc-500">아직 녹음이 없습니다.</p>
          )}
        </section>
      )}

      <h2 className="mb-1 font-semibold">곡 목록</h2>
      <p className="mb-4 text-sm text-zinc-500">
        song_refs · {songs?.length ?? 0}곡
      </p>

      {songs && songs.length > 0 ? (
        <ul className="space-y-2">
          {songs.map((song) => (
            <li key={song.id} className="border-b border-zinc-200 pb-2">
              <strong>{song.song_title}</strong>
              <span className="text-zinc-500"> — {song.artist}</span>
              <span className="ml-2 text-sm text-zinc-400">
                {song.ref_low_note} ~ {song.ref_high_note}
              </span>
            </li>
          ))}
        </ul>
      ) : (
        <p>곡이 없습니다.</p>
      )}
    </main>
  );
}
