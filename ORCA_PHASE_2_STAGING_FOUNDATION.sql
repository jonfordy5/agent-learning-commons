-- ORCA Phase 2 staging foundation — review draft only.
--
-- DO NOT EXECUTE. This is a proposed core-schema baseline assembled from the
-- owner-supplied production catalog evidence packet. It has not been run
-- against production or staging. It is a review draft; exact-source/ACL
-- verification for the transcribed functions and any applicable trigger or
-- agent-session test dependencies listed below remain open.
--
-- The target is a dedicated Orca-staging Supabase project. Supabase-managed
-- auth.users and auth.uid() are prerequisites, not objects created here. Never
-- copy production Auth rows, credentials, findings, or task data. Create only
-- dedicated synthetic staging users and fixtures after the installer review.
--
-- Evidence scope: production schema before Phase 2. The owner supplied the
-- columns, constraints, indexes, RLS policies, effective table privileges,
-- and selected column privileges for the six core tables. Constraint meanings
-- below match that evidence. Where catalog constraint names were not included
-- in the packet, PostgreSQL will generate names; no additional checks are
-- introduced. Effective grants are reproduced for anon/authenticated without
-- claiming to reproduce unprovided grantor/ACL provenance.

-- SECTION 1 — Core tables
-- Create referenced tables before their dependents. auth.users is provided by
-- Supabase and must already exist in the isolated staging project.

create table public.stocks (
  ticker text not null primary key,
  company_name text,
  created_at timestamptz default now()
);

create table public.agent_profiles (
  id uuid not null default gen_random_uuid() primary key,
  owner_id uuid not null unique references auth.users(id) on delete cascade,
  display_name text not null default 'My AI Agent'::text
    check (char_length(display_name) between 1 and 60),
  opted_in boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.agent_sessions (
  id uuid not null default gen_random_uuid() primary key,
  agent_profile_id uuid not null
    references public.agent_profiles(id) on delete cascade,
  status text not null default 'pending'::text
    check (status in ('pending', 'connected', 'disconnected', 'expired')),
  connected_at timestamptz,
  last_heartbeat_at timestamptz,
  lease_expires_at timestamptz,
  disconnected_at timestamptz,
  created_at timestamptz not null default now(),
  check (
    status <> 'connected'
    or (
      connected_at is not null
      and last_heartbeat_at is not null
      and lease_expires_at is not null
    )
  )
);

create table public.stock_research_memberships (
  user_id uuid not null references auth.users(id) on delete cascade,
  ticker text not null,
  display_name text not null
    check (char_length(btrim(display_name)) between 2 and 40),
  joined_at timestamptz not null default now(),
  primary key (user_id, ticker),
  constraint stock_research_memberships_ticker_format
    check (ticker ~ '^[A-Z][A-Z0-9.]{0,9}$')
);

create table public.research_tasks (
  id uuid not null default gen_random_uuid() primary key,
  ticker text not null references public.stocks(ticker),
  research_area text not null,
  research_question text not null,
  status text not null default 'open'::text
    constraint research_tasks_status_check
    check (status in ('open', 'claimed', 'completed', 'cancelled')),
  assigned_agent text,
  claimed_until timestamptz,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  claimed_session_id uuid references public.agent_sessions(id),
  claimed_owner_id uuid references auth.users(id) on delete set null
);

create table public.commons_research_findings (
  id uuid not null default gen_random_uuid() primary key,
  task_id uuid not null
    references public.research_tasks(id) on delete restrict,
  ticker text not null,
  research_area text not null,
  contributor_id uuid not null
    references auth.users(id) on delete restrict,
  contributor_alias text not null
    check (char_length(contributor_alias) between 2 and 40),
  summary text not null
    check (char_length(btrim(summary)) between 40 and 700),
  source_urls jsonb not null
    check (
      jsonb_typeof(source_urls) = 'array'
      and jsonb_array_length(source_urls) between 1 and 5
    ),
  limitations text not null default ''::text
    check (char_length(limitations) <= 400),
  observed_at timestamptz not null,
  published_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '30 days')
);

-- SECTION 2 — Non-constraint indexes
-- Primary-key and unique-constraint indexes are created by SECTION 1 and are
-- not repeated here.

create index agent_sessions_lease_idx
  on public.agent_sessions using btree (lease_expires_at)
  where status = any (array['pending'::text, 'connected'::text]);

