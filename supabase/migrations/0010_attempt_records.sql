-- ============================================================
-- UnoLock · ⑭ 풀이 결과 저장 — 기록표(attempts/questions/answers)를 "지금 제품"에 맞게 수정
--
-- 왜? 기록표는 아주 초반(⑤)에 "학생 계정 + 저장된 미션"을 가정하고 만들었다.
-- 그런데 제품은 그 뒤로 (1) 학생은 로그인 없이 '링크'로 풀고,
-- (2) 문제는 즉석에서 AI가 만들고, (3) 풀이는 '수업 묶음(batch)' 기준으로 돈다.
-- 그래서 mission_id·student_id를 '선택값'으로 풀고, batch_id·share_token·student_name(이름만 입력)을 더한다.
--
-- 실제 저장은 공개 Edge Function 'record-attempt'가 service_role로 한다(RLS 우회).
-- 여기서 추가하는 RLS는 "출제자가 자기 반의 풀이 결과만 읽기"용(14-4 결과 화면).
--
-- Supabase 대시보드 → SQL Editor 에 통째로 붙여넣고 [Run]. 여러 번 실행해도 안전.
-- (0001~0009 를 먼저 실행한 뒤에 실행하세요.)
-- ============================================================

-- 1) attempts(풀이 1회) 를 지금 제품에 맞게 ----------------------------------
-- 1-1) 저장된 미션이 없을 수 있으니 mission_id 를 '선택값'으로
alter table public.attempts alter column mission_id drop not null;
-- 1-2) 로그인 안 한 학생도 있으니 student_id 를 '선택값'으로
alter table public.attempts alter column student_id drop not null;
-- 1-3) 풀이가 속한 '수업 묶음' / '학생 이름(자기입력)' / '어느 링크로 들어왔나'
alter table public.attempts add column if not exists batch_id    uuid references public.lesson_batches(id) on delete cascade;
alter table public.attempts add column if not exists student_name text;
alter table public.attempts add column if not exists share_token  text references public.share_links(token) on delete set null;

-- 1-4) 옛 유니크 제약(mission_id+student_id+attempt_no)은 이제 둘 다 비어 있을 수 있어 의미가 없다 → 제거
alter table public.attempts drop constraint if exists attempts_mission_id_student_id_attempt_no_key;

-- 1-5) "이 반의 최근 풀이"를 빨리 찾기 위한 색인
create index if not exists attempts_batch_recent on public.attempts (batch_id, created_at desc);

-- 2) 출제자 읽기 권한(RLS) — "자기 학원 묶음의 풀이 결과만 본다" --------------
-- (저장은 함수가 service_role 로 하므로 INSERT 정책은 필요 없다.)
drop policy if exists "owner reads attempts" on public.attempts;
create policy "owner reads attempts" on public.attempts
  for select to authenticated
  using (
    batch_id in (
      select b.id from public.lesson_batches b
      join public.academies a on a.id = b.academy_id
      where a.owner_id = auth.uid()
    )
  );

-- questions/answers 도 같은 원리: 자기 반 풀이(attempt)에 속한 것만 읽기
drop policy if exists "owner reads questions" on public.questions;
create policy "owner reads questions" on public.questions
  for select to authenticated
  using (
    attempt_id in (
      select t.id from public.attempts t
      join public.lesson_batches b on b.id = t.batch_id
      join public.academies a on a.id = b.academy_id
      where a.owner_id = auth.uid()
    )
  );

drop policy if exists "owner reads answers" on public.answers;
create policy "owner reads answers" on public.answers
  for select to authenticated
  using (
    attempt_id in (
      select t.id from public.attempts t
      join public.lesson_batches b on b.id = t.batch_id
      join public.academies a on a.id = b.academy_id
      where a.owner_id = auth.uid()
    )
  );
