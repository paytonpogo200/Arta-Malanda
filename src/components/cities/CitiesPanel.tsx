'use client';

import { useCallback, useEffect, useMemo, useState, type CSSProperties, type FormEvent } from 'react';
import { ArrowDown, ArrowLeft, ArrowUp, CheckCircle2, ChevronDown, ChevronRight, Eye, EyeOff, Hammer, Lock, PackageCheck, Pencil, Plus, RefreshCw, Search, Settings, ShoppingBag, Sparkles, Star, Store, Trash2, Unlock, Users, WandSparkles, X } from 'lucide-react';
import { ItemIcon } from '@/components/inventory/ItemIcon';
import { Button } from '@/components/ui/Button';
import { Card, SoftCard } from '@/components/ui/Card';
import { ColorField, SelectField, TextAreaField, TextField } from '@/components/ui/Field';
import { Modal } from '@/components/ui/Modal';
import { NumberInput } from '@/components/ui/NumberInput';
import { composeCurrencyValue, currencyUnitsForSystem, decomposeCurrencyValue, formatCoinValue, formatCurrencyValue, normalizeCitiesPayload, normalizeCurrencySystemKey, type CitiesPayload } from '@/features/cities/data';
import { normalizeUpdateAssetsPayload } from '@/features/assets/data';
import { normalizeHousePayload } from '@/features/houses/data';
import { ITEM_TYPES, normalizeCharacterInventoryPayload, normalizeInventoryItem, quantityStepForItem } from '@/features/inventory/data';
import { normalizeWagonPayload } from '@/features/inventory/wagons';
import { useLiveRefresh } from '@/hooks/useLiveRefresh';
import { potionEffectText } from '@/lib/utils/potions';
import { rarityClass, rarityOptions } from '@/lib/utils/rarity';
import { spellTypeClass, spellTypeFromProductSection, spellTypes } from '@/lib/utils/spells';
import { ATTRIBUTE_KEYS, ATTRIBUTE_LABELS, type Character, type City, type CityConstructionProject, type CityConstructionRequirement, type InventoryItem, type ItemCatalogEntry, type ItemRarity, type ItemType, type MarketProduct, type Profile, type ShopVendor, type WalletBalance } from '@/lib/types';

const EMPTY_PAYLOAD: CitiesPayload = { characters: [], cities: [], vendors: [], constructionProjects: [] };

type ProductDraft = {
  name: string;
  description: string;
  type: ItemType;
  rarity: ItemRarity;
  priceCoin: number;
  currencySystemKey: 'common' | 'calostrynn';
  stockQuantity: number;
  available: boolean;
  section: string;
  quantityStep: number;
  kind: 'item' | 'spell' | 'document' | 'service';
  documentAuthor: string;
  documentContent: string;
  manaCost: number;
  catalogItemKey: string;
};

type VendorDraft = {
  name: string;
  npcName: string;
  facility: string;
  category: string;
  blueprintType: 'market' | 'blacksmith' | 'armory' | 'brewery' | 'spell_registrar' | 'library';
  payoutCharacterId: string;
  hidden: boolean;
  order: number;
};

type CityDraft = {
  name: string;
  description: string;
  primaryColor: string;
  secondaryColor: string;
  accentColor: string;
  locked: boolean;
  currentResidence: boolean;
  showUnderConstruction: boolean;
  order: number;
};

type ProjectRequirementDraft = {
  itemCatalogId: string;
  quantity: number;
};

type ProjectDraft = {
  name: string;
  requirements: ProjectRequirementDraft[];
};

type ContributionSourceItem = {
  source: 'inventory' | 'home' | 'wagon';
  sourceLabel: string;
  item: InventoryItem;
};

type CraftRecipe = {
  key: string;
  section: string;
  name: string;
  type: ItemType;
  laborCoin: number;
  materialQuantity: number;
  materialName?: string;
  twoHanded?: boolean;
  note?: string;
};

type ForgeService = 'blacksmith' | 'armory';

type CraftModalState =
  | { mode: 'craft'; service: ForgeService; recipe: CraftRecipe }
  | { mode: 'enhance'; service: ForgeService }
  | { mode: 'enchant'; service: 'blacksmith' }
  | { mode: 'dragon-scales'; service: ForgeService };

type BreweryDefinition = {
  propertyKey: string;
  potionName: string;
  description: string;
  automatedEffect: string;
  order: number;
};

type BreweryAvailableItem = {
  source: 'inventory' | 'house';
  id: string;
  name: string;
  type: ItemType;
  rarity: ItemRarity;
  quantity: number;
  properties: string[];
  catalystBonus: number;
};

type BreweryState = {
  definitions: BreweryDefinition[];
  availableItems: BreweryAvailableItem[];
  houseAccess: {
    accessible: boolean;
    city: string;
  };
};

type BrewResult = {
  success: boolean;
  d20: number;
  alchemyBonus: number;
  catalystBonus: number;
  total: number;
  quality: string | null;
  message: string;
  item?: InventoryItem | null;
};

type CraftSourceItem = {
  source: 'inventory' | 'house';
  item: InventoryItem;
};

const BLACKSMITH_RECIPES: CraftRecipe[] = [
  { key: 'dagger', section: 'Light Weapons', name: 'Dagger', type: 'weapon', laborCoin: 50, materialQuantity: 0.5 },
  { key: 'throwing-knives', section: 'Light Weapons', name: 'Throwing Knives', type: 'weapon', laborCoin: 100, materialQuantity: 0.5 },
  { key: 'shortbow', section: 'Light Weapons', name: 'Shortbow', type: 'weapon', laborCoin: 100, materialQuantity: 0.5 },
  { key: 'custom-light-weapon', section: 'Light Weapons', name: 'Custom Light Weapon', type: 'weapon', laborCoin: 1000, materialQuantity: 0.5 },
  { key: 'sword', section: 'Medium Weapons', name: 'Sword', type: 'weapon', laborCoin: 300, materialQuantity: 1 },
  { key: 'spear', section: 'Medium Weapons', name: 'Spear', type: 'weapon', laborCoin: 500, materialQuantity: 1 },
  { key: 'longbow', section: 'Medium Weapons', name: 'Longbow', type: 'weapon', laborCoin: 500, materialQuantity: 1 },
  { key: 'custom-medium-weapon', section: 'Medium Weapons', name: 'Custom Medium Weapon', type: 'weapon', laborCoin: 2500, materialQuantity: 1 },
  { key: 'battleaxe', section: 'Heavy Weapons', name: 'Battleaxe', type: 'weapon', laborCoin: 3000, materialQuantity: 2, twoHanded: true },
  { key: 'mace', section: 'Heavy Weapons', name: 'Mace', type: 'weapon', laborCoin: 3000, materialQuantity: 2, twoHanded: true },
  { key: 'claymore', section: 'Heavy Weapons', name: 'Claymore', type: 'weapon', laborCoin: 3000, materialQuantity: 2, twoHanded: true },
  { key: 'crossbow', section: 'Heavy Weapons', name: 'Crossbow', type: 'weapon', laborCoin: 4000, materialQuantity: 2, twoHanded: true },
  { key: 'custom-heavy-weapon', section: 'Heavy Weapons', name: 'Custom Heavy Weapon', type: 'weapon', laborCoin: 5000, materialQuantity: 2, twoHanded: true },
  { key: 'magic-bow', section: 'Magecraft Commissions', name: 'Magic Bow', type: 'weapon', laborCoin: 3000, materialQuantity: 0, note: 'Commissioned magecraft weapon.' },
  { key: 'magic-longbow', section: 'Magecraft Commissions', name: 'Magic Longbow', type: 'weapon', laborCoin: 5000, materialQuantity: 0, note: 'Commissioned magecraft weapon.' },
  { key: 'wand', section: 'Magecraft Commissions', name: 'Wand', type: 'weapon', laborCoin: 100, materialQuantity: 0.5, note: 'Arcana Wood, Mythril, or Vaylium commission.' },
  { key: 'scepter', section: 'Magecraft Commissions', name: 'Scepter', type: 'weapon', laborCoin: 1000, materialQuantity: 1, note: 'Arcana Wood, Mythril, or Vaylium commission.' },
  { key: 'staff', section: 'Magecraft Commissions', name: 'Staff', type: 'weapon', laborCoin: 5000, materialQuantity: 2, note: 'Arcana Wood, Mythril, or Vaylium commission.' },
  { key: 'custom-magecraft', section: 'Magecraft Commissions', name: 'Custom Magecraft Commission', type: 'weapon', laborCoin: 6500, materialQuantity: 1, note: 'DM-facing flexible magecraft commission.' },
  { key: 'shield', section: 'Shield Creation', name: 'Shield', type: 'shield', laborCoin: 5000, materialQuantity: 1 }
];

const BLACKSMITH_SERVICE_SECTIONS = ['Material Scales', 'Light Weapons', 'Medium Weapons', 'Heavy Weapons', 'Magecraft Commissions', 'Shield Creation', 'Mythril Services', 'Runes'];
const SPELL_SERVICE_SECTIONS = spellTypes.map((type) => `${type} Spells`);
const ARMORY_RECIPES: CraftRecipe[] = [
  { key: 'leather-armor', section: 'Armor Creation', name: 'Leather Armor', type: 'armor', laborCoin: 0, materialQuantity: 0, note: '-1 Vitality' },
  { key: 'iron-armor', section: 'Armor Creation', name: 'Iron Armor', type: 'armor', laborCoin: 500, materialQuantity: 3, materialName: 'Iron Scale', note: '-1 Agility' },
  { key: 'steel-armor', section: 'Armor Creation', name: 'Steel Armor', type: 'armor', laborCoin: 2500, materialQuantity: 3, materialName: 'Steel Scale', note: '+1 Vitality' },
  { key: 'mythril-armor', section: 'Armor Creation', name: 'Mythril Armor', type: 'armor', laborCoin: 5000, materialQuantity: 3, materialName: 'Mythril Scale', note: 'Enhanceable' },
  { key: 'vaylium-armor', section: 'Armor Creation', name: 'Vaylium Armor', type: 'armor', laborCoin: 7500, materialQuantity: 3, materialName: 'Vaylium Scale', note: '+3 Intelligence, +1 Magic Resist' },
  { key: 'dragonscale-armor', section: 'Armor Creation', name: 'Dragonscale Armor', type: 'armor', laborCoin: 10000, materialQuantity: 3, materialName: 'Dragonscale Scale', note: '+2 Vitality, +5 Magic Resist' }
];
const FORGE_MATERIAL_ORDER = ['Bronze Scale', 'Iron Scale', 'Steel Scale', 'Mythril Scale', 'Vaylium Scale', 'Dragonscale Scale'];
const ARMORY_SERVICE_SECTIONS = ['Shared Material Scales', 'Armor Creation', 'Mythril Services'];
const MATERIAL_SECTION_ALIASES = new Set(['material scales', 'materials', 'scales']);
const CALOSTRYNN_ACTIVE_VENDOR_KEYS = new Set(['calostrynn-armory', 'calostrynn-brewery', 'calostrynn-blacksmith', 'calostrynn-city-market', 'calostrynn-library', 'calostrynn-spells']);
const MAGICAL_RESEARCH_TYPES = spellTypes;
const BREWERY_STRENGTHS = ['Lesser', 'Greater', 'Greatest'] as const;
const FORGE_RUNE_NAMES = ['Ember Rune', 'Frost Rune', 'Lightning Rune', 'Earth Rune', 'Wind Rune', 'Mountain Rune', 'Void Rune'];

