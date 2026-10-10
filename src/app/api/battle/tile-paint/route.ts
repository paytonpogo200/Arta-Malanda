import { NextResponse, type NextRequest } from 'next/server';
import { normalizeBattleRoomPayload } from '@/features/battle/data';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

export async function POST(request: NextRequest) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in before painting battlefield tiles.' }, { status: 401 });

    const body = await request.json().catch(() => ({}));
    const cells = Array.isArray(body.cells) ? body.cells : [];
    const color = String(body.color ?? '').trim().toLowerCase();
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('set_battle_tile_paint', {
      p_session_token: token,
      p_color: color,
      p_cells: cells
    });

    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    return NextResponse.json(normalizeBattleRoomPayload(data));
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Battlefield tiles could not be painted.' }, { status: 500 });
  }
}

export async function DELETE() {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in before clearing battlefield tile paint.' }, { status: 401 });

    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('clear_battle_tile_paint', { p_session_token: token });
    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    return NextResponse.json(normalizeBattleRoomPayload(data));
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Battlefield tile paint could not be cleared.' }, { status: 500 });
  }
}
