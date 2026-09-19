-- ============================================================
-- vocalfit — Supabase 초기 스키마
-- Supabase Dashboard > SQL Editor 에 전체 붙여넣고 Run
-- 여러 번 실행해도 안전하도록 if not exists / drop policy if exists 사용
-- ============================================================

-- ------------------------------------------------------------
-- 0. 확장
-- ------------------------------------------------------------
create extension if not exists "pgcrypto";   -- gen_random_uuid()

-- ------------------------------------------------------------
-- 1. profiles  (spec의 users 역할)
--    이메일/비밀번호는 Supabase Auth(auth.users)가 관리한다.
--    직접 password_hash 컬럼을 두지 않는다.
-- ------------------------------------------------------------
create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  email       text not null,
  nickname    text not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

comment on table public.profiles is 'auth.users 1:1 확장 프로필. 회원가입 시 트리거로 자동 생성.';

-- 닉네임 중복 방지 (대소문자 무시)
create unique index if not exists profiles_nickname_key
  on public.profiles (lower(nickname));

-- ------------------------------------------------------------
-- 2. song_refs  (프리셋 10곡, 사용자 데이터 아님 → user_id 없음)
-- ------------------------------------------------------------
create table if not exists public.song_refs (
  id            uuid primary key default gen_random_uuid(),
  song_title    text not null,
  artist        text not null,
  ref_high_note text not null,          -- 예: 'A4'
  ref_low_note  text not null,          -- 예: 'C3'
  ref_high_midi smallint not null,      -- 예: 69  (계산용)
  ref_low_midi  smallint not null,      -- 예: 48
  source        text not null default 'manual_seed',
  created_at    timestamptz not null default now(),
  constraint song_refs_range_chk check (ref_low_midi < ref_high_midi)
);

create unique index if not exists song_refs_title_artist_key
  on public.song_refs (lower(song_title), lower(artist));

-- ------------------------------------------------------------
-- 3. recordings
-- ------------------------------------------------------------
create table if not exists public.recordings (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles(id) on delete cascade,
  song_title   text not null,
  file_path    text not null,           -- Storage 버킷 내 경로
  duration_sec numeric(6,2),
  sample_rate  integer,
  created_at   timestamptz not null default now(),
  constraint recordings_duration_chk check (duration_sec is null or duration_sec > 0)
);

create index if not exists recordings_user_created_idx
  on public.recordings (user_id, created_at desc);

-- ------------------------------------------------------------
-- 4. analyses
-- ------------------------------------------------------------
do $$ begin
  create type public.analysis_status as enum ('pending', 'processing', 'done', 'failed');
exception when duplicate_object then null; end $$;

create table if not exists public.analyses (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references public.profiles(id) on delete cascade,
  recording_id    uuid not null references public.recordings(id) on delete cascade,
  status          public.analysis_status not null default 'pending',
  low_note        text,                 -- 'C3'
  high_note       text,
  safe_high_note  text,                 -- 상위 5% 컷 이후 안전 최고음
  break_note      text,                 -- 무너지는 지점
  low_midi        smallint,
  high_midi       smallint,
  safe_high_midi  smallint,
  break_midi      smallint,
  confidence      numeric(4,3),         -- 0.000 ~ 1.000
  f0_series_path  text,                 -- f0 시계열 JSON 경로
  error_message   text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint analyses_confidence_chk
    check (confidence is null or (confidence >= 0 and confidence <= 1))
);

-- 녹음 1건당 분석 1건
create unique index if not exists analyses_recording_key
  on public.analyses (recording_id);

create index if not exists analyses_user_created_idx
  on public.analyses (user_id, created_at desc);

create index if not exists analyses_status_idx
  on public.analyses (status) where status in ('pending', 'processing');

-- ------------------------------------------------------------
-- 5. key_results
-- ------------------------------------------------------------
do $$ begin
  create type public.key_verdict as enum ('easy', 'fit', 'hard', 'impossible');
exception when duplicate_object then null; end $$;

create table if not exists public.key_results (
  id                    uuid primary key default gen_random_uuid(),
  user_id               uuid not null references public.profiles(id) on delete cascade,
  analysis_id           uuid not null references public.analyses(id) on delete cascade,
  song_ref_id           uuid not null references public.song_refs(id) on delete restrict,
  recommended_key_shift smallint not null,   -- 반음 단위 ±n
  verdict               public.key_verdict not null,
  created_at            timestamptz not null default now(),
  constraint key_results_shift_chk
    check (recommended_key_shift between -12 and 12)
);

create unique index if not exists key_results_analysis_song_key
  on public.key_results (analysis_id, song_ref_id);

create index if not exists key_results_user_created_idx
  on public.key_results (user_id, created_at desc);

-- ------------------------------------------------------------
-- 6. updated_at 자동 갱신 트리거
-- ------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
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
-- 7. 회원가입 시 profiles 자동 생성 트리거
--    signUp 시 options.data 에 nickname 을 넣으면 그대로 들어간다.
-- ------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, nickname)
  values (
    new.id,
    new.email,
    coalesce(
      nullif(new.raw_user_meta_data ->> 'nickname', ''),
      split_part(new.email, '@', 1)
    )
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
-- 8. RLS — 본인 데이터만 접근
-- ------------------------------------------------------------
alter table public.profiles    enable row level security;
alter table public.recordings  enable row level security;
alter table public.analyses    enable row level security;
alter table public.key_results enable row level security;
alter table public.song_refs   enable row level security;

-- profiles: 본인 행만 읽기/수정 (insert 는 트리거가 담당)
drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own" on public.profiles
  for select using (auth.uid() = id);

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own" on public.profiles
  for update using (auth.uid() = id) with check (auth.uid() = id);

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

-- analyses (쓰기는 서버 service_role 이 담당 → 클라이언트는 읽기만)
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

-- song_refs: 로그인 사용자 모두 읽기 전용
drop policy if exists "song_refs_select_all" on public.song_refs;
create policy "song_refs_select_all" on public.song_refs
  for select to authenticated using (true);

-- ------------------------------------------------------------
-- 9. Storage 버킷 (녹음 파일)
-- ------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('recordings', 'recordings', false)
on conflict (id) do nothing;

-- 경로 규칙: recordings/<user_id>/<uuid>.webm
drop policy if exists "recordings_bucket_insert_own" on storage.objects;
create policy "recordings_bucket_insert_own" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'recordings'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "recordings_bucket_select_own" on storage.objects;
create policy "recordings_bucket_select_own" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'recordings'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "recordings_bucket_delete_own" on storage.objects;
create policy "recordings_bucket_delete_own" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'recordings'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
