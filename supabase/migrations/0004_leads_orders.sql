-- ============================================================================
-- 0004_leads_orders.sql
-- ZONECOD — Milestone 05, Migration 4 of 10
--
-- Creates: orders, order_status_history, order_assignments
-- Depends on: 0001_foundational.sql (sellers, agents, profiles, set_updated_at())
--             0002_catalog.sql (seller_products)
--             0003_packs.sql (packs)
--
-- NO separate `leads` table. Per the CODPLUS reference screenshots you
-- provided, a "lead" is just an order in status = 'new_lead' — same row,
-- same table, same id for the entire lifecycle. See conversation history
-- for the evidence (Orders page titled with lead+order language, "Total
-- Leads" and "Delivered Orders" as the same underlying count on the admin
-- dashboard). If this assumption turns out wrong once you see more of the
-- product, this migration is the one to revisit first.
--
-- NO order_items table. Per the Create Lead screenshots, an order
-- references exactly ONE seller_product OR ONE pack, with a quantity —
-- not a multi-item cart. Simpler than a typical e-commerce order model,
-- and matches the actual reference product rather than a generic assumption.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Order number generation: human-readable identifier shown to sellers/agents
-- (e.g. COD-260911774 in your screenshots), separate from the internal uuid
-- primary key. A sequence guarantees no two orders ever collide. Exact
-- format is cosmetic — adjust the expression below if you want to match
-- CODPLUS's exact pattern more closely once you confirm it (looks
-- date-prefixed, not fully confirmed from the screenshot alone).
-- ----------------------------------------------------------------------------
create sequence public.order_number_seq;

create or replace function public.generate_order_number()
returns text
language sql
as $$
  select 'COD-' || to_char(now(), 'YYMMDD') || lpad(nextval('public.order_number_seq')::text, 4, '0');
$$;


-- ============================================================================
-- orders
--
-- Central table of the whole platform. Never hard-deleted — 'canceled' is
-- a status, not a row removal. Represents the FULL lifecycle from initial
-- lead creation through delivery/return.
-- ============================================================================
create table public.orders (
  id                    uuid primary key default gen_random_uuid(),
  order_number          text not null unique default public.generate_order_number(),

  seller_id             uuid not null references public.sellers(id),

  -- Exactly one of these two is set — an order sells either a single
  -- seller_product OR a pack, never both, never neither. Enforced below
  -- by CHECK, not left to application code alone to get right.
  seller_product_id     uuid references public.seller_products(id),
  pack_id                uuid references public.packs(id),

  quantity              integer not null default 1 check (quantity > 0),

  -- Snapshots, not live joins — same principle as seller_products/pack_items.
  -- Once this order exists, changing the underlying product/pack price
  -- must NOT change what this order shows or what the seller's profit
  -- calculation is based on.
  item_name_snapshot    text not null,
  unit_price_snapshot   numeric(10,2) not null check (unit_price_snapshot >= 0),
  total_amount          numeric(10,2) not null check (total_amount >= 0),

  customer_name         text not null,
  customer_phone        text not null,
  customer_address      text not null,
  customer_city         text not null,

  source                text not null default 'manual'
                          check (source in ('manual', 'google_sheet_import', 'store_integration')),

  status                text not null default 'new_lead'
                          check (status in (
                            'new_lead', 'no_answer', 'call_later', 'injoignable', 'report',
                            'awaiting_confirmation', 'voicemail', 'confirmed', 'preparing',
                            'fulfilled', 'product_unavailable', 'in_delivery', 'delivered',
                            'returned', 'refused', 'canceled', 'fake_order', 'duplicate_order'
                          )),

  notes                 text,

  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),

  constraint orders_exactly_one_item check (
    (seller_product_id is not null and pack_id is null)
    or
    (seller_product_id is null and pack_id is not null)
  )
);

comment on table public.orders is
  'Merged lead+order entity — status=''new_lead'' at creation, progresses through the same row. See migration header for the reasoning and the evidence this is based on. status list is provisional per your master context even though it came from Wiam directly this time — if she revises it, this CHECK constraint is a single migration to update, not a structural change (this is exactly why status is text+CHECK, not a native Postgres enum).';

comment on column public.orders.seller_product_id is
  'Ownership check (this seller_product actually belongs to this order''s seller_id) is NOT enforced by this foreign key alone — same gap as pack_items in 0003. Enforce in the Server Action that creates orders, and revisit with a trigger if needed once RLS is written.';

