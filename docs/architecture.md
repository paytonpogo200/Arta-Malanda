# Architecture Notes

Arta Malanda is built around small feature modules instead of large all-in-one screens.

## Performance rules

- Heavy tabs are loaded only when selected.
- Collapsed sections should avoid mounting expensive content.
- Inventory, loadout, and combat tokens use small memo-friendly components.
- Typing state stays local to the form being edited.
- Drag and map movement should use refs/direct transforms instead of whole-page rerenders.
- Rarity effects should look magical without forcing every repeated cell to animate all the time.

## Data direction

The app is database-backed. Supabase schema, functions, seed data, workbook import behavior, and one-time data transitions live in `supabase/RUN_THIS_IN_SUPABASE.sql`.

There should not be separate migration folders, sidecar data imports, or old-site compatibility files. If the database model changes, rewrite the affected runner section cleanly and remove the old path in the same checkpoint.

## Feature boundaries

- `components/ui`: shared visual primitives.
- `components/app-shell`: dashboard frame/navigation.
- `components/characters`: character ledger and sheet.
- `components/inventory`: item slots, grids, loadout, containers.
- `components/battle`: map, tokens, encounter roster.
- `features/*`: data normalization and focused helpers for each feature.

## Patch discipline

See `docs/project-rules.md`. In short: fix the system that owns the problem. Do not add side-effect patches while leaving the contradiction in place.
