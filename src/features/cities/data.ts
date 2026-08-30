import { normalizeCharacter, normalizeProfile } from '@/features/characters/data';
import { ITEM_TYPES } from '@/features/inventory/data';
import type { Character, City, CityConstructionProject, CityConstructionRequirement, ItemCatalogEntry, ItemRarity, ItemType, LoadoutModifiers, MarketProduct, Profile, ShopSection, ShopVendor } from '@/lib/types';

export type CitiesPayload = {
  profiles: Profile[];
  characters: Character[];
  cities: City[];
  vendors: ShopVendor[];
  constructionProjects: CityConstructionProject[];
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

function normalizeModifierMap(value: unknown): LoadoutModifiers {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return {};
  return Object.fromEntries(
    Object.entries(value)
      .map(([key, raw]) => [key, numberFrom(raw, NaN)] as const)
      .filter((entry): entry is readonly [string, number] => Number.isFinite(entry[1]))
  ) as LoadoutModifiers;
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

export const CURRENCY_SYSTEMS = {
  common: {
    label: 'Global Currency',
    units: [
      { key: 'sovereign', name: 'Sovereign', value: 10000 },
      { key: 'crown', name: 'Crown', value: 1000 },
      { key: 'mark', name: 'Mark', value: 100 },
      { key: 'shilling', name: 'Shilling', value: 10 },
      { key: 'bit', name: 'Bit', value: 1 }
    ]
  },
  calostrynn: {
    label: 'Calostrynn Currency',
    units: [
      { key: 'cal', name: 'Cal', value: 10000 },
      { key: 'callor', name: 'Callor', value: 100 },
      { key: 'callis', name: 'Callis', value: 10 },
      { key: 'coin', name: 'Coin', value: 1 }
    ]
  }
} as const;

export type CurrencySystemKey = keyof typeof CURRENCY_SYSTEMS;

export function normalizeCurrencySystemKey(value: unknown): CurrencySystemKey {
  return value === 'common' ? 'common' : 'calostrynn';
}

export function currencyUnitsForSystem(systemKey: string) {
  return CURRENCY_SYSTEMS[normalizeCurrencySystemKey(systemKey)].units;
}

export function composeCurrencyValue(parts: Record<string, number>, systemKey: string) {
  return currencyUnitsForSystem(systemKey).reduce((total, unit) => total + Math.max(0, Math.floor(parts[unit.key] ?? 0)) * unit.value, 0);
}

export function decomposeCurrencyValue(value: number, systemKey: string) {
  let remaining = Math.max(0, Math.floor(value));
  return Object.fromEntries(currencyUnitsForSystem(systemKey).map((unit) => {
    const amount = Math.floor(remaining / unit.value);
    remaining -= amount * unit.value;
    return [unit.key, amount];
  }));
}

export function formatCurrencyValue(value: number, systemKey = 'calostrynn') {
  let remaining = Math.max(0, Math.floor(value));
  const units = currencyUnitsForSystem(systemKey);
  const parts = units.map((unit) => {
    const amount = Math.floor(remaining / unit.value);
    remaining -= amount * unit.value;
    if (!amount) return '';
    return `${amount} ${amount === 1 ? unit.name : `${unit.name}s`}`;
  }).filter(Boolean);
  return parts.length ? parts.join(' ') : `0 ${units[units.length - 1].name}s`;
}

export function formatCoinValue(value: number) {
  return formatCurrencyValue(value, 'calostrynn');
}

export function normalizeCity(value: unknown): City {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  return {
    id: String(source.id ?? ''),
    key: String(source.key ?? ''),
    name: String(source.name ?? 'Unknown City'),
    description: String(source.description ?? ''),
    primaryColor: String(source.primaryColor ?? '#d1a85b'),
    secondaryColor: String(source.secondaryColor ?? '#1f7875'),
    accentColor: String(source.accentColor ?? '#f5b44c'),
    locked: Boolean(source.locked),
    currentResidence: Boolean(source.currentResidence),
    showUnderConstruction: Boolean(source.showUnderConstruction),
    order: numberFrom(source.order, 0)
  };
}

export function normalizeConstructionRequirement(value: unknown): CityConstructionRequirement {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  return {
    id: String(source.id ?? ''),
    projectId: String(source.projectId ?? ''),
    item: normalizeItemCatalogEntry(source.item),
    requiredQuantity: Math.max(0, numberFrom(source.requiredQuantity, 0)),
    contributedQuantity: Math.max(0, numberFrom(source.contributedQuantity, 0)),
    complete: Boolean(source.complete),
    order: numberFrom(source.order, 0)
  };
}

export function normalizeConstructionProject(value: unknown): CityConstructionProject {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  const requirements = Array.isArray(source.requirements)
    ? source.requirements.map(normalizeConstructionRequirement).filter((entry) => entry.id && entry.item.id)
    : [];
  const status = source.status === 'ended' ? 'ended' : 'active';
  return {
    id: String(source.id ?? ''),
    cityKey: String(source.cityKey ?? ''),
    name: String(source.name ?? 'Construction Project'),
    status,
    order: numberFrom(source.order, 0),
    complete: Boolean(source.complete),
    progress: Math.max(0, Math.min(1, numberFrom(source.progress, 0))),
    requirements
  };
}

export function normalizeProduct(value: unknown): MarketProduct {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  const kind = source.kind === 'spell' || source.kind === 'document' || source.kind === 'service' ? source.kind : 'item';
  const rawPages = Array.isArray(source.documentPages)
    ? source.documentPages
    : Array.isArray(source.document_pages)
      ? source.document_pages
      : [];
  return {
    id: String(source.id ?? ''),
    vendorId: String(source.vendorId ?? ''),
    key: String(source.key ?? ''),
    name: String(source.name ?? 'Unknown item'),
    description: String(source.description ?? ''),
    type: normalizeItemType(source.type),
    rarity: normalizeRarity(source.rarity),
    priceCoin: Math.max(0, numberFrom(source.priceCoin, 0)),
    currencySystemKey: normalizeCurrencySystemKey(source.currencySystemKey ?? source.currency_system_key),
    stockQuantity: source.stockQuantity === null || source.stockQuantity === undefined ? null : Math.max(0, numberFrom(source.stockQuantity, 0)),
    available: Boolean(source.available),
    catalogItemKey: String(source.catalogItemKey ?? ''),
    section: String(source.section ?? ''),
    quantityStep: Math.max(0.1, numberFrom(source.quantityStep, 1)),
    kind,
    manaCost: Math.max(0, numberFrom(source.manaCost, 0)),
    manaLabel: String(source.manaLabel ?? ''),
    documentAuthor: String(source.documentAuthor ?? ''),
    documentContent: String(source.documentContent ?? ''),
    documentPages: rawPages.map(String),
    documentVisibility: source.documentVisibility === 'government' || source.document_visibility === 'government' ? 'government' : 'for_sale',
    documentEditorUserId: source.documentEditorUserId || source.document_editor_user_id ? String(source.documentEditorUserId ?? source.document_editor_user_id) : null
  };
}

export function normalizeShopSection(value: unknown): ShopSection {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  const rawSectionType = source.sectionType ?? source.section_type;
  const sectionType = rawSectionType === 'sale' || rawSectionType === 'rent' || rawSectionType === 'holding'
    ? rawSectionType
    : 'standard';
  return {
    id: String(source.id ?? ''),
    vendorId: String(source.vendorId ?? ''),
    key: String(source.key ?? ''),
    name: String(source.name ?? 'Wares'),
    npcName: String(source.npcName ?? ''),
    roleLabel: String(source.roleLabel ?? ''),
    sectionType,
    slotCount: Math.max(0, numberFrom(source.slotCount, 0)),
    hidden: Boolean(source.hidden),
    order: numberFrom(source.order, 0),
    productCount: Math.max(0, numberFrom(source.productCount, 0))
  };
}

export function normalizeVendor(value: unknown): ShopVendor {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  const blueprintType = source.blueprintType === 'blacksmith'
    || source.blueprintType === 'armory'
    || source.blueprintType === 'brewery'
    || source.blueprintType === 'spell_registrar'
    || source.blueprintType === 'library'
    || source.blueprintType === 'stable'
    ? source.blueprintType
    : 'market';
  return {
    id: String(source.id ?? ''),
    cityKey: String(source.cityKey ?? ''),
    key: String(source.key ?? ''),
    name: String(source.name ?? 'Vendor'),
    npcName: String(source.npcName ?? 'Shopkeeper'),
    facility: String(source.facility ?? 'Market'),
    category: String(source.category ?? 'General'),
    blueprintType,
    payoutCharacterId: source.payoutCharacterId ? String(source.payoutCharacterId) : null,
    custom: Boolean(source.custom),
    hidden: Boolean(source.hidden),
    order: numberFrom(source.order, 0),
    sections: Array.isArray(source.sections) ? source.sections.map(normalizeShopSection).filter((section) => section.id || section.name) : [],
    products: Array.isArray(source.products) ? source.products.map(normalizeProduct).filter((product) => product.id) : []
  };
}

export function normalizeCitiesPayload(value: unknown): CitiesPayload {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  return {
    profiles: Array.isArray(source.profiles) ? source.profiles.map(normalizeProfile).filter((profile) => profile.id) : [],
    characters: Array.isArray(source.characters) ? source.characters.map(normalizeCharacter).filter((character) => character.id) : [],
    cities: Array.isArray(source.cities) ? source.cities.map(normalizeCity).filter((city) => city.key) : [],
    vendors: Array.isArray(source.vendors) ? source.vendors.map(normalizeVendor).filter((vendor) => vendor.id) : [],
    constructionProjects: Array.isArray(source.constructionProjects) ? source.constructionProjects.map(normalizeConstructionProject).filter((project) => project.id) : []
  };
}
