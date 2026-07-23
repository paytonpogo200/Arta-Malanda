import { normalizeInventoryItem } from '@/features/inventory/data';
import type { CampaignProperty, House, InventoryItem, PropertyLocation, PropertyType } from '@/lib/types';

export const PROPERTY_TYPES: PropertyType[] = ['animal', 'wagon', 'pet', 'mount', 'other'];
export const PROPERTY_LOCATIONS: PropertyLocation[] = ['with_character', 'at_house'];

export type HousePayload = {
  house: House | null;
  items: InventoryItem[];
  properties: CampaignProperty[];
};

function numberFrom(value: unknown, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function normalizePropertyType(value: unknown): PropertyType {
  return PROPERTY_TYPES.includes(value as PropertyType) ? value as PropertyType : 'other';
}

function normalizePropertyLocation(value: unknown): PropertyLocation {
  return PROPERTY_LOCATIONS.includes(value as PropertyLocation) ? value as PropertyLocation : 'at_house';
}

export function normalizeHouse(value: unknown): House | null {
  if (!value || typeof value !== 'object') return null;
  const source = value as Record<string, unknown>;
  const id = String(source.id ?? '');
  const ownerUserId = String(source.ownerUserId ?? '');
  if (!id || !ownerUserId) return null;

  return {
    id,
    ownerUserId,
    cityName: String(source.cityName ?? 'Calostrynn'),
    inventorySlots: Math.max(0, numberFrom(source.inventorySlots, 50)),
    propertySlots: Math.max(0, numberFrom(source.propertySlots, 10)),
    locked: Boolean(source.locked)
  };
}

export function normalizeProperty(value: unknown): CampaignProperty {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};

  return {
    id: String(source.id ?? ''),
    ownerUserId: String(source.ownerUserId ?? ''),
    caretakerCharacterId: source.caretakerCharacterId ? String(source.caretakerCharacterId) : null,
    name: String(source.name ?? 'Property'),
    type: normalizePropertyType(source.type),
    location: normalizePropertyLocation(source.location),
    isPet: Boolean(source.isPet),
    slotIndex: Math.max(0, numberFrom(source.slotIndex, 0)),
    storageCapacity: Math.max(0, numberFrom(source.storageCapacity, 0))
  };
}

export function normalizeHousePayload(value: unknown): HousePayload {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  return {
    house: normalizeHouse(source.house),
    items: Array.isArray(source.items) ? source.items.map(normalizeInventoryItem).filter((item) => item.id) : [],
    properties: Array.isArray(source.properties) ? source.properties.map(normalizeProperty).filter((property) => property.id) : []
  };
}
