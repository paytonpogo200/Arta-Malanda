import { NextResponse, type NextRequest } from 'next/server';
import { createAuthDatabaseClient, toAuthProfile } from '@/lib/auth/database';
import { setSessionCookie } from '@/lib/auth/session';

export async function POST(request: NextRequest) {
  try {
    const body = await request.json().catch(() => ({}));
    const username = String(body.username ?? '').trim();
    const displayName = String(body.displayName ?? '').trim();
    const password = String(body.password ?? '');
    const confirmPassword = String(body.confirmPassword ?? '');
    const claimDm = Boolean(body.claimDm);

    if (!username || !password) {
      return NextResponse.json({ error: 'Choose a username and password.' }, { status: 400 });
    }

    if (password !== confirmPassword) {
      return NextResponse.json({ error: 'Passwords must match.' }, { status: 400 });
    }

    const supabase = createAuthDatabaseClient();
    if (!supabase) {
      return NextResponse.json({ error: 'The campaign database is not connected yet. Check Vercel environment variables.' }, { status: 503 });
    }

    const { data, error } = await supabase.rpc('create_campaign_account', {
      p_username: username,
      p_display_name: displayName || username,
      p_password: password,
      p_claim_dm: claimDm
    });

    if (error) {
      return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    }

    const row = Array.isArray(data) ? data[0] : data;
    if (!row?.session_token) {
      return NextResponse.json({ error: 'Account creation failed. The database did not return a session token.' }, { status: 400 });
    }

    const response = NextResponse.json({ profile: toAuthProfile(row) });
    setSessionCookie(response, row.session_token);
    return response;
  } catch (error) {
    return NextResponse.json({
      error: error instanceof Error ? error.message : 'Signup route crashed before it could finish.'
    }, { status: 500 });
  }
}
