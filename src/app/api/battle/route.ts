import { NextResponse, type NextRequest } from 'next/server';
import { normalizeBattleRoomPayload } from '@/features/battle/data';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

export async function GET() {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in to view the battlefield.' }, { status: 401 });

    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('get_battle_room', { p_session_token: token });
    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });

    return NextResponse.json(normalizeBattleRoomPayload(data));
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Battlefield could not be loaded.' }, { status: 500 });
  }
}

export async function POST(request: NextRequest) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in before starting combat.' }, { status: 401 });

    const body = await request.json().catch(() => ({}));
    const characterIds = Array.isArray(body.characterIds) ? body.characterIds.map(String).filter(Boolean) : [];
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('start_campaign_battle', {
      p_session_token: token,
      p_character_ids: characterIds,
      p_grid_width: Number(body.gridWidth ?? 24),
      p_grid_height: Number(body.gridHeight ?? 24)
    });

    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    return NextResponse.json(normalizeBattleRoomPayload(data));
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Combat could not be started.' }, { status: 500 });
  }
}

export async function DELETE() {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in before ending combat.' }, { status: 401 });

    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('end_active_battle', { p_session_token: token });
    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });

    return NextResponse.json(normalizeBattleRoomPayload(data));
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Combat could not be ended.' }, { status: 500 });
  }
}
