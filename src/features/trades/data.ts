import { ITEM_TYPES } from '@/features/inventory/data';
import { rarityOptions } from '@/lib/utils/rarity';
import type { ItemRarity, ItemType, TradeItem, TradeOffer, TradeStatus } from '@/lib/types';

function normalizeTradeStatus(value: unknown): TradeStatus {
  if (value === 'accepted' || value === 'declined' || value === 'cancelled') return value;
  return 'pending';
}

function normalizeTradeCurrency(value: unknown): { unitId: string; amount: number }[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((entry) => {
      const source = entry && typeof entry === 'object' ? entry as Record<string, unknown> : {};
      return {
        unitId: String(source.unitId ?? source.unit_id ?? ''),
        amount: Math.max(0, Math.floor(Number(source.amount ?? 0)))
      };
    })
    .filter((entry) => entry.unitId && entry.amount > 0);
}

function normalizeTradeItems(value: unknown, fallbackId: unknown, fallbackName: unknown, fallbackQuantity: unknown): TradeItem[] {
  const sourceItems = Array.isArray(value) ? value : [];
  const items = sourceItems
    .map<TradeItem | null>((entry) => {
      const source = entry && typeof entry === 'object' ? entry as Record<string, unknown> : {};
      const itemId = String(source.itemId ?? source.item_id ?? source.id ?? '');
      const quantity = Math.max(0.5, Number(source.quantity ?? 1));
      if (!itemId) return null;
      return {
        itemId,
        name: String(source.name ?? source.itemName ?? source.item_name ?? 'Trade item'),
        quantity,
        type: ITEM_TYPES.includes(source.type as ItemType) ? source.type as ItemType : undefined,
        rarity: rarityOptions.includes(source.rarity as ItemRarity) ? source.rarity as ItemRarity : undefined
      } satisfies TradeItem;
    })
    .filter((entry): entry is TradeItem => Boolean(entry));

  if (items.length) return items;
  const itemId = fallbackId ? String(fallbackId) : '';
  if (!itemId) return [];
  return [{
    itemId,
    name: String(fallbackName ?? 'Trade item'),
    quantity: Math.max(0.5, Number(fallbackQuantity ?? 1))
  }];
}

export function normalizeTradeOffer(value: unknown): TradeOffer {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  return {
    id: String(source.id ?? ''),
    senderUserId: String(source.senderUserId ?? source.sender_user_id ?? ''),
    recipientUserId: String(source.recipientUserId ?? source.recipient_user_id ?? ''),
    senderCharacterId: String(source.senderCharacterId ?? source.sender_character_id ?? ''),
    targetCharacterId: String(source.targetCharacterId ?? source.target_character_id ?? ''),
    senderCharacterName: String(source.senderCharacterName ?? source.sender_character_name ?? 'Unknown'),
    targetCharacterName: String(source.targetCharacterName ?? source.target_character_name ?? 'Unknown'),
    status: normalizeTradeStatus(source.status),
    offerNote: String(source.offerNote ?? source.offer_note ?? ''),
    requestNote: String(source.requestNote ?? source.request_note ?? ''),
    offeredItemId: source.offeredItemId || source.offered_item_id ? String(source.offeredItemId ?? source.offered_item_id) : null,
    offeredItemName: String(source.offeredItemName ?? source.offered_item_name ?? ''),
    offeredQuantity: Math.max(0.5, Number(source.offeredQuantity ?? source.offered_quantity ?? 1)),
    requestedItemId: source.requestedItemId || source.requested_item_id ? String(source.requestedItemId ?? source.requested_item_id) : null,
    requestedItemName: String(source.requestedItemName ?? source.requested_item_name ?? ''),
    requestedQuantity: Math.max(0.5, Number(source.requestedQuantity ?? source.requested_quantity ?? 1)),
    offeredItems: normalizeTradeItems(source.offeredItems ?? source.offered_items, source.offeredItemId ?? source.offered_item_id, source.offeredItemName ?? source.offered_item_name, source.offeredQuantity ?? source.offered_quantity),
    requestedItems: normalizeTradeItems(source.requestedItems ?? source.requested_items, source.requestedItemId ?? source.requested_item_id, source.requestedItemName ?? source.requested_item_name, source.requestedQuantity ?? source.requested_quantity),
    offeredCurrency: normalizeTradeCurrency(source.offeredCurrency ?? source.offered_currency),
    requestedCurrency: normalizeTradeCurrency(source.requestedCurrency ?? source.requested_currency),
    message: String(source.message ?? ''),
    createdAt: source.createdAt || source.created_at ? String(source.createdAt ?? source.created_at) : null,
    updatedAt: source.updatedAt || source.updated_at ? String(source.updatedAt ?? source.updated_at) : null
  };
}

export function normalizeTradeList(value: unknown): TradeOffer[] {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  const trades = Array.isArray(source.trades) ? source.trades : Array.isArray(value) ? value : [];
  return trades.map(normalizeTradeOffer).filter((trade) => trade.id);
}
