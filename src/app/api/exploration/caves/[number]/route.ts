import { NextResponse, type NextRequest } from 'next/server';
import { CAVE_RECORDS } from '@/features/exploration/caves';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

function normalizeNickname(value: unknown) {
  return String(value ?? '').trim().slice(0, 80);
}

export async function PATCH(request: NextRequest, context: { params: Promise<{ number: string }> }) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in before renaming caves.' }, { status: 401 });

    const { number } = await context.params;
    const caveNumber = Number(number);
    const cave = CAVE_RECORDS.find((entry) => entry.number === caveNumber);
    if (!cave) return NextResponse.json({ error: 'Cave not found.' }, { status: 404 });

    const body = await request.json().catch(() => ({}));
    const nickname = normalizeNickname((body as Record<string, unknown>).nickname);
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('set_exploration_cave_nickname', {
      p_session_token: token,
      p_cave_number: caveNumber,
      p_nickname: nickname
    });

    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    const record = data && typeof data === 'object' ? data as Record<string, unknown> : {};
    const savedNickname = normalizeNickname(record.nickname);
    return NextResponse.json({ cave: { ...cave, nickname: savedNickname || undefined } });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Cave nickname could not be saved.' }, { status: 500 });
  }
}
