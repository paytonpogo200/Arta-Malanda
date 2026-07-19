import { NextResponse } from 'next/server';
import { normalizeTradeOffer } from '@/features/trades/data';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

export async function PATCH(request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in to update a trade.' }, { status: 401 });

    const { id } = await params;
    const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;
    const status = String(body.status ?? '');
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('update_trade_offer_status', {
      p_session_token: token,
      p_trade_id: id,
      p_status: status
    });
    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });

    return NextResponse.json({ trade: normalizeTradeOffer(data) });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Trade could not be updated.' }, { status: 500 });
  }
}
