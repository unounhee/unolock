-- ============================================================
-- UnoLock · 학생 풀이 공유 링크
-- 출제자가 교재로 "풀이 링크"를 만들면, 학생은 로그인 없이 토큰으로 접속해 푼다.
-- 실제 문제 출제는 공개 Edge Function이 service_role로 처리(키 노출 없음).
-- Supabase SQL Editor에 붙여넣고 [Run]. 여러 번 실행해도 안전.
-- ============================================================

create table if not exists public.share_links (
  token       text primary key,   -- 링크에 들어가는 무작위 토큰
  material_id uuid not null references public.materials(id) on delete cascade,
  created_by  uuid not null references public.profiles(id) on delete cascade,
  label       text,
  created_at  timestamptz not null default now()
);

alter table public.share_links enable row level security;

-- 출제자는 자기 학원 교재로 만든 링크만 생성/조회/삭제.
drop policy if exists "owner manages share_links" on public.share_links;
create policy "owner manages share_links" on public.share_links
  for all to authenticated
  using (created_by = auth.uid())
  with check (
    created_by = auth.uid()
    and material_id in (
      select m.id from public.materials m
      join public.academies a on a.id = m.academy_id
      where a.owner_id = auth.uid()
    )
  );
