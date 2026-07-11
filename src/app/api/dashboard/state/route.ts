import { NextResponse } from 'next/server';
import { normalizeDashboardState } from '@/features/dashboard/state';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

export async function GET() {
  try {
    const token = await readSessionToken();
    if (!token) {
      return NextResponse.json({ error: 'Log in to view the campaign dashboard.' }, { status: 401 });
    }

    const supabase = createAuthDatabaseClient();
    if (!supabase) {
      return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });
    }

    const { data, error } = await supabase.rpc('get_dashboard_state', { p_session_token: token });
    if (error) {
      return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    }

    return NextResponse.json(normalizeDashboardState(data));
  } catch (error) {
    return NextResponse.json({
      error: error instanceof Error ? error.message : 'The dashboard state could not be loaded.'
    }, { status: 500 });
  }
}
