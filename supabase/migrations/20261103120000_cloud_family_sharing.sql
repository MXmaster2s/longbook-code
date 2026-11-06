-- longbook Cloud through Family Sharing: each family member's copy is its own transaction,
-- recorded on their own account. The row says whose it is, so a family copy never takes the
-- place of the account's own subscription. Rows from before read as the subscriber's own.
alter table public.cloud_subscriptions
  add column if not exists apple_ownership text not null default 'PURCHASED'
    check (apple_ownership in ('PURCHASED', 'FAMILY_SHARED'));

-- Kept for the server, as the Apple ids are: the client's named-column grant is unchanged.
