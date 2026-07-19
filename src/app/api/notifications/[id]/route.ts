import { NextResponse } from 'next/server';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

export async function PATCH(request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in to update notifications.' }, { status: 401 });

    const { id } = await params;
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('mark_notification_read', {
      p_session_token: token,
      p_notification_id: id
    });
    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });

    return NextResponse.json(data ?? { ok: true });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Notification could not be updated.' }, { status: 500 });
  }
}
