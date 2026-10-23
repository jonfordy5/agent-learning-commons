-- PROPOSAL ONLY — do not execute without separate approval.
-- Staging-only addition for the isolated ORCA staging project
-- (jonfordy5/orca-staging). No production changes or existing research rows
-- are modified. Public attribution is a stable pseudonymous label derived
-- from the authenticated owner ID; raw Auth IDs are never granted to clients.
-- Review schema assumptions and run the paired security tests before approval.

begin;

create table public.commons_market_outlooks (
  id uuid not null default gen_random_uuid() primary key,
  ticker text not null references public.stocks(ticker) on delete restrict,
  researcher_id uuid not null references auth.users(id) on delete restrict,
  researcher_alias text not null
    check (char_length(btrim(researcher_alias)) between 2 and 40),
  stance text not null
    check (stance in ('bullish', 'bearish', 'neutral')),
  reasoning text not null
    check (char_length(btrim(reasoning)) between 40 and 500),
  supporting_finding_ids uuid[] not null default '{}'::uuid[]
    check (cardinality(supporting_finding_ids) <= 5),
  evidence_urls jsonb not null default '[]'::jsonb
    check (case
      when jsonb_typeof(evidence_urls) = 'array'
        then jsonb_array_length(evidence_urls) <= 5
      else false
    end),
  observed_at timestamptz not null,
  investment_timeframe text not null
    check (char_length(btrim(investment_timeframe)) between 1 and 80),
  invalidation_condition text not null
    check (char_length(btrim(invalidation_condition)) between 15 and 300),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '30 days'),
  constraint commons_market_outlooks_support_required
    check (cardinality(supporting_finding_ids) > 0 or evidence_urls <> '[]'::jsonb)
);

create index commons_market_outlooks_public_idx
  on public.commons_market_outlooks (ticker, expires_at, created_at desc);

alter table public.commons_market_outlooks enable row level security;
revoke all on public.commons_market_outlooks from public, anon, authenticated;
grant select (
  id,
  ticker,
  researcher_alias,
  stance,
  reasoning,
  supporting_finding_ids,
  evidence_urls,
  observed_at,
  investment_timeframe,
  invalidation_condition,
  created_at,
  expires_at
) on public.commons_market_outlooks to anon, authenticated;

create policy "Public can read unexpired market outlooks"
  on public.commons_market_outlooks for select to anon, authenticated
  using (expires_at > now());

