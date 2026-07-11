import { NextResponse, type NextRequest } from 'next/server';
import { characterFromClassTemplate, normalizeCharacter } from '@/features/characters/data';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';
import { CLASS_TEMPLATES } from '@/lib/constants/classes';

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

    if (!name) {
      return NextResponse.json({ error: 'Name the character first.' }, { status: 400 });
    }

    const template = CLASS_TEMPLATES.find((entry) => entry.key === classKey) ?? CLASS_TEMPLATES[0];
    const character = characterFromClassTemplate(template, ownerUserId, name, personalPassives);

    const supabase = createAuthDatabaseClient();
    if (!supabase) {
      return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });
    }

    const { data, error } = await supabase.rpc('create_campaign_character', {
      p_session_token: token,
      p_name: character.name,
      p_owner_user_id: character.ownerUserId,
      p_class_key: character.classKey,
      p_class_name: character.className,
      p_level: character.level,
      p_max_hp: character.maxHp,
      p_current_hp: character.currentHp,
      p_max_mana: character.maxMana,
      p_current_mana: character.currentMana,
      p_inventory_slots: character.inventorySlots,
      p_spell_slots: character.spellSlots,
      p_attributes: character.attributes,
      p_class_passives: character.classPassives,
      p_personal_passives: character.personalPassives,
      p_token_color: character.tokenColor
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
