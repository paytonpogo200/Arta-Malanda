import { NextResponse, type NextRequest } from 'next/server';
import { normalizeInventoryItem } from '@/features/inventory/data';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

export async function POST(request: NextRequest) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in before giving loot.' }, { status: 401 });
    const body = await request.json().catch(() => ({}));
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('award_exploration_loot_item', {
      p_session_token: token,
      p_character_id: String(body.characterId ?? ''),
      p_loot_item_id: String(body.itemId ?? ''),
      p_quantity: Math.max(1, Number(body.quantity ?? 1))
    });

    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    if (data && typeof data === 'object' && !Array.isArray(data) && 'currency' in data) {
      return NextResponse.json({ wallet: data });
    }
    return NextResponse.json({ item: normalizeInventoryItem(data) });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Loot could not be given.' }, { status: 500 });
  }
}
