-- AI Stock Commons Phase 2: staging-only tests for approved metrics and idempotency.
-- Run only in disposable staging with dedicated authorized test users and execute
-- the whole script as one unit. All task/request writes are rolled back. Before
-- running, bootstrap-map all existing tasks for RKLB or use an empty staging ticker.
-- Provide CLAIMED_TASK_WITH_EXISTING_FINDING_UUID owned by TEST_USER_UUID, plus a
-- second authorized member/profile for the denied-release test.
-- This does not replace the existing claim RPC concurrency tests.

begin;

set local role authenticated;
select set_config('request.jwt.claim.sub', '<TEST_USER_UUID>', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

do $$
declare
  v_request_id uuid;
  v_volume_request_id uuid;
  v_first jsonb;
  v_retry jsonb;
  v_next_cycle jsonb;
  v_task_id uuid;
  v_conflict_rejected boolean;
  v_write_denied boolean;
  v_claim_rejected boolean;
  v_claim_next jsonb;
  v_claimed_status text;
  v_claimed_until timestamptz;
  v_assigned_agent text;
  v_assigned_agent_after text;
  v_series_id uuid;
  v_series_id_after uuid;
  v_predecessor_id uuid;
  v_predecessor_id_after uuid;
  v_next_task_id uuid;
  v_other_task_id uuid;
  v_claimed_with_finding_id uuid := '<CLAIMED_TASK_WITH_EXISTING_FINDING_UUID>';
  v_release_rejected boolean;
  v_findings_before bigint;
  v_findings_after bigint;
  v_original_user_id text := current_setting('request.jwt.claim.sub', true);
  v_categories text[] := array['sec', 'fundamentals', 'volume', 'technical', 'news'];
  v_metrics text[] := array[
    'sec.filings_catalysts',
    'fundamentals.valuation',
    'volume.relative',
    'technical.technical_analysis',
    'news.market_sentiment'
  ];
  v_index integer;
begin
  for v_index in 1..array_length(v_categories, 1) loop
    v_request_id := gen_random_uuid();
    v_first := public.commons_create_or_renew_research(
      'RKLB', v_categories[v_index], v_metrics[v_index], v_request_id, null
    );
    v_retry := public.commons_create_or_renew_research(
      'RKLB', v_categories[v_index], v_metrics[v_index], v_request_id, null
    );

    if (v_retry ->> 'id')::uuid <> (v_first ->> 'id')::uuid then
      raise exception 'Retry returned a different task for category %', v_categories[v_index];
    end if;

    if v_first ->> 'status' <> 'open' then
      raise exception 'First task for category % is not open', v_categories[v_index];
    end if;

    if v_categories[v_index] = 'volume' then
      v_task_id := (v_first ->> 'id')::uuid;
      v_volume_request_id := v_request_id;
    end if;
  end loop;

  -- A request UUID cannot be reused for a different metric.
  v_conflict_rejected := false;
  begin
    perform public.commons_create_or_renew_research(
      'RKLB', 'volume', 'volume.options', v_request_id, null
    );
  exception when sqlstate '22023' then
    v_conflict_rejected := true;
  end;
  if not v_conflict_rejected then
    raise exception 'Conflicting request UUID reuse was not rejected';
  end if;

  -- Same request UUID cannot be replayed with a different source task.
  v_conflict_rejected := false;
  begin
    perform public.commons_create_or_renew_research(
      'RKLB', 'volume', 'volume.relative', v_volume_request_id, v_task_id
    );
  exception when sqlstate '22023' then
    v_conflict_rejected := true;
  end;
  if not v_conflict_rejected then
    raise exception 'Request UUID reuse with a different source was not rejected';
  end if;

  -- A different authenticated researcher cannot replay another user's request.
  perform set_config('request.jwt.claim.sub', '<SECOND_AUTHORIZED_TEST_USER_UUID>', true);
  v_conflict_rejected := false;
  begin
    perform public.commons_create_or_renew_research(
      'RKLB', 'volume', 'volume.relative', v_volume_request_id, null
    );
  exception when sqlstate '22023' then
    v_conflict_rejected := true;
  end;
  perform set_config('request.jwt.claim.sub', v_original_user_id, true);
  if not v_conflict_rejected then
    raise exception 'Request UUID replay by a different user was not rejected';
  end if;

  -- Only catalog-approved metric keys may create a series.
  v_conflict_rejected := false;
  begin
    perform public.commons_create_or_renew_research(
      'RKLB', 'volume', 'volume.arbitrary_metric', gen_random_uuid(), null
    );
  exception when no_data_found then
    v_conflict_rejected := true;
  end;
  if not v_conflict_rejected then
    raise exception 'Unapproved metric key was not rejected';
  end if;

  -- Volume and Options are distinct approved metric keys in the same category.
  v_retry := public.commons_create_or_renew_research(
    'RKLB', 'volume', 'volume.options', gen_random_uuid(), null
  );
  if (v_retry ->> 'id')::uuid = v_task_id then
    raise exception 'Volume and Options resolved to the same task';
  end if;

  -- Clients cannot directly modify historical lineage fields.
  v_write_denied := false;
  begin
    update public.research_tasks
       set renewed_from_task_id = id
     where id = v_task_id;
  exception when insufficient_privilege then
    v_write_denied := true;
  end;
  if not v_write_denied then
    raise exception 'Authenticated direct lineage modification was not denied';
  end if;

  -- Bootstrap is restricted to service_role; an authenticated researcher cannot
  -- invoke the legacy mapping path.
  v_conflict_rejected := false;
  begin
    perform public.commons_bootstrap_legacy_research_task(
      v_task_id, 'volume', 'volume.relative', false
    );
  exception when insufficient_privilege then
    v_conflict_rejected := true;
  end;
  if not v_conflict_rejected then
    raise exception 'Authenticated legacy bootstrap was not denied';
  end if;

  -- Fixture: a task currently claimed by TEST_USER_UUID with at least one finding.
  select status, research_series_id, renewed_from_task_id
    into strict v_claimed_status, v_series_id, v_predecessor_id
    from public.research_tasks
   where id = v_claimed_with_finding_id;
  select count(*) into v_findings_before
    from public.commons_research_findings
   where task_id = v_claimed_with_finding_id;
  if v_claimed_status <> 'claimed' or v_findings_before < 1 then
    raise exception 'Finding-release fixture must be claimed and have a finding';
  end if;

  -- Another researcher cannot release the owner's claimed task.
  perform set_config('request.jwt.claim.sub', '<SECOND_AUTHORIZED_TEST_USER_UUID>', true);
  v_release_rejected := false;
  begin
    perform public.commons_release_task(v_claimed_with_finding_id);
  exception when others then
    v_release_rejected := true;
  end;
  perform set_config('request.jwt.claim.sub', v_original_user_id, true);
  if not v_release_rejected then
    raise exception 'Another researcher released a task they do not own';
  end if;

  select status, research_series_id, renewed_from_task_id
    into strict v_claimed_status, v_series_id_after, v_predecessor_id_after
    from public.research_tasks
   where id = v_claimed_with_finding_id;
  select count(*) into v_findings_after
    from public.commons_research_findings
   where task_id = v_claimed_with_finding_id;
  if v_claimed_status <> 'claimed'
     or v_series_id_after is distinct from v_series_id
     or v_predecessor_id_after is distinct from v_predecessor_id
     or v_findings_after <> v_findings_before then
    raise exception 'Unauthorized release changed task status, lineage, or findings';
  end if;

  -- The owner releases a claimed task with findings. Fixed function should set
  -- completed (not invalid complete), preserving links and finding rows.
  perform public.commons_release_task(v_claimed_with_finding_id);
  select status, research_series_id, renewed_from_task_id
    into strict v_claimed_status, v_series_id_after, v_predecessor_id_after
    from public.research_tasks
   where id = v_claimed_with_finding_id;
  select count(*) into v_findings_after
    from public.commons_research_findings
   where task_id = v_claimed_with_finding_id;
  if v_claimed_status <> 'completed'
     or v_series_id_after is distinct from v_series_id
     or v_predecessor_id_after is distinct from v_predecessor_id
     or v_findings_after <> v_findings_before then
    raise exception 'Owner release with findings did not complete safely';
  end if;

  -- Existing claim_task updates must succeed with the lineage trigger installed.
  perform public.commons_claim_task(v_task_id);
  select status, claimed_until
    into strict v_claimed_status, v_claimed_until
    from public.research_tasks
   where id = v_task_id;
  if v_claimed_status <> 'claimed' or v_claimed_until <= now() then
    raise exception 'commons_claim_task did not establish an active lease';
  end if;

  -- Publish must atomically preserve its existing completed transition and finding.
  select count(*) into v_findings_before
    from public.commons_research_findings
   where task_id = v_task_id;
  perform public.commons_publish_finding(
    v_task_id,
    'Staging-only checked summary confirming that claim and publish RPCs remain compatible with lineage protection.',
    array['https://example.com/staging-research-test'],
    now(),
    'Staging fixture only; not research evidence.'
  );
  select status into strict v_claimed_status
    from public.research_tasks
   where id = v_task_id;
  select count(*) into v_findings_after
    from public.commons_research_findings
   where task_id = v_task_id;
  if v_claimed_status <> 'completed' or v_findings_after <> v_findings_before + 1 then
    raise exception 'Publish did not atomically complete task and add one finding';
  end if;

  -- Replaying the original request after publication returns its original task.
  v_retry := public.commons_create_or_renew_research(
    'RKLB', 'volume', 'volume.relative', v_volume_request_id, null
  );
  if (v_retry ->> 'id')::uuid <> v_task_id
     or v_retry ->> 'status' <> 'completed' then
    raise exception 'Completed task request replay did not return its original task';
  end if;

  -- A new request after completion creates a fresh task ID linked to that task.
  v_next_cycle := public.commons_create_or_renew_research(
    'RKLB', 'volume', 'volume.relative', gen_random_uuid(), v_task_id
  );
  v_next_task_id := (v_next_cycle ->> 'id')::uuid;
  if v_next_task_id = v_task_id or v_next_cycle ->> 'status' <> 'open' then
    raise exception 'Next research cycle did not create a distinct open task';
  end if;
  if not exists (
    select 1 from public.research_tasks
     where id = v_next_task_id and renewed_from_task_id = v_task_id
  ) then
    raise exception 'Next task does not link to the completed predecessor';
  end if;

  -- The existing duplicate-publication window is scoped to task_id, so this
  -- distinct cycle task can be claimed and published immediately.
  perform public.commons_claim_task(v_next_task_id);
  select count(*) into v_findings_before
    from public.commons_research_findings
   where task_id = v_next_task_id;
  if v_findings_before <> 0 then
    raise exception 'No-findings release fixture unexpectedly has prior findings';
  end if;
  select assigned_agent, research_series_id, renewed_from_task_id
    into strict v_assigned_agent, v_series_id, v_predecessor_id
    from public.research_tasks
   where id = v_next_task_id;
  perform public.commons_release_task(v_next_task_id);
  select status, assigned_agent, research_series_id, renewed_from_task_id
     into strict v_claimed_status, v_assigned_agent_after,
             v_series_id_after, v_predecessor_id_after
    from public.research_tasks
   where id = v_next_task_id;
  if v_claimed_status <> 'open'
      or v_assigned_agent_after is not null
      or v_series_id_after is distinct from v_series_id
      or v_predecessor_id_after is distinct from v_predecessor_id then
    raise exception 'commons_release_task changed status/claim fields or lineage incorrectly';
  end if;
    select count(*) into v_findings_after
      from public.commons_research_findings
     where task_id = v_next_task_id;
    if v_findings_after <> 0 then
      raise exception 'Release without findings unexpectedly changed findings';
    end if;

  perform public.commons_claim_task(v_next_task_id);
  perform public.commons_publish_finding(
    v_next_task_id,
    'Second staging cycle summary using a fresh task ID to verify publication deduplication remains task-scoped.',
    array['https://example.com/staging-research-test-cycle-two'],
    now(),
    'Staging fixture only; not research evidence.'
  );
  select status into strict v_claimed_status
    from public.research_tasks
   where id = v_next_task_id;
  if v_claimed_status <> 'completed' then
    raise exception 'Fresh task cycle was blocked from publication';
  end if;

  -- Claim-next must also remain compatible with the lineage trigger.
  select pg_catalog.to_jsonb(public.commons_claim_next('RKLB'))
    into v_claim_next;
  v_next_task_id := (v_claim_next ->> 'id')::uuid;
  if v_next_task_id is null then
    raise exception 'commons_claim_next did not return an assignment';
  end if;

  select status into strict v_claimed_status
    from public.research_tasks
   where id = v_next_task_id;
  if v_claimed_status <> 'claimed' then
    raise exception 'commons_claim_next did not transition the task to claimed';
  end if;

  select id into strict v_other_task_id
    from public.research_tasks
   where ticker = 'RKLB'
     and status = 'open'
     and id <> v_next_task_id
   limit 1;

  v_claim_rejected := false;
  begin
    perform public.commons_claim_task(v_other_task_id);
  exception when others then
    v_claim_rejected := true;
  end;
  if not v_claim_rejected then
    raise exception 'A second active assignment was allowed for the same researcher';
  end if;

  -- Concurrent claim arbitration across two users must be run as two sessions in
  -- staging; this transaction checks same-user active-claim protection only.
end
$$;

rollback;