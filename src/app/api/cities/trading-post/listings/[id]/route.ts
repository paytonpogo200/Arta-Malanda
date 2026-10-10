import { NextResponse } from 'next/server';
import { normalizeTradingPostPayload } from '@/features/trading-post/data';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

export async function PATCH(request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in to update this listing.' }, { status: 401 });
    const { id } = await params;
    const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;
    const action = String(body.action ?? '');
    const functionName = action === 'approve' || action === 'decline'
      ? 'review_trading_post_listing'
      : 'close_trading_post_listing';
    const args = functionName === 'review_trading_post_listing'
      ? { p_session_token: token, p_listing_id: id, p_action: action, p_review_note: String(body.reviewNote ?? '') }
      : { p_session_token: token, p_listing_id: id, p_action: action };
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });
    const { data, error } = await supabase.rpc(functionName, args);
    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    return NextResponse.json(normalizeTradingPostPayload(data));
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'The listing could not be updated.' }, { status: 500 });
  }
}