comment on column public.orders.source is
  'manual = seller-created via the Create Lead flow (must reference a seller_product/pack the seller is actually approved for -- application-layer check). google_sheet_import / store_integration = bulk-created; these still go through the same table and status lifecycle, just a different creation path for traceability.';

create trigger set_orders_updated_at
  before update on public.orders
  for each row
  execute function public.set_updated_at();

-- These are the highest-value indexes in the whole schema — orders is the
-- table every dashboard, every list view, every agent queue queries most.
create index idx_orders_seller on public.orders(seller_id);
create index idx_orders_status on public.orders(status);
create index idx_orders_seller_status on public.orders(seller_id, status);
create index idx_orders_created_at on public.orders(created_at desc);


-- ============================================================================
-- order_status_history
--
-- Append-only audit trail. Never updated, never deleted. Auto-populated by
-- a trigger below rather than trusting every piece of application code that
-- touches orders.status to remember to also write a history row -- the
-- database guarantees this happens, not a convention developers have to
-- remember.
-- ============================================================================
create table public.order_status_history (
  id                uuid primary key default gen_random_uuid(),
  order_id          uuid not null references public.orders(id) on delete cascade,
  previous_status   text,
  new_status        text not null,
  changed_by        uuid references public.profiles(id),
  reason            text,
  created_at        timestamptz not null default now()
);

comment on table public.order_status_history is
  'Append-only. previous_status is null for the very first row (order creation). changed_by is nullable to allow system-triggered changes (e.g. a future automated timeout rule) with no human actor. ON DELETE CASCADE from orders is safe here despite the "never delete financial/audit history" principle elsewhere, because orders themselves are never actually hard-deleted in practice -- this cascade exists only as a structural safety net, not a path expected to trigger.';

create index idx_order_status_history_order on public.order_status_history(order_id);

-- Auto-log every status change (including the initial creation) so no
-- application code path can accidentally update orders.status without
-- leaving a history trail.
create or replace function public.log_order_status_change()
returns trigger
language plpgsql
security definer
as $$
begin
  if TG_OP = 'INSERT' then
    insert into public.order_status_history (order_id, previous_status, new_status, changed_by)
    values (new.id, null, new.status, auth.uid());
  elsif TG_OP = 'UPDATE' and old.status is distinct from new.status then
    insert into public.order_status_history (order_id, previous_status, new_status, changed_by)
    values (new.id, old.status, new.status, auth.uid());
  end if;
  return new;
end;
$$;

comment on function public.log_order_status_change is
  'security definer so this can insert into order_status_history even for callers whose RLS policy (written next milestone) might not otherwise grant them direct insert access to that table -- the history log should be a guaranteed side effect of a status change, not something the caller needs separate permission for. auth.uid() will be null for service-role/system-triggered changes, which order_status_history.changed_by already allows.';

create trigger orders_log_status_change
  after insert or update on public.orders
  for each row
  execute function public.log_order_status_change();


-- ============================================================================
-- order_assignments
--
-- Tracks which agent is/was responsible for an order over time. NOT a
-- single orders.agent_id column -- see the schema review for why: this
-- loses reassignment history and can't represent an order needing both a
-- call-center agent AND a packaging agent at different (or overlapping)
-- points in its lifecycle.
-- ============================================================================
create table public.order_assignments (
  id                uuid primary key default gen_random_uuid(),
  order_id          uuid not null references public.orders(id) on delete cascade,
  agent_id          uuid not null references public.agents(id),
  assignment_type   text not null check (assignment_type in ('call_center', 'packaging')),
  assigned_by       uuid references public.profiles(id),
  assigned_at       timestamptz not null default now(),
  unassigned_at     timestamptz
);

comment on table public.order_assignments is
  'unassigned_at is null for the currently-active assignment of a given (order_id, assignment_type) pair. Multiple historical rows can exist for the same order+type if it was reassigned. Application logic (or a future partial-unique-index) should ensure at most one ACTIVE (unassigned_at is null) assignment per (order_id, assignment_type) -- not enforced by a plain constraint yet since Postgres partial unique indexes are the right tool here and are worth adding once real assignment logic is built, rather than guessing the exact rule now.';

create index idx_order_assignments_order on public.order_assignments(order_id);
create index idx_order_assignments_agent on public.order_assignments(agent_id);
-- Fast "does this order currently have an active assignment" check.
create index idx_order_assignments_active on public.order_assignments(order_id, assignment_type) where unassigned_at is null;


-- ============================================================================
-- Row Level Security — enabled now, policies next milestone.
-- ============================================================================
alter table public.orders                enable row level security;
alter table public.order_status_history  enable row level security;
alter table public.order_assignments     enable row level security;
