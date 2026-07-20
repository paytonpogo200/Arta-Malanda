import { NextResponse, type NextRequest } from 'next/server';
import { normalizeBestiaryPayload } from '@/features/bestiary/data';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

export async function PATCH(request: NextRequest, context: { params: Promise<{ key: string }> }) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in before changing bestiary categories.' }, { status: 401 });

    const { key } = await context.params;
    const patch = await request.json().catch(() => ({}));
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('update_bestiary_category', {
      p_session_token: token,
      p_category_key: key,
      p_patch: patch
    });

    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    return NextResponse.json(normalizeBestiaryPayload(data));
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Bestiary category could not be changed.' }, { status: 500 });
  }
}
