import { NextResponse, type NextRequest } from 'next/server';
import { normalizeHousePayload } from '@/features/houses/data';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

export async function POST(request: NextRequest, context: { params: Promise<{ id: string }> }) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in before sending items home.' }, { status: 401 });

    const { id } = await context.params;
    const body = await request.json().catch(() => ({}));
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('move_inventory_item_to_home', {
      p_session_token: token,
      p_item_id: id,
      p_actor_character_id: body.actorCharacterId || null,
      p_home_id: body.homeId || null,
      p_home_source: body.source || null,
      p_slot_index: body && typeof body === 'object' && 'slotIndex' in body ? Number(body.slotIndex ?? 0) : null,
      p_parent_item_id: body.parentItemId || null
    });

    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    return NextResponse.json(normalizeHousePayload(data));
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Item could not be sent to the house.' }, { status: 500 });
  }
}
