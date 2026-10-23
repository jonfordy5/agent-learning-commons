-- READ-ONLY preflight for the proposed ORCA Phase 3A profile/consent migration.
-- Run only in the Orca-staging SQL Editor after confirming project ref
-- vbziibatnejoswsdggga in the dashboard. This is one SELECT and makes no changes.

with inspection as (
  select
    'context'::text as section,
    current_database()::text as object_name,
    pg_catalog.jsonb_build_object(
      'current_user', current_user,
      'server_version', pg_catalog.current_setting('server_version')
    ) as details

  union all

  select
    'table'::text,
    pg_catalog.format('%I.%I', n.nspname, c.relname),
    pg_catalog.jsonb_build_object(
      'rls_enabled', c.relrowsecurity,
      'rls_forced', c.relforcerowsecurity,
      'raw_acl', c.relacl,
      'authenticated_table_insert', pg_catalog.has_table_privilege('authenticated', c.oid, 'INSERT'),
      'authenticated_table_update', pg_catalog.has_table_privilege('authenticated', c.oid, 'UPDATE'),
      'authenticated_columns', (
        select pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            'column', a.attname,
            'select', pg_catalog.has_column_privilege('authenticated', c.oid, a.attname, 'SELECT'),
            'insert', pg_catalog.has_column_privilege('authenticated', c.oid, a.attname, 'INSERT'),
            'update', pg_catalog.has_column_privilege('authenticated', c.oid, a.attname, 'UPDATE')
          ) order by a.attnum
        )
        from pg_catalog.pg_attribute a
        where a.attrelid = c.oid
          and a.attnum > 0
          and not a.attisdropped
      )
    )
  from pg_catalog.pg_class c
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname in ('agent_profiles', 'agent_sessions', 'research_tasks', 'commons_research_findings')

  union all

  select
    'policy'::text,
    pg_catalog.format('%I.%I.%I', n.nspname, c.relname, p.polname),
    pg_catalog.jsonb_build_object(
      'permissive', p.polpermissive,
      'command', p.polcmd,
      'roles', p.polroles,
      'using', pg_catalog.pg_get_expr(p.polqual, p.polrelid),
      'with_check', pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid)
    )
  from pg_catalog.pg_policy p
  join pg_catalog.pg_class c on c.oid = p.polrelid
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname in ('agent_profiles', 'agent_sessions', 'research_tasks', 'commons_research_findings')

  union all

  select
    'function'::text,
    pg_catalog.format('%I.%I(%s)', n.nspname, p.proname, pg_catalog.pg_get_function_identity_arguments(p.oid)),
    pg_catalog.jsonb_build_object(
      'owner', pg_catalog.pg_get_userbyid(p.proowner),
      'security_definer', p.prosecdef,
      'settings', p.proconfig,
      'raw_acl', p.proacl,
      'authenticated_execute', pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE'),
      'anon_execute', pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE'),
      'definition', pg_catalog.pg_get_functiondef(p.oid)
    )
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in (
      'commons_create_my_agent_profile',
      'commons_set_my_research_consent',
      'commons_claim_next',
      'commons_claim_task',
      'commons_publish_finding',
      'commons_release_task',
      'commons_my_claim',
      'commons_release_on_opt_out'
    )

  union all

  select
    'trigger'::text,
    pg_catalog.format('%I.%I.%I', n.nspname, c.relname, t.tgname),
    pg_catalog.jsonb_build_object(
      'enabled', t.tgenabled,
      'definition', pg_catalog.pg_get_triggerdef(t.oid, true),
      'function_owner', pg_catalog.pg_get_userbyid(f.proowner),
      'function_security_definer', f.prosecdef,
      'function_settings', f.proconfig,
      'function_acl', f.proacl,
      'function_definition', pg_catalog.pg_get_functiondef(f.oid)
    )
  from pg_catalog.pg_trigger t
  join pg_catalog.pg_class c on c.oid = t.tgrelid
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
  join pg_catalog.pg_proc f on f.oid = t.tgfoid
  where n.nspname = 'public'
    and c.relname in ('agent_profiles', 'research_tasks')
    and not t.tgisinternal
)
select section, object_name, details
from inspection
order by section, object_name;
