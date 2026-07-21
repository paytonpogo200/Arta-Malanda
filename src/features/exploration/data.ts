import { ITEM_TYPES } from '@/features/inventory/data';
import type { ItemRarity, ItemType, LootItem, LootPool } from '@/lib/types';

export type ItemCatalogPayload = {
  pools: LootPool[];
  items: LootItem[];
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
    type,
    rarity: normalizeRarity(source.rarity),
    minQuantity: Math.max(1, numberFrom(source.minQuantity, 1)),
    maxQuantity: Math.max(1, numberFrom(source.maxQuantity, 1)),
    notes: String(source.notes ?? '')
  };
}

export function normalizeItemCatalogPayload(value: unknown): ItemCatalogPayload {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  return {
    pools: Array.isArray(source.pools) ? source.pools.map(normalizeLootPool).filter((entry) => entry.id) : [],
    items: Array.isArray(source.items) ? source.items.map(normalizeLootItem).filter((entry) => entry.id) : []
  };
}
