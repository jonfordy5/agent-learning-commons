-- READ-ONLY PREFLIGHT — no writes, DDL, grants, or transaction control.
-- Run only after confirming Supabase project vbziibatnejoswsdggga
-- (jonfordy5/orca-staging). PostgreSQL catalogs do not prove project identity.
-- Paste back every result set, including empty results. Do not include secrets.

-- RESULT 1 — Reserved Phase 2 test profile and RKLB fixture readiness.
with expected_profiles(display_name) as (
  values
    ('ORCA Test Researcher 1'::text),
    ('ORCA Test Researcher 2'::text)
),
profile_matches as (
  select
    expected.display_name,
    count(profile.owner_id) as profile_count,
    count(distinct profile.owner_id) as distinct_owner_count,
    bool_and(profile.opted_in)
      filter (where profile.owner_id is not null) as opted_in,
    bool_and(auth_user.id is not null)
      filter (where profile.owner_id is not null) as auth_user_exists,
    bool_and(membership.user_id is not null)
      filter (where profile.owner_id is not null) as rklb_member
  from expected_profiles expected
  left join public.agent_profiles profile
    on profile.display_name = expected.display_name
  left join auth.users auth_user
    on auth_user.id = profile.owner_id
  left join public.stock_research_memberships membership
    on membership.user_id = profile.owner_id
   and membership.ticker = 'RKLB'
  group by expected.display_name
)
select
  'RESULT 1 - test fixture readiness' as result_section,
  display_name,
  profile_count,
  distinct_owner_count,
  opted_in,
  auth_user_exists,
  rklb_member,
  profile_count = 1
    and distinct_owner_count = 1
    and coalesce(opted_in, false)
    and coalesce(auth_user_exists, false)
    and coalesce(rklb_member, false) as ready
from profile_matches
order by display_name;

-- RESULT 2 — Existing research baseline. Counts only; no finding content or IDs.
select
  'RESULT 2 - RKLB baseline counts' as result_section,
  (select count(*) from public.stocks stock where stock.ticker = 'RKLB')
    as rklb_stock_rows,
  (select count(*) from public.research_tasks task where task.ticker = 'RKLB')
    as rklb_assignment_rows,
  (select count(*) from public.commons_research_findings finding where finding.ticker = 'RKLB')
    as rklb_finding_rows,
  (select count(*) from public.commons_research_findings finding
    where finding.ticker = 'RKLB' and finding.expires_at > now())
    as rklb_unexpired_finding_rows;

-- RESULT 3 — Required objects, proposed objects, handle index, and core functions.
select
  'RESULT 3 - installation state' as result_section,
  to_regclass('public.stocks') is not null as stocks_table_present,
  to_regclass('public.agent_profiles') is not null as profiles_table_present,
  to_regclass('public.stock_research_memberships') is not null as memberships_table_present,
  to_regclass('public.research_tasks') is not null as assignments_table_present,
  to_regclass('public.commons_research_findings') is not null as findings_table_present,
  to_regclass('public.commons_market_outlooks') is not null as outlook_table_installed,
  to_regprocedure('public.commons_set_my_research_consent(boolean)') is not null
    as consent_rpc_present,
  to_regprocedure('auth.uid()') is not null as auth_uid_function_present,
  to_regprocedure('gen_random_uuid()') is not null as uuid_generator_present,
  to_regprocedure('public.commons_publish_finding(uuid,text,jsonb,timestamp with time zone,text)')
    is not null as publish_finding_rpc_present,
  to_regprocedure(
    'public.commons_submit_market_outlook(text,text,text,uuid[],jsonb,timestamp with time zone,text,text)'
  ) is not null as outlook_rpc_installed,
  exists (
    select 1
      from pg_catalog.pg_constraint constraint_data
      join pg_catalog.pg_class relation
        on relation.oid = constraint_data.conrelid
      join pg_catalog.pg_namespace relation_schema
        on relation_schema.oid = relation.relnamespace
     where relation_schema.nspname = 'public'
       and relation.relname = 'commons_research_findings'
       and constraint_data.conname = 'commons_research_findings_contributor_alias_handle_check'
       and constraint_data.contype = 'c'
  ) as widened_finding_alias_constraint_present,
  exists (
    select 1
      from pg_catalog.pg_index index_data
      join pg_catalog.pg_class index_relation
        on index_relation.oid = index_data.indexrelid
      join pg_catalog.pg_class profile_table
        on profile_table.oid = index_data.indrelid
      join pg_catalog.pg_namespace profile_schema
        on profile_schema.oid = profile_table.relnamespace
     where profile_schema.nspname = 'public'
       and profile_table.relname = 'agent_profiles'
       and index_relation.relname = 'agent_profiles_display_name_handle_key'
       and index_data.indisunique
       and index_data.indisvalid
       and pg_catalog.strpos(
         pg_catalog.lower(pg_catalog.pg_get_indexdef(index_data.indexrelid)),
         'lower(btrim(display_name))'
       ) > 0
  ) as unique_profile_handle_index_present;

