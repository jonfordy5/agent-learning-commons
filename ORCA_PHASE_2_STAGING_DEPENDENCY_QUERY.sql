-- ORCA Phase 2: focused, read-only trigger-function dependency query.
-- Run against production only as a metadata query; this script reads no user
-- rows and makes no changes. It retrieves the exact reported trigger and its
-- function definition/security metadata. Do not rerun the completed table/
-- constraint/index/RLS/grant audit.

select c.relname as table_name,
       t.tgname as trigger_name,
       pg_catalog.pg_get_triggerdef(t.oid, true) as trigger_definition,
       p.proname as trigger_function,
       pg_catalog.pg_get_userbyid(p.proowner) as function_owner,
       p.prosecdef as security_definer,
       p.proconfig as function_settings,
       p.proacl as function_acl,
       pg_catalog.pg_get_functiondef(p.oid) as function_definition
from pg_catalog.pg_trigger t
join pg_catalog.pg_class c on c.oid = t.tgrelid
join pg_catalog.pg_namespace n on n.oid = c.relnamespace
join pg_catalog.pg_proc p on p.oid = t.tgfoid
where n.nspname = 'public'
  and c.relname = 'agent_profiles'
  and t.tgname = 'commons_owner_opt_out_release'
  and not t.tgisinternal;

-- If this returns no rows, the reported trigger name/table did not resolve in
-- that database. Do not broaden the query automatically. The trigger function
-- body, owner, SECURITY DEFINER flag, search_path, and ACL are returned above.
