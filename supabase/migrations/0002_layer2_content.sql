-- ============================================================
-- UnoLock · 2층 — 콘텐츠 (교재·미션)
-- Supabase 대시보드 → SQL Editor 에 통째로 붙여넣고 [Run] 하세요.
-- (1층 SQL을 먼저 실행한 뒤에 실행하세요.)
-- ============================================================

-- 6) materials — 출제자가 올린 교재 (사진/PDF)
--    실제 파일은 Supabase Storage에 저장하고, 여기엔 그 "위치(storage_path)"만 기록합니다.
create table if not exists public.materials (
  id           uuid primary key default gen_random_uuid(),
  academy_id   uuid not null references public.academies(id) on delete cascade,
  uploaded_by  uuid not null references public.profiles(id),
  title        text not null,
  storage_path text,                                  -- 파일 저장 위치 (업로드 기능 만들 때 채움)
  file_type    text check (file_type in ('image','pdf')),
  created_at   timestamptz not null default now()
);

-- 7) missions — 교재로 만든 미션 1개 (반 전체에 배포)
--    학생별 풀이/채점은 3층(attempts)에서 다룹니다. 통과기준 기본 80%(8할).
create table if not exists public.missions (
  id          uuid primary key default gen_random_uuid(),
  class_id    uuid not null references public.classes(id) on delete cascade,
  material_id uuid references public.materials(id) on delete set null,  -- 출처 교재 (없을 수도 있음)
  created_by  uuid not null references public.profiles(id),
  subject     text not null check (subject in ('math','vocab')),        -- 수학 / 영단어
  title       text not null,
  pass_score  int not null default 80,                                  -- 통과 커트라인(%)
  created_at  timestamptz not null default now()
);

-- ------------------------------------------------------------
-- 보안: 두 표 모두 잠금(RLS) 켜기 (기본 "아무도 못 봄").
-- ------------------------------------------------------------
alter table public.materials enable row level security;
alter table public.missions  enable row level security;
