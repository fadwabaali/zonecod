-- ============================================================================
-- 0008_support_notifications.sql
-- ZONECOD — Milestone 05, Migration 8 of 10
--
-- Creates: support_tickets, support_messages, notifications
-- Depends on: 0001 (profiles, sellers, set_updated_at())
-- ============================================================================

-- ============================================================================
-- support_tickets
--
-- seller_id is nullable: your role matrix shows "Support Create" allowed
-- for both admin and seller, so a ticket may originate from either -- not
-- exclusively a seller-owned entity the way orders/packs are.
-- ============================================================================
create table public.support_tickets (
  id             uuid primary key default gen_random_uuid(),
  seller_id      uuid references public.sellers(id),
  created_by     uuid not null references public.profiles(id),
  subject        text not null,
  status         text not null default 'open'
                   check (status in ('open', 'in_progress', 'resolved', 'closed')),
  priority       text not null default 'normal'
                   check (priority in ('low', 'normal', 'high', 'urgent')),
  assigned_to    uuid references public.profiles(id),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

comment on table public.support_tickets is
  'created_by is always set (whoever opened the ticket) -- seller_id is additionally set when the ticket concerns a specific seller account, but an admin-initiated internal ticket might reasonably have created_by = an admin profile and seller_id = null. status/priority lists are reasonable defaults, not confirmed against a CODPLUS screenshot the way order statuses were -- flag as worth verifying if you have a support-screen reference.';

create trigger set_support_tickets_updated_at
  before update on public.support_tickets
  for each row
  execute function public.set_updated_at();

create index idx_support_tickets_seller on public.support_tickets(seller_id) where seller_id is not null;
create index idx_support_tickets_status on public.support_tickets(status);
create index idx_support_tickets_assigned on public.support_tickets(assigned_to) where assigned_to is not null;


-- ============================================================================
-- support_messages
--
-- The conversation thread within a ticket. Append-only in practice (no
-- edit/delete UI expected), though not database-enforced immutable the way
-- wallet_transactions is -- a support conversation correcting a typo isn't
-- the same integrity risk as financial history being altered, so I did not
-- add blocking triggers here. Reconsider only if abuse/moderation needs
-- surface later.
-- ============================================================================
create table public.support_messages (
  id          uuid primary key default gen_random_uuid(),
  ticket_id   uuid not null references public.support_tickets(id) on delete cascade,
  sender_id   uuid not null references public.profiles(id),
  message     text not null,
  created_at  timestamptz not null default now()
);

comment on table public.support_messages is
  'ON DELETE CASCADE from support_tickets: a message has no meaning without its parent ticket. sender_id can be the seller who opened the ticket OR the admin/agent responding -- role is looked up via profiles, not duplicated onto this table.';

create index idx_support_messages_ticket on public.support_messages(ticket_id, created_at);


-- ============================================================================
-- notifications
--
-- Deliberately generic (per the original milestone context) -- not tightly
-- coupled to any one feature. Any future module creates a notification by
-- inserting a row with the right `type` and an optional `link`, without
-- needing its own notifications sub-table.
-- ============================================================================
create table public.notifications (
  id             uuid primary key default gen_random_uuid(),
  recipient_id   uuid not null references public.profiles(id) on delete cascade,
  type           text not null,
  title          text not null,
  message        text,
  link           text,
  is_read        boolean not null default false,
  created_at     timestamptz not null default now()
);

comment on table public.notifications is
  'type is plain text, NOT a CHECK-constrained list -- deliberately open-ended so new notification types (order updates, approvals, wallet events, support replies, and whatever future modules need) can be introduced by application code alone, without a migration every time a new notification type is added. This is the one place in the schema where I chose flexibility over a locked-down constraint, specifically because the cost of a typo''d type value is low (a notification that does not render an icon correctly) compared to the cost of a migration every time a new feature wants to notify someone.';

create index idx_notifications_recipient_unread on public.notifications(recipient_id, is_read);
create index idx_notifications_created_at on public.notifications(created_at desc);


-- ============================================================================
-- Row Level Security — enabled now, policies next milestone.
-- ============================================================================
alter table public.support_tickets   enable row level security;
alter table public.support_messages  enable row level security;
alter table public.notifications     enable row level security;
