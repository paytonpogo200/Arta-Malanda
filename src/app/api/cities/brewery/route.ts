import { NextResponse, type NextRequest } from 'next/server';
import { normalizeCitiesPayload } from '@/features/cities/data';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

export async function GET(request: NextRequest) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in before using the brewery.' }, { status: 401 });

    const characterId = request.nextUrl.searchParams.get('characterId') ?? '';
    if (!characterId) return NextResponse.json({ error: 'Choose a brewing character first.' }, { status: 400 });

    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('get_brewery_state', {
      p_session_token: token,
      p_character_id: characterId
    });

    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    return NextResponse.json(data ?? {});
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Brewery could not be loaded.' }, { status: 500 });
  }
}

export async function POST(request: NextRequest) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in before brewing.' }, { status: 401 });

    const body = await request.json().catch(() => ({}));
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('brew_potion', {
      p_session_token: token,
      p_character_id: String(body.characterId ?? ''),
      p_strength: String(body.strength ?? ''),
      p_property_key: String(body.propertyKey ?? ''),
      p_property_selections: Array.isArray(body.propertySelections) ? body.propertySelections : [],
      p_stabilizer_selections: Array.isArray(body.stabilizerSelections) ? body.stabilizerSelections : [],
      p_catalyst_selection: body.catalystSelection && typeof body.catalystSelection === 'object' ? body.catalystSelection : null
    });

    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    return NextResponse.json({
      result: data?.result ?? null,
      brewery: data?.brewery ?? {},
      cities: normalizeCitiesPayload(data?.cities ?? {})
    });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Brew failed.' }, { status: 500 });
  }
}
