-- ================================================================
-- TẠO LẠI CƠ SỞ DỮ LIỆU CHO ỨNG DỤNG QUẢN LÝ DUY CÚC
-- Không có lệnh DROP/TRUNCATE. Có thể chạy trên project mới hoặc project trống.
-- ================================================================

create extension if not exists pgcrypto;

-- 1. Giao dịch thu/chi
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

-- 2. Ngân sách theo danh mục
create table if not exists public.budgets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  category text not null,
  amount numeric(18,2) not null check (amount > 0),
  created_at timestamptz not null default now(),
  unique (user_id, category)
);

-- 3. Khoản chi định kỳ
create table if not exists public.recurring_bills (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  category text not null,
  amount numeric(18,2) not null check (amount > 0),
  day_of_month integer not null check (day_of_month between 1 and 28),
  last_paid_month text null check (
    last_paid_month is null or last_paid_month ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'
  ),
  created_at timestamptz not null default now()
);

-- 4. Công việc
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

-- 5. Mục tiêu tiết kiệm
create table if not exists public.goals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  target_amount numeric(18,2) not null check (target_amount > 0),
  current_amount numeric(18,2) not null default 0 check (current_amount >= 0),
  created_at timestamptz not null default now()
);

-- Chỉ mục để tải dữ liệu nhanh hơn
create index if not exists entries_user_date_idx on public.entries (user_id, date desc);
create index if not exists budgets_user_idx on public.budgets (user_id);
create index if not exists recurring_bills_user_day_idx on public.recurring_bills (user_id, day_of_month);
create index if not exists tasks_user_due_idx on public.tasks (user_id, due_date);
create index if not exists tasks_user_done_idx on public.tasks (user_id, done);
create index if not exists goals_user_created_idx on public.goals (user_id, created_at);

-- Bật Row Level Security
alter table public.entries enable row level security;
alter table public.budgets enable row level security;
alter table public.recurring_bills enable row level security;
alter table public.tasks enable row level security;
alter table public.goals enable row level security;

-- Không cho người chưa đăng nhập truy cập bảng
revoke all on table public.entries from anon;
revoke all on table public.budgets from anon;
revoke all on table public.recurring_bills from anon;
revoke all on table public.tasks from anon;
revoke all on table public.goals from anon;

-- Cho tài khoản đã đăng nhập thực hiện CRUD; RLS bên dưới sẽ giới hạn theo user_id
 grant select, insert, update, delete on table public.entries to authenticated;
 grant select, insert, update, delete on table public.budgets to authenticated;
 grant select, insert, update, delete on table public.recurring_bills to authenticated;
 grant select, insert, update, delete on table public.tasks to authenticated;
 grant select, insert, update, delete on table public.goals to authenticated;

-- Xóa chính sách cũ cùng tên nếu đã tồn tại
 drop policy if exists "entries_own_rows" on public.entries;
 drop policy if exists "budgets_own_rows" on public.budgets;
 drop policy if exists "recurring_bills_own_rows" on public.recurring_bills;
 drop policy if exists "tasks_own_rows" on public.tasks;
 drop policy if exists "goals_own_rows" on public.goals;

-- Mỗi tài khoản chỉ được xem/thêm/sửa/xóa dữ liệu của chính mình
create policy "entries_own_rows"
on public.entries
for all
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create policy "budgets_own_rows"
on public.budgets
for all
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create policy "recurring_bills_own_rows"
on public.recurring_bills
for all
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create policy "tasks_own_rows"
on public.tasks
for all
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create policy "goals_own_rows"
on public.goals
for all
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

-- Bật Realtime cho 5 bảng; chỉ thêm nếu chưa nằm trong publication
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'entries'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.entries;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'budgets'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.budgets;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'recurring_bills'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.recurring_bills;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'tasks'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.tasks;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'goals'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.goals;
  END IF;
END $$;

-- Kết quả kiểm tra: phải trả về đủ 5 bảng và rls_enabled = true
select
  c.relname as table_name,
  c.relrowsecurity as rls_enabled
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in ('entries', 'budgets', 'recurring_bills', 'tasks', 'goals')
order by c.relname;
