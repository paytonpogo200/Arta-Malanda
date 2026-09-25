import { normalizeInventoryItem } from '@/features/inventory/data';
import type { House, HouseAccess, InventoryItem } from '@/lib/types';

export type HousePayload = {
  house: House | null;
  homes: House[];
  items: InventoryItem[];
  access: HouseAccess;
};

function numberFrom(value: unknown, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
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
    source: source.source === 'mobile' ? 'mobile' : 'static',
    name: String(source.name ?? (source.kind === 'wagon-home' ? 'Wagon Home' : source.kind === 'caged-wagon' ? 'Caged Wagon Stable' : 'House')),
    stableName: String(source.stableName ?? (source.kind === 'caged-wagon' ? 'Caged Wagon Stable' : 'Stable')),
    cityName: String(source.cityName ?? 'Calostrynn'),
    inventorySlots: Math.max(0, numberFrom(source.inventorySlots, 45)),
    stableSlots: Math.max(0, numberFrom(source.stableSlots, 0)),
    locked: Boolean(source.locked),
    isMain: Boolean(source.isMain),
    displayOrder: Math.max(0, numberFrom(source.displayOrder, 0)),
    accessible: source.accessible === undefined ? true : Boolean(source.accessible),
    accessReason: String(source.accessReason ?? ''),
    kind: source.kind === 'wagon-home' || source.kind === 'caged-wagon' || source.kind === 'stable' ? source.kind : 'house',
    storageItemId: source.storageItemId ? String(source.storageItemId) : null,
    storageCharacterId: source.storageCharacterId ? String(source.storageCharacterId) : null,
    stableStorageItemId: source.stableStorageItemId ? String(source.stableStorageItemId) : null,
    stableStorageCharacterId: source.stableStorageCharacterId ? String(source.stableStorageCharacterId) : null
  };
}

export function normalizeHouseAccess(value: unknown): HouseAccess {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  return {
    owner: Boolean(source.owner),
    dm: Boolean(source.dm),
    house: Boolean(source.house),
    stable: Boolean(source.stable)
  };
}

export function normalizeHousePayload(value: unknown): HousePayload {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  return {
    house: normalizeHouse(source.house),
    homes: Array.isArray(source.homes) ? source.homes.map(normalizeHouse).filter((home): home is House => Boolean(home)) : [],
    items: Array.isArray(source.items) ? source.items.map(normalizeInventoryItem).filter((item) => item.id) : [],
    access: normalizeHouseAccess(source.access)
  };
}
