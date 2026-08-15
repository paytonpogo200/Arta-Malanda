import { NextResponse, type NextRequest } from 'next/server';
import { normalizeHousePayload } from '@/features/houses/data';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

export async function PATCH(request: NextRequest, context: { params: Promise<{ ownerId: string }> }) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in before changing house permissions.' }, { status: 401 });

    const { ownerId } = await context.params;
    const body = await request.json().catch(() => ({}));
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('set_player_house_permissions', {
      p_session_token: token,
      p_owner_user_id: ownerId,
      p_permissions: Array.isArray(body.permissions) ? body.permissions : []
    });

    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    return NextResponse.json(normalizeHousePayload(data));
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'House permissions could not be saved.' }, { status: 500 });
  }
}
