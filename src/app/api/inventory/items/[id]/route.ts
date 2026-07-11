import { NextResponse, type NextRequest } from 'next/server';
import { normalizeInventoryItem } from '@/features/inventory/data';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

export async function PATCH(request: NextRequest, context: { params: Promise<{ id: string }> }) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in before changing inventory.' }, { status: 401 });

    const { id } = await context.params;
    const patch = await request.json().catch(() => ({}));
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('update_inventory_item_state', {
      p_session_token: token,
      p_item_id: id,
      p_patch: patch
    });

    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    return NextResponse.json({ item: data ? normalizeInventoryItem(data) : null });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Inventory item could not be changed.' }, { status: 500 });
  }
}

export async function DELETE(request: NextRequest, context: { params: Promise<{ id: string }> }) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in before dropping inventory.' }, { status: 401 });

    const { id } = await context.params;
    const { searchParams } = new URL(request.url);
    const quantity = Math.max(1, Number(searchParams.get('quantity') ?? 999999));
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('drop_inventory_item_quantity', {
      p_session_token: token,
      p_item_id: id,
      p_quantity: quantity
    });

    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    return NextResponse.json({ item: data ? normalizeInventoryItem(data) : null });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Inventory item could not be dropped.' }, { status: 500 });
  }
}
