import { normalizeCharacter } from '@/features/characters/data';
import { normalizeInventoryItem } from '@/features/inventory/data';
import type { Character, InventoryItem, ItemRarity, ItemType, WalletBalance } from '@/lib/types';

export type TradingPostListingStatus = 'pending_approval' | 'active' | 'declined' | 'withdrawn' | 'completed' | 'removed';
export type TradingPostOfferStatus = 'pending' | 'accepted' | 'declined' | 'cancelled' | 'unavailable';

export type TradingPostItemSnapshot = {
  itemId: string | null;
  name: string;
  displayName: string;
  description: string;
  type: ItemType;
  rarity: ItemRarity;
  quantity: number;
};

export type TradingPostCurrency = {
  unitId: string;
  systemKey: string;
  key: string;
  name: string;
  symbol: string;
  order: number;
  amount: number;
};

export type TradingPostListing = {
  id: string;
  vendorId: string;
  sellerUserId: string;
  sellerCharacterId: string;
  sellerPlayerName: string;
  sellerCharacterName: string;
  item: TradingPostItemSnapshot;
  quantity: number;
  status: TradingPostListingStatus;
  reviewNote: string;
  reviewedByName: string;
  offerCount: number;
  createdAt: string;
  approvedAt: string;
  closedAt: string;
  completedAt: string;
};

export type TradingPostOffer = {
  id: string;
  listingId: string;
  offererUserId: string;
  offererCharacterId: string;
  offererPlayerName: string;
  offererCharacterName: string;
  status: TradingPostOfferStatus;
  message: string;
  items: TradingPostItemSnapshot[];
  currency: TradingPostCurrency[];
  listing: TradingPostListing;
  createdAt: string;
  resolvedAt: string;
};

export type TradingPostPayload = {
  vendor: {
    id: string;
    name: string;
    cityKey: string;
    shopkeeperName: string;
    canManage: boolean;
  } | null;
  characters: Character[];
  selectedCharacterId: string;
  inventory: InventoryItem[];
  wallet: WalletBalance[];
  activeListings: TradingPostListing[];
  myListings: TradingPostListing[];
  pendingReview: TradingPostListing[];
  offersReceived: TradingPostOffer[];
  offersSent: TradingPostOffer[];
};

const RARITIES: ItemRarity[] = ['Common', 'Uncommon', 'Rare', 'Epic', 'Legendary', 'Mythical'];

function record(value: unknown): Record<string, unknown> {
  return value && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, unknown> : {};
}

