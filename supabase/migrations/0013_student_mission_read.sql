-- ============================================================
-- UnoLock · S3a — 승인된 학생이 자기 반의 수업/교재/사진을 읽게(7-3 일부)
-- generate-questions 함수가 "호출자 권한"으로 동작하므로,
-- 승인 학생에게 lesson_batches/materials/storage 읽기를 열어주면
-- 함수 수정 없이 학생도 출제를 받을 수 있다.
-- Supabase SQL Editor 비우고 통째로 붙여넣어 [Run].
-- ============================================================

-- 도우미 함수 (SECURITY DEFINER → 내부 조회 RLS 우회, 정책 재귀 방지)
create or replace function public.is_approved_member(p_class_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  return exists (
    select 1 from public.memberships m
    where m.class_id = p_class_id
      and m.student_id = auth.uid()
      and m.status = 'approved'
  );
end
$$;

create or replace function public.is_my_batch(p_batch_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  return exists (
    select 1 from public.lesson_batches b
    join public.memberships m on m.class_id = b.class_id
    where b.id = p_batch_id
      and m.student_id = auth.uid()
      and m.status = 'approved'
  );
end
$$;

-- 저장소 경로(academyId/batchId/파일)에서 batchId를 안전하게 뽑아 권한 확인
create or replace function public.can_read_material_path(p_name text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_batch uuid;
begin
  begin
    v_batch := split_part(p_name, '/', 2)::uuid;
  exception when others then
    return false;
  end;
  return exists (
    select 1 from public.lesson_batches b
    join public.memberships m on m.class_id = b.class_id
    where b.id = v_batch
      and m.student_id = auth.uid()
      and m.status = 'approved'
  );
end
$$;

-- 1) 승인 학생: 자기 반의 수업 묶음 읽기
drop policy if exists lesson_batches_student_select on public.lesson_batches;
create policy lesson_batches_student_select on public.lesson_batches
  for select using (public.is_approved_member(class_id));

-- 2) 승인 학생: 자기 반 묶음의 교재(materials) 읽기
drop policy if exists materials_student_select on public.materials;
create policy materials_student_select on public.materials
  for select using (public.is_my_batch(batch_id));

-- 3) 승인 학생: 자기 반 묶음의 사진 파일(storage) 읽기
drop policy if exists materials_read_student on storage.objects;
create policy materials_read_student on storage.objects
  for select using (
    bucket_id = 'materials'
    and public.can_read_material_path(name)
  );
