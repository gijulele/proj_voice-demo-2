-- ============================================================
-- 05_rls_test.sql — RLS(Row Level Security)가 "실제로 막는지" 확인
--
-- 목적: "정책을 만들었다"가 아니라 "정책이 진짜로 차단한다"를 증명한다.
--
-- ⚠️ 왜 이런 번거로운 방식이 필요한가
--    Supabase SQL Editor 는 postgres 역할로 실행되고, postgres 는 RLS 를
--    통째로 무시한다. 그냥 select 하면 남의 데이터도 전부 보이기 때문에
--    그걸 보고 "RLS 가 안 걸렸네" 라고 착각하게 된다.
--    아래처럼 role 을 authenticated / anon 으로 바꿔 로그인 상태를 흉내낸다.
--
-- ⚠️ 순서 규칙 (여기서 대부분 틀린다)
--    auth.users 조회는 반드시 role 을 바꾸기 "전"에 해야 한다.
--    authenticated 역할은 auth.users 를 읽을 권한이 없어서,
--    순서를 바꾸면 RLS 와 무관한 permission denied 가 나고
--    그걸 "RLS 가 막았다"고 오해하게 된다.
--
-- 아무것도 바꾸지 않는다 (전부 rollback 으로 끝남). 몇 번이든 실행 가능.
--
-- 실행 전 준비
--    1) 00_all_in_one.sql (또는 01+02+04) 이 Run 되어 있을 것
--    2) 03_seed_demo_data.sql 이 Run 되어 있을 것
--       → demo@vocalfit.test 계정과 그 계정의 녹음/분석 데이터가 필요하다
--
-- 사용법: 블록별로 읽되, 전체 선택 후 한 번에 Run 해도 된다.
--         테스트 3 은 에러가 나도 스크립트가 멈추지 않게 처리해 두었다.
-- ============================================================


-- ------------------------------------------------------------
-- 테스트 0. 정책이 붙어 있는지 / RLS 스위치가 켜져 있는지
-- ------------------------------------------------------------

-- 기대: profiles 2, recordings 3, analyses 2, key_results 2, song_refs 1  (총 10행)
select tablename, policyname, cmd, roles
from pg_policies
where schemaname = 'public'
order by tablename, cmd, policyname;

-- 기대: 5개 테이블 전부 rls_on = true
select relname as table_name, relrowsecurity as rls_on
from pg_class
where relnamespace = 'public'::regnamespace
  and relkind = 'r'
order by relname;


-- ------------------------------------------------------------
-- 테스트 1. 로그인한 "나" — 내 데이터가 보여야 한다
-- ------------------------------------------------------------
begin;

  -- (1) 먼저 postgres 권한으로 demo 계정의 uid 를 JWT 에 심는다
  select set_config(
    'request.jwt.claims',
    json_build_object(
      'sub',  (select id from auth.users where email = 'demo@vocalfit.test'),
      'role', 'authenticated'
    )::text,
    true
  );

  -- (2) 그 다음에 역할을 바꾼다 (순서 반대로 하면 권한 에러)
  set local role authenticated;

  select
    auth.uid()                                          as 내_uid,
    (select count(*) from public.recordings)            as 내_녹음수,
    (select count(*) from public.analyses)              as 내_분석수,
    (select count(*) from public.key_results)           as 내_키추천수,
    (select count(*) from public.profiles)              as 보이는_프로필수,
    (select count(*) from public.song_refs)             as 보이는_곡수;
  -- 기대: 내_uid 는 UUID(null 이면 시드 계정이 없는 것),
  --       녹음/분석/키추천 수는 0 이 아님,
  --       보이는_프로필수 = 1 (남의 프로필은 안 보임),
  --       보이는_곡수 = 10

rollback;


