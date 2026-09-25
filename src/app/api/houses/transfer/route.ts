import { NextResponse, type NextRequest } from 'next/server';
import { normalizeHousePayload } from '@/features/houses/data';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

export async function POST(request: NextRequest) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in before moving items between properties.' }, { status: 401 });
    const body = await request.json().catch(() => ({}));
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });
    const { data, error } = await supabase.rpc('move_item_between_homes', {
      p_session_token: token,
      p_actor_character_id: body.actorCharacterId || null,
      p_item_id: String(body.itemId ?? ''),
      p_source_home_id: String(body.sourceHomeId ?? ''),
      p_source: String(body.source ?? ''),
      p_destination_home_id: String(body.destinationHomeId ?? ''),
      p_destination: String(body.destination ?? ''),
      p_slot_index: Number(body.slotIndex),
      p_parent_item_id: body.parentItemId ? String(body.parentItemId) : null
    });
    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    return NextResponse.json(normalizeHousePayload(data));
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Item could not be moved between properties.' }, { status: 500 });
  }
}
