-- ============================================================================
-- 0012_rls_policies.sql
-- ZONECOD — Milestone 06 (Auth & RBAC), Migration 2
--
-- Adds real RLS policies to every table created in Milestone 05 + the
-- profiles/sellers/agents guard triggers that stop self-privilege-escalation.
-- Before this migration, every table was "RLS enabled, zero policies" —
-- i.e. fully locked to normal clients. This is what actually opens access
-- up, precisely, per role.
-- ============================================================================

-- ============================================================================
-- Helper functions — SECURITY DEFINER so they can read profiles/sellers/
-- agents regardless of the calling user's own RLS restrictions, avoiding
-- recursive-policy problems. Every policy below calls these instead of
-- querying profiles/sellers/agents directly.
-- ============================================================================
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles where id = auth.uid() and role = 'admin'
  );
$$;

create or replace function public.is_agent()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles where id = auth.uid() and role = 'agent'
  );
$$;

create or replace function public.current_seller_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select id from public.sellers where profile_id = auth.uid();
$$;

create or replace function public.current_agent_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select id from public.agents where profile_id = auth.uid();
$$;

create or replace function public.is_assigned_to_order(p_order_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.order_assignments
    where order_id = p_order_id
      and agent_id = public.current_agent_id()
      and unassigned_at is null
  );
$$;

comment on function public.is_admin is
  'SECURITY DEFINER: reads profiles bypassing RLS, specifically so RLS policies on OTHER tables can call this without triggering profiles'' own RLS recursively. Never call this to bypass a check you actually want enforced elsewhere -- it exists only to make ownership checks writable.';


-- ============================================================================
-- Guard triggers — block privilege escalation that RLS alone cannot express
-- (RLS restricts ROWS, not individual COLUMNS within an allowed row).
--
-- auth.uid() IS NULL check: when run from the SQL Editor / a service-role
-- context with no logged-in user session, auth.uid() returns null. We
-- deliberately ALLOW the change in that case -- that path is only reachable
-- by someone with direct database/service-role access (you, bootstrapping
-- the first admin), never by a browser client. A normal authenticated
-- client request always has a real auth.uid().
-- ============================================================================
create or replace function public.prevent_unauthorized_role_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.role is distinct from old.role
     and auth.uid() is not null
     and not public.is_admin() then
    raise exception 'Only admins can change a profile''s role.';
  end if;
  return new;
end;
$$;

create trigger profiles_guard_role_change
  before update on public.profiles
  for each row
  execute function public.prevent_unauthorized_role_change();


create or replace function public.prevent_unauthorized_seller_status_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if (new.status is distinct from old.status
      or new.approved_at is distinct from old.approved_at
      or new.approved_by is distinct from old.approved_by)
     and auth.uid() is not null
     and not public.is_admin() then
    raise exception 'Only admins can change seller approval status.';
  end if;
  return new;
end;
$$;

create trigger sellers_guard_status_change
  before update on public.sellers
  for each row
  execute function public.prevent_unauthorized_seller_status_change();

comment on trigger sellers_guard_status_change on public.sellers is
  'Lets a seller update business_name freely via their own RLS UPDATE policy, but blocks them from approving/suspending themselves by editing status/approved_at/approved_by -- same pattern as profiles.role above.';


-- ============================================================================
-- profiles
-- ============================================================================
create policy profiles_select_own_or_admin
  on public.profiles for select
  using (id = auth.uid() or public.is_admin());

create policy profiles_update_own_or_admin
  on public.profiles for update
  using (id = auth.uid() or public.is_admin())
  with check (id = auth.uid() or public.is_admin());
-- No INSERT policy: rows are created exclusively by handle_new_user()
-- (SECURITY DEFINER, bypasses RLS) -- a client should never insert here
-- directly, and none can, since no policy grants it.
-- No DELETE policy: profiles are never deleted by any client.


-- ============================================================================
-- sellers
-- ============================================================================
create policy sellers_select_own_or_staff
  on public.sellers for select
  using (profile_id = auth.uid() or public.is_admin() or public.is_agent());

