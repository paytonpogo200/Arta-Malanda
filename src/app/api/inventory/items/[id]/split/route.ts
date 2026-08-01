import { NextResponse, type NextRequest } from 'next/server';
import { normalizeCharacterInventoryPayload } from '@/features/inventory/data';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

export async function POST(request: NextRequest, context: { params: Promise<{ id: string }> }) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in before splitting inventory.' }, { status: 401 });

    const { id } = await context.params;
    const body = await request.json().catch(() => ({}));
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('split_inventory_item_stack', {
      p_session_token: token,
      p_item_id: id,
      p_quantity: Math.max(0.5, Number(body.quantity ?? 1)),
      p_confirm_drop: Boolean(body.confirmDrop)
    });

    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    const payload = data && typeof data === 'object' ? data as Record<string, unknown> : {};
    return NextResponse.json({
      ...payload,
      inventory: normalizeCharacterInventoryPayload(payload.inventory ?? {})
    });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Stack could not be split.' }, { status: 500 });
  }
}
