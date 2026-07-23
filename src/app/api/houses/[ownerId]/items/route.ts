import { NextResponse, type NextRequest } from 'next/server';
import { normalizeInventoryItem } from '@/features/inventory/data';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

export async function POST(request: NextRequest, context: { params: Promise<{ ownerId: string }> }) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in before adding house items.' }, { status: 401 });

    const { ownerId } = await context.params;
    const body = await request.json().catch(() => ({}));
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('add_house_inventory_item', {
      p_session_token: token,
      p_owner_user_id: ownerId,
      p_slot_index: Number(body.slotIndex ?? 0),
      p_item_name: String(body.name ?? ''),
      p_item_type: String(body.type ?? 'misc'),
      p_rarity: String(body.rarity ?? 'Common'),
      p_quantity: Math.max(0.5, Number(body.quantity ?? 1)),
      p_is_storage: Boolean(body.isStorage),
      p_storage_capacity: Math.max(0, Number(body.storageCapacity ?? 0)),
      p_modifiers: body.modifiers ?? {},
      p_enchantment: body.enchantment || null
    });

    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    return NextResponse.json({ item: normalizeInventoryItem(data) });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'House item could not be added.' }, { status: 500 });
  }
}
