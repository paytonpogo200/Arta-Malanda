import { NextResponse, type NextRequest } from 'next/server';
import { normalizeBattleRoomPayload, normalizeCombatant } from '@/features/battle/data';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

export async function PATCH(request: NextRequest, context: { params: Promise<{ id: string }> }) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in before changing combat.' }, { status: 401 });

    const { id } = await context.params;
    const patch = await request.json().catch(() => ({}));
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('update_combatant_state', {
      p_session_token: token,
      p_combatant_id: id,
      p_patch: patch
    });

    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    return NextResponse.json({ combatant: normalizeCombatant(data) });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Combatant could not be changed.' }, { status: 500 });
  }
}

export async function POST(request: NextRequest, context: { params: Promise<{ id: string }> }) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in before changing battle effects.' }, { status: 401 });

    const { id } = await context.params;
    const body = await request.json().catch(() => ({}));
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('update_combatant_statuses', {
      p_session_token: token,
      p_combatant_id: id,
      p_action: String(body.action ?? ''),
      p_status_key: body.statusKey ? String(body.statusKey) : null,
      p_status_id: body.statusId ? String(body.statusId) : null,
      p_duration: body.duration === undefined || body.duration === null ? null : Number(body.duration)
    });
    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });

    const result = data && typeof data === 'object' ? data as Record<string, unknown> : {};
    return NextResponse.json({ combatant: normalizeCombatant(result.combatant), damage: Number(result.damage ?? 0) });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Battle effects could not be changed.' }, { status: 500 });
  }
}

export async function DELETE(_request: NextRequest, context: { params: Promise<{ id: string }> }) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in before removing combatants.' }, { status: 401 });

    const { id } = await context.params;
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('remove_combatant_from_battle', {
      p_session_token: token,
      p_combatant_id: id
    });

    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    return NextResponse.json(normalizeBattleRoomPayload(data));
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Combatant could not be removed.' }, { status: 500 });
  }
}
