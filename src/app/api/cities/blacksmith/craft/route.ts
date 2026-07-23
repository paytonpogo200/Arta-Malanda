import { NextResponse, type NextRequest } from 'next/server';
import { normalizeCitiesPayload } from '@/features/cities/data';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

export async function POST(request: NextRequest) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in before using the blacksmith.' }, { status: 401 });

    const body = await request.json().catch(() => ({}));
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('run_blacksmith_action', {
      p_session_token: token,
      p_character_id: String(body.characterId ?? ''),
      p_action: String(body.action ?? ''),
      p_recipe_key: body.recipeKey ? String(body.recipeKey) : null,
      p_material_product_id: body.materialProductId ? String(body.materialProductId) : null,
      p_target_item_id: body.targetItemId ? String(body.targetItemId) : null,
      p_rune_product_id: body.runeProductId ? String(body.runeProductId) : null,
      p_modifier_key: body.modifierKey ? String(body.modifierKey) : null
    });

    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    return NextResponse.json(normalizeCitiesPayload(data));
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Blacksmith work failed.' }, { status: 500 });
  }
}
