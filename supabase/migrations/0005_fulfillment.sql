-- ============================================================================
-- 0005_fulfillment.sql
-- ZONECOD — Milestone 05, Migration 5 of 10
--
-- Creates: deliveries
-- Depends on: 0004_leads_orders.sql (orders)
--
-- Kept separate from orders (rather than adding shipped_at/tracking_number
-- etc. directly onto the orders table) specifically so a future carrier-API
-- integration can populate/update this table without touching the core
-- order model at all. carrier and tracking_number are nullable because no
-- concrete carrier integration is confirmed yet -- this table exists to
-- leave room for one, not because one is being built this milestone.
-- ============================================================================

create table public.deliveries (
  id                     uuid primary key default gen_random_uuid(),
  order_id               uuid not null unique references public.orders(id) on delete cascade,

  carrier                text,
  tracking_number        text,

  shipped_at             timestamptz,
  out_for_delivery_at    timestamptz,
  delivered_at           timestamptz,
  failed_at              timestamptz,
  returned_at            timestamptz,
  failure_reason         text,

  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);

comment on table public.deliveries is
  'One-to-one (or one-to-zero) with orders -- unique on order_id enforces that. A row here is only created once an order actually reaches shipping, not at order creation, so most orders will have NO deliveries row for most of their life -- that is expected, not a data-integrity problem to fix.';

comment on column public.deliveries.order_id is
  'ON DELETE CASCADE mirrors order_status_history: a safety net for a scenario (order hard-deleted) that should never actually happen in practice, since orders are meant to be status-changed, never deleted.';

comment on column public.deliveries.carrier is
  'Nullable and currently unused by any confirmed feature -- reserved for a future carrier integration. Do not treat a null value here as an error; it just means no integration has touched this order yet.';

create trigger set_deliveries_updated_at
  before update on public.deliveries
  for each row
  execute function public.set_updated_at();

create index idx_deliveries_order on public.deliveries(order_id);
create index idx_deliveries_tracking on public.deliveries(tracking_number) where tracking_number is not null;


-- ============================================================================
-- Row Level Security — enabled now, policies next milestone.
-- ============================================================================
alter table public.deliveries enable row level security;
