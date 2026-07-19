import { NextResponse } from 'next/server';
import { normalizeExplorationPayload } from '@/features/exploration/data';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

export async function GET() {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in to view exploration tools.' }, { status: 401 });
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });
    const { data, error } = await supabase.rpc('get_exploration_state', { p_session_token: token });
    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    return NextResponse.json(normalizeExplorationPayload(data));
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Exploration tools could not be loaded.' }, { status: 500 });
  }
}
