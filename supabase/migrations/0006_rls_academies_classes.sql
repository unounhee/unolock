drop policy if exists "owner manages academies" on public.academies;
create policy "owner manages academies"
on public.academies
for all
to authenticated
using (owner_id = auth.uid())
with check (owner_id = auth.uid());

drop policy if exists "owner manages classes" on public.classes;
create policy "owner manages classes"
on public.classes
for all
to authenticated
using (academy_id in (select id from public.academies where owner_id = auth.uid()))
with check (academy_id in (select id from public.academies where owner_id = auth.uid()));
