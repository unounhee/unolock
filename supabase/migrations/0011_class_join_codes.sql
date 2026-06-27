-- ============================================================
-- UnoLock · S2 — 반 참가 코드 + 학생 신청/승인/내보내기
-- Supabase 대시보드 → SQL Editor 에 통째로 붙여넣고 [Run].
-- 여러 번 실행해도 안전(if not exists / create or replace / drop ... if exists).
-- ============================================================

-- 1) 반에 "참가 코드" 칸 추가 -------------------------------------------------
alter table public.classes add column if not exists join_code text;

-- 헷갈리는 글자(O,0,1,I 등) 빼고 6자리 코드를 만드는 함수
create or replace function public.gen_join_code()
returns text language plpgsql as $fn$
declare
  alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  code text;
  i int;
begin
  loop
    code := '';
    for i in 1..6 loop
      code := code || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from public.classes where join_code = code);
  end loop;
  return code;
end
$fn$;

-- 기존 반들에 코드 채우기
update public.classes set join_code = public.gen_join_code() where join_code is null;

-- 새 반이 생기면 코드 자동 부여(트리거 대신 "기본값"으로 — 더 간단/안전)
alter table public.classes alter column join_code set default public.gen_join_code();
alter table public.classes alter column join_code set not null;
create unique index if not exists classes_join_code_key on public.classes(join_code);

-- 2) 학생이 코드로 신청하는 함수 -------------------------------------------
--    비공개 반이라도 "정확한 코드"를 아는 학생만 신청 가능.
--    항상 신청자 본인(auth.uid())으로만 membership을 만든다(대기 상태).
create or replace function public.join_class_by_code(p_code text)
returns table(class_id uuid, class_name text, status text)
language plpgsql security definer set search_path = public as $fn$
declare
  v_class public.classes;
  v_status text;
begin
  select * into v_class from public.classes
    where join_code = upper(trim(p_code));
  if not found then
    raise exception '반 코드를 찾을 수 없어요.';
  end if;

  select m.status into v_status from public.memberships m
    where m.student_id = auth.uid() and m.class_id = v_class.id;

  if v_status is null then
    insert into public.memberships(student_id, class_id, status)
      values (auth.uid(), v_class.id, 'pending');
    v_status := 'pending';
  end if;

  return query select v_class.id, v_class.name, v_status;
end
$fn$;

grant execute on function public.join_class_by_code(text) to authenticated;

-- 3) 권한 규칙(RLS) -------------------------------------------------------
-- memberships: 학생은 자기 신청만, 선생님은 자기 반 신청 전체를 보고 관리.
drop policy if exists memberships_student_select on public.memberships;
create policy memberships_student_select on public.memberships
  for select using (student_id = auth.uid());

drop policy if exists memberships_teacher_select on public.memberships;
create policy memberships_teacher_select on public.memberships
  for select using (exists (
    select 1 from public.classes c
    join public.academies a on a.id = c.academy_id
    where c.id = memberships.class_id and a.owner_id = auth.uid()
  ));

drop policy if exists memberships_teacher_update on public.memberships;
create policy memberships_teacher_update on public.memberships
  for update using (exists (
    select 1 from public.classes c
    join public.academies a on a.id = c.academy_id
    where c.id = memberships.class_id and a.owner_id = auth.uid()
  ));

drop policy if exists memberships_teacher_delete on public.memberships;
create policy memberships_teacher_delete on public.memberships
  for delete using (exists (
    select 1 from public.classes c
    join public.academies a on a.id = c.academy_id
    where c.id = memberships.class_id and a.owner_id = auth.uid()
  ));

-- profiles: 선생님이 "자기 반에 신청/소속된 학생"의 이름을 볼 수 있게.
drop policy if exists profiles_teacher_read_students on public.profiles;
create policy profiles_teacher_read_students on public.profiles
  for select using (exists (
    select 1 from public.memberships m
    join public.classes c on c.id = m.class_id
    join public.academies a on a.id = c.academy_id
    where m.student_id = profiles.id and a.owner_id = auth.uid()
  ));

-- classes: 학생이 "자기가 신청/소속된 반"의 이름을 볼 수 있게(미션 단계에서도 사용).
drop policy if exists classes_student_select on public.classes;
create policy classes_student_select on public.classes
  for select using (exists (
    select 1 from public.memberships m
    where m.class_id = classes.id and m.student_id = auth.uid()
  ));
