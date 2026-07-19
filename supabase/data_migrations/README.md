# Data migrations

These files are one-time campaign data imports. They are separate from `supabase/RUN_THIS_IN_SUPABASE.sql` on purpose.

Run order:

1. Run `supabase/RUN_THIS_IN_SUPABASE.sql`.
2. Run the desired file in this folder.

`202607190001_import_old_campaign_unclaimed.sql` imports the old live campaign export while keeping old player-owned characters unclaimed. The original owner display name is preserved on each migrated character as `legacy_owner_name`, so the DM can later assign the character to a newly created account.

This migration intentionally does not create login accounts or passwords for old players.
