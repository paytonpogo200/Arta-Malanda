import { NextResponse } from 'next/server';
import { normalizeTradingPostPayload } from '@/features/trading-post/data';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

export async function PATCH(request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in to update this offer.' }, { status: 401 });
    const { id } = await params;
    const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });
    const { data, error } = await supabase.rpc('resolve_trading_post_offer', {
      p_session_token: token,
      p_offer_id: id,
      p_action: String(body.action ?? '')
    });
    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    return NextResponse.json(normalizeTradingPostPayload(data));
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'The offer could not be updated.' }, { status: 500 });
  }
}
