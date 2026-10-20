-- AI Stock Commons Phase 2: proposed migration for review only.
-- DO NOT RUN until the preflight output and live function definitions have been
-- reviewed. In particular, verify task column types/defaults and make sure the
-- existing claim RPCs claim only open tasks or eligible expired claimed tasks.
-- Also verify RLS/table grants prevent direct authenticated writes to lineage
-- columns, and that the SECURITY DEFINER owner has only the intended privileges.
-- This script creates no findings and changes no existing task status or finding.
-- Existing claim/publish RPC bodies are deliberately not replaced here: preserve
-- their exact authentication/permission checks when reviewing any claim adjustment.

begin;

-- SECTION 1: Approved metrics, per-metric series, and request idempotency ledger.
create table public.commons_research_metric_catalog (
  category_key text not null check (category_key in (
    'sec', 'fundamentals', 'volume', 'technical', 'news'
  )),
  metric_key text not null check (
    metric_key ~ '^[a-z][a-z0-9_.-]{0,79}$'
  ),
  research_area text not null check (char_length(btrim(research_area)) between 2 and 100),
  research_question text not null check (char_length(btrim(research_question)) between 10 and 1000),
  active boolean not null default true,
  primary key (category_key, metric_key)
);

insert into public.commons_research_metric_catalog (
  category_key, metric_key, research_area, research_question
) values
  ('sec', 'sec.filings_catalysts', 'SEC Filings & Catalysts', 'Review recent SEC filings and identify material, source-backed catalysts and limitations.'),
  ('fundamentals', 'fundamentals.valuation', 'Fundamentals & Valuation', 'Assess the selected fundamental or valuation metric using dated primary sources.'),
  ('volume', 'volume.relative', 'Volume', 'Measure relative volume against a stated, time-matched baseline and report the source and observation time.'),
  ('volume', 'volume.options', 'Options', 'Summarize the selected options metric with timestamp, source, and limitations.'),
  ('technical', 'technical.technical_analysis', 'Technical Analysis', 'Describe the selected technical metric, timeframe, method, and source.'),
  ('news', 'news.market_sentiment', 'News & Market Sentiment', 'Summarize dated news and sentiment evidence, distinguishing reporting from interpretation.');

-- One series represents one approved metric for one ticker. Distinct metric_key
-- values keep Volume and Options separate within the Volume dashboard category.
create table public.commons_research_series (
  id uuid primary key default gen_random_uuid(),
  ticker text not null references public.stocks(ticker) on delete restrict,
  category_key text not null,
  metric_key text not null,
  research_area text not null check (char_length(btrim(research_area)) between 2 and 100),
  research_question text not null check (char_length(btrim(research_question)) between 10 and 1000),
  current_task_id uuid,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint commons_research_series_metric_fkey
    foreign key (category_key, metric_key)
    references public.commons_research_metric_catalog(category_key, metric_key)
    on delete restrict,
  constraint commons_research_series_ticker_metric_uq
    unique (ticker, category_key, metric_key)
);

create table public.commons_research_requests (
  request_id uuid primary key,
  requested_by uuid not null,
  ticker text not null references public.stocks(ticker) on delete restrict,
  category_key text not null,
  metric_key text not null,
  source_task_id uuid references public.research_tasks(id) on delete restrict,
  series_id uuid not null references public.commons_research_series(id) on delete restrict,
  task_id uuid references public.research_tasks(id) on delete restrict,
  created_task boolean not null default false,
  created_at timestamptz not null default now(),
  constraint commons_research_requests_metric_fkey
    foreign key (category_key, metric_key)
    references public.commons_research_metric_catalog(category_key, metric_key)
    on delete restrict
);

-- SECTION 2: Task lineage and uniqueness/concurrency constraints.
alter table public.research_tasks
  add column research_series_id uuid,
  add column renewed_from_task_id uuid;

alter table public.research_tasks
  add constraint research_tasks_research_series_id_fkey
    foreign key (research_series_id)
    references public.commons_research_series(id)
    on delete restrict,
  add constraint research_tasks_renewed_from_task_id_fkey
    foreign key (renewed_from_task_id)
    references public.research_tasks(id)
    on delete restrict;

alter table public.commons_research_series
  add constraint commons_research_series_current_task_id_fkey
    foreign key (current_task_id)
    references public.research_tasks(id)
    on delete restrict;

