# Arta Malanda

Campaign dashboard for the Arta Malanda table.

The app uses Next.js and Supabase RPC functions. Its rerunnable database setup is split into two ordered SQL files so each fits comfortably in the Supabase editor. Keep schema, function, seed, import, and data-transition work in those files and run Part 1 before Part 2.

## Local setup

1. Copy `.env.example` to `.env.local`.
2. Add fresh Supabase project values when ready.
3. Install dependencies.
4. Run `npm run dev`.

## Supabase

Use one SQL source only:

- `supabase/RUN_THIS_IN_SUPABASE_PART_1.sql`
- `supabase/RUN_THIS_IN_SUPABASE_PART_2.sql`

Do not add numbered migration folders or separate data migration files. If schema or seed behavior changes, rewrite the affected section in the runner cleanly.

## Project discipline

See `docs/project-rules.md`.
