import { NextResponse, type NextRequest } from 'next/server';
import { normalizeCharacter } from '@/features/characters/data';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

export async function PATCH(request: NextRequest, context: { params: Promise<{ id: string }> }) {
  try {
    const token = await readSessionToken();
    if (!token) {
      return NextResponse.json({ error: 'Log in before editing a character.' }, { status: 401 });
    }

    const { id } = await context.params;
    const patch = await request.json().catch(() => ({}));

    const supabase = createAuthDatabaseClient();
    if (!supabase) {
      return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });
    }

    const { data, error } = await supabase.rpc('update_campaign_character', {
      p_session_token: token,
      p_character_id: id,
      p_patch: patch
    });

    if (error) {
      return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    }

    return NextResponse.json({ character: normalizeCharacter(data) });
  } catch (error) {
    return NextResponse.json({
      error: error instanceof Error ? error.message : 'The character could not be updated.'
    }, { status: 500 });
  }
}

export async function DELETE(_request: NextRequest, context: { params: Promise<{ id: string }> }) {
  try {
    const token = await readSessionToken();
    if (!token) {
      return NextResponse.json({ error: 'Log in before deleting a character.' }, { status: 401 });
    }

    const { id } = await context.params;
    const supabase = createAuthDatabaseClient();
    if (!supabase) {
      return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });
    }

    const { data, error } = await supabase.rpc('delete_campaign_character', {
      p_session_token: token,
      p_character_id: id
    });

    if (error) {
      return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    }

    return NextResponse.json({ deletedCharacterId: String(data ?? id) });
  } catch (error) {
    return NextResponse.json({
      error: error instanceof Error ? error.message : 'The character could not be deleted.'
    }, { status: 500 });
  }
}
