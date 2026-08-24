import { NextResponse, type NextRequest } from 'next/server';
import { normalizeDailyRewardsPayload } from '@/features/daily-rewards/data';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

export async function GET() {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in to view daily rewards.' }, { status: 401 });

    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('get_daily_rewards', { p_session_token: token });
    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });

    return NextResponse.json(normalizeDailyRewardsPayload(data));
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Daily rewards could not be loaded.' }, { status: 500 });
  }
}

export async function PATCH(request: NextRequest) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in before changing daily rewards.' }, { status: 401 });
    const body = await request.json().catch(() => ({}));

    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('update_daily_reward_schedule', {
      p_session_token: token,
      p_rewards: Array.isArray(body.rewards) ? body.rewards : []
    });
    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });

    return NextResponse.json(normalizeDailyRewardsPayload(data));
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Daily rewards could not be saved.' }, { status: 500 });
  }
}