-- RESULT 4 — Columns used by the proposal and current schema.
select
  'RESULT 4 - relevant columns' as result_section,
  table_name,
  column_name,
  data_type,
  udt_name,
  is_nullable,
  character_maximum_length,
  column_default
from information_schema.columns
where table_schema = 'public'
  and table_name in (
    'stocks',
    'agent_profiles',
    'stock_research_memberships',
    'research_tasks',
    'commons_research_findings',
    'commons_market_outlooks'
  )
order by table_name, ordinal_position;

-- RESULT 5 — Keys, checks, and foreign-key dependencies; no row identifiers.
select
  'RESULT 5 - constraints and dependencies' as result_section,
  relation.relname as table_name,
  constraint_data.conname as constraint_name,
  constraint_data.contype as constraint_type,
  referenced.relname as referenced_table,
  pg_catalog.pg_get_constraintdef(constraint_data.oid, true) as definition
from pg_catalog.pg_constraint constraint_data
join pg_catalog.pg_class relation
  on relation.oid = constraint_data.conrelid
join pg_catalog.pg_namespace relation_schema
  on relation_schema.oid = relation.relnamespace
left join pg_catalog.pg_class referenced
  on referenced.oid = constraint_data.confrelid
where relation_schema.nspname = 'public'
  and (
    relation.relname in (
      'stocks',
      'agent_profiles',
      'stock_research_memberships',
      'research_tasks',
      'commons_research_findings',
      'commons_market_outlooks'
    )
    or referenced.relname in (
      'stocks',
      'agent_profiles',
      'stock_research_memberships',
      'research_tasks',
      'commons_research_findings',
      'commons_market_outlooks'
    )
  )
order by relation.relname, constraint_data.conname;

-- RESULT 6 — RLS status and all policies on the dependent tables.
select
  'RESULT 6 - RLS and policies' as result_section,
  relation.relname as table_name,
  relation.relrowsecurity as rls_enabled,
  relation.relforcerowsecurity as rls_forced,
  policy.policyname,
  policy.permissive,
  policy.roles,
  policy.cmd,
  policy.qual,
  policy.with_check
from pg_catalog.pg_class relation
join pg_catalog.pg_namespace relation_schema
  on relation_schema.oid = relation.relnamespace
left join pg_catalog.pg_policies policy
  on policy.schemaname = relation_schema.nspname
 and policy.tablename = relation.relname
where relation_schema.nspname = 'public'
  and relation.relname in (
    'stocks',
    'agent_profiles',
    'stock_research_memberships',
    'research_tasks',
    'commons_research_findings',
    'commons_market_outlooks'
  )
order by relation.relname, policy.policyname;

-- RESULT 7 — Effective table privileges for anon and authenticated.
with relations(table_name) as (
  values
    ('stocks'::text),
    ('agent_profiles'::text),
    ('stock_research_memberships'::text),
    ('research_tasks'::text),
    ('commons_research_findings'::text),
    ('commons_market_outlooks'::text)
),
client_roles(role_name) as (
  values ('anon'::text), ('authenticated'::text)
),
privileges(privilege_name) as (
  values ('SELECT'::text), ('INSERT'::text), ('UPDATE'::text), ('DELETE'::text)
)
select
  'RESULT 7 - table privileges' as result_section,
  client_roles.role_name,
  relations.table_name,
  privileges.privilege_name,
  case
    when pg_catalog.to_regclass(pg_catalog.format('public.%I', relations.table_name)) is null
      then null
    else pg_catalog.has_table_privilege(
      client_roles.role_name,
      pg_catalog.format('public.%I', relations.table_name),
      privileges.privilege_name
    )
  end as granted
from relations
cross join client_roles
cross join privileges
order by relations.table_name, client_roles.role_name, privileges.privilege_name;

