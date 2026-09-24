import { NextResponse, type NextRequest } from 'next/server';
import { normalizeBestiaryPayload } from '@/features/bestiary/data';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

export async function GET() {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in to view the bestiary.' }, { status: 401 });

    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('get_bestiary', { p_session_token: token });
    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });

    return NextResponse.json(normalizeBestiaryPayload(data));
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Bestiary could not be loaded.' }, { status: 500 });
  }
}

export async function POST(request: NextRequest) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in before creating a bestiary entry.' }, { status: 401 });

    const entry = await request.json().catch(() => ({}));
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('create_bestiary_entity', {
      p_session_token: token,
      p_entry: entry
    });
    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    return NextResponse.json(normalizeBestiaryPayload(data));
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Bestiary entry could not be created.' }, { status: 500 });
  }
}
