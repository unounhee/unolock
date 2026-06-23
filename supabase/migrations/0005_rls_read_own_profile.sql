drop policy if exists "read own profile" on public.profiles;

create policy "read own profile"
on public.profiles
for select
to authenticated
using (id = auth.uid());