create policy sellers_update_own_or_admin
  on public.sellers for update
  using (profile_id = auth.uid() or public.is_admin())
  with check (profile_id = auth.uid() or public.is_admin());
-- No INSERT/DELETE: created by handle_new_user(), never deleted (suspend
-- via status instead).


-- ============================================================================
-- agents
-- ============================================================================
create policy agents_select_own_or_admin
  on public.agents for select
  using (profile_id = auth.uid() or public.is_admin());

create policy agents_update_admin_only
  on public.agents for update
  using (public.is_admin())
  with check (public.is_admin());
-- Deliberately admin-only for updates (unlike sellers) -- agent_type/status
-- changes are an admin management action, not seller-style self-editing.
-- No INSERT/DELETE: created by createAgentAccount() Server Action via the
-- service-role client, which bypasses RLS entirely.


-- ============================================================================
-- categories — public marketplace browsing, admin-only writes
-- ============================================================================
create policy categories_select_all
  on public.categories for select
  using (true);

create policy categories_write_admin_only
  on public.categories for all
  using (public.is_admin())
  with check (public.is_admin());


-- ============================================================================
-- products
-- ============================================================================
create policy products_select_published_or_staff
  on public.products for select
  using (status = 'published' or public.is_admin() or public.is_agent());

create policy products_write_admin_only
  on public.products for all
  using (public.is_admin())
  with check (public.is_admin());


-- ============================================================================
-- seller_products
-- ============================================================================
create policy seller_products_select_own_or_staff
  on public.seller_products for select
  using (seller_id = public.current_seller_id() or public.is_admin() or public.is_agent());

create policy seller_products_insert_own
  on public.seller_products for insert
  with check (seller_id = public.current_seller_id());

create policy seller_products_update_own_or_admin
  on public.seller_products for update
  using (seller_id = public.current_seller_id() or public.is_admin())
  with check (seller_id = public.current_seller_id() or public.is_admin());

create policy seller_products_delete_admin_only
  on public.seller_products for delete
  using (public.is_admin());
-- Sellers deactivate via status update, never delete their own row.


-- ============================================================================
-- packs
-- ============================================================================
create policy packs_select_own_or_admin
  on public.packs for select
  using (seller_id = public.current_seller_id() or public.is_admin());

create policy packs_insert_own
  on public.packs for insert
  with check (seller_id = public.current_seller_id());

create policy packs_update_own_or_admin
  on public.packs for update
  using (seller_id = public.current_seller_id() or public.is_admin())
  with check (seller_id = public.current_seller_id() or public.is_admin());

create policy packs_delete_own_or_admin
  on public.packs for delete
  using (seller_id = public.current_seller_id() or public.is_admin());


-- ============================================================================
-- pack_items — ownership is checked THROUGH the parent pack, since
-- pack_items has no direct seller_id column.
-- ============================================================================
create policy pack_items_select_via_pack
  on public.pack_items for select
  using (
    exists (
      select 1 from public.packs p
      where p.id = pack_items.pack_id
        and (p.seller_id = public.current_seller_id() or public.is_admin())
    )
  );

create policy pack_items_insert_via_pack
  on public.pack_items for insert
  with check (
    exists (
      select 1 from public.packs p
      where p.id = pack_items.pack_id
        and p.seller_id = public.current_seller_id()
    )
    and exists (
      -- Closes the cross-seller gap flagged back in 0003: the
      -- seller_product being added must ALSO belong to this same seller.
      select 1 from public.seller_products sp
      where sp.id = pack_items.seller_product_id
        and sp.seller_id = public.current_seller_id()
    )
  );

create policy pack_items_delete_via_pack
  on public.pack_items for delete
  using (
    exists (
      select 1 from public.packs p
      where p.id = pack_items.pack_id
        and (p.seller_id = public.current_seller_id() or public.is_admin())
    )
  );
-- No UPDATE policy: pack_items are add/remove, not edited in place --
-- change quantity by deleting and re-inserting, or add an UPDATE policy
-- later if a concrete "edit quantity in place" feature needs it.


