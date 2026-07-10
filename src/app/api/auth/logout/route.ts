import { NextResponse } from 'next/server';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { clearSessionCookie, readSessionToken } from '@/lib/auth/session';

export async function POST() {
  const token = await readSessionToken();
  const supabase = createAuthDatabaseClient();

  if (token && supabase) {
    await supabase.rpc('logout_campaign_session', { p_session_token: token });
  }

  const response = NextResponse.json({ ok: true });
  clearSessionCookie(response);
  return response;
}
