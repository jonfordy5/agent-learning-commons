-- ORCA staging-only profile creation and owner consent controls.
-- Apply only to the dedicated ORCA staging project after verifying its
-- project reference. This does not modify existing profiles, assignments,
-- sessions, or findings.

begin;

do $$
begin
  if not exists (
    select 1
      from pg_catalog.pg_class c
      join pg_catalog.pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
       and c.relname = 'agent_profiles'
       and c.relrowsecurity
  ) then
    raise exception 'RLS must be enabled on public.agent_profiles';
  end if;
end;
$$;

-- Clients may create only an opted-out profile through the owner-scoped
-- INSERT policy. Column grants below also prevent submitting opted_in.
drop policy if exists "ORCA profiles start owner-scoped and opted out"
  on public.agent_profiles;

create policy "ORCA profiles start owner-scoped and opted out"
  on public.agent_profiles as restrictive
  for insert to authenticated
  with check (
    owner_id = (select auth.uid())
    and opted_in is false
  );

revoke insert on table public.agent_profiles from public, anon, authenticated;
revoke insert (
  id, owner_id, display_name, opted_in, created_at
) on table public.agent_profiles from public, anon, authenticated;
grant insert (owner_id, display_name)
  on table public.agent_profiles to authenticated;

-- Replace any broad/column-level client UPDATE grants. Profile-name edits
-- remain available; owner_id and opted_in remain server-controlled.
revoke update on table public.agent_profiles from public, anon, authenticated;
revoke update (
  id, owner_id, display_name, opted_in, created_at
) on table public.agent_profiles from public, anon, authenticated;
grant update (display_name) on table public.agent_profiles to authenticated;

create or replace function public.commons_create_my_agent_profile(
  p_display_name text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_profile public.agent_profiles%rowtype;
begin
  if v_user_id is null then
    raise exception 'Sign in required' using errcode = '42501';
  end if;

  if p_display_name is null
     or pg_catalog.char_length(pg_catalog.btrim(p_display_name)) not between 1 and 60 then
    raise exception 'Agent name must contain 1 to 60 characters'
      using errcode = '22023';
  end if;

  insert into public.agent_profiles (owner_id, display_name, opted_in)
  values (v_user_id, pg_catalog.btrim(p_display_name), false)
  on conflict (owner_id) do nothing;

  select p.* into strict v_profile
    from public.agent_profiles p
   where p.owner_id = v_user_id;

  return pg_catalog.jsonb_build_object(
    'id', v_profile.id,
    'display_name', v_profile.display_name,
    'opted_in', v_profile.opted_in
  );
end;
$function$;

create or replace function public.commons_set_my_research_consent(
  p_opted_in boolean
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_profile public.agent_profiles%rowtype;
begin
  if v_user_id is null then
    raise exception 'Sign in required' using errcode = '42501';
  end if;

  if p_opted_in is null then
    raise exception 'Explicit consent value is required' using errcode = '22023';
  end if;

  update public.agent_profiles p
     set opted_in = p_opted_in
   where p.owner_id = v_user_id
  returning p.* into v_profile;

  if not found then
    raise exception 'Create your agent profile before changing permission'
      using errcode = '42501';
  end if;

  return pg_catalog.jsonb_build_object(
    'authenticated', true,
    'agent', pg_catalog.jsonb_build_object(
      'id', v_profile.id,
      'display_name', v_profile.display_name,
      'opted_in', v_profile.opted_in
    ),
    'consent_enabled', v_profile.opted_in
  );
end;
$function$;

alter function public.commons_create_my_agent_profile(text) owner to postgres;
alter function public.commons_set_my_research_consent(boolean) owner to postgres;

revoke all on function public.commons_create_my_agent_profile(text)
  from public, anon, authenticated;
revoke all on function public.commons_set_my_research_consent(boolean)
  from public, anon, authenticated;
grant execute on function public.commons_create_my_agent_profile(text)
  to authenticated;
grant execute on function public.commons_set_my_research_consent(boolean)
  to authenticated;

commit;
