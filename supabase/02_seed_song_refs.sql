-- ============================================================
-- vocalfit — song_refs 프리셋 시드 (10곡)
-- 01_schema.sql 실행 후 SQL Editor 에서 Run
--
-- ⚠️ ref_high/low 값은 임시 placeholder 다. 실제 서비스 전에
--    원곡을 듣고 수동 검증해서 정확한 값으로 교체할 것.
--    (spec: "프리셋 10곡의 최고음/최저음을 수동 입력")
--
-- MIDI 번호 참고: C3=48, C4=60(가온다), A4=69, C5=72
-- ============================================================

insert into public.song_refs
  (song_title, artist, ref_low_note, ref_low_midi, ref_high_note, ref_high_midi, source)
values
  ('밤편지',          '아이유',     'F3',  53, 'D5',  74, 'manual_seed'),
  ('좋은 날',         '아이유',     'G3',  55, 'F5',  77, 'manual_seed'),
  ('사랑은 늘 도망가', '임영웅',     'A2',  45, 'A4',  69, 'manual_seed'),
  ('취중진담',        '김동률',     'A2',  45, 'A4',  69, 'manual_seed'),
  ('너를 사랑하고 있어','전상근',     'C3',  48, 'A4',  69, 'manual_seed'),
  ('모든 날, 모든 순간','폴킴',      'A2',  45, 'G4',  67, 'manual_seed'),
  ('말리꽃',          '이승철',     'C3',  48, 'C5',  72, 'manual_seed'),
  ('거짓말',          '빅뱅',       'B2',  47, 'G4',  67, 'manual_seed'),
  ('나였으면',        '적재',       'B2',  47, 'A4',  69, 'manual_seed'),
  ('소주 한 잔',      '임창정',     'A2',  45, 'A4',  69, 'manual_seed')
on conflict (lower(song_title), lower(artist)) do nothing;

-- 확인
select song_title, artist, ref_low_note, ref_high_note,
       ref_high_midi - ref_low_midi as semitone_range
from public.song_refs
order by song_title;
