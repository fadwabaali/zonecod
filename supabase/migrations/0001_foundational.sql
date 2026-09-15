-- ============================================================================
-- 0001_foundational.sql
-- ZONECOD — Milestone 05, Migration 1 of 10
--
-- Creates: profiles, sellers, agents
-- Depends on: auth.users (Supabase-managed, already exists)
--
-- These three tables are the identity foundation everything else in the
-- product depends on. No RLS policies yet — that's the Auth/RBAC milestone.
-- This migration only creates structure + ownership columns that RLS will
-- later be written against.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Reusable trigger function: auto-update `updated_at` on every row update.
-- Defined once here, reused by every table in every future migration —
-- avoids every table needing its own copy of this logic.
-- ----------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ============================================================================
-- profiles
--
-- One row per authenticated user, regardless of role. Extends Supabase's
-- auth.users with app-specific identity data.
--
-- id is NOT a freshly generated UUID — it IS auth.users.id, via foreign key.
-- This is what links "who is logged in" (Supabase Auth) to "who are they in
-- our app" (this table). ON DELETE CASCADE: if the auth user is ever removed,
-- their profile goes too — an auth user with no profile has no meaning here.
-- ============================================================================
create table public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  role        text not null check (role in ('admin', 'agent', 'seller')),
  full_name   text not null,
  phone       text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

comment on table public.profiles is
  'One row per authenticated user. role determines which of sellers/agents this user also has a row in. role changes must go through admin-controlled server logic, never a direct user update — enforced at the RLS/authorization layer in the next milestone, not here.';

create trigger set_profiles_updated_at
  before update on public.profiles
  for each row
  execute function public.set_updated_at();

-- Index: every "who is this user / what's their role" lookup filters on role
-- at least implicitly via RLS policies checked on nearly every query in the
-- app. Cheap to add now, expensive to realize you need it after the table
-- has real data.
create index idx_profiles_role on public.profiles(role);


-- ============================================================================
-- sellers
--
-- One-to-one with profiles where role = 'seller'. Kept as a separate table
-- rather than columns on profiles — a seller's fields (business_name,
-- approval status) have no meaning for an agent or admin, and vice versa.
-- Keeping them apart avoids a profiles table full of nulls and keeps
-- per-role RLS policies simple to write later.
-- ============================================================================
create table public.sellers (
  id            uuid primary key default gen_random_uuid(),
  profile_id    uuid not null unique references public.profiles(id) on delete cascade,
  business_name text not null,
  status        text not null default 'pending'
                  check (status in ('pending', 'active', 'suspended')),
  approved_at   timestamptz,
  approved_by   uuid references public.profiles(id),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

comment on table public.sellers is
  'Seller-specific fields, one-to-one with profiles. status governs the signup-approval workflow: pending until admin approves, suspended is a soft-deactivation — sellers are never hard-deleted since they will eventually be referenced by orders, wallets, and other historical records.';

comment on column public.sellers.profile_id is
  'UNIQUE enforces the one-to-one relationship with profiles — a profile can have at most one seller row.';

comment on column public.sellers.approved_by is
  'References the admin profile that approved this seller. Nullable — null until approved. No ON DELETE behavior specified deliberately: if that admin profile is ever removed, we want this to fail loudly (default RESTRICT) rather than silently orphan the approval record.';

create trigger set_sellers_updated_at
  before update on public.sellers
  for each row
  execute function public.set_updated_at();

create index idx_sellers_status on public.sellers(status);
-- profile_id already has an implicit index from the UNIQUE constraint above,
-- no separate index needed for it.


-- ============================================================================
-- agents
--
-- One-to-one with profiles where role = 'agent'. Mirrors sellers structurally.
-- agent_type distinguishes call-center vs packaging/fulfillment agents, per
-- the two operational functions described in the master project context —
-- this matters later for order_assignments.assignment_type routing.
-- ============================================================================
create table public.agents (
  id          uuid primary key default gen_random_uuid(),
  profile_id  uuid not null unique references public.profiles(id) on delete cascade,
  agent_type  text not null check (agent_type in ('call_center', 'packaging')),
  status      text not null default 'active'
                check (status in ('active', 'suspended')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

comment on table public.agents is
  'Agent-specific fields, one-to-one with profiles. agent_type is intentionally NOT nullable — an agent must be classified as call_center or packaging at creation, since order_assignments.assignment_type routing depends on knowing which kind of work this agent does.';

create trigger set_agents_updated_at
  before update on public.agents
  for each row
  execute function public.set_updated_at();

create index idx_agents_type on public.agents(agent_type);
create index idx_agents_status on public.agents(status);


-- ============================================================================
-- Row Level Security — enabled now, policies written in the next milestone.
--
-- Enabling RLS with zero policies means these tables are currently
-- INACCESSIBLE to anyone using the anon/authenticated Supabase client (the
-- browser/server clients from your setup guide) — only the service-role
-- admin client can read/write them until policies exist. This is the correct
-- default: fail closed, not open. Don't be alarmed if a query from
-- lib/supabase/server.ts returns nothing/errors right now — that's RLS
-- doing exactly what it should before real policies are written.
-- ============================================================================
alter table public.profiles enable row level security;
alter table public.sellers  enable row level security;
alter table public.agents   enable row level security;
