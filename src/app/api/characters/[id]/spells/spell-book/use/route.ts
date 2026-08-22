import { NextResponse, type NextRequest } from 'next/server';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

export async function POST(request: NextRequest, context: { params: Promise<{ id: string }> }) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in before using spell books.' }, { status: 401 });

    const { id } = await context.params;
    const body = await request.json().catch(() => ({}));
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('use_spell_book_item', {
      p_session_token: token,
      p_character_id: id,
      p_item_id: String(body.itemId ?? ''),
      p_target_character_id: String(body.targetCharacterId ?? ''),
      p_form: Number(body.form ?? 1),
      p_caster_on_fire: Boolean(body.casterOnFire)
    });

    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    return NextResponse.json(data ?? {});
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Spell book could not be used.' }, { status: 500 });
  }
}
