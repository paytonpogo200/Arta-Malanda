import { NextResponse } from 'next/server';
import { normalizeTradeList, normalizeTradeOffer } from '@/features/trades/data';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

export async function GET() {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in to view trades.' }, { status: 401 });

    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('get_trade_offers', { p_session_token: token });
    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });

    return NextResponse.json({ trades: normalizeTradeList(data) });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Trades could not be loaded.' }, { status: 500 });
  }
}

export async function POST(request: Request) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in to offer a trade.' }, { status: 401 });

    const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('create_trade_offer', {
      p_session_token: token,
      p_sender_character_id: String(body.senderCharacterId ?? ''),
      p_target_character_id: String(body.targetCharacterId ?? ''),
      p_offer_note: String(body.offerNote ?? ''),
      p_request_note: String(body.requestNote ?? ''),
      p_message: String(body.message ?? ''),
      p_offered_item_id: body.offeredItemId ? String(body.offeredItemId) : null,
      p_offered_quantity: Math.max(0.5, Number(body.offeredQuantity ?? 1))
    });
    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });

    return NextResponse.json({ trade: normalizeTradeOffer(data) });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Trade could not be offered.' }, { status: 500 });
  }
}
