import { NextResponse } from 'next/server';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';
import { normalizeLedgerPayload } from '@/features/characters/data';

export async function GET() {
  try {
    const token = await readSessionToken();
    if (!token) {
      return NextResponse.json({ error: 'Log in to view the campaign ledger.' }, { status: 401 });
    }

    const supabase = createAuthDatabaseClient();
    if (!supabase) {
      return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });
    }

    const { data, error } = await supabase.rpc('get_character_ledger', { p_session_token: token });
    if (error) {
      return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    }

    return NextResponse.json(normalizeLedgerPayload(data));
  } catch (error) {
    return NextResponse.json({
      error: error instanceof Error ? error.message : 'The character ledger could not be loaded.'
    }, { status: 500 });
  }
}
