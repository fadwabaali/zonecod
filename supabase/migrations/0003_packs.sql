-- ============================================================================
-- 0003_packs.sql
-- ZONECOD — Milestone 05, Migration 3 of 10
--
-- Creates: packs, pack_items
-- Depends on: 0001_foundational.sql (sellers, set_updated_at())
--             0002_catalog.sql (seller_products)
-- ============================================================================

-- ============================================================================
-- packs
--
-- Seller-created bundles of products they're approved to sell. Owned
-- entirely by the seller who created it — admin gets read access for
-- oversight (via RLS, next milestone), never write.
-- ============================================================================
create table public.packs (
  id          uuid primary key default gen_random_uuid(),
  seller_id   uuid not null references public.sellers(id) on delete cascade,
  name        text not null,
  status      text not null default 'active'
                check (status in ('active', 'archived')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

comment on table public.packs is
  'Seller-owned product bundles. ON DELETE CASCADE from sellers is deliberate here (same reasoning as seller_products in 0002): a pack has no meaning without its owning seller. archived status, not hard deletion, is the normal way a seller retires a pack — this keeps historical orders that referenced it (once orders exist in 0004) intact.';

create trigger set_packs_updated_at
  before update on public.packs
  for each row
  execute function public.set_updated_at();

create index idx_packs_seller on public.packs(seller_id);
create index idx_packs_status on public.packs(status);


-- ============================================================================
-- pack_items
--
-- Junction table: packs <-> seller_products. References seller_products,
-- NOT products directly — this is the security-relevant decision from the
-- schema review. If this referenced products directly, a seller could add
-- ANY platform product to their pack, including ones they were never
-- approved to sell. Referencing seller_products (the row that proves THIS
-- seller is approved for THIS product) makes that mistake structurally
-- impossible at the database level, not just something application code
-- has to remember to check.
--
-- price_at_add is a snapshot of seller_products.selling_price at the moment
-- the item was added to the pack — same historical-accuracy principle as
-- everywhere else in this schema. If the seller later changes their selling
-- price on that product, packs that already included it at the old price
-- don't silently change. (Whether pack pricing should ever "refresh" to
-- current prices is a product decision, not a database one — for now the
-- schema preserves the snapshot; the application layer can choose to show
-- both the snapshot and the current live price if useful.)
-- ============================================================================
create table public.pack_items (
  id                  uuid primary key default gen_random_uuid(),
  pack_id             uuid not null references public.packs(id) on delete cascade,
  seller_product_id   uuid not null references public.seller_products(id),
  quantity            integer not null default 1 check (quantity > 0),
  price_at_add        numeric(10,2) not null check (price_at_add >= 0),
  created_at          timestamptz not null default now(),

  -- A pack shouldn't contain the same seller_product twice as separate
  -- rows — if the seller wants more of it, that's what quantity is for.
  unique (pack_id, seller_product_id)
);

comment on table public.pack_items is
  'Junction between packs and seller_products (never products directly — see table header). ON DELETE CASCADE from packs: a pack_item has no meaning without its parent pack. No cascade from seller_products deliberately — if a seller deactivates a seller_products row, existing pack_items should NOT disappear silently; that is a product decision (do inactive-product packs still display? get flagged?) to resolve at the application layer, not something the database should decide unilaterally by deleting history.';

comment on column public.pack_items.price_at_add is
  'Snapshot of seller_products.selling_price at the time this item was added — not a live join. See table comment for reasoning.';

create index idx_pack_items_pack on public.pack_items(pack_id);
create index idx_pack_items_seller_product on public.pack_items(seller_product_id);


-- ============================================================================
-- Row Level Security — enabled now, policies next milestone.
-- ============================================================================
alter table public.packs      enable row level security;
alter table public.pack_items enable row level security;
