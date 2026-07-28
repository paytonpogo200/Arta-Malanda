import { NextResponse, type NextRequest } from 'next/server';
import { normalizeInventoryItem } from '@/features/inventory/data';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

function normalizeWagonPayload(source: unknown) {
  const payload = source && typeof source === 'object' ? source as Record<string, unknown> : {};
  const wagons = Array.isArray(payload.wagons) ? payload.wagons.map((entry) => {
    const record = entry && typeof entry === 'object' ? entry as Record<string, unknown> : {};
    return {
      wagon: normalizeInventoryItem(record.wagon),
      ownerCharacterId: String(record.ownerCharacterId ?? ''),
      ownerName: String(record.ownerName ?? 'Unknown'),
      ownerUserId: record.ownerUserId ? String(record.ownerUserId) : null,
      canManage: Boolean(record.canManage)
    };
  }).filter((entry) => entry.wagon.id) : [];
  const items = Array.isArray(payload.items) ? payload.items.map(normalizeInventoryItem).filter((entry) => entry.id) : [];
  return { wagons, items };
}

export async function GET(_request: NextRequest, context: { params: Promise<{ id: string }> }) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in to view nearby wagons.' }, { status: 401 });

    const { id } = await context.params;
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('get_location_wagon_storage', {
      p_session_token: token,
      p_character_id: id
    });

    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    return NextResponse.json(normalizeWagonPayload(data));
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Nearby wagons could not be loaded.' }, { status: 500 });
  }
}
