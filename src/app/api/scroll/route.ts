import { NextResponse } from 'next/server';
import { normalizePersonalScroll } from '@/features/scroll/data';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

export async function GET() {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in to open your Personal Scroll.' }, { status: 401 });

    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('get_personal_scroll', { p_session_token: token });
    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });

    return NextResponse.json(normalizePersonalScroll(data));
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Your Personal Scroll could not be opened.' }, { status: 500 });
  }
}

export async function PATCH(request: Request) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in to save your Personal Scroll.' }, { status: 401 });

    const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('update_personal_scroll', {
      p_session_token: token,
      p_content_html: String(body.contentHtml ?? ''),
      p_drawing_data_url: String(body.drawingDataUrl ?? '')
    });
    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });

    return NextResponse.json(normalizePersonalScroll(data));
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Your Personal Scroll could not be saved.' }, { status: 500 });
  }
}
