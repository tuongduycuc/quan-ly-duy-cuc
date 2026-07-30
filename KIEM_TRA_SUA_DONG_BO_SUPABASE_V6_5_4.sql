-- =====================================================================
-- KIỂM TRA VÀ SỬA QUYỀN DỮ LIỆU / REALTIME SUPABASE - ỨNG DỤNG QUẢN LÝ DUY CÚC
-- Dùng cho project: https://poxzjancfnynwtigmhzn.supabase.co
-- Có thể chạy lại nhiều lần. Không xóa bảng và không xóa dữ liệu.
-- =====================================================================

begin;

-- 1. Bảo đảm 5 bảng đã tồn tại đúng tên
create extension if not exists pgcrypto;

create table if not exists public.entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  type text not null check (type in ('income', 'expense')),
  amount numeric(18,2) not null check (amount > 0),
  category text not null,
  note text not null default '',
  date date not null,
  created_at timestamptz not null default now()
);

create table if not exists public.budgets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  category text not null,
  amount numeric(18,2) not null check (amount > 0),
  created_at timestamptz not null default now(),
  unique (user_id, category)
);

create table if not exists public.recurring_bills (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  category text not null,
  amount numeric(18,2) not null check (amount > 0),
  day_of_month integer not null check (day_of_month between 1 and 28),
  last_paid_month text null,
  created_at timestamptz not null default now()
);

create table if not exists public.tasks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  due_date date not null,
  priority text not null default 'normal' check (priority in ('high', 'normal', 'low')),
  done boolean not null default false,
  project text not null default '',
  repeat_freq text not null default 'none' check (repeat_freq in ('none', 'daily', 'weekly', 'monthly')),
  created_at timestamptz not null default now()
);

create table if not exists public.goals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  target_amount numeric(18,2) not null check (target_amount > 0),
  current_amount numeric(18,2) not null default 0 check (current_amount >= 0),
  created_at timestamptz not null default now()
);

-- 2. Bảo đảm Data API có quyền truy cập schema và các bảng
grant usage on schema public to authenticated;
grant select, insert, update, delete on table public.entries to authenticated;
grant select, insert, update, delete on table public.budgets to authenticated;
grant select, insert, update, delete on table public.recurring_bills to authenticated;
grant select, insert, update, delete on table public.tasks to authenticated;
grant select, insert, update, delete on table public.goals to authenticated;

revoke all on table public.entries from anon;
revoke all on table public.budgets from anon;
revoke all on table public.recurring_bills from anon;
revoke all on table public.tasks from anon;
revoke all on table public.goals from anon;

-- 3. Bật RLS
alter table public.entries enable row level security;
alter table public.budgets enable row level security;
alter table public.recurring_bills enable row level security;
alter table public.tasks enable row level security;
alter table public.goals enable row level security;

-- 4. Tạo lại chính sách: mỗi tài khoản chỉ thấy dữ liệu của chính mình
drop policy if exists entries_own_rows on public.entries;
drop policy if exists budgets_own_rows on public.budgets;
drop policy if exists recurring_bills_own_rows on public.recurring_bills;
drop policy if exists tasks_own_rows on public.tasks;
drop policy if exists goals_own_rows on public.goals;

create policy entries_own_rows on public.entries
for all to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create policy budgets_own_rows on public.budgets
for all to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create policy recurring_bills_own_rows on public.recurring_bills
for all to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create policy tasks_own_rows on public.tasks
for all to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create policy goals_own_rows on public.goals
for all to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

-- 5. Cho Realtime nhận đủ INSERT / UPDATE / DELETE
alter table public.entries replica identity full;
alter table public.budgets replica identity full;
alter table public.recurring_bills replica identity full;
alter table public.tasks replica identity full;
alter table public.goals replica identity full;

DO $$
DECLARE
  t text;
BEGIN
  IF NOT EXISTS (select 1 from pg_publication where pubname = 'supabase_realtime') THEN
    execute 'create publication supabase_realtime';
  END IF;

  FOREACH t IN ARRAY ARRAY['entries','budgets','recurring_bills','tasks','goals']
  LOOP
    IF NOT EXISTS (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = t
    ) THEN
      execute format('alter publication supabase_realtime add table public.%I', t);
    END IF;
  END LOOP;
END $$;

-- 6. Chỉ mục hỗ trợ tải và kiểm tra RLS nhanh
create index if not exists entries_user_date_idx on public.entries (user_id, date desc);
create index if not exists budgets_user_idx on public.budgets (user_id);
create index if not exists recurring_bills_user_day_idx on public.recurring_bills (user_id, day_of_month);
create index if not exists tasks_user_due_idx on public.tasks (user_id, due_date);
create index if not exists goals_user_created_idx on public.goals (user_id, created_at);

commit;

-- 7. Bắt Data API đọc lại bảng/chính sách mới
notify pgrst, 'reload schema';
notify pgrst, 'reload config';

-- 8. Kết quả kiểm tra: phải có 5 dòng, rls_enabled = true, realtime_enabled = true
select
  c.relname as table_name,
  c.relrowsecurity as rls_enabled,
  exists (
    select 1
    from pg_publication_tables p
    where p.pubname = 'supabase_realtime'
      and p.schemaname = 'public'
      and p.tablename = c.relname
  ) as realtime_enabled
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in ('entries','budgets','recurring_bills','tasks','goals')
order by c.relname;
