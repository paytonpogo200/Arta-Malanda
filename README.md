# Arta Malanda

Campaign dashboard for the Arta Malanda table.

The app uses Next.js, Supabase RPC functions, and a single rerunnable Supabase SQL runner. Keep schema, function, seed, import, and data-transition work in `supabase/RUN_THIS_IN_SUPABASE.sql`.

## Local setup

1. Copy `.env.example` to `.env.local`.
2. Add fresh Supabase project values when ready.
3. Install dependencies.
4. Run `npm run dev`.

## Supabase

Use one SQL source only:

- `supabase/RUN_THIS_IN_SUPABASE.sql`

Do not add numbered migration folders or separate data migration files. If schema or seed behavior changes, rewrite the affected section in the runner cleanly.

## Project discipline

See `docs/project-rules.md`.
