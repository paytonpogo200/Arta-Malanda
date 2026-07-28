import { NextResponse, type NextRequest } from 'next/server';
import { normalizeWagonPayload } from '@/features/inventory/wagons';
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

    const { data, error } = await supabase.rpc('move_inventory_item_to_wagon', {
      p_session_token: token,
      p_actor_character_id: String(body.characterId ?? ''),
      p_item_id: id,
      p_wagon_id: String(body.wagonId ?? ''),
      p_slot_index: Number(body.slotIndex ?? 0)
    });

    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    return NextResponse.json(normalizeWagonPayload(data));
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Item could not be moved into the wagon.' }, { status: 500 });
  }
}