-- ============================================================================
-- orders — the most important policy set in this migration.
-- ============================================================================
create policy orders_select_owner_or_assigned_or_admin
  on public.orders for select
  using (
    seller_id = public.current_seller_id()
    or public.is_admin()
    or public.is_assigned_to_order(id)
  );

create policy orders_insert_own
  on public.orders for insert
  with check (
    seller_id = public.current_seller_id()
    and (
      -- pack_id path: must be the seller's own pack
      (pack_id is not null and exists (
        select 1 from public.packs p
        where p.id = orders.pack_id and p.seller_id = public.current_seller_id()
      ))
      or
      -- seller_product_id path: must be the seller's own listing --
      -- closes the ownership gap flagged back in 0004.
      (seller_product_id is not null and exists (
        select 1 from public.seller_products sp
        where sp.id = orders.seller_product_id and sp.seller_id = public.current_seller_id()
      ))
    )
    or public.is_admin()
  );

create policy orders_update_assigned_or_admin
  on public.orders for update
  using (public.is_admin() or public.is_assigned_to_order(id))
  with check (public.is_admin() or public.is_assigned_to_order(id));
-- Deliberately NO seller update policy -- per your role matrix, "Change
-- Order Status: Seller ❌". Sellers can SELECT their own orders but never
-- modify them once created.
-- No DELETE policy: orders are never deleted, ever.


-- ============================================================================
-- order_status_history — read-only to clients; writes happen exclusively
-- via the SECURITY DEFINER trigger from 0004, which bypasses RLS.
-- ============================================================================
create policy order_status_history_select_via_order
  on public.order_status_history for select
  using (
    exists (
      select 1 from public.orders o
      where o.id = order_status_history.order_id
        and (
          o.seller_id = public.current_seller_id()
          or public.is_admin()
          or public.is_assigned_to_order(o.id)
        )
    )
  );
-- No INSERT/UPDATE/DELETE policies for any role -- this table is written
-- only by log_order_status_change() (SECURITY DEFINER, 0004), never
-- directly by application code.


-- ============================================================================
-- order_assignments
-- ============================================================================
create policy order_assignments_select_relevant
  on public.order_assignments for select
  using (
    agent_id = public.current_agent_id()
    or public.is_admin()
    or exists (
      select 1 from public.orders o
      where o.id = order_assignments.order_id
        and o.seller_id = public.current_seller_id()
    )
  );

create policy order_assignments_write_admin_only
  on public.order_assignments for all
  using (public.is_admin())
  with check (public.is_admin());
-- Assignment logic (who gets assigned which order) is an admin/system
-- action for now, per the original schema review's open question about
-- exact assignment rules -- revisit if agents end up self-assigning.


-- ============================================================================
-- deliveries
-- ============================================================================
create policy deliveries_select_via_order
  on public.deliveries for select
  using (
    exists (
      select 1 from public.orders o
      where o.id = deliveries.order_id
        and (
          o.seller_id = public.current_seller_id()
          or public.is_admin()
          or public.is_assigned_to_order(o.id)
        )
    )
  );

create policy deliveries_write_admin_or_assigned
  on public.deliveries for all
  using (public.is_admin() or is_assigned_to_order(order_id))
  with check (public.is_admin() or is_assigned_to_order(order_id));


-- ============================================================================
-- wallets — read own, write via admin/service-role only (no client-side
-- balance manipulation, per the financial architecture principle).
-- ============================================================================
create policy wallets_select_own_or_admin
  on public.wallets for select
  using (seller_id = public.current_seller_id() or public.is_admin());

create policy wallets_write_admin_only
  on public.wallets for all
  using (public.is_admin())
  with check (public.is_admin());


-- ============================================================================
-- wallet_transactions — read own via parent wallet; writes admin-only at
-- the RLS layer (real balance-affecting writes should go through trusted
-- server logic/service-role transactions, not ad-hoc authenticated client
-- calls, but this at least prevents a compromised seller session from
-- ever inserting a fake transaction).
-- ============================================================================
create policy wallet_transactions_select_via_wallet
  on public.wallet_transactions for select
  using (
    exists (
      select 1 from public.wallets w
      where w.id = wallet_transactions.wallet_id
        and (w.seller_id = public.current_seller_id() or public.is_admin())
    )
  );

