import { normalizeCharacter } from '@/features/characters/data';
import { ITEM_TYPES } from '@/features/inventory/data';
import type { Character, ItemRarity, ItemType, LootDrop, LootGeneratorSettings, LootItem, LootPool } from '@/lib/types';

export type ExplorationPayload = {
  characters: Character[];
  pools: LootPool[];
  items: LootItem[];
  settings: LootGeneratorSettings;
};

export type LootRollPayload = {
  drops: LootDrop[];
  rolls: number;
  eligibleCount: number;
  totalWeight: number;
  multiplier: {
    total: number;
    pool: number;
    room: number;
    legendaryLuck: number;
    mythicalLuck: number;
  };
};

export const LOOT_RARITIES: ItemRarity[] = ['Common', 'Uncommon', 'Rare', 'Epic', 'Legendary', 'Mythical'];
export const MULTIPLIER_RARITIES: ItemRarity[] = ['Rare', 'Epic', 'Legendary', 'Mythical'];

export type WeightedLootItem = {
  item: LootItem;
  adjustedWeight: number;
};

export type LootRarityMath = {
  rarity: ItemRarity;
  multiplier: number;
  itemCount: number;
  weight: number;
  chance: number;
};

export type LootRaritySummary = {
  rarities: LootRarityMath[];
  eligibleCount: number;
  totalWeight: number;
  weightedItems: WeightedLootItem[];
};

export const DEFAULT_LOOT_GENERATOR_SETTINGS: LootGeneratorSettings = {
  biomes: ['Any', 'Caves', 'Goblins', 'Elven', 'Volcano', 'Mountains', 'Snow', 'Voidlands'],
  difficulties: [1, 2, 3, 4, 5],
  poolSizes: ['Night Encounter', 'Small Cave', 'Medium Cave', 'Large Cave', 'Dragon Lair', 'Tower Floor', 'Base'],
  roomTypes: ['Normal', 'Secret Room', 'Tower Boss Room'],
  luckPotionOptions: ['None', 'Lesser', 'Greater', 'Greatest'],
  baseRollsByPoolSize: {
    'Night Encounter': 5,
    'Small Cave': 10,
    'Medium Cave': 15,
    'Large Cave': 20,
    'Dragon Lair': 50,
    'Tower Floor': 25,
    Base: 50
  },
  poolMultipliers: {
    'Large Cave': 1.33,
    'Dragon Lair': 5,
    'Tower Floor': 2,
    Base: 2
  },
  roomMultipliers: {
    'Secret Room': 2,
    'Tower Boss Room': 2
  },
  luckPotionMultipliers: {
    None: { legendary: 1, mythical: 1 },
    Lesser: { legendary: 2, mythical: 2 },
    Greater: { legendary: 3, mythical: 3 },
    Greatest: { legendary: 3, mythical: 5 }
  },
  rareBoostRarities: ['Rare', 'Epic', 'Legendary', 'Mythical'],
  sourceFormulas: {}
};

function numberFrom(value: unknown, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function normalizeItemType(value: unknown): ItemType {
  if (value === 'currency') return 'currency';
  return ITEM_TYPES.includes(value as ItemType) ? value as ItemType : 'misc';
}

function normalizeRarity(value: unknown): ItemRarity {
  return LOOT_RARITIES.includes(value as ItemRarity) ? value as ItemRarity : 'Common';
}

function stringList(value: unknown, fallback: string[]) {
  const list = Array.isArray(value) ? value.map(String).map((entry) => entry.trim()).filter(Boolean) : [];
  return list.length ? list : fallback;
}

function numberList(value: unknown, fallback: number[]) {
  const list = Array.isArray(value) ? value.map((entry) => numberFrom(entry, NaN)).filter(Number.isFinite) : [];
  return list.length ? list : fallback;
}

function numberRecord(value: unknown, fallback: Record<string, number>) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return fallback;
  const result: Record<string, number> = {};
  for (const [key, raw] of Object.entries(value)) {
    const parsed = numberFrom(raw, NaN);
    if (key && Number.isFinite(parsed)) result[key] = parsed;
  }
  return Object.keys(result).length ? result : fallback;
}

function luckPotionRecord(value: unknown, fallback: Record<string, { legendary: number; mythical: number }>) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return fallback;
  const result: Record<string, { legendary: number; mythical: number }> = {};
  for (const [key, raw] of Object.entries(value)) {
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) continue;
    const entry = raw as Record<string, unknown>;
    const legendary = numberFrom(entry.legendary, NaN);
    const mythical = numberFrom(entry.mythical, NaN);
    if (key && Number.isFinite(legendary) && Number.isFinite(mythical)) result[key] = {
      legendary: Math.max(0, legendary),
      mythical: Math.max(0, mythical)
    };
  }
  return Object.keys(result).length ? result : fallback;
}