create unique index one_connected_session_per_agent
  on public.agent_sessions using btree (agent_profile_id)
  where status = 'connected'::text;

create index commons_findings_expiration_idx
  on public.commons_research_findings using btree (expires_at);

create index commons_findings_owner_recent_idx
  on public.commons_research_findings using btree
    (contributor_id, task_id, published_at desc);

create index commons_findings_public_idx
  on public.commons_research_findings using btree (ticker, published_at desc);

create index commons_tasks_owner_lease_idx
  on public.research_tasks using btree (claimed_owner_id, claimed_until)
  where claimed_owner_id is not null;

create index research_tasks_claimed_session_idx
  on public.research_tasks using btree (claimed_session_id);

create index research_tasks_ticker_status_idx
  on public.research_tasks using btree (ticker, status);

create index stock_research_memberships_ticker_idx
  on public.stock_research_memberships using btree (ticker, joined_at);

-- SECTION 3 — RLS policies
-- RLS is enabled but not forced on each of the six production tables.

alter table public.agent_profiles enable row level security;
alter table public.agent_sessions enable row level security;
alter table public.commons_research_findings enable row level security;
alter table public.research_tasks enable row level security;
alter table public.stock_research_memberships enable row level security;
alter table public.stocks enable row level security;

create policy "Owners manage their agent profiles"
  on public.agent_profiles for all to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

create policy "Owners view their agent sessions"
  on public.agent_sessions for select to authenticated
  using (
    exists (
      select 1
      from public.agent_profiles p
      where p.id = agent_sessions.agent_profile_id
        and p.owner_id = (select auth.uid())
    )
  );

create policy "Public can read unexpired research"
  on public.commons_research_findings for select to anon, authenticated
  using (expires_at > now());

create policy "Public can view research tasks"
  on public.research_tasks for select to anon, authenticated
  using (true);

create policy "Participants may join a listed stock"
  on public.stock_research_memberships for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (
      select 1 from public.stocks s
      where s.ticker = stock_research_memberships.ticker
    )
  );

create policy "Participants may leave their own stock"
  on public.stock_research_memberships for delete to authenticated
  using (user_id = (select auth.uid()));

create policy "Participants may see research team"
  on public.stock_research_memberships for select to authenticated
  using (true);

create policy "Public can read stocks"
  on public.stocks for select to anon, authenticated
  using (true);

-- SECTION 4 — Effective anon/authenticated privileges
-- Reset only these client roles and PUBLIC for these six objects, then grant
-- the verified effective privileges. In particular, task DML stays unavailable
-- to authenticated; finding contributor_id stays unreadable; and opted_in is
-- not directly updateable by authenticated.

revoke select, insert, update, delete on table
  public.agent_profiles,
  public.agent_sessions,
  public.commons_research_findings,
  public.research_tasks,
  public.stock_research_memberships,
  public.stocks
from public, anon, authenticated;

