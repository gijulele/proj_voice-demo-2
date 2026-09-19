-- ============================================================
-- vocalfit — 통합 실행본 (스키마 + 시드)
-- 이 파일 하나만 SQL Editor 에 붙여넣고 Run 하면 끝난다.
--
-- 여러 번 실행해도 안전하다 (if not exists / on conflict do nothing).
--
-- ⚠️ 주의: 다른 곳에서 복사한 CREATE TABLE 조각을 이 아래에 덧붙이지 말 것.
--    특히 아래 형태의 profiles 는 이 스키마와 충돌한다 (42P07 에러의 원인):
--      CREATE TABLE public.profiles (
--        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
--        user_id UUID REFERENCES auth.users(id), ... );
--    이 스키마에서 profiles.id 는 곧 auth.users.id 다. user_id 컬럼은 없다.
--    그래야 RLS 의 auth.uid() = id 가 성립한다.
-- ============================================================


-- ============================================================
-- PART 1. 스키마
-- ============================================================

create extension if not exists "pgcrypto";

-- ------------------------------------------------------------
-- profiles  (spec 의 users 역할)
--   이메일/비밀번호/세션은 auth.users 가 관리한다.
--   여기엔 닉네임 등 부가 정보만 둔다.
-- ------------------------------------------------------------
create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  email       text not null,
  nickname    text not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create unique index if not exists profiles_nickname_key
  on public.profiles (lower(nickname));

-- ------------------------------------------------------------
-- song_refs  (프리셋 곡, 사용자 데이터 아님 → user_id 없음)
-- ------------------------------------------------------------
create table if not exists public.song_refs (
  id            uuid primary key default gen_random_uuid(),
  song_title    text not null,
  artist        text not null,
  ref_high_note text not null,
  ref_low_note  text not null,
  ref_high_midi smallint not null,
  ref_low_midi  smallint not null,
  source        text not null default 'manual_seed',
  created_at    timestamptz not null default now(),
  constraint song_refs_range_chk check (ref_low_midi < ref_high_midi)
);

create unique index if not exists song_refs_title_artist_key
  on public.song_refs (lower(song_title), lower(artist));

-- ------------------------------------------------------------
-- recordings
-- ------------------------------------------------------------
create table if not exists public.recordings (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles(id) on delete cascade,
  song_title   text not null,
  file_path    text not null,
  duration_sec numeric(6,2),
  sample_rate  integer,
  created_at   timestamptz not null default now(),
  constraint recordings_duration_chk check (duration_sec is null or duration_sec > 0)
);

create index if not exists recordings_user_created_idx
  on public.recordings (user_id, created_at desc);

-- ------------------------------------------------------------
-- analyses
-- ------------------------------------------------------------
do $$ begin
  create type public.analysis_status as enum ('pending','processing','done','failed');
exception when duplicate_object then null; end $$;

create table if not exists public.analyses (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references public.profiles(id) on delete cascade,
  recording_id    uuid not null references public.recordings(id) on delete cascade,
  status          public.analysis_status not null default 'pending',
  low_note        text,
  high_note       text,
  safe_high_note  text,
  break_note      text,
  low_midi        smallint,
  high_midi       smallint,
  safe_high_midi  smallint,
  break_midi      smallint,
  confidence      numeric(4,3),
  f0_series_path  text,
  error_message   text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint analyses_confidence_chk
    check (confidence is null or (confidence >= 0 and confidence <= 1))
);

create unique index if not exists analyses_recording_key
  on public.analyses (recording_id);
create index if not exists analyses_user_created_idx
  on public.analyses (user_id, created_at desc);
create index if not exists analyses_status_idx
  on public.analyses (status) where status in ('pending','processing');

-- ------------------------------------------------------------
-- key_results
-- ------------------------------------------------------------
do $$ begin
  create type public.key_verdict as enum ('easy','fit','hard','impossible');
exception when duplicate_object then null; end $$;

create table if not exists public.key_results (
  id                    uuid primary key default gen_random_uuid(),
  user_id               uuid not null references public.profiles(id) on delete cascade,
  analysis_id           uuid not null references public.analyses(id) on delete cascade,
  song_ref_id           uuid not null references public.song_refs(id) on delete restrict,
  recommended_key_shift smallint not null,
  verdict               public.key_verdict not null,
  created_at            timestamptz not null default now(),
  constraint key_results_shift_chk check (recommended_key_shift between -12 and 12)
);

create unique index if not exists key_results_analysis_song_key
  on public.key_results (analysis_id, song_ref_id);
create index if not exists key_results_user_created_idx
  on public.key_results (user_id, created_at desc);