export function normalizeLootGeneratorSettings(value: unknown): LootGeneratorSettings {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  return {
    biomes: stringList(source.biomes, DEFAULT_LOOT_GENERATOR_SETTINGS.biomes),
    difficulties: numberList(source.difficulties, DEFAULT_LOOT_GENERATOR_SETTINGS.difficulties),
    poolSizes: stringList(source.poolSizes, DEFAULT_LOOT_GENERATOR_SETTINGS.poolSizes),
    roomTypes: stringList(source.roomTypes, DEFAULT_LOOT_GENERATOR_SETTINGS.roomTypes),
    luckPotionOptions: stringList(source.luckPotionOptions, DEFAULT_LOOT_GENERATOR_SETTINGS.luckPotionOptions),
    baseRollsByPoolSize: numberRecord(source.baseRollsByPoolSize, DEFAULT_LOOT_GENERATOR_SETTINGS.baseRollsByPoolSize),
    poolMultipliers: numberRecord(source.poolMultipliers, DEFAULT_LOOT_GENERATOR_SETTINGS.poolMultipliers),
    roomMultipliers: numberRecord(source.roomMultipliers, DEFAULT_LOOT_GENERATOR_SETTINGS.roomMultipliers),
    luckPotionMultipliers: luckPotionRecord(source.luckPotionMultipliers, DEFAULT_LOOT_GENERATOR_SETTINGS.luckPotionMultipliers),
    rareBoostRarities: Array.isArray(source.rareBoostRarities) ? source.rareBoostRarities.map(normalizeRarity) : DEFAULT_LOOT_GENERATOR_SETTINGS.rareBoostRarities,
    sourceFormulas: source.sourceFormulas && typeof source.sourceFormulas === 'object' && !Array.isArray(source.sourceFormulas)
      ? Object.fromEntries(Object.entries(source.sourceFormulas).map(([key, val]) => [key, String(val ?? '')]))
      : {}
  };
}

export function normalizeLootPool(value: unknown): LootPool {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  return {
    id: String(source.id ?? ''),
    key: String(source.key ?? ''),
    name: String(source.name ?? 'Item Catalog'),
    description: String(source.description ?? ''),
    order: numberFrom(source.order, 0)
  };
}

export function normalizeLootItem(value: unknown): LootItem {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  const type = normalizeItemType(source.type);
  return {
    id: String(source.id ?? ''),
    poolId: String(source.poolId ?? ''),
    name: String(source.name ?? 'Unknown Item'),
    category: String(source.category ?? type),
    biomes: Array.isArray(source.biomes) ? source.biomes.map(String).filter(Boolean) : ['Any'],
    minDifficulty: Math.max(1, numberFrom(source.minDifficulty, 1)),
    maxDifficulty: Math.max(1, numberFrom(source.maxDifficulty, 5)),
    type,
    rarity: normalizeRarity(source.rarity),
    minQuantity: Math.max(1, numberFrom(source.minQuantity, 1)),
    maxQuantity: Math.max(1, numberFrom(source.maxQuantity, 1)),
    weight: Math.max(0, numberFrom(source.weight, 1)),
    towerBaseOnly: Boolean(source.towerBaseOnly),
    notes: String(source.notes ?? '')
  };
}

export function normalizeLootDrop(value: unknown): LootDrop {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  const quantity = Math.max(1, numberFrom(source.quantity, 1));
  return {
    id: String(source.id ?? crypto.randomUUID()),
    rollNumber: Math.max(1, numberFrom(source.rollNumber, 1)),
    itemId: String(source.itemId ?? ''),
    name: String(source.name ?? 'Unknown Item'),
    type: normalizeItemType(source.type),
    rarity: normalizeRarity(source.rarity),
    quantity,
    remaining: Math.max(0, numberFrom(source.remaining, quantity))
  };
}

export function normalizeExplorationPayload(value: unknown): ExplorationPayload {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  return {
    characters: Array.isArray(source.characters) ? source.characters.map(normalizeCharacter).filter((entry) => entry.id) : [],
    pools: Array.isArray(source.pools) ? source.pools.map(normalizeLootPool).filter((entry) => entry.id) : [],
    items: Array.isArray(source.items) ? source.items.map(normalizeLootItem).filter((entry) => entry.id) : [],
    settings: normalizeLootGeneratorSettings(source.settings)
  };
}

