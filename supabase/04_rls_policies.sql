-- ============================================================
-- 04_rls_policies.sql — RLS 정책만 다시 적용 (proj_voice_demo)
--
-- 이 파일은 00_all_in_one.sql 안의 "RLS" 부분과 100% 같은 내용이다.
-- 정책 이름·형태를 일부러 똑같이 맞춰 놓았다. 정답지는 하나여야 한다.
--
-- 언제 쓰나
--   - 테이블은 그대로 두고 정책만 초기화하고 싶을 때
--   - 대시보드에서 정책을 손으로 건드려서 원상복구하고 싶을 때
--   - 00_all_in_one.sql 을 이미 Run 했다면 실행할 필요 없다 (실행해도 무해)
--
-- 여러 번 실행해도 안전하다 (drop if exists → create).
-- 실행 후 05_rls_test.sql 로 "실제로 막히는지" 확인할 것.
-- ============================================================

-- ------------------------------------------------------------
-- 1) RLS 스위치 켜기
-- ------------------------------------------------------------
alter table public.profiles    enable row level security;
alter table public.recordings  enable row level security;
alter table public.analyses    enable row level security;
alter table public.key_results enable row level security;
alter table public.song_refs   enable row level security;

-- ------------------------------------------------------------
-- 2) 예전에 쓰던 한글 이름 정책이 남아 있으면 제거
--    (이 파일의 옛 버전이 만들던 "FOR ALL" 정책들)
-- ------------------------------------------------------------
drop policy if exists "누구나 읽기 가능" on public.song_refs;
drop policy if exists "내 프로필만"     on public.profiles;
drop policy if exists "내 녹음만"       on public.recordings;
drop policy if exists "내 분석만"       on public.analyses;
drop policy if exists "내 키추천만"     on public.key_results;

-- ------------------------------------------------------------
-- 3) 정책 생성 — 00_all_in_one.sql 과 동일
--    동작(select/insert/update/delete)별로 쪼갠 이유:
--    "읽기는 되는데 쓰기가 안 된다" 같은 상황을 정확히 표현하기 위해서다.
-- ------------------------------------------------------------

-- profiles : PK 가 곧 auth.users(id) 라서 user_id 가 아니라 id 를 비교한다
drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own" on public.profiles
  for select using (auth.uid() = id);

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own" on public.profiles
  for update using (auth.uid() = id) with check (auth.uid() = id);
-- profiles 에 insert 정책이 없는 건 의도적이다.
-- 가입 시 handle_new_user() 트리거(security definer)가 대신 만든다.

-- recordings
drop policy if exists "recordings_select_own" on public.recordings;
create policy "recordings_select_own" on public.recordings
  for select using (auth.uid() = user_id);

drop policy if exists "recordings_insert_own" on public.recordings;
create policy "recordings_insert_own" on public.recordings
  for insert with check (auth.uid() = user_id);

drop policy if exists "recordings_delete_own" on public.recordings;
create policy "recordings_delete_own" on public.recordings
  for delete using (auth.uid() = user_id);

-- analyses
--   analyses 에 user_id 를 중복해서 넣은 이유가 여기서 드러난다:
--   recordings 를 조인해서 타고 갈 필요 없이 한 줄로 끝난다.
drop policy if exists "analyses_select_own" on public.analyses;
create policy "analyses_select_own" on public.analyses
  for select using (auth.uid() = user_id);

drop policy if exists "analyses_insert_own" on public.analyses;
create policy "analyses_insert_own" on public.analyses
  for insert with check (auth.uid() = user_id);

-- key_results
drop policy if exists "key_results_select_own" on public.key_results;
create policy "key_results_select_own" on public.key_results
  for select using (auth.uid() = user_id);

drop policy if exists "key_results_insert_own" on public.key_results;
create policy "key_results_insert_own" on public.key_results
  for insert with check (auth.uid() = user_id);

-- song_refs : 공용 프리셋 곡 목록 (user_id 없음)
--   읽기는 누구나(비로그인 포함). 곡 추가·수정은 service_role(서버)만.
--   ※ 로그인 전 랜딩 화면에서도 곡 목록을 보여주기 위해 anon 을 포함한다.
--     로그인한 사람만 보게 하려면 to authenticated 로 바꾼다.
drop policy if exists "song_refs_select_all" on public.song_refs;
create policy "song_refs_select_all" on public.song_refs
  for select to anon, authenticated using (true);

-- ------------------------------------------------------------
-- 4) 확인 — 정책이 붙었는지 바로 보인다
--    기대: profiles 2, recordings 3, analyses 2, key_results 2, song_refs 1
-- ------------------------------------------------------------
select tablename, policyname, cmd
from pg_policies
where schemaname = 'public'
order by tablename, cmd, policyname;
