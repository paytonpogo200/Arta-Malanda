import { NextResponse } from 'next/server';
import { mergeCaveNicknames } from '@/features/exploration/caves';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

function nicknameMapFromPayload(value: unknown) {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  const rows = Array.isArray(source.nicknames) ? source.nicknames : [];
  const nicknames: Record<number, string> = {};
  for (const row of rows) {
    const record = row && typeof row === 'object' ? row as Record<string, unknown> : {};
    const caveNumber = Number(record.caveNumber ?? 0);
    const nickname = String(record.nickname ?? '').trim();
    if (caveNumber > 0 && nickname) nicknames[caveNumber] = nickname;
  }
  return nicknames;
}

export async function GET() {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in to view cave tools.' }, { status: 401 });
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('get_exploration_cave_nicknames', { p_session_token: token });
    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });

    return NextResponse.json({ caves: mergeCaveNicknames(nicknameMapFromPayload(data)) });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Caves could not be loaded.' }, { status: 500 });
  }
}