export function normalizeLootRollPayload(value: unknown): LootRollPayload {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  const multiplier = source.multiplier && typeof source.multiplier === 'object' ? source.multiplier as Record<string, unknown> : {};
  return {
    drops: Array.isArray(source.drops) ? source.drops.map(normalizeLootDrop).filter((entry) => entry.itemId) : [],
    rolls: Math.max(0, numberFrom(source.rolls, 0)),
    eligibleCount: Math.max(0, numberFrom(source.eligibleCount, 0)),
    totalWeight: Math.max(0, numberFrom(source.totalWeight, 0)),
    multiplier: {
      total: Math.max(0, numberFrom(multiplier.total, 1)),
      pool: Math.max(0, numberFrom(multiplier.pool, 1)),
      room: Math.max(0, numberFrom(multiplier.room, 1)),
      legendaryLuck: Math.max(0, numberFrom(multiplier.legendaryLuck, 1)),
      mythicalLuck: Math.max(0, numberFrom(multiplier.mythicalLuck, 1))
    }
  };
}

export function getLootMultiplier(settings: LootGeneratorSettings, poolSize: string, roomType: string, luckPotion = 'None') {
  const pool = settings.poolMultipliers[poolSize] ?? 1;
  const room = settings.roomMultipliers[roomType] ?? 1;
  const luck = settings.luckPotionMultipliers[luckPotion] ?? settings.luckPotionMultipliers.None ?? { legendary: 1, mythical: 1 };
  return { pool, room, total: pool * room, legendaryLuck: luck.legendary, mythicalLuck: luck.mythical };
}

function token(value: string) {
  return value.replace(/\s+/g, '').toLowerCase();
}

export function lootBiomeMatches(item: LootItem, biome: string) {
  if (biome === 'Any') return true;
  const selected = token(biome);
  const tokens = item.biomes.map(token);
  return tokens.includes('any') || tokens.includes(selected);
}

export function isLootItemEligible(item: LootItem, biome: string, difficulty: number, poolSize: string) {
  return item.name
    && lootBiomeMatches(item, biome)
    && item.minDifficulty <= difficulty
    && item.maxDifficulty >= difficulty
    && (!item.towerBaseOnly || poolSize === 'Tower Floor' || poolSize === 'Base');
}

export function getLootRarityMultiplier(settings: LootGeneratorSettings, rarity: ItemRarity, poolSize: string, roomType: string, luckPotion = 'None') {
  const multiplier = getLootMultiplier(settings, poolSize, roomType, luckPotion);
  const boosted = settings.rareBoostRarities.includes(rarity) ? multiplier.total : 1;
  const legendaryLuck = rarity === 'Legendary' ? multiplier.legendaryLuck : 1;
  const mythicalLuck = rarity === 'Mythical' ? multiplier.mythicalLuck : 1;
  return boosted * legendaryLuck * mythicalLuck;
}

export function getWeightedLootItems(items: LootItem[], settings: LootGeneratorSettings, biome: string, difficulty: number, poolSize: string, roomType: string, luckPotion = 'None'): WeightedLootItem[] {
  return items
    .filter((item) => isLootItemEligible(item, biome, difficulty, poolSize))
    .map((item) => ({
      item,
      adjustedWeight: item.weight * getLootRarityMultiplier(settings, item.rarity, poolSize, roomType, luckPotion)
    }))
    .filter((entry) => entry.adjustedWeight > 0);
}

export function getLootRaritySummary(items: LootItem[], settings: LootGeneratorSettings, biome: string, difficulty: number, poolSize: string, roomType: string, luckPotion = 'None'): LootRaritySummary {
  const weightedItems = getWeightedLootItems(items, settings, biome, difficulty, poolSize, roomType, luckPotion);
  const totalWeight = weightedItems.reduce((sum, entry) => sum + entry.adjustedWeight, 0);
  const rarityWeights = Object.fromEntries(LOOT_RARITIES.map((rarity) => [rarity, 0])) as Record<ItemRarity, number>;
  const rarityCounts = Object.fromEntries(LOOT_RARITIES.map((rarity) => [rarity, 0])) as Record<ItemRarity, number>;

  for (const entry of weightedItems) {
    rarityWeights[entry.item.rarity] += entry.adjustedWeight;
    rarityCounts[entry.item.rarity] += 1;
  }

  return {
    rarities: LOOT_RARITIES.map((rarity) => ({
      rarity,
      multiplier: getLootRarityMultiplier(settings, rarity, poolSize, roomType, luckPotion),
      itemCount: rarityCounts[rarity],
      weight: rarityWeights[rarity],
      chance: totalWeight > 0 ? (rarityWeights[rarity] / totalWeight) * 100 : 0
    })),
    eligibleCount: weightedItems.length,
    totalWeight,
    weightedItems
  };
}

export function getLootRollCount(settings: LootGeneratorSettings, poolSize: string, roomType: string) {
  const base = Math.max(1, Math.round(settings.baseRollsByPoolSize[poolSize] ?? 1));
  if (roomType === 'Secret Room') return Math.max(1, Math.ceil(base / 2));
  if (roomType === 'Tower Boss Room') return base * 2;
  return base;
}
