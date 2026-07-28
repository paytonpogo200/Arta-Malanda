import { NextResponse, type NextRequest } from 'next/server';
import { normalizeInventoryItem } from '@/features/inventory/data';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

export async function POST(request: NextRequest, context: { params: Promise<{ id: string }> }) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in before applying runes.' }, { status: 401 });

    const { id } = await context.params;
    const body = await request.json().catch(() => ({}));
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('apply_inventory_item_rune', {
      p_session_token: token,
      p_target_item_id: id,
      p_rune_item_id: String(body.runeItemId ?? ''),
      p_source: String(body.source ?? 'inventory')
    });

    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    return NextResponse.json({ item: normalizeInventoryItem(data) });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Rune could not be applied.' }, { status: 500 });
  }
}
