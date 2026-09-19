-- ============================================================
-- vocalfit 시드 A — song_refs 프리셋 10곡
-- 01_schema.sql 실행 후 SQL Editor 에 붙여넣고 Run
--
-- ⚠️ 음역 숫자(ref_low/high)는 검증되지 않은 추정값이다.
--    웹에서 곡별 최고음 공개 데이터를 찾지 못했다.
--    데모 전에 곡을 직접 듣고 수정할 것. 안 고치면 추천 키가 틀린다.
--    수정 방법은 파일 맨 아래 주석 참고.
--
-- MIDI 참고:  C3=48  C4=60(가온다)  A4=69  C5=72
--            한국식 '2옥타브 라' = A4 = 69
-- ============================================================

insert into public.song_refs
  (song_title, artist, ref_low_note, ref_low_midi, ref_high_note, ref_high_midi, source)
values
  -- 남성 중음 (최고음 2옥 솔~라)
  ('모든 날, 모든 순간',  '폴킴',   'G2', 43, 'G4', 67, 'manual_seed_unverified'),
  ('거짓말',             '빅뱅',   'B2', 47, 'G4', 67, 'manual_seed_unverified'),
  ('나였으면',           '적재',   'B2', 47, 'A4', 69, 'manual_seed_unverified'),
  ('취중진담',           '김동률', 'A2', 45, 'A4', 69, 'manual_seed_unverified'),
  ('너를 사랑하고 있어',  '전상근', 'C3', 48, 'A4', 69, 'manual_seed_unverified'),

  -- 남성 고음 (최고음 2옥 시~3옥 도)
  ('소주 한 잔',         '임창정', 'A2', 45, 'B4', 71, 'manual_seed_unverified'),
  ('사랑은 늘 도망가',    '임영웅', 'G2', 43, 'B4', 71, 'manual_seed_unverified'),
  ('말리꽃',             '이승철', 'C3', 48, 'C5', 72, 'manual_seed_unverified'),

  -- 여성
  ('밤편지',             '아이유', 'F3', 53, 'D5', 74, 'manual_seed_unverified'),
  ('좋은 날',            '아이유', 'G3', 55, 'F5', 77, 'manual_seed_unverified')

on conflict (lower(song_title), lower(artist)) do nothing;


-- 확인
select song_title, artist,
       ref_low_note  || ' (' || ref_low_midi  || ')' as 최저음,
       ref_high_note || ' (' || ref_high_midi || ')' as 최고음,
       ref_high_midi - ref_low_midi as 음역폭_반음
from public.song_refs
order by ref_high_midi;


-- ------------------------------------------------------------
-- 값 수정하는 법 (곡을 듣고 실제 음을 확인한 뒤)
-- ------------------------------------------------------------
-- update public.song_refs
--    set ref_high_note = 'A4', ref_high_midi = 69,
--        source = 'manual_verified'
--  where song_title = '밤편지';
--
-- 음이름 → MIDI 변환:  midi = (옥타브 + 1) * 12 + 음계offset
--   C=0 C#=1 D=2 D#=3 E=4 F=5 F#=6 G=7 G#=8 A=9 A#=10 B=11
--   예) A4 = (4+1)*12 + 9 = 69
--
-- 한국식 옥타브 표기 → 국제 표기:
--   1옥타브 도 = C3(48) / 2옥타브 도 = C4(60) / 3옥타브 도 = C5(72)
--   흔히 말하는 "3옥타브 라"는 A5(81) 가 아니라 A4(69) 인 경우가 많으니 주의
-- ------------------------------------------------------------
