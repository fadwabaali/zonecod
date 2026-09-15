-- ============================================================================
-- 0006_financial.sql
-- ZONECOD — Milestone 05, Migration 6 of 10
--
-- Creates: service_fees, wallets, wallet_transactions
-- Depends on: 0001 (sellers, profiles), 0002 (products, seller_products),
--             0004 (orders)
--
-- This migration also CLOSES a gap left open since 0002: seller_products
-- has never had a database-enforced minimum-price check, because that
-- check needs service_fees to exist. It exists now -- the trigger goes in
-- at the end of this file.
-- ============================================================================

-- ============================================================================
-- service_fees
--
-- Versioned fee schedule. NOT a single "current value" config table --
-- storing history is the whole point, since Wiam confirmed the delivery
-- fee specifically may change in the future, and historical orders/
-- transactions must keep reflecting whatever fee applied AT THE TIME, not
-- silently be reinterpreted when admin updates today's fee.
--
-- effective_until = null means "currently active". A partial unique index
-- below guarantees at most one active row per fee_type at any moment --
-- without it, nothing would stop two different "confirmation fee" rows
-- both being active simultaneously, which would make
-- calculate_minimum_selling_price() below ambiguous.
-- ============================================================================
create table public.service_fees (
  id                uuid primary key default gen_random_uuid(),
  fee_type          text not null
                      check (fee_type in ('confirmation', 'fulfillment', 'delivery', 'storage', 'followup')),
  amount            numeric(10,2) not null check (amount >= 0),
  effective_from    timestamptz not null default now(),
  effective_until   timestamptz,
  created_by        uuid references public.profiles(id),
  created_at        timestamptz not null default now()
);

comment on table public.service_fees is
  'Versioned, not a single current-value row per fee_type. To "change" a fee: set effective_until = now() on the old active row, then insert a new row with the new amount and effective_from = now(). Never UPDATE amount on an existing row directly -- that would silently rewrite what historical calculations meant at the time, exactly the mistake the whole snapshot principle in this schema exists to prevent.';

-- At most one ACTIVE row per fee_type. This is what makes "the current
-- confirmation fee" unambiguous for calculate_minimum_selling_price() below.
create unique index idx_service_fees_one_active_per_type
  on public.service_fees(fee_type)
  where effective_until is null;

create index idx_service_fees_type on public.service_fees(fee_type);


-- ----------------------------------------------------------------------------
-- calculate_minimum_selling_price(product_id)
--
-- Minimum Selling Price = (product.cost + product.admin_margin) +
--                          SUM(all currently-active service_fees)
--
-- Confirmed against your own screenshot math: cost 75 x2=150, fees summed
-- to 48 (8+6+34+0+0), seller sold at 150 (0 margin that time), profit
-- shown as -48 -- matches exactly.
--
-- STABLE (not IMMUTABLE): the result can change between calls as fees
-- change over time, but does not modify the database and gives consistent
-- results within a single query -- the correct volatility category for a
-- function whose only inputs are table reads.
-- ----------------------------------------------------------------------------
create or replace function public.calculate_minimum_selling_price(p_product_id uuid)
returns numeric
language plpgsql
stable
as $$
declare
  v_cost    numeric;
  v_margin  numeric;
  v_fees    numeric;
begin
  select cost, admin_margin into v_cost, v_margin
  from public.products
  where id = p_product_id;

  select coalesce(sum(amount), 0) into v_fees
  from public.service_fees
  where effective_until is null;

  return v_cost + v_margin + v_fees;
end;
$$;

comment on function public.calculate_minimum_selling_price is
  'Total Admin Cost (product cost + all active service fees) + per-product admin_margin. Used both by the enforcement trigger below and available for the application layer to show sellers "your minimum price is X" before they submit a price.';


-- ============================================================================
-- Close the gap from 0002: enforce selling_price >= minimum on seller_products
-- ============================================================================
create or replace function public.check_seller_product_minimum_price()
returns trigger
language plpgsql
as $$
declare
  v_minimum numeric;
begin
  v_minimum := public.calculate_minimum_selling_price(new.product_id);

  if new.selling_price < v_minimum then
    raise exception 'selling_price (%) is below the minimum selling price (%) for this product', new.selling_price, v_minimum;
  end if;

  return new;
end;
$$;

create trigger seller_products_enforce_minimum_price
  before insert or update of selling_price, product_id on public.seller_products
  for each row
  execute function public.check_seller_product_minimum_price();

comment on trigger seller_products_enforce_minimum_price on public.seller_products is
  'Closes the gap noted in 0002_catalog.sql: minimum-price checking could not be database-enforced until service_fees existed. From this migration onward, a seller literally cannot save a selling_price below cost+margin+active fees -- not just an application-layer validation that could be bypassed by a bug or a direct API call.';