-- One non-cancelled successor per predecessor. Cancelled attempts remain in
-- history and can be replaced. Series-row locking prevents duplicate roots.
create unique index research_tasks_one_live_successor_idx
  on public.research_tasks (renewed_from_task_id)
  where renewed_from_task_id is not null
    and status <> 'cancelled';

create index research_tasks_series_created_idx
  on public.research_tasks (research_series_id, created_at desc, id desc)
  where research_series_id is not null;

create index commons_research_requests_user_created_idx
  on public.commons_research_requests (requested_by, created_at desc)
  where created_task;

-- SECTION 3: Private metadata table permissions.
alter table public.commons_research_series enable row level security;
alter table public.commons_research_requests enable row level security;
alter table public.commons_research_metric_catalog enable row level security;
revoke all on public.commons_research_series from public, anon, authenticated;
revoke all on public.commons_research_requests from public, anon, authenticated;
revoke all on public.commons_research_metric_catalog from public, anon, authenticated;

-- Task reads keep using the existing public feed; all client task writes go through
-- authenticated SECURITY DEFINER research/claim/publish RPCs or controlled bootstrap.
revoke insert, update, delete on table public.research_tasks
  from public, anon, authenticated;
revoke truncate on table public.research_tasks
  from public, anon, authenticated;
revoke trigger, references on table public.research_tasks
  from public, anon, authenticated;
revoke insert (research_series_id, renewed_from_task_id),
       update (research_series_id, renewed_from_task_id),
       references (research_series_id, renewed_from_task_id)
  on table public.research_tasks
  from public, anon, authenticated;

do $$
declare
  v_column record;
begin
  for v_column in
    select column_name
      from information_schema.columns
     where table_schema = 'public'
       and table_name = 'research_tasks'
  loop
    execute format(
      'revoke insert (%1$I), update (%1$I) on table public.research_tasks from public, anon, authenticated',
      v_column.column_name
    );
  end loop;
end
$$;

comment on table public.commons_research_series is
  'Idempotent per-ticker, per-category, per-metric coordinator for first assignments and later research cycles.';
comment on column public.research_tasks.renewed_from_task_id is
  'Prior task in this metric series; each cycle has a new task ID and historical rows are retained.';
comment on table public.commons_research_requests is
  'Private idempotency ledger mapping each accepted create-or-renew request to its returned task.';
comment on table public.commons_research_metric_catalog is
  'Maintainer-controlled allowlist of metric keys and canonical research definitions.';

create or replace function public.commons_enforce_research_task_lineage()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_series public.commons_research_series%rowtype;
  v_predecessor public.research_tasks%rowtype;
begin
  if tg_op = 'INSERT' then
    if new.status is distinct from 'open' then
      raise exception 'New research assignments must start open'
        using errcode = '23514';
    end if;

    if new.research_series_id is null then
      raise exception 'New research tasks must belong to an approved metric series'
        using errcode = '23514';
    end if;

    select s.* into strict v_series
      from public.commons_research_series s
     where s.id = new.research_series_id
     for update;

    if new.ticker is distinct from v_series.ticker
       or new.research_area is distinct from v_series.research_area
       or new.research_question is distinct from v_series.research_question
       or new.renewed_from_task_id is distinct from v_series.current_task_id then
      raise exception 'New research task does not match its series and current predecessor'
        using errcode = '23514';
    end if;

    if v_series.current_task_id is null and exists (
      select 1 from public.research_tasks t
       where t.research_series_id = v_series.id
    ) then
      raise exception 'Series has task history but no current task; bootstrap is required'
        using errcode = '23514';
    end if;

    if new.renewed_from_task_id is not null then
      select t.* into strict v_predecessor
        from public.research_tasks t
       where t.id = new.renewed_from_task_id
       for update;

      if v_predecessor.research_series_id is distinct from v_series.id
         or v_predecessor.ticker is distinct from v_series.ticker
         or v_predecessor.research_area is distinct from v_series.research_area
         or v_predecessor.research_question is distinct from v_series.research_question
         or v_predecessor.status not in ('completed', 'cancelled') then
        raise exception 'New task predecessor is not a completed/cancelled task in this series'
          using errcode = '23514';
      end if;
    end if;
  else
    if old.research_series_id is not null
       and new.research_series_id is distinct from old.research_series_id then
      raise exception 'Research task series lineage is immutable'
        using errcode = '23514';
    end if;

    if new.renewed_from_task_id is distinct from old.renewed_from_task_id then
      raise exception 'Research task predecessor lineage is immutable'
        using errcode = '23514';
    end if;

    if new.research_series_id is not null then
      select s.* into strict v_series
        from public.commons_research_series s
       where s.id = new.research_series_id;

      if new.ticker is distinct from v_series.ticker
         or new.research_area is distinct from v_series.research_area
         or new.research_question is distinct from v_series.research_question then
        raise exception 'Research task definition does not match its series'
          using errcode = '23514';
      end if;
    elsif new.status = 'claimed'
       and (
         old.status is distinct from new.status
         or old.assigned_agent is distinct from new.assigned_agent
         or old.claimed_until is distinct from new.claimed_until
       ) then
      raise exception 'A task must be mapped to a current series before it can be claimed'
        using errcode = '23514';
    end if;

    if new.status = 'claimed'
       and (
         old.status is distinct from new.status
         or old.assigned_agent is distinct from new.assigned_agent
         or old.claimed_until is distinct from new.claimed_until
       )
       and v_series.current_task_id is distinct from new.id then
      raise exception 'Only the current task in a research series can be claimed'
        using errcode = '23514';
    end if;
  end if;

  return new;
