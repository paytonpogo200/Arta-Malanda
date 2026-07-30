import { NextResponse, type NextRequest } from 'next/server';
import { normalizeCharacterInventoryPayload, normalizeInventoryItem } from '@/features/inventory/data';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

export async function GET(_request: NextRequest, context: { params: Promise<{ id: string }> }) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in to view inventory.' }, { status: 401 });

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
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Inventory could not be loaded.' }, { status: 500 });
  }
}

export async function POST(request: NextRequest, context: { params: Promise<{ id: string }> }) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in before adding inventory.' }, { status: 401 });

    const { id } = await context.params;
    const body = await request.json().catch(() => ({}));
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('add_character_inventory_item', {
      p_session_token: token,
      p_character_id: id,
      p_parent_item_id: body.parentItemId || null,
      p_slot_index: Number(body.slotIndex ?? 0),
      p_item_name: String(body.name ?? ''),
      p_item_type: String(body.type ?? 'misc'),
      p_rarity: String(body.rarity ?? 'Common'),
      p_quantity: Math.max(0.5, Number(body.quantity ?? 1)),
      p_is_storage: Boolean(body.isStorage),
      p_storage_capacity: Math.max(0, Number(body.storageCapacity ?? 0)),
      p_modifiers: body.modifiers ?? {},
      p_enchantment: body.enchantment || null,
      p_material: body.material || null,
      p_enhancement_count: Math.max(0, Math.min(3, Number(body.enhancementCount ?? 0))),
      p_is_two_handed: Boolean(body.isTwoHanded),
      p_potion_strength: body.potionStrength ? String(body.potionStrength) : null,
      p_potion_property: body.potionProperty ? String(body.potionProperty) : null,
      p_potion_quality: body.potionQuality ? String(body.potionQuality) : null,
      p_item_description: body.itemDescription ? String(body.itemDescription) : null,
      p_is_accessory: Boolean(body.isAccessory)
    });

    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    return NextResponse.json({ item: normalizeInventoryItem(data) });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Item could not be added.' }, { status: 500 });
  }
}
