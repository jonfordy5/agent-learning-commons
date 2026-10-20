-- Read-only gate for ORCA_PHASE_2_AUTHENTICATED_INTEGRATION_TEST.mjs.
-- Run only in Orca-staging immediately before the authenticated integration test.
-- Expected research-data counts are zero; fixture prerequisites are nonzero.
-- This script does not modify data.

select 'RKLB tasks' as fixture, count(*) as row_count
  from public.research_tasks
 where ticker = 'RKLB'
union all
select 'RKLB findings', count(*)
  from public.commons_research_findings
 where ticker = 'RKLB'
union all
select 'RKLB metric series', count(*)
  from public.commons_research_series
 where ticker = 'RKLB'
union all
select 'RKLB request ledger', count(*)
  from public.commons_research_requests
 where ticker = 'RKLB'
union all
select 'RKLB stock row', count(*)
  from public.stocks
 where ticker = 'RKLB'
union all
select 'Active SEC filings metric', count(*)
  from public.commons_research_metric_catalog
 where category_key = 'sec'
   and metric_key = 'sec.filings_catalysts'
   and active
union all
select 'Opted-in named researcher profiles', count(*)
  from public.agent_profiles
 where display_name in ('ORCA Test Researcher 1', 'ORCA Test Researcher 2')
   and opted_in
union all
select 'Named researchers with RKLB membership', count(*)
  from public.agent_profiles p
  join public.stock_research_memberships m on m.user_id = p.owner_id
 where p.display_name in ('ORCA Test Researcher 1', 'ORCA Test Researcher 2')
   and p.opted_in
   and m.ticker = 'RKLB'
order by fixture;
