import { NextResponse, type NextRequest } from 'next/server';
import { normalizeProperty } from '@/features/houses/data';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

export async function POST(request: NextRequest, context: { params: Promise<{ ownerId: string }> }) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in before adding property.' }, { status: 401 });

    const { ownerId } = await context.params;
    const body = await request.json().catch(() => ({}));
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('add_campaign_property', {
      p_session_token: token,
      p_owner_user_id: ownerId,
      p_caretaker_character_id: body.caretakerCharacterId || null,
      p_name: String(body.name ?? ''),
      p_property_type: String(body.type ?? 'other'),
      p_location: String(body.location ?? 'at_house'),
      p_is_pet: Boolean(body.isPet),
      p_slot_index: Number(body.slotIndex ?? 0),
      p_storage_capacity: Math.max(0, Number(body.storageCapacity ?? 0))
    });

    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    return NextResponse.json({ property: normalizeProperty(data) });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Property could not be added.' }, { status: 500 });
  }
}
