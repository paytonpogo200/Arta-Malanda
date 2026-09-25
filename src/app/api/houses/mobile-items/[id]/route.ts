import { NextResponse, type NextRequest } from 'next/server';
import { normalizeInventoryItem } from '@/features/inventory/data';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

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
