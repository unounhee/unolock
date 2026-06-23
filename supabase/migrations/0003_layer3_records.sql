create table if not exists public.attempts (
  id uuid primary key default gen_random_uuid(),
  mission_id uuid not null references public.missions(id) on delete cascade,
  student_id uuid not null references public.profiles(id) on delete cascade,
  attempt_no int not null,
  score int,
  passed boolean not null default false,
  photo_url text,
  created_at timestamptz not null default now(),
  unique (mission_id, student_id, attempt_no)
);

create table if not exists public.questions (
  id uuid primary key default gen_random_uuid(),
  attempt_id uuid not null references public.attempts(id) on delete cascade,
  order_no int not null,
  type text not null check (type in ('mc','short')),
  body text not null,
  choices jsonb,
  correct_answer text not null,
  explanation text,
  created_at timestamptz not null default now()
);

create table if not exists public.answers (
  id uuid primary key default gen_random_uuid(),
  question_id uuid not null references public.questions(id) on delete cascade,
  attempt_id uuid not null references public.attempts(id) on delete cascade,
  student_answer text,
  is_correct boolean,
  created_at timestamptz not null default now(),
  unique (question_id)
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  parent_id uuid not null references public.profiles(id) on delete cascade,
  student_id uuid not null references public.profiles(id) on delete cascade,
  mission_id uuid references public.missions(id) on delete set null,
  attempt_id uuid references public.attempts(id) on delete set null,
  message text not null,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.attempts enable row level security;
alter table public.questions enable row level security;
alter table public.answers enable row level security;
alter table public.notifications enable row level security;