-- RESULT 8 — Effective column privileges for identity and evidence columns.
with requested_columns(table_name, column_name) as (
  values
    ('agent_profiles'::text, 'owner_id'::text),
    ('agent_profiles', 'display_name'),
    ('agent_profiles', 'opted_in'),
    ('stock_research_memberships', 'user_id'),
    ('stock_research_memberships', 'ticker'),
    ('commons_research_findings', 'id'),
    ('commons_research_findings', 'contributor_id'),
    ('commons_research_findings', 'contributor_alias'),
    ('commons_research_findings', 'ticker'),
    ('commons_research_findings', 'expires_at'),
    ('commons_market_outlooks', 'researcher_id'),
    ('commons_market_outlooks', 'researcher_alias')
),
client_roles(role_name) as (
  values ('anon'::text), ('authenticated'::text)
),
column_privileges(privilege_name) as (
  values
    ('SELECT'::text),
    ('INSERT'::text),
    ('UPDATE'::text),
    ('REFERENCES'::text)
)
select
  'RESULT 8 - column privileges' as result_section,
  client_roles.role_name,
  requested_columns.table_name,
  requested_columns.column_name,
  column_privileges.privilege_name,
  case
    when not exists (
      select 1
        from information_schema.columns column_data
       where column_data.table_schema = 'public'
         and column_data.table_name = requested_columns.table_name
         and column_data.column_name = requested_columns.column_name
    ) then null
    else pg_catalog.has_column_privilege(
      client_roles.role_name,
      pg_catalog.format('public.%I', requested_columns.table_name),
      requested_columns.column_name,
      column_privileges.privilege_name
    )
  end as granted
from requested_columns
cross join client_roles
cross join column_privileges
order by
  requested_columns.table_name,
  requested_columns.column_name,
  client_roles.role_name,
  column_privileges.privilege_name;

-- RESULT 9 — Security settings and grants for existing/proposed RPCs.
select
  'RESULT 9 - RPC security and grants' as result_section,
  routine.proname as function_name,
  pg_catalog.oidvectortypes(routine.proargtypes) as argument_types,
  routine.prosecdef as security_definer,
  routine.proconfig as function_settings,
  pg_catalog.pg_get_userbyid(routine.proowner) as owner_name,
  case when routine.proname = 'commons_publish_finding'
    then pg_catalog.strpos(pg_catalog.lower(routine.prosrc), 'agent_profiles') > 0
    else null
  end as publish_finding_reads_profile_handle,
  case when routine.proname = 'commons_publish_finding'
    then pg_catalog.strpos(pg_catalog.lower(routine.prosrc), 'm.display_name') > 0
    else null
  end as publish_finding_uses_membership_name,
  pg_catalog.has_function_privilege('anon', routine.oid, 'EXECUTE') as anon_can_execute,
  pg_catalog.has_function_privilege('authenticated', routine.oid, 'EXECUTE')
    as authenticated_can_execute
from pg_catalog.pg_proc routine
join pg_catalog.pg_namespace routine_schema
  on routine_schema.oid = routine.pronamespace
where routine_schema.nspname = 'public'
  and routine.proname in (
    'commons_create_my_agent_profile',
    'commons_set_my_research_consent',
    'commons_publish_finding',
    'commons_submit_market_outlook'
  )
order by routine.proname, argument_types;

-- RESULT 10 — Existing duplicate normalized profile handles. Names only; no IDs.
select
  'RESULT 10 - duplicate normalized profile handles' as result_section,
  pg_catalog.lower(pg_catalog.btrim(display_name)) as normalized_handle,
  count(*) as profile_count
from public.agent_profiles
group by pg_catalog.lower(pg_catalog.btrim(display_name))
having count(*) > 1
order by normalized_handle;

-- RESULT 11 — Existing profiles matching recognizable/test handles. Names only.
with expected_handles(handle) as (
  values
    ('alys ai'::text),
    ('Aly''s AI'::text),
    ('orca test researcher 1'::text),
    ('orca test researcher 2'::text)
)
select
  'RESULT 11 - requested handle ownership counts' as result_section,
  expected.handle as requested_handle,
  count(profile.owner_id) as matching_profile_count,
  min(profile.display_name) as stored_display_name
from expected_handles expected
left join public.agent_profiles profile
  on pg_catalog.lower(pg_catalog.btrim(profile.display_name))
     = pg_catalog.lower(pg_catalog.btrim(expected.handle))
group by expected.handle
order by expected.handle;

-- RESULT 12 — Existing profile handles that need cleanup before the constraint.
select
  'RESULT 12 - invalid handle values' as result_section,
  count(*) filter (
    where display_name <> pg_catalog.btrim(display_name)
       or pg_catalog.char_length(pg_catalog.btrim(display_name)) not between 1 and 60
  ) as invalid_handle_count
from public.agent_profiles;

-- RESULT 13 — Existing finding aliases must remain valid under the widened
-- 1-to-60-character snapshot constraint. This checks without changing rows.
select
  'RESULT 13 - finding attribution compatibility' as result_section,
  count(*) as existing_finding_rows,
  count(*) filter (
    where contributor_alias is null
       or contributor_alias <> pg_catalog.btrim(contributor_alias)
       or pg_catalog.char_length(pg_catalog.btrim(contributor_alias))
          not between 1 and 60
  ) as aliases_incompatible_with_proposed_constraint
from public.commons_research_findings;
