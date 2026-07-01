-- ============================================================
-- UnoLock · ⑰ 17-7a — child_settings (부모가 정하는 자녀별 잠금 설정)
--   부모가 자녀별 "매일 잠금시각 / 허용앱 / 보상(분)"을 서버에 저장.
--   자녀 폰은 자기 줄을 읽어 로컬(SharedPreferences)로 동기화 → 인터넷 없어도 잠금.
--   RLS: 부모=자기 자녀 것 읽기/쓰기, 학생=자기 것 읽기만(못 바꿈).
--   is_my_child(uuid) SECURITY DEFINER 는 0014 에서 만든 것을 재사용.
--   ⚠️ SQL 에디터를 비우고 실행. 함수 본문은 $fn$ 로.
-- ============================================================

create table if not exists public.child_settings (
  student_id       uuid primary key references public.profiles(id) on delete cascade,
  lock_hour        int  not null default -1,   -- -1 = 아직 설정 안 함
  lock_minute      int  not null default 0,
  allowed_packages text[] not null default '{}',
  reward_minutes   int  not null default 5,    -- 미션 하나 통과당 짧은 자유(분)
  updated_at       timestamptz not null default now()
);

alter table public.child_settings enable row level security;

-- 수정될 때마다 updated_at 자동 갱신 (자녀 폰이 "새 설정" 감지용)
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $fn$
begin
  new.updated_at := now();
  return new;
end
$fn$;

drop trigger if exists child_settings_touch on public.child_settings;
create trigger child_settings_touch
  before update on public.child_settings
  for each row execute function public.touch_updated_at();

-- 부모: 자기 자녀의 설정을 읽고/만들고/고친다.
drop policy if exists child_settings_parent_all on public.child_settings;
create policy child_settings_parent_all on public.child_settings
  for all
  using (public.is_my_child(student_id))
  with check (public.is_my_child(student_id));

-- 자녀(학생): 자기 설정을 읽기만 (폰이 로컬로 동기화). 못 바꾼다.
drop policy if exists child_settings_student_read on public.child_settings;
create policy child_settings_student_read on public.child_settings
  for select
  using (student_id = auth.uid());
