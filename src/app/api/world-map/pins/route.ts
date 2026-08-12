import { NextResponse, type NextRequest } from 'next/server';
import { normalizeWorldMapPayload } from '@/features/world-map/data';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

export async function POST(request: NextRequest) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in before adding a map pin.' }, { status: 401 });

    const body = await request.json().catch(() => ({}));
    const x = Number(body.x);
    const y = Number(body.y);
    if (!Number.isFinite(x) || !Number.isFinite(y)) return NextResponse.json({ error: 'Place the pin inside the map.' }, { status: 400 });

    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('add_world_map_pin', {
      p_session_token: token,
      p_pin_type: String(body.type ?? ''),
      p_x: x,
      p_y: y,
      p_description: String(body.description ?? '')
    });

    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    return NextResponse.json(normalizeWorldMapPayload(data));
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Map pin could not be added.' }, { status: 500 });
  }
}
