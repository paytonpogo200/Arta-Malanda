import { normalizeBestiaryEntity } from '@/features/bestiary/data';
import { normalizeClassTemplate } from '@/features/characters/data';
import { normalizeCity, normalizeVendor } from '@/features/cities/data';
import { normalizeLootItem, normalizeLootPool } from '@/features/exploration/data';
import { ITEM_TYPES } from '@/features/inventory/data';
import { normalizeSpell } from '@/features/spells/data';
import type { BestiaryEntity, City, ClassTemplate, ItemCatalogEntry, ItemRarity, ItemType, LootItem, LootPool, ShopVendor, Spell } from '@/lib/types';

export type UpdateAssetsPayload = {
  classes: ClassTemplate[];
  cities: City[];
  vendors: ShopVendor[];
  spells: Spell[];
  itemCatalog: ItemCatalogEntry[];
  lootPools: LootPool[];
  lootItems: LootItem[];
  bestiary: BestiaryEntity[];
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

function normalizeModifierMap(value: unknown) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return {};
  return Object.fromEntries(
    Object.entries(value)
      .map(([key, raw]) => [key, numberFrom(raw, NaN)] as const)
      .filter((entry): entry is readonly [string, number] => Number.isFinite(entry[1]))
  );
}

export function normalizeItemCatalogEntry(value: unknown): ItemCatalogEntry {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  return {
    id: String(source.id ?? ''),
    key: String(source.key ?? ''),
    name: String(source.name ?? 'Unknown Item'),
    type: normalizeItemType(source.type),
    rarity: normalizeRarity(source.rarity),
    category: String(source.category ?? ''),
    properties: Array.isArray(source.properties) ? source.properties.map(String).filter(Boolean) : [],
    quantityStep: Math.max(0.1, numberFrom(source.quantityStep, 1)),
    stackable: source.stackable === undefined ? true : Boolean(source.stackable),
    defaultModifiers: normalizeModifierMap(source.defaultModifiers),
    material: String(source.material ?? ''),
    isTwoHanded: Boolean(source.isTwoHanded),
    storageCapacity: Math.max(0, numberFrom(source.storageCapacity, 0)),
    notes: String(source.notes ?? ''),
    canBeEnhanced: Boolean(source.canBeEnhanced),
    canBeEnchanted: Boolean(source.canBeEnchanted),
    active: source.active === undefined ? true : Boolean(source.active),
    order: numberFrom(source.order, 0)
  };
}

export function normalizeUpdateAssetsPayload(value: unknown): UpdateAssetsPayload {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  return {
    classes: Array.isArray(source.classes) ? source.classes.map(normalizeClassTemplate).filter((entry) => entry.id) : [],
    cities: Array.isArray(source.cities) ? source.cities.map(normalizeCity).filter((entry) => entry.id) : [],
    vendors: Array.isArray(source.vendors) ? source.vendors.map(normalizeVendor).filter((entry) => entry.id) : [],
    spells: Array.isArray(source.spells) ? source.spells.map(normalizeSpell).filter((entry) => entry.id) : [],
    itemCatalog: Array.isArray(source.itemCatalog) ? source.itemCatalog.map(normalizeItemCatalogEntry).filter((entry) => entry.id) : [],
    lootPools: Array.isArray(source.lootPools) ? source.lootPools.map(normalizeLootPool).filter((entry) => entry.id) : [],
    lootItems: Array.isArray(source.lootItems) ? source.lootItems.map(normalizeLootItem).filter((entry) => entry.id) : [],
    bestiary: Array.isArray(source.bestiary) ? source.bestiary.map(normalizeBestiaryEntity).filter((entry) => entry.id) : []
  };
}
