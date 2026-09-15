-- ============================================================================
-- 0011_auth_trigger.sql
-- ZONECOD — Milestone 06 (Auth & RBAC), Migration 1
--
-- Creates: handle_new_user() trigger function + trigger on auth.users
-- Depends on: 0001_foundational.sql (profiles, sellers, agents)
--
-- SECURITY: role is read from raw_app_meta_data, NEVER raw_user_meta_data.
-- app_metadata can only be set via the service-role Admin API (server-only,
-- never by a browser client) -- user_metadata is client-editable and must
-- never be trusted for anything privilege-related. See conversation
-- history for the full reasoning. If you ever see role being read from
-- raw_user_meta_data anywhere in this codebase, that is a privilege
-- escalation bug, not a style choice.
-- ============================================================================

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
begin
  -- Missing app_metadata.role means this was a normal public signup --
  -- defaults to 'seller'. Only the admin-create-agent Server Action
  -- (using the service-role client) can set this to 'agent'.
  v_role := coalesce(new.raw_app_meta_data->>'role', 'seller');

  insert into public.profiles (id, role, full_name, phone)
  values (
    new.id,
    v_role,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    new.raw_user_meta_data->>'phone'
  );

  if v_role = 'seller' then
    insert into public.sellers (profile_id, business_name, status)
    values (new.id, coalesce(new.raw_user_meta_data->>'business_name', ''), 'pending');
  elsif v_role = 'agent' then
    insert into public.agents (profile_id, agent_type, status)
    values (new.id, coalesce(new.raw_user_meta_data->>'agent_type', 'call_center'), 'active');
  end if;
  -- No branch for 'admin' -- admin accounts are expected to be created
  -- directly (e.g. via the Supabase dashboard or a one-off trusted script)
  -- for the handful of real admins this platform will ever have, not
  -- through this same self-service-shaped trigger path. Revisit if that
  -- assumption turns out wrong.

  return new;
end;
$$;

comment on function public.handle_new_user is
  'security definer so it can insert into profiles/sellers/agents regardless of the caller''s RLS permissions -- account creation must always succeed as a guaranteed side effect of a new auth.users row, not something dependent on the signing-up user already having table access (which they don''t, and shouldn''t, before their profile even exists).';

create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function public.handle_new_user();
