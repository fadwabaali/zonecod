-- ============================================================================
-- 0013_seller_banking.sql
-- ZONECOD — Milestone 06 (Auth & RBAC), Migration 3
--
-- Adds: sellers.city, sellers.bank, sellers.rib
-- Updates: handle_new_user() (0011) to populate them at signup
-- Depends on: 0001 (sellers), 0011 (handle_new_user)
--
-- RIB (Relevé d'Identité Bancaire) is a 24-digit Moroccan bank account
-- identifier. bank/rib are OPTIONAL per your screenshot; city is required.
-- ============================================================================

alter table public.sellers
  add column city text not null default '',
  add column bank text,
  add column rib text;

-- Drop the default now that existing rows (if any) are backfilled with ''
-- -- new rows must supply a real city, the default only exists so this
-- ALTER doesn't fail against rows that already existed before this column
-- was added.
alter table public.sellers
  alter column city drop default;

alter table public.sellers
  add constraint sellers_rib_format
    check (rib is null or rib ~ '^[0-9]{24}$');

comment on column public.sellers.city is
  'Free text, not a foreign key to a cities table -- Morocco''s city list is small and effectively static for this use case, so a whole cities table would be over-engineering per the "don''t create tables just because they sound useful" principle. The dropdown options themselves live in the frontend form as a plain constant array, not in the database.';

comment on column public.sellers.rib is
  'Optional. When present, must be exactly 24 digits (standard Moroccan RIB format). This is financial-adjacent PII -- treat it with the same care as anything in the wallet/payout system once payouts are built (that''s likely where this value actually gets used).';


-- ============================================================================
-- Update the signup trigger to populate the new columns from user_metadata.
-- CREATE OR REPLACE is safe to run even though 0011 already created this
-- function -- this is how you evolve a function across migrations without
-- editing an already-applied migration file.
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
  v_role := coalesce(new.raw_app_meta_data->>'role', 'seller');

  insert into public.profiles (id, role, full_name, phone)
  values (
    new.id,
    v_role,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    new.raw_user_meta_data->>'phone'
  );

  if v_role = 'seller' then
    insert into public.sellers (profile_id, business_name, status, city, bank, rib)
    values (
      new.id,
      coalesce(new.raw_user_meta_data->>'business_name', ''),
      'pending',
      coalesce(new.raw_user_meta_data->>'city', ''),
      new.raw_user_meta_data->>'bank',
      new.raw_user_meta_data->>'rib'
    );
  elsif v_role = 'agent' then
    insert into public.agents (profile_id, agent_type, status)
    values (new.id, coalesce(new.raw_user_meta_data->>'agent_type', 'call_center'), 'active');
  end if;

  return new;
end;
$$;
