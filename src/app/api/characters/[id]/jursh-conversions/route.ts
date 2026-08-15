import { NextResponse, type NextRequest } from 'next/server';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

export async function GET(_request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in before using Jursh conversions.' }, { status: 401 });

    const { id } = await params;
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('get_jursh_conversion_state', {
      p_session_token: token,
      p_character_id: id
    });

    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    return NextResponse.json(data);
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Jursh conversions could not be loaded.' }, { status: 500 });
  }
}

export async function POST(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in before using Jursh conversions.' }, { status: 401 });

    const { id } = await params;
    const body = await request.json().catch(() => ({}));
    const action = String(body.action ?? '');
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    if (action === 'item-to-scales') {
      const { data, error } = await supabase.rpc('convert_jursh_item_to_scales', {
        p_session_token: token,
        p_character_id: id,
        p_item_id: String(body.itemId ?? ''),
        p_confirm_destroy_extras: Boolean(body.confirmDestroyExtras),
        p_quantity: Number.isFinite(Number(body.quantity)) ? Math.max(1, Math.floor(Number(body.quantity))) : 1
      });
      if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
      return NextResponse.json(data);
    }

    if (action === 'scales-to-item') {
      const selections = Array.isArray(body.selections) ? body.selections : null;
      const { data, error } = selections ? await supabase.rpc('convert_jursh_selected_scales_to_item', {
        p_session_token: token,
        p_character_id: id,
        p_recipe_key: String(body.recipeKey ?? ''),
        p_selections: selections
      }) : await supabase.rpc('convert_jursh_scales_to_item', {
        p_session_token: token,
        p_character_id: id,
        p_recipe_key: String(body.recipeKey ?? '')
      });
      if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
      return NextResponse.json(data);
    }

    if (action === 'dragon-scales') {
      const { data, error } = await supabase.rpc('forge_dragonscale_scale_from_dragon_scales', {
        p_session_token: token,
        p_character_id: id,
        p_station_city_name: null,
        p_selections: Array.isArray(body.selections) ? body.selections : null
      });
      if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
      const { data: state, error: stateError } = await supabase.rpc('get_jursh_conversion_state', {
        p_session_token: token,
        p_character_id: id
      });
      if (stateError) return NextResponse.json({ ...data, warning: stateError.message });
      return NextResponse.json({ ...state, dragonForge: data });
    }

    return NextResponse.json({ error: 'Unknown Jursh conversion action.' }, { status: 400 });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Jursh conversion failed.' }, { status: 500 });
  }
}