end
$function$;

alter function public.commons_enforce_research_task_lineage() owner to postgres;
revoke all on function public.commons_enforce_research_task_lineage()
  from public, anon, authenticated, service_role;

create trigger research_tasks_enforce_lineage
before insert or update of research_series_id, renewed_from_task_id, status,
                         assigned_agent, claimed_until
on public.research_tasks
for each row
execute function public.commons_enforce_research_task_lineage();

-- SECTION 4: Authenticated create-or-renew and privileged legacy bootstrap.
create or replace function public.commons_create_or_renew_research(
  p_ticker text,
  p_category_key text,
  p_metric_key text,
  p_request_id uuid,
  p_source_task_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_ticker text := pg_catalog.upper(pg_catalog.btrim(p_ticker));
  v_category_key text := pg_catalog.lower(pg_catalog.btrim(p_category_key));
  v_metric_key text := pg_catalog.lower(pg_catalog.btrim(p_metric_key));
  v_catalog public.commons_research_metric_catalog%rowtype;
  v_series public.commons_research_series%rowtype;
  v_current public.research_tasks%rowtype;
  v_task public.research_tasks%rowtype;
  v_request public.commons_research_requests%rowtype;
  v_reserved_request_id uuid;
  v_created_count bigint;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if p_request_id is null
     or v_ticker is null or v_ticker = ''
     or v_category_key is null or v_category_key = ''
     or v_metric_key is null or v_metric_key = '' then
    raise exception 'Ticker, metric, and request id are required' using errcode = '22023';
  end if;

  if not exists (select 1 from public.stocks s where s.ticker = v_ticker) then
    raise exception 'Ticker is not on the research board' using errcode = '22023';
  end if;

  -- Preserve current participant and owner-consent requirements. Verify against
  -- the live claim/publish functions before approval; do not weaken those checks.
  if not exists (
    select 1 from public.stock_research_memberships m
     where m.user_id = v_user_id and m.ticker = v_ticker
  ) or not exists (
    select 1 from public.agent_profiles ap
     where ap.owner_id = v_user_id and ap.opted_in is true
  ) then
    raise exception 'Research participation is not authorized' using errcode = '42501';
  end if;

  -- Same UUID is valid only for the same authenticated user and canonical inputs.
  select r.* into v_request
    from public.commons_research_requests r
   where r.request_id = p_request_id;

  if found then
    if v_request.requested_by is distinct from v_user_id
       or v_request.ticker is distinct from v_ticker
       or v_request.category_key is distinct from v_category_key
       or v_request.metric_key is distinct from v_metric_key
       or v_request.source_task_id is distinct from p_source_task_id then
      raise exception 'Request idempotency key conflicts with an existing request'
        using errcode = '22023';
    end if;

    select t.* into strict v_task
      from public.research_tasks t
      join public.commons_research_series s
        on s.id = v_request.series_id
       and s.ticker = v_request.ticker
       and s.category_key = v_request.category_key
       and s.metric_key = v_request.metric_key
     where t.id = v_request.task_id
       and t.research_series_id = s.id
       and t.ticker = s.ticker
       and t.research_area = s.research_area
       and t.research_question = s.research_question
       and (not v_request.created_task
            or t.renewed_from_task_id is not distinct from v_request.source_task_id);

    return pg_catalog.jsonb_build_object(
      'id', v_task.id,
      'ticker', v_task.ticker,
      'research_area', v_task.research_area,
      'research_question', v_task.research_question,
      'status', v_task.status
    );
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_user_id::text, 0)
  );

  select c.* into strict v_catalog
    from public.commons_research_metric_catalog c
   where c.category_key = v_category_key
     and c.metric_key = v_metric_key
     and c.active;

  insert into public.commons_research_series (
    ticker, category_key, metric_key, research_area, research_question, created_by
  ) values (
    v_ticker, v_category_key, v_metric_key,
    v_catalog.research_area, v_catalog.research_question, v_user_id
  )
  on conflict (ticker, category_key, metric_key) do nothing;

  select s.* into strict v_series
    from public.commons_research_series s
   where s.ticker = v_ticker
     and s.category_key = v_category_key
     and s.metric_key = v_metric_key
   for update;

  if v_series.research_area is distinct from v_catalog.research_area
     or v_series.research_question is distinct from v_catalog.research_question then
    raise exception 'Metric series definition differs from the approved catalog'
      using errcode = '22023';
  end if;

  -- Recheck after obtaining the series lock: a concurrent same-series request may
  -- have committed its ledger row while this call waited for that lock.
  select r.* into v_request
    from public.commons_research_requests r
   where r.request_id = p_request_id;

  if found then
    if v_request.requested_by is distinct from v_user_id
       or v_request.ticker is distinct from v_ticker
       or v_request.category_key is distinct from v_category_key
       or v_request.metric_key is distinct from v_metric_key
       or v_request.source_task_id is distinct from p_source_task_id
       or v_request.series_id is distinct from v_series.id then
      raise exception 'Request idempotency key conflicts with an existing request'
        using errcode = '22023';
    end if;

    select t.* into strict v_task
      from public.research_tasks t
     where t.id = v_request.task_id
       and t.research_series_id = v_series.id
       and t.ticker = v_series.ticker
       and t.research_area = v_series.research_area
       and t.research_question = v_series.research_question
       and (not v_request.created_task
            or t.renewed_from_task_id is not distinct from v_request.source_task_id);

    return pg_catalog.jsonb_build_object(
      'id', v_task.id,
      'ticker', v_task.ticker,
      'research_area', v_task.research_area,
      'research_question', v_task.research_question,
      'status', v_task.status
    );
  end if;

  if exists (
    select 1 from public.research_tasks t
     where t.ticker = v_series.ticker
       and t.research_series_id is null
  ) then
    raise exception 'Unmapped legacy assignments exist for this ticker; bootstrap mapping is required'
      using errcode = '22023';
  end if;

  if v_series.current_task_id is null then
    if p_source_task_id is not null then
      raise exception 'Legacy assignments must be mapped by the bootstrap process'
        using errcode = '22023';
    end if;

    if exists (
      select 1 from public.research_tasks t
       where t.research_series_id = v_series.id
    ) then
      raise exception 'Series has mapped tasks but no current task; bootstrap is incomplete'
        using errcode = '55000';
    end if;
  else
    select t.* into strict v_current
      from public.research_tasks t
     where t.id = v_series.current_task_id
     for update;

    if v_current.research_series_id is distinct from v_series.id
       or v_current.ticker is distinct from v_series.ticker
       or v_current.research_area is distinct from v_series.research_area
       or v_current.research_question is distinct from v_series.research_question then
      raise exception 'Current assignment does not belong to this metric series'
        using errcode = '55000';
    end if;

    if p_source_task_id is not null and p_source_task_id <> v_current.id then
      raise exception 'Expected current assignment id is required for this series'
        using errcode = '22023';
    end if;

    if v_current.status not in ('open', 'claimed', 'completed', 'cancelled') then
      raise exception 'Current assignment has an unsupported status'
        using errcode = '55000';
    end if;

    if p_source_task_id is null
       and v_current.status not in ('open', 'claimed') then
      raise exception 'Current assignment id is required to start a new research cycle'
        using errcode = '22023';
    end if;
  end if;

  -- Reserve the request UUID before returning or creating a task. The unique key
  -- also serializes conflicting UUID reuse across different metric series.
  insert into public.commons_research_requests (
    request_id, requested_by, ticker, category_key, metric_key,
    source_task_id, series_id, task_id, created_task
  ) values (
    p_request_id, v_user_id, v_ticker, v_category_key, v_metric_key,
    p_source_task_id, v_series.id, null, false
  )
  on conflict (request_id) do nothing
  returning request_id into v_reserved_request_id;

  if v_reserved_request_id is null then
    select r.* into strict v_request
      from public.commons_research_requests r
     where r.request_id = p_request_id;

    if v_request.requested_by is distinct from v_user_id
       or v_request.ticker is distinct from v_ticker
       or v_request.category_key is distinct from v_category_key
       or v_request.metric_key is distinct from v_metric_key
       or v_request.source_task_id is distinct from p_source_task_id
       or v_request.series_id is distinct from v_series.id then
      raise exception 'Request idempotency key conflicts with an existing request'
        using errcode = '22023';
    end if;

    select t.* into strict v_task
      from public.research_tasks t
     where t.id = v_request.task_id
       and t.research_series_id = v_series.id
       and t.ticker = v_series.ticker
       and t.research_area = v_series.research_area
       and t.research_question = v_series.research_question
       and (not v_request.created_task
            or t.renewed_from_task_id is not distinct from v_request.source_task_id);

    return pg_catalog.jsonb_build_object(
      'id', v_task.id,
      'ticker', v_task.ticker,
      'research_area', v_task.research_area,
      'research_question', v_task.research_question,
      'status', v_task.status
    );
  end if;

  if v_current.id is not null and v_current.status in ('open', 'claimed') then
    update public.commons_research_requests
       set task_id = v_current.id
     where request_id = p_request_id;

    return pg_catalog.jsonb_build_object(
      'id', v_current.id,
      'ticker', v_current.ticker,
      'research_area', v_current.research_area,
      'research_question', v_current.research_question,
      'status', v_current.status
    );
  end if;

  select pg_catalog.count(*) into v_created_count
    from public.commons_research_requests r
   where r.requested_by = v_user_id
     and r.created_task
    and r.created_at >= pg_catalog.now() - interval '1 hour';

  if v_created_count >= 20 then
    raise exception 'Research assignment creation rate limit reached; retry later'
      using errcode = '54000';
  end if;

  insert into public.research_tasks (
    ticker, research_area, research_question, status,
    research_series_id, renewed_from_task_id
  ) values (
    v_series.ticker, v_series.research_area, v_series.research_question, 'open',
    v_series.id, v_current.id
  )
  returning * into v_task;

  update public.commons_research_requests
     set task_id = v_task.id, created_task = true
   where request_id = p_request_id;

  update public.commons_research_series
    set current_task_id = v_task.id, updated_at = pg_catalog.now()
   where id = v_series.id;

  return pg_catalog.jsonb_build_object(
    'id', v_task.id,
    'ticker', v_task.ticker,
    'research_area', v_task.research_area,
    'research_question', v_task.research_question,
    'status', v_task.status
  );
