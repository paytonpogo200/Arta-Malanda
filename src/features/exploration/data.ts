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
};

const RARITIES: ItemRarity[] = ['Common', 'Uncommon', 'Rare', 'Epic', 'Legendary', 'Mythical'];
const DEFAULT_SETTINGS: LootGeneratorSettings = {
  biomes: ['Any'],
  difficulties: [1, 2, 3, 4, 5],
  poolSizes: ['Night Encounter', 'Small Cave', 'Medium Cave', 'Large Cave', 'Dragon Lair', 'Tower Floor', 'Base'],
  roomTypes: ['Normal', 'Secret Room', 'Tower Boss Room'],
  baseRollsByPoolSize: {
    'Night Encounter': 5,
    'Small Cave': 10,
    'Medium Cave': 15,
    'Large Cave': 20,
    'Dragon Lair': 50,
    'Tower Floor': 25,
    Base: 40
  },
  rareMultiplierKeywords: { capital: 5, base: 2, camp: 1.33 },
  rareBoostRarities: ['Rare', 'Epic', 'Legendary', 'Mythical'],
  towerBoostRarities: ['Epic', 'Legendary', 'Mythical'],
  towerBoostMultiplier: 2,
  specialRoomBoostRarities: ['Epic', 'Legendary', 'Mythical'],
  specialRoomTypes: ['Secret Room', 'Tower Boss Room'],
  specialRoomMultiplier: 2,
  sourceFormulas: {}
};

function numberFrom(value: unknown, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function normalizeItemType(value: unknown): ItemType {
  return ITEM_TYPES.includes(value as ItemType) ? value as ItemType : 'misc';
}

function normalizeRarity(value: unknown): ItemRarity {
  return RARITIES.includes(value as ItemRarity) ? value as ItemRarity : 'Common';
}

export function normalizeLootPool(value: unknown): LootPool {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  return {
    id: String(source.id ?? ''),
    key: String(source.key ?? ''),
    name: String(source.name ?? 'Loot Pool'),
    description: String(source.description ?? ''),
    order: numberFrom(source.order, 0)
  };
}

export function normalizeLootItem(value: unknown): LootItem {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  return {
    id: String(source.id ?? ''),
    poolId: String(source.poolId ?? ''),
    name: String(source.name ?? 'Unknown Item'),
    category: String(source.category ?? ''),
    biomes: Array.isArray(source.biomes) ? source.biomes.map(String).filter(Boolean) : ['Any'],
    minDifficulty: Math.max(1, numberFrom(source.minDifficulty, 1)),
    maxDifficulty: Math.max(1, numberFrom(source.maxDifficulty, 5)),
    type: normalizeItemType(source.type),
    rarity: normalizeRarity(source.rarity),
    minQuantity: Math.max(1, numberFrom(source.minQuantity, 1)),
    maxQuantity: Math.max(1, numberFrom(source.maxQuantity, 1)),
    weight: Math.max(1, numberFrom(source.weight, 1)),
    baseWeight: Math.max(1, numberFrom(source.baseWeight, numberFrom(source.weight, 1))),
    notes: String(source.notes ?? '')
  };
}

export function normalizeLootDrop(value: unknown): LootDrop {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  return {
    id: String(source.id ?? crypto.randomUUID()),
    itemId: String(source.itemId ?? ''),
    name: String(source.name ?? 'Unknown Item'),
    type: normalizeItemType(source.type),
    rarity: normalizeRarity(source.rarity),
    quantity: Math.max(1, numberFrom(source.quantity, 1))
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
  return {
    drops: Array.isArray(source.drops) ? source.drops.map(normalizeLootDrop).filter((entry) => entry.itemId) : []
  };
}

export function parseLootImport(text: string) {
  const trimmed = text.trim();
  if (!trimmed) return [];
  if (trimmed.startsWith('[')) return JSON.parse(trimmed);

  const [headerLine, ...rows] = trimmed.split(/\r?\n/);
  const headers = headerLine.split(',').map((header) => header.trim().toLowerCase());
  return rows.filter(Boolean).map((row) => {
    const cells = row.split(',').map((cell) => cell.trim());
    return Object.fromEntries(headers.map((header, index) => [header, cells[index] ?? '']));
  });
}

export function normalizeLootGeneratorSettings(value: unknown): LootGeneratorSettings {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  const objectOfNumbers = (entry: unknown, fallback: Record<string, number>) => {
    if (!entry || typeof entry !== 'object' || Array.isArray(entry)) return fallback;
    const result: Record<string, number> = {};
    for (const [key, val] of Object.entries(entry)) {
      const parsed = Number(val);
      if (key && Number.isFinite(parsed)) result[key] = parsed;
    }
    return Object.keys(result).length ? result : fallback;
  };

  return {
    biomes: Array.isArray(source.biomes) && source.biomes.length ? source.biomes.map(String).filter(Boolean) : DEFAULT_SETTINGS.biomes,
    difficulties: Array.isArray(source.difficulties) && source.difficulties.length ? source.difficulties.map((entry) => numberFrom(entry, 1)).filter((entry) => entry > 0) : DEFAULT_SETTINGS.difficulties,
    poolSizes: Array.isArray(source.poolSizes) && source.poolSizes.length ? source.poolSizes.map(String).filter(Boolean) : DEFAULT_SETTINGS.poolSizes,
    roomTypes: Array.isArray(source.roomTypes) && source.roomTypes.length ? source.roomTypes.map(String).filter(Boolean) : DEFAULT_SETTINGS.roomTypes,
    baseRollsByPoolSize: objectOfNumbers(source.baseRollsByPoolSize, DEFAULT_SETTINGS.baseRollsByPoolSize),
    rareMultiplierKeywords: objectOfNumbers(source.rareMultiplierKeywords, DEFAULT_SETTINGS.rareMultiplierKeywords),
    rareBoostRarities: Array.isArray(source.rareBoostRarities) ? source.rareBoostRarities.map(normalizeRarity) : DEFAULT_SETTINGS.rareBoostRarities,
    towerBoostRarities: Array.isArray(source.towerBoostRarities) ? source.towerBoostRarities.map(normalizeRarity) : DEFAULT_SETTINGS.towerBoostRarities,
    towerBoostMultiplier: numberFrom(source.towerBoostMultiplier, DEFAULT_SETTINGS.towerBoostMultiplier ?? 2),
    specialRoomBoostRarities: Array.isArray(source.specialRoomBoostRarities) ? source.specialRoomBoostRarities.map(normalizeRarity) : DEFAULT_SETTINGS.specialRoomBoostRarities,
    specialRoomTypes: Array.isArray(source.specialRoomTypes) ? source.specialRoomTypes.map(String).filter(Boolean) : DEFAULT_SETTINGS.specialRoomTypes,
    specialRoomMultiplier: numberFrom(source.specialRoomMultiplier, DEFAULT_SETTINGS.specialRoomMultiplier ?? 2),
    sourceFormulas: source.sourceFormulas && typeof source.sourceFormulas === 'object' && !Array.isArray(source.sourceFormulas)
      ? Object.fromEntries(Object.entries(source.sourceFormulas).map(([key, val]) => [key, String(val ?? '')]))
      : {}
  };
}

export function estimateLootRollCount(settings: LootGeneratorSettings, poolSize: string, roomType: string) {
  const base = Math.max(1, Math.round(settings.baseRollsByPoolSize[poolSize] ?? 1));
  if (roomType === 'Secret Room') return Math.max(1, Math.ceil(base / 2));
  if (roomType === 'Tower Boss Room') return base * 2;
  return base;
}
