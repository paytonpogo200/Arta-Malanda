import type { CurrencyUnit, InventoryItem, ItemRarity, ItemType, LoadoutModifiers, LoadoutSlot, WalletBalance } from '@/lib/types';

export type CharacterInventoryPayload = {
  items: InventoryItem[];
  wallet: WalletBalance[];
};

export const ITEM_TYPES: ItemType[] = ['weapon', 'armor', 'shield', 'pet', 'accessory', 'storage', 'material', 'catalyst', 'rune', 'ore', 'potion', 'food', 'plant', 'fabric', 'tool', 'quest', 'currency', 'misc'];
export const LOADOUT_SLOTS: LoadoutSlot[] = ['weapon', 'armor', 'shield', 'active-pet', 'accessory-1', 'accessory-2', 'accessory-3', 'accessory-4'];

export function acceptsLoadoutItem(slot: LoadoutSlot, type: ItemType) {
  if (slot === 'weapon') return type === 'weapon';
  if (slot === 'armor') return type === 'armor';
  if (slot === 'shield') return type === 'shield';
  if (slot === 'active-pet') return type === 'pet';
  return type === 'accessory';
}

function numberFrom(value: unknown, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function normalizeItemType(value: unknown): ItemType {
  return ITEM_TYPES.includes(value as ItemType) ? value as ItemType : 'misc';
}

function normalizeRarity(value: unknown): ItemRarity {
  if (value === 'Uncommon' || value === 'Rare' || value === 'Epic' || value === 'Legendary' || value === 'Mythical') return value;
  return 'Common';
}

function normalizeLoadoutSlot(value: unknown): LoadoutSlot | null {
  return LOADOUT_SLOTS.includes(value as LoadoutSlot) ? value as LoadoutSlot : null;
}

function normalizeCurrencyUnit(value: unknown): CurrencyUnit {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  return {
    id: String(source.id ?? ''),
    key: String(source.key ?? ''),
    name: String(source.name ?? 'Currency'),
    symbol: String(source.symbol ?? ''),
    order: numberFrom(source.order, 0)
  };
}

function normalizeModifiers(value: unknown): LoadoutModifiers {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return {};
  return Object.fromEntries(
    Object.entries(value)
      .map(([key, raw]) => [key, numberFrom(raw, NaN)] as const)
      .filter((entry): entry is readonly [string, number] => Number.isFinite(entry[1]))
  ) as LoadoutModifiers;
}

export function normalizeInventoryItem(value: unknown): InventoryItem {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  return {
    id: String(source.id ?? ''),
    characterId: String(source.characterId ?? ''),
    parentItemId: source.parentItemId ? String(source.parentItemId) : null,
    name: String(source.name ?? 'Unknown item'),
    type: normalizeItemType(source.type),
    rarity: normalizeRarity(source.rarity),
    quantity: Math.max(0.5, numberFrom(source.quantity, 1)),
    slotIndex: Math.max(0, numberFrom(source.slotIndex, 0)),
    loadoutSlot: normalizeLoadoutSlot(source.loadoutSlot),
    isStorage: Boolean(source.isStorage),
    storageCapacity: Math.max(0, numberFrom(source.storageCapacity, 0)),
    modifiers: normalizeModifiers(source.modifiers),
    enchantment: source.enchantment ? String(source.enchantment) : undefined,
    material: source.material ? String(source.material) : undefined,
    enhancementCount: Math.max(0, numberFrom(source.enhancementCount, 0)),
    isTwoHanded: Boolean(source.isTwoHanded)
  };
}

export function itemAllowsDecimalQuantity(item: Pick<InventoryItem, 'type' | 'name'> | { type: ItemType; name: string }) {
  const name = item.name.toLowerCase();
  return (item.type === 'material' || item.type === 'ore') && (
    name === 'bronze scale'
    || name === 'iron scale'
    || name === 'steel scale'
    || name === 'mythril scale'
    || name === 'vaylium scale'
    || name === 'dragonscale scale'
    || name === 'dragon scale'
  );
}

export function quantityStepForItem(item: Pick<InventoryItem, 'type' | 'name'> | { type: ItemType; name: string }) {
  return itemAllowsDecimalQuantity(item) ? 0.5 : 1;
}

export function normalizeWalletBalance(value: unknown): WalletBalance | null {
  if (!value || typeof value !== 'object') return null;
  const source = value as Record<string, unknown>;
  const unit = normalizeCurrencyUnit(source.unit);
  if (!unit.id) return null;
  return {
    unit,
    amount: Math.max(0, numberFrom(source.amount, 0))
  };
}

export function normalizeCharacterInventoryPayload(value: unknown): CharacterInventoryPayload {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  return {
    items: Array.isArray(source.items) ? source.items.map(normalizeInventoryItem).filter((item) => item.id) : [],
    wallet: Array.isArray(source.wallet) ? source.wallet.map(normalizeWalletBalance).filter((entry): entry is WalletBalance => Boolean(entry)) : []
  };
}
