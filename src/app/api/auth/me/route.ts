import { NextResponse } from 'next/server';
import { createAuthDatabaseClient, toAuthProfile } from '@/lib/auth/database';
import { clearSessionCookie, readSessionToken } from '@/lib/auth/session';

export async function GET() {
  const token = await readSessionToken();
  if (!token) {
    return NextResponse.json({ profile: null });
  }

  const supabase = createAuthDatabaseClient();
  if (!supabase) {
    return NextResponse.json({ profile: null }, { status: 503 });
  }

  const { data, error } = await supabase.rpc('get_campaign_session', { p_session_token: token });
  const row = Array.isArray(data) ? data[0] : data;

  if (error || !row) {
    const response = NextResponse.json({ profile: null }, { status: error ? 401 : 200 });
    clearSessionCookie(response);
    return response;
  }

  return NextResponse.json({ profile: toAuthProfile(row) });
}