-- ============================================================================
-- wallets
--
-- Deliberately minimal -- NO stored balance column. Per the schema review's
-- financial architecture recommendation: for a first production system,
-- a purely CALCULATED balance (see the view below) is safer than a cached
-- one, because there is nothing that can drift out of sync with the
-- ledger. Add a cached balance column later ONLY if you measure an actual
-- performance problem -- don't take on cache-drift risk preemptively.
-- ============================================================================
create table public.wallets (
  id          uuid primary key default gen_random_uuid(),
  seller_id   uuid not null unique references public.sellers(id) on delete cascade,
  created_at  timestamptz not null default now()
);

comment on table public.wallets is
  'One per seller, created once at seller approval (application logic, not enforced here). Holds no balance itself -- see wallet_transactions and the wallet_balances view below for the actual financial data.';


-- ============================================================================
-- wallet_transactions
--
-- The authoritative, immutable ledger. Every financial event a seller
-- experiences is a row here. amount is SIGNED: positive = credit (money
-- owed to the seller), negative = debit (fees, payouts already made).
-- Balance is always SUM(amount) for a wallet, never a value trusted from
-- anywhere else.
-- ============================================================================
create table public.wallet_transactions (
  id            uuid primary key default gen_random_uuid(),
  wallet_id     uuid not null references public.wallets(id),
  type          text not null
                  check (type in ('sale', 'fee', 'refund', 'payout', 'adjustment')),
  amount        numeric(10,2) not null,
  order_id      uuid references public.orders(id),
  payout_id     uuid,  -- no FK yet -- payouts table doesn't exist (deferred per the schema review, §8). Add the FK constraint in a later migration once payouts is built: alter table wallet_transactions add constraint ... references payouts(id).
  description   text,
  created_at    timestamptz not null default now()
);

comment on table public.wallet_transactions is
  'Immutable append-only ledger -- see the triggers below that make UPDATE/DELETE actually impossible, not just discouraged by convention. amount is signed: sale=positive credit, fee=negative debit, payout=negative debit, refund/adjustment=either direction depending on the specific case. Never derive a transaction''s direction from its type alone in application code -- read the sign of amount.';

comment on column public.wallet_transactions.payout_id is
  'Deliberately no foreign key constraint yet -- the payouts table is deferred (see schema review §8). This column exists now so that adding payouts later does not require altering every historical wallet_transactions row; only a constraint needs adding once that table exists.';

create index idx_wallet_transactions_wallet on public.wallet_transactions(wallet_id, created_at);
create index idx_wallet_transactions_order on public.wallet_transactions(order_id) where order_id is not null;
create index idx_wallet_transactions_type on public.wallet_transactions(type);

-- ----------------------------------------------------------------------------
-- Enforce immutability at the DATABASE level, not just by convention/comment.
-- Corrections must be a NEW offsetting transaction, never an edit to
-- history. This is the single most important integrity rule for the whole
-- financial model -- worth making literally impossible to violate, not
-- just documented.
-- ----------------------------------------------------------------------------
create or replace function public.prevent_wallet_transaction_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception 'wallet_transactions rows are immutable. Corrections must be made via a new offsetting transaction, never by editing or deleting an existing row.';
end;
$$;

create trigger wallet_transactions_no_update
  before update on public.wallet_transactions
  for each row
  execute function public.prevent_wallet_transaction_mutation();

create trigger wallet_transactions_no_delete
  before delete on public.wallet_transactions
  for each row
  execute function public.prevent_wallet_transaction_mutation();


-- ============================================================================
-- wallet_balances view
--
-- The "balance" a seller sees is always this computed sum -- never a
-- stored value read from elsewhere. This is what "purely calculated
-- balance" (recommended in the schema review) looks like in practice.
-- ============================================================================
create view public.wallet_balances as
select
  w.id as wallet_id,
  w.seller_id,
  coalesce(sum(wt.amount), 0) as balance
from public.wallets w
left join public.wallet_transactions wt on wt.wallet_id = w.id
group by w.id, w.seller_id;

comment on view public.wallet_balances is
  'Computed, not cached. Always reflects wallet_transactions exactly -- there is no separate balance value anywhere that could drift out of sync with the ledger.';


-- ============================================================================
-- Row Level Security — enabled now, policies next milestone. service_fees
-- will need a PUBLIC (or at least all-authenticated-roles) read policy
-- eventually, since minimum-price display in the marketplace UI needs it --
-- unlike wallets/wallet_transactions, which are strictly owner + admin only.
-- ============================================================================
alter table public.service_fees        enable row level security;
alter table public.wallets              enable row level security;
alter table public.wallet_transactions  enable row level security;
-- Views inherit the RLS of their underlying tables automatically in
-- Postgres/Supabase -- wallet_balances does not need its own RLS statement.
