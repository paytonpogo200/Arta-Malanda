import { NextResponse, type NextRequest } from 'next/server';
import { normalizeCharacterInventoryPayload } from '@/features/inventory/data';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

export async function POST(request: NextRequest, context: { params: Promise<{ id: string }> }) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in before gifting inventory.' }, { status: 401 });

    const { id } = await context.params;
    const body = await request.json().catch(() => ({}));
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('gift_inventory_item', {
      p_session_token: token,
      p_item_id: id,
      p_target_character_id: String(body.targetCharacterId ?? ''),
      p_quantity: Math.max(0.5, Number(body.quantity ?? 1))
    });

    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    return NextResponse.json({ inventory: normalizeCharacterInventoryPayload(data) });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Inventory gift could not be sent.' }, { status: 500 });
  }
}
