# Arta Malanda

Clean rebuild of the Ladders and Snakes campaign table.

This repo is intentionally separate from the live production app. The goal is to rebuild the core systems with a performance-first architecture while preserving the same fantasy/parchment identity.

## First preview target

- Auth shell
- Dashboard shell
- Character ledger
- Character sheet
- Inventory and loadout
- Battlemap and combat roster

## Local setup

1. Copy `.env.example` to `.env.local`.
2. Add fresh Supabase project values when ready.
3. Install dependencies.
4. Run `npm run dev`.

The app can render its first core preview with local mock campaign data while the fresh Supabase project/schema is being prepared.
