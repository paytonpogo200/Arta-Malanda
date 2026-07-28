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
    const hasSlotIndex = body && typeof body === 'object' && 'slotIndex' in body;
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = hasSlotIndex
      ? await supabase.rpc('move_inventory_item_to_house_slot', {
        p_session_token: token,
        p_item_id: id,
        p_slot_index: Number(body.slotIndex ?? 0)
      })
      : await supabase.rpc('move_inventory_item_to_house', {
        p_session_token: token,
        p_item_id: id
      });

    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    return NextResponse.json(normalizeHousePayload(data));
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Item could not be sent to the house.' }, { status: 500 });
  }
}