function numberFromUnknown(value: unknown, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function itemCanBeEnhanced(item: InventoryItem) {
  return item.canBeEnhanced || (`${item.material ?? ''} ${item.name}`.toLowerCase().includes('mythril') && ['weapon', 'shield', 'armor', 'tool'].includes(item.type));
}

function itemCanBeEnchanted(item: InventoryItem) {
  return item.canBeEnchanted || (`${item.material ?? ''} ${item.name}`.toLowerCase().includes('mythril') && ['weapon', 'shield', 'tool'].includes(item.type));
}

const ENHANCEMENT_OPTIONS = ATTRIBUTE_KEYS.map((key) => ({ key, label: ATTRIBUTE_LABELS[key] }));

function productToDraft(product: MarketProduct): ProductDraft {
  return {
    name: product.name,
    description: product.description,
    type: product.type,
    rarity: product.rarity,
    priceCoin: product.priceCoin,
    currencySystemKey: normalizeCurrencySystemKey(product.currencySystemKey),
    stockQuantity: product.stockQuantity ?? 0,
    available: product.available,
    section: product.section || '',
    quantityStep: product.quantityStep || quantityStepForItem(product),
    kind: product.kind,
    documentAuthor: product.documentAuthor,
    documentContent: product.documentContent,
    manaCost: product.manaCost,
    catalogItemKey: product.catalogItemKey
  };
}

function vendorToDraft(vendor: ShopVendor): VendorDraft {
  return {
    name: vendor.name,
    npcName: vendor.npcName,
    facility: vendor.facility,
    category: vendor.category,
    blueprintType: vendor.blueprintType,
    payoutCharacterId: vendor.payoutCharacterId ?? '',
    hidden: vendor.hidden,
    order: vendor.order
  };
}

function defaultVendorDraft(): VendorDraft {
  return {
    name: 'New Shop',
    npcName: 'Shopkeeper',
    facility: 'Market',
    category: 'General',
    blueprintType: 'market',
    payoutCharacterId: '',
    hidden: false,
    order: 0
  };
}

function defaultProductDraft(vendor: ShopVendor, city?: City | null): ProductDraft {
  const currencySystemKey = city?.key === 'calostrynn' ? 'calostrynn' : 'common';
  const kind = vendor.blueprintType === 'spell_registrar'
    ? 'spell'
    : vendor.blueprintType === 'library'
      ? 'document'
      : 'item';
  return {
    name: kind === 'spell' ? 'New Spell' : kind === 'document' ? 'New Document' : 'New Item',
    description: '',
    type: 'misc',
    rarity: 'Common',
    priceCoin: 0,
    currencySystemKey,
    stockQuantity: 0,
    available: true,
    section: vendor.blueprintType === 'library' ? 'Government' : kind === 'spell' ? 'Utility Spells' : 'Wares',
    quantityStep: 1,
    kind,
    documentAuthor: '',
    documentContent: '',
    manaCost: 0,
    catalogItemKey: ''
  };
}

const SHOP_BLUEPRINTS: Array<{ key: VendorDraft['blueprintType']; label: string; facility: string; category: string; description: string }> = [
  { key: 'market', label: 'Market', facility: 'Market', category: 'General Goods', description: 'Blank section-based shop for stalls, supplies, food, pets, tools, and odd wares.' },
  { key: 'blacksmith', label: 'Blacksmith', facility: 'Blacksmith', category: 'Forge Services', description: 'Copies the Calostrynn blacksmith structure and keeps forge services available.' },
  { key: 'armory', label: 'Armory', facility: 'Armory', category: 'Armor Services', description: 'Copies the Calostrynn armory structure and keeps armor crafting services available.' },
  { key: 'brewery', label: 'Brewery', facility: 'Brewery', category: 'Alchemy Services', description: 'Uses the Calostrynn brewery style with editable sale sections.' },
  { key: 'spell_registrar', label: 'Spell Registrar', facility: 'Spell Registrar', category: 'Spells', description: 'Category-based spell shop for existing or custom spells.' },
  { key: 'library', label: 'Library', facility: 'Library', category: 'Documents', description: 'Government and recreation documents, including purchasable books.' }
];

function blueprintInfo(blueprint: VendorDraft['blueprintType']) {
  return SHOP_BLUEPRINTS.find((entry) => entry.key === blueprint) ?? SHOP_BLUEPRINTS[0];
}

function blueprintSections(blueprint: VendorDraft['blueprintType']) {
  if (blueprint === 'blacksmith') return [...BLACKSMITH_SERVICE_SECTIONS, 'Crafted Weapons', 'Mythril Services', 'Dragon Scale Refining'];
  if (blueprint === 'armory') return [...ARMORY_SERVICE_SECTIONS, 'Crafted Armor', 'Dragon Scale Refining'];
  if (blueprint === 'brewery') return ['Brewing Supplies', 'Finished Potions', 'Brew Potion'];
  if (blueprint === 'spell_registrar') return [...SPELL_SERVICE_SECTIONS];
  if (blueprint === 'library') return ['Government', 'Recreation', 'For Sale'];
  return ['Wares'];
}

function defaultSectionForBlueprint(blueprint: VendorDraft['blueprintType']) {
  if (blueprint === 'library') return 'Government';
  if (blueprint === 'spell_registrar') return 'Utility Spells';
  if (blueprint === 'brewery') return 'Finished Potions';
  return 'Wares';
}

function sectionNamesForVendor(vendor: ShopVendor, extraSection = '') {
  const names = new Set<string>();
  vendor.products.forEach((product) => names.add(productSection(product)));
  if (extraSection.trim()) names.add(extraSection.trim());
  if (names.size === 0) names.add(defaultSectionForBlueprint(vendor.blueprintType));
  return Array.from(names).sort((a, b) => {
    const blueprintOrder = blueprintSections(vendor.blueprintType);
    const indexA = blueprintOrder.indexOf(a);
    const indexB = blueprintOrder.indexOf(b);
    if (indexA >= 0 || indexB >= 0) return (indexA < 0 ? 99 : indexA) - (indexB < 0 ? 99 : indexB);
    return a.localeCompare(b);
  });
}

function productDraftFromCatalogItem(vendor: ShopVendor, city: City | null | undefined, section: string, item: ItemCatalogEntry): ProductDraft {
  return {
    ...defaultProductDraft(vendor, city),
    name: item.name,
    description: item.notes,
    type: item.type,
    rarity: item.rarity,
    section,
    quantityStep: item.quantityStep,
    catalogItemKey: item.key,
    kind: 'item',
    stockQuantity: 0
  };
}

function normalizeBreweryDefinition(value: unknown): BreweryDefinition | null {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  const propertyKey = String(source.propertyKey ?? '');
  if (!propertyKey) return null;
  return {
    propertyKey,
    potionName: String(source.potionName ?? propertyKey),
    description: String(source.description ?? ''),
    automatedEffect: String(source.automatedEffect ?? ''),
    order: numberFromUnknown(source.order, 0)
  };
}

function normalizeBreweryAvailableItem(value: unknown): BreweryAvailableItem | null {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  const id = String(source.id ?? '');
  const sourceName = source.source === 'house' ? 'house' : 'inventory';
  if (!id) return null;
  return {
    source: sourceName,
    id,
    name: String(source.name ?? 'Unknown ingredient'),
    type: ITEM_TYPES.includes(source.type as ItemType) ? source.type as ItemType : 'misc',
    rarity: rarityOptions.includes(source.rarity as ItemRarity) ? source.rarity as ItemRarity : 'Common',
    quantity: Math.max(0, numberFromUnknown(source.quantity, 0)),
    properties: Array.isArray(source.properties) ? source.properties.map(String) : [],
    catalystBonus: Math.max(0, numberFromUnknown(source.catalystBonus, 0))
  };
}

function normalizeBreweryState(value: unknown): BreweryState {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  const houseAccess = source.houseAccess && typeof source.houseAccess === 'object' ? source.houseAccess as Record<string, unknown> : {};
  return {
    definitions: Array.isArray(source.definitions)
      ? source.definitions.map(normalizeBreweryDefinition).filter((entry): entry is BreweryDefinition => Boolean(entry)).sort((a, b) => a.order - b.order)
      : [],
    availableItems: Array.isArray(source.availableItems)
      ? source.availableItems.map(normalizeBreweryAvailableItem).filter((entry): entry is BreweryAvailableItem => Boolean(entry))
      : [],
    houseAccess: {
      accessible: Boolean(houseAccess.accessible),
      city: String(houseAccess.city ?? 'Calostrynn')
    }
  };
}

function normalizeBrewResult(value: unknown): BrewResult | null {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  if (!('success' in source)) return null;
  return {
    success: Boolean(source.success),
    d20: numberFromUnknown(source.d20, 0),
    alchemyBonus: numberFromUnknown(source.alchemyBonus, 0),
    catalystBonus: numberFromUnknown(source.catalystBonus, 0),
    total: numberFromUnknown(source.total, 0),
    quality: source.quality ? String(source.quality) : null,
    message: String(source.message ?? ''),
    item: source.item ? normalizeInventoryItem(source.item) : null
  };
}

function productCountText(vendor: ShopVendor) {
  const visible = vendor.products.filter((product) => product.available).length;
  const total = vendor.products.length;
  if (!total) return 'No wares listed';
  return visible === total ? `${total} wares` : `${visible}/${total} visible wares`;
}

function isBlacksmithVendor(vendor: ShopVendor) {
  const searchable = `${vendor.name} ${vendor.facility} ${vendor.category}`.toLowerCase();
  return searchable.includes('blacksmith');
}

function isArmoryVendor(vendor: ShopVendor) {
  const searchable = `${vendor.name} ${vendor.facility} ${vendor.category}`.toLowerCase();
  return searchable.includes('armory');
}

function isBreweryVendor(vendor: ShopVendor) {
  const searchable = `${vendor.name} ${vendor.facility} ${vendor.category}`.toLowerCase();
  return searchable.includes('brewery');
}

function isSpellVendor(vendor: ShopVendor) {
  const searchable = `${vendor.key} ${vendor.name} ${vendor.facility} ${vendor.category}`.toLowerCase();
  return searchable.includes('spell');
}

function isLibraryVendor(vendor: ShopVendor) {
  const searchable = `${vendor.key} ${vendor.name} ${vendor.facility} ${vendor.category}`.toLowerCase();
  return searchable.includes('library');
}

function isSpellProduct(product: MarketProduct) {
  return product.kind === 'spell' || Boolean(spellTypeFromProductSection(product.section));
}

function isMagicalResearchProduct(product: MarketProduct) {
  return product.key === 'library-magical-research' || product.name.toLowerCase() === 'magical research';
}

function isSinglePurchaseProduct(product: MarketProduct) {
  return product.type === 'pet' || isSpellProduct(product) || isMagicalResearchProduct(product);
}

function purchaseActionLabel(product: MarketProduct) {
  if (product.type === 'pet') return 'Send to stable';
  if (isSpellProduct(product)) return 'Learn';
  if (isMagicalResearchProduct(product)) return 'Research';
  return 'Buy';
}

function productEffectText(product: MarketProduct) {
  if (product.type === 'potion') return potionEffectText(product);
  if (isSpellProduct(product)) return product.description;
  return '';
}

function spellManaBadgeText(product: MarketProduct) {
  if (!isSpellProduct(product)) return '';
  if (product.manaLabel) return product.manaLabel;
  if (product.manaCost > 0) return `${product.manaCost} mana`;
  const match = product.description.match(/^(.{1,48}?)\s+-\s+/);
  if (!match) return '';
  const label = match[1].trim();
  return /mana|free|varies|variable|all/i.test(label) || /^\d+$/.test(label) ? label : '';
}

function productCardClass(product: MarketProduct) {
  const spellType = spellTypeFromProductSection(product.section);
  return spellType ? spellTypeClass(spellType) : rarityClass(product.rarity);
}

function productSection(product: MarketProduct) {
  return product.section || product.type || 'Wares';
}

function groupProducts(products: MarketProduct[]) {
  return Array.from(
    products.reduce((map, product) => {
      const section = productSection(product);
      const current = map.get(section) ?? [];
      current.push(product);
      map.set(section, current);
      return map;
    }, new Map<string, MarketProduct[]>())
  ).sort(([a], [b]) => {
    const sectionA = BLACKSMITH_SERVICE_SECTIONS.indexOf(a);
    const sectionB = BLACKSMITH_SERVICE_SECTIONS.indexOf(b);
    if (sectionA >= 0 || sectionB >= 0) return (sectionA < 0 ? 99 : sectionA) - (sectionB < 0 ? 99 : sectionB);
    const spellSectionA = SPELL_SERVICE_SECTIONS.indexOf(a);
    const spellSectionB = SPELL_SERVICE_SECTIONS.indexOf(b);
    if (spellSectionA >= 0 || spellSectionB >= 0) return (spellSectionA < 0 ? 99 : spellSectionA) - (spellSectionB < 0 ? 99 : spellSectionB);
    return a.localeCompare(b);
  });
}

function materialProducts(vendor: ShopVendor) {
  return vendor.products.filter((product) => MATERIAL_SECTION_ALIASES.has(productSection(product).toLowerCase()) || product.name.toLowerCase().endsWith(' scale'));
}

function uniqueProductsByName(products: MarketProduct[]) {
  const byName = new Map<string, MarketProduct>();
  for (const product of products) {
    const key = product.name.toLowerCase();
    if (!byName.has(key)) byName.set(key, product);
  }
  return Array.from(byName.values());
}

function activeCityVendor(vendor: ShopVendor) {
  return vendor.custom || vendor.cityKey !== 'calostrynn' || CALOSTRYNN_ACTIVE_VENDOR_KEYS.has(vendor.key);
}

function sameCityName(left: string | null | undefined, right: string | null | undefined) {
  const normalizedLeft = (left ?? '').trim().replace(/\*+$/g, '').trim().toLowerCase();
  const normalizedRight = (right ?? '').trim().replace(/\*+$/g, '').trim().toLowerCase();
  return normalizedLeft.length > 0 && normalizedLeft === normalizedRight;
}

function catalogKeyForName(name: string) {
  return name.trim().toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
}

function forgeMaterialProducts(vendors: ShopVendor[], service: ForgeService) {
  const vendor = vendors.find(service === 'armory' ? isArmoryVendor : isBlacksmithVendor);
  const source = vendor ? materialProducts(vendor) : vendors.flatMap(materialProducts);
  return uniqueProductsByName(source)
    .filter((product) => FORGE_MATERIAL_ORDER.some((name) => name.toLowerCase() === product.name.toLowerCase()))
    .sort((a, b) => FORGE_MATERIAL_ORDER.findIndex((name) => name.toLowerCase() === a.name.toLowerCase()) - FORGE_MATERIAL_ORDER.findIndex((name) => name.toLowerCase() === b.name.toLowerCase()));
}

function materialProductByName(products: MarketProduct[], materialName?: string) {
  if (!materialName) return null;
  return products.find((product) => product.name.toLowerCase() === materialName.toLowerCase()) ?? null;
}

function hasUsableStock(product: MarketProduct, quantity = 1) {
  return product.available
    && product.priceCoin > 0
    && (product.stockQuantity === null || product.stockQuantity >= quantity);
}

function unavailableReason(product: MarketProduct) {
  if (!product.available) return 'Unavailable';
  if (product.priceCoin <= 0) return 'Needs price';
  if (product.stockQuantity === 0) return 'Out of stock';
  return '';
}

function isBlacksmithClass(character: Character | null) {
  if (!character) return false;
  return character.classKey.toLowerCase() === 'blacksmith' || character.className.toLowerCase() === 'blacksmith';
}

function isArmorCladClass(character: Character | null) {
  if (!character) return false;
  return character.classKey.toLowerCase() === 'armor-clad' || character.className.toLowerCase() === 'armor-clad';
}

function isTalismanistClass(character: Character | null) {
  if (!character) return false;
  return character.classKey.toLowerCase() === 'talismanist' || character.className.toLowerCase() === 'talismanist';
}

function walletTotalCurrency(wallet: WalletBalance[], systemKey = 'calostrynn') {
  const key = normalizeCurrencySystemKey(systemKey);
  return wallet
    .filter((entry) => normalizeCurrencySystemKey(entry.unit.systemKey) === key)
    .reduce((total, entry) => total + entry.amount * (currencyUnitsForSystem(key).find((unit) => unit.key === entry.unit.key.toLowerCase())?.value ?? 0), 0);
}

function walletTotalCoin(wallet: WalletBalance[]) {
  return walletTotalCurrency(wallet, 'calostrynn');
}

function formatProductPrice(product: Pick<MarketProduct, 'priceCoin' | 'currencySystemKey'>, quantity = 1) {
  return formatCurrencyValue(product.priceCoin * quantity, product.currencySystemKey);
}

function carriedQuantity(items: InventoryItem[], itemName: string) {
  return items
    .filter((item) => !item.loadoutSlot && !item.isStorage && item.name.toLowerCase() === itemName.toLowerCase())
    .reduce((total, item) => total + item.quantity, 0);
}

function recipeLaborCost(service: ForgeService, shopper: Character | null, recipe: CraftRecipe) {
  if (service === 'blacksmith' && isBlacksmithClass(shopper)) return 0;
  if (service === 'armory' && isArmorCladClass(shopper)) return 0;
  return recipe.laborCoin;
}

function buildMaterialPlan(recipe: CraftRecipe, materials: MarketProduct[], materialProductId: string, inventory: InventoryItem[], houseItems: InventoryItem[] = []) {
  if (recipe.materialQuantity <= 0) {
    return { product: null, required: 0, carried: 0, missing: 0, buyQuantity: 0, leftover: 0, materialCost: 0, canCover: true, reason: '' };
  }

  const product = recipe.materialName
    ? materialProductByName(materials, recipe.materialName)
    : materials.find((entry) => entry.id === materialProductId) ?? null;

  if (!product) {
    return { product: null, required: recipe.materialQuantity, carried: 0, missing: recipe.materialQuantity, buyQuantity: 0, leftover: 0, materialCost: 0, canCover: false, reason: 'Choose a material scale.' };
  }

  const carried = Math.min(recipe.materialQuantity, carriedQuantity([...inventory, ...houseItems], product.name));
  const missing = Math.max(0, recipe.materialQuantity - carried);
  const buyQuantity = missing > 0 ? Math.ceil(missing) : 0;
  const leftover = Math.max(0, buyQuantity - missing);
  const canBuyMissing = missing <= 0 || hasUsableStock(product, buyQuantity);
  const reason = canBuyMissing ? '' : unavailableReason(product) || 'Not enough shop material.';

  return {
    product,
    required: recipe.materialQuantity,
    carried,
    missing,
    buyQuantity,
    leftover,
    materialCost: product.priceCoin * buyQuantity,
    canCover: canBuyMissing,
    reason
  };
}

type MaterialPlan = ReturnType<typeof buildMaterialPlan>;

function MaterialRequirementCard({ plan }: { plan: MaterialPlan }) {
  const product = plan.product;
  if (!product) return null;

  return (
    <div className={`rounded-2xl border p-3 ${rarityClass(product.rarity)}`}>
      <div className="flex items-start justify-between gap-3">
        <div className="flex min-w-0 items-start gap-2">
          <span className="text-[var(--brass)]"><ItemIcon type={product.type} /></span>
          <div className="min-w-0">
            <p className="font-black">{product.name}</p>
            <p className="mt-1 text-xs text-[var(--muted)]">{product.type} - {product.rarity}</p>
            {product.description && <p className="mt-2 text-xs text-[var(--muted)]">{product.description}</p>}
          </div>
        </div>
        <div className="shrink-0 text-right text-xs font-black text-[var(--brass)]">
          <p>{formatProductPrice(product)} each</p>
          <p className="mt-1 text-[var(--muted)]">stock {product.stockQuantity ?? 'unlimited'}</p>
        </div>
      </div>
    </div>
  );
}

function breweryRequirements(strength: string) {
  if (strength === 'Greater') return { property: 25, stabilizer: 10 };
  if (strength === 'Greatest') return { property: 50, stabilizer: 25 };
  return { property: 10, stabilizer: 3 };
}

function breweryItemKey(item: BreweryAvailableItem) {
  return `${item.source}:${item.id}`;
}

function sourceLabel(source: BreweryAvailableItem['source']) {
  return source === 'house' ? 'House' : 'Inventory';
}

function selectedTotal(selections: Record<string, number>) {
  return Object.values(selections).reduce((total, quantity) => total + Math.max(0, quantity || 0), 0);
}

function selectedBreweryItems(items: BreweryAvailableItem[], selections: Record<string, number>) {
  return items
    .map((item) => ({ item, quantity: Math.min(item.quantity, Math.max(0, selections[breweryItemKey(item)] || 0)) }))
    .filter((entry) => entry.quantity > 0);
}

function breweryPotionRarity(strength: string, propertyKey?: string): ItemRarity {
  const normalizedProperty = propertyKey?.trim().toLowerCase();
  if (normalizedProperty === 'luck' && (strength === 'Lesser' || strength === 'Greater')) return 'Legendary';
  if (normalizedProperty === 'luck' && strength === 'Greatest') return 'Mythical';
  if (strength === 'Greatest') return 'Legendary';
  if (strength === 'Greater') return 'Rare';
  if (strength === 'Lesser') return 'Uncommon';
  return 'Common';
}

function selectionsToPayload(selections: Record<string, number>) {
  return Object.entries(selections)
    .map(([key, quantity]) => {
      const [source, id] = key.split(':');
      return { source, id, quantity: Math.max(0, quantity || 0) };
    })
    .filter((entry) => entry.id && entry.quantity > 0);
}

function selectionFromKey(key: string) {
  const [source, id] = key.split(':');
  return source && id ? { source, id } : null;
}

function eligibleBlacksmithEnhancementTargets(items: InventoryItem[]) {
  return items.filter((item) => {
    return !item.enchantment
      && item.enhancementCount < 3
      && item.type !== 'armor'
      && itemCanBeEnhanced(item);
  });
}

function eligibleArmoryEnhancementTargets(items: InventoryItem[]) {
  return items.filter((item) => {
    return !item.enchantment
      && item.enhancementCount < 3
      && item.type === 'armor'
      && itemCanBeEnhanced(item);
  });
}

function eligibleEnchantmentTargets(items: InventoryItem[]) {
  return items.filter((item) => {
    return !item.enchantment
      && item.enhancementCount <= 0
      && itemCanBeEnchanted(item);
  });
}

function eligibleRuneItems(items: InventoryItem[]) {
  return items.filter((item) => item.type === 'rune' && FORGE_RUNE_NAMES.some((name) => name.toLowerCase() === item.name.toLowerCase()));
}

function enchantmentMinimumRunes(shopper: Character | null) {
  return isTalismanistClass(shopper) ? 3 : 5;
}

function normalizedRuneQuantity(mode: 'enhance' | 'enchant', shopper: Character | null, quantity: number) {
  if (mode !== 'enchant') return 1;
  return Math.max(enchantmentMinimumRunes(shopper), Math.floor(quantity || enchantmentMinimumRunes(shopper)));
}

function isDragonScaleFragmentName(name: string) {
  const clean = name.toLowerCase();
  return clean.includes('dragon')
    && clean.includes('scales')
    && !clean.includes('dragonscale scale');
}

function sourceItemKey(entry: CraftSourceItem) {
  return `${entry.source}:${entry.item.id}`;
}

function contributionSourceKey(entry: ContributionSourceItem) {
  return `${entry.source}:${entry.item.id}`;
}

function formatQuantity(value: number) {
  return Number.isInteger(value) ? String(value) : value.toFixed(1);
}

function dragonScaleOutputQuantity(total: number) {
  return Math.floor(total / 25);
}

function dragonScaleConsumedQuantity(total: number) {
  return dragonScaleOutputQuantity(total) * 25;
}

function dragonScaleReturnedQuantity(total: number) {
  return Math.max(0, total - dragonScaleConsumedQuantity(total));
}

export function CitiesPanel({ profile }: { profile: Profile }) {
  const [payload, setPayload] = useState<CitiesPayload>(EMPTY_PAYLOAD);
  const [selectedCityKey, setSelectedCityKey] = useState('');
  const [cityDetailOpen, setCityDetailOpen] = useState(false);
  const [shoppingAs, setShoppingAs] = useState('');
  const [selectedVendorId, setSelectedVendorId] = useState('');
  const [editCity, setEditCity] = useState<City | null>(null);
  const [cityDraft, setCityDraft] = useState<CityDraft | null>(null);
  const [itemCatalog, setItemCatalog] = useState<ItemCatalogEntry[]>([]);
  const [projectDraft, setProjectDraft] = useState<ProjectDraft | null>(null);
  const [catalogPickerIndex, setCatalogPickerIndex] = useState<number | null>(null);
  const [catalogSearch, setCatalogSearch] = useState('');
  const [editProject, setEditProject] = useState<CityConstructionProject | null>(null);
  const [contributeProject, setContributeProject] = useState<CityConstructionProject | null>(null);
  const [contributionSources, setContributionSources] = useState<ContributionSourceItem[]>([]);
  const [contributionSelections, setContributionSelections] = useState<Record<string, number>>({});
  const [selectedProduct, setSelectedProduct] = useState<MarketProduct | null>(null);
  const [editProduct, setEditProduct] = useState<MarketProduct | null>(null);
  const [editVendor, setEditVendor] = useState<ShopVendor | null>(null);
  const [creatingVendor, setCreatingVendor] = useState(false);
  const [creatingProductForVendor, setCreatingProductForVendor] = useState<ShopVendor | null>(null);
  const [productDraft, setProductDraft] = useState<ProductDraft | null>(null);
  const [vendorDraft, setVendorDraft] = useState<VendorDraft | null>(null);
  const [productCatalogPickerOpen, setProductCatalogPickerOpen] = useState(false);
  const [managingVendorId, setManagingVendorId] = useState('');
  const [manageSection, setManageSection] = useState('');
  const [sectionDraftName, setSectionDraftName] = useState('');
  const [bulkProductPickerOpen, setBulkProductPickerOpen] = useState(false);
  const [bulkCatalogKeys, setBulkCatalogKeys] = useState<string[]>([]);
  const [quantity, setQuantity] = useState(1);
  const [researchType, setResearchType] = useState(MAGICAL_RESEARCH_TYPES[0]);
  const [craftModal, setCraftModal] = useState<CraftModalState | null>(null);
  const [craftInventory, setCraftInventory] = useState<InventoryItem[]>([]);
  const [craftHouseItems, setCraftHouseItems] = useState<InventoryItem[]>([]);
  const [craftWallet, setCraftWallet] = useState<WalletBalance[]>([]);
  const [craftMaterialProductId, setCraftMaterialProductId] = useState('');
  const [craftRuneItemKey, setCraftRuneItemKey] = useState('');
  const [craftRuneQuantity, setCraftRuneQuantity] = useState(5);
  const [craftTargetItemId, setCraftTargetItemId] = useState('');
  const [craftModifier, setCraftModifier] = useState('strength');
  const [craftRefreshSignal, setCraftRefreshSignal] = useState(0);
  const [craftConfirmOpen, setCraftConfirmOpen] = useState(false);
  const [craftTargetPickerOpen, setCraftTargetPickerOpen] = useState(false);
  const [craftRunePickerOpen, setCraftRunePickerOpen] = useState(false);
  const [craftStatPickerOpen, setCraftStatPickerOpen] = useState(false);
  const [dragonScalePickerOpen, setDragonScalePickerOpen] = useState(false);
  const [dragonScaleSelections, setDragonScaleSelections] = useState<Record<string, number>>({});
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const isDm = profile.role === 'dm';

  const visibleCities = useMemo(() => [...payload.cities].sort((a, b) => a.order - b.order || a.name.localeCompare(b.name)), [payload.cities]);
  const currentResidenceCity = visibleCities.find((city) => city.currentResidence) ?? null;
  const selectedCity = visibleCities.find((city) => city.key === selectedCityKey) ?? visibleCities[0] ?? null;
  const shoppers = useMemo(() => payload.characters.filter((character) => isDm || character.ownerUserId === profile.id), [isDm, payload.characters, profile.id]);
  const selectedShopper = shoppers.find((character) => character.id === shoppingAs) ?? null;
  const selectedVendor = payload.vendors.find((vendor) => vendor.id === selectedVendorId && vendor.cityKey === selectedCity?.key && activeCityVendor(vendor)) ?? null;
  const managingVendor = payload.vendors.find((vendor) => vendor.id === managingVendorId && vendor.cityKey === selectedCity?.key && activeCityVendor(vendor)) ?? null;
  const cityLocked = Boolean(selectedCity?.locked);
  const shopperInCity = sameCityName(selectedShopper?.locationName, selectedCity?.name);
  const canShop = Boolean(selectedShopper && selectedCity && !cityLocked && shopperInCity);
  const cityProjects = useMemo(() => payload.constructionProjects
    .filter((project) => project.cityKey === selectedCity?.key && project.status === 'active')
    .sort((a, b) => a.order - b.order || a.name.localeCompare(b.name)), [payload.constructionProjects, selectedCity?.key]);
  const canContribute = Boolean(selectedShopper && selectedCity && selectedCity.showUnderConstruction && !cityLocked && shopperInCity);
  const constructionCatalogItems = useMemo(() => itemCatalog
    .filter((item) => item.type !== 'pet' && item.type !== 'storage')
    .sort((a, b) => a.name.localeCompare(b.name)), [itemCatalog]);
  const filteredConstructionCatalog = useMemo(() => {
    const query = catalogSearch.trim().toLowerCase();
    if (!query) return constructionCatalogItems;
    return constructionCatalogItems.filter((item) => [
      item.name,
      item.type,
      item.rarity,
      item.category,
      item.notes,
      item.properties.join(' ')
    ].join(' ').toLowerCase().includes(query));
  }, [catalogSearch, constructionCatalogItems]);
  const filteredProductCatalog = useMemo(() => {
    const source = [...itemCatalog].sort((a, b) => a.name.localeCompare(b.name));
    const query = catalogSearch.trim().toLowerCase();
    if (!query) return source;
    return source.filter((item) => [
      item.name,
      item.type,
      item.rarity,
      item.category,
      item.notes,
      item.properties.join(' ')
    ].join(' ').toLowerCase().includes(query));
  }, [catalogSearch, itemCatalog]);
  const blacksmithMaterials = useMemo(() => forgeMaterialProducts(payload.vendors, 'blacksmith'), [payload.vendors]);
  const armoryMaterials = useMemo(() => forgeMaterialProducts(payload.vendors, 'armory'), [payload.vendors]);
  const craftMaterials = craftModal?.service === 'armory' ? armoryMaterials : blacksmithMaterials;
  const dragonScaleItems = useMemo<CraftSourceItem[]>(() => [
    ...craftInventory.filter((item) => isDragonScaleFragmentName(item.name)).map((item) => ({ source: 'inventory' as const, item })),
    ...craftHouseItems.filter((item) => isDragonScaleFragmentName(item.name)).map((item) => ({ source: 'house' as const, item }))
  ], [craftHouseItems, craftInventory]);
  const craftRuneItems = useMemo<CraftSourceItem[]>(() => [
    ...eligibleRuneItems(craftInventory).map((item) => ({ source: 'inventory' as const, item })),
    ...eligibleRuneItems(craftHouseItems).map((item) => ({ source: 'house' as const, item }))
  ], [craftHouseItems, craftInventory]);
  const selectedCraftRuneItem = craftRuneItems.find((entry) => sourceItemKey(entry) === craftRuneItemKey) ?? null;
  const craftTargetItems = useMemo(() => {
    if (!craftModal) return [];
    if (craftModal.mode === 'enhance') {
      return craftModal.service === 'armory'
        ? eligibleArmoryEnhancementTargets(craftInventory)
        : eligibleBlacksmithEnhancementTargets(craftInventory);
    }
    if (craftModal.mode === 'enchant') return eligibleEnchantmentTargets(craftInventory);
    return [];
  }, [craftInventory, craftModal]);
  const selectedDragonScaleItems = useMemo(() => dragonScaleItems
    .map((entry) => ({ ...entry, quantity: Math.max(0, dragonScaleSelections[sourceItemKey(entry)] ?? 0) }))
    .filter((entry) => entry.quantity > 0), [dragonScaleItems, dragonScaleSelections]);
  const selectedDragonScaleTotal = selectedDragonScaleItems.reduce((total, entry) => total + entry.quantity, 0);
  const selectedDragonScaleOutput = dragonScaleOutputQuantity(selectedDragonScaleTotal);
  const selectedDragonScaleConsumed = dragonScaleConsumedQuantity(selectedDragonScaleTotal);
  const selectedDragonScaleReturned = dragonScaleReturnedQuantity(selectedDragonScaleTotal);
  const canConfirmForge = (() => {
    if (!craftModal || !selectedVendor || !selectedShopper || !canShop) return false;
    if (craftModal.mode === 'craft') {
      const walletCoin = walletTotalCoin(craftWallet);
      const plan = buildMaterialPlan(craftModal.recipe, craftMaterials, craftMaterialProductId, craftInventory, craftHouseItems);
      const totalCost = plan.materialCost + recipeLaborCost(craftModal.service, selectedShopper, craftModal.recipe);
      return plan.canCover && walletCoin >= totalCost;
    }
    if (craftModal.mode === 'dragon-scales') return selectedDragonScaleTotal >= 25;

    if (!craftTargetItemId || !craftTargetItems.some((item) => item.id === craftTargetItemId)) return false;
    if (!selectedCraftRuneItem) return false;
    const requiredRunes = normalizedRuneQuantity(craftModal.mode, selectedShopper, craftRuneQuantity);
    if (selectedCraftRuneItem.item.quantity < requiredRunes) return false;
    if (craftModal.mode === 'enhance' && !craftModifier) return false;
    return true;
  })();
  const manageSections = managingVendor ? sectionNamesForVendor(managingVendor, manageSection) : [];
  const activeManageSection = manageSections.includes(manageSection) ? manageSection : manageSections[0] ?? 'Wares';
  const manageSectionProducts = managingVendor
    ? managingVendor.products.filter((product) => productSection(product) === activeManageSection)
    : [];
  const selectedBulkCatalogItems = itemCatalog.filter((item) => bulkCatalogKeys.includes(item.key));

  const cityVendors = useMemo(() => payload.vendors
    .filter((vendor) => vendor.cityKey === selectedCity?.key)
    .filter(activeCityVendor)
    .filter((vendor) => isDm || !vendor.hidden)
    .sort((a, b) => a.order - b.order || a.name.localeCompare(b.name)), [selectedCity?.key, isDm, payload.vendors]);

  const loadCities = useCallback(async (showLoading = true) => {
    if (showLoading) setLoading(true);
    setError('');
    try {
      const response = await fetch('/api/cities', { cache: 'no-store' });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(body.error ?? 'Discovered cities could not be loaded.');
      const normalized = normalizeCitiesPayload(body);
      const orderedCities = [...normalized.cities].sort((a, b) => a.order - b.order || a.name.localeCompare(b.name));
      setPayload(normalized);
      setShoppingAs((current) => current || normalized.characters.find((character) => isDm || character.ownerUserId === profile.id)?.id || '');
      setSelectedCityKey((current) => current || orderedCities[0]?.key || '');
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : 'Discovered cities could not be loaded.');
    } finally {
      if (showLoading) setLoading(false);
    }
  }, [isDm, profile.id]);

  useLiveRefresh(['cities', 'inventory', 'house', 'characters', 'spells'], () => {
    void loadCities(false);
    setCraftRefreshSignal((current) => current + 1);
  });

  useEffect(() => {
    void loadCities();
  }, [loadCities]);

  useEffect(() => {
    if (!isDm) return;
    let active = true;
    fetch('/api/assets', { cache: 'no-store' })
      .then((response) => response.json())
      .then((body) => {
        if (!active) return;
        setItemCatalog(normalizeUpdateAssetsPayload(body).itemCatalog.filter((item) => item.active));
      })
      .catch(() => {
        if (active) setItemCatalog([]);
      });
    return () => {
      active = false;
    };
  }, [isDm]);

  useEffect(() => {
    if (!craftModal || !selectedShopper || !selectedCity || !canShop) {
      setCraftInventory([]);
      setCraftHouseItems([]);
      setCraftWallet([]);
      return;
    }
    let active = true;
    Promise.all([
      fetch(`/api/characters/${selectedShopper.id}/inventory`, { cache: 'no-store' }).then((response) => response.json()),
      selectedShopper.ownerUserId
        ? fetch(`/api/houses/${selectedShopper.ownerUserId}`, { cache: 'no-store' }).then((response) => response.json()).catch(() => null)
        : Promise.resolve(null)
    ])
      .then(([body, houseBody]) => {
        if (!active) return;
        const normalized = normalizeCharacterInventoryPayload(body);
        setCraftInventory(normalized.items);
        setCraftWallet(normalized.wallet);
        const house = normalizeHousePayload(houseBody);
        const houseAccessible = Boolean(house.house && !house.house.locked && sameCityName(house.house.cityName, selectedCity.name));
        setCraftHouseItems(houseAccessible ? house.items : []);
      })
      .catch(() => {
        if (active) {
          setCraftInventory([]);
          setCraftHouseItems([]);
          setCraftWallet([]);
        }
      });
    return () => {
      active = false;
    };
  }, [canShop, craftModal, craftRefreshSignal, selectedCity, selectedShopper]);

  useEffect(() => {
    if (!contributeProject || !selectedShopper || !selectedCity || !canContribute) {
      setContributionSources([]);
      setContributionSelections({});
      return;
    }
    let active = true;
    Promise.all([
      fetch(`/api/characters/${selectedShopper.id}/inventory`, { cache: 'no-store' }).then((response) => response.json()),
      selectedShopper.ownerUserId
        ? fetch(`/api/houses/${selectedShopper.ownerUserId}`, { cache: 'no-store' }).then((response) => response.json()).catch(() => null)
        : Promise.resolve(null),
      fetch(`/api/characters/${selectedShopper.id}/wagons`, { cache: 'no-store' }).then((response) => response.json()).catch(() => null)
    ])
      .then(([inventoryBody, houseBody, wagonBody]) => {
        if (!active) return;
        const requirementKeys = new Set(contributeProject.requirements
          .filter((requirement) => !requirement.complete)
          .map((requirement) => requirement.item.key));
        const inventory = normalizeCharacterInventoryPayload(inventoryBody).items
          .filter((item) => item.loadoutSlot === null && !item.isStorage && item.type !== 'pet' && requirementKeys.has(catalogKeyForName(item.name)))
          .map((item) => ({ source: 'inventory' as const, sourceLabel: 'Inventory', item }));
        const house = normalizeHousePayload(houseBody);
        const houseItems = house.house && sameCityName(house.house.cityName, selectedCity.name) && (house.access.owner || house.access.dm || house.access.house)
          ? house.items
            .filter((item) => item.loadoutSlot === null && !item.isStorage && item.type !== 'pet' && requirementKeys.has(catalogKeyForName(item.name)))
            .map((item) => ({ source: 'home' as const, sourceLabel: house.house?.kind === 'wagon-home' ? 'Wagon Home' : 'Home Storage', item }))
          : [];
        const wagons = normalizeWagonPayload(wagonBody);
        const wagonItems = wagons.items
          .filter((item) => item.loadoutSlot === null && !item.isStorage && item.type !== 'pet' && requirementKeys.has(catalogKeyForName(item.name)))
          .map((item) => {
            const wagon = wagons.wagons.find((entry) => entry.wagon.id === item.parentItemId);
            return { source: 'wagon' as const, sourceLabel: wagon ? `${wagon.ownerName}'s ${wagon.wagon.displayName || wagon.wagon.name}` : 'Shared Wagon', item };
          });
        setContributionSources([...inventory, ...houseItems, ...wagonItems]);
      })
      .catch(() => {
        if (active) setContributionSources([]);
      });
    return () => {
      active = false;
    };
  }, [canContribute, contributeProject, selectedCity, selectedShopper]);

  async function replaceFromResponse(response: Response, fallback: string) {
    const body = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(body.error ?? fallback);
    const normalized = normalizeCitiesPayload(body);
    setPayload(normalized);
    if (selectedVendorId && !normalized.vendors.some((vendor) => vendor.id === selectedVendorId && activeCityVendor(vendor))) setSelectedVendorId('');
  }

  async function toggleCityLock() {
    if (!isDm || !selectedCity) return;
    setSaving(true);
    setError('');
    try {
      await replaceFromResponse(await fetch(`/api/cities/${selectedCity.key}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ locked: !selectedCity.locked })
      }), 'City access could not be changed.');
    } catch (lockError) {
      setError(lockError instanceof Error ? lockError.message : 'City access could not be changed.');
    } finally {
      setSaving(false);
    }
  }

  function openCityEdit(city: City) {
    setEditCity(city);
    setCityDraft({
      name: city.name,
      description: city.description,
      primaryColor: city.primaryColor,
      secondaryColor: city.secondaryColor,
      accentColor: city.accentColor,
      locked: city.locked,
      currentResidence: city.currentResidence,
      showUnderConstruction: city.showUnderConstruction,
      order: city.order
    });
  }

  async function saveCity(event: FormEvent) {
    event.preventDefault();
    if (!editCity || !cityDraft || !isDm) return;
    setSaving(true);
    setError('');
    try {
      await replaceFromResponse(await fetch(`/api/cities/${editCity.key}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(cityDraft)
      }), 'City settings could not be saved.');
      setEditCity(null);
      setCityDraft(null);
    } catch (saveError) {
      setError(saveError instanceof Error ? saveError.message : 'City settings could not be saved.');
    } finally {
      setSaving(false);
    }
  }

  function openProjectCreate(city: City) {
    setSelectedCityKey(city.key);
    setProjectDraft({ name: '', requirements: [{ itemCatalogId: '', quantity: 1 }] });
    setEditProject(null);
  }

  function openProjectEdit(project: CityConstructionProject) {
    setEditProject(project);
    setProjectDraft({
      name: project.name,
      requirements: project.requirements.map((requirement) => ({
        itemCatalogId: requirement.item.id,
        quantity: requirement.requiredQuantity
      }))
    });
  }

  async function saveProject(event: FormEvent) {
    event.preventDefault();
    if (!selectedCity || !projectDraft || !isDm) return;
    const requirements = projectDraft.requirements.filter((requirement) => requirement.itemCatalogId && requirement.quantity > 0);
    if (!projectDraft.name.trim() || requirements.length === 0) return;
    setSaving(true);
    setError('');
    try {
      const response = editProject
        ? await fetch(`/api/cities/construction/${editProject.id}`, {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ name: projectDraft.name, requirements })
        })
        : await fetch('/api/cities/construction', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ cityKey: selectedCity.key, name: projectDraft.name, requirements })
        });
      await replaceFromResponse(response, 'Construction project could not be saved.');
      setProjectDraft(null);
      setEditProject(null);
    } catch (saveError) {
      setError(saveError instanceof Error ? saveError.message : 'Construction project could not be saved.');
    } finally {
      setSaving(false);
    }
  }

  async function endProject(project: CityConstructionProject) {
    if (!isDm) return;
    setSaving(true);
    setError('');
    try {
      await replaceFromResponse(await fetch(`/api/cities/construction/${project.id}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ status: 'ended' })
      }), 'Construction project could not be ended.');
    } catch (saveError) {
      setError(saveError instanceof Error ? saveError.message : 'Construction project could not be ended.');
    } finally {
      setSaving(false);
    }
  }

  async function submitContribution() {
    if (!contributeProject || !selectedShopper) return;
    const contributions = contributionSources
      .map((entry) => {
        const quantity = contributionSelections[contributionSourceKey(entry)] ?? 0;
        const requirement = contributeProject.requirements.find((candidate) => candidate.item.key === catalogKeyForName(entry.item.name) && !candidate.complete);
        return requirement && quantity > 0 ? { requirementId: requirement.id, itemId: entry.item.id, quantity } : null;
      })
      .filter((entry): entry is { requirementId: string; itemId: string; quantity: number } => Boolean(entry));
    if (contributions.length === 0) return;
    setSaving(true);
    setError('');
    try {
      await replaceFromResponse(await fetch(`/api/cities/construction/${contributeProject.id}/contribute`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ characterId: selectedShopper.id, contributions })
      }), 'Construction contribution could not be completed.');
      setContributeProject(null);
      setContributionSelections({});
    } catch (saveError) {
      setError(saveError instanceof Error ? saveError.message : 'Construction contribution could not be completed.');
    } finally {
      setSaving(false);
    }
  }

  async function patchProduct(product: MarketProduct, patch: Partial<ProductDraft>, fallback = 'Shop stock could not be changed.') {
    if (!isDm) return false;
    setSaving(true);
    setError('');
    try {
      await replaceFromResponse(await fetch(`/api/cities/products/${product.id}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(patch)
      }), fallback);
      return true;
    } catch (saveError) {
      setError(saveError instanceof Error ? saveError.message : fallback);
      return false;
    } finally {
      setSaving(false);
    }
  }

  async function patchVendor(vendor: ShopVendor, patch: Partial<VendorDraft>, fallback = 'Shop details could not be changed.') {
    if (!isDm) return false;
    setSaving(true);
    setError('');
    try {
      await replaceFromResponse(await fetch(`/api/cities/vendors/${vendor.id}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(patch)
      }), fallback);
      return true;
    } catch (saveError) {
      setError(saveError instanceof Error ? saveError.message : fallback);
      return false;
    } finally {
      setSaving(false);
    }
  }

  async function deleteProduct(product: MarketProduct) {
    if (!isDm) return;
    if (!window.confirm(`Delete ${product.name} from this shop?`)) return;
    setSaving(true);
    setError('');
    try {
      await replaceFromResponse(await fetch(`/api/cities/products/${product.id}`, { method: 'DELETE' }), 'Shop item could not be deleted.');
    } catch (deleteError) {
      setError(deleteError instanceof Error ? deleteError.message : 'Shop item could not be deleted.');
    } finally {
      setSaving(false);
    }
  }

  async function deleteSection(vendor: ShopVendor, section: string) {
    if (!isDm) return;
    const productsInSection = vendor.products.filter((product) => productSection(product) === section).length;
    if (!window.confirm(productsInSection > 0
      ? `Delete the ${section} section and its ${productsInSection} product${productsInSection === 1 ? '' : 's'}?`
      : `Remove the empty ${section} section from this workspace?`)) return;
    if (productsInSection === 0) {
      setManageSection('');
      return;
    }
    setSaving(true);
    setError('');
    try {
      await replaceFromResponse(await fetch(`/api/cities/vendors/${vendor.id}/sections?section=${encodeURIComponent(section)}`, { method: 'DELETE' }), 'Shop section could not be deleted.');
      setManageSection('');
    } catch (deleteError) {
      setError(deleteError instanceof Error ? deleteError.message : 'Shop section could not be deleted.');
    } finally {
      setSaving(false);
    }
  }

  async function deleteVendor(vendor: ShopVendor) {
    if (!isDm) return;
    if (!window.confirm(`Delete ${vendor.name} and every product inside it?`)) return;
    setSaving(true);
    setError('');
    try {
      await replaceFromResponse(await fetch(`/api/cities/vendors/${vendor.id}`, { method: 'DELETE' }), 'Shop could not be deleted.');
      setSelectedVendorId('');
      setManagingVendorId('');
      setManageSection('');
    } catch (deleteError) {
      setError(deleteError instanceof Error ? deleteError.message : 'Shop could not be deleted.');
    } finally {
      setSaving(false);
    }
  }

  async function addCatalogProductsToSection(vendor: ShopVendor, section: string) {
    if (!isDm || !selectedCity || bulkCatalogKeys.length === 0) return;
    const selectedItems = itemCatalog.filter((item) => bulkCatalogKeys.includes(item.key));
    if (selectedItems.length === 0) return;
    setSaving(true);
    setError('');
    try {
      let latestPayload: CitiesPayload | null = null;
      for (const item of selectedItems) {
        const response = await fetch('/api/cities/products', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ ...productDraftFromCatalogItem(vendor, selectedCity, section, item), vendorId: vendor.id })
        });
        const body = await response.json().catch(() => ({}));
        if (!response.ok) throw new Error(body.error ?? 'Shop items could not be added.');
        latestPayload = normalizeCitiesPayload(body);
      }
      if (latestPayload) setPayload(latestPayload);
      setBulkCatalogKeys([]);
      setBulkProductPickerOpen(false);
      setCatalogSearch('');
      setManageSection(section);
    } catch (createError) {
      setError(createError instanceof Error ? createError.message : 'Shop items could not be added.');
    } finally {
      setSaving(false);
    }
  }

  async function moveVendor(vendor: ShopVendor, direction: -1 | 1) {
    const currentIndex = cityVendors.findIndex((entry) => entry.id === vendor.id);
    const swapWith = cityVendors[currentIndex + direction];
    if (!swapWith) return;
    setSaving(true);
    setError('');
    try {
      await replaceFromResponse(await fetch(`/api/cities/vendors/${vendor.id}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ order: swapWith.order })
      }), 'Shop order could not be changed.');
      await replaceFromResponse(await fetch(`/api/cities/vendors/${swapWith.id}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ order: vendor.order })
      }), 'Shop order could not be changed.');
    } catch (moveError) {
      setError(moveError instanceof Error ? moveError.message : 'Shop order could not be changed.');
    } finally {
      setSaving(false);
    }
  }

  async function buyProduct() {
    if (!selectedProduct || !selectedShopper) return;
    setSaving(true);
    setError('');
    try {
      const purchaseQuantity = isSinglePurchaseProduct(selectedProduct) ? 1 : quantity;
      const purchaseOption = isMagicalResearchProduct(selectedProduct) ? researchType : null;
      await replaceFromResponse(await fetch('/api/cities/purchase', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ productId: selectedProduct.id, characterId: selectedShopper.id, quantity: purchaseQuantity, purchaseOption })
      }), 'Purchase failed.');
      setSelectedProduct(null);
      setQuantity(1);
    } catch (buyError) {
      setError(buyError instanceof Error ? buyError.message : 'Purchase failed.');
    } finally {
      setSaving(false);
    }
  }

  async function runForgeAction() {
    if (!selectedShopper || !craftModal) return;
    setSaving(true);
    setError('');
    try {
      const body = craftModal.mode === 'craft'
        ? {
            action: 'craft',
            characterId: selectedShopper.id,
            recipeKey: craftModal.recipe.key,
            materialProductId: craftMaterialProductId || null,
            vendorKey: selectedVendor?.key ?? null
          }
        : craftModal.mode === 'dragon-scales'
          ? {
              action: 'dragon-scales',
              characterId: selectedShopper.id,
              vendorKey: selectedVendor?.key ?? null,
              dragonScaleSelections: selectedDragonScaleItems.map((entry) => ({
                source: entry.source,
                itemId: entry.item.id,
                quantity: entry.quantity
              }))
            }
        : {
            action: craftModal.mode,
            characterId: selectedShopper.id,
            targetItemId: craftTargetItemId || null,
            runeProductId: null,
            runeName: selectedCraftRuneItem?.item.name ?? null,
            modifierKey: craftModifier,
            vendorKey: selectedVendor?.key ?? null,
            runeQuantity: craftModal.mode === 'enchant'
              ? normalizedRuneQuantity(craftModal.mode, selectedShopper, craftRuneQuantity)
              : null
          };
      const endpoint = craftModal.mode !== 'enchant' && craftModal.service === 'armory'
        ? '/api/cities/armory/craft'
        : '/api/cities/blacksmith/craft';
      await replaceFromResponse(await fetch(endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body)
      }), craftModal.service === 'armory' ? 'Armory work failed.' : 'Blacksmith work failed.');
      setCraftModal(null);
      setCraftConfirmOpen(false);
      setCraftMaterialProductId('');
      setCraftRuneItemKey('');
      setCraftRuneQuantity(enchantmentMinimumRunes(selectedShopper));
      setCraftTargetItemId('');
      setCraftModifier('strength');
      setCraftTargetPickerOpen(false);
      setCraftRunePickerOpen(false);
      setCraftStatPickerOpen(false);
      setDragonScaleSelections({});
      setDragonScalePickerOpen(false);
    } catch (craftError) {
      setError(craftError instanceof Error ? craftError.message : 'Forge work failed.');
    } finally {
      setSaving(false);
    }
  }

  function openProductEdit(product: MarketProduct) {
    setEditProduct(product);
    setCreatingProductForVendor(null);
    setProductDraft(productToDraft(product));
  }

  function openVendorEdit(vendor: ShopVendor) {
    setEditVendor(vendor);
    setCreatingVendor(false);
    setVendorDraft(vendorToDraft(vendor));
  }

  function openVendorCreate() {
    setEditVendor(null);
    setCreatingVendor(true);
    setVendorDraft(defaultVendorDraft());
  }

  function openProductCreate(vendor: ShopVendor, section = '') {
    setEditProduct(null);
    setCreatingProductForVendor(vendor);
    const draft = defaultProductDraft(vendor, selectedCity);
    setProductDraft(section ? { ...draft, section } : draft);
  }

  async function saveProduct(event: FormEvent) {
    event.preventDefault();
    if (!productDraft) return;
    if (creatingProductForVendor) {
      setSaving(true);
      setError('');
      try {
        await replaceFromResponse(await fetch('/api/cities/products', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ ...productDraft, vendorId: creatingProductForVendor.id })
        }), 'Shop item could not be added.');
        setCreatingProductForVendor(null);
        setProductDraft(null);
      } catch (createError) {
        setError(createError instanceof Error ? createError.message : 'Shop item could not be added.');
      } finally {
        setSaving(false);
      }
      return;
    }
    if (editProduct) {
      const saved = await patchProduct(editProduct, productDraft);
      if (saved) {
        setEditProduct(null);
        setProductDraft(null);
      }
    }
  }

  async function saveVendor(event: FormEvent) {
    event.preventDefault();
    if (!vendorDraft || !selectedCity) return;
    if (creatingVendor) {
      setSaving(true);
      setError('');
      try {
        await replaceFromResponse(await fetch('/api/cities/vendors', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ ...vendorDraft, cityKey: selectedCity.key })
        }), 'Shop could not be created.');
        setCreatingVendor(false);
        setVendorDraft(null);
      } catch (createError) {
        setError(createError instanceof Error ? createError.message : 'Shop could not be created.');
      } finally {
        setSaving(false);
      }
      return;
    }
    if (editVendor) {
      const saved = await patchVendor(editVendor, vendorDraft);
      if (saved) {
        setEditVendor(null);
        setVendorDraft(null);
      }
    }
  }

  function openCraftModal(next: CraftModalState) {
    const materials = next.service === 'armory' ? armoryMaterials : blacksmithMaterials;
    const minimumRunes = next.mode === 'enchant' ? enchantmentMinimumRunes(selectedShopper) : 1;
    setCraftModal(next);
    setCraftMaterialProductId(next.mode === 'craft'
      ? (next.recipe.materialName ? materialProductByName(materials, next.recipe.materialName)?.id : materials[0]?.id) ?? ''
      : '');
    setCraftRuneItemKey('');
    setCraftRuneQuantity(minimumRunes);
    setCraftTargetItemId('');
    setCraftModifier('strength');
    setCraftConfirmOpen(false);
    setCraftTargetPickerOpen(false);
    setCraftRunePickerOpen(false);
    setCraftStatPickerOpen(false);
    setDragonScalePickerOpen(false);
    setDragonScaleSelections({});
  }

  function craftConfirmation() {
    if (!craftModal || !selectedShopper) return null;
    if (craftModal.mode === 'dragon-scales') {
      return {
        title: 'Forge Dragonscale Scale',
        inputs: selectedDragonScaleItems.map((entry) => ({
          key: sourceItemKey(entry),
          name: entry.item.displayName || entry.item.name,
          type: entry.item.type,
          rarity: entry.item.rarity,
          quantity: entry.quantity,
          note: entry.source === 'house' ? 'House storage' : 'Inventory'
        })),
        output: {
          name: 'Dragonscale Scale',
          type: 'material' as ItemType,
          rarity: 'Legendary' as ItemRarity,
          quantity: selectedDragonScaleOutput,
          note: selectedDragonScaleReturned > 0
            ? `${formatQuantity(selectedDragonScaleConsumed)} fragments are consumed. ${formatQuantity(selectedDragonScaleReturned)} extra fragment${selectedDragonScaleReturned === 1 ? '' : 's'} stay in storage.`
            : 'A refined forging scale for Dragonscale gear.'
        }
      };
    }
    if (craftModal.mode === 'craft') {
      const plan = buildMaterialPlan(craftModal.recipe, craftMaterials, craftMaterialProductId, craftInventory, craftHouseItems);
      const laborCost = recipeLaborCost(craftModal.service, selectedShopper, craftModal.recipe);
      const inputs = [
        ...(plan.product && craftModal.recipe.materialQuantity > 0 ? [{
          key: 'material',
          name: plan.product.name,
          type: plan.product.type,
          rarity: plan.product.rarity,
          quantity: craftModal.recipe.materialQuantity
        }] : []),
        ...(laborCost > 0 ? [{
          key: 'labor',
          name: 'Labor',
          type: 'currency' as ItemType,
          rarity: 'Common' as ItemRarity,
          quantity: formatCoinValue(laborCost)
        }] : [])
      ];
      return {
        title: `Craft ${craftModal.recipe.name}`,
        inputs,
        output: {
          name: craftModal.recipe.name,
          type: craftModal.recipe.type,
          rarity: plan.product?.rarity ?? 'Common' as ItemRarity,
          quantity: 1,
          note: craftModal.recipe.note || (craftModal.recipe.twoHanded ? 'Two-handed' : '')
        }
      };
    }

    const target = craftInventory.find((item) => item.id === craftTargetItemId) ?? null;
    const rune = selectedCraftRuneItem?.item ?? null;
    const requiredRunes = normalizedRuneQuantity(craftModal.mode, selectedShopper, craftRuneQuantity);
    return {
      title: craftModal.mode === 'enhance' ? `Enhance ${target?.displayName || target?.name || 'item'}` : `Enchant ${target?.displayName || target?.name || 'item'}`,
      inputs: [
        ...(target ? [{
          key: 'target',
          name: target.displayName || target.name,
          type: target.type,
          rarity: target.rarity,
          quantity: 1
        }] : []),
        ...(rune ? [{
          key: 'rune',
          name: rune.displayName || rune.name,
          type: rune.type,
          rarity: rune.rarity,
          quantity: requiredRunes,
          note: selectedCraftRuneItem?.source === 'house' ? 'House storage' : 'Inventory'
        }] : [])
      ],
      output: {
        name: target?.displayName || target?.name || 'Chosen item',
        type: target?.type ?? 'misc' as ItemType,
        rarity: target?.rarity ?? 'Common' as ItemRarity,
        quantity: 1,
        note: craftModal.mode === 'enhance'
          ? `Adds ${ENHANCEMENT_OPTIONS.find((option) => option.key === craftModifier)?.label ?? craftModifier}`
          : rune ? `Adds ${rune.name.replace(/\s+rune$/i, '')} enchantment` : 'Adds enchantment'
      }
    };
  }

  if (loading) {
    return <Card><div className="h-32 animate-pulse rounded-2xl bg-black/20" /></Card>;
  }

  const pageTitle = selectedVendor ? selectedVendor.name : cityDetailOpen ? (selectedCity?.name ?? 'City') : 'City Hub';
  const craftConfirm = craftConfirmation();

  return (
    <div className="space-y-4">
      <Card>
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <p className="eyebrow">Discovered Cities</p>
            <h2 className="mt-1 text-2xl font-black">{pageTitle}</h2>
            {!selectedVendor && !cityDetailOpen && currentResidenceCity && <p className="mt-1 text-sm font-bold text-[var(--muted)]">Current residence: {currentResidenceCity.name}</p>}
            {selectedVendor && <p className="mt-1 text-sm font-bold text-[var(--muted)]">{selectedVendor.facility} · {selectedVendor.npcName}</p>}
          </div>
          <div className="flex flex-wrap gap-2">
            {selectedVendor && <Button variant="secondary" onClick={() => setSelectedVendorId('')}><ArrowLeft className="mr-2 inline" size={15} /> Return to City</Button>}
            {isDm && selectedVendor && <Button variant="secondary" onClick={() => { setManagingVendorId(selectedVendor.id); setManageSection(sectionNamesForVendor(selectedVendor)[0] ?? 'Wares'); }} disabled={saving}><Settings className="mr-2 inline" size={15} /> Manage shop</Button>}
            {!selectedVendor && cityDetailOpen && <Button variant="secondary" onClick={() => setCityDetailOpen(false)}><ArrowLeft className="mr-2 inline" size={15} /> City Hub</Button>}
            <Button variant="secondary" className="p-3" onClick={() => void loadCities()} aria-label="Refresh cities"><RefreshCw size={16} /></Button>
            {isDm && !selectedVendor && selectedCity && <Button variant="secondary" onClick={() => openCityEdit(selectedCity)} disabled={saving}><Settings className="mr-2 inline" size={15} /> City Settings</Button>}
            {isDm && !selectedVendor && selectedCity && <Button variant={cityLocked ? 'danger' : 'teal'} onClick={toggleCityLock} disabled={saving}>{cityLocked ? <Lock className="mr-2 inline" size={15} /> : <Unlock className="mr-2 inline" size={15} />}{cityLocked ? 'Locked' : 'Open'}</Button>}
          </div>
        </div>
        {error && <div className="mt-3 rounded-2xl border border-[var(--red)]/40 bg-[var(--red)]/10 p-3 text-sm text-[var(--red)]">{error}</div>}
        {!selectedVendor && !cityDetailOpen && (
          <div className="mt-5 grid gap-4">
            {visibleCities.map((city) => {
              const active = city.key === selectedCity?.key;
              const vendorCount = payload.vendors.filter((vendor) => vendor.cityKey === city.key && activeCityVendor(vendor) && (isDm || !vendor.hidden)).length;
              const projectCount = payload.constructionProjects.filter((project) => project.cityKey === city.key && project.status === 'active').length;
              const cardStyle = {
                '--city-primary': city.primaryColor,
                '--city-secondary': city.secondaryColor,
                '--city-accent': city.accentColor,
                borderColor: active ? `${city.primaryColor}a8` : `${city.primaryColor}66`,
                boxShadow: active ? `0 0 0 1px ${city.primaryColor}34, 0 22px 52px ${city.primaryColor}18` : `0 16px 36px ${city.secondaryColor}12`
              } as CSSProperties;
              return (
                <button
                  key={city.key}
                  type="button"
                  onClick={() => {
                    setSelectedCityKey(city.key);
                    setSelectedVendorId('');
                    setCityDetailOpen(true);
                  }}
                  style={cardStyle}
                  className="group relative overflow-hidden rounded-2xl border bg-black/15 text-left transition hover:-translate-y-0.5 hover:shadow-[0_24px_60px_rgba(0,0,0,0.24)]"
                >
                  <span className="pointer-events-none absolute inset-0 opacity-95" style={{ background: `radial-gradient(circle at 10% -12%, ${city.primaryColor}42, transparent 38%), radial-gradient(circle at 100% 100%, ${city.accentColor}1f, transparent 34%), linear-gradient(135deg, ${city.primaryColor}36 0%, rgba(14,14,14,0.58) 52%, ${city.secondaryColor}2b 100%)` }} />
                  <span className="pointer-events-none absolute inset-x-5 top-0 h-px opacity-75" style={{ background: `linear-gradient(90deg, transparent, ${city.primaryColor}, ${city.secondaryColor}88, transparent)` }} />
                  <span className="relative block p-4 sm:p-5">
                    <span className="grid gap-4 lg:grid-cols-[1fr_minmax(16rem,28rem)] lg:items-stretch">
                      <span className="flex min-w-0 flex-col justify-between gap-5">
                        <span className="min-w-0">
                          <span className="flex flex-wrap items-center gap-2 text-[10px] font-black uppercase tracking-wider">
                            {city.currentResidence && <span className="inline-flex items-center gap-1 rounded-full border px-2 py-1" style={{ borderColor: `${city.primaryColor}aa`, backgroundColor: `${city.primaryColor}24`, color: city.primaryColor }}><Star size={12} fill="currentColor" /> Residence</span>}
                            <span className={`rounded-full border px-2 py-1 ${city.locked ? 'border-[var(--red)]/45 text-[var(--red)]' : 'border-[var(--teal)]/45 text-[var(--teal)]'}`}>{city.locked ? 'Locked' : 'Open'}</span>
                            {city.showUnderConstruction && <span className="rounded-full border border-[var(--line)] bg-black/25 px-2 py-1 text-[var(--muted)]">Building</span>}
                          </span>
                          <span className="mt-3 flex items-center gap-3">
                            <span className="block min-w-0 flex-1 break-words text-3xl font-black leading-tight sm:text-5xl">{city.name}</span>
                            <span className="grid h-10 w-10 shrink-0 place-items-center rounded-full border bg-black/20 transition group-hover:translate-x-0.5" style={{ borderColor: `${city.accentColor}78`, color: city.accentColor }}>
                              <ChevronRight size={21} />
                            </span>
                          </span>
                        </span>
                        <span className="flex flex-wrap gap-2 text-xs font-black uppercase tracking-wide">
                          <span className="rounded-xl border border-white/10 bg-black/25 px-3 py-2 text-[var(--paper)]">{vendorCount} service{vendorCount === 1 ? '' : 's'}</span>
                          {city.showUnderConstruction && <span className="rounded-xl border border-white/10 bg-black/25 px-3 py-2 text-[var(--paper)]">{projectCount} project{projectCount === 1 ? '' : 's'}</span>}
                        </span>
                      </span>
                      <span className="rounded-2xl border bg-black/30 p-4 backdrop-blur-sm" style={{ borderColor: `${city.primaryColor}55` }}>
                        <span className="eyebrow">City Notes</span>
                        <span className="mt-2 line-clamp-3 block min-h-[4.5rem] text-sm font-bold leading-6 text-[var(--muted)]">{city.description || 'No city notes yet.'}</span>
                      </span>
                    </span>
                  </span>
                </button>
              );
            })}
          </div>
        )}
        {(cityDetailOpen || selectedVendor) && <div className="mt-4 grid gap-3 md:grid-cols-[18rem_1fr]">
          <label>
            <span className="mb-1 block text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">Shopping as</span>
            <SelectField value={shoppingAs} onChange={(event) => setShoppingAs(event.target.value)}>
              <option value="">Choose character</option>
              {shoppers.map((character) => <option key={character.id} value={character.id}>{character.name}</option>)}
            </SelectField>
          </label>
          <div className="rounded-2xl border border-[var(--line)] bg-black/10 p-3 text-sm text-[var(--muted)]">
            {!selectedShopper ? 'Choose who is shopping.' : cityLocked ? `${selectedCity?.name ?? 'This city'} is locked by the DM.` : !shopperInCity ? `${selectedShopper.name} is in ${selectedShopper.locationName}, not ${selectedCity?.name ?? 'this city'}.` : `${selectedShopper.name} can shop here.`}
          </div>
        </div>}
      </Card>

      {!selectedCity ? (
        <Card><p className="text-sm text-[var(--muted)]">No cities have been discovered yet.</p></Card>
      ) : !cityDetailOpen && !selectedVendor ? null : !selectedVendor ? (
        <div className="space-y-4">
          <Card className="overflow-hidden">
            <div
              className="relative overflow-hidden rounded-2xl border px-4 py-9 text-center shadow-[0_0_42px_rgba(0,0,0,0.2)] sm:px-8 sm:py-12"
              style={{
                borderColor: `${selectedCity.accentColor}88`,
                background: `radial-gradient(circle at 50% -18%, ${selectedCity.accentColor}66, transparent 36%), radial-gradient(circle at 0% 80%, ${selectedCity.primaryColor}38, transparent 34%), linear-gradient(135deg, ${selectedCity.primaryColor}4d, rgba(14,14,14,0.9) 48%, ${selectedCity.secondaryColor}4a)`,
                boxShadow: `0 0 0 1px ${selectedCity.primaryColor}22, 0 24px 70px ${selectedCity.secondaryColor}20`
              }}
            >
              <div className="pointer-events-none absolute inset-x-8 top-5 h-px" style={{ background: `linear-gradient(90deg, transparent, ${selectedCity.primaryColor}, transparent)` }} />
              <div className="pointer-events-none absolute inset-x-16 bottom-5 h-px" style={{ background: `linear-gradient(90deg, transparent, ${selectedCity.secondaryColor}, transparent)` }} />
              <div className="mx-auto max-w-4xl">
                <p className="eyebrow justify-center">Discovered City</p>
                <h3 className="mt-3 break-words text-4xl font-black leading-tight sm:text-6xl">{selectedCity.name}</h3>
                <div className="mt-6 flex flex-wrap justify-center gap-2">
                  <span className={`rounded-xl border px-3 py-2 text-[10px] font-black uppercase tracking-wider ${selectedCity.locked ? 'border-[var(--red)]/45 bg-[var(--red)]/10 text-[var(--red)]' : 'border-[var(--teal)]/45 bg-[var(--teal)]/10 text-[var(--teal)]'}`}>{selectedCity.locked ? 'Locked' : 'Open'}</span>
                  {selectedCity.currentResidence && <span className="inline-flex items-center gap-2 rounded-xl border border-[var(--brass)]/55 bg-[var(--brass)]/15 px-3 py-2 text-[10px] font-black uppercase tracking-wider text-[var(--brass)]"><Star size={13} fill="currentColor" /> Residence</span>}
                  {selectedCity.showUnderConstruction && <span className="rounded-xl border border-[var(--line)] bg-black/20 px-3 py-2 text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">Construction Open</span>}
                </div>
              </div>
            </div>
          </Card>

          <section className="space-y-3">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <div className="min-w-[14rem] flex-1"><CitySectionHeading label="City Services" city={selectedCity} /></div>
              {isDm && <Button variant="secondary" className="px-3 py-2 text-xs" onClick={openVendorCreate} disabled={saving}><Plus className="mr-2 inline" size={13} /> Create shop</Button>}
            </div>
            {cityVendors.length === 0 ? (
              <Card><p className="text-sm font-bold text-[var(--muted)]">No services are available here yet.</p></Card>
            ) : (
              <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
                {cityVendors.map((vendor) => (
                  <ShopCard
                    key={vendor.id}
                    vendor={vendor}
                    isDm={isDm}
                    saving={saving}
                    index={cityVendors.findIndex((entry) => entry.id === vendor.id)}
                    total={cityVendors.length}
                    onOpen={() => setSelectedVendorId(vendor.id)}
                    onManage={() => {
                      setManagingVendorId(vendor.id);
                      setManageSection(sectionNamesForVendor(vendor)[0] ?? 'Wares');
                    }}
                    onEdit={() => openVendorEdit(vendor)}
                    onDelete={() => void deleteVendor(vendor)}
                    onToggleVisibility={() => void patchVendor(vendor, { hidden: !vendor.hidden }, 'Shop visibility could not be changed.')}
                    onMove={(direction) => void moveVendor(vendor, direction)}
                  />
                ))}
              </div>
            )}
          </section>

          {selectedCity.showUnderConstruction && (
            <ConstructionSection
              city={selectedCity}
              projects={cityProjects}
              isDm={isDm}
              saving={saving}
              canContribute={canContribute}
              onCreate={() => openProjectCreate(selectedCity)}
              onEdit={openProjectEdit}
              onEnd={(project) => void endProject(project)}
              onContribute={setContributeProject}
            />
          )}
        </div>
      ) : isBlacksmithVendor(selectedVendor) ? (
        <BlacksmithPage
          vendor={selectedVendor}
          isDm={isDm}
          saving={saving}
          canShop={canShop}
          onSelectProduct={(product) => {
            setSelectedProduct(product);
            setQuantity(product.quantityStep || quantityStepForItem(product));
          }}
          onEditProduct={openProductEdit}
          onDeleteProduct={(product) => void deleteProduct(product)}
          onPatchProduct={(product, patch) => void patchProduct(product, patch, 'Item visibility could not be changed.')}
          onCraft={openCraftModal}
        />
      ) : isArmoryVendor(selectedVendor) ? (
        <ArmoryPage
          vendor={selectedVendor}
          sharedMaterials={armoryMaterials}
          isDm={isDm}
          saving={saving}
          canShop={canShop}
          onSelectProduct={(product) => {
            setSelectedProduct(product);
            setQuantity(product.quantityStep || quantityStepForItem(product));
          }}
          onEditProduct={openProductEdit}
          onDeleteProduct={(product) => void deleteProduct(product)}
          onPatchProduct={(product, patch) => void patchProduct(product, patch, 'Item visibility could not be changed.')}
          onCraft={openCraftModal}
        />
      ) : isBreweryVendor(selectedVendor) ? (
        <BreweryPage
          vendor={selectedVendor}
          shopper={selectedShopper}
          isDm={isDm}
          saving={saving}
          canShop={canShop}
          onSelectProduct={(product) => {
            setSelectedProduct(product);
            setQuantity(product.quantityStep || quantityStepForItem(product));
          }}
          onEditProduct={openProductEdit}
          onDeleteProduct={(product) => void deleteProduct(product)}
          onPatchProduct={(product, patch) => void patchProduct(product, patch, 'Item visibility could not be changed.')}
          onCitiesChanged={setPayload}
          liveRefreshSignal={craftRefreshSignal}
          setError={setError}
        />
      ) : isSpellVendor(selectedVendor) ? (
        <SpellShopPage
          vendor={selectedVendor}
          isDm={isDm}
          saving={saving}
          canShop={canShop}
          onSelectProduct={(product) => {
            setSelectedProduct(product);
            setQuantity(1);
          }}
          onEditProduct={openProductEdit}
          onDeleteProduct={(product) => void deleteProduct(product)}
          onPatchProduct={(product, patch) => void patchProduct(product, patch, 'Spell visibility could not be changed.')}
        />
      ) : isLibraryVendor(selectedVendor) ? (
        <LibraryPage
          vendor={selectedVendor}
          isDm={isDm}
          saving={saving}
          canShop={canShop}
          onSelectProduct={(product) => {
            setSelectedProduct(product);
            setQuantity(1);
            if (isMagicalResearchProduct(product)) setResearchType(MAGICAL_RESEARCH_TYPES[0]);
          }}
          onEditProduct={openProductEdit}
          onDeleteProduct={(product) => void deleteProduct(product)}
          onPatchProduct={(product, patch) => void patchProduct(product, patch, 'Library stock could not be changed.')}
        />
      ) : (
        <ShopPage
          vendor={selectedVendor}
          isDm={isDm}
          saving={saving}
          canShop={canShop}
          onSelectProduct={(product) => {
            setSelectedProduct(product);
            setQuantity(product.quantityStep || quantityStepForItem(product));
          }}
          onEditProduct={openProductEdit}
          onDeleteProduct={(product) => void deleteProduct(product)}
          onPatchProduct={(product, patch) => void patchProduct(product, patch, 'Item visibility could not be changed.')}
        />
      )}

      {selectedProduct && (
        <Modal title={selectedProduct.name} onClose={() => setSelectedProduct(null)}>
          <div className="space-y-4">
            <div className={`rounded-2xl border p-4 ${productCardClass(selectedProduct)}`}>
              <div className="flex items-center gap-3">
                <span className="text-[var(--brass)]"><ItemIcon type={selectedProduct.type} size={22} /></span>
                <div>
                  <p className="font-black">{isSpellProduct(selectedProduct) ? selectedProduct.section.replace(/\s+Spells$/i, '') : `${selectedProduct.rarity} ${selectedProduct.type}`}</p>
                  <p className="text-sm text-[var(--muted)]">{selectedProduct.description}</p>
                </div>
              </div>
              {productEffectText(selectedProduct) && (
                <div className="mt-3 rounded-xl border border-[var(--line)] bg-black/20 p-3 text-sm leading-6 text-[var(--paper)]">
                  <p className="text-[10px] font-black uppercase tracking-wider text-[var(--brass)]">{isSpellProduct(selectedProduct) ? 'Spell description' : 'Potion effect'}</p>
                  <p className="mt-1">{productEffectText(selectedProduct)}</p>
                </div>
              )}
              {selectedProduct.kind === 'document' && (
                <div className="mt-3 rounded-xl border border-[var(--line)] bg-black/20 p-3 text-sm leading-6 text-[var(--paper)]">
                  <p className="text-[10px] font-black uppercase tracking-wider text-[var(--brass)]">{selectedProduct.documentAuthor ? `By ${selectedProduct.documentAuthor}` : 'Document'}</p>
                  <p className="mt-1 whitespace-pre-line">{selectedProduct.documentContent || 'Contents unlock after purchase.'}</p>
                </div>
              )}
            </div>
            {isSinglePurchaseProduct(selectedProduct) ? (
              <div className="rounded-xl border border-[var(--line)] bg-black/15 px-4 py-3 text-sm font-black text-[var(--brass)]">{formatProductPrice(selectedProduct)}</div>
            ) : (
              <div className="grid gap-3 sm:grid-cols-[1fr_auto]">
                <NumberInput min={selectedProduct.quantityStep || quantityStepForItem(selectedProduct)} step={selectedProduct.quantityStep || quantityStepForItem(selectedProduct)} max={selectedProduct.stockQuantity ?? 999999} value={quantity} onValueChange={setQuantity} />
                <div className="rounded-xl border border-[var(--line)] bg-black/15 px-4 py-3 text-sm font-black text-[var(--brass)]">{formatProductPrice(selectedProduct, quantity)}</div>
              </div>
            )}
            {isMagicalResearchProduct(selectedProduct) && (
              <label className="grid gap-2">
                <span className="text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">Research focus</span>
                <SelectField value={researchType} onChange={(event) => setResearchType(event.target.value as typeof MAGICAL_RESEARCH_TYPES[number])}>
                  {MAGICAL_RESEARCH_TYPES.map((type) => <option key={type} value={type}>{type}</option>)}
                </SelectField>
              </label>
            )}
            <div className="grid grid-cols-2 gap-2">
              <Button variant="secondary" onClick={() => setSelectedProduct(null)}>I&rsquo;ll pass</Button>
              <Button variant="primary" disabled={!canShop || saving} onClick={buyProduct}><ShoppingBag className="mr-2 inline" size={15} /> {purchaseActionLabel(selectedProduct)}</Button>
            </div>
          </div>
        </Modal>
      )}

      {craftModal && selectedVendor && (
        <Modal title={craftModal.mode === 'craft' ? craftModal.recipe.name : craftModal.mode === 'dragon-scales' ? 'Forge Dragonscale Scale' : craftModal.mode === 'enhance' ? (craftModal.service === 'armory' ? 'Enhance Armor' : 'Enhance Gear') : 'Enchant Item'} onClose={() => setCraftModal(null)}>
          <div className="grid gap-4">
            {!selectedShopper && <div className="rounded-2xl border border-[var(--red)]/40 bg-[var(--red)]/10 p-3 text-sm text-[var(--red)]">Choose a character first.</div>}
            {craftModal.mode === 'craft' ? (
              <CraftRecipeForm
                service={craftModal.service}
                shopper={selectedShopper}
                recipe={craftModal.recipe}
                materials={craftMaterials}
                inventory={craftInventory}
                houseItems={craftHouseItems}
                wallet={craftWallet}
                materialProductId={craftMaterialProductId}
                setMaterialProductId={setCraftMaterialProductId}
              />
            ) : craftModal.mode === 'dragon-scales' ? (
              <div className="grid gap-3">
                <SoftCard>
                  <p className="font-black">Forge every 25 chosen dragon scale fragments into 1 Dragonscale Scale.</p>
                  <p className="mt-1 text-sm font-bold text-[var(--muted)]">Choose fragments from inventory or accessible house storage. Extra fragments that do not complete a set of 25 stay where they are.</p>
                </SoftCard>
                <div className="grid gap-2 sm:grid-cols-[1fr_auto]">
                  <SoftCard>
                    <p className="eyebrow">Selected fragments</p>
                    <p className={`mt-1 text-xl font-black ${selectedDragonScaleTotal >= 25 ? 'text-[var(--teal)]' : 'text-[var(--brass)]'}`}>{formatQuantity(selectedDragonScaleTotal)} / 25+</p>
                    {selectedDragonScaleTotal >= 25 && (
                      <p className="mt-1 text-xs font-black uppercase tracking-wider text-[var(--muted)]">
                        Creates {formatQuantity(selectedDragonScaleOutput)} scale{selectedDragonScaleOutput === 1 ? '' : 's'}
                        {selectedDragonScaleReturned > 0 ? `, returns ${formatQuantity(selectedDragonScaleReturned)} fragment${selectedDragonScaleReturned === 1 ? '' : 's'}` : ''}
                      </p>
                    )}
                  </SoftCard>
                  <Button variant="secondary" onClick={() => setDragonScalePickerOpen(true)}>Choose Inputs</Button>
                </div>
                {selectedDragonScaleItems.length > 0 && (
                  <div className="grid gap-2 sm:grid-cols-2">
                    {selectedDragonScaleItems.map((entry) => (
                      <CraftPreviewItem
                        key={sourceItemKey(entry)}
                        item={{
                          key: sourceItemKey(entry),
                          name: entry.item.displayName || entry.item.name,
                          type: entry.item.type,
                          rarity: entry.item.rarity,
                          quantity: entry.quantity,
                          note: entry.source === 'house' ? 'House storage' : 'Inventory'
                        }}
                      />
                    ))}
                  </div>
                )}
                {selectedDragonScaleTotal < 25 && (
                  <div className="rounded-2xl border border-[var(--red)]/40 bg-[var(--red)]/10 p-3 text-sm text-[var(--red)]">Choose at least 25 compatible dragon scale fragments.</div>
                )}
              </div>
            ) : (
              <MythrilServiceForm
                service={craftModal.service}
                mode={craftModal.mode}
                shopper={selectedShopper}
                inventory={craftInventory}
                runeItems={craftRuneItems}
                targetItemId={craftTargetItemId}
                runeItemKey={craftRuneItemKey}
                runeQuantity={craftRuneQuantity}
                setRuneQuantity={setCraftRuneQuantity}
                modifier={craftModifier}
                onOpenTargetPicker={() => setCraftTargetPickerOpen(true)}
                onOpenRunePicker={() => setCraftRunePickerOpen(true)}
                onOpenStatPicker={() => setCraftStatPickerOpen(true)}
              />
            )}
            <Button variant="primary" disabled={saving || !canConfirmForge} onClick={craftModal.mode === 'craft' ? runForgeAction : () => setCraftConfirmOpen(true)}>
              {craftModal.mode === 'craft' || craftModal.mode === 'dragon-scales' ? <Hammer className="mr-2 inline" size={15} /> : <WandSparkles className="mr-2 inline" size={15} />}
              Craft
            </Button>
          </div>
        </Modal>
      )}

      {craftModal?.mode === 'dragon-scales' && dragonScalePickerOpen && (
        <Modal title="Choose Dragon Scale Fragments" onClose={() => setDragonScalePickerOpen(false)}>
          <DragonScaleInputPicker
            items={dragonScaleItems}
            selections={dragonScaleSelections}
            onChange={setDragonScaleSelections}
            total={selectedDragonScaleTotal}
          />
          <div className="mt-4 grid grid-cols-2 gap-2">
            <Button variant="secondary" onClick={() => setDragonScaleSelections({})}>Clear</Button>
            <Button variant="primary" disabled={selectedDragonScaleTotal < 25} onClick={() => setDragonScalePickerOpen(false)}>Use These Inputs</Button>
          </div>
        </Modal>
      )}

      {craftModal && craftTargetPickerOpen && (
        <Modal title="Choose Target Item" onClose={() => setCraftTargetPickerOpen(false)}>
          <div className="grid gap-3">
            {craftTargetItems.length ? (
              <div className="thin-scrollbar grid max-h-[60vh] gap-2 overflow-y-auto pr-1 sm:grid-cols-2">
                {craftTargetItems.map((item) => (
                  <ForgeSelectableItemCard
                    key={item.id}
                    item={item}
                    selected={item.id === craftTargetItemId}
                    onClick={() => {
                      setCraftTargetItemId(item.id);
                      setCraftTargetPickerOpen(false);
                    }}
                  />
                ))}
              </div>
            ) : (
              <div className="rounded-2xl border border-[var(--line)] bg-black/15 p-4 text-sm font-bold text-[var(--muted)]">
                No eligible items are available for this forge action.
              </div>
            )}
          </div>
        </Modal>
      )}

      {craftModal && craftRunePickerOpen && (
        <Modal title="Choose Rune" onClose={() => setCraftRunePickerOpen(false)}>
          <div className="grid gap-3">
            {craftRuneItems.length ? (
              <div className="thin-scrollbar grid max-h-[60vh] gap-2 overflow-y-auto pr-1 sm:grid-cols-2">
                {craftRuneItems.map((entry) => {
                  const key = sourceItemKey(entry);
                  const minimum = craftModal.mode === 'enchant' ? enchantmentMinimumRunes(selectedShopper) : 1;
                  return (
                    <ForgeSelectableItemCard
                      key={key}
                      item={entry.item}
                      selected={key === craftRuneItemKey}
                      sourceLabel={entry.source === 'house' ? 'House storage' : 'Inventory'}
                      quantity={entry.item.quantity}
                      onClick={() => {
                        setCraftRuneItemKey(key);
                        setCraftRuneQuantity(Math.max(minimum, Math.min(Math.floor(entry.item.quantity), craftRuneQuantity || minimum)));
                        setCraftRunePickerOpen(false);
                      }}
                    />
                  );
                })}
              </div>
            ) : (
              <div className="rounded-2xl border border-[var(--line)] bg-black/15 p-4 text-sm font-bold text-[var(--muted)]">
                No compatible runes are available.
              </div>
            )}
          </div>
        </Modal>
      )}

      {craftModal?.mode === 'enhance' && craftStatPickerOpen && (
        <Modal title="Choose Stat Bonus" onClose={() => setCraftStatPickerOpen(false)}>
          <div className="grid gap-2 sm:grid-cols-2">
            {ENHANCEMENT_OPTIONS.map((option) => (
              <button
                key={option.key}
                type="button"
                onClick={() => {
                  setCraftModifier(option.key);
                  setCraftStatPickerOpen(false);
                }}
                className={`rounded-2xl border border-[var(--line)] bg-black/15 p-3 text-left transition hover:border-[var(--brass)]/60 ${craftModifier === option.key ? 'ring-2 ring-[var(--brass)] ring-offset-2 ring-offset-[#120a08]' : ''}`}
              >
                <span className="block text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">Add +1</span>
                <span className="mt-1 block font-black">{option.label}</span>
              </button>
            ))}
          </div>
        </Modal>
      )}

      {craftModal && craftConfirmOpen && craftConfirm && (
        <Modal title={craftConfirm.title} onClose={() => setCraftConfirmOpen(false)}>
          <div className="grid gap-4">
            <div className="grid items-center gap-3 md:grid-cols-[1fr_auto_1fr]">
              <div className="grid gap-2">
                <p className="eyebrow">Using</p>
                {craftConfirm.inputs.length ? craftConfirm.inputs.map((item) => <CraftPreviewItem key={item.key} item={item} />) : (
                  <div className="rounded-2xl border border-[var(--line)] bg-black/15 p-3 text-sm font-bold text-[var(--muted)]">No physical materials required.</div>
                )}
              </div>
              <div className="grid place-items-center text-[var(--brass)]">
                <ArrowRightCraft />
              </div>
              <div className="grid gap-2">
                <p className="eyebrow">Creating</p>
                <CraftPreviewItem item={{ key: 'output', ...craftConfirm.output }} featured />
              </div>
            </div>
            <div className="grid grid-cols-2 gap-2">
              <Button variant="secondary" onClick={() => setCraftConfirmOpen(false)}>Back</Button>
              <Button variant="primary" disabled={saving || !canConfirmForge} onClick={runForgeAction}>Confirm Craft</Button>
            </div>
          </div>
        </Modal>
      )}

      {editCity && cityDraft && (
        <Modal title={`Edit ${editCity.name}`} onClose={() => setEditCity(null)}>
          <form onSubmit={saveCity} className="grid gap-3">
            <label>
              <span className="mb-1 block text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">City name</span>
              <TextField value={cityDraft.name} onChange={(event) => setCityDraft({ ...cityDraft, name: event.target.value })} />
            </label>
            <label>
              <span className="mb-1 block text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">Banner description</span>
              <TextAreaField rows={5} value={cityDraft.description} onChange={(event) => setCityDraft({ ...cityDraft, description: event.target.value })} />
            </label>
            <div className="grid gap-2 sm:grid-cols-3">
              <label>
                <span className="mb-1 block text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">Primary color</span>
                <ColorField value={cityDraft.primaryColor} onChange={(event) => setCityDraft({ ...cityDraft, primaryColor: event.target.value })} />
              </label>
              <label>
                <span className="mb-1 block text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">Secondary color</span>
                <ColorField value={cityDraft.secondaryColor} onChange={(event) => setCityDraft({ ...cityDraft, secondaryColor: event.target.value })} />
              </label>
              <label>
                <span className="mb-1 block text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">Accent color</span>
                <ColorField value={cityDraft.accentColor} onChange={(event) => setCityDraft({ ...cityDraft, accentColor: event.target.value })} />
              </label>
            </div>
            <label>
              <span className="mb-1 block text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">Page position</span>
              <NumberInput min={0} step={1} value={cityDraft.order} onValueChange={(order) => setCityDraft({ ...cityDraft, order })} />
            </label>
            <div className="grid gap-2 sm:grid-cols-2">
              <label className="flex items-center gap-2 rounded-xl border border-[var(--line)] bg-black/15 p-3 text-sm font-black">
                <input type="checkbox" checked={!cityDraft.locked} onChange={(event) => setCityDraft({ ...cityDraft, locked: !event.target.checked })} />
                Open to party
              </label>
              <label className="flex items-center gap-2 rounded-xl border border-[var(--line)] bg-black/15 p-3 text-sm font-black">
                <input type="checkbox" checked={cityDraft.currentResidence} onChange={(event) => setCityDraft({ ...cityDraft, currentResidence: event.target.checked })} />
                Current residence
              </label>
              <label className="flex items-center gap-2 rounded-xl border border-[var(--line)] bg-black/15 p-3 text-sm font-black sm:col-span-2">
                <input type="checkbox" checked={cityDraft.showUnderConstruction} onChange={(event) => setCityDraft({ ...cityDraft, showUnderConstruction: event.target.checked })} />
                Show Under Construction
              </label>
            </div>
            <Button variant="primary" disabled={!cityDraft.name.trim() || saving}><PackageCheck className="mr-2 inline" size={15} /> Save city</Button>
          </form>
        </Modal>
      )}

      {projectDraft && selectedCity && (
        <Modal title={editProject ? `Edit ${editProject.name}` : 'Create Construction Project'} onClose={() => { setProjectDraft(null); setEditProject(null); setCatalogPickerIndex(null); }}>
          <form onSubmit={saveProject} className="grid gap-4">
            <label>
              <span className="mb-1 block text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">Project name</span>
              <TextField value={projectDraft.name} onChange={(event) => setProjectDraft({ ...projectDraft, name: event.target.value })} />
            </label>
            <div className="grid gap-2">
              <p className="eyebrow">Required materials</p>
              {projectDraft.requirements.map((requirement, index) => (
                <div key={index} className="grid gap-2 rounded-2xl border border-[var(--line)] bg-black/15 p-3 sm:grid-cols-[1fr_8rem_auto]">
                  <button
                    type="button"
                    onClick={() => {
                      setCatalogPickerIndex(index);
                      setCatalogSearch('');
                    }}
                    className="flex min-h-[3.25rem] items-center gap-3 rounded-xl border border-[var(--line)] bg-black/20 px-3 py-2 text-left transition hover:border-[var(--brass)]/60"
                  >
                    {(() => {
                      const selectedItem = itemCatalog.find((item) => item.id === requirement.itemCatalogId) ?? null;
                      return selectedItem ? (
                        <>
                          <span className={`grid h-9 w-9 shrink-0 place-items-center rounded-lg border bg-black/25 ${rarityClass(selectedItem.rarity)}`}><ItemIcon type={selectedItem.type} size={18} /></span>
                          <span className="min-w-0">
                            <span className="block truncate font-black">{selectedItem.name}</span>
                            <span className="block text-xs font-bold text-[var(--muted)]">{selectedItem.rarity} · {selectedItem.type}</span>
                          </span>
                        </>
                      ) : (
                        <>
                          <span className="grid h-9 w-9 shrink-0 place-items-center rounded-lg border border-[var(--brass)]/35 bg-[var(--brass)]/10 text-[var(--brass)]"><PackageCheck size={17} /></span>
                          <span className="font-black text-[var(--muted)]">Choose item catalog</span>
                        </>
                      );
                    })()}
                  </button>
                  <NumberInput min={0.5} step={0.5} value={requirement.quantity} onValueChange={(quantity) => {
                    const requirements = [...projectDraft.requirements];
                    requirements[index] = { ...requirement, quantity };
                    setProjectDraft({ ...projectDraft, requirements });
                  }} />
                  <Button type="button" variant="secondary" className="px-3" onClick={() => setProjectDraft({ ...projectDraft, requirements: projectDraft.requirements.filter((_, entryIndex) => entryIndex !== index) })} disabled={projectDraft.requirements.length <= 1} aria-label="Remove material"><X size={14} /></Button>
                </div>
              ))}
              <Button type="button" variant="secondary" onClick={() => setProjectDraft({ ...projectDraft, requirements: [...projectDraft.requirements, { itemCatalogId: '', quantity: 1 }] })}><Plus className="mr-2 inline" size={15} /> Add material</Button>
            </div>
            <Button variant="primary" disabled={!projectDraft.name.trim() || projectDraft.requirements.every((requirement) => !requirement.itemCatalogId) || saving}><PackageCheck className="mr-2 inline" size={15} /> Save project</Button>
          </form>
        </Modal>
      )}

      {projectDraft && catalogPickerIndex !== null && (
        <Modal title="Choose Construction Item" onClose={() => setCatalogPickerIndex(null)}>
          <div className="grid gap-4">
            <label className="relative block">
              <span className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-[var(--muted)]"><Search size={17} /></span>
              <TextField className="pl-10" value={catalogSearch} onChange={(event) => setCatalogSearch(event.target.value)} placeholder="Search item catalog" autoFocus />
            </label>
            <div className="max-h-[60vh] overflow-y-auto rounded-2xl border border-[var(--line)] bg-black/15 p-2">
              {filteredConstructionCatalog.length === 0 ? (
                <div className="rounded-xl border border-[var(--line)] bg-black/20 p-4 text-sm font-bold text-[var(--muted)]">No catalog items match that search.</div>
              ) : (
                <div className="grid gap-2 sm:grid-cols-2">
                  {filteredConstructionCatalog.map((item) => {
                    const active = projectDraft.requirements[catalogPickerIndex]?.itemCatalogId === item.id;
                    return (
                      <button
                        key={item.id}
                        type="button"
                        onClick={() => {
                          const requirements = [...projectDraft.requirements];
                          requirements[catalogPickerIndex] = { ...requirements[catalogPickerIndex], itemCatalogId: item.id };
                          setProjectDraft({ ...projectDraft, requirements });
                          setCatalogPickerIndex(null);
                        }}
                        className={`flex min-h-[4.5rem] items-center gap-3 rounded-xl border p-3 text-left transition ${active ? 'border-[var(--brass)] bg-[var(--brass)]/12' : 'border-[var(--line)] bg-black/20 hover:border-[var(--brass)]/60'}`}
                      >
                        <span className={`grid h-11 w-11 shrink-0 place-items-center rounded-xl border bg-black/25 ${rarityClass(item.rarity)}`}><ItemIcon type={item.type} size={21} /></span>
                        <span className="min-w-0">
                          <span className="block break-words font-black">{item.name}</span>
                          <span className="mt-1 block text-xs font-bold text-[var(--muted)]">{item.rarity} · {item.type}{item.category ? ` · ${item.category}` : ''}</span>
                        </span>
                      </button>
                    );
                  })}
                </div>
              )}
            </div>
          </div>
        </Modal>
      )}

      {contributeProject && (
        <Modal title={`Contribute to ${contributeProject.name}`} onClose={() => setContributeProject(null)}>
          <div className="grid gap-4">
            {!canContribute && <div className="rounded-2xl border border-[var(--red)]/40 bg-[var(--red)]/10 p-3 text-sm text-[var(--red)]">Choose a character in this open city before contributing.</div>}
            <div className="grid gap-2 sm:grid-cols-2">
              {contributionSources.length === 0 ? (
                <div className="rounded-2xl border border-[var(--line)] bg-black/15 p-3 text-sm font-bold text-[var(--muted)] sm:col-span-2">No matching materials are available from this character, accessible Wagon Home storage, or nearby shared wagons.</div>
              ) : contributionSources.map((entry) => {
                const key = contributionSourceKey(entry);
                const selected = contributionSelections[key] ?? 0;
                return (
                  <div key={key} className={`rounded-2xl border p-3 ${selected > 0 ? 'border-[var(--brass)] bg-[var(--brass)]/10' : 'border-[var(--line)] bg-black/15'}`}>
                    <button type="button" className="flex w-full items-center gap-3 text-left" onClick={() => setContributionSelections((current) => ({ ...current, [key]: current[key] ? 0 : Math.min(entry.item.quantity, 1) }))}>
                      <span className="grid h-11 w-11 shrink-0 place-items-center rounded-xl border border-[var(--brass)]/45 bg-black/20 text-[var(--brass)]"><ItemIcon type={entry.item.type} size={21} /></span>
                      <span className="min-w-0">
                        <span className="block break-words font-black">{entry.item.displayName || entry.item.name}</span>
                        <span className="block text-xs font-bold text-[var(--muted)]">{entry.sourceLabel} · {formatQuantity(entry.item.quantity)} available</span>
                      </span>
                    </button>
                    {selected > 0 && <div className="mt-3"><NumberInput min={quantityStepForItem(entry.item)} step={quantityStepForItem(entry.item)} max={entry.item.quantity} value={selected} onValueChange={(quantity) => setContributionSelections((current) => ({ ...current, [key]: quantity }))} /></div>}
                  </div>
                );
              })}
            </div>
            <Button variant="primary" disabled={!canContribute || saving || Object.values(contributionSelections).every((quantity) => quantity <= 0)} onClick={submitContribution}><PackageCheck className="mr-2 inline" size={15} /> Contribute</Button>
          </div>
        </Modal>
      )}

      {managingVendor && selectedCity && (
        <Modal title={`Manage ${managingVendor.name}`} onClose={() => { setManagingVendorId(''); setManageSection(''); setSectionDraftName(''); setBulkProductPickerOpen(false); setBulkCatalogKeys([]); }}>
          <div className="grid gap-4">
            <div className="rounded-2xl border border-[var(--line)] bg-black/15 p-4">
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div className="min-w-0">
                  <p className="eyebrow">{blueprintInfo(managingVendor.blueprintType).label} Blueprint</p>
                  <h3 className="mt-1 break-words text-2xl font-black">{managingVendor.name}</h3>
                  <p className="mt-1 text-sm font-bold text-[var(--muted)]">{managingVendor.npcName} - {managingVendor.facility} - {productCountText(managingVendor)}</p>
                </div>
                <div className="flex flex-wrap gap-2">
                  <Button variant="secondary" className="px-3 py-2 text-xs" onClick={() => openVendorEdit(managingVendor)} disabled={saving}><Pencil className="mr-2 inline" size={13} /> Shop settings</Button>
                  <Button variant={managingVendor.hidden ? 'teal' : 'secondary'} className="px-3 py-2 text-xs" onClick={() => void patchVendor(managingVendor, { hidden: !managingVendor.hidden }, 'Shop visibility could not be changed.')} disabled={saving}>
                    {managingVendor.hidden ? <Eye className="mr-2 inline" size={13} /> : <EyeOff className="mr-2 inline" size={13} />}
                    {managingVendor.hidden ? 'Show shop' : 'Hide shop'}
                  </Button>
                  <Button variant="danger" className="px-3 py-2 text-xs" onClick={() => void deleteVendor(managingVendor)} disabled={saving}><Trash2 className="mr-2 inline" size={13} /> Delete shop</Button>
                </div>
              </div>
            </div>

            <div className="grid gap-4 xl:grid-cols-[18rem_1fr]">
              <div className="rounded-2xl border border-[var(--line)] bg-black/15 p-3">
                <div className="mb-3 flex items-center justify-between gap-2">
                  <div>
                    <p className="eyebrow">Sections</p>
                    <p className="text-xs font-bold text-[var(--muted)]">Choose where products live.</p>
                  </div>
                  <span className="rounded-full border border-[var(--line)] bg-black/25 px-2 py-1 text-xs font-black text-[var(--muted)]">{manageSections.length}</span>
                </div>
                <div className="grid gap-2">
                  {manageSections.map((section) => {
                    const count = managingVendor.products.filter((product) => productSection(product) === section).length;
                    const selected = section === activeManageSection;
                    return (
                      <button
                        key={section}
                        type="button"
                        onClick={() => setManageSection(section)}
                        className={`rounded-xl border p-3 text-left transition ${selected ? 'border-[var(--brass)] bg-[var(--brass)]/12' : 'border-[var(--line)] bg-black/15 hover:border-[var(--brass)]/50'}`}
                      >
                        <span className="flex items-center justify-between gap-2">
                          <span className="min-w-0">
                            <span className="block break-words text-sm font-black">{section}</span>
                            <span className="mt-1 block text-xs font-bold text-[var(--muted)]">{count} product{count === 1 ? '' : 's'}</span>
                          </span>
                          {selected && <CheckCircle2 size={16} className="shrink-0 text-[var(--brass)]" />}
                        </span>
                      </button>
                    );
                  })}
                </div>
                <div className="mt-3 grid gap-2 rounded-xl border border-[var(--line)] bg-black/15 p-3">
                  <label>
                    <span className="mb-1 block text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">New section</span>
                    <TextField value={sectionDraftName} onChange={(event) => setSectionDraftName(event.target.value)} placeholder="Example: Cedrick - Supplies" />
                  </label>
                  <div className="flex flex-wrap gap-1">
                    {blueprintSections(managingVendor.blueprintType)
                      .filter((section) => !manageSections.includes(section))
                      .slice(0, 6)
                      .map((section) => (
                        <button
                          key={section}
                          type="button"
                          onClick={() => setSectionDraftName(section)}
                          className="rounded-lg border border-[var(--line)] bg-black/20 px-2 py-1 text-[10px] font-black uppercase tracking-wide text-[var(--muted)] transition hover:border-[var(--brass)]/50 hover:text-[var(--brass)]"
                        >
                          {section}
                        </button>
                      ))}
                  </div>
                  <Button
                    variant="secondary"
                    className="px-3 py-2 text-xs"
                    disabled={!sectionDraftName.trim()}
                    onClick={() => {
                      const nextSection = sectionDraftName.trim();
                      setManageSection(nextSection);
                      setSectionDraftName('');
                    }}
                  >
                    <Plus className="mr-2 inline" size={13} /> Add section
                  </Button>
                </div>
              </div>

              <div className="rounded-2xl border border-[var(--line)] bg-black/15 p-3">
                <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
                  <div>
                    <p className="eyebrow">Section Inventory</p>
                    <h3 className="mt-1 text-xl font-black">{activeManageSection}</h3>
                    <p className="mt-1 text-xs font-bold text-[var(--muted)]">Products here use the same cards players see while shopping.</p>
                  </div>
                  <div className="flex flex-wrap gap-2">
                    <Button variant="secondary" className="px-3 py-2 text-xs" onClick={() => { setBulkProductPickerOpen(true); setBulkCatalogKeys([]); setCatalogSearch(''); }} disabled={saving}>
                      <PackageCheck className="mr-2 inline" size={13} /> Add catalog items
                    </Button>
                    <Button variant="secondary" className="px-3 py-2 text-xs" onClick={() => openProductCreate(managingVendor, activeManageSection)} disabled={saving}>
                      <Plus className="mr-2 inline" size={13} /> Custom product
                    </Button>
                    <Button variant="danger" className="px-3 py-2 text-xs" onClick={() => void deleteSection(managingVendor, activeManageSection)} disabled={saving}>
                      <Trash2 className="mr-2 inline" size={13} /> Delete section
                    </Button>
                  </div>
                </div>
                {manageSectionProducts.length === 0 ? (
                  <div className="rounded-2xl border border-dashed border-[var(--line)] bg-black/10 p-5 text-sm font-bold text-[var(--muted)]">
                    This section is empty. Add catalog items or create a custom product to make it appear in the shop.
                  </div>
                ) : (
                  <ProductGrid
                    products={manageSectionProducts}
                    isDm={isDm}
                    saving={saving}
                    canShop={false}
                    onSelectProduct={openProductEdit}
                    onEditProduct={openProductEdit}
                    onDeleteProduct={(product) => void deleteProduct(product)}
                    onPatchProduct={(product, patch) => void patchProduct(product, patch, 'Item visibility could not be changed.')}
                  />
                )}
              </div>
            </div>
          </div>
        </Modal>
      )}

      {managingVendor && selectedCity && bulkProductPickerOpen && (
        <Modal title={`Add Items to ${activeManageSection}`} onClose={() => { setBulkProductPickerOpen(false); setBulkCatalogKeys([]); }}>
          <div className="grid gap-4">
            <label className="relative block">
              <span className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-[var(--muted)]"><Search size={17} /></span>
              <TextField className="pl-10" value={catalogSearch} onChange={(event) => setCatalogSearch(event.target.value)} placeholder="Search item catalog" autoFocus />
            </label>
            <div className="rounded-2xl border border-[var(--line)] bg-black/15 p-3">
              <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
                <p className="text-sm font-black">{selectedBulkCatalogItems.length} selected</p>
                <Button variant="secondary" className="px-3 py-2 text-xs" onClick={() => setBulkCatalogKeys([])} disabled={selectedBulkCatalogItems.length === 0}>Clear</Button>
              </div>
              <div className="thin-scrollbar max-h-[58vh] overflow-y-auto pr-1">
                {filteredProductCatalog.length === 0 ? (
                  <div className="rounded-xl border border-[var(--line)] bg-black/20 p-4 text-sm font-bold text-[var(--muted)]">No catalog items match that search.</div>
                ) : (
                  <div className="grid gap-2 sm:grid-cols-2">
                    {filteredProductCatalog.map((item) => {
                      const selected = bulkCatalogKeys.includes(item.key);
                      return (
                        <button
                          key={item.id}
                          type="button"
                          onClick={() => setBulkCatalogKeys((current) => selected ? current.filter((key) => key !== item.key) : [...current, item.key])}
                          className={`flex min-h-[4.75rem] items-center gap-3 rounded-xl border p-3 text-left transition ${selected ? 'border-[var(--brass)] bg-[var(--brass)]/12' : 'border-[var(--line)] bg-black/20 hover:border-[var(--brass)]/60'}`}
                        >
                          <span className={`grid h-11 w-11 shrink-0 place-items-center rounded-xl border bg-black/25 ${rarityClass(item.rarity)}`}><ItemIcon type={item.type} size={21} /></span>
                          <span className="min-w-0 flex-1">
                            <span className="block break-words font-black">{item.name}</span>
                            <span className="mt-1 block text-xs font-bold text-[var(--muted)]">{item.rarity} - {item.type}{item.category ? ` - ${item.category}` : ''}</span>
                          </span>
                          {selected && <CheckCircle2 size={17} className="shrink-0 text-[var(--brass)]" />}
                        </button>
                      );
                    })}
                  </div>
                )}
              </div>
            </div>
            <Button variant="primary" disabled={saving || bulkCatalogKeys.length === 0} onClick={() => void addCatalogProductsToSection(managingVendor, activeManageSection)}>
              <PackageCheck className="mr-2 inline" size={15} /> Add {bulkCatalogKeys.length || ''} item{bulkCatalogKeys.length === 1 ? '' : 's'}
            </Button>
          </div>
        </Modal>
      )}

      {(editVendor || creatingVendor) && vendorDraft && (
        <Modal title={creatingVendor ? 'Create Shop' : `Edit ${editVendor?.name ?? 'Shop'}`} onClose={() => { setEditVendor(null); setCreatingVendor(false); setVendorDraft(null); }}>
          <form onSubmit={saveVendor} className="grid gap-3">
            {creatingVendor && (
              <div className="rounded-2xl border border-[var(--line)] bg-black/15 p-3">
                <p className="eyebrow">Choose Blueprint</p>
                <div className="mt-3 grid gap-2 sm:grid-cols-2">
                  {SHOP_BLUEPRINTS.map((blueprint) => {
                    const selected = vendorDraft.blueprintType === blueprint.key;
                    return (
                      <button
                        key={blueprint.key}
                        type="button"
                        onClick={() => setVendorDraft({
                          ...vendorDraft,
                          blueprintType: blueprint.key,
                          facility: blueprint.facility,
                          category: blueprint.category
                        })}
                        className={`rounded-2xl border p-3 text-left transition ${selected ? 'border-[var(--brass)] bg-[var(--brass)]/12' : 'border-[var(--line)] bg-black/15 hover:border-[var(--brass)]/50'}`}
                      >
                        <span className="flex items-start gap-3">
                          <span className="grid h-10 w-10 shrink-0 place-items-center rounded-xl border border-[var(--brass)]/35 bg-[var(--brass)]/10 text-[var(--brass)]"><Store size={18} /></span>
                          <span className="min-w-0">
                            <span className="flex items-center gap-2 font-black">{blueprint.label}{selected && <CheckCircle2 size={15} className="text-[var(--brass)]" />}</span>
                            <span className="mt-1 block text-xs font-bold leading-5 text-[var(--muted)]">{blueprint.description}</span>
                          </span>
                        </span>
                      </button>
                    );
                  })}
                </div>
              </div>
            )}
            <label>
              <span className="mb-1 block text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">Shop name</span>
              <TextField value={vendorDraft.name} onChange={(event) => setVendorDraft({ ...vendorDraft, name: event.target.value })} />
            </label>
            <label>
              <span className="mb-1 block text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">NPC running shop</span>
              <TextField value={vendorDraft.npcName} onChange={(event) => setVendorDraft({ ...vendorDraft, npcName: event.target.value })} />
            </label>
            <div className="grid gap-2 sm:grid-cols-2">
              <label>
                <span className="mb-1 block text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">Blueprint</span>
                <SelectField value={vendorDraft.blueprintType} onChange={(event) => setVendorDraft({ ...vendorDraft, blueprintType: event.target.value as VendorDraft['blueprintType'] })} disabled={!creatingVendor}>
                  <option value="market">Market</option>
                  <option value="blacksmith">Blacksmith</option>
                  <option value="armory">Armory</option>
                  <option value="brewery">Brewery</option>
                  <option value="spell_registrar">Spell Registrar</option>
                  <option value="library">Library</option>
                </SelectField>
              </label>
              <label>
                <span className="mb-1 block text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">Player-run payout</span>
                <SelectField value={vendorDraft.payoutCharacterId} onChange={(event) => setVendorDraft({ ...vendorDraft, payoutCharacterId: event.target.value })}>
                  <option value="">No payout</option>
                  {payload.characters.map((character) => (
                    <option key={character.id} value={character.id}>{character.name} - {character.className}</option>
                  ))}
                </SelectField>
              </label>
              <label>
                <span className="mb-1 block text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">Facility</span>
                <TextField value={vendorDraft.facility} onChange={(event) => setVendorDraft({ ...vendorDraft, facility: event.target.value })} />
              </label>
              <label>
                <span className="mb-1 block text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">Category</span>
                <TextField value={vendorDraft.category} onChange={(event) => setVendorDraft({ ...vendorDraft, category: event.target.value })} />
              </label>
            </div>
            <label className="flex items-center gap-2 rounded-xl border border-[var(--line)] bg-black/15 p-3 text-sm font-black">
              <input type="checkbox" checked={!vendorDraft.hidden} onChange={(event) => setVendorDraft({ ...vendorDraft, hidden: !event.target.checked })} />
              Visible to players
            </label>
            <Button variant="primary" disabled={!vendorDraft.name.trim() || !vendorDraft.npcName.trim() || saving}><PackageCheck className="mr-2 inline" size={15} /> Save shop</Button>
          </form>
        </Modal>
      )}

      {(editProduct || creatingProductForVendor) && productDraft && (
        <Modal title={creatingProductForVendor ? `Add to ${creatingProductForVendor.name}` : `Edit ${editProduct?.name ?? 'Product'}`} onClose={() => { setEditProduct(null); setCreatingProductForVendor(null); setProductDraft(null); setProductCatalogPickerOpen(false); }}>
          <form onSubmit={saveProduct} className="grid gap-3">
            <label>
              <span className="mb-1 block text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">Name</span>
              <TextField value={productDraft.name} onChange={(event) => setProductDraft({ ...productDraft, name: event.target.value })} />
            </label>
            <label>
              <span className="mb-1 block text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">Description / public preview</span>
              <TextAreaField rows={3} value={productDraft.description} onChange={(event) => setProductDraft({ ...productDraft, description: event.target.value })} />
            </label>
            <div className="grid gap-2 sm:grid-cols-2">
              <label>
                <span className="mb-1 block text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">Sale kind</span>
                <SelectField value={productDraft.kind} onChange={(event) => setProductDraft({ ...productDraft, kind: event.target.value as ProductDraft['kind'] })}>
                  <option value="item">Item</option>
                  <option value="spell">Spell</option>
                  <option value="document">Document</option>
                  <option value="service">Service only</option>
                </SelectField>
              </label>
              {productDraft.kind === 'item' && (
                <button
                  type="button"
                  onClick={() => {
                    setProductCatalogPickerOpen(true);
                    setCatalogSearch('');
                  }}
                  className="flex min-h-[3.25rem] items-center gap-3 rounded-xl border border-[var(--line)] bg-black/20 px-3 py-2 text-left transition hover:border-[var(--brass)]/60"
                >
                  <span className="grid h-9 w-9 shrink-0 place-items-center rounded-lg border border-[var(--brass)]/35 bg-[var(--brass)]/10 text-[var(--brass)]"><PackageCheck size={17} /></span>
                  <span className="min-w-0">
                    <span className="block truncate font-black">{productDraft.catalogItemKey ? 'Catalog linked' : 'Choose catalog item'}</span>
                    <span className="block text-xs font-bold text-[var(--muted)]">{productDraft.catalogItemKey || 'Optional, but recommended'}</span>
                  </span>
                </button>
              )}
              <label>
                <span className="mb-1 block text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">Item type</span>
                <SelectField value={productDraft.type} onChange={(event) => setProductDraft({ ...productDraft, type: event.target.value as ItemType })}>{ITEM_TYPES.map((type) => <option key={type} value={type}>{type}</option>)}</SelectField>
              </label>
              <label>
                <span className="mb-1 block text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">Rarity</span>
                <SelectField value={productDraft.rarity} onChange={(event) => setProductDraft({ ...productDraft, rarity: event.target.value as ItemRarity })}>{rarityOptions.map((rarity) => <option key={rarity} value={rarity}>{rarity}</option>)}</SelectField>
              </label>
              <div className="sm:col-span-2">
                <CurrencyPriceEditor
                  systemKey={productDraft.currencySystemKey}
                  value={productDraft.priceCoin}
                  onSystemChange={(currencySystemKey) => setProductDraft({ ...productDraft, currencySystemKey, priceCoin: 0 })}
                  onValueChange={(priceCoin) => setProductDraft({ ...productDraft, priceCoin })}
                />
              </div>
              <label>
                <span className="mb-1 block text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">Stock quantity</span>
                <NumberInput min={0} step={productDraft.quantityStep || 1} value={productDraft.stockQuantity} onValueChange={(stockQuantity) => setProductDraft({ ...productDraft, stockQuantity })} />
              </label>
              <label>
                <span className="mb-1 block text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">{productDraft.kind === 'spell' ? 'Spell category' : productDraft.kind === 'document' ? 'Library section' : 'Shop section'}</span>
                <TextField value={productDraft.section} onChange={(event) => setProductDraft({ ...productDraft, section: event.target.value })} placeholder="Shop section" />
              </label>
              {productDraft.kind === 'spell' && (
                <label>
                  <span className="mb-1 block text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">Mana cost</span>
                  <NumberInput min={0} step={1} value={productDraft.manaCost} onValueChange={(manaCost) => setProductDraft({ ...productDraft, manaCost })} />
                </label>
              )}
              <label>
                <span className="mb-1 block text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">Quantity step</span>
                <NumberInput min={0.5} step={0.5} value={productDraft.quantityStep} onValueChange={(quantityStep) => setProductDraft({ ...productDraft, quantityStep })} />
              </label>
            </div>
            {productDraft.kind === 'document' && (
              <div className="grid gap-3">
                <label>
                  <span className="mb-1 block text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">Author / drafted by</span>
                  <TextField value={productDraft.documentAuthor} onChange={(event) => setProductDraft({ ...productDraft, documentAuthor: event.target.value })} />
                </label>
                <label>
                  <span className="mb-1 block text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">Document contents</span>
                  <TextAreaField rows={8} value={productDraft.documentContent} onChange={(event) => setProductDraft({ ...productDraft, documentContent: event.target.value })} />
                </label>
              </div>
            )}
            <label className="flex items-center gap-2 rounded-xl border border-[var(--line)] bg-black/15 p-3 text-sm font-black">
              <input type="checkbox" checked={productDraft.available} onChange={(event) => setProductDraft({ ...productDraft, available: event.target.checked })} />
              Available for sale
            </label>
            <Button variant="primary" disabled={!productDraft.name.trim() || saving}><PackageCheck className="mr-2 inline" size={15} /> Save product</Button>
          </form>
        </Modal>
      )}

      {productDraft && productCatalogPickerOpen && (
        <Modal title="Choose Shop Item" onClose={() => setProductCatalogPickerOpen(false)}>
          <div className="grid gap-4">
            <label className="relative block">
              <span className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-[var(--muted)]"><Search size={17} /></span>
              <TextField className="pl-10" value={catalogSearch} onChange={(event) => setCatalogSearch(event.target.value)} placeholder="Search item catalog" autoFocus />
            </label>
            <div className="max-h-[60vh] overflow-y-auto rounded-2xl border border-[var(--line)] bg-black/15 p-2">
              {filteredProductCatalog.length === 0 ? (
                <div className="rounded-xl border border-[var(--line)] bg-black/20 p-4 text-sm font-bold text-[var(--muted)]">No catalog items match that search.</div>
              ) : (
                <div className="grid gap-2 sm:grid-cols-2">
                  {filteredProductCatalog.map((item) => (
                    <button
                      key={item.id}
                      type="button"
                      onClick={() => {
                        setProductDraft({
                          ...productDraft,
                          name: item.name,
                          type: item.type,
                          rarity: item.rarity,
                          quantityStep: item.quantityStep,
                          catalogItemKey: item.key,
                          description: productDraft.description || item.notes
                        });
                        setProductCatalogPickerOpen(false);
                      }}
                      className="flex min-h-[4.5rem] items-center gap-3 rounded-xl border border-[var(--line)] bg-black/20 p-3 text-left transition hover:border-[var(--brass)]/60"
                    >
                      <span className={`grid h-11 w-11 shrink-0 place-items-center rounded-xl border bg-black/25 ${rarityClass(item.rarity)}`}><ItemIcon type={item.type} size={21} /></span>
                      <span className="min-w-0">
                        <span className="block break-words font-black">{item.name}</span>
                        <span className="mt-1 block text-xs font-bold text-[var(--muted)]">{item.rarity} - {item.type}{item.category ? ` - ${item.category}` : ''}</span>
                      </span>
                    </button>
                  ))}
                </div>
              )}
            </div>
          </div>
        </Modal>
      )}
    </div>
  );
}

function CurrencyPriceEditor({
  systemKey,
  value,
  onSystemChange,
  onValueChange
}: {
  systemKey: 'common' | 'calostrynn';
  value: number;
  onSystemChange: (systemKey: 'common' | 'calostrynn') => void;
  onValueChange: (value: number) => void;
}) {
  const parts = decomposeCurrencyValue(value, systemKey);
  const units = currencyUnitsForSystem(systemKey);

  function updatePart(unitKey: string, amount: number) {
    onValueChange(composeCurrencyValue({ ...parts, [unitKey]: amount }, systemKey));
  }

  return (
    <div className="rounded-2xl border border-[var(--line)] bg-black/15 p-3">
      <div className="mb-3 grid gap-2 sm:grid-cols-[1fr_auto] sm:items-end">
        <label>
          <span className="mb-1 block text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">Price currency</span>
          <SelectField value={systemKey} onChange={(event) => onSystemChange(normalizeCurrencySystemKey(event.target.value))}>
            <option value="common">Bits / Shillings / Marks / Crown / Sovereign</option>
            <option value="calostrynn">Coin / Callis / Callor / Cal</option>
          </SelectField>
        </label>
        <span className="rounded-xl border border-[var(--brass)]/35 bg-[var(--brass)]/10 px-3 py-2 text-sm font-black text-[var(--brass)]">
          {formatCurrencyValue(value, systemKey)}
        </span>
      </div>
      <div className="grid grid-cols-2 gap-2 sm:grid-cols-5">
        {units.map((unit) => (
          <label key={unit.key}>
            <span className="mb-1 block text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">{unit.name}</span>
            <NumberInput min={0} step={1} value={parts[unit.key] ?? 0} onValueChange={(amount) => updatePart(unit.key, amount)} />
          </label>
        ))}
      </div>
    </div>
  );
}

function CitySectionHeading({ label, city }: { label: string; city?: City }) {
  return (
    <div
      className="relative overflow-hidden rounded-2xl border px-4 py-3 shadow-[0_12px_28px_rgba(0,0,0,0.18)]"
      style={{
        borderColor: city ? `${city.accentColor}66` : undefined,
        background: city
          ? `linear-gradient(90deg, ${city.primaryColor}34, rgba(0,0,0,0.24), ${city.secondaryColor}30)`
          : undefined
      }}
    >
      <div
        className="pointer-events-none absolute inset-x-4 top-0 h-px"
        style={{ background: city ? `linear-gradient(90deg, transparent, ${city.accentColor}, ${city.primaryColor}, transparent)` : undefined }}
      />
      <h3 className="text-center text-sm font-black uppercase tracking-[0.24em]" style={{ color: city?.accentColor ?? undefined }}>{label}</h3>
    </div>
  );
}

function ConstructionSection({ city, projects, isDm, saving, canContribute, onCreate, onEdit, onEnd, onContribute }: {
  city: City;
  projects: CityConstructionProject[];
  isDm: boolean;
  saving: boolean;
  canContribute: boolean;
  onCreate: () => void;
  onEdit: (project: CityConstructionProject) => void;
  onEnd: (project: CityConstructionProject) => void;
  onContribute: (project: CityConstructionProject) => void;
}) {
  return (
    <section className="space-y-3">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div className="min-w-[14rem] flex-1"><CitySectionHeading label="Under Construction" city={city} /></div>
        {isDm && <Button variant="secondary" className="px-3 py-2 text-xs" onClick={onCreate} disabled={saving}><Plus className="mr-2 inline" size={13} /> New project</Button>}
      </div>
      {projects.length === 0 ? (
        <Card><p className="text-sm font-bold text-[var(--muted)]">No active projects yet.</p></Card>
      ) : (
        <div className="grid gap-4">
          {projects.map((project) => (
            <Card key={project.id} className="overflow-hidden">
              <div
                className="relative -m-4 mb-4 overflow-hidden border-b p-4 sm:-m-5 sm:mb-5 sm:p-5"
                style={{
                  borderColor: `${city.primaryColor}42`,
                  background: `linear-gradient(135deg, ${city.primaryColor}24, rgba(0,0,0,0.12), ${city.secondaryColor}20)`
                }}
              >
                <div className="pointer-events-none absolute inset-x-5 top-0 h-px" style={{ background: `linear-gradient(90deg, transparent, ${city.accentColor}, transparent)` }} />
                <div className="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <p className="eyebrow">Construction Project</p>
                  <h4 className="mt-1 text-2xl font-black">{project.name}</h4>
                </div>
                <div className="flex flex-wrap gap-2">
                  {!project.complete && <Button variant="teal" className="px-3 py-2 text-xs" disabled={!canContribute || saving} onClick={() => onContribute(project)}>Contribute</Button>}
                  {isDm && !project.complete && <Button variant="secondary" className="px-3 py-2 text-xs" disabled={saving} onClick={() => onEdit(project)}><Pencil className="mr-2 inline" size={13} /> Edit</Button>}
                  {isDm && <Button variant={project.complete ? 'primary' : 'secondary'} className="px-3 py-2 text-xs" disabled={saving} onClick={() => onEnd(project)}>{project.complete ? <CheckCircle2 className="mr-2 inline" size={13} /> : null} End</Button>}
                </div>
                </div>
              </div>
              <div className="h-4 overflow-hidden rounded-full border bg-black/35" style={{ borderColor: `${city.accentColor}55` }}>
                <div
                  className="h-full rounded-full shadow-[0_0_18px_rgba(245,180,76,0.18)]"
                  style={{
                    width: '100%',
                    transform: `scaleX(${Math.max(0, Math.min(1, project.progress))})`,
                    transformOrigin: 'left center',
                    background: `linear-gradient(90deg, ${city.primaryColor} 0%, ${city.primaryColor} 68%, ${city.secondaryColor} 88%, ${city.accentColor} 100%)`
                  }}
                />
              </div>
              {project.complete ? (
                <div
                  className="mt-5 rounded-2xl border p-5 text-center text-2xl font-black"
                  style={{ borderColor: `${city.accentColor}70`, backgroundColor: `${city.secondaryColor}18`, color: city.accentColor }}
                >COMPLETED</div>
              ) : (
                <div className="mt-4 grid gap-2">
                  {project.requirements.map((requirement) => (
                    <ConstructionRequirementRow key={requirement.id} requirement={requirement} city={city} />
                  ))}
                </div>
              )}
            </Card>
          ))}
        </div>
      )}
    </section>
  );
}

function ConstructionRequirementRow({ requirement, city }: { requirement: CityConstructionRequirement; city: City }) {
  return (
    <div
      className="grid grid-cols-[1fr_auto] items-center gap-3 rounded-2xl border bg-black/15 p-3"
      style={{ borderColor: requirement.complete ? `${city.accentColor}70` : `${city.primaryColor}30` }}
    >
      <div className="flex min-w-0 items-center gap-3">
        <span className={`grid h-11 w-11 shrink-0 place-items-center rounded-xl border bg-black/20 ${rarityClass(requirement.item.rarity)}`}><ItemIcon type={requirement.item.type} size={20} /></span>
        <div className="min-w-0">
          <p className="break-words font-black">{requirement.item.name}</p>
          <p className="text-xs font-bold text-[var(--muted)]">{requirement.item.type}</p>
        </div>
      </div>
      <div className="text-right text-sm font-black" style={{ color: requirement.complete ? city.accentColor : undefined }}>
        {requirement.complete ? 'COMPLETE' : `${formatQuantity(requirement.contributedQuantity)} / ${formatQuantity(requirement.requiredQuantity)}`}
      </div>
    </div>
  );
}

function ShopCard({ vendor, isDm, saving, index, total, onOpen, onManage, onEdit, onDelete, onToggleVisibility, onMove }: {
  vendor: ShopVendor;
  isDm: boolean;
  saving: boolean;
  index: number;
  total: number;
  onOpen: () => void;
  onManage: () => void;
  onEdit: () => void;
  onDelete: () => void;
  onToggleVisibility: () => void;
  onMove: (direction: -1 | 1) => void;
}) {
  return (
    <Card className={`overflow-hidden ${vendor.hidden ? 'opacity-75' : ''}`}>
      <button
        type="button"
        onClick={onOpen}
        className="group w-full rounded-2xl border border-[var(--line)] bg-gradient-to-br from-[rgba(245,180,76,0.18)] via-black/10 to-[rgba(31,120,117,0.14)] p-4 text-left transition hover:border-[var(--brass)]/70"
      >
        <span className="flex items-start gap-3">
          <span className="grid h-12 w-12 shrink-0 place-items-center rounded-2xl border border-[var(--brass)]/45 bg-[var(--brass)]/15 text-[var(--brass)] shadow-[0_0_22px_rgba(245,180,76,0.14)]">
            <Store size={22} />
          </span>
          <span className="min-w-0 flex-1">
            <span className="eyebrow">{vendor.facility}</span>
            <span className="mt-1 block break-words text-xl font-black leading-tight">{vendor.name}</span>
            <span className="mt-1 flex flex-wrap items-center gap-2 text-xs font-bold text-[var(--muted)]">
              <span className="inline-flex items-center gap-1"><Users size={13} /> {vendor.npcName}</span>
              <span>{vendor.category}</span>
              <span>{productCountText(vendor)}</span>
            </span>
          </span>
        </span>
      </button>

      {isDm && (
        <div className="mt-3 flex flex-wrap gap-2">
          <Button variant="primary" className="px-3 py-2 text-xs" onClick={onManage} disabled={saving}>
            <Settings className="mr-2 inline" size={13} /> Manage
          </Button>
          <Button variant="secondary" className="px-3 py-2 text-xs" onClick={onEdit} disabled={saving}>
            <Pencil className="mr-2 inline" size={13} /> Edit shop
          </Button>
          <Button variant={vendor.hidden ? 'teal' : 'secondary'} className="px-3 py-2 text-xs" onClick={onToggleVisibility} disabled={saving}>
            {vendor.hidden ? <Eye className="mr-2 inline" size={13} /> : <EyeOff className="mr-2 inline" size={13} />}
            {vendor.hidden ? 'Show shop' : 'Hide shop'}
          </Button>
          <Button variant="danger" className="px-3 py-2 text-xs" onClick={onDelete} disabled={saving}>
            <Trash2 className="mr-2 inline" size={13} /> Delete
          </Button>
          <Button variant="secondary" className="px-3 py-2 text-xs" onClick={() => onMove(-1)} disabled={saving || index <= 0} aria-label={`Move ${vendor.name} up`}><ArrowUp size={13} /></Button>
          <Button variant="secondary" className="px-3 py-2 text-xs" onClick={() => onMove(1)} disabled={saving || index >= total - 1} aria-label={`Move ${vendor.name} down`}><ArrowDown size={13} /></Button>
        </div>
      )}
    </Card>
  );
}

function ShopPage({ vendor, isDm, saving, canShop, onSelectProduct, onEditProduct, onDeleteProduct, onPatchProduct }: {
  vendor: ShopVendor;
  isDm: boolean;
  saving: boolean;
  canShop: boolean;
  onSelectProduct: (product: MarketProduct) => void;
  onEditProduct: (product: MarketProduct) => void;
  onDeleteProduct: (product: MarketProduct) => void;
  onPatchProduct: (product: MarketProduct, patch: Partial<ProductDraft>) => void;
}) {
  return (
    <div className="grid gap-4">
      {groupProducts(vendor.products).map(([section, products]) => (
        <Card key={section}>
          <div className="rule-title mb-3"><h3 className="text-sm font-black uppercase tracking-wider">{section}</h3></div>
          <ProductGrid products={products} isDm={isDm} saving={saving} canShop={canShop} onSelectProduct={onSelectProduct} onEditProduct={onEditProduct} onDeleteProduct={onDeleteProduct} onPatchProduct={onPatchProduct} />
        </Card>
      ))}
    </div>
  );
}

function SpellShopPage({ vendor, isDm, saving, canShop, onSelectProduct, onEditProduct, onDeleteProduct, onPatchProduct }: {
  vendor: ShopVendor;
  isDm: boolean;
  saving: boolean;
  canShop: boolean;
  onSelectProduct: (product: MarketProduct) => void;
  onEditProduct: (product: MarketProduct) => void;
  onDeleteProduct: (product: MarketProduct) => void;
  onPatchProduct: (product: MarketProduct, patch: Partial<ProductDraft>) => void;
}) {
  const [expandedSections, setExpandedSections] = useState<Set<string>>(() => new Set());
  function toggleSection(section: string) {
    setExpandedSections((current) => {
      const next = new Set(current);
      if (next.has(section)) next.delete(section);
      else next.add(section);
      return next;
    });
  }

  return (
    <div className="grid gap-3">
      {groupProducts(vendor.products).map(([section, products]) => {
        const spellType = spellTypeFromProductSection(section);
        const expanded = expandedSections.has(section);
        return (
          <Card key={section} className="overflow-hidden">
            <button
              type="button"
              onClick={() => toggleSection(section)}
              className="group w-full rounded-2xl border border-[var(--line)] bg-gradient-to-br from-[rgba(245,180,76,0.16)] via-black/10 to-[rgba(31,120,117,0.14)] p-4 text-left transition hover:border-[var(--brass)]/70"
            >
              <span className="flex items-start justify-between gap-3">
                <span className="min-w-0">
                  <span className="eyebrow">Spell Category</span>
                  <span className="mt-1 block text-xl font-black leading-tight">{spellType ? `${spellType} Spells` : section}</span>
                  <span className="mt-1 flex flex-wrap gap-2 text-xs font-bold text-[var(--muted)]">
                    <span>{products.filter((product) => product.available).length}/{products.length} available</span>
                    <span>{products.length} shown here</span>
                  </span>
                </span>
                <span className="rounded-full border border-[var(--line)] bg-black/25 p-2 text-[var(--brass)]">
                  {expanded ? <ChevronDown size={18} /> : <ChevronRight size={18} />}
                </span>
              </span>
            </button>
            {expanded && (
              <div className="mt-4">
                <ProductGrid products={products} isDm={isDm} saving={saving} canShop={canShop} onSelectProduct={onSelectProduct} onEditProduct={onEditProduct} onDeleteProduct={onDeleteProduct} onPatchProduct={onPatchProduct} />
              </div>
            )}
          </Card>
        );
      })}
    </div>
  );
}

function LibraryPage(props: {
  vendor: ShopVendor;
  isDm: boolean;
  saving: boolean;
  canShop: boolean;
  onSelectProduct: (product: MarketProduct) => void;
  onEditProduct: (product: MarketProduct) => void;
  onDeleteProduct: (product: MarketProduct) => void;
  onPatchProduct: (product: MarketProduct, patch: Partial<ProductDraft>) => void;
}) {
  const productGroups = groupProducts(props.vendor.products);
  return (
    <div className="grid gap-4">
      {productGroups.map(([section, products]) => (
        <Card key={section}>
          <div className="rule-title mb-3"><h3 className="text-sm font-black uppercase tracking-wider">{section}</h3></div>
          <ProductGrid {...props} products={products} />
        </Card>
      ))}
    </div>
  );
}

function BlacksmithPage(props: {
  vendor: ShopVendor;
  isDm: boolean;
  saving: boolean;
  canShop: boolean;
  onSelectProduct: (product: MarketProduct) => void;
  onEditProduct: (product: MarketProduct) => void;
  onDeleteProduct: (product: MarketProduct) => void;
  onPatchProduct: (product: MarketProduct, patch: Partial<ProductDraft>) => void;
  onCraft: (state: CraftModalState) => void;
}) {
  const { vendor, onCraft } = props;
  const productGroups = groupProducts(vendor.products);
  const recipeSections = Array.from(new Set(BLACKSMITH_RECIPES.map((recipe) => recipe.section)));

  return (
    <div className="grid gap-4">
      <Card>
        <div className="flex items-center gap-3">
          <span className="grid h-12 w-12 place-items-center rounded-2xl border border-[var(--brass)]/45 bg-[var(--brass)]/15 text-[var(--brass)]">
            <Hammer size={24} />
          </span>
          <div>
            <p className="eyebrow">Forge Services</p>
            <h3 className="text-2xl font-black">{vendor.name}</h3>
          </div>
        </div>
      </Card>

      {productGroups.map(([section, products]) => (
        <Card key={section}>
          <div className="rule-title mb-3"><h3 className="text-sm font-black uppercase tracking-wider">{section}</h3></div>
          <ProductGrid {...props} products={products} />
        </Card>
      ))}

      {recipeSections.map((section) => (
        <Card key={section}>
          <div className="rule-title mb-3"><h3 className="text-sm font-black uppercase tracking-wider">{section}</h3></div>
          <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
            {BLACKSMITH_RECIPES.filter((recipe) => recipe.section === section).map((recipe) => (
              <button
                key={recipe.key}
                type="button"
                onClick={() => onCraft({ mode: 'craft', service: 'blacksmith', recipe })}
                className="rounded-2xl border border-[var(--line)] bg-black/15 p-3 text-left transition hover:border-[var(--brass)] active:scale-[0.99]"
              >
                <span className="flex items-start gap-2">
                  <ItemIcon type={recipe.type} />
                  <span>
                    <span className="block font-black">{recipe.name}</span>
                    <span className="mt-1 block text-xs text-[var(--muted)]">{recipe.materialQuantity ? `${recipe.materialQuantity} material scale · ` : ''}{formatCoinValue(recipe.laborCoin)} labor{recipe.twoHanded ? ' · two-handed' : ''}</span>
                    {recipe.note && <span className="mt-1 block text-xs text-[var(--muted)]">{recipe.note}</span>}
                  </span>
                </span>
              </button>
            ))}
          </div>
        </Card>
      ))}

      <Card>
        <div className="rule-title mb-3"><h3 className="text-sm font-black uppercase tracking-wider">Mythril Services</h3></div>
        <div className="grid gap-2 sm:grid-cols-2">
          <Button variant="teal" onClick={() => onCraft({ mode: 'enhance', service: 'blacksmith' })}><Sparkles className="mr-2 inline" size={15} /> Enhance Mythril Weapon/Shield</Button>
          <Button variant="primary" onClick={() => onCraft({ mode: 'enchant', service: 'blacksmith' })}><WandSparkles className="mr-2 inline" size={15} /> Enchant Mythril Weapon</Button>
        </div>
      </Card>

      <Card>
        <div className="rule-title mb-3"><h3 className="text-sm font-black uppercase tracking-wider">Dragon Scale Refining</h3></div>
        <Button variant="primary" onClick={() => onCraft({ mode: 'dragon-scales', service: 'blacksmith' })}>
          <Hammer className="mr-2 inline" size={15} /> Forge Dragonscale Scale
        </Button>
      </Card>
    </div>
  );
}

function ArmoryPage(props: {
  vendor: ShopVendor;
  sharedMaterials: MarketProduct[];
  isDm: boolean;
  saving: boolean;
  canShop: boolean;
  onSelectProduct: (product: MarketProduct) => void;
  onEditProduct: (product: MarketProduct) => void;
  onDeleteProduct: (product: MarketProduct) => void;
  onPatchProduct: (product: MarketProduct, patch: Partial<ProductDraft>) => void;
  onCraft: (state: CraftModalState) => void;
}) {
  const { vendor, sharedMaterials, onCraft } = props;
  const recipeSections = Array.from(new Set(ARMORY_RECIPES.map((recipe) => recipe.section)));

  return (
    <div className="grid gap-4">
      <Card>
        <div className="flex items-center gap-3">
          <span className="grid h-12 w-12 place-items-center rounded-2xl border border-[var(--brass)]/45 bg-[var(--brass)]/15 text-[var(--brass)]">
            <ItemIcon type="armor" size={24} />
          </span>
          <div>
            <p className="eyebrow">Armor Services</p>
            <h3 className="text-2xl font-black">{vendor.name}</h3>
          </div>
        </div>
      </Card>

      <Card>
        <div className="rule-title mb-3"><h3 className="text-sm font-black uppercase tracking-wider">{ARMORY_SERVICE_SECTIONS[0]}</h3></div>
        <ProductGrid {...props} products={sharedMaterials} />
      </Card>

      {recipeSections.map((section) => (
        <Card key={section}>
          <div className="rule-title mb-3"><h3 className="text-sm font-black uppercase tracking-wider">{section}</h3></div>
          <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
            {ARMORY_RECIPES.filter((recipe) => recipe.section === section).map((recipe) => {
              const materialProduct = recipe.materialName ? materialProductByName(sharedMaterials, recipe.materialName) : null;
              const recipeMaterialClass = materialProduct ? rarityClass(materialProduct.rarity) : 'border-[var(--line)] bg-black/15';
              return (
              <button
                key={recipe.key}
                type="button"
                onClick={() => onCraft({ mode: 'craft', service: 'armory', recipe })}
                className={`rounded-2xl border p-3 text-left transition hover:border-[var(--brass)] active:scale-[0.99] ${recipeMaterialClass}`}
              >
                <span className="flex items-start gap-2">
                  <span className="grid shrink-0 justify-items-center gap-1 text-[var(--brass)]">
                    <ItemIcon type="armor" />
                    {materialProduct && <span className="text-[10px] font-black uppercase tracking-wide text-[var(--paper)]">{materialProduct.rarity}</span>}
                  </span>
                  <span>
                    <span className="block font-black">{recipe.name}</span>
                    <span className="mt-1 block text-xs text-[var(--muted)]">{recipe.materialQuantity ? `${recipe.materialQuantity} ${recipe.materialName} - ` : ''}{formatCoinValue(recipe.laborCoin)} labor</span>
                    {recipe.note && <span className="mt-1 block text-xs text-[var(--muted)]">{recipe.note}</span>}
                  </span>
                </span>
              </button>
              );
            })}
          </div>
        </Card>
      ))}

      <Card>
        <div className="rule-title mb-3"><h3 className="text-sm font-black uppercase tracking-wider">{ARMORY_SERVICE_SECTIONS[2]}</h3></div>
        <Button variant="teal" onClick={() => onCraft({ mode: 'enhance', service: 'armory' })}><Sparkles className="mr-2 inline" size={15} /> Enhance Mythril Armor</Button>
      </Card>

      <Card>
        <div className="rule-title mb-3"><h3 className="text-sm font-black uppercase tracking-wider">Dragon Scale Refining</h3></div>
        <Button variant="primary" onClick={() => onCraft({ mode: 'dragon-scales', service: 'armory' })}>
          <Hammer className="mr-2 inline" size={15} /> Forge Dragonscale Scale
        </Button>
      </Card>
    </div>
  );
}

function BreweryPage({ vendor, shopper, isDm, saving, canShop, onSelectProduct, onEditProduct, onDeleteProduct, onPatchProduct, onCitiesChanged, liveRefreshSignal, setError }: {
  vendor: ShopVendor;
  shopper: Character | null;
  isDm: boolean;
  saving: boolean;
  canShop: boolean;
  onSelectProduct: (product: MarketProduct) => void;
  onEditProduct: (product: MarketProduct) => void;
  onDeleteProduct: (product: MarketProduct) => void;
  onPatchProduct: (product: MarketProduct, patch: Partial<ProductDraft>) => void;
  onCitiesChanged: (payload: CitiesPayload) => void;
  liveRefreshSignal: number;
  setError: (message: string) => void;
}) {
  const [brewery, setBrewery] = useState<BreweryState>({ definitions: [], availableItems: [], houseAccess: { accessible: false, city: 'Calostrynn' } });
  const [breweryLoading, setBreweryLoading] = useState(false);
  const [brewSaving, setBrewSaving] = useState(false);
  const [strength, setStrength] = useState<typeof BREWERY_STRENGTHS[number]>('Lesser');
  const [propertyKey, setPropertyKey] = useState('');
  const [propertySelections, setPropertySelections] = useState<Record<string, number>>({});
  const [stabilizerSelections, setStabilizerSelections] = useState<Record<string, number>>({});
  const [catalystKey, setCatalystKey] = useState('');
  const [result, setResult] = useState<BrewResult | null>(null);
  const [brewConfirmOpen, setBrewConfirmOpen] = useState(false);
  const [brewResultOpen, setBrewResultOpen] = useState(false);

  const productGroups = groupProducts(vendor.products);

  useEffect(() => {
    if (!shopper || !canShop) {
      setBrewery({ definitions: [], availableItems: [], houseAccess: { accessible: false, city: 'Calostrynn' } });
      return;
    }

    let active = true;
    setBreweryLoading(true);
    fetch(`/api/cities/brewery?characterId=${encodeURIComponent(shopper.id)}&vendorKey=${encodeURIComponent(vendor.key)}`, { cache: 'no-store' })
      .then((response) => response.json().then((body) => ({ response, body })).catch(() => ({ response, body: {} })))
      .then(({ response, body }) => {
        if (!active) return;
        if (!response.ok) throw new Error(body.error ?? 'Brewery could not be loaded.');
        const normalized = normalizeBreweryState(body);
        setBrewery(normalized);
        setPropertyKey((current) => current || normalized.definitions[0]?.propertyKey || '');
      })
      .catch((loadError) => {
        if (active) setError(loadError instanceof Error ? loadError.message : 'Brewery could not be loaded.');
      })
      .finally(() => {
        if (active) setBreweryLoading(false);
      });

    return () => {
      active = false;
    };
  }, [canShop, liveRefreshSignal, setError, shopper, vendor.key]);

  useEffect(() => {
    setPropertySelections({});
    setStabilizerSelections({});
    setCatalystKey('');
    setResult(null);
    setBrewConfirmOpen(false);
    setBrewResultOpen(false);
  }, [shopper?.id, strength, propertyKey]);

  const selectedDefinition = brewery.definitions.find((definition) => definition.propertyKey === propertyKey) ?? brewery.definitions[0] ?? null;
  const requirements = breweryRequirements(strength);
  const ingredientEligibleItems = brewery.availableItems.filter((item) => item.type !== 'potion');
  const propertyItems = ingredientEligibleItems.filter((item) => selectedDefinition && item.properties.includes(selectedDefinition.propertyKey));
  const stabilizerItems = ingredientEligibleItems.filter((item) => item.properties.includes('Stabilizer'));
  const catalystItems = ingredientEligibleItems.filter((item) => item.properties.includes('Catalyst'));
  const selectedPropertyItems = selectedBreweryItems(propertyItems, propertySelections);
  const selectedStabilizerItems = selectedBreweryItems(stabilizerItems, stabilizerSelections);
  const selectedCatalystItem = catalystKey ? catalystItems.find((item) => breweryItemKey(item) === catalystKey) ?? null : null;
  const arcaneNectorCount = brewery.availableItems
    .filter((item) => item.name.toLowerCase() === 'arcane nector')
    .reduce((total, item) => total + item.quantity, 0);
  const propertyTotal = selectedTotal(propertySelections);
  const stabilizerTotal = selectedTotal(stabilizerSelections);
  const canBrew = canShop
    && Boolean(shopper && selectedDefinition)
    && arcaneNectorCount >= 1
    && propertyTotal >= requirements.property
    && stabilizerTotal >= requirements.stabilizer
    && !brewSaving;
  const brewPreviewInputs = [
    ...selectedPropertyItems.map(({ item, quantity }) => ({
      key: `property:${breweryItemKey(item)}`,
      name: item.name,
      type: item.type,
      rarity: item.rarity,
      quantity,
      note: `${sourceLabel(item.source)} - ${selectedDefinition?.potionName ?? 'Potion'} property`
    })),
    ...selectedStabilizerItems.map(({ item, quantity }) => ({
      key: `stabilizer:${breweryItemKey(item)}`,
      name: item.name,
      type: item.type,
      rarity: item.rarity,
      quantity,
      note: `${sourceLabel(item.source)} - stabilizer`
    })),
    {
      key: 'arcane-nector',
      name: 'Arcane Nector',
      type: 'potion' as ItemType,
      rarity: 'Common' as ItemRarity,
      quantity: 1,
      note: 'Required brewing base'
    },
    ...(selectedCatalystItem ? [{
      key: `catalyst:${breweryItemKey(selectedCatalystItem)}`,
      name: selectedCatalystItem.name,
      type: selectedCatalystItem.type,
      rarity: selectedCatalystItem.rarity,
      quantity: 1,
      note: `${sourceLabel(selectedCatalystItem.source)} - catalyst +${selectedCatalystItem.catalystBonus}`
    }] : [])
  ];
  const brewPreviewOutput = selectedDefinition ? {
    key: 'brewed-potion',
    name: `${strength} ${selectedDefinition.potionName} Potion`,
    type: 'potion' as ItemType,
    rarity: breweryPotionRarity(strength, selectedDefinition?.propertyKey),
    quantity: 1,
    note: selectedDefinition.description || selectedDefinition.automatedEffect || 'Quality is rolled when brewing completes.'
  } : null;

  async function runBrew() {
    if (!shopper || !selectedDefinition) return;
    setBrewSaving(true);
    setError('');
    try {
      const catalystSelection = catalystKey ? selectionFromKey(catalystKey) : null;
      const response = await fetch('/api/cities/brewery', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          characterId: shopper.id,
          vendorKey: vendor.key,
          strength,
          propertyKey: selectedDefinition.propertyKey,
          propertySelections: selectionsToPayload(propertySelections),
          stabilizerSelections: selectionsToPayload(stabilizerSelections),
          catalystSelection
        })
      });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(body.error ?? 'Brew failed.');
      const normalizedResult = normalizeBrewResult(body.result);
      setResult(normalizedResult);
      setBrewResultOpen(Boolean(normalizedResult));
      setBrewery(normalizeBreweryState(body.brewery));
      onCitiesChanged(normalizeCitiesPayload(body.cities));
      setPropertySelections({});
      setStabilizerSelections({});
      setCatalystKey('');
      setBrewConfirmOpen(false);
    } catch (brewError) {
      setError(brewError instanceof Error ? brewError.message : 'Brew failed.');
    } finally {
      setBrewSaving(false);
    }
  }

  return (
    <div className="grid gap-4">
      <Card>
        <div className="flex items-center gap-3">
          <span className="grid h-12 w-12 place-items-center rounded-2xl border border-[#56e2c2]/45 bg-[#56e2c2]/15 text-[#56e2c2]">
            <ItemIcon type="potion" size={24} />
          </span>
          <div>
            <p className="eyebrow">Brewing Services</p>
            <h3 className="text-2xl font-black">{vendor.name}</h3>
          </div>
        </div>
      </Card>

      {productGroups.map(([section, products]) => (
        <Card key={section}>
          <div className="rule-title mb-3"><h3 className="text-sm font-black uppercase tracking-wider">{section}</h3></div>
          <ProductGrid products={products} isDm={isDm} saving={saving} canShop={canShop} onSelectProduct={onSelectProduct} onEditProduct={onEditProduct} onDeleteProduct={onDeleteProduct} onPatchProduct={onPatchProduct} />
        </Card>
      ))}

      <Card>
        <div className="rule-title mb-3"><h3 className="text-sm font-black uppercase tracking-wider">Brew Potion</h3></div>
        {!shopper ? (
          <div className="rounded-2xl border border-[var(--line)] bg-black/15 p-4 text-sm font-bold text-[var(--muted)]">Choose a brewing character first.</div>
        ) : breweryLoading ? (
          <div className="grid h-28 place-items-center rounded-2xl border border-[var(--line)] bg-black/10 text-[var(--muted)]"><RefreshCw className="animate-spin" size={18} /></div>
        ) : (
          <div className="grid gap-4">
            <div className="grid gap-2 sm:grid-cols-3">
              <label>
                <span className="mb-1 block text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">Strength</span>
                <SelectField value={strength} onChange={(event) => setStrength(event.target.value as typeof BREWERY_STRENGTHS[number])}>
                  {BREWERY_STRENGTHS.map((option) => <option key={option} value={option}>{option}</option>)}
                </SelectField>
              </label>
              <label className="sm:col-span-2">
                <span className="mb-1 block text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">Potion</span>
                <SelectField value={propertyKey} onChange={(event) => setPropertyKey(event.target.value)}>
                  {brewery.definitions.map((definition) => <option key={definition.propertyKey} value={definition.propertyKey}>{definition.potionName} Potion</option>)}
                </SelectField>
              </label>
            </div>

            <div className="grid gap-2 sm:grid-cols-4">
              <SoftCard><p className="eyebrow">Ingredients</p><p className="font-black">{propertyTotal}/{requirements.property}</p></SoftCard>
              <SoftCard><p className="eyebrow">Stabilizers</p><p className="font-black">{stabilizerTotal}/{requirements.stabilizer}</p></SoftCard>
              <SoftCard><p className="eyebrow">Arcane Nector</p><p className={`font-black ${arcaneNectorCount >= 1 ? 'text-[var(--teal)]' : 'text-[var(--red)]'}`}>{arcaneNectorCount}/1</p></SoftCard>
              <SoftCard><p className="eyebrow">House</p><p className="font-black">{brewery.houseAccess.accessible ? 'Accessible' : 'Unavailable'}</p></SoftCard>
            </div>

            <BreweryIngredientPicker
              title={`${selectedDefinition?.potionName ?? 'Potion'} ingredients`}
              items={propertyItems}
              selections={propertySelections}
              onChange={setPropertySelections}
            />
            <BreweryIngredientPicker
              title="Stabilizers"
              items={stabilizerItems}
              selections={stabilizerSelections}
              onChange={setStabilizerSelections}
            />

            <div className="rounded-2xl border border-[var(--line)] bg-black/10 p-3">
              <label>
                <span className="mb-1 block text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">Catalyst</span>
                <SelectField value={catalystKey} onChange={(event) => setCatalystKey(event.target.value)}>
                  <option value="">No catalyst</option>
                  {catalystItems.map((item) => (
                    <option key={breweryItemKey(item)} value={breweryItemKey(item)}>
                      {item.name} · +{item.catalystBonus} · {item.rarity} · {sourceLabel(item.source)} x{item.quantity}
                    </option>
                  ))}
                </SelectField>
              </label>
            </div>

            {result && (
              <div className={`rounded-2xl border p-4 ${result.success ? 'border-[var(--teal)]/40 bg-[var(--teal)]/10' : 'border-[var(--red)]/40 bg-[var(--red)]/10'}`}>
                <p className="font-black">{result.success ? 'Brew successful' : 'Brew failed'}</p>
                <p className="mt-1 text-sm text-[var(--muted)]">d20 {result.d20} + Alchemy {result.alchemyBonus} + Catalyst {result.catalystBonus} = {result.total}</p>
                {result.item && <p className="mt-2 text-sm font-black text-[var(--brass)]">Created {result.item.name}</p>}
                {result.quality && <p className="mt-1 text-xs font-black uppercase text-[var(--teal)]">Quality: {result.quality}</p>}
              </div>
            )}

            <Button variant="primary" disabled={!canBrew} onClick={() => setBrewConfirmOpen(true)}>
              <Sparkles className="mr-2 inline" size={15} /> Brew
            </Button>
          </div>
        )}
      </Card>

      {brewConfirmOpen && brewPreviewOutput && (
        <Modal title="Confirm Brew" onClose={() => setBrewConfirmOpen(false)}>
          <div className="grid gap-4">
            <div className="rounded-2xl border border-[#56e2c2]/30 bg-[#56e2c2]/10 p-3">
              <p className="font-black">{strength} {selectedDefinition?.potionName} Potion</p>
              <p className="mt-1 text-xs font-bold text-[var(--muted)]">
                Uses {propertyTotal}/{requirements.property} matching ingredients and {stabilizerTotal}/{requirements.stabilizer} stabilizers.
              </p>
            </div>
            <div className="grid items-center gap-3 md:grid-cols-[1fr_auto_1fr]">
              <div className="grid gap-2">
                <p className="eyebrow">Consuming</p>
                {brewPreviewInputs.map((item) => <CraftPreviewItem key={item.key} item={item} />)}
              </div>
              <div className="grid place-items-center text-[var(--brass)]">
                <ArrowRightCraft />
              </div>
              <div className="grid gap-2">
                <p className="eyebrow">Brewing</p>
                <CraftPreviewItem item={brewPreviewOutput} featured />
              </div>
            </div>
            <div className="grid grid-cols-2 gap-2">
              <Button variant="secondary" onClick={() => setBrewConfirmOpen(false)}>Back</Button>
              <Button variant="primary" disabled={!canBrew} onClick={runBrew}>Confirm Brew</Button>
            </div>
          </div>
        </Modal>
      )}

      {brewResultOpen && result && (
        <Modal title={result.success ? 'Brew Successful' : 'Brew Failed'} onClose={() => setBrewResultOpen(false)}>
          <div className="grid gap-4">
            <div className={`rounded-2xl border p-4 ${result.success ? 'border-[var(--teal)]/45 bg-[var(--teal)]/10' : 'border-[var(--red)]/45 bg-[var(--red)]/10'}`}>
              <p className="text-lg font-black">{result.success ? 'The potion held together.' : 'The brew collapsed.'}</p>
              <p className="mt-2 text-sm font-bold text-[var(--muted)]">
                d20 {result.d20} + Alchemy {result.alchemyBonus} + Catalyst {result.catalystBonus} = {result.total}
              </p>
            </div>
            {result.item && (
              <CraftPreviewItem
                featured
                item={{
                  key: result.item.id,
                  name: result.item.name,
                  type: result.item.type,
                  rarity: result.item.rarity,
                  quantity: result.item.quantity,
                  note: result.quality ? `Quality: ${result.quality}` : potionEffectText(result.item) || 'Added to inventory.'
                }}
              />
            )}
            {!result.item && (
              <div className="rounded-2xl border border-[var(--line)] bg-black/15 p-3 text-sm font-bold text-[var(--muted)]">
                Ingredients were consumed and no potion was created.
              </div>
            )}
            <Button variant="primary" onClick={() => setBrewResultOpen(false)}>Done</Button>
          </div>
        </Modal>
      )}
    </div>
  );
}

function BreweryIngredientPicker({ title, items, selections, onChange }: {
  title: string;
  items: BreweryAvailableItem[];
  selections: Record<string, number>;
  onChange: (next: Record<string, number>) => void;
}) {
  return (
    <div className="rounded-2xl border border-[var(--line)] bg-black/10 p-3">
      <div className="mb-2 flex items-center justify-between gap-2">
        <p className="eyebrow">{title}</p>
        <span className="text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">{items.length} options</span>
      </div>
      {items.length ? (
        <div className="thin-scrollbar grid max-h-72 gap-2 overflow-y-auto pr-1">
          {items.map((item) => {
            const key = breweryItemKey(item);
            return (
              <div key={key} className={`grid gap-2 rounded-2xl border p-3 sm:grid-cols-[1fr_7rem] ${rarityClass(item.rarity)}`}>
                <div className="flex min-w-0 items-start gap-2">
                  <span className="mt-1 text-[var(--brass)]"><ItemIcon type={item.type} size={17} /></span>
                  <div className="min-w-0">
                    <p className="font-black leading-5">{item.name}</p>
                    <p className="mt-1 text-xs text-[var(--muted)]">{sourceLabel(item.source)} · {item.rarity} · available {item.quantity}</p>
                    <p className="mt-1 text-[10px] font-bold uppercase tracking-wide text-[var(--muted)]">{item.properties.join(' · ')}</p>
                  </div>
                </div>
                <NumberInput
                  min={0}
                  max={item.quantity}
                  step={1}
                  value={selections[key] ?? 0}
                  onValueChange={(quantity) => onChange({ ...selections, [key]: Math.min(item.quantity, Math.max(0, quantity)) })}
                />
              </div>
            );
          })}
        </div>
      ) : (
        <div className="rounded-xl border border-[var(--line)] bg-black/15 p-3 text-sm font-bold text-[var(--muted)]">
          No valid ingredients available.
        </div>
      )}
    </div>
  );
}

function ProductGrid({ products, isDm, saving, canShop, onSelectProduct, onEditProduct, onDeleteProduct, onPatchProduct }: {
  products: MarketProduct[];
  isDm: boolean;
  saving: boolean;
  canShop: boolean;
  onSelectProduct: (product: MarketProduct) => void;
  onEditProduct: (product: MarketProduct) => void;
  onDeleteProduct: (product: MarketProduct) => void;
  onPatchProduct: (product: MarketProduct, patch: Partial<ProductDraft>) => void;
}) {
  return (
    <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
      {products.map((product) => {
        const disabled = !hasUsableStock(product);
        const manaBadge = spellManaBadgeText(product);
        return (
          <button
            key={product.id}
            type="button"
            onClick={() => {
              if (!disabled && canShop) onSelectProduct(product);
            }}
            className={`relative rounded-2xl border p-3 text-left transition active:scale-[0.99] ${productCardClass(product)} ${disabled ? 'opacity-45' : ''}`}
          >
            <span className="mb-2 flex items-start justify-between gap-3">
              <span className="flex min-w-0 items-center gap-2">
                <span className="text-[var(--brass)]"><ItemIcon type={product.type} /></span>
                <span className="min-w-0">
                  <span className="block break-words font-black leading-tight">{product.name}</span>
                  <span className="block text-xs text-[var(--muted)]">{isSpellProduct(product) ? product.section.replace(/\s+Spells$/i, '') : `${product.type} · ${product.rarity}`}</span>
                </span>
              </span>
              {isDm && (
                <span className="flex shrink-0 gap-1">
                  <span role="button" tabIndex={0} aria-disabled={saving} onClick={(event) => { event.stopPropagation(); if (!saving) onPatchProduct(product, { available: !product.available }); }} className={`rounded-lg border border-[var(--line)] bg-black/25 p-2 text-[var(--muted)] ${saving ? 'pointer-events-none opacity-50' : ''}`}>
                    {product.available ? <Eye size={13} /> : <EyeOff size={13} />}
                  </span>
                  <span role="button" tabIndex={0} aria-disabled={saving} onClick={(event) => { event.stopPropagation(); if (!saving) onEditProduct(product); }} className={`rounded-lg border border-[var(--line)] bg-black/25 p-2 text-[var(--muted)] ${saving ? 'pointer-events-none opacity-50' : ''}`}><Pencil size={13} /></span>
                  <span role="button" tabIndex={0} aria-disabled={saving} onClick={(event) => { event.stopPropagation(); if (!saving) onDeleteProduct(product); }} className={`rounded-lg border border-[var(--red)]/35 bg-[var(--red)]/10 p-2 text-[var(--red)] ${saving ? 'pointer-events-none opacity-50' : ''}`}><Trash2 size={13} /></span>
                </span>
              )}
            </span>
            <p className="line-clamp-2 min-h-8 text-xs text-[var(--muted)]">{productEffectText(product) || product.description}</p>
            {manaBadge && (
              <span className="mt-2 inline-flex rounded-lg border border-[var(--brass)]/35 bg-[var(--brass)]/10 px-2 py-1 text-[10px] font-black uppercase tracking-wide text-[var(--brass)]">
                Mana: {manaBadge}
              </span>
            )}
            {product.type === 'potion' && productEffectText(product) && (
              <span className="mt-2 block rounded-lg border border-[#56e2c2]/25 bg-[#56e2c2]/10 px-2 py-1 text-[10px] font-black uppercase tracking-wide text-[#56e2c2]">
                {productEffectText(product)}
              </span>
            )}
            <span className="mt-3 flex items-center justify-between gap-2 text-xs font-black">
              <span className="text-[var(--brass)]">{formatProductPrice(product)}</span>
              <span className="text-[var(--muted)]">{product.stockQuantity === null ? 'Stock ∞' : `Stock ${product.stockQuantity}`}</span>
            </span>
            {disabled && <span className="mt-2 block text-[10px] font-black uppercase text-[var(--muted)]">{unavailableReason(product)}</span>}
            {!canShop && !disabled && <span className="mt-2 block text-[10px] font-black uppercase text-[var(--muted)]">Unavailable from current location</span>}
          </button>
        );
      })}
    </div>
  );
}

function ArrowRightCraft() {
  return (
    <div className="relative grid h-16 w-full min-w-24 place-items-center md:h-24 md:w-24">
      <span className="absolute h-1 w-full rounded-full bg-gradient-to-r from-transparent via-[var(--brass)] to-[var(--brass)] shadow-[0_0_18px_rgba(209,168,91,.45)]" />
      <span className="absolute right-1 h-5 w-5 rotate-45 border-r-4 border-t-4 border-[var(--brass)] shadow-[0_0_18px_rgba(209,168,91,.45)]" />
      <Sparkles size={20} className="relative rounded-full bg-[#1a100c] p-0.5 text-[var(--brass)]" />
    </div>
  );
}

function CraftPreviewItem({ item, featured = false }: {
  item: {
    key: string;
    name: string;
    type: ItemType;
    rarity: ItemRarity;
    quantity: number | string;
    note?: string;
  };
  featured?: boolean;
}) {
  return (
    <div className={`rarity-card rounded-2xl border p-3 ${rarityClass(item.rarity)} ${featured ? 'ring-2 ring-[var(--brass)] ring-offset-2 ring-offset-[#120907]' : ''}`}>
      <div className="relative z-10 flex items-start gap-3">
        <span className="grid h-11 w-11 shrink-0 place-items-center rounded-xl bg-black/25 text-[var(--brass)]"><ItemIcon type={item.type} size={22} /></span>
        <span className="min-w-0 flex-1">
          <span className="block break-words text-sm font-black leading-5">{item.name}</span>
          <span className="mt-1 block text-xs font-black uppercase tracking-wider text-[var(--muted)]">{item.rarity} {item.type} - x{item.quantity}</span>
          {item.note && <span className="mt-2 block text-xs leading-5 text-[var(--paper)]">{item.note}</span>}
        </span>
      </div>
    </div>
  );
}

function DragonScaleInputPicker({ items, selections, onChange, total }: {
  items: CraftSourceItem[];
  selections: Record<string, number>;
  onChange: (next: Record<string, number>) => void;
  total: number;
}) {
  return (
    <div className="grid gap-3">
      <div className="rounded-2xl border border-[var(--line)] bg-black/15 p-3">
        <p className="eyebrow">Selected</p>
        <p className={`mt-1 text-2xl font-black ${total >= 25 ? 'text-[var(--teal)]' : 'text-[var(--brass)]'}`}>{formatQuantity(total)} / 25+</p>
        {total >= 25 && (
          <p className="mt-1 text-xs font-black uppercase tracking-wider text-[var(--muted)]">
            Creates {formatQuantity(dragonScaleOutputQuantity(total))} scale{dragonScaleOutputQuantity(total) === 1 ? '' : 's'}
            {dragonScaleReturnedQuantity(total) > 0 ? `, returns ${formatQuantity(dragonScaleReturnedQuantity(total))}` : ''}
          </p>
        )}
      </div>
      {items.length ? (
        <div className="thin-scrollbar grid max-h-[55vh] gap-2 overflow-y-auto pr-1">
          {items.map((entry) => {
            const key = sourceItemKey(entry);
            const selected = Math.min(entry.item.quantity, Math.max(0, selections[key] ?? 0));
            return (
              <div key={key} className={`grid gap-3 rounded-2xl border p-3 sm:grid-cols-[1fr_8rem] ${rarityClass(entry.item.rarity)}`}>
                <div className="flex min-w-0 items-start gap-3">
                  <span className="grid h-10 w-10 shrink-0 place-items-center rounded-xl bg-black/25 text-[var(--brass)]"><ItemIcon type={entry.item.type} size={20} /></span>
                  <div className="min-w-0">
                    <p className="break-words font-black leading-5">{entry.item.displayName || entry.item.name}</p>
                    <p className="mt-1 text-xs font-bold text-[var(--muted)]">{entry.source === 'house' ? 'House storage' : 'Inventory'} - available {formatQuantity(entry.item.quantity)}</p>
                  </div>
                </div>
                <NumberInput
                  min={0}
                  max={entry.item.quantity}
                  step={1}
                  value={selected}
                  onValueChange={(quantity) => onChange({ ...selections, [key]: Math.min(entry.item.quantity, Math.max(0, Math.floor(quantity))) })}
                />
              </div>
            );
          })}
        </div>
      ) : (
        <div className="rounded-2xl border border-[var(--line)] bg-black/15 p-3 text-sm font-bold text-[var(--muted)]">
          No compatible dragon scale fragments are available.
        </div>
      )}
    </div>
  );
}

function CraftRecipeForm({ service, shopper, recipe, materials, inventory, houseItems, wallet, materialProductId, setMaterialProductId }: {
  service: ForgeService;
  shopper: Character | null;
  recipe: CraftRecipe;
  materials: MarketProduct[];
  inventory: InventoryItem[];
  houseItems: InventoryItem[];
  wallet: WalletBalance[];
  materialProductId: string;
  setMaterialProductId: (value: string) => void;
}) {
  const plan = buildMaterialPlan(recipe, materials, materialProductId, inventory, houseItems);
  const laborCost = recipeLaborCost(service, shopper, recipe);
  const totalCost = plan.materialCost + laborCost;
  const walletCoin = walletTotalCoin(wallet);
  const discountLabel = service === 'armory' ? 'Armor-clad discount' : 'Blacksmith discount';
  return (
    <div className="grid gap-3">
      <SoftCard>
        <p className="text-sm font-black">{recipe.name}</p>
        <p className="mt-1 text-xs text-[var(--muted)]">{recipe.materialQuantity ? `${recipe.materialQuantity} material scale required.` : 'No material scale required.'}</p>
      </SoftCard>
      {recipe.materialQuantity > 0 && recipe.materialName && !plan.product && (
        <SoftCard>
          <p className="eyebrow">Material</p>
          <p className="font-black">{recipe.materialName}</p>
          {!plan.product && <p className="mt-1 text-xs font-bold text-[var(--red)]">Shared material row missing from shop assets.</p>}
        </SoftCard>
      )}
      {recipe.materialQuantity > 0 && !recipe.materialName && (
        <label>
          <span className="mb-1 block text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">Material</span>
          <SelectField value={materialProductId} onChange={(event) => setMaterialProductId(event.target.value)}>
            <option value="">Choose material scale</option>
            {materials.map((product) => <option key={product.id} value={product.id}>{product.name} · {formatProductPrice(product)} each · stock {product.stockQuantity ?? '∞'}</option>)}
          </SelectField>
        </label>
      )}
      {recipe.materialQuantity > 0 && plan.product && <MaterialRequirementCard plan={plan} />}
      {recipe.materialQuantity > 0 && (
        <div className="grid gap-2 sm:grid-cols-4">
          <SoftCard><p className="eyebrow">Required</p><p className="font-black">{plan.required}</p></SoftCard>
          <SoftCard><p className="eyebrow">Available</p><p className="font-black">{plan.carried}</p></SoftCard>
          <SoftCard><p className="eyebrow">Shop buys</p><p className="font-black">{plan.buyQuantity}</p></SoftCard>
          <SoftCard><p className="eyebrow">Leftover</p><p className="font-black">{plan.leftover}</p></SoftCard>
        </div>
      )}
      <div className="grid gap-2 sm:grid-cols-3">
        <SoftCard><p className="eyebrow">Materials</p><p className="font-black">{formatCoinValue(plan.materialCost)}</p></SoftCard>
        <SoftCard>
          <p className="eyebrow">Labor</p>
          <p className="font-black">{formatCoinValue(laborCost)}</p>
          {recipe.laborCoin > 0 && laborCost === 0 && <span className="text-[10px] font-black uppercase tracking-wide text-[var(--teal)]">{discountLabel}</span>}
        </SoftCard>
        <SoftCard><p className="eyebrow">Total</p><p className="font-black text-[var(--brass)]">{formatCoinValue(totalCost)}</p></SoftCard>
      </div>
      {recipe.materialQuantity > 0 && !plan.canCover && <div className="rounded-2xl border border-[var(--red)]/40 bg-[var(--red)]/10 p-3 text-sm text-[var(--red)]">{plan.reason}</div>}
      {walletCoin < totalCost && <div className="rounded-2xl border border-[var(--red)]/40 bg-[var(--red)]/10 p-3 text-sm text-[var(--red)]">Not enough currency.</div>}
    </div>
  );
}

function ForgeSelectableItemCard({ item, selected = false, sourceLabel, quantity, onClick }: {
  item: InventoryItem;
  selected?: boolean;
  sourceLabel?: string;
  quantity?: number;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`rounded-2xl border p-3 text-left transition hover:scale-[1.01] ${rarityClass(item.rarity)} ${selected ? 'ring-2 ring-[var(--brass)] ring-offset-2 ring-offset-[#120a08]' : ''}`}
    >
      <span className="flex min-w-0 items-start gap-3">
        <span className="grid h-11 w-11 shrink-0 place-items-center rounded-xl bg-black/25 text-[var(--brass)]"><ItemIcon type={item.type} size={21} /></span>
        <span className="min-w-0">
          <span className="block break-words font-black leading-5">{item.displayName || item.name}</span>
          <span className="mt-1 block text-xs font-black uppercase tracking-wide text-[var(--muted)]">
            {sourceLabel ? `${sourceLabel} - ` : ''}{item.rarity} {item.type}{typeof quantity === 'number' ? ` - Qty ${formatQuantity(quantity)}` : ''}
          </span>
          {item.enhancementCount > 0 && <span className="mt-1 block text-xs font-black text-[var(--brass)]">{item.enhancementCount}/3 enhancements</span>}
        </span>
      </span>
    </button>
  );
}

function MythrilServiceForm({ service, mode, shopper, inventory, runeItems, targetItemId, runeItemKey, runeQuantity, setRuneQuantity, modifier, onOpenTargetPicker, onOpenRunePicker, onOpenStatPicker }: {
  service: ForgeService;
  mode: 'enhance' | 'enchant';
  shopper: Character | null;
  inventory: InventoryItem[];
  runeItems: CraftSourceItem[];
  targetItemId: string;
  runeItemKey: string;
  runeQuantity: number;
  setRuneQuantity: (value: number) => void;
  modifier: string;
  onOpenTargetPicker: () => void;
  onOpenRunePicker: () => void;
  onOpenStatPicker: () => void;
}) {
  const minimumRunes = mode === 'enchant' ? enchantmentMinimumRunes(shopper) : 1;
  const requiredRunes = normalizedRuneQuantity(mode, shopper, runeQuantity);
  const targets = mode === 'enhance'
    ? service === 'armory' ? eligibleArmoryEnhancementTargets(inventory) : eligibleBlacksmithEnhancementTargets(inventory)
    : eligibleEnchantmentTargets(inventory);
  const target = targets.find((item) => item.id === targetItemId) ?? null;
  const runeEntry = runeItems.find((entry) => sourceItemKey(entry) === runeItemKey) ?? null;
  const maxRunes = Math.max(minimumRunes, Math.floor(runeEntry?.item.quantity ?? minimumRunes));
  const cappedRunes = mode === 'enchant' ? Math.min(requiredRunes, maxRunes) : 1;
  const selectedModifier = ENHANCEMENT_OPTIONS.find((option) => option.key === modifier) ?? ENHANCEMENT_OPTIONS[0];
  return (
    <div className="grid gap-3">
      <div className="grid gap-3 sm:grid-cols-2">
        <SoftCard>
          <div className="flex items-start justify-between gap-3">
            <div>
              <p className="eyebrow">Target item</p>
              <p className="mt-1 text-sm font-bold text-[var(--muted)]">
                {mode === 'enhance' ? 'Choose one eligible item with fewer than 3 enhancements.' : 'Choose one enchantable, unenhanced item.'}
              </p>
            </div>
            <Button variant="secondary" className="px-3 py-2 text-xs" onClick={onOpenTargetPicker}>Choose</Button>
          </div>
          <div className="mt-3">
            {target ? <ForgeSelectableItemCard item={target} selected onClick={onOpenTargetPicker} /> : (
              <div className="rounded-2xl border border-[var(--line)] bg-black/15 p-3 text-sm font-bold text-[var(--muted)]">No item selected.</div>
            )}
          </div>
        </SoftCard>
        <SoftCard>
          <div className="flex items-start justify-between gap-3">
            <div>
              <p className="eyebrow">Rune</p>
              <p className="mt-1 text-sm font-bold text-[var(--muted)]">{mode === 'enhance' ? 'Choose one rune to consume.' : `Choose ${minimumRunes}+ matching runes to determine the spell.`}</p>
            </div>
            <Button variant="secondary" className="px-3 py-2 text-xs" onClick={onOpenRunePicker}>Choose</Button>
          </div>
          <div className="mt-3">
            {runeEntry ? (
              <ForgeSelectableItemCard
                item={runeEntry.item}
                selected
                sourceLabel={runeEntry.source === 'house' ? 'House storage' : 'Inventory'}
                quantity={runeEntry.item.quantity}
                onClick={onOpenRunePicker}
              />
            ) : (
              <div className="rounded-2xl border border-[var(--line)] bg-black/15 p-3 text-sm font-bold text-[var(--muted)]">No rune selected.</div>
            )}
          </div>
        </SoftCard>
      </div>
      {mode === 'enchant' && (
        <label>
          <span className="mb-1 block text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">Runes committed</span>
          <NumberInput
            min={minimumRunes}
            max={maxRunes}
            step={1}
            value={cappedRunes}
            emptyFallback={minimumRunes}
            onValueChange={(value) => setRuneQuantity(Math.max(minimumRunes, Math.min(maxRunes, Math.floor(value))))}
          />
        </label>
      )}
      {mode === 'enhance' && (
        <SoftCard>
          <div className="flex items-center justify-between gap-3">
            <div>
              <p className="eyebrow">Stat bonus</p>
              <p className="mt-1 font-black">+1 {selectedModifier.label}</p>
            </div>
            <Button variant="secondary" className="px-3 py-2 text-xs" onClick={onOpenStatPicker}>Choose stat</Button>
          </div>
        </SoftCard>
      )}
      <div className="rounded-2xl border border-[var(--line)] bg-black/15 p-3 text-sm text-[var(--muted)]">
        {mode === 'enhance'
          ? 'Consumes the chosen item and 1 chosen rune, then returns the item with the selected +1 modifier. Max 3 enhancements per item.'
          : `Consumes the chosen item and ${cappedRunes} chosen rune${cappedRunes === 1 ? '' : 's'}, then returns the item with a spell based on rune affinity and committed rune count.`}
      </div>
      {!targets.length && <div className="rounded-2xl border border-[var(--red)]/40 bg-[var(--red)]/10 p-3 text-sm text-[var(--red)]">No eligible target items are available.</div>}
      {!runeItems.length && <div className="rounded-2xl border border-[var(--red)]/40 bg-[var(--red)]/10 p-3 text-sm text-[var(--red)]">No compatible runes are available.</div>}
      {runeEntry && runeEntry.item.quantity < requiredRunes && <div className="rounded-2xl border border-[var(--red)]/40 bg-[var(--red)]/10 p-3 text-sm text-[var(--red)]">That rune stack only has {formatQuantity(runeEntry.item.quantity)} available.</div>}
    </div>
  );
}
