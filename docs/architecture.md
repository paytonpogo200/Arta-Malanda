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

The rebuild targets a fresh Supabase schema. During early development, the UI can run against typed mock data so the interface can be tested before database setup.

## Feature boundaries

- `components/ui`: shared visual primitives.
- `components/app-shell`: dashboard frame/navigation.
- `components/characters`: character ledger and sheet.
- `components/inventory`: item slots, grids, loadout, containers.
- `components/battle`: map, tokens, encounter roster.
- `features/campaign`: local campaign state and future data gateway.
