import { NextResponse, type NextRequest } from 'next/server';
import { normalizeInventoryItem } from '@/features/inventory/data';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

export async function POST(request: NextRequest, context: { params: Promise<{ id: string }> }) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in before adding mobile home items.' }, { status: 401 });
    const { id } = await context.params;
    const body = await request.json().catch(() => ({}));
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });
    const { data, error } = await supabase.rpc('add_mobile_home_inventory_item', {
      p_session_token: token,
      p_mobile_home_id: id,
      p_actor_character_id: body.actorCharacterId || null,
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
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Mobile home item could not be added.' }, { status: 500 });
  }
}

export async function PATCH(request: NextRequest, context: { params: Promise<{ id: string }> }) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in before changing mobile home storage.' }, { status: 401 });
    const { id } = await context.params;
    const patch = await request.json().catch(() => ({}));
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });
    const { data, error } = await supabase.rpc('update_mobile_home_item_state', {
      p_session_token: token,
      p_item_id: id,
      p_actor_character_id: patch.actorCharacterId || null,
      p_patch: patch
    });
    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    return NextResponse.json({ item: normalizeInventoryItem(data) });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Mobile home item could not be changed.' }, { status: 500 });
  }
}

export async function DELETE(request: NextRequest, context: { params: Promise<{ id: string }> }) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in before dropping mobile home items.' }, { status: 401 });
    const { id } = await context.params;
    const quantity = Math.max(0.5, Number(request.nextUrl.searchParams.get('quantity') ?? 1));
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });
    const { data, error } = await supabase.rpc('drop_mobile_home_item_quantity', {
      p_session_token: token,
      p_item_id: id,
      p_actor_character_id: request.nextUrl.searchParams.get('characterId') || null,
      p_quantity: quantity
    });
    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    return NextResponse.json({ item: data ? normalizeInventoryItem(data) : null });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Mobile home item could not be dropped.' }, { status: 500 });
  }
}
