import { NextResponse } from 'next/server';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

export async function POST(request: Request) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in to send an announcement.' }, { status: 401 });

    const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('create_campaign_announcement', {
      p_session_token: token,
      p_title: String(body.title ?? ''),
      p_body: String(body.body ?? ''),
      p_location_name: String(body.locationName ?? ''),
      p_in_world: Boolean(body.inWorld)
    });
    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });

    return NextResponse.json(data ?? { ok: true });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Announcement could not be sent.' }, { status: 500 });
  }
}
