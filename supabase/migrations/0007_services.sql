-- ============================================================================
-- 0007_services.sql
-- ZONECOD — Milestone 05, Migration 7 of 10
--
-- Creates: services, service_requests
-- Depends on: 0001 (sellers, set_updated_at())
--
-- NOTE: do not confuse this `services` table with service_fees from 0006.
-- service_fees = platform operational costs baked into every order
-- (confirmation, fulfillment, delivery...). services/service_requests here
-- = optional extra offerings a seller can request (per your module list --
-- distinct concept, just an unfortunately similar name).
-- ============================================================================

-- ============================================================================
-- services
--
-- Admin-controlled catalog of optional services sellers can request.
-- ============================================================================
create table public.services (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,
  description  text,
  price        numeric(10,2) not null check (price >= 0),
  is_active    boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

comment on table public.services is
  'Admin-controlled. is_active (not archived/deleted) governs whether sellers can currently request it -- kept as a simple boolean here rather than the draft/published/archived status pattern used on products, since services do not need a draft-review stage on the evidence available so far. Revisit if that turns out wrong.';

create trigger set_services_updated_at
  before update on public.services
  for each row
  execute function public.set_updated_at();

create index idx_services_active on public.services(is_active);


-- ============================================================================
-- service_requests
--
-- A seller's request for a service, with a price SNAPSHOT -- same
-- historical-accuracy principle as everywhere else. If admin changes
-- services.price after a seller requests it, that seller's already-made
-- request should not silently change price underneath them.
-- ============================================================================
create table public.service_requests (
  id               uuid primary key default gen_random_uuid(),
  seller_id        uuid not null references public.sellers(id),
  service_id       uuid not null references public.services(id),
  price_snapshot   numeric(10,2) not null check (price_snapshot >= 0),
  status           text not null default 'pending'
                     check (status in ('pending', 'approved', 'rejected')),
  notes            text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

comment on table public.service_requests is
  'price_snapshot is captured from services.price at the moment the request is created (application-layer responsibility -- the INSERT statement must read the current price and pass it explicitly, not just reference service_id and assume a later join). status list here is a reasonable default, not confirmed by Wiam the way order statuses were -- flag as Decision Required if the actual admin UI needs more granularity (e.g. an in-progress state between approved and complete).';

create trigger set_service_requests_updated_at
  before update on public.service_requests
  for each row
  execute function public.set_updated_at();

create index idx_service_requests_seller on public.service_requests(seller_id);
create index idx_service_requests_status on public.service_requests(status);


-- ============================================================================
-- Row Level Security — enabled now, policies next milestone.
-- ============================================================================
alter table public.services         enable row level security;
alter table public.service_requests enable row level security;
