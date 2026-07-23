import { NextResponse, type NextRequest } from 'next/server';
import { normalizeCharacterInventoryPayload } from '@/features/inventory/data';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

export async function POST(request: NextRequest, context: { params: Promise<{ id: string }> }) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in before consuming potions.' }, { status: 401 });

    const { id } = await context.params;
    const body = await request.json().catch(() => ({}));
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('consume_inventory_potion', {
      p_session_token: token,
      p_item_id: id,
      p_confirm_drop_flask: Boolean(body.confirmDropFlask)
    });

    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    if (data?.needsFlaskDropConfirmation) {
      return NextResponse.json({
        needsFlaskDropConfirmation: true,
        message: String(data.message ?? 'No open inventory slot for the Empty Flask.')
      });
    }

    return NextResponse.json({
      needsFlaskDropConfirmation: false,
      flaskDropped: Boolean(data?.flaskDropped),
      effect: data?.effect ?? null,
      inventory: normalizeCharacterInventoryPayload(data?.inventory ?? {})
    });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Potion could not be consumed.' }, { status: 500 });
  }
}
