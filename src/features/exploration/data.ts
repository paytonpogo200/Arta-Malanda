import { normalizeCharacter } from '@/features/characters/data';
import { ITEM_TYPES } from '@/features/inventory/data';
import type { Character, ItemRarity, ItemType, LootDrop, LootItem, LootPool } from '@/lib/types';

export type ExplorationPayload = {
  characters: Character[];
  pools: LootPool[];
  items: LootItem[];
};

export type LootRollPayload = {
  drops: LootDrop[];
};

const RARITIES: ItemRarity[] = ['Common', 'Uncommon', 'Rare', 'Epic', 'Legendary', 'Mythical'];

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
    type: normalizeItemType(source.type),
    rarity: normalizeRarity(source.rarity),
    minQuantity: Math.max(1, numberFrom(source.minQuantity, 1)),
    maxQuantity: Math.max(1, numberFrom(source.maxQuantity, 1)),
    weight: Math.max(1, numberFrom(source.weight, 1)),
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
    items: Array.isArray(source.items) ? source.items.map(normalizeLootItem).filter((entry) => entry.id) : []
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
