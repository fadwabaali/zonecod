-- ============================================================================
-- 0009_audit.sql
-- ZONECOD — Milestone 05, Migration 9 of 10
--
-- Creates: audit_logs
-- Depends on: 0001 (profiles)
-- ============================================================================

create table public.audit_logs (
  id            uuid primary key default gen_random_uuid(),
  actor_id      uuid references public.profiles(id),
  action        text not null,
  target_table  text not null,
  target_id     uuid,
  metadata      jsonb,
  created_at    timestamptz not null default now()
);

comment on table public.audit_logs is
  'Append-only, immutable -- see triggers below, same pattern as wallet_transactions. actor_id is nullable for system-triggered actions (e.g. an automated status-timeout rule) with no human actor. target_table/target_id together identify what was acted on, without a formal foreign key -- deliberately, since this table needs to reference rows across MANY different tables (any table in the schema could be an audit target), and a single polymorphic foreign key is not something Postgres supports directly. The tradeoff: referential integrity for target_id is NOT database-enforced -- application code is responsible for writing correct values here.';

comment on column public.audit_logs.metadata is
  'SECURITY: keep this lean and purposeful. Do NOT store full request bodies, raw IP addresses beyond what is genuinely needed, passwords/tokens, or anything resembling sensitive personal data here. Audit logs are frequently under-protected relative to how much they can reveal if this column becomes a dumping ground -- write only the specific fields relevant to understanding what changed (e.g. {"old_status": "...", "new_status": "..."}), not entire row snapshots.';

create index idx_audit_logs_target on public.audit_logs(target_table, target_id);
create index idx_audit_logs_actor on public.audit_logs(actor_id) where actor_id is not null;
create index idx_audit_logs_created_at on public.audit_logs(created_at desc);
create index idx_audit_logs_action on public.audit_logs(action);

-- ----------------------------------------------------------------------------
-- Immutability, same principle as wallet_transactions in 0006 -- an audit
-- log that can be edited or deleted after the fact defeats its entire
-- purpose. Separate function (not reusing prevent_wallet_transaction_mutation)
-- so the error message is accurate to which table actually rejected the write.
-- ----------------------------------------------------------------------------
create or replace function public.prevent_audit_log_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception 'audit_logs rows are immutable and cannot be updated or deleted.';
end;
$$;

create trigger audit_logs_no_update
  before update on public.audit_logs
  for each row
  execute function public.prevent_audit_log_mutation();

create trigger audit_logs_no_delete
  before delete on public.audit_logs
  for each row
  execute function public.prevent_audit_log_mutation();


-- ============================================================================
-- Row Level Security — enabled now, policies next milestone. Note for that
-- milestone: even admin access to audit_logs may warrant restriction (e.g.
-- logs of admin's OWN actions being reviewable by a different admin, not
-- self-auditable) -- worth a specific conversation with Wiam rather than
-- defaulting to "admin sees everything" without thinking about it.
-- ============================================================================
alter table public.audit_logs enable row level security;