revoke select (
  id, owner_id, display_name, opted_in, created_at
) on table public.agent_profiles from public, anon, authenticated;
revoke insert (
  id, owner_id, display_name, opted_in, created_at
) on table public.agent_profiles from public, anon, authenticated;
revoke update (
  id, owner_id, display_name, opted_in, created_at
) on table public.agent_profiles from public, anon, authenticated;
revoke references (
  id, owner_id, display_name, opted_in, created_at
) on table public.agent_profiles from public, anon, authenticated;
revoke select (
  id, agent_profile_id, status, connected_at, last_heartbeat_at,
  lease_expires_at, disconnected_at, created_at
) on table public.agent_sessions from public, anon, authenticated;
revoke insert (
  id, agent_profile_id, status, connected_at, last_heartbeat_at,
  lease_expires_at, disconnected_at, created_at
) on table public.agent_sessions from public, anon, authenticated;
revoke update (
  id, agent_profile_id, status, connected_at, last_heartbeat_at,
  lease_expires_at, disconnected_at, created_at
) on table public.agent_sessions from public, anon, authenticated;
revoke references (
  id, agent_profile_id, status, connected_at, last_heartbeat_at,
  lease_expires_at, disconnected_at, created_at
) on table public.agent_sessions from public, anon, authenticated;
revoke select (
  id, task_id, ticker, research_area, contributor_id, contributor_alias,
  summary, source_urls, limitations, observed_at, published_at, expires_at
) on table public.commons_research_findings from public, anon, authenticated;
revoke insert (
  id, task_id, ticker, research_area, contributor_id, contributor_alias,
  summary, source_urls, limitations, observed_at, published_at, expires_at
) on table public.commons_research_findings from public, anon, authenticated;
revoke update (
  id, task_id, ticker, research_area, contributor_id, contributor_alias,
  summary, source_urls, limitations, observed_at, published_at, expires_at
) on table public.commons_research_findings from public, anon, authenticated;
revoke references (
  id, task_id, ticker, research_area, contributor_id, contributor_alias,
  summary, source_urls, limitations, observed_at, published_at, expires_at
) on table public.commons_research_findings from public, anon, authenticated;
revoke select (
  id, ticker, research_area, research_question, status, assigned_agent,
  claimed_until, created_at, updated_at, claimed_session_id, claimed_owner_id
) on table public.research_tasks from public, anon, authenticated;
revoke insert (
  id, ticker, research_area, research_question, status, assigned_agent,
  claimed_until, created_at, updated_at, claimed_session_id, claimed_owner_id
) on table public.research_tasks from public, anon, authenticated;
revoke update (
  id, ticker, research_area, research_question, status, assigned_agent,
  claimed_until, created_at, updated_at, claimed_session_id, claimed_owner_id
) on table public.research_tasks from public, anon, authenticated;
revoke references (
  id, ticker, research_area, research_question, status, assigned_agent,
  claimed_until, created_at, updated_at, claimed_session_id, claimed_owner_id
) on table public.research_tasks from public, anon, authenticated;
revoke select (
  user_id, ticker, display_name, joined_at
) on table public.stock_research_memberships from public, anon, authenticated;
revoke insert (
  user_id, ticker, display_name, joined_at
) on table public.stock_research_memberships from public, anon, authenticated;
revoke update (
  user_id, ticker, display_name, joined_at
) on table public.stock_research_memberships from public, anon, authenticated;
revoke references (
  user_id, ticker, display_name, joined_at
) on table public.stock_research_memberships from public, anon, authenticated;
revoke select (
  ticker, company_name, created_at
) on table public.stocks from public, anon, authenticated;
revoke insert (
  ticker, company_name, created_at
) on table public.stocks from public, anon, authenticated;
revoke update (
  ticker, company_name, created_at
) on table public.stocks from public, anon, authenticated;
revoke references (
  ticker, company_name, created_at
) on table public.stocks from public, anon, authenticated;

grant select, insert, delete on table public.agent_profiles to authenticated;
grant update (display_name) on table public.agent_profiles to authenticated;

grant select on table public.agent_sessions to authenticated;

grant select (
  id,
  task_id,
  ticker,
  research_area,
  contributor_alias,
  summary,
  source_urls,
  limitations,
  observed_at,
  published_at,
  expires_at
) on table public.commons_research_findings to anon, authenticated;

grant select on table public.research_tasks to anon, authenticated;

grant select, insert, delete
  on table public.stock_research_memberships to authenticated;

grant select on table public.stocks to anon, authenticated;

-- SECTION 5 — Existing lifecycle RPCs (owner-supplied body transcription)
-- The following four definitions are based on the owner-supplied pg_get_
-- functiondef text, reformatted for readability in the evidence attachment.
-- They have not been independently compared byte-for-byte with production.
-- Validate the exact saved source and complete ACL before installation. Their
-- reported owner is postgres, SECURITY DEFINER is true, search_path is empty,
-- authenticated can execute, and anon cannot execute. No replacement
-- authorization behavior has been designed here.

