import { NextResponse, type NextRequest } from 'next/server';
import { normalizeCharacter } from '@/features/characters/data';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

export async function PATCH(request: NextRequest, context: { params: Promise<{ id: string }> }) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in before changing gift access.' }, { status: 401 });

    const { id } = await context.params;
    const body = await request.json().catch(() => ({}));
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('set_character_gift_inventory_open', {
      p_session_token: token,
      p_character_id: id,
      p_open: Boolean(body.open)
    });

    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    return NextResponse.json({ character: normalizeCharacter(data) });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Gift access could not be changed.' }, { status: 500 });
  }
}
