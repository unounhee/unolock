-- ============================================================
-- UnoLock · 교재 업로드 — 파일 창고(Storage 버킷) + 권한 규칙
-- Supabase 대시보드 → SQL Editor 에 통째로 붙여넣고 [Run] 하세요.
-- (1층·2층 SQL을 먼저 실행한 뒤에 실행하세요. 여러 번 실행해도 안전.)
-- 원칙: 7-2와 동일 — "출제자는 자기 학원의 교재만 올리고/본다."
-- ============================================================

-- 1) 교재 파일을 담을 비공개 창고(버킷) 만들기
insert into storage.buckets (id, name, public)
values ('materials', 'materials', false)
on conflict (id) do nothing;

-- 2) materials 표 권한: 출제자는 자기 학원의 교재 줄만 관리
drop policy if exists "owner manages materials" on public.materials;
create policy "owner manages materials" on public.materials
  for all to authenticated
  using ( academy_id in (select id from public.academies where owner_id = auth.uid()) )
  with check ( academy_id in (select id from public.academies where owner_id = auth.uid()) and uploaded_by = auth.uid() );

-- 3) 창고(파일) 권한: 파일은 "<학원id>/<파일명>"에 저장. 첫 폴더(=학원id)가 내 학원일 때만 접근.
drop policy if exists "teacher upload own materials" on storage.objects;
create policy "teacher upload own materials" on storage.objects
  for insert to authenticated
  with check ( bucket_id = 'materials' and split_part(name, '/', 1) in (select id::text from public.academies where owner_id = auth.uid()) );

drop policy if exists "teacher read own materials" on storage.objects;
create policy "teacher read own materials" on storage.objects
  for select to authenticated
  using ( bucket_id = 'materials' and split_part(name, '/', 1) in (select id::text from public.academies where owner_id = auth.uid()) );

drop policy if exists "teacher delete own materials" on storage.objects;
create policy "teacher delete own materials" on storage.objects
  for delete to authenticated
  using ( bucket_id = 'materials' and split_part(name, '/', 1) in (select id::text from public.academies where owner_id = auth.uid()) );
