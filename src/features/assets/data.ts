import { normalizeBestiaryEntity } from '@/features/bestiary/data';
import { normalizeClassTemplate } from '@/features/characters/data';
import { normalizeCity, normalizeVendor } from '@/features/cities/data';
import { normalizeLootItem, normalizeLootPool } from '@/features/exploration/data';
import { normalizeSpell } from '@/features/spells/data';
import type { BestiaryEntity, City, ClassTemplate, LootItem, LootPool, ShopVendor, Spell } from '@/lib/types';

export type UpdateAssetsPayload = {
  classes: ClassTemplate[];
  cities: City[];
  vendors: ShopVendor[];
  spells: Spell[];
  lootPools: LootPool[];
  lootItems: LootItem[];
  bestiary: BestiaryEntity[];
};

export function normalizeUpdateAssetsPayload(value: unknown): UpdateAssetsPayload {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  return {
    classes: Array.isArray(source.classes) ? source.classes.map(normalizeClassTemplate).filter((entry) => entry.id) : [],
    cities: Array.isArray(source.cities) ? source.cities.map(normalizeCity).filter((entry) => entry.id) : [],
    vendors: Array.isArray(source.vendors) ? source.vendors.map(normalizeVendor).filter((entry) => entry.id) : [],
    spells: Array.isArray(source.spells) ? source.spells.map(normalizeSpell).filter((entry) => entry.id) : [],
    lootPools: Array.isArray(source.lootPools) ? source.lootPools.map(normalizeLootPool).filter((entry) => entry.id) : [],
    lootItems: Array.isArray(source.lootItems) ? source.lootItems.map(normalizeLootItem).filter((entry) => entry.id) : [],
    bestiary: Array.isArray(source.bestiary) ? source.bestiary.map(normalizeBestiaryEntity).filter((entry) => entry.id) : []
  };
}
