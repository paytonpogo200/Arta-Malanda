import { NextResponse, type NextRequest } from 'next/server';
import { createAuthDatabaseClient, toAuthProfile } from '@/lib/auth/database';
import { setSessionCookie } from '@/lib/auth/session';

export async function POST(request: NextRequest) {
  try {
    const { username, password } = await request.json().catch(() => ({ username: '', password: '' }));
    const normalizedUsername = String(username ?? '').trim();
    const plainPassword = String(password ?? '');

    if (!normalizedUsername || !plainPassword) {
      return NextResponse.json({ error: 'Enter a username and password.' }, { status: 400 });
    }

    const supabase = createAuthDatabaseClient();
    if (!supabase) {
      return NextResponse.json({ error: 'The campaign database is not connected yet. Check Vercel environment variables.' }, { status: 503 });
    }

    const { data, error } = await supabase.rpc('login_campaign_account', {
      p_username: normalizedUsername,
      p_password: plainPassword
    });

    if (error) {
      return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 401 });
    }

    const row = Array.isArray(data) ? data[0] : data;
    if (!row?.session_token) {
      return NextResponse.json({ error: 'Login failed. The database did not return a session token.' }, { status: 401 });
    }

    const response = NextResponse.json({ profile: toAuthProfile(row) });
    setSessionCookie(response, row.session_token);
    return response;
  } catch (error) {
    return NextResponse.json({
      error: error instanceof Error ? error.message : 'Login route crashed before it could finish.'
    }, { status: 500 });
  }
}
