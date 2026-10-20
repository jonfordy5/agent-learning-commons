-- ORCA Phase 2 staging-only opt-out trigger and renewal integration tests.
-- Run only in Orca-staging after both ORCA_PHASE_2_STAGING_FOUNDATION.sql and
-- PHASE_2_RENEWAL_PROPOSED.sql have been reviewed and installed. Run as
-- postgres. The script uses the existing opted-in profile named
-- "ORCA Test Researcher 1". Every write is rolled back.

begin;

do $$
declare
  v_owner_id uuid;
  v_profile_id uuid;
  v_trigger_function_oid oid :=
    'public.commons_release_on_opt_out()'::regprocedure;
  v_trigger_definition text;
  v_function_owner text;
  v_security_definer boolean;
  v_function_config text[];
  v_unfinished_series_id uuid;
  v_finding_series_id uuid;
  v_unfinished_task_id uuid;
  v_finding_task_id uuid;
  v_renewed_task_id uuid;
  v_finding_id uuid;
  v_result jsonb;
  v_finding_count bigint;
  v_finding_summary text;
  v_metric_count bigint;
  v_claim_rejected boolean;
  v_renewal_rejected boolean;
begin
  if current_user <> 'postgres' then
    raise exception 'Run this staging test as postgres';
  end if;

  select p.owner_id, p.id into strict v_owner_id, v_profile_id
    from public.agent_profiles p
   where p.display_name = 'ORCA Test Researcher 1'
     and p.opted_in is true;

  if exists (
    select 1
      from public.agent_profiles p
     where p.owner_id = v_owner_id
       and p.id <> v_profile_id
  ) then
    raise exception 'Trigger test profile owner has unexpected duplicate profiles';
  end if;

  select count(*) into v_metric_count
    from public.commons_research_metric_catalog c
   where c.active
     and (c.category_key, c.metric_key) in (
       ('sec', 'sec.filings_catalysts'),
       ('fundamentals', 'fundamentals.valuation')
     );
  if v_metric_count <> 2 then
    raise exception 'Required active staging metrics are missing';
  end if;

  select pg_catalog.pg_get_userbyid(p.proowner), p.prosecdef, p.proconfig
    into strict v_function_owner, v_security_definer, v_function_config
    from pg_catalog.pg_proc p
   where p.oid = v_trigger_function_oid;

  if v_function_owner <> 'postgres'
     or not v_security_definer
     or coalesce(
          v_function_config @> array['search_path=']
          or v_function_config @> array['search_path=""'],
          false
        ) is not true
     or pg_catalog.has_function_privilege('anon', v_trigger_function_oid, 'EXECUTE')
     or pg_catalog.has_function_privilege(
          'authenticated', v_trigger_function_oid, 'EXECUTE'
        ) then
    raise exception 'Opt-out trigger function security boundary is incorrect';
  end if;

  select pg_catalog.pg_get_triggerdef(t.oid, true)
    into strict v_trigger_definition
    from pg_catalog.pg_trigger t
    join pg_catalog.pg_class c on c.oid = t.tgrelid
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relname = 'agent_profiles'
     and t.tgname = 'commons_owner_opt_out_release'
     and not t.tgisinternal;

  if pg_catalog.strpos(v_trigger_definition, 'AFTER UPDATE OF opted_in') = 0
     or pg_catalog.strpos(
          v_trigger_definition,
          'commons_release_on_opt_out()'
        ) = 0 then
    raise exception 'Opt-out trigger event or function binding is incorrect';
  end if;

  if not exists (select 1 from public.stocks where ticker = 'ORCATSTG') then
    insert into public.stocks (ticker, company_name)
    values ('ORCATSTG', 'ORCA staging trigger fixture');
  else
    raise exception 'ORCATSTG fixture ticker already exists; choose a fresh staging fixture';
  end if;

  if exists (
    select 1
      from public.research_tasks t
     where t.claimed_owner_id = v_owner_id
       and t.status = 'claimed'
  ) then
    raise exception 'Dedicated trigger test user already has claimed tasks';
  end if;

  insert into public.stock_research_memberships (user_id, ticker, display_name)
  values (v_owner_id, 'ORCATSTG', 'ORCA staging test');

  insert into public.commons_research_series (
    ticker, category_key, metric_key, research_area, research_question, created_by
  )
  select 'ORCATSTG', c.category_key, c.metric_key,
         c.research_area, c.research_question, v_owner_id
    from public.commons_research_metric_catalog c
   where c.category_key = 'sec'
     and c.metric_key = 'sec.filings_catalysts'
     and c.active
  returning id into v_unfinished_series_id;

  insert into public.commons_research_series (
    ticker, category_key, metric_key, research_area, research_question, created_by
  )
  select 'ORCATSTG', c.category_key, c.metric_key,
         c.research_area, c.research_question, v_owner_id
    from public.commons_research_metric_catalog c
   where c.category_key = 'fundamentals'
     and c.metric_key = 'fundamentals.valuation'
     and c.active
  returning id into v_finding_series_id;

  insert into public.research_tasks (
    ticker, research_area, research_question, research_series_id
  )
  select s.ticker, s.research_area, s.research_question, s.id
    from public.commons_research_series s
   where s.id = v_unfinished_series_id
  returning id into v_unfinished_task_id;

  update public.commons_research_series
     set current_task_id = v_unfinished_task_id
   where id = v_unfinished_series_id;

  insert into public.research_tasks (
    ticker, research_area, research_question, research_series_id
  )
  select s.ticker, s.research_area, s.research_question, s.id
    from public.commons_research_series s
   where s.id = v_finding_series_id
  returning id into v_finding_task_id;

  update public.commons_research_series
     set current_task_id = v_finding_task_id
   where id = v_finding_series_id;

  update public.research_tasks
     set status = 'claimed',
         assigned_agent = 'ORCA staging test',
         claimed_owner_id = v_owner_id,
         claimed_until = pg_catalog.now() + interval '30 minutes'
   where id in (v_unfinished_task_id, v_finding_task_id);

  insert into public.commons_research_findings (
    task_id, ticker, research_area, contributor_id, contributor_alias,
    summary, source_urls, observed_at
  )
  select v_finding_task_id, s.ticker, s.research_area, v_owner_id,
         'ORCA staging test',
         'Synthetic staging finding used only to verify opt-out history retention.',
         pg_catalog.jsonb_build_array('https://example.com/orca-staging-test'),
         pg_catalog.now()
    from public.commons_research_series s
   where s.id = v_finding_series_id
  returning id into v_finding_id;

  update public.agent_profiles
     set opted_in = false
   where id = v_profile_id;

  if not exists (
    select 1
      from public.research_tasks t
     where t.id = v_unfinished_task_id
       and t.status = 'open'
       and t.claimed_owner_id is null
       and t.claimed_session_id is null
       and t.claimed_until is null
       and t.assigned_agent is null
  ) then
    raise exception 'Opt-out did not release an unfinished claim to open';
  end if;

  if not exists (
    select 1
      from public.research_tasks t
     where t.id = v_finding_task_id
       and t.status = 'completed'
       and t.claimed_owner_id is null
       and t.claimed_session_id is null
       and t.claimed_until is null
       and t.assigned_agent is null
  ) then
    raise exception 'Opt-out did not complete a claimed task with a finding';
  end if;

  select count(*), min(f.summary)
    into v_finding_count, v_finding_summary
    from public.commons_research_findings f
   where f.task_id = v_finding_task_id;

  if v_finding_count <> 1
     or v_finding_summary is distinct from
        'Synthetic staging finding used only to verify opt-out history retention.'
     or not exists (
       select 1 from public.commons_research_findings f where f.id = v_finding_id
     ) then
    raise exception 'Opt-out did not preserve the existing finding';
  end if;

  perform pg_catalog.set_config('request.jwt.claim.sub', v_owner_id::text, true);
  perform pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);

  v_claim_rejected := false;
  begin
    perform public.commons_claim_task(v_unfinished_task_id);
  exception when sqlstate '42501' then
    v_claim_rejected := true;
  end;
  if not v_claim_rejected then
    raise exception 'Opted-out researcher was able to claim an assignment';
  end if;

  v_renewal_rejected := false;
  begin
    perform public.commons_create_or_renew_research(
      'ORCATSTG',
      'sec',
      'sec.filings_catalysts',
      pg_catalog.gen_random_uuid(),
      null
    );
  exception when sqlstate '42501' then
    v_renewal_rejected := true;
  end;
  if not v_renewal_rejected then
    raise exception 'Opted-out researcher was able to request research';
  end if;

  -- Establish a claim while opted out so a repeated false -> false update
  -- proves the trigger function checks the transition, not just the new value.
  update public.research_tasks
     set status = 'claimed',
         assigned_agent = 'ORCA repeated opt-out test',
         claimed_owner_id = v_owner_id,
         claimed_until = pg_catalog.now() + interval '30 minutes'
   where id = v_unfinished_task_id;

  -- This still fires the UPDATE OF trigger; the transition guard must no-op.
  update public.agent_profiles
     set opted_in = false
   where id = v_profile_id;

  if not exists (
    select 1
      from public.research_tasks t
     where t.id = v_unfinished_task_id
       and t.status = 'claimed'
       and t.claimed_owner_id = v_owner_id
       and t.claimed_until is not null
       and t.assigned_agent = 'ORCA repeated opt-out test'
  ) or not exists (
    select 1
      from public.research_tasks t
     where t.id = v_finding_task_id
       and t.status = 'completed'
  ) or (
    select count(*)
      from public.commons_research_findings f
     where f.task_id = v_finding_task_id
  ) <> 1 then
    raise exception 'Repeated opt-out changed released tasks or finding history';
  end if;

  update public.research_tasks
     set status = 'open',
         assigned_agent = null,
         claimed_owner_id = null,
         claimed_until = null
   where id = v_unfinished_task_id;

  -- Re-consent and renew the completed current task to prove it remains a valid
  -- predecessor under the Phase 2 lineage guard and create-or-renew RPC.
  update public.agent_profiles
     set opted_in = true
   where id = v_profile_id;

  v_result := public.commons_create_or_renew_research(
    'ORCATSTG',
    'fundamentals',
    'fundamentals.valuation',
    pg_catalog.gen_random_uuid(),
    v_finding_task_id
  );
  v_renewed_task_id := (v_result ->> 'id')::uuid;

  if v_renewed_task_id is null
     or v_renewed_task_id = v_finding_task_id
     or v_result ->> 'status' is distinct from 'open'
     or not exists (
       select 1
         from public.research_tasks t
        where t.id = v_renewed_task_id
          and t.status = 'open'
          and t.renewed_from_task_id = v_finding_task_id
          and t.research_series_id = v_finding_series_id
     )
     or not exists (
       select 1
         from public.commons_research_series s
        where s.id = v_finding_series_id
          and s.current_task_id = v_renewed_task_id
     )
     or not exists (
       select 1
         from public.research_tasks t
        where t.id = v_finding_task_id
          and t.status = 'completed'
     )
     or (
       select count(*)
         from public.commons_research_findings f
        where f.task_id = v_finding_task_id
     ) <> 1 then
    raise exception 'Renewal after opt-out did not preserve completed history and create a linked successor';
  end if;
end
$$;

select 'PASS: opt-out trigger, permission withdrawal, history, and renewal checks completed; all test writes are rolled back.' as result;

rollback;