create or replace function public.commons_claim_next(p_ticker text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_user uuid := auth.uid();
  v_id uuid;
  v_task public.research_tasks%rowtype;
begin
  if v_user is null then
    raise exception 'Sign in required' using errcode = '42501';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_user::text, 0)
  );

  if not exists (
    select 1 from public.stock_research_memberships m
    where m.user_id = v_user and m.ticker = upper(btrim(p_ticker))
  ) then
    raise exception 'Join this stock team first' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.agent_profiles p
    where p.owner_id = v_user and p.opted_in is true
  ) then
    raise exception 'Owner research permission is OFF or agent profile is missing'
      using errcode = '42501';
  end if;

  select * into v_task
  from public.research_tasks
  where ticker = upper(btrim(p_ticker))
    and status = 'claimed'
    and claimed_owner_id = v_user
    and claimed_until > now()
  order by claimed_until desc limit 1;

  if found then
    return jsonb_build_object(
      'id', v_task.id,
      'ticker', v_task.ticker,
      'research_area', v_task.research_area,
      'research_question', v_task.research_question,
      'claimed_until', v_task.claimed_until,
      'already_claimed', true
    );
  end if;

  select t.id into v_id
  from public.research_tasks t
  where t.ticker = upper(btrim(p_ticker))
    and (
      t.status in ('open', 'complete')
      or (t.status = 'claimed'
          and (t.claimed_until is null or t.claimed_until <= now()))
    )
    and not exists (
      select 1 from public.commons_research_findings f
      where f.task_id = t.id
        and f.contributor_id = v_user
        and f.published_at > now() - interval '12 hours'
    )
  order by
    case
      when t.status = 'open' then 0
      when t.status = 'claimed' then 1
      else 2
    end,
    t.updated_at asc,
    t.id
  for update of t skip locked
  limit 1;

  if v_id is null then
    raise exception 'No available assignment. Please try later';
  end if;

  return public.commons_claim_task(v_id);
end;
$function$;

create or replace function public.commons_claim_task(p_task_id uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_user uuid := auth.uid();
  v_task public.research_tasks%rowtype;
  v_alias text;
begin
  if v_user is null then
    raise exception 'Sign in required' using errcode = '42501';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_user::text, 0)
  );

  select m.display_name into v_alias
  from public.stock_research_memberships m
  join public.research_tasks t on t.ticker = m.ticker
  where m.user_id = v_user and t.id = p_task_id;

  if v_alias is null then
    raise exception 'Join this stock team first' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.agent_profiles p
    where p.owner_id = v_user and p.opted_in is true
  ) then
    raise exception 'Owner research permission is OFF or agent profile is missing'
      using errcode = '42501';
  end if;

  select * into v_task
  from public.research_tasks
  where id = p_task_id
  for update;

  if not found then
    raise exception 'Assignment not found';
  end if;

  if v_task.status = 'claimed'
    and v_task.claimed_owner_id = v_user
    and v_task.claimed_until > now() then
    return jsonb_build_object(
      'id', v_task.id, 'ticker', v_task.ticker,
      'research_area', v_task.research_area,
      'research_question', v_task.research_question,
      'claimed_until', v_task.claimed_until,
      'already_claimed', true
    );
  end if;

  if v_task.status = 'claimed' and v_task.claimed_until > now() then
    raise exception 'Another researcher currently holds this assignment';
  end if;

  if v_task.status not in ('open', 'complete', 'claimed') then
    raise exception 'This assignment is not available';
  end if;

  if exists (
    select 1 from public.research_tasks t
    where t.claimed_owner_id = v_user
      and t.status = 'claimed'
      and t.claimed_until > now()
  ) then
    raise exception 'Finish or release your current assignment first';
  end if;

  if exists (
    select 1 from public.commons_research_findings f
    where f.task_id = p_task_id
      and f.contributor_id = v_user
      and f.published_at > now() - interval '12 hours'
  ) then
    raise exception 'You already submitted this metric recently; choose another';
  end if;

  update public.research_tasks
  set status = 'claimed',
      claimed_owner_id = v_user,
      claimed_session_id = null,
      assigned_agent = v_alias,
      claimed_until = now() + interval '30 minutes',
      updated_at = now()
  where id = p_task_id
  returning * into v_task;

  return jsonb_build_object(
    'id', v_task.id,
    'ticker', v_task.ticker,
    'research_area', v_task.research_area,
    'research_question', v_task.research_question,
    'claimed_until', v_task.claimed_until,
    'already_claimed', false
  );
end;
$function$;

create or replace function public.commons_publish_finding(
  p_task_id uuid,
  p_summary text,
  p_source_urls jsonb,
  p_observed_at timestamp with time zone,
  p_limitations text default ''::text
)
 returns uuid
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_user uuid := auth.uid();
  v_task public.research_tasks%rowtype;
  v_alias text;
  v_source jsonb;
  v_id uuid;
