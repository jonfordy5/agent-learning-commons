-- AI Stock Commons Phase 2: guarded rollback for the proposed renewal migration.
-- Run only after stopping renewal calls and reviewing the pilot state.
-- This refuses to remove series/lineage metadata after any task or request has
-- been recorded; it never deletes research assignments or findings.
-- The migration revokes direct task DML from client roles. Restore only the exact
-- pre-migration grants recorded by preflight; do not guess or blanket-grant.

begin;

do $$
begin
  if exists (select 1 from public.commons_research_requests)
     or exists (select 1 from public.commons_research_series)
     or exists (
       select 1 from public.research_tasks
        where research_series_id is not null or renewed_from_task_id is not null
     ) then
    raise exception
      'Rollback stopped: series requests or linked assignments exist. Disable the RPC and retain lineage/schema; do not delete research history.';
  end if;
end
$$;

revoke all on function public.commons_create_or_renew_research(text, text, text, uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.commons_bootstrap_legacy_research_task(uuid, text, text, boolean)
  from public, anon, authenticated, service_role;
revoke all on function public.commons_enforce_research_task_lineage()
  from public, anon, authenticated, service_role;
drop function public.commons_create_or_renew_research(text, text, text, uuid, uuid);
drop function public.commons_bootstrap_legacy_research_task(uuid, text, text, boolean);
drop trigger research_tasks_enforce_lineage on public.research_tasks;
drop function public.commons_enforce_research_task_lineage();

drop index public.research_tasks_one_live_successor_idx;
drop index public.research_tasks_series_created_idx;
drop index public.commons_research_requests_user_created_idx;
drop table public.commons_research_requests;
alter table public.research_tasks
  drop constraint research_tasks_research_series_id_fkey,
  drop constraint research_tasks_renewed_from_task_id_fkey;
alter table public.commons_research_series
  drop constraint commons_research_series_current_task_id_fkey;
drop table public.commons_research_series;
  drop table public.commons_research_metric_catalog;

alter table public.research_tasks
  drop column research_series_id,
  drop column renewed_from_task_id;

commit;