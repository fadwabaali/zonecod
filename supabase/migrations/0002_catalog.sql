-- ============================================================================
-- 0002_catalog.sql
-- ZONECOD — Milestone 05, Migration 2 of 10
--
-- Creates: categories, products, seller_products
-- Depends on: 0001_foundational.sql (sellers, set_updated_at())
--
-- Money note: cost and admin_margin are PER-PRODUCT (admin sets them when
-- creating a product). Confirmation/fulfillment/delivery/storage/followup
-- fees are PLATFORM-WIDE and versioned — they belong to service_fees,
-- created in 0006_financial.sql, not here. minimum_selling_price is
-- therefore NOT a stored column on products: it's cost + admin_margin +
-- (sum of currently-active service_fees), which can only be computed once
-- service_fees exists. Until 0006 lands, treat minimum-price validation as
-- an application-layer concern; a DB-level trigger enforcing it gets added
-- once service_fees is in place.
-- ============================================================================

-- ============================================================================
-- categories
--
-- Shared by both the product catalog AND the future product/white-label
-- request tables (0003 or later) — hence `type`, not a bare category list.
-- Product categories and white-label categories are different lists per
-- Wiam's confirmation, so they're modeled as the same table scoped by type,
-- rather than two separate category tables with identical shape.
-- ============================================================================
create table public.categories (
  id          uuid primary key default gen_random_uuid(),
  type        text not null check (type in ('product', 'white_label')),
  name        text not null,
  slug        text not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  -- A slug must be unique WITHIN its type, but "skin_care" could sensibly
  -- exist as both a product category and unrelated to white-label's
  -- "Skin Care" — composite uniqueness, not a bare unique on slug alone.
  unique (type, slug)
);

comment on table public.categories is
  'Flat category list (no nesting) shared by products and future product/white-label request tables, distinguished by type. Flat by deliberate choice — nested categories add real complexity with no confirmed product need yet; revisit only if a concrete requirement for subcategories shows up.';

create trigger set_categories_updated_at
  before update on public.categories
  for each row
  execute function public.set_updated_at();

create index idx_categories_type on public.categories(type);


-- ============================================================================
-- products
--
-- Platform-wide catalog, admin-controlled. Never hard-deleted — status
-- moves to 'archived' instead, since historical orders may reference a
-- product long after admin stops selling it (order-level snapshotting
-- happens later in 0004, but the product row itself must still exist to
-- snapshot FROM).
-- ============================================================================
create table public.products (
  id                  uuid primary key default gen_random_uuid(),
  category_id         uuid not null references public.categories(id),
  name                text not null,
  name_ar             text,
  description         text,
  image_url           text,
  cost                numeric(10,2) not null check (cost >= 0),
  admin_margin        numeric(10,2) not null default 0 check (admin_margin >= 0),
  stock               integer check (stock is null or stock >= 0),
  status              text not null default 'draft'
                        check (status in ('draft', 'published', 'archived')),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

comment on table public.products is
  'Admin-controlled catalog. cost and admin_margin are per-product inputs to the minimum-selling-price formula (see migration header). stock is nullable deliberately — not every product type may be stock-tracked the same way (e.g. some white-label or made-to-order flows might not track a numeric stock count); a null stock means "not tracked", not "zero available".';

comment on column public.products.admin_margin is
  'Flat per-product markup admin adds on top of total cost+fees, per Wiam: typically 2-3 DH, NOT a percentage. Do not reintroduce percentage-based margin logic here without an explicit, confirmed business rule change.';

comment on column public.products.category_id is
  'References a categories row where type = ''product''. Not DB-enforced that the referenced category is the right type (Postgres FKs can''t express that condition directly) — enforce this at the application layer when creating/editing a product, and revisit with a trigger if this becomes a real source of bugs.';

create trigger set_products_updated_at
  before update on public.products
  for each row
  execute function public.set_updated_at();

create index idx_products_category on public.products(category_id);
create index idx_products_status on public.products(status);
-- Composite: marketplace browsing almost always filters "published products
-- in category X" together, not each independently.
create index idx_products_status_category on public.products(status, category_id);


-- ============================================================================
-- seller_products
--
-- The table that actually answers "is this seller allowed to sell this
-- product" — this is why pack_items (built in 0003) will reference THIS
-- table, not products directly, so a seller can never bundle a product
-- they were never approved for.
-- ============================================================================
create table public.seller_products (
  id              uuid primary key default gen_random_uuid(),
  seller_id       uuid not null references public.sellers(id) on delete cascade,
  product_id      uuid not null references public.products(id),
  selling_price   numeric(10,2) not null check (selling_price >= 0),
  status          text not null default 'requested'
                    check (status in ('requested', 'approved', 'active', 'inactive')),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  unique (seller_id, product_id)
);

comment on table public.seller_products is
  'Join between a seller and a product they are approved to sell, with their own selling_price. selling_price >= minimum_selling_price (cost + admin_margin + active service fees) is NOT enforced here yet — service_fees does not exist until 0006. A trigger enforcing this constraint gets added once that table lands; until then, validate in the Server Action that creates/updates this row.';

comment on column public.seller_products.seller_id is
  'ON DELETE CASCADE here (unlike most FKs in this schema) is deliberate: if a seller row is hard-deleted (which should be rare/never in practice — sellers are meant to be suspended, not deleted), their seller_products rows have no independent meaning and should go with them. This does NOT cascade to orders, which reference product/pricing by snapshot, not by live join to this table.';

create trigger set_seller_products_updated_at
  before update on public.seller_products
  for each row
  execute function public.set_updated_at();

create index idx_seller_products_seller on public.seller_products(seller_id);
create index idx_seller_products_product on public.seller_products(product_id);
create index idx_seller_products_status on public.seller_products(status);


-- ============================================================================
-- Row Level Security — enabled now, policies next milestone (same pattern
-- as 0001). Note: categories and products will eventually need a PUBLIC
-- read policy (unauthenticated marketplace browsing, per your public
-- website module), unlike seller_products which is strictly owner-only —
-- flagging this distinction now so it's not forgotten when policies are
-- actually written.
-- ============================================================================
alter table public.categories      enable row level security;
alter table public.products        enable row level security;
alter table public.seller_products enable row level security;
