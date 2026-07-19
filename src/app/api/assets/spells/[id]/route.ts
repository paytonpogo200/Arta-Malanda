import { NextResponse } from 'next/server';
import { normalizeUpdateAssetsPayload } from '@/features/assets/data';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

export async function PATCH(request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in as the Dungeon Master to update spells.' }, { status: 401 });
    const { id } = await params;
    const patch = await request.json().catch(() => ({}));
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });
    const { data, error } = await supabase.rpc('update_spell_asset', { p_session_token: token, p_spell_id: id, p_patch: patch });
    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    return NextResponse.json(normalizeUpdateAssetsPayload(data));
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Spell could not be updated.' }, { status: 500 });
  }
}
