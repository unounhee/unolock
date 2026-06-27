-- ============================================================
-- UnoLock · S2 보정 — 권한 규칙(RLS) 무한 반복 끊기
-- 0011 정책들이 서로(memberships↔classes↔profiles) 참조 → recursion 가능.
-- 검사 로직을 SECURITY DEFINER 함수(RLS 우회)로 빼서 고리를 끊는다.
-- (함수 형태는 0011에서 통과한 plpgsql begin/end 형태로 통일)
-- Supabase SQL Editor 비우고 통째로 붙여넣어 [Run].
-- ============================================================

create or replace function public.is_class_owner(p_class_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  return exists (
    select 1 from public.classes c
    join public.academies a on a.id = c.academy_id
    where c.id = p_class_id and a.owner_id = auth.uid()
  );
end
$$;

create or replace function public.is_my_class(p_class_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  return exists (
    select 1 from public.memberships m
    where m.class_id = p_class_id and m.student_id = auth.uid()
  );
end
$$;

create or replace function public.is_my_student(p_student_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  return exists (
    select 1 from public.memberships m
    join public.classes c on c.id = m.class_id
    join public.academies a on a.id = c.academy_id
    where m.student_id = p_student_id and a.owner_id = auth.uid()
  );
end
$$;

drop policy if exists memberships_teacher_select on public.memberships;
create policy memberships_teacher_select on public.memberships
  for select using (public.is_class_owner(class_id));

drop policy if exists memberships_teacher_update on public.memberships;
create policy memberships_teacher_update on public.memberships
  for update using (public.is_class_owner(class_id));

drop policy if exists memberships_teacher_delete on public.memberships;
create policy memberships_teacher_delete on public.memberships
  for delete using (public.is_class_owner(class_id));

drop policy if exists profiles_teacher_read_students on public.profiles;
create policy profiles_teacher_read_students on public.profiles
  for select using (public.is_my_student(id));

drop policy if exists classes_student_select on public.classes;
create policy classes_student_select on public.classes
  for select using (public.is_my_class(id));