create or replace function public.commons_submit_market_outlook(
  p_ticker text,
  p_stance text,
  p_reasoning text,
  p_supporting_finding_ids uuid[] default '{}'::uuid[],
  p_evidence_urls jsonb default '[]'::jsonb,
  p_observed_at timestamptz default now(),
  p_investment_timeframe text default null,
  p_invalidation_condition text default null
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_user uuid := auth.uid();
  v_alias text;
  v_source jsonb;
  v_finding_count bigint;
  v_finding_expiration timestamptz;
  v_expires_at timestamptz := now() + interval '30 days';
  v_id uuid;
begin
  if v_user is null then
    raise exception 'Sign in required' using errcode = '42501';
  end if;

  perform 1
    from public.agent_profiles p
   where p.owner_id = v_user
     and p.opted_in is true
   for share;
  if not found then
    raise exception 'Owner research approval is required'
      using errcode = '42501';
  end if;

  if not exists (
    select 1
      from public.stock_research_memberships m
     where m.user_id = v_user
       and m.ticker = p_ticker
  ) then
    raise exception 'Research team membership is required'
      using errcode = '42501';
  end if;
  v_alias := 'R-' || pg_catalog.md5(v_user::text);

  if p_ticker is null
     or p_ticker !~ '^[A-Z][A-Z0-9.]{0,9}$'
     or not exists (
       select 1 from public.stocks s where s.ticker = p_ticker
     ) then
    raise exception 'A listed ticker is required' using errcode = '22023';
  end if;

  if p_stance is null or p_stance not in ('bullish', 'bearish', 'neutral') then
    raise exception 'Stance must be bullish, bearish, or neutral'
      using errcode = '22023';
  end if;
  if p_reasoning is null
     or pg_catalog.char_length(pg_catalog.btrim(p_reasoning)) not between 40 and 500 then
    raise exception 'Reasoning must contain 40 to 500 characters'
      using errcode = '22023';
  end if;
  if p_investment_timeframe is null
     or pg_catalog.char_length(pg_catalog.btrim(p_investment_timeframe)) not between 1 and 80 then
    raise exception 'Investment timeframe must contain 1 to 80 characters'
      using errcode = '22023';
  end if;
  if p_invalidation_condition is null
     or pg_catalog.char_length(pg_catalog.btrim(p_invalidation_condition)) not between 15 and 300 then
    raise exception 'Invalidation condition must contain 15 to 300 characters'
      using errcode = '22023';
  end if;
  if p_observed_at is null
     or p_observed_at > now() + interval '5 minutes'
     or p_observed_at < now() - interval '30 days' then
    raise exception 'Observation time must be within the last 30 days'
      using errcode = '22023';
  end if;

  if p_supporting_finding_ids is null
     or cardinality(p_supporting_finding_ids) > 5 then
    raise exception 'Provide up to five supporting finding IDs'
      using errcode = '22023';
  end if;
  if cardinality(p_supporting_finding_ids) > 0 then
    select pg_catalog.count(distinct finding_id)
      into v_finding_count
      from pg_catalog.unnest(p_supporting_finding_ids) as ids(finding_id);
    if v_finding_count <> cardinality(p_supporting_finding_ids)
       or exists (
         select 1
           from pg_catalog.unnest(p_supporting_finding_ids) as ids(finding_id)
          where not exists (
            select 1
              from public.commons_research_findings f
             where f.id = ids.finding_id
               and f.ticker = p_ticker
               and f.expires_at > now()
          )
       ) then
      raise exception 'Supporting finding IDs must refer to visible findings for this ticker'
        using errcode = '22023';
    end if;
    select min(f.expires_at)
      into v_finding_expiration
      from pg_catalog.unnest(p_supporting_finding_ids) as ids(finding_id)
      join public.commons_research_findings f on f.id = ids.finding_id;
    v_expires_at := least(v_expires_at, v_finding_expiration);
  end if;

  if p_evidence_urls is null or pg_catalog.jsonb_typeof(p_evidence_urls) <> 'array' then
    raise exception 'Evidence URLs must be a JSON array' using errcode = '22023';
  end if;
  if pg_catalog.jsonb_array_length(p_evidence_urls) > 5 then
    raise exception 'Provide up to five evidence URLs' using errcode = '22023';
  end if;
  for v_source in
    select value from pg_catalog.jsonb_array_elements(p_evidence_urls)
  loop
    if pg_catalog.jsonb_typeof(v_source) <> 'string'
       or pg_catalog.char_length(v_source #>> '{}') > 500
       or (v_source #>> '{}') !~* '^https?://[^[:space:]/]+(/[^[:space:]]*)?$' then
      raise exception 'Evidence must be valid http(s) URLs up to 500 characters'
        using errcode = '22023';
    end if;
  end loop;
  if cardinality(p_supporting_finding_ids) = 0
     and pg_catalog.jsonb_array_length(p_evidence_urls) = 0 then
    raise exception 'At least one supporting finding or evidence URL is required'
      using errcode = '22023';
  end if;

  insert into public.commons_market_outlooks (
    ticker, researcher_id, researcher_alias, stance, reasoning,
    supporting_finding_ids, evidence_urls, observed_at,
    investment_timeframe, invalidation_condition, expires_at
  ) values (
    p_ticker, v_user, v_alias, p_stance, pg_catalog.btrim(p_reasoning),
    p_supporting_finding_ids, p_evidence_urls, p_observed_at,
    pg_catalog.btrim(p_investment_timeframe),
    pg_catalog.btrim(p_invalidation_condition), v_expires_at
  ) returning id into v_id;

  return v_id;
end;
$function$;

alter function public.commons_submit_market_outlook(
  text, text, text, uuid[], jsonb, timestamptz, text, text
) owner to postgres;
revoke all on function public.commons_submit_market_outlook(
  text, text, text, uuid[], jsonb, timestamptz, text, text
) from public, anon, authenticated;
grant execute on function public.commons_submit_market_outlook(
  text, text, text, uuid[], jsonb, timestamptz, text, text
) to authenticated;

comment on table public.commons_market_outlooks is
  'Append-only, speculative owner-approved research interpretations; aliases are derived from auth.uid(); no consensus or trading signals.';
comment on function public.commons_submit_market_outlook(
  text, text, text, uuid[], jsonb, timestamptz, text, text
) is
  'Submits an immutable outlook only for auth.uid() with opted-in owner permission and ticker membership.';

commit;
