-- ============================================================
-- vocalfit 시드 B — 데모용 사용자 데이터
-- (recordings / analyses / key_results 에 가짜 기록 채우기)
--
-- 목적: 결과 화면·기록 목록 UI를 녹음 없이 바로 개발/확인하기 위함.
--
-- ⚠️ 실행 전 준비
--    1) 02_seed_song_refs.sql 을 먼저 Run (song_refs 가 있어야 함)
--    2) Supabase Dashboard > Authentication > Users > "Add user" 로
--       테스트 계정을 만든다. 예: demo@vocalfit.test / 비밀번호 아무거나
--       ("Auto Confirm User" 체크할 것)
--    3) 아래 v_email 값을 그 계정 이메일과 똑같이 맞춘다
--
-- 여러 번 실행해도 중복 생성되지 않는다.
-- ============================================================

do $$
declare
  v_email        text := 'demo@vocalfit.test';   -- ← 만든 테스트 계정 이메일
  v_user_id      uuid;
  v_rec_id       uuid;
  v_analysis_id  uuid;
  v_song_id      uuid;
begin

  ------------------------------------------------------------
  -- 0. 테스트 계정 확인
  ------------------------------------------------------------
  select id into v_user_id from auth.users where email = v_email;

  if v_user_id is null then
    raise exception
      '테스트 계정(%)이 없습니다. Authentication > Users 에서 먼저 만들고 다시 실행하세요.',
      v_email;
  end if;

  -- 트리거가 이미 profiles 를 만들었겠지만, 혹시 없으면 보정
  insert into public.profiles (id, email, nickname)
  values (v_user_id, v_email, '데모유저')
  on conflict (id) do nothing;


  ------------------------------------------------------------
  -- 기록 1) 성공한 분석 — 밤편지, 음이 모자라서 키를 내려야 하는 경우
  --    사용자 안전최고음 F#4(66) vs 곡 최고음 D5(74) → 8키 내림
  ------------------------------------------------------------
  select id into v_song_id from public.song_refs where song_title = '밤편지';

  insert into public.recordings
    (user_id, song_title, file_path, duration_sec, sample_rate)
  select v_user_id, '밤편지', v_user_id || '/demo-seed-01.webm', 30.00, 48000
  where not exists (
    select 1 from public.recordings
    where user_id = v_user_id and file_path like '%demo-seed-01%'
  )
  returning id into v_rec_id;

  if v_rec_id is not null then
    insert into public.analyses
      (user_id, recording_id, status,
       low_note, low_midi, high_note, high_midi,
       safe_high_note, safe_high_midi, break_note, break_midi,
       confidence, f0_series_path)
    values
      (v_user_id, v_rec_id, 'done',
       'E2', 40, 'A4', 69,
       'F#4', 66, 'G4', 67,
       0.912, v_user_id || '/demo-seed-01.f0.json')
    returning id into v_analysis_id;

    insert into public.key_results
      (user_id, analysis_id, song_ref_id, recommended_key_shift, verdict)
    values (v_user_id, v_analysis_id, v_song_id, -8, 'hard');
  end if;


  ------------------------------------------------------------
  -- 기록 2) 성공한 분석 — 거짓말, 원키로 편하게 부를 수 있는 경우
  --    안전최고음 F#4(66) vs 곡 최고음 G4(67) → 1키만 내리면 편함
  ------------------------------------------------------------
  v_rec_id := null;
  select id into v_song_id from public.song_refs where song_title = '거짓말';

  insert into public.recordings
    (user_id, song_title, file_path, duration_sec, sample_rate)
  select v_user_id, '거짓말', v_user_id || '/demo-seed-02.webm', 29.40, 48000
  where not exists (
    select 1 from public.recordings
    where user_id = v_user_id and file_path like '%demo-seed-02%'
  )
  returning id into v_rec_id;

  if v_rec_id is not null then
    insert into public.analyses
      (user_id, recording_id, status,
       low_note, low_midi, high_note, high_midi,
       safe_high_note, safe_high_midi, break_note, break_midi,
       confidence, f0_series_path)
    values
      (v_user_id, v_rec_id, 'done',
       'F2', 41, 'A4', 69,
       'F#4', 66, 'G4', 67,
       0.874, v_user_id || '/demo-seed-02.f0.json')
    returning id into v_analysis_id;

    insert into public.key_results
      (user_id, analysis_id, song_ref_id, recommended_key_shift, verdict)
    values (v_user_id, v_analysis_id, v_song_id, -1, 'fit');
  end if;


  ------------------------------------------------------------
  -- 기록 3) 실패한 분석 — 에러 화면 UI 확인용
  ------------------------------------------------------------
  v_rec_id := null;

  insert into public.recordings
    (user_id, song_title, file_path, duration_sec, sample_rate)
  select v_user_id, '취중진담', v_user_id || '/demo-seed-03.webm', 4.20, 48000
  where not exists (
    select 1 from public.recordings
    where user_id = v_user_id and file_path like '%demo-seed-03%'
  )
  returning id into v_rec_id;

  if v_rec_id is not null then
    insert into public.analyses
      (user_id, recording_id, status, error_message)
    values
      (v_user_id, v_rec_id, 'failed',
       '유성음 구간이 너무 짧습니다. 30초 동안 가사를 이어서 불러주세요.');
  end if;


  ------------------------------------------------------------
  -- 기록 4) 분석 대기 중 — 로딩/폴링 화면 UI 확인용
  ------------------------------------------------------------
  v_rec_id := null;

  insert into public.recordings
    (user_id, song_title, file_path, duration_sec, sample_rate)
  select v_user_id, '소주 한 잔', v_user_id || '/demo-seed-04.webm', 30.00, 48000
  where not exists (
    select 1 from public.recordings
    where user_id = v_user_id and file_path like '%demo-seed-04%'
  )
  returning id into v_rec_id;

  if v_rec_id is not null then
    insert into public.analyses (user_id, recording_id, status)
    values (v_user_id, v_rec_id, 'processing');
  end if;


  raise notice '데모 시드 완료. user_id = %', v_user_id;
end $$;


-- ------------------------------------------------------------
-- 확인: 이 계정의 기록 목록 (결과 화면이 보여줄 형태)
-- ------------------------------------------------------------
select r.created_at,
       r.song_title,
       a.status,
       a.low_note  as 최저음,
       a.safe_high_note as 안전최고음,
       a.break_note as 무너지는지점,
       k.recommended_key_shift as 추천키,
       k.verdict,
       a.error_message
from public.recordings r
left join public.analyses    a on a.recording_id = r.id
left join public.key_results k on k.analysis_id  = a.id
where r.user_id = (select id from auth.users where email = 'demo@vocalfit.test')
order by r.created_at desc;


-- ------------------------------------------------------------
-- 데모 시드만 지우고 싶을 때 (song_refs 는 안 지움)
-- ------------------------------------------------------------
-- delete from public.recordings
--  where file_path like '%demo-seed-%';
--   → analyses, key_results 는 on delete cascade 로 같이 지워진다
-- ------------------------------------------------------------
