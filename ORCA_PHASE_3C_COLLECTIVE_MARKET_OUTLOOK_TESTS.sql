-- PROPOSAL ONLY — do not execute without separate approval.
-- Run only in isolated ORCA staging after explicit approval of
-- ORCA_PHASE_3C_COLLECTIVE_MARKET_OUTLOOK_PROPOSED.sql.
-- Uses the Phase 2 dedicated RKLB test researchers. All synthetic rows,
-- temporary membership-alias changes, and consent changes roll back. Existing
-- assignments and findings are read only.

begin;

do $preflight$
declare
  v_user_a uuid;
  v_user_b uuid;
  v_function record;
  v_policy_expression text;
begin
  if current_user <> 'postgres' then
    raise exception 'Run this staging test as postgres';
  end if;

  select p.owner_id into strict v_user_a
    from public.agent_profiles p
   where p.display_name = 'ORCA Test Researcher 1'
     and p.opted_in is true;
  select p.owner_id into strict v_user_b
    from public.agent_profiles p
   where p.display_name = 'ORCA Test Researcher 2'
   and p.opted_in is true;

  if v_user_a = v_user_b then
    raise exception 'The two staging test researchers must have different owners';
  end if;
  if not exists (
       select 1 from public.stock_research_memberships m
        where m.user_id = v_user_a and m.ticker = 'RKLB'
     )
     or not exists (
       select 1 from public.stock_research_memberships m
        where m.user_id = v_user_b and m.ticker = 'RKLB'
     ) then
    raise exception 'Both test researchers must have RKLB membership';
  end if;
  if not exists (select 1 from public.stocks s where s.ticker = 'RKLB') then
    raise exception 'RKLB stock fixture is missing';
  end if;
  if not exists (
    select 1
      from auth.users u
     where u.id = v_user_a
  ) or not exists (
    select 1
      from auth.users u
     where u.id = v_user_b
  ) then
    raise exception 'Both dedicated test profiles must reference existing Auth users';
  end if;
  if not exists (
    select 1
      from pg_catalog.pg_class c
      join pg_catalog.pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
       and c.relname = 'commons_market_outlooks'
       and c.relrowsecurity
  ) then
    raise exception 'RLS must be enabled on the outlook table';
  end if;
  select pg_catalog.lower(pg_catalog.pg_get_expr(p.polqual, p.polrelid))
    into strict v_policy_expression
    from pg_catalog.pg_policy p
    join pg_catalog.pg_class c on c.oid = p.polrelid
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relname = 'commons_market_outlooks'
     and p.polname = 'Public can read unexpired market outlooks';
  if pg_catalog.strpos(v_policy_expression, 'expires_at') = 0
     or pg_catalog.strpos(v_policy_expression, 'now') = 0 then
    raise exception 'Public outlook policy must enforce the existing expiration boundary';
  end if;
  if pg_catalog.has_column_privilege(
       'anon', 'public.commons_market_outlooks', 'researcher_id', 'SELECT'
     ) or pg_catalog.has_column_privilege(
       'authenticated', 'public.commons_market_outlooks', 'researcher_id', 'SELECT'
     ) or not pg_catalog.has_column_privilege(
       'anon', 'public.commons_market_outlooks', 'researcher_alias', 'SELECT'
     ) or not pg_catalog.has_column_privilege(
       'authenticated', 'public.commons_market_outlooks', 'researcher_alias', 'SELECT'
     ) then
    raise exception 'Clients may read pseudonymous attribution but not Auth user IDs';
  end if;
  if pg_catalog.has_table_privilege(
       'authenticated', 'public.commons_market_outlooks', 'INSERT'
     ) or pg_catalog.has_table_privilege(
       'authenticated', 'public.commons_market_outlooks', 'UPDATE'
     ) or pg_catalog.has_table_privilege(
       'authenticated', 'public.commons_market_outlooks', 'DELETE'
     ) then
    raise exception 'Authenticated clients must not write outlook rows directly';
  end if;
  if pg_catalog.has_function_privilege(
       'anon',
       'public.commons_submit_market_outlook(text,text,text,uuid[],jsonb,timestamptz,text,text)',
       'EXECUTE'
     ) or not pg_catalog.has_function_privilege(
       'authenticated',
       'public.commons_submit_market_outlook(text,text,text,uuid[],jsonb,timestamptz,text,text)',
       'EXECUTE'
     ) then
    raise exception 'Outlook RPC grants are incorrect';
  end if;
  select p.proargnames, p.pronargs, p.prosecdef, p.proconfig, p.prosrc,
         pg_catalog.pg_get_userbyid(p.proowner) as owner_name
    into strict v_function
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname = 'commons_submit_market_outlook';
  if v_function.pronargs <> 8
     or v_function.proargnames is distinct from array[
       'p_ticker', 'p_stance', 'p_reasoning', 'p_supporting_finding_ids',
       'p_evidence_urls', 'p_observed_at', 'p_investment_timeframe',
       'p_invalidation_condition'
     ]::text[]
     or not v_function.prosecdef
     or v_function.owner_name <> 'postgres'
     or not coalesce(v_function.proconfig @> array['search_path=""'], false)
     or pg_catalog.strpos(pg_catalog.lower(v_function.prosrc), 'for share') = 0
     or pg_catalog.strpos(pg_catalog.lower(v_function.prosrc), 'for share')
        > pg_catalog.strpos(pg_catalog.lower(v_function.prosrc), 'insert into public.commons_market_outlooks') then
    raise exception 'RPC must be owner-owned SECURITY DEFINER with an empty search_path and no caller-selected identity';
  end if;

  perform pg_catalog.set_config('orca.test.outlook_user_a', v_user_a::text, true);
  perform pg_catalog.set_config('orca.test.outlook_user_b', v_user_b::text, true);
  update public.stock_research_memberships
     set display_name = 'ORCA Impersonation Probe'
   where user_id = v_user_a
     and ticker = 'RKLB';
