import { NextResponse, type NextRequest } from 'next/server';
import { normalizeCharacterInventoryPayload } from '@/features/inventory/data';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

export async function PATCH(request: NextRequest, context: { params: Promise<{ id: string }> }) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in before changing a wallet.' }, { status: 401 });

    const { id } = await context.params;
    const body = await request.json().catch(() => ({}));
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('set_character_wallet_balances', {
      p_session_token: token,
      p_character_id: id,
      p_balances: body.balances ?? []
    });

    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    return NextResponse.json(normalizeCharacterInventoryPayload({ items: [], wallet: data }));
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Wallet could not be changed.' }, { status: 500 });
  }
}

export async function POST(request: NextRequest, context: { params: Promise<{ id: string }> }) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in before gifting money.' }, { status: 401 });

    const { id } = await context.params;
    const body = await request.json().catch(() => ({}));
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('gift_character_currency', {
      p_session_token: token,
      p_sender_character_id: id,
      p_target_character_id: String(body.targetCharacterId ?? ''),
      p_currency: Array.isArray(body.currency) ? body.currency : []
    });

    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    return NextResponse.json({ inventory: normalizeCharacterInventoryPayload(data) });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Money gift could not be sent.' }, { status: 500 });
  }
}