begin
  if v_user is null then
    raise exception 'Sign in required' using errcode = '42501';
  end if;

  select * into v_task
  from public.research_tasks
  where id = p_task_id
  for update;

  if not found
    or v_task.status <> 'claimed'
    or v_task.claimed_owner_id is distinct from v_user
    or v_task.claimed_until <= now()
    or v_task.claimed_until is null then
    raise exception 'An unexpired assignment claim belonging to you is required';
  end if;

  select m.display_name into v_alias
  from public.stock_research_memberships m
  where m.user_id = v_user and m.ticker = v_task.ticker;

  if v_alias is null then
    raise exception 'Team membership required' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.agent_profiles p
    where p.owner_id = v_user and p.opted_in is true
  ) then
    raise exception 'Owner permission is OFF' using errcode = '42501';
  end if;

  if p_summary is null
    or char_length(btrim(p_summary)) not between 40 and 700 then
    raise exception 'Summary must contain 40 to 700 characters';
  end if;

  if p_source_urls is null
    or jsonb_typeof(p_source_urls) <> 'array'
    or jsonb_array_length(p_source_urls) not between 1 and 5 then
    raise exception 'Provide 1 to 5 source links';
  end if;

  for v_source in select value from jsonb_array_elements(p_source_urls) loop
    if jsonb_typeof(v_source) <> 'string'
      or char_length(v_source #>> '{}') > 500
      or (v_source #>> '{}') !~* '^https?://[^[:space:]/]+(/[^[:space:]]*)?$' then
      raise exception 'Sources must be valid http(s) URLs up to 500 characters';
    end if;
  end loop;

  if p_observed_at is null
    or p_observed_at > now() + interval '5 minutes'
    or p_observed_at < now() - interval '30 days' then
    raise exception 'Evidence observation time must be within the last 30 days';
  end if;

  if char_length(coalesce(p_limitations, '')) > 400 then
    raise exception 'Limitations must be at most 400 characters';
  end if;

  insert into public.commons_research_findings (
    task_id, ticker, research_area, contributor_id, contributor_alias,
    summary, source_urls, observed_at, limitations
  ) values (
    v_task.id, v_task.ticker, v_task.research_area, v_user, v_alias,
    btrim(p_summary), p_source_urls, p_observed_at, coalesce(p_limitations, '')
  ) returning id into v_id;

  update public.research_tasks
  set status = 'completed',
      claimed_owner_id = null,
      claimed_session_id = null,
      claimed_until = null,
      assigned_agent = v_alias,
      updated_at = now()
  where id = p_task_id;

  return v_id;
end;
$function$;

create or replace function public.commons_release_task(p_task_id uuid)
 returns boolean
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_user uuid := auth.uid();
  v_task public.research_tasks%rowtype;
  v_has_findings boolean;
begin
  if v_user is null then
    raise exception 'Sign in required' using errcode = '42501';
  end if;

  select * into v_task
  from public.research_tasks
  where id = p_task_id
  for update;

  if not found
    or v_task.claimed_owner_id is distinct from v_user
    or v_task.status <> 'claimed' then
    raise exception 'You do not hold this assignment';
  end if;

  select exists (
    select 1 from public.commons_research_findings
    where task_id = p_task_id
  ) into v_has_findings;

  update public.research_tasks
  set status = case
        when v_has_findings then 'complete'
        else 'open'
      end,
      claimed_owner_id = null,
      claimed_session_id = null,
      claimed_until = null,
      assigned_agent = null,
      updated_at = now()
  where id = p_task_id;

  return true;
end;
$function$;

alter function public.commons_claim_next(text) owner to postgres;
alter function public.commons_claim_task(uuid) owner to postgres;
alter function public.commons_publish_finding(uuid, text, jsonb, timestamptz, text)
  owner to postgres;
alter function public.commons_release_task(uuid) owner to postgres;

revoke all on function public.commons_claim_next(text) from public, anon;
revoke all on function public.commons_claim_task(uuid) from public, anon;
revoke all on function
  public.commons_publish_finding(uuid, text, jsonb, timestamptz, text)
  from public, anon;
revoke all on function public.commons_release_task(uuid) from public, anon;

grant execute on function public.commons_claim_next(text) to authenticated;
grant execute on function public.commons_claim_task(uuid) to authenticated;
grant execute on function
  public.commons_publish_finding(uuid, text, jsonb, timestamptz, text)
  to authenticated;
grant execute on function public.commons_release_task(uuid) to authenticated;

create or replace function public.commons_my_claim(p_ticker text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_user uuid := auth.uid();
  v_task public.research_tasks%rowtype;
begin
  if v_user is null then
    return null;
  end if;

  select * into v_task
    from public.research_tasks
   where ticker = upper(btrim(p_ticker))
     and status = 'claimed'
     and claimed_owner_id = v_user
     and claimed_until > now()
   order by claimed_until desc
   limit 1;

  if not found then
    return null;
  end if;

  return jsonb_build_object(
    'id', v_task.id,
    'ticker', v_task.ticker,
    'research_area', v_task.research_area,
    'research_question', v_task.research_question,
    'claimed_until', v_task.claimed_until
  );
end;
$function$;

alter function public.commons_my_claim(text) owner to postgres;
revoke all on function public.commons_my_claim(text) from public, anon;
grant execute on function public.commons_my_claim(text) to authenticated;

-- Remaining dependencies before a faithful staging test:
-- 1. The five user-supplied bodies are readable transcriptions. Verify the four
--    earlier RPC bodies against their saved full pg_get_functiondef output
--    before treating this draft as installable. commons_my_claim was supplied
--    as whitespace-normalized source.
-- 2. The evidence reports postgres ownership, SECURITY DEFINER, empty
--    search_path, authenticated EXECUTE, and no anon EXECUTE for all five
--    functions. Exact raw ACL/grantor metadata was not supplied; the explicit
--    grants here preserve the reported effective client boundary.
-- 3. One existing production trigger is confirmed: commons_owner_opt_out_release
--    is AFTER UPDATE OF opted_in on public.agent_profiles and calls
--    commons_release_on_opt_out(), owned by postgres. Its exact function body
--    and security settings/ACL are still required before faithful staging
--    installation/testing. Inspect its compatibility with the lineage guard,
--    especially when it releases unfinished tasks. The focused read-only query
--    is in ORCA_PHASE_2_STAGING_DEPENDENCY_QUERY.sql. Other non-internal
--    triggers, if any, are not reported in the evidence provided so far.
-- 4. The five research RPC bodies depend only on auth.uid(), PostgreSQL
--    built-ins, and the included commons_claim_task call. No additional custom
--    helper is apparent in the supplied bodies. Do not recreate auth.uid() or
--    auth.users.
-- 5. For end-to-end agent-session/pairing tests (not needed for isolated
--    research-task claim/publish tests), the repository UI also calls
--    start_session, heartbeat_session, and stop_all_sessions, and invokes the
--    agent-control, agent-session, agent-pairing, agent-pair-complete, and
--    agent-gateway Supabase Edge Functions. Their deployed definitions and
--    dependencies are not in this repository; obtain only the functions
--    exercised by the planned session/pairing test. The research RPCs
--    themselves use agent_sessions only through task FK/claimed_session_id
--    metadata and do not call these session functions.
-- 6. Scheduled finding cleanup is not required to install the research
--    lifecycle baseline or run immediate claim/publish tests. It is required
--    evidence only for expiry/retention behavior. The supplied expires_at
--    default and RLS visibility check do not establish deletion behavior.
--
-- Do not rerun completed column, constraint, index, RLS, or privilege checks.
-- Finding expiry/cleanup jobs are a separate retention concern: expires_at and
-- its RLS policy control visibility but do not establish row deletion. Do not
-- change or promise retention behavior without that separate evidence.
--
-- Lifecycle cautions from the supplied digest:
-- * research_tasks permits open, claimed, completed, cancelled only.
-- * The retrieved claim bodies contain the invalid literal 'complete'. Preserve
--   the exact captured definitions for review. Do NOT replace this with
--   'completed' in claim eligibility; completed tasks must remain terminal.
-- * commons_release_task also attempts to set 'complete' when a finding exists,
--   which violates the status constraint. PHASE_2_RELEASE_STATUS_FIX.sql is a
--   separate guarded staging-only correction to that release branch. It must
--   be reviewed and, if approved, used only after installing the exact function
--   in isolated staging. It is not included or executed here.
--
-- SECTION 6 — Phase 2 proposal and staging-only test gate
-- PHASE_2_RENEWAL_PROPOSED.sql remains design-only. Reconcile it with this
-- verified baseline and the exact RPC/trigger dependencies before appending
-- its reviewed sections. Do not modify production, copy production rows, or
-- run any SQL until the complete installer and tests have been reviewed.
