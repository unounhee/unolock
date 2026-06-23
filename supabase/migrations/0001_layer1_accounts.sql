-- ============================================================
-- UnoLock · 1층 — 사람과 공간 (계정·권한 기초)
-- Supabase 대시보드 → SQL Editor 에 통째로 붙여넣고 [Run] 하세요.
-- 한 번 더 실행해도 안전하도록 "if not exists" 로 작성했습니다.
-- ============================================================

-- 1) profiles — 모든 사용자(로그인 계정 1개당 1줄) + 역할
--    로그인(auth.users)과 1:1로 연결됩니다. 가입하면 한 줄이 생깁니다.
create table if not exists public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  role       text not null check (role in ('teacher','student','parent')),
  full_name  text,
  phone      text,
  created_at timestamptz not null default now()
);

-- 2) academies — 학원/과외 "공간" (출제자가 만듦)
create table if not exists public.academies (
  id         uuid primary key default gen_random_uuid(),
  owner_id   uuid not null references public.profiles(id) on delete cascade,
  name       text not null,
  created_at timestamptz not null default now()
);

-- 3) classes — 반 (학원에 속함). 난이도 구분은 반 이름에 녹아있어 별도 칸 없음.
create table if not exists public.classes (
  id         uuid primary key default gen_random_uuid(),
  academy_id uuid not null references public.academies(id) on delete cascade,
  name       text not null,
  created_at timestamptz not null default now()
);

-- 4) memberships — 학생 ↔ 반 연결 + 승인 상태
--    한 학생이 여러 반(여러 학원)에 등록될 수 있음.
create table if not exists public.memberships (
  id         uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles(id) on delete cascade,
  class_id   uuid not null references public.classes(id) on delete cascade,
  status     text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at timestamptz not null default now(),
  unique (student_id, class_id)
);

-- 5) guardianships — 학부모 ↔ 학생 연결 (자녀 증명 코드)
create table if not exists public.guardianships (
  id          uuid primary key default gen_random_uuid(),
  parent_id   uuid not null references public.profiles(id) on delete cascade,
  student_id  uuid not null references public.profiles(id) on delete cascade,
  verify_code text,
  status      text not null default 'pending' check (status in ('pending','approved')),
  created_at  timestamptz not null default now(),
  unique (parent_id, student_id)
);

-- ------------------------------------------------------------
-- 보안: 5개 표 모두 잠금(RLS) 켜기.
-- 기본값은 "아무도 못 봄" = 안전. (공개키가 브라우저에 노출되므로 필수)
-- "누가 무엇을 보는지" 규칙(정보 비대칭)은 다음 단계에서 하나씩 추가합니다.
-- ------------------------------------------------------------
alter table public.profiles      enable row level security;
alter table public.academies     enable row level security;
alter table public.classes       enable row level security;
alter table public.memberships   enable row level security;
alter table public.guardianships enable row level security;
