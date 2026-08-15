import { NextResponse, type NextRequest } from 'next/server';
import { normalizeCharacterSpellsPayload } from '@/features/spells/data';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

export async function PATCH(request: NextRequest, context: { params: Promise<{ id: string }> }) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in before changing spells.' }, { status: 401 });

    const { id } = await context.params;
    const patch = await request.json().catch(() => ({}));
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const isDetailsPatch = patch && typeof patch === 'object' && ['name', 'summary', 'details', 'manaCost'].some((key) => key in patch);
    const rpcName = isDetailsPatch ? 'update_character_spell_details' : 'update_character_spell_state';
    const { data, error } = await supabase.rpc(rpcName, {
      p_session_token: token,
      p_character_spell_id: id,
      p_patch: patch
    });

    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    return NextResponse.json(normalizeCharacterSpellsPayload(data));
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Spell could not be changed.' }, { status: 500 });
  }
}
