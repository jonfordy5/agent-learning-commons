-- ORCA staging-only security tests. Replace both placeholders with distinct
-- existing Auth user UUIDs for dedicated test accounts. Both accounts must
-- have no agent profile, active claim, or published finding before this test.
-- Run only in the isolated ORCA staging project after the migration is applied.
-- All profile writes are rolled back. Never use Aly's account or production.

begin;

do $preflight$
declare
  v_user_a uuid := 'dcd629f9-83de-4a17-9550-a3b44522caeb'::uuid;
  v_user_b uuid := 'ecab5e86-2c71-42f4-bb29-8979ee897331'::uuid;
  v_policy pg_catalog.pg_policy%rowtype;
  v_policy_expression text;
  v_trigger_function text;
  v_function record;
begin
  if v_user_a = v_user_b then
    raise exception 'Use two independent staging Auth users';
  end if;

  if not exists (select 1 from auth.users u where u.id = v_user_a)
     or not exists (select 1 from auth.users u where u.id = v_user_b) then
    raise exception 'Both test identities must already exist in staging Auth';
  end if;

  if exists (
    select 1 from public.agent_profiles p
     where p.owner_id in (v_user_a, v_user_b)
  ) or exists (
    select 1 from public.research_tasks t
     where t.claimed_owner_id in (v_user_a, v_user_b)
  ) or exists (
    select 1 from public.commons_research_findings f
     where f.contributor_id in (v_user_a, v_user_b)
  ) then
    raise exception 'Test identities already own profiles or research data; choose fresh test accounts';
  end if;

  if pg_catalog.has_table_privilege(
       'authenticated', 'public.agent_profiles', 'INSERT'
     ) or pg_catalog.has_table_privilege(
       'authenticated', 'public.agent_profiles', 'UPDATE'
     ) or pg_catalog.has_column_privilege(
       'authenticated', 'public.agent_profiles', 'opted_in', 'INSERT'
     ) or pg_catalog.has_column_privilege(
       'authenticated', 'public.agent_profiles', 'opted_in', 'UPDATE'
     ) or pg_catalog.has_column_privilege(
       'authenticated', 'public.agent_profiles', 'owner_id', 'UPDATE'
     ) then
    raise exception 'Authenticated clients can still directly set consent or change profile ownership';
  end if;
  if not pg_catalog.has_column_privilege(
       'authenticated', 'public.agent_profiles', 'owner_id', 'INSERT'
     ) or not pg_catalog.has_column_privilege(
       'authenticated', 'public.agent_profiles', 'display_name', 'INSERT'
     ) or not pg_catalog.has_column_privilege(
       'authenticated', 'public.agent_profiles', 'display_name', 'UPDATE'
     ) then
    raise exception 'Expected limited profile creation/name-edit grants are missing';
  end if;

  if not pg_catalog.has_function_privilege(
       'authenticated', 'public.commons_create_my_agent_profile(text)', 'EXECUTE'
     ) or not pg_catalog.has_function_privilege(
       'authenticated', 'public.commons_set_my_research_consent(boolean)', 'EXECUTE'
     ) then
    raise exception 'Authenticated RPC execution grants are missing';
  end if;
  if pg_catalog.has_function_privilege(
       'anon', 'public.commons_create_my_agent_profile(text)', 'EXECUTE'
     ) or pg_catalog.has_function_privilege(
       'anon', 'public.commons_set_my_research_consent(boolean)', 'EXECUTE'
     ) then
    raise exception 'Anonymous RPC execution must be denied';
  end if;
  for v_function in
    select p.proname,
           p.prosrc,
           p.proargnames,
           p.pronargs,
           p.prosecdef,
           p.proconfig,
           pg_catalog.pg_get_userbyid(p.proowner) as owner_name
      from pg_catalog.pg_proc p
      join pg_catalog.pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in (
         'commons_create_my_agent_profile',
         'commons_set_my_research_consent'
       )
  loop
    if not v_function.prosecdef
       or v_function.owner_name <> 'postgres'
       or not coalesce(v_function.proconfig @> array['search_path=""'], false) then
      raise exception 'RPC SECURITY DEFINER owner or empty search_path is unsafe';
    end if;
    if v_function.proname = 'commons_create_my_agent_profile'
       and (
         v_function.pronargs <> 1
         or v_function.proargnames is distinct from array['p_display_name']::text[]
         or pg_catalog.strpos(v_function.prosrc, 'auth.uid()') = 0
         or pg_catalog.strpos(v_function.prosrc, 'false') = 0
       ) then
      raise exception 'Profile RPC must derive its sole owner from auth.uid() and insert opted_out';
    end if;
    if v_function.proname = 'commons_set_my_research_consent'
       and (
         v_function.pronargs <> 1
         or v_function.proargnames is distinct from array['p_opted_in']::text[]
         or pg_catalog.strpos(v_function.prosrc, 'auth.uid()') = 0
         or pg_catalog.strpos(v_function.prosrc, 'p.owner_id = v_user_id') = 0
       ) then
      raise exception 'Consent RPC must accept only a consent value and update the authenticated owner';
    end if;
  end loop;

  select p.* into strict v_policy
    from pg_catalog.pg_policy p
    join pg_catalog.pg_class c on c.oid = p.polrelid
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relname = 'agent_profiles'
     and p.polname = 'ORCA profiles start owner-scoped and opted out';
  v_policy_expression := pg_catalog.lower(
    pg_catalog.pg_get_expr(v_policy.polwithcheck, v_policy.polrelid)
  );
  if v_policy.polpermissive
     or v_policy.polcmd <> 'a'
     or pg_catalog.strpos(v_policy_expression, 'opted_in') = 0
     or pg_catalog.strpos(v_policy_expression, 'auth.uid') = 0
     or pg_catalog.strpos(v_policy_expression, 'false') = 0 then
    raise exception 'Restrictive opted-out, owner-scoped INSERT policy is missing';
  end if;

  select pg_catalog.pg_get_functiondef(t.tgfoid)
    into v_trigger_function
    from pg_catalog.pg_trigger t
    join pg_catalog.pg_class c on c.oid = t.tgrelid
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relname = 'agent_profiles'
     and t.tgname = 'commons_owner_opt_out_release'
     and not t.tgisinternal;
  if v_trigger_function is null
     or pg_catalog.strpos(pg_catalog.lower(v_trigger_function), 'old.opted_in is true') = 0
     or pg_catalog.strpos(pg_catalog.lower(v_trigger_function), 'new.opted_in is false') = 0
     or pg_catalog.strpos(v_trigger_function, 'commons_research_findings') = 0
     or pg_catalog.strpos(v_trigger_function, 'research_tasks') = 0
     or pg_catalog.strpos(pg_catalog.lower(v_trigger_function), '''completed''') = 0
     or pg_catalog.strpos(pg_catalog.lower(v_trigger_function), '''open''') = 0 then
    raise exception 'Existing opt-out task-release and finding-preservation trigger is missing or changed';
  end if;
