import { NextResponse, type NextRequest } from 'next/server';
import { normalizeHousePayload } from '@/features/houses/data';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

export async function GET(_request: NextRequest, context: { params: Promise<{ ownerId: string }> }) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in to view a house.' }, { status: 401 });

    const { ownerId } = await context.params;
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('get_player_house', {
      p_session_token: token,
      p_owner_user_id: ownerId
    });

    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    return NextResponse.json(normalizeHousePayload(data));
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'House could not be loaded.' }, { status: 500 });
  }
}

export async function PATCH(request: NextRequest, context: { params: Promise<{ ownerId: string }> }) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in before changing a house.' }, { status: 401 });

    const { ownerId } = await context.params;
    const patch = await request.json().catch(() => ({}));
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('update_player_house', {
      p_session_token: token,
      p_owner_user_id: ownerId,
      p_patch: patch
    });

    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    return NextResponse.json(normalizeHousePayload(data));
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'House could not be changed.' }, { status: 500 });
  }
}

export async function DELETE(_request: NextRequest, context: { params: Promise<{ ownerId: string }> }) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in before deleting a house.' }, { status: 401 });

    const { ownerId } = await context.params;
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('delete_player_house', {
      p_session_token: token,
      p_owner_user_id: ownerId
    });

    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    return NextResponse.json(normalizeHousePayload(data));
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'House could not be deleted.' }, { status: 500 });
  }
}
