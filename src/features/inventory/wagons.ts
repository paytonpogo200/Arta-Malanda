import { normalizeInventoryItem } from '@/features/inventory/data';
import type { InventoryItem } from '@/lib/types';

export type WagonActivity = {
  id: string;
  wagonId: string;
  actorCharacterId: string | null;
  actorName: string;
  action: 'stored' | 'taken';
  itemName: string;
  quantity: number;
  createdAt: string;
};

export type WagonStorage = {
  wagon: InventoryItem;
  ownerCharacterId: string;
  ownerName: string;
  ownerUserId: string | null;
  locationName: string;
  canManage: boolean;
};

export function normalizeWagonPayload(source: unknown) {
  const payload = source && typeof source === 'object' ? source as Record<string, unknown> : {};
  const wagons = Array.isArray(payload.wagons) ? payload.wagons.map((entry) => {
    const record = entry && typeof entry === 'object' ? entry as Record<string, unknown> : {};
    return {
      wagon: normalizeInventoryItem(record.wagon),
      ownerCharacterId: String(record.ownerCharacterId ?? ''),
      ownerName: String(record.ownerName ?? 'Unknown'),
      ownerUserId: record.ownerUserId ? String(record.ownerUserId) : null,
      locationName: String(record.locationName ?? ''),
      canManage: Boolean(record.canManage)
    };
  }).filter((entry) => entry.wagon.id) : [];
  const items = Array.isArray(payload.items) ? payload.items.map(normalizeInventoryItem).filter((entry) => entry.id) : [];
  const activity = Array.isArray(payload.activity) ? payload.activity.map((entry) => {
    const record = entry && typeof entry === 'object' ? entry as Record<string, unknown> : {};
    return {
      id: String(record.id ?? ''),
      wagonId: String(record.wagonId ?? ''),
      actorCharacterId: record.actorCharacterId ? String(record.actorCharacterId) : null,
      actorName: String(record.actorName ?? 'Unknown'),
      action: record.action === 'taken' ? 'taken' as const : 'stored' as const,
      itemName: String(record.itemName ?? 'Item'),
      quantity: Number(record.quantity ?? 0),
      createdAt: String(record.createdAt ?? '')
    };
  }).filter((entry) => entry.id && entry.wagonId) : [];
  return { wagons, items, activity };
}
