-- AI Stock Commons Phase 2: read-only Supabase preflight.
-- Run this before reviewing or applying PHASE_2_RENEWAL_PROPOSED.sql.
-- Inspect output privately; function definitions and role names are database metadata.

-- Relevant table columns, types, nullability, and defaults.
select table_name, ordinal_position, column_name, data_type, udt_name,
       is_nullable, column_default
from information_schema.columns
where table_schema = 'public'
  and table_name in (
    'research_tasks', 'commons_research_findings',
    'stock_research_memberships', 'agent_profiles',
    'commons_research_series', 'commons_research_requests',
    'commons_research_metric_catalog'
  )
order by table_name, ordinal_position;

-- Constraints and indexes, including any existing lineage/deduplication protections.
select c.relname as table_name, con.conname as constraint_name,
       con.contype as constraint_type,
       pg_catalog.pg_get_constraintdef(con.oid) as constraint_definition
from pg_catalog.pg_constraint con
join pg_catalog.pg_class c on c.oid = con.conrelid
join pg_catalog.pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in (
    'research_tasks', 'commons_research_findings',
    'commons_research_series', 'commons_research_requests',
    'commons_research_metric_catalog'
  )
order by c.relname, con.contype, con.conname;

select tablename, indexname, indexdef
from pg_catalog.pg_indexes
where schemaname = 'public'
  and tablename in (
    'research_tasks', 'commons_research_findings',
    'commons_research_series', 'commons_research_requests',
    'commons_research_metric_catalog'
  )
order by tablename, indexname;

-- RLS state, policies, table grants, and triggers on the affected tables.
select c.relname as table_name, c.relrowsecurity as rls_enabled,
       c.relforcerowsecurity as rls_forced
from pg_catalog.pg_class c
join pg_catalog.pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in (
    'research_tasks', 'commons_research_findings',
    'commons_research_series', 'commons_research_requests',
    'commons_research_metric_catalog'
  );

select schemaname, tablename, policyname, permissive, roles,
       cmd, qual, with_check
from pg_catalog.pg_policies
where schemaname = 'public'
  and tablename in (
    'research_tasks', 'commons_research_findings',
    'commons_research_series', 'commons_research_requests',
    'commons_research_metric_catalog'
  )
order by tablename, policyname;

select grantee, table_name, privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
  and table_name in (
    'research_tasks', 'commons_research_findings',
    'commons_research_series', 'commons_research_requests',
    'commons_research_metric_catalog'
  )
order by table_name, grantee, privilege_type;

select grantee, table_name, column_name, privilege_type
from information_schema.column_privileges
where table_schema = 'public'
  and table_name = 'research_tasks'
order by table_name, column_name, grantee, privilege_type;

select event_object_table as table_name, trigger_name, action_timing,
       event_manipulation, action_statement
from information_schema.triggers
where event_object_schema = 'public'
  and event_object_table in (
    'research_tasks', 'commons_research_findings',
    'commons_research_series', 'commons_research_requests',
    'commons_research_metric_catalog'
  )
order by event_object_table, trigger_name, event_manipulation;

-- Exact existing RPC definitions, identity arguments, owner, SECURITY DEFINER,
-- configured search_path, and execute grants. Review every authorization check
-- before any CREATE OR REPLACE of an existing function.
select p.proname, pg_catalog.pg_get_function_identity_arguments(p.oid) as arguments,
       r.rolname as owner, p.prosecdef as security_definer,
       p.proconfig as function_settings,
       pg_catalog.pg_get_functiondef(p.oid) as definition
from pg_catalog.pg_proc p
join pg_catalog.pg_namespace n on n.oid = p.pronamespace
join pg_catalog.pg_roles r on r.oid = p.proowner
where n.nspname = 'public'
  and p.proname in (
    'commons_claim_task', 'commons_claim_next', 'commons_my_claim',
    'commons_release_task', 'commons_publish_finding',
    'commons_create_or_renew_research', 'commons_bootstrap_legacy_research_task',
    'commons_enforce_research_task_lineage'
  )
order by p.proname, arguments;

select routine_name, specific_name, grantee, privilege_type
from information_schema.routine_privileges
where specific_schema = 'public'
  and routine_name in (
    'commons_claim_task', 'commons_claim_next', 'commons_my_claim',
    'commons_release_task', 'commons_publish_finding',
    'commons_create_or_renew_research', 'commons_bootstrap_legacy_research_task',
    'commons_enforce_research_task_lineage'
  )
order by routine_name, specific_name, grantee, privilege_type;

-- Current finding counts and expiration distribution. This does not modify data.
select count(*) as finding_count,
       count(*) filter (where expires_at is null) as no_expiry_count,
       count(*) filter (where expires_at <= now()) as expired_count,
       count(*) filter (where expires_at > now()) as future_expiry_count,
       min(published_at) as oldest_published_at,
       max(published_at) as newest_published_at
from public.commons_research_findings;

select ticker, count(*) as finding_count,
       count(*) filter (where expires_at <= now()) as expired_count,
       min(published_at) as oldest_published_at,
       max(published_at) as newest_published_at
from public.commons_research_findings
group by ticker
order by ticker;

-- Search database routine bodies for task writers and findings cleanup/expiry logic.
select n.nspname, p.proname,
       pg_catalog.pg_get_function_identity_arguments(p.oid) as arguments,
       r.rolname as owner, p.prosecdef as security_definer,
       pg_catalog.pg_get_functiondef(p.oid) as definition
from pg_catalog.pg_proc p
join pg_catalog.pg_namespace n on n.oid = p.pronamespace
join pg_catalog.pg_roles r on r.oid = p.proowner
where p.prosrc ilike '%research_tasks%'
  or p.prosrc ilike '%commons_research_findings%'
   or p.prosrc ilike '%expires_at%'
order by n.nspname, p.proname, arguments;

-- pg_cron jobs are emitted as NOTICE output when the extension is installed.
-- Also inspect any Supabase Dashboard scheduled functions/external schedulers;
-- they are not necessarily represented in pg_cron.
do $$
declare
  jobs text;
begin
  if pg_catalog.to_regclass('cron.job') is null then
    raise notice 'cron.job is not installed/visible in this database';
    return;
  end if;

  execute $query$
    select string_agg(
      format('jobid=%s schedule=%s active=%s command=%s',
             jobid, schedule, active, command), E'\n'
      order by jobid
    )
    from cron.job
    where command ilike '%commons_research_findings%'
       or command ilike '%expires_at%'
       or command ilike '%research_tasks%'
  $query$ into jobs;

  raise notice 'Matching pg_cron jobs:%', coalesce(E'\n' || jobs, ' none');
end
$$;