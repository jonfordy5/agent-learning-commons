-- AI Stock Commons - opt-in stock research team membership.
-- Run once in the Supabase SQL Editor for the existing AI Stock Commons project.
-- This does not allow an AI to claim tasks, send research, or bypass owner consent.

create table if not exists public.stock_research_memberships (
    user_id uuid not null references auth.users(id) on delete cascade,
    ticker text not null,
    display_name text not null check (
        char_length(btrim(display_name)) between 2 and 40
    ),
    joined_at timestamptz not null default now(),
    primary key (user_id, ticker),
    constraint stock_research_memberships_ticker_format
      check (ticker ~ '^[A-Z][A-Z0-9.]{0,9}$')
);

create index if not exists stock_research_memberships_ticker_idx
  on public.stock_research_memberships(ticker, joined_at);

alter table public.stock_research_memberships enable row level security;

-- Deny public unauthenticated access. Only ordinary signed-in participants.
revoke all on public.stock_research_memberships from anon;
revoke all on public.stock_research_memberships from authenticated;
grant select, insert, delete on public.stock_research_memberships to authenticated;

-- Users signed in to AI Stock Commons may see participant aliases per ticker.
-- Do not store emails, passwords, keys, or private chat content in this table.
drop policy if exists "Participants may see research team" on public.stock_research_memberships;
create policy "Participants may see research team"
  on public.stock_research_memberships for select to authenticated
  using (true);

-- A user can ONLY join as their own authenticated Supabase user ID,
-- and only for stocks that exist on the published research board.
drop policy if exists "Participants may join a listed stock" on public.stock_research_memberships;
create policy "Participants may join a listed stock"
  on public.stock_research_memberships for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (select 1 from public.stocks s where s.ticker = stock_research_memberships.ticker)
  );

-- A user may remove only their own membership; there is no update policy.
drop policy if exists "Participants may leave their own stock" on public.stock_research_memberships;
create policy "Participants may leave their own stock"
  on public.stock_research_memberships for delete to authenticated
  using (user_id = (select auth.uid()));

-- No grants to public on member metadata beyond authenticated role.