create policy wallet_transactions_insert_admin_only
  on public.wallet_transactions for insert
  with check (public.is_admin());
-- No UPDATE/DELETE policy for anyone -- and the 0006 triggers block it
-- even for the table owner regardless, so this is belt-and-suspenders.


-- ============================================================================
-- service_fees — needs to be readable by sellers for minimum-price
-- display, admin-only writes.
-- ============================================================================
create policy service_fees_select_all
  on public.service_fees for select
  using (true);

create policy service_fees_write_admin_only
  on public.service_fees for all
  using (public.is_admin())
  with check (public.is_admin());


-- ============================================================================
-- services
-- ============================================================================
create policy services_select_active_or_admin
  on public.services for select
  using (is_active = true or public.is_admin());

create policy services_write_admin_only
  on public.services for all
  using (public.is_admin())
  with check (public.is_admin());


-- ============================================================================
-- service_requests
-- ============================================================================
create policy service_requests_select_own_or_admin
  on public.service_requests for select
  using (seller_id = public.current_seller_id() or public.is_admin());

create policy service_requests_insert_own
  on public.service_requests for insert
  with check (seller_id = public.current_seller_id());

create policy service_requests_update_admin_only
  on public.service_requests for update
  using (public.is_admin())
  with check (public.is_admin());
-- Sellers can create a request but not edit it after submission --
-- keeps the approval workflow simple; revisit if a "cancel my own
-- pending request" feature is needed later.


-- ============================================================================
-- support_tickets
-- ============================================================================
create policy support_tickets_select_relevant
  on public.support_tickets for select
  using (
    created_by = auth.uid()
    or seller_id = public.current_seller_id()
    or assigned_to = auth.uid()
    or public.is_admin()
  );

create policy support_tickets_insert_own
  on public.support_tickets for insert
  with check (created_by = auth.uid());

create policy support_tickets_update_admin_or_assigned
  on public.support_tickets for update
  using (public.is_admin() or assigned_to = auth.uid())
  with check (public.is_admin() or assigned_to = auth.uid());


-- ============================================================================
-- support_messages
-- ============================================================================
create policy support_messages_select_via_ticket
  on public.support_messages for select
  using (
    exists (
      select 1 from public.support_tickets t
      where t.id = support_messages.ticket_id
        and (
          t.created_by = auth.uid()
          or t.seller_id = public.current_seller_id()
          or t.assigned_to = auth.uid()
          or public.is_admin()
        )
    )
  );

create policy support_messages_insert_via_ticket
  on public.support_messages for insert
  with check (
    sender_id = auth.uid()
    and exists (
      select 1 from public.support_tickets t
      where t.id = support_messages.ticket_id
        and (
          t.created_by = auth.uid()
          or t.seller_id = public.current_seller_id()
          or t.assigned_to = auth.uid()
          or public.is_admin()
        )
    )
  );


-- ============================================================================
-- notifications — strictly own, mark-as-read only (no insert from
-- clients -- these are system/trigger generated).
-- ============================================================================
create policy notifications_select_own
  on public.notifications for select
  using (recipient_id = auth.uid());

create policy notifications_update_own
  on public.notifications for update
  using (recipient_id = auth.uid())
  with check (recipient_id = auth.uid());


-- ============================================================================
-- audit_logs — admin read-only. No client can ever write here; only
-- trusted server-side logging code using the service-role client.
-- ============================================================================
create policy audit_logs_select_admin_only
  on public.audit_logs for select
  using (public.is_admin());


-- ============================================================================
-- platform_settings — readable by anyone (e.g. a maintenance-mode flag
-- needs to be checkable before the user is even authenticated), admin
-- writes only.
-- ============================================================================
create policy platform_settings_select_all
  on public.platform_settings for select
  using (true);

create policy platform_settings_write_admin_only
  on public.platform_settings for all
  using (public.is_admin())
  with check (public.is_admin());
