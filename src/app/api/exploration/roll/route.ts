import { NextResponse, type NextRequest } from 'next/server';
import { normalizeLootRollPayload } from '@/features/exploration/data';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

export async function POST(request: NextRequest) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in before rolling loot.' }, { status: 401 });
    const body = await request.json().catch(() => ({}));
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });
    const { data, error } = await supabase.rpc('roll_loot_generator', {
      p_session_token: token,
      p_biome: String(body.biome ?? 'Any'),
      p_difficulty: Math.max(1, Number(body.difficulty ?? 1)),
      p_pool_size: String(body.poolSize ?? 'Medium Cave'),
      p_room_type: String(body.roomType ?? 'Normal')
    });
    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    return NextResponse.json(normalizeLootRollPayload(data));
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Loot could not be rolled.' }, { status: 500 });
  }
}
