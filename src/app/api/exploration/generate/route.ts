import { NextResponse, type NextRequest } from 'next/server';
import { getLootMultiplier, getLootRollCount, getWeightedLootItems, normalizeExplorationPayload, normalizeLootRollPayload } from '@/features/exploration/data';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

function randomQuantity(min: number, max: number) {
  return min + Math.floor(Math.random() * (max - min + 1));
}

export async function POST(request: NextRequest) {
  try {
    const tokenValue = await readSessionToken();
    if (!tokenValue) return NextResponse.json({ error: 'Log in before generating loot.' }, { status: 401 });

    const body = await request.json().catch(() => ({}));
    const biome = String(body.biome ?? 'Any');
    const difficulty = Math.max(1, Number(body.difficulty ?? 1));
    const poolSize = String(body.poolSize ?? 'Medium Cave');
    const roomType = String(body.roomType ?? 'Normal');
    const luckPotion = String(body.luckPotion ?? 'None');

    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('get_exploration_state', { p_session_token: tokenValue });
    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });

    const payload = normalizeExplorationPayload(data);
    const multiplier = getLootMultiplier(payload.settings, poolSize, roomType, luckPotion);
    const rolls = getLootRollCount(payload.settings, poolSize, roomType);
    const eligible = getWeightedLootItems(payload.items, payload.settings, biome, difficulty, poolSize, roomType, luckPotion);

    const totalWeight = eligible.reduce((sum, entry) => sum + entry.adjustedWeight, 0);
    if (totalWeight <= 0) {
      return NextResponse.json({ error: 'No matching loot for those settings.' }, { status: 400 });
    }

    const drops = Array.from({ length: rolls }, (_, index) => {
      const pick = Math.random() * totalWeight;
      let running = 0;
      const chosen = eligible.find((entry) => {
        running += entry.adjustedWeight;
        return pick < running;
      }) ?? eligible[eligible.length - 1];
      const quantity = randomQuantity(chosen.item.minQuantity, chosen.item.maxQuantity);
      return {
        id: crypto.randomUUID(),
        rollNumber: index + 1,
        itemId: chosen.item.id,
        name: chosen.item.name,
        type: chosen.item.type,
        rarity: chosen.item.rarity,
        quantity,
        remaining: quantity
      };
    });

    return NextResponse.json(normalizeLootRollPayload({
      drops,
      rolls,
      eligibleCount: eligible.length,
      totalWeight,
      multiplier
    }));
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Loot could not be generated.' }, { status: 500 });
  }
}
