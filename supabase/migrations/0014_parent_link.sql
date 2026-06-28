-- ============================================================
-- UnoLock · S3c-2a — parent links child + sees passed only
-- functions wrapped in $fn$ (editor mishandles complex $$ bodies).
-- run on a cleared SQL editor.
-- ============================================================

alter table public.profiles add column if not exists link_code text;

create or replace function public.gen_link_code()
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
    exit when not exists (select 1 from public.profiles where link_code = code);
  end loop;
  return code;
end
$fn$;

update public.profiles set link_code = public.gen_link_code() where link_code is null;
alter table public.profiles alter column link_code set default public.gen_link_code();
alter table public.profiles alter column link_code set not null;
create unique index if not exists profiles_link_code_key on public.profiles(link_code);

create or replace function public.is_my_child(p_student_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $fn$
begin
  return exists (
    select 1 from public.guardianships g
    where g.parent_id = auth.uid()
      and g.student_id = p_student_id
      and g.status = 'approved'
  );
end
$fn$;

-- return columns renamed to child_id/child_name to avoid ambiguity with table columns
drop function if exists public.link_child_by_code(text);
create function public.link_child_by_code(p_code text)
returns table(child_id uuid, child_name text)
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_student public.profiles;
begin
  select * into v_student from public.profiles
    where link_code = upper(trim(p_code)) and role = 'student';
  if not found then
    raise exception 'link code not found';
  end if;
  insert into public.guardianships(parent_id, student_id, status)
    values (auth.uid(), v_student.id, 'approved')
    on conflict (parent_id, student_id) do nothing;
  return query select v_student.id, v_student.full_name;
end
$fn$;

grant execute on function public.link_child_by_code(text) to authenticated;

drop policy if exists guardianships_parent_select on public.guardianships;
create policy guardianships_parent_select on public.guardianships
  for select using (parent_id = auth.uid());

drop policy if exists profiles_parent_read_child on public.profiles;
create policy profiles_parent_read_child on public.profiles
  for select using (public.is_my_child(id));

drop policy if exists attempts_parent_read_passed on public.attempts;
create policy attempts_parent_read_passed on public.attempts
  for select using (passed = true and public.is_my_child(student_id));
