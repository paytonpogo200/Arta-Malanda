# Project Rules

Arta Malanda should stay clean enough to grow.

## Patch discipline

- Rewrite the affected system when a feature changes.
- Do not patch around stale behavior while leaving the stale behavior alive.
- Do not add "if old version exists, use new version instead" branches unless the branch is an isolated one-time data migration inside `supabase/RUN_THIS_IN_SUPABASE.sql`.
- Remove dead code, stale constants, old UI assumptions, and obsolete SQL in the same checkpoint that replaces them.
- If a fix reveals a deeper model problem, fix the model instead of only hiding the symptom.

## Supabase discipline

- `supabase/RUN_THIS_IN_SUPABASE.sql` is the only supported Supabase source file.
- Do not add numbered migration folders or separate data migration folders.
- Any schema, function, seed, import, or data transition must be incorporated cleanly into the one runner.
- The runner must be rerunnable and should use `create or replace function`, idempotent inserts, and explicit data transitions.

## Identity discipline

- The new app is Arta Malanda. Old-site imports can inform the data, but old-site scaffolding should not remain once the data has been absorbed.
- Imported character context is represented as previous owner context, not legacy app dependency.