end
$function$;

create or replace function public.commons_bootstrap_legacy_research_task(
  p_task_id uuid,
  p_category_key text,
  p_metric_key text,
  p_set_current boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_task public.research_tasks%rowtype;
  v_catalog public.commons_research_metric_catalog%rowtype;
  v_series public.commons_research_series%rowtype;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'Privileged bootstrap authorization required' using errcode = '42501';
  end if;

  select c.* into strict v_catalog
    from public.commons_research_metric_catalog c
   where c.category_key = pg_catalog.lower(pg_catalog.btrim(p_category_key))
     and c.metric_key = pg_catalog.lower(pg_catalog.btrim(p_metric_key))
     and c.active;

  select t.* into strict v_task
    from public.research_tasks t
   where t.id = p_task_id;

  if v_task.research_area is distinct from v_catalog.research_area
     or v_task.research_question is distinct from v_catalog.research_question
     or v_task.status not in ('open', 'claimed', 'completed', 'cancelled') then
    raise exception 'Legacy task does not match the approved metric definition'
      using errcode = '22023';
  end if;

  insert into public.commons_research_series (
    ticker, category_key, metric_key, research_area, research_question, created_by
  ) values (
    v_task.ticker, v_catalog.category_key, v_catalog.metric_key,
    v_catalog.research_area, v_catalog.research_question, null
  )
  on conflict (ticker, category_key, metric_key) do nothing;

  select s.* into strict v_series
    from public.commons_research_series s
   where s.ticker = v_task.ticker
     and s.category_key = v_catalog.category_key
     and s.metric_key = v_catalog.metric_key
   for update;

  if v_series.research_area is distinct from v_catalog.research_area
     or v_series.research_question is distinct from v_catalog.research_question then
    raise exception 'Existing series differs from the approved metric definition'
      using errcode = '22023';
  end if;

  if v_series.current_task_id is not null and not exists (
    select 1 from public.research_tasks t
     where t.id = v_series.current_task_id
       and t.research_series_id = v_series.id
       and t.ticker = v_series.ticker
       and t.research_area = v_series.research_area
       and t.research_question = v_series.research_question
  ) then
    raise exception 'Existing current assignment does not belong to this series'
      using errcode = '55000';
  end if;

  select t.* into strict v_task
    from public.research_tasks t
   where t.id = p_task_id
   for update;

  if v_task.ticker is distinct from v_series.ticker
     or v_task.research_area is distinct from v_catalog.research_area
     or v_task.research_question is distinct from v_catalog.research_question
     or v_task.status not in ('open', 'claimed', 'completed', 'cancelled') then
    raise exception 'Legacy task changed or no longer matches the approved definition'
      using errcode = '22023';
  end if;

  if v_task.research_series_id is not null
     and v_task.research_series_id is distinct from v_series.id then
    raise exception 'Legacy task is already mapped to another series'
      using errcode = '22023';
  end if;

  if p_set_current
     and v_series.current_task_id is not null
     and v_series.current_task_id is distinct from v_task.id then
    raise exception 'Series already has a different current task'
      using errcode = '55000';
  end if;

  update public.research_tasks
     set research_series_id = v_series.id
   where id = v_task.id
     and research_series_id is null;

  if p_set_current then
    update public.commons_research_series
      set current_task_id = v_task.id, updated_at = pg_catalog.now()
     where id = v_series.id;
  end if;

  return pg_catalog.jsonb_build_object(
    'id', v_task.id,
    'ticker', v_task.ticker,
    'research_area', v_task.research_area,
    'research_question', v_task.research_question,
    'status', v_task.status
  );
end
$function$;

alter function public.commons_create_or_renew_research(text, text, text, uuid, uuid)
  owner to postgres;
alter function public.commons_bootstrap_legacy_research_task(uuid, text, text, boolean)
  owner to postgres;

revoke all on function public.commons_create_or_renew_research(text, text, text, uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.commons_create_or_renew_research(text, text, text, uuid, uuid)
  to authenticated;

revoke all on function public.commons_bootstrap_legacy_research_task(uuid, text, text, boolean)
  from public, anon, authenticated, service_role;
grant execute on function public.commons_bootstrap_legacy_research_task(uuid, text, text, boolean)
  to service_role;

-- SECTION 5: Atomic commit.
commit;

-- REVIEW CONTRACT (not an additional SQL statement): existing RPC definitions
-- must be reviewed, not mechanically rewritten. Claim only status='open' rows, or
-- status='claimed' rows whose lease
-- is expired; for mapped rows require the task to equal its series current_task_id.
-- Never claim completed/cancelled rows. Keep one-active-claim-per-user,
-- row locking, auth/owner-consent checks, and SECURITY DEFINER configuration.
-- All mapped-task RPCs must use a consistent series-before-task lock order; if
-- researcher-level locks are used, order them consistently across all RPCs too.
-- Verify commons_release_task owner/lease checks and that it only updates claim
-- fields/status; it must not update lineage. The supplied live lock report says
-- publish locks the task row only; claim_next/claim_task take user advisory locks.
-- A completed assignment is renewed only by inserting a new open task above.
-- Expired claimed work remains the same unfinished task and may be reclaimed.