function numberValue(value: unknown, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function itemSnapshot(value: unknown): TradingPostItemSnapshot {
  const source = record(value);
  return {
    itemId: source.itemId ? String(source.itemId) : null,
    name: String(source.name ?? 'Unknown Item'),
    displayName: String(source.displayName ?? ''),
    description: String(source.description ?? ''),
    type: String(source.type ?? 'misc') as ItemType,
    rarity: RARITIES.includes(source.rarity as ItemRarity) ? source.rarity as ItemRarity : 'Common',
    quantity: Math.max(0, numberValue(source.quantity, 0))
  };
}

function normalizeListing(value: unknown): TradingPostListing {
  const source = record(value);
  const status = String(source.status ?? 'pending_approval') as TradingPostListingStatus;
  return {
    id: String(source.id ?? ''),
    vendorId: String(source.vendorId ?? ''),
    sellerUserId: String(source.sellerUserId ?? ''),
    sellerCharacterId: String(source.sellerCharacterId ?? ''),
    sellerPlayerName: String(source.sellerPlayerName ?? 'Unknown Player'),
    sellerCharacterName: String(source.sellerCharacterName ?? 'Unknown Character'),
    item: itemSnapshot(source.item),
    quantity: Math.max(0, numberValue(source.quantity, 0)),
    status,
    reviewNote: String(source.reviewNote ?? ''),
    reviewedByName: String(source.reviewedByName ?? ''),
    offerCount: Math.max(0, numberValue(source.offerCount, 0)),
    createdAt: String(source.createdAt ?? ''),
    approvedAt: String(source.approvedAt ?? ''),
    closedAt: String(source.closedAt ?? ''),
    completedAt: String(source.completedAt ?? '')
  };
}

function normalizeCurrency(value: unknown): TradingPostCurrency {
  const source = record(value);
  return {
    unitId: String(source.unitId ?? ''),
    systemKey: String(source.systemKey ?? 'common'),
    key: String(source.key ?? ''),
    name: String(source.name ?? 'Currency'),
    symbol: String(source.symbol ?? ''),
    order: numberValue(source.order, 0),
    amount: Math.max(0, Math.floor(numberValue(source.amount, 0)))
  };
}

function normalizeOffer(value: unknown): TradingPostOffer {
  const source = record(value);
  return {
    id: String(source.id ?? ''),
    listingId: String(source.listingId ?? ''),
    offererUserId: String(source.offererUserId ?? ''),
    offererCharacterId: String(source.offererCharacterId ?? ''),
    offererPlayerName: String(source.offererPlayerName ?? 'Unknown Player'),
    offererCharacterName: String(source.offererCharacterName ?? 'Unknown Character'),
    status: String(source.status ?? 'pending') as TradingPostOfferStatus,
    message: String(source.message ?? ''),
    items: Array.isArray(source.items) ? source.items.map(itemSnapshot) : [],
    currency: Array.isArray(source.currency) ? source.currency.map(normalizeCurrency).filter((entry) => entry.unitId && entry.amount > 0) : [],
    listing: normalizeListing(source.listing),
    createdAt: String(source.createdAt ?? ''),
    resolvedAt: String(source.resolvedAt ?? '')
  };
}

export function normalizeTradingPostPayload(value: unknown): TradingPostPayload {
  const source = record(value);
  const vendor = record(source.vendor);
  return {
    vendor: vendor.id ? {
      id: String(vendor.id),
      name: String(vendor.name ?? 'Trading Post'),
      cityKey: String(vendor.cityKey ?? ''),
      shopkeeperName: String(vendor.shopkeeperName ?? 'Unassigned shopkeeper'),
      canManage: Boolean(vendor.canManage)
    } : null,
    characters: Array.isArray(source.characters) ? source.characters.map(normalizeCharacter).filter((entry) => entry.id) : [],
    selectedCharacterId: String(source.selectedCharacterId ?? ''),
    inventory: Array.isArray(source.inventory) ? source.inventory.map(normalizeInventoryItem).filter((entry) => entry.id) : [],
    wallet: Array.isArray(source.wallet) ? source.wallet.map((value) => {
      const balance = record(value);
      const unit = record(balance.unit);
      return {
        unit: {
          id: String(unit.id ?? ''),
          systemKey: String(unit.systemKey ?? 'common'),
          key: String(unit.key ?? ''),
          name: String(unit.name ?? 'Currency'),
          symbol: String(unit.symbol ?? ''),
          order: numberValue(unit.order, 0)
        },
        amount: Math.max(0, Math.floor(numberValue(balance.amount, 0)))
      };
    }).filter((entry) => entry.unit.id) : [],
    activeListings: Array.isArray(source.activeListings) ? source.activeListings.map(normalizeListing).filter((entry) => entry.id) : [],
    myListings: Array.isArray(source.myListings) ? source.myListings.map(normalizeListing).filter((entry) => entry.id) : [],
    pendingReview: Array.isArray(source.pendingReview) ? source.pendingReview.map(normalizeListing).filter((entry) => entry.id) : [],
    offersReceived: Array.isArray(source.offersReceived) ? source.offersReceived.map(normalizeOffer).filter((entry) => entry.id) : [],
    offersSent: Array.isArray(source.offersSent) ? source.offersSent.map(normalizeOffer).filter((entry) => entry.id) : []
  };
}
