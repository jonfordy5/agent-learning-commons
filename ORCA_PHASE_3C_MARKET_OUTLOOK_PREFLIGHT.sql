-- Read-only prerequisite query for the proposed ORCA Market Outlook migration.
-- Run only after confirming the Supabase dashboard/API URL is project
-- vbziibatnejoswsdggga (jonfordy5/orca-staging). PostgreSQL catalogs do not
-- independently prove the Supabase project reference.
-- Run as a trusted staging operator. This query does not change database state.
-- Requires the two reserved Phase 2 test profiles and RKLB fixtures.

-- Test identity and fixture readiness. Each expected profile must resolve
-- exactly once to an existing Auth user and RKLB research membership.
with expected_profiles(display_name) as (
  values
    ('ORCA Test Researcher 1'::text),
    ('ORCA Test Researcher 2'::text)
),
profile_matches as (
  select
    e.display_name,
    count(p.owner_id) as profile_count,
    count(distinct p.owner_id) as distinct_owner_count,
    bool_and(p.opted_in) filter (where p.owner_id is not null) as opted_in,
    bool_and(u.id is not null) filter (where p.owner_id is not null) as auth_user_exists,
    bool_and(m.user_id is not null) filter (where p.owner_id is not null) as rklb_member
  from expected_profiles e
  left join public.agent_profiles p
    on p.display_name = e.display_name
  left join auth.users u
    on u.id = p.owner_id
  left join public.stock_research_memberships m
    on m.user_id = p.owner_id
   and m.ticker = 'RKLB'
  group by e.display_name
)
select
  display_name,
  profile_count,
  distinct_owner_count,
  opted_in,
  auth_user_exists,
  rklb_member,
  profile_count = 1
    and distinct_owner_count = 1
    and coalesce(auth_user_exists, false)
    and coalesce(rklb_member, false) as ready
from profile_matches
order by display_name;

-- Baseline state for comparison after any separately approved staging test.
select
  (select count(*) from public.stocks s where s.ticker = 'RKLB') as rklb_stock_rows,
  (select count(*) from public.research_tasks t where t.ticker = 'RKLB') as rklb_assignment_rows,
  (select count(*) from public.commons_research_findings f where f.ticker = 'RKLB') as rklb_finding_rows,
  (select count(*) from public.commons_research_findings f
    where f.ticker = 'RKLB' and f.expires_at > now()) as rklb_unexpired_finding_rows;

-- Phase 2 / 3A prerequisites and Phase 3C installation state.
select
  to_regclass('public.stocks') is not null as stocks_table_present,
  to_regclass('public.agent_profiles') is not null as profiles_table_present,
  to_regclass('public.stock_research_memberships') is not null as memberships_table_present,
  to_regclass('public.research_tasks') is not null as assignments_table_present,
  to_regclass('public.commons_research_findings') is not null as findings_table_present,
  to_regprocedure('public.commons_set_my_research_consent(boolean)') is not null as consent_rpc_present,
  to_regclass('public.commons_market_outlooks') is not null as outlook_table_installed,
  to_regprocedure(
    'public.commons_submit_market_outlook(text,text,text,uuid[],jsonb,timestamp with time zone,text,text)'
  ) is not null as outlook_rpc_installed;
