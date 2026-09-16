-- ============================================================================
-- 0010_settings.sql
-- ZONECOD — Milestone 05, Migration 10 of 10 (final migration of this milestone)
--
-- Creates: platform_settings
-- Depends on: 0001 (profiles, set_updated_at())
-- ============================================================================

-- ============================================================================
-- platform_settings
--
-- Key-value, not fixed columns -- same reasoning as notifications.type
-- being open-ended in 0008: platform-wide config needs (feature flags,
-- default values, future toggles) are not fully known yet, and a key-value
-- shape lets new settings be added by application code / a seed script
-- without a migration each time. The tradeoff is no CHECK-constrained
-- structure per setting -- validate values at the application layer when
-- reading/writing a specific known key.
-- ============================================================================
create table public.platform_settings (
  key          text primary key,
  value        jsonb not null,
  updated_by   uuid references public.profiles(id),
  updated_at   timestamptz not null default now()
);

comment on table public.platform_settings is
  'Single row per config key, value stored as jsonb so a setting can be a plain string/number/boolean or a small structured object depending on what it represents. Examples this table is likely to hold once populated: default currency display, feature flags for in-progress modules, maybe a maintenance-mode toggle -- none seeded by this migration, since no concrete setting is confirmed yet. Seed actual rows via a separate, deliberate script once you know what you need, not speculatively here.';

create trigger set_platform_settings_updated_at
  before update on public.platform_settings
  for each row
  execute function public.set_updated_at();


-- ============================================================================
-- Row Level Security — public/all-authenticated read is likely correct here
-- eventually (e.g. a maintenance-mode flag needs to be readable by
-- everyone), write restricted to admin only -- decide precisely at the
-- RLS milestone, enabling now with zero policies per the pattern used
-- throughout this whole migration set.
-- ============================================================================
alter table public.platform_settings enable row level security;


-- ============================================================================
-- END OF MILESTONE 05 SCHEMA
--
-- All ten migrations (0001-0010) together define the complete ZONECOD
-- foundational schema: profiles/sellers/agents, catalog, packs, the merged
-- orders model, fulfillment, the full financial ledger, services, support/
-- notifications, audit logging, and platform settings.
--
-- What this milestone deliberately does NOT include (see schema review §8):
-- product_requests, white_label_requests (deferred to the product-approval
-- workflow milestone -- now understood to likely be ONE table with a
-- request_type column, per Wiam's confirmation that they share the same
-- field shape), invoices, payouts, integrations/integration_orders,
-- simulation_runs, ai_generations, tutorials. "reviews" was resolved to
-- not need its own table at all -- it is the request-approval status flow
-- already captured elsewhere.
--
-- What still has zero RLS POLICIES (only RLS enabled, defaulting to
-- deny-all for non-service-role clients): every table in this migration
-- set. That is the entire next milestone.
--
-- Known open gaps carried forward, not silently fixed:
--  - Cross-seller ownership on pack_items.seller_product_id and
--    orders.seller_product_id/pack_id is not FK-enforced (0003, 0004) --
--    needs application-layer validation now, a trigger or RLS policy later.
--  - order_assignments has no enforced "at most one active assignment per
--    type" rule yet (0004) -- needs a partial unique index once the exact
--    reassignment rule is defined.
--  - wallet_transactions.payout_id has no FK yet (0006) -- add once
--    payouts is built.
--  - service_requests/support_tickets status lists are reasonable
--    defaults, not confirmed against a CODPLUS reference screenshot the
--    way order statuses were.
-- ============================================================================
