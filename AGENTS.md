# Arta Malanda Codex Instructions

- Rewrite the affected module or SQL section when changing behavior.
- Do not layer override code on top of stale code and leave the stale path alive.
- Remove dead code, stale constants, obsolete files, and old assumptions in the same checkpoint that replaces them.
- `supabase/RUN_THIS_IN_SUPABASE.sql` is the only supported Supabase source. Do not create migration folders, separate data migration files, or alternate SQL runners.
- Old app exports may inform current data, but the new repo should not keep old-app compatibility scaffolding after that data has been absorbed.
- Every pushed checkpoint must pass typecheck and production build.