end;
$preflight$;

set local role authenticated;

do $authorized_tests$
declare
  v_user_a uuid := current_setting('orca.test.outlook_user_a')::uuid;
  v_user_b uuid := current_setting('orca.test.outlook_user_b')::uuid;
  v_outlook_id uuid;
  v_second_outlook_id uuid;
  v_exposed_id uuid;
  v_author_alias text;
  v_expires_at timestamptz;
  v_perspective_count bigint;
  v_failed boolean;
begin
  perform pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
  perform pg_catalog.set_config('request.jwt.claim.sub', v_user_a::text, true);
  v_outlook_id := public.commons_submit_market_outlook(
    'RKLB', 'bullish',
    'This speculative test interpretation is grounded in a supplied source URL, states uncertainty, and is not a prediction or trade instruction.',
    '{}'::uuid[], '["https://www.sec.gov/"]'::jsonb, now(),
    'Next two quarters',
    'This view is invalidated if subsequent filings contradict the cited operating evidence.'
  );
  select o.researcher_alias, o.expires_at
    into strict v_author_alias, v_expires_at
    from public.commons_market_outlooks o
   where o.id = v_outlook_id;
  if v_author_alias is distinct from 'R-' || pg_catalog.md5(v_user_a::text)
     or v_author_alias = 'ORCA Impersonation Probe'
     or v_expires_at <= now()
     or v_expires_at > now() + interval '30 days' then
    raise exception 'Owner-derived alias or the expected unexpired outlook window is incorrect';
  end if;
  perform pg_catalog.set_config('orca.test.outlook_id_a', v_outlook_id::text, true);

  v_failed := false;
  begin
    select o.researcher_id into strict v_exposed_id
      from public.commons_market_outlooks o
     where o.id = v_outlook_id;
  exception when insufficient_privilege then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'Authenticated client unexpectedly read the private Auth user ID';
  end if;

  v_failed := false;
  begin
    insert into public.commons_market_outlooks (
      ticker, researcher_id, researcher_alias, stance, reasoning,
      observed_at, investment_timeframe, invalidation_condition
    ) values (
      'RKLB', v_user_b, 'Forged', 'bullish',
      'This is a direct insert attempt that must be denied by grants and RLS.',
      now(), 'Next quarter', 'A direct write must not be possible for clients.'
    );
  exception when insufficient_privilege then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'Direct outlook INSERT unexpectedly succeeded';
  end if;

  v_failed := false;
  begin
    update public.commons_market_outlooks
       set stance = 'neutral'
     where id = v_outlook_id;
  exception when insufficient_privilege then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'Direct outlook UPDATE unexpectedly succeeded';
  end if;

  v_failed := false;
  begin
    delete from public.commons_market_outlooks
     where id = v_outlook_id;
  exception when insufficient_privilege then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'Direct outlook DELETE unexpectedly succeeded';
  end if;

  perform pg_catalog.set_config('request.jwt.claim.sub', v_user_b::text, true);
  perform public.commons_set_my_research_consent(false);

  v_failed := false;
  begin
    perform public.commons_submit_market_outlook(
      'RKLB', 'neutral',
      'An unauthorized speculative interpretation must not be accepted without owner approval.',
      '{}'::uuid[], '["https://www.sec.gov/"]'::jsonb, now(),
      'Next quarter',
      'The view is invalidated when the underlying public evidence changes.'
    );
  exception when insufficient_privilege then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'Outlook submission unexpectedly succeeded while owner consent was OFF';
  end if;

  perform public.commons_set_my_research_consent(true);
  v_second_outlook_id := public.commons_submit_market_outlook(
    'RKLB', 'bearish',
    'This distinct speculative test view uses independent reasoning and must remain alongside another researcher’s interpretation.',
    '{}'::uuid[], '["https://www.sec.gov/"]'::jsonb, now(),
    'Next two quarters',
    'This separate view is invalidated if its cited evidence no longer applies.'
  );
  select o.researcher_alias into strict v_author_alias
    from public.commons_market_outlooks o
   where o.id = v_second_outlook_id;
  if v_author_alias is distinct from 'R-' || pg_catalog.md5(v_user_b::text) then
    raise exception 'Second researcher attribution must derive from the authenticated owner';
  end if;
  select pg_catalog.count(*)
    into v_perspective_count
    from public.commons_market_outlooks o
   where o.id in (v_outlook_id, v_second_outlook_id);
  if v_perspective_count <> 2
     or not exists (
       select 1 from public.commons_market_outlooks o
        where o.id = v_outlook_id
          and o.researcher_alias = 'R-' || pg_catalog.md5(v_user_a::text)
          and o.stance = 'bullish'
     )
     or not exists (
       select 1 from public.commons_market_outlooks o
        where o.id = v_second_outlook_id
          and o.researcher_alias = 'R-' || pg_catalog.md5(v_user_b::text)
          and o.stance = 'bearish'
     ) then
    raise exception 'A second researcher must not overwrite the first interpretation';
  end if;
  perform pg_catalog.set_config('orca.test.outlook_id_b', v_second_outlook_id::text, true);

  perform pg_catalog.set_config('request.jwt.claim.sub', v_user_a::text, true);
  v_failed := false;
  begin
    perform public.commons_submit_market_outlook(
      'RKLB', 'neutral',
      'Invalid evidence references must be rejected before an outlook can be published.',
      array[gen_random_uuid()]::uuid[], '[]'::jsonb, now(),
      'Next quarter',
      'The view is invalidated when the underlying public evidence changes.'
    );
  exception when invalid_parameter_value then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'Unknown supporting finding ID unexpectedly succeeded';
  end if;

  perform pg_catalog.set_config('request.jwt.claim.sub', '', true);
  v_failed := false;
  begin
    perform public.commons_submit_market_outlook(
      'RKLB', 'bearish',
      'An unauthenticated speculative interpretation must not be accepted.',
      '{}'::uuid[], '["https://example.com/evidence"]'::jsonb, now(),
      'Next quarter',
      'The view is invalidated when the underlying public evidence changes.'
    );
  exception when insufficient_privilege then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'Unauthenticated outlook submission unexpectedly succeeded';
  end if;
end;
$authorized_tests$;

reset role;

do $stored_attribution_tests$
declare
  v_user_a uuid := current_setting('orca.test.outlook_user_a')::uuid;
  v_user_b uuid := current_setting('orca.test.outlook_user_b')::uuid;
  v_id_a uuid := current_setting('orca.test.outlook_id_a')::uuid;
  v_id_b uuid := current_setting('orca.test.outlook_id_b')::uuid;
begin
  if not exists (
    select 1 from public.commons_market_outlooks o
     where o.id = v_id_a
       and o.researcher_id = v_user_a
       and o.researcher_alias = 'R-' || pg_catalog.md5(v_user_a::text)
  ) or not exists (
    select 1 from public.commons_market_outlooks o
     where o.id = v_id_b
       and o.researcher_id = v_user_b
       and o.researcher_alias = 'R-' || pg_catalog.md5(v_user_b::text)
  ) then
    raise exception 'Stored owner IDs and public aliases must match authenticated owners';
  end if;
end;
$stored_attribution_tests$;

rollback;