end;
$preflight$;

set local role authenticated;

do $authorized_tests$
declare
  v_user_a uuid := 'dcd629f9-83de-4a17-9550-a3b44522caeb'::uuid;
  v_user_b uuid := 'ecab5e86-2c71-42f4-bb29-8979ee897331'::uuid;
  v_result jsonb;
  v_failed boolean;
  v_b_opted_in boolean;
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', v_user_a::text, true);

  v_result := public.commons_create_my_agent_profile('ORCA Test Researcher A');
  if v_result->>'opted_in' is distinct from 'false' then
    raise exception 'New profiles must always start opted out';
  end if;

  v_failed := false;
  begin
    insert into public.agent_profiles (owner_id, display_name, opted_in)
    values (v_user_a, 'Direct Opt-in Attempt', true);
  exception when insufficient_privilege then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'Direct opted_in INSERT unexpectedly succeeded';
  end if;

  v_failed := false;
  begin
    insert into public.agent_profiles (owner_id, display_name)
    values (v_user_b, 'Cross-owner Insert Attempt');
  exception when insufficient_privilege then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'Cross-owner profile INSERT unexpectedly succeeded';
  end if;

  v_failed := false;
  begin
    update public.agent_profiles set opted_in = true where owner_id = v_user_a;
  exception when insufficient_privilege then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'Direct opted_in UPDATE unexpectedly succeeded';
  end if;

  v_failed := false;
  begin
    update public.agent_profiles set owner_id = v_user_b where owner_id = v_user_a;
  exception when insufficient_privilege then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'Direct owner_id UPDATE unexpectedly succeeded';
  end if;

  v_result := public.commons_set_my_research_consent(true);
  if v_result->>'consent_enabled' is distinct from 'true' then
    raise exception 'Owner could not explicitly opt in through the RPC';
  end if;

  perform pg_catalog.set_config('request.jwt.claim.sub', v_user_b::text, true);
  v_result := public.commons_create_my_agent_profile('ORCA Test Researcher B');
  if v_result->>'opted_in' is distinct from 'false' then
    raise exception 'Second identity profile did not start opted out';
  end if;
  perform public.commons_set_my_research_consent(true);

  perform pg_catalog.set_config('request.jwt.claim.sub', v_user_a::text, true);
  v_result := public.commons_set_my_research_consent(false);
  if v_result->>'consent_enabled' is distinct from 'false' then
    raise exception 'Owner could not explicitly opt out through the RPC';
  end if;

  perform pg_catalog.set_config('request.jwt.claim.sub', v_user_b::text, true);
  select p.opted_in into strict v_b_opted_in
    from public.agent_profiles p
   where p.owner_id = v_user_b;
  if not v_b_opted_in then
    raise exception 'One researcher changed another researcher''s permission';
  end if;

  perform pg_catalog.set_config('request.jwt.claim.sub', '', true);
  v_failed := false;
  begin
    perform public.commons_create_my_agent_profile('Unauthenticated');
  exception when insufficient_privilege then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'Unauthenticated profile creation unexpectedly succeeded';
  end if;

  v_failed := false;
  begin
    perform public.commons_set_my_research_consent(false);
  exception when insufficient_privilege then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'Unauthenticated consent update unexpectedly succeeded';
  end if;
end;
$authorized_tests$;

rollback;
