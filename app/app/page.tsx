import { supabase } from '@/lib/supabase';

// 서버 컴포넌트다. 이 함수는 브라우저가 아니라 서버에서 실행되고,
// 완성된 HTML 만 브라우저로 간다. 그래서 async/await 를 바로 쓸 수 있다.
export default async function Home() {
  // song_refs 는 공용 데이터라 로그인 없이 읽힌다.
  // (recordings 같은 개인 테이블은 같은 방식으로 조회하면 0행이 나온다 — RLS 때문이고, 정상이다)
  const { data: songs, error } = await supabase
    .from('song_refs')
    .select('*')
    .order('ref_high_midi');

  if (error) {
    return (
      <main className="p-8">
        <h1 className="mb-4 text-2xl font-bold">곡 목록</h1>
        <p className="text-red-600">불러오지 못했습니다: {error.message}</p>
      </main>
    );
  }

  return (
    <main className="p-8">
      <h1 className="mb-1 text-2xl font-bold">곡 목록</h1>
      <p className="mb-6 text-sm text-zinc-500">
        Supabase song_refs 테이블 · {songs?.length ?? 0}곡
      </p>

      <ul className="space-y-2">
        {songs?.map((song) => (
          <li key={song.id} className="border-b border-zinc-200 pb-2">
            <strong>{song.song_title}</strong>
            <span className="text-zinc-500"> — {song.artist}</span>
            <span className="ml-2 text-sm text-zinc-400">
              {song.ref_low_note} ~ {song.ref_high_note}
            </span>
          </li>
        ))}
      </ul>
    </main>
  );
}
