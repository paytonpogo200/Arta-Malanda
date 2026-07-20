import { normalizeCharacter } from '@/features/characters/data';
import { ITEM_TYPES } from '@/features/inventory/data';
import type { Character, City, ItemRarity, ItemType, MarketProduct, ShopVendor } from '@/lib/types';

export type CitiesPayload = {
  characters: Character[];
  cities: City[];
  vendors: ShopVendor[];
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

export function formatCoinValue(value: number) {
  let remaining = Math.max(0, Math.floor(value));
  const cal = Math.floor(remaining / 10000);
  remaining -= cal * 10000;
  const callor = Math.floor(remaining / 100);
  remaining -= callor * 100;
  const callis = Math.floor(remaining / 10);
  remaining -= callis * 10;
  const parts = [
    cal ? `${cal} Cal` : '',
    callor ? `${callor} Callor` : '',
    callis ? `${callis} Callis` : '',
    remaining ? `${remaining} coin` : ''
  ].filter(Boolean);
  return parts.length ? parts.join(' ') : '0 coin';
}

export function normalizeCity(value: unknown): City {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  return {
    id: String(source.id ?? ''),
    key: String(source.key ?? ''),
    name: String(source.name ?? 'Unknown City'),
    locked: Boolean(source.locked),
    order: numberFrom(source.order, 0)
  };
}

export function normalizeProduct(value: unknown): MarketProduct {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  return {
    id: String(source.id ?? ''),
    vendorId: String(source.vendorId ?? ''),
    key: String(source.key ?? ''),
    name: String(source.name ?? 'Unknown item'),
    description: String(source.description ?? ''),
    type: normalizeItemType(source.type),
    rarity: normalizeRarity(source.rarity),
    priceCoin: Math.max(0, numberFrom(source.priceCoin, 0)),
    stockQuantity: source.stockQuantity === null || source.stockQuantity === undefined ? null : Math.max(0, numberFrom(source.stockQuantity, 0)),
    available: Boolean(source.available)
  };
}

export function normalizeVendor(value: unknown): ShopVendor {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  return {
    id: String(source.id ?? ''),
    cityKey: String(source.cityKey ?? ''),
    key: String(source.key ?? ''),
    name: String(source.name ?? 'Vendor'),
    npcName: String(source.npcName ?? 'Shopkeeper'),
    facility: String(source.facility ?? 'Market'),
    category: String(source.category ?? 'General'),
    hidden: Boolean(source.hidden),
    order: numberFrom(source.order, 0),
    products: Array.isArray(source.products) ? source.products.map(normalizeProduct).filter((product) => product.id) : []
  };
}

export function normalizeCitiesPayload(value: unknown): CitiesPayload {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  return {
    characters: Array.isArray(source.characters) ? source.characters.map(normalizeCharacter).filter((character) => character.id) : [],
    cities: Array.isArray(source.cities) ? source.cities.map(normalizeCity).filter((city) => city.key) : [],
    vendors: Array.isArray(source.vendors) ? source.vendors.map(normalizeVendor).filter((vendor) => vendor.id) : []
  };
}
