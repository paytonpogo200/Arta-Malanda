import { NextResponse, type NextRequest } from 'next/server';
import { normalizeHousePayload } from '@/features/houses/data';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

export async function GET(request: NextRequest, context: { params: Promise<{ ownerId: string }> }) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in to view a house.' }, { status: 401 });

    const { ownerId } = await context.params;
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('get_player_homes', {
      p_session_token: token,
      p_owner_user_id: ownerId,
      p_selected_home_id: request.nextUrl.searchParams.get('homeId') || null,
      p_selected_source: request.nextUrl.searchParams.get('source') || null
    });

    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    return NextResponse.json(normalizeHousePayload(data));
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'House could not be loaded.' }, { status: 500 });
  }
}

export async function PATCH(request: NextRequest, context: { params: Promise<{ ownerId: string }> }) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in before changing a house.' }, { status: 401 });

    const { ownerId } = await context.params;
    const patch = await request.json().catch(() => ({}));
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('save_player_home', {
      p_session_token: token,
      p_owner_user_id: ownerId,
      p_home_id: patch.homeId || null,
      p_home_source: patch.source || 'static',
      p_patch: patch
    });

    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    return NextResponse.json(normalizeHousePayload(data));
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'House could not be changed.' }, { status: 500 });
  }
}

export async function POST(request: NextRequest, context: { params: Promise<{ ownerId: string }> }) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in before creating a home.' }, { status: 401 });

    const { ownerId } = await context.params;
    const patch = await request.json().catch(() => ({}));
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('save_player_home', {
      p_session_token: token,
      p_owner_user_id: ownerId,
      p_home_id: null,
      p_home_source: 'static',
      p_patch: patch
    });

    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    return NextResponse.json(normalizeHousePayload(data));
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Home could not be created.' }, { status: 500 });
  }
}

export async function DELETE(request: NextRequest, context: { params: Promise<{ ownerId: string }> }) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in before deleting a house.' }, { status: 401 });

    const { ownerId } = await context.params;
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('delete_player_home', {
      p_session_token: token,
      p_owner_user_id: ownerId,
      p_home_id: request.nextUrl.searchParams.get('homeId') || null,
      p_home_source: request.nextUrl.searchParams.get('source') || 'static'
    });

    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    return NextResponse.json(normalizeHousePayload(data));
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'House could not be deleted.' }, { status: 500 });
  }
}