-- ------------------------------------------------------------
-- updated_at 자동 갱신
-- ------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

drop trigger if exists analyses_set_updated_at on public.analyses;
create trigger analyses_set_updated_at
  before update on public.analyses
  for each row execute function public.set_updated_at();

-- ------------------------------------------------------------
-- 회원가입 시 profiles 자동 생성
--   signUp({ options: { data: { nickname } } }) 로 넘긴 닉네임을 받는다.
--   닉네임이 비면 이메일 앞부분을 쓴다.
-- ------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer
set search_path = public as $$
begin
  insert into public.profiles (id, email, nickname)
  values (
    new.id,
    new.email,
    coalesce(nullif(new.raw_user_meta_data ->> 'nickname',''),
             split_part(new.email,'@',1))
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ------------------------------------------------------------
-- RLS — 본인 데이터만
-- ------------------------------------------------------------
alter table public.profiles    enable row level security;
alter table public.recordings  enable row level security;
alter table public.analyses    enable row level security;
alter table public.key_results enable row level security;
alter table public.song_refs   enable row level security;

drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own" on public.profiles
  for select using (auth.uid() = id);

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own" on public.profiles
  for update using (auth.uid() = id) with check (auth.uid() = id);

drop policy if exists "recordings_select_own" on public.recordings;
create policy "recordings_select_own" on public.recordings
  for select using (auth.uid() = user_id);

drop policy if exists "recordings_insert_own" on public.recordings;
create policy "recordings_insert_own" on public.recordings
  for insert with check (auth.uid() = user_id);

drop policy if exists "recordings_delete_own" on public.recordings;
create policy "recordings_delete_own" on public.recordings
  for delete using (auth.uid() = user_id);

drop policy if exists "analyses_select_own" on public.analyses;
create policy "analyses_select_own" on public.analyses
  for select using (auth.uid() = user_id);

drop policy if exists "analyses_insert_own" on public.analyses;
create policy "analyses_insert_own" on public.analyses
  for insert with check (auth.uid() = user_id);

drop policy if exists "key_results_select_own" on public.key_results;
create policy "key_results_select_own" on public.key_results
  for select using (auth.uid() = user_id);

drop policy if exists "key_results_insert_own" on public.key_results;
create policy "key_results_insert_own" on public.key_results
  for insert with check (auth.uid() = user_id);

drop policy if exists "song_refs_select_all" on public.song_refs;
create policy "song_refs_select_all" on public.song_refs
  for select to authenticated using (true);

-- ------------------------------------------------------------
-- Storage 버킷 (녹음 파일, 비공개)
--   경로 규칙: recordings/<user_id>/<파일명>
-- ------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('recordings','recordings',false)
on conflict (id) do nothing;

drop policy if exists "recordings_bucket_insert_own" on storage.objects;
create policy "recordings_bucket_insert_own" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'recordings'
              and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "recordings_bucket_select_own" on storage.objects;
create policy "recordings_bucket_select_own" on storage.objects
  for select to authenticated
  using (bucket_id = 'recordings'
         and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "recordings_bucket_delete_own" on storage.objects;
create policy "recordings_bucket_delete_own" on storage.objects
  for delete to authenticated
  using (bucket_id = 'recordings'
         and (storage.foldername(name))[1] = auth.uid()::text);


-- ============================================================
-- PART 2. 시드 — song_refs 프리셋 10곡
--
-- ⚠️ 음역 숫자는 검증되지 않은 추정값이다 (source = manual_seed_unverified).
--    데모 전에 곡을 듣고 수정할 것. 안 고치면 추천 키가 틀린다.
--    수정 예:
--      update public.song_refs
--         set ref_high_note='A4', ref_high_midi=69, source='manual_verified'
--       where song_title='밤편지';
--
--    MIDI 참고: C3=48  C4=60(가온다)  A4=69  C5=72
--    한국식 "2옥타브 라" = A4 = 69
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


-- ============================================================
-- PART 3. 결과 확인
-- ============================================================

-- 만들어진 테이블
select table_name
from information_schema.tables
where table_schema = 'public'
order by table_name;
-- 기대: analyses, key_results, profiles, recordings, song_refs

-- profiles 구조 (id 가 uuid PK 이고 user_id 컬럼이 없어야 정상)
select column_name, data_type
from information_schema.columns
where table_schema = 'public' and table_name = 'profiles'
order by ordinal_position;

-- 시드된 곡
select song_title, artist, ref_low_note, ref_high_note,
       ref_high_midi - ref_low_midi as 음역폭_반음, source
from public.song_refs
order by ref_high_midi;
-- 기대: 10행
