-- AI Stock Commons Phase 2: separately reviewable release-status correction.
-- STAGING ONLY. Do not execute against production.
-- Reconstructs the exact installed commons_release_task(uuid) definition and
-- changes only: WHEN v_has_findings THEN 'complete'
-- to:           WHEN v_has_findings THEN 'completed'
-- Owner, SECURITY DEFINER, search_path, ACL, and all other function logic must
-- remain exactly as installed. The transaction aborts if the expected text is
-- absent/duplicated or if security metadata changes.

begin;

do $$
declare
  v_function_oid oid := 'public.commons_release_task(uuid)'::regprocedure;
  v_definition text;
  v_updated_definition text;
  v_old_branch constant text := 'WHEN v_has_findings THEN ''complete''';
  v_new_branch constant text := 'WHEN v_has_findings THEN ''completed''';
  v_before_owner text;
  v_before_security_definer boolean;
  v_before_config text[];
  v_before_acl aclitem[];
  v_after_owner text;
  v_after_security_definer boolean;
  v_after_config text[];
  v_after_acl aclitem[];
begin
  select pg_catalog.pg_get_userbyid(p.proowner), p.prosecdef, p.proconfig, p.proacl,
         pg_catalog.pg_get_functiondef(p.oid)
    into v_before_owner, v_before_security_definer, v_before_config, v_before_acl,
         v_definition
    from pg_catalog.pg_proc p
   where p.oid = v_function_oid;

  if v_before_owner <> 'postgres' or not v_before_security_definer then
    raise exception 'Unexpected commons_release_task owner or SECURITY DEFINER setting';
  end if;

  if not case
    when v_before_config @> array['search_path='] then true
    when v_before_config @> array['search_path=""'] then true
    else false
  end then
    raise exception 'Unexpected commons_release_task search_path; review manually';
  end if;

  if (pg_catalog.length(v_definition)
      - pg_catalog.length(pg_catalog.replace(v_definition, v_old_branch, '')))
      / pg_catalog.length(v_old_branch) <> 1 then
    raise exception 'Expected exactly one invalid release status branch; no change applied';
  end if;

  v_updated_definition := pg_catalog.replace(v_definition, v_old_branch, v_new_branch);
  execute v_updated_definition;

  select pg_catalog.pg_get_userbyid(p.proowner), p.prosecdef, p.proconfig, p.proacl,
         pg_catalog.pg_get_functiondef(p.oid)
    into v_after_owner, v_after_security_definer, v_after_config, v_after_acl,
         v_definition
    from pg_catalog.pg_proc p
   where p.oid = v_function_oid;

  if v_after_owner is distinct from v_before_owner
     or v_after_security_definer is distinct from v_before_security_definer
     or v_after_config is distinct from v_before_config
     or v_after_acl is distinct from v_before_acl then
    raise exception 'Release function security metadata changed; transaction aborted';
  end if;

  if pg_catalog.strpos(v_definition, v_new_branch) = 0
     or pg_catalog.strpos(v_definition, v_old_branch) <> 0 then
    raise exception 'Release function body verification failed; transaction aborted';
  end if;
end
$$;

commit;