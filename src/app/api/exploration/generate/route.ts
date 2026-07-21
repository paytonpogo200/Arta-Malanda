import { NextResponse, type NextRequest } from 'next/server';
import { getLootMultiplier, getLootRollCount, normalizeExplorationPayload, normalizeLootRollPayload } from '@/features/exploration/data';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';
import type { LootItem } from '@/lib/types';

function token(value: string) {
  return value.replace(/\s+/g, '').toLowerCase();
}

function biomeMatches(item: LootItem, biome: string) {
  if (biome === 'Any') return true;
  const selected = token(biome);
  const tokens = item.biomes.map(token);
  return tokens.includes('any') || tokens.includes(selected);
}

function isEligible(item: LootItem, biome: string, difficulty: number, poolSize: string) {
  return item.name
    && biomeMatches(item, biome)
    && item.minDifficulty <= difficulty
    && item.maxDifficulty >= difficulty
    && (!item.towerBaseOnly || poolSize === 'Tower Floor' || poolSize === 'Base');
}

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
    const boosted = new Set(payload.settings.rareBoostRarities);
    const eligible = payload.items
      .filter((item) => isEligible(item, biome, difficulty, poolSize))
      .map((item) => ({
        item,
        adjustedWeight: item.weight
          * (boosted.has(item.rarity) ? multiplier.total : 1)
          * (item.rarity === 'Legendary' ? multiplier.legendaryLuck : 1)
          * (item.rarity === 'Mythical' ? multiplier.mythicalLuck : 1)
      }))
      .filter((entry) => entry.adjustedWeight > 0);

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
