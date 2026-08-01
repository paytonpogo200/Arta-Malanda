import { NextResponse, type NextRequest } from 'next/server';
import { normalizeCharacterInventoryPayload } from '@/features/inventory/data';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

export async function GET(_request: NextRequest, context: { params: Promise<{ id: string }> }) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in to preview a trade inventory.' }, { status: 401 });

    const { id } = await context.params;
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('get_character_inventory', {
      p_session_token: token,
      p_character_id: id
    });

    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    return NextResponse.json(normalizeCharacterInventoryPayload(data));
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Trade inventory could not be loaded.' }, { status: 500 });
  }
}
