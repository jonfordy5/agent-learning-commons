-- Destructive, staging-only cleanup for one completed authenticated ORCA test.
-- Run only in Orca-staging after replacing all five run-manifest placeholders.
-- The guard refuses to delete data unless the requests, users, task lineage,
-- claim, and uniquely labeled synthetic finding match this test exactly.
-- No Auth users, profiles, memberships, stocks, or unrelated research are deleted.

begin;

do $$
declare
  v_run_id uuid := '<ORCA_TEST_RUN_UUID>'::uuid;
  v_initial_request_id uuid := '<ORCA_INITIAL_REQUEST_UUID>'::uuid;
  v_observer_request_id uuid := '<ORCA_OBSERVER_REQUEST_UUID>'::uuid;
  v_renewal_request_id uuid := '<ORCA_RENEWAL_REQUEST_UUID>'::uuid;
  v_finding_id uuid := '<ORCA_TEST_FINDING_UUID>'::uuid;
  v_request_a public.commons_research_requests%rowtype;
  v_request_b_initial public.commons_research_requests%rowtype;
  v_request_b_renewal public.commons_research_requests%rowtype;
  v_user_a uuid;
  v_user_b uuid;
  v_original_task public.research_tasks%rowtype;
  v_renewed_task public.research_tasks%rowtype;
  v_series public.commons_research_series%rowtype;
  v_finding public.commons_research_findings%rowtype;
  v_count bigint;
