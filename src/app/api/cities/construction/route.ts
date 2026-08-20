import { NextResponse, type NextRequest } from 'next/server';
import { normalizeCitiesPayload } from '@/features/cities/data';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

export async function POST(request: NextRequest) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in as the Dungeon Master to create city projects.' }, { status: 401 });

    const body = await request.json().catch(() => ({}));
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('create_city_construction_project', {
      p_session_token: token,
      p_city_key: body.cityKey,
      p_project_name: body.name,
      p_requirements: body.requirements ?? []
    });

    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    return NextResponse.json(normalizeCitiesPayload(data));
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Construction project could not be created.' }, { status: 500 });
  }
}
