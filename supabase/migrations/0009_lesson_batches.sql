-- ============================================================
-- UnoLock · 수업 묶음(lesson_batches) — "한 번의 업로드 = 그 반의 현재 수업"
-- 출제자가 한 반에 사진 여러 장을 한꺼번에 올리면 묶음 1개가 생긴다.
-- 다음 업로드(새 묶음)가 생기면, 출제는 항상 "그 반의 가장 최근 묶음"만 쓴다.
--   (옛 묶음/파일은 지우지 않고 그냥 안 쓴다 = 무시.)
-- Supabase 대시보드 → SQL Editor 에 통째로 붙여넣고 [Run]. 여러 번 실행해도 안전.
-- (1~3층 + 0007·0008 을 먼저 실행한 뒤에 실행하세요.)
-- ============================================================

-- 1) lesson_batches — 업로드 한 번(= 그 반의 한 수업)
create table if not exists public.lesson_batches (
  id          uuid primary key default gen_random_uuid(),
  class_id    uuid not null references public.classes(id) on delete cascade,
  academy_id  uuid not null references public.academies(id) on delete cascade,
  created_by  uuid not null references public.profiles(id),
  created_at  timestamptz not null default now()
);

alter table public.lesson_batches enable row level security;

-- "그 반의 가장 최근 묶음"을 빨리 찾기 위한 색인
create index if not exists lesson_batches_class_recent
  on public.lesson_batches (class_id, created_at desc);

-- 출제자는 자기 학원의 묶음만 관리 (7-2·0007 과 동일한 학원 소유 규칙)
drop policy if exists "owner manages lesson_batches" on public.lesson_batches;
create policy "owner manages lesson_batches" on public.lesson_batches
  for all to authenticated
  using ( academy_id in (select id from public.academies where owner_id = auth.uid()) )
  with check (
    academy_id in (select id from public.academies where owner_id = auth.uid())
    and created_by = auth.uid()
  );

-- 2) materials 에 "어느 묶음 / 어느 반" 칸 추가 (기존 줄은 비어 있어도 됨 = 옛 단일 교재와 호환)
alter table public.materials add column if not exists batch_id uuid references public.lesson_batches(id) on delete cascade;
alter table public.materials add column if not exists class_id uuid references public.classes(id) on delete cascade;

-- 3) share_links 를 "교재 1개" 대신 "반"에 연결.
--    링크는 반에 묶이고, 출제는 그 반의 최신 묶음으로 → 학생은 같은 링크에서 항상 오늘 수업을 푼다.
alter table public.share_links alter column material_id drop not null;  -- 이제 반 기반 링크는 material_id 없이 생성
alter table public.share_links add column if not exists class_id uuid references public.classes(id) on delete cascade;

-- 권한 갱신: 자기 학원의 (반 기반 OR 옛 교재 기반) 링크만 관리
drop policy if exists "owner manages share_links" on public.share_links;
create policy "owner manages share_links" on public.share_links
  for all to authenticated
  using (created_by = auth.uid())
  with check (
    created_by = auth.uid()
    and (
      class_id in (
        select c.id from public.classes c
        join public.academies a on a.id = c.academy_id
        where a.owner_id = auth.uid()
      )
      or material_id in (
        select m.id from public.materials m
        join public.academies a on a.id = m.academy_id
        where a.owner_id = auth.uid()
      )
    )
  );