begin
  if current_user <> 'postgres' then
    raise exception 'Run this cleanup as postgres in Orca-staging only';
  end if;

  if v_initial_request_id = v_observer_request_id
     or v_initial_request_id = v_renewal_request_id
     or v_observer_request_id = v_renewal_request_id then
    raise exception 'All three request IDs must be different';
  end if;

  select p.owner_id into strict v_user_a
    from public.agent_profiles p
   where p.display_name = 'ORCA Test Researcher 1';
  select p.owner_id into strict v_user_b
    from public.agent_profiles p
   where p.display_name = 'ORCA Test Researcher 2';

  select r.* into strict v_request_a
    from public.commons_research_requests r
   where r.request_id = v_initial_request_id;
  select r.* into strict v_request_b_initial
    from public.commons_research_requests r
   where r.request_id = v_observer_request_id;
  select r.* into strict v_request_b_renewal
    from public.commons_research_requests r
   where r.request_id = v_renewal_request_id;

  if v_request_a.requested_by is distinct from v_user_a
     or v_request_b_initial.requested_by is distinct from v_user_b
     or v_request_b_renewal.requested_by is distinct from v_user_b
     or v_request_a.ticker is distinct from 'RKLB'
     or v_request_b_initial.ticker is distinct from 'RKLB'
     or v_request_b_renewal.ticker is distinct from 'RKLB'
     or v_request_a.category_key is distinct from 'sec'
     or v_request_b_initial.category_key is distinct from 'sec'
     or v_request_b_renewal.category_key is distinct from 'sec'
     or v_request_a.metric_key is distinct from 'sec.filings_catalysts'
     or v_request_b_initial.metric_key is distinct from 'sec.filings_catalysts'
     or v_request_b_renewal.metric_key is distinct from 'sec.filings_catalysts'
     or v_request_a.source_task_id is not null
     or v_request_b_initial.source_task_id is not null
     or v_request_b_renewal.source_task_id is distinct from v_request_a.task_id
     or v_request_a.created_task is not true
     or v_request_b_initial.created_task is not false
     or v_request_b_renewal.created_task is not true
     or v_request_a.task_id is distinct from v_request_b_initial.task_id
     or v_request_a.series_id is distinct from v_request_b_initial.series_id
     or v_request_a.series_id is distinct from v_request_b_renewal.series_id then
    raise exception 'Request ledger does not match the expected two-researcher test';
  end if;

  select s.* into strict v_series
    from public.commons_research_series s
   where s.id = v_request_a.series_id;
  select t.* into strict v_original_task
    from public.research_tasks t
   where t.id = v_request_a.task_id;
  select t.* into strict v_renewed_task
    from public.research_tasks t
   where t.id = v_request_b_renewal.task_id;

  if v_series.ticker is distinct from 'RKLB'
     or v_series.category_key is distinct from 'sec'
     or v_series.metric_key is distinct from 'sec.filings_catalysts'
     or v_series.current_task_id is distinct from v_renewed_task.id
     or v_original_task.ticker is distinct from 'RKLB'
     or v_original_task.research_series_id is distinct from v_series.id
     or v_original_task.status is distinct from 'completed'
     or v_original_task.claimed_owner_id is not null
     or v_original_task.claimed_until is not null
     or v_renewed_task.ticker is distinct from 'RKLB'
     or v_renewed_task.research_series_id is distinct from v_series.id
     or v_renewed_task.renewed_from_task_id is distinct from v_original_task.id
     or v_renewed_task.status is distinct from 'claimed'
     or v_renewed_task.claimed_owner_id is distinct from v_user_b
     or v_renewed_task.claimed_until is null
     or v_renewed_task.claimed_until <= pg_catalog.now() then
    raise exception 'Task history or active Researcher B claim does not match the test';
  end if;

  select count(*) into v_count
    from public.research_tasks t
   where t.research_series_id = v_series.id;
  if v_count <> 2 then
    raise exception 'Unexpected task history exists in the test series; refusing cleanup';
  end if;

  select count(*) into v_count
    from public.commons_research_requests r
   where r.series_id = v_series.id;
  if v_count <> 3 then
    raise exception 'Unexpected request history exists in the test series; refusing cleanup';
  end if;

  select count(*) into v_count
    from public.commons_research_findings f
    join public.research_tasks t on t.id = f.task_id
   where t.research_series_id = v_series.id;
  if v_count <> 1 then
    raise exception 'Unexpected finding history exists in the test series; refusing cleanup';
  end if;

  select f.* into strict v_finding
    from public.commons_research_findings f
   where f.id = v_finding_id
     and f.task_id = v_original_task.id
     and f.contributor_id = v_user_a
     and f.summary like '[ORCA STAGING TEST ' || v_run_id::text || ']%';

  if exists (
    select 1
      from public.commons_research_findings f
     where f.task_id = v_renewed_task.id
  ) then
    raise exception 'The renewed task has unexpected findings; refusing cleanup';
  end if;

  update public.commons_research_series
     set current_task_id = null
   where id = v_series.id
     and current_task_id = v_renewed_task.id;

  if not found then
    raise exception 'Could not safely clear the test series current-task pointer';
  end if;

  delete from public.commons_research_requests
   where request_id in (
     v_initial_request_id,
     v_observer_request_id,
     v_renewal_request_id
   );
  get diagnostics v_count = row_count;
  if v_count <> 3 then
    raise exception 'Expected to delete exactly three test request rows';
  end if;

  delete from public.commons_research_findings
   where id = v_finding.id;
  get diagnostics v_count = row_count;
  if v_count <> 1 then
    raise exception 'Expected to delete exactly one labeled test finding';
  end if;

  delete from public.research_tasks
   where id = v_renewed_task.id
     and renewed_from_task_id = v_original_task.id;
  get diagnostics v_count = row_count;
  if v_count <> 1 then
    raise exception 'Expected to delete exactly one renewed test task';
  end if;

  delete from public.research_tasks
   where id = v_original_task.id
     and research_series_id = v_series.id
     and status = 'completed';
  get diagnostics v_count = row_count;
  if v_count <> 1 then
    raise exception 'Expected to delete exactly one completed test task';
  end if;

  delete from public.commons_research_series
   where id = v_series.id
     and ticker = 'RKLB'
     and category_key = 'sec'
     and metric_key = 'sec.filings_catalysts'
     and current_task_id is null;
  get diagnostics v_count = row_count;
  if v_count <> 1 then
    raise exception 'Expected to delete exactly one test-created metric series';
  end if;
end
$$;

select 'PASS: only the guarded ORCA authenticated integration-test records were removed.' as result;

commit;
