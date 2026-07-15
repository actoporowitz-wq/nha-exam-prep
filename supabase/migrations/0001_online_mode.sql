-- NHA Exam Prep — online mode schema
-- Run this once in the Supabase SQL Editor for your project (as the default
-- `postgres` role — required so the SECURITY DEFINER function below can
-- delete from auth.users).

-- ============================================================
-- exam_rounds: one row per "round" (full attempt -> narrowing missed-only
-- retakes -> mastery) per user per exam.
-- ============================================================
create table public.exam_rounds (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  exam_key text not null,
  exam_title text not null,
  round_number int not null,
  original_total int not null,
  funnel_missed_count int not null default 0,
  status text not null default 'in_progress'
    check (status in ('in_progress','mastered','abandoned')),
  mastered_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, exam_key, round_number)
);

-- ============================================================
-- exam_attempts: one row per attempt within a round's funnel
-- (attempt 1 = full exam, attempt 2+ = missed-only retakes).
-- ============================================================
create table public.exam_attempts (
  id uuid primary key default gen_random_uuid(),
  round_id uuid not null references public.exam_rounds(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  attempt_number int not null,
  attempt_scope text not null check (attempt_scope in ('full','missed_retake')),
  source_attempt_id uuid references public.exam_attempts(id),
  total_questions int not null,
  correct_count int not null default 0,
  status text not null default 'in_progress' check (status in ('in_progress','completed')),
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  unique (round_id, attempt_number)
);

-- ============================================================
-- exam_attempt_answers: per-question snapshot + user's answer for that
-- attempt. Snapshotted (not FK'd to the static EXAM_LIBRARY) so review and
-- export stay correct even if the library's question text changes later.
-- ============================================================
create table public.exam_attempt_answers (
  id uuid primary key default gen_random_uuid(),
  attempt_id uuid not null references public.exam_attempts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  question_index int not null,
  question_text text not null,
  options jsonb not null,
  correct_option int not null,
  explanation text,
  selected_option int,
  flagged boolean not null default false,
  unique (attempt_id, question_index)
);

create index idx_exam_rounds_user_exam on public.exam_rounds(user_id, exam_key);
create index idx_exam_attempts_round on public.exam_attempts(round_id);
create index idx_exam_attempts_user on public.exam_attempts(user_id);
create index idx_exam_attempt_answers_attempt on public.exam_attempt_answers(attempt_id);

-- ============================================================
-- RLS: every table locked to user_id = auth.uid(), both directions.
-- ============================================================
alter table public.exam_rounds enable row level security;
alter table public.exam_attempts enable row level security;
alter table public.exam_attempt_answers enable row level security;

create policy "own rounds" on public.exam_rounds
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own attempts" on public.exam_attempts
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own answers" on public.exam_attempt_answers
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ============================================================
-- Self-delete RPC: the ONLY way to remove an auth.users row from client
-- code (the service_role key is never shipped client-side). Runs as the
-- function owner (postgres), so it can DELETE from auth.users; app tables
-- cascade automatically via the FKs above.
-- ============================================================
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;
  delete from auth.users where id = auth.uid();
end;
$$;

revoke all on function public.delete_my_account() from public;
grant execute on function public.delete_my_account() to authenticated;
