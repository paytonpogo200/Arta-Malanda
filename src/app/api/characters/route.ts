import { NextResponse, type NextRequest } from 'next/server';
import { normalizeCharacter } from '@/features/characters/data';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

export async function POST(request: NextRequest) {
  try {
    const token = await readSessionToken();
    if (!token) {
      return NextResponse.json({ error: 'Log in before creating a character.' }, { status: 401 });
    }

    const body = await request.json().catch(() => ({}));
    const name = String(body.name ?? '').trim();
    const classKey = String(body.classKey ?? '').trim();
    const ownerUserId = body.ownerUserId ? String(body.ownerUserId) : null;
    const personalPassives = String(body.personalPassives ?? '').trim();
    const tokenColor = String(body.tokenColor ?? '').trim() || null;

    if (!name) {
      return NextResponse.json({ error: 'Name the character first.' }, { status: 400 });
    }

    const supabase = createAuthDatabaseClient();
    if (!supabase) {
      return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });
    }

    const { data, error } = await supabase.rpc('create_campaign_character', {
      p_session_token: token,
      p_name: name,
      p_owner_user_id: ownerUserId,
      p_class_key: classKey,
      p_personal_passives: personalPassives,
      p_token_color: tokenColor
    });

    if (error) {
      return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    }

    return NextResponse.json({ character: normalizeCharacter(data) });
  } catch (error) {
    return NextResponse.json({
      error: error instanceof Error ? error.message : 'The character could not be created.'
    }, { status: 500 });
  }
}