-- ------------------------------------------------------------
-- 테스트 2. 로그인한 "남" — 내 데이터가 하나도 안 보여야 한다
--   존재하지 않는 uuid 를 남의 계정처럼 사용한다.
-- ------------------------------------------------------------
begin;

  select set_config(
    'request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-000000000099","role":"authenticated"}',
    true
  );
  set local role authenticated;

  select
    auth.uid()                                  as 남의_uid,
    (select count(*) from public.recordings)    as 녹음수,
    (select count(*) from public.analyses)      as 분석수,
    (select count(*) from public.key_results)   as 키추천수,
    (select count(*) from public.profiles)      as 프로필수,
    (select count(*) from public.song_refs)     as 곡수;
  -- 기대: 녹음/분석/키추천/프로필 전부 0, 곡수만 10 (공용 데이터)
  -- ★ 곡수 말고 하나라도 0 이 아니면 RLS 가 새고 있는 것이다.

rollback;


-- ------------------------------------------------------------
-- 테스트 3. 남의 이름으로 INSERT 시도 — 거부되어야 한다
--   with check 절이 실제로 막는지 확인.
--
--   에러를 do 블록 안에서 잡아 결과를 한 줄로 돌려준다.
--   (그냥 insert 하면 에러로 스크립트가 중단되어 테스트 4가 안 돌아간다)
-- ------------------------------------------------------------
begin;

  create temp table rls_test3 (결과 text) on commit drop;

  do $$
  declare
    v_victim uuid;
  begin
    -- role 바꾸기 전에 조회해 둔다
    select id into v_victim from auth.users where email = 'demo@vocalfit.test';

    if v_victim is null then
      insert into rls_test3 values
        ('건너뜀 — demo@vocalfit.test 계정이 없다. 03_seed_demo_data.sql 먼저 실행할 것.');
      return;
    end if;

    begin
      execute 'set local role authenticated';
      perform set_config(
        'request.jwt.claims',
        '{"sub":"00000000-0000-0000-0000-000000000099","role":"authenticated"}',
        true
      );

      -- 내 uid 가 아닌 user_id 로 녹음을 밀어넣어 본다
      insert into public.recordings (user_id, file_path, duration_sec)
      values (v_victim, 'hack/attack.webm', 30);

      -- 여기까지 왔다는 건 막히지 않았다는 뜻 = 실패
      execute 'reset role';
      insert into rls_test3 values
        ('실패 ★ 남의 user_id 로 INSERT 가 통과했다. recordings_insert_own 정책을 확인할 것.');

    exception
      when insufficient_privilege then
        -- 예외가 나면 role 변경도 함께 되돌아간다
        insert into rls_test3 values
          ('성공 — RLS 가 INSERT 를 차단했다: ' || sqlerrm);
      when others then
        insert into rls_test3 values
          ('확인필요 — RLS 아닌 다른 에러: ' || sqlerrm || ' (SQLSTATE ' || sqlstate || ')');
    end;
  end $$;

  select * from rls_test3;
  -- 기대: "성공 — RLS 가 INSERT 를 차단했다: new row violates row-level security policy ..."

rollback;


-- ------------------------------------------------------------
-- 테스트 4. 비로그인(anon) — 아무것도 못 봐야 한다
-- ------------------------------------------------------------
begin;

  select set_config('request.jwt.claims', null, true);
  set local role anon;

  select
    (select count(*)::int from public.recordings) as 녹음수,
    (select count(*)::int from public.profiles)   as 프로필수,
    (select count(*)::int from public.song_refs)  as 곡수;
  -- 기대: 녹음수 0, 프로필수 0, 곡수 10
  --       song_refs 정책이 "to anon, authenticated" 라 곡 목록은 보이는 게 정상이다
  --       (로그인 전 랜딩 화면에 곡을 띄우기 위해서다)
  -- ★ 녹음수/프로필수가 0 이 아니면 RLS 가 새고 있는 것이다.

rollback;


-- ------------------------------------------------------------
-- 참고) 로그인한 사람만 곡 목록을 보게 하고 싶을 때만 실행
--       실행했다면 04_rls_policies.sql 의 song_refs 정책도 같이 고칠 것.
--       (안 고치면 04 를 다시 Run 할 때 원래대로 되돌아간다)
-- ------------------------------------------------------------
-- drop policy if exists "song_refs_select_all" on public.song_refs;
-- create policy "song_refs_select_all" on public.song_refs
--   for select to authenticated using (true);
