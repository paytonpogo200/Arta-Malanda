import { NextResponse } from 'next/server';
import { normalizeTradingPostPayload } from '@/features/trading-post/data';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

export async function POST(request: Request) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in to propose a trade.' }, { status: 401 });
    const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });
    const { data, error } = await supabase.rpc('create_trading_post_offer', {
      p_session_token: token,
      p_listing_id: String(body.listingId ?? ''),
      p_character_id: String(body.characterId ?? ''),
      p_items: Array.isArray(body.items) ? body.items : [],
      p_currency: Array.isArray(body.currency) ? body.currency : [],
      p_message: String(body.message ?? '')
    });
    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    return NextResponse.json(normalizeTradingPostPayload(data));
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'The offer could not be submitted.' }, { status: 500 });
  }
}
