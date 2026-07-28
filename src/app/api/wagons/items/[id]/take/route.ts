import { NextResponse, type NextRequest } from 'next/server';
import { normalizeCharacterInventoryPayload } from '@/features/inventory/data';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

export async function POST(request: NextRequest, context: { params: Promise<{ id: string }> }) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in before using wagon storage.' }, { status: 401 });

    const { id } = await context.params;
    const body = await request.json().catch(() => ({}));
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('move_wagon_item_to_inventory', {
      p_session_token: token,
      p_actor_character_id: String(body.characterId ?? ''),
      p_item_id: id,
      p_parent_item_id: body.parentItemId || null,
      p_slot_index: body.slotIndex === undefined || body.slotIndex === null ? null : Number(body.slotIndex)
    });

    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    return NextResponse.json(normalizeCharacterInventoryPayload(data));
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Item could not be taken from the wagon.' }, { status: 500 });
  }
}
