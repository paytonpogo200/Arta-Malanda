import { NextResponse, type NextRequest } from 'next/server';
import { normalizeTradingPostPayload } from '@/features/trading-post/data';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

export async function GET(request: NextRequest) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in to visit the Trading Post.' }, { status: 401 });
    const vendorId = request.nextUrl.searchParams.get('vendorId') ?? '';
    const characterId = request.nextUrl.searchParams.get('characterId') || null;
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('get_trading_post', {
      p_session_token: token,
      p_vendor_id: vendorId,
      p_character_id: characterId
    });
    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    return NextResponse.json(normalizeTradingPostPayload(data));
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'The Trading Post could not be loaded.' }, { status: 500 });
  }
}

export async function POST(request: NextRequest) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in to enter trade goods.' }, { status: 401 });
    const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('submit_trading_post_listing', {
      p_session_token: token,
      p_vendor_id: String(body.vendorId ?? ''),
      p_character_id: String(body.characterId ?? ''),
      p_item_id: String(body.itemId ?? ''),
      p_quantity: Number(body.quantity ?? 0)
    });
    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    return NextResponse.json(normalizeTradingPostPayload(data));
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'The listing could not be submitted.' }, { status: 500 });
  }
}
