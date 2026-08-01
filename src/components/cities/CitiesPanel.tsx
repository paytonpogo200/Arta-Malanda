'use client';

import { useCallback, useEffect, useMemo, useState, type FormEvent } from 'react';
import { ArrowDown, ArrowLeft, ArrowUp, ChevronDown, ChevronRight, Eye, EyeOff, Hammer, Lock, PackageCheck, Pencil, RefreshCw, ShoppingBag, Sparkles, Store, Unlock, Users, WandSparkles } from 'lucide-react';
import { ItemIcon } from '@/components/inventory/ItemIcon';
import { Button } from '@/components/ui/Button';
import { Card, SoftCard } from '@/components/ui/Card';
import { SelectField, TextAreaField, TextField } from '@/components/ui/Field';
import { Modal } from '@/components/ui/Modal';
import { NumberInput } from '@/components/ui/NumberInput';
import { formatCoinValue, normalizeCitiesPayload, type CitiesPayload } from '@/features/cities/data';
import { normalizeHousePayload } from '@/features/houses/data';
import { ITEM_TYPES, normalizeCharacterInventoryPayload, normalizeInventoryItem, quantityStepForItem } from '@/features/inventory/data';
import { useLiveRefresh } from '@/hooks/useLiveRefresh';
import { potionEffectText } from '@/lib/utils/potions';
import { rarityClass, rarityOptions } from '@/lib/utils/rarity';
import { spellTypeClass, spellTypeFromProductSection, spellTypes } from '@/lib/utils/spells';
import type { Character, InventoryItem, ItemRarity, ItemType, MarketProduct, Profile, ShopVendor, WalletBalance } from '@/lib/types';

const EMPTY_PAYLOAD: CitiesPayload = { characters: [], cities: [], vendors: [] };

type ProductDraft = {
  name: string;
  description: string;
  type: ItemType;
  rarity: ItemRarity;
  priceCoin: number;
  stockQuantity: number;
  available: boolean;
  section: string;
  quantityStep: number;
};

type VendorDraft = {
  name: string;
  npcName: string;
  facility: string;
  category: string;
  hidden: boolean;
  order: number;
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
  | { mode: 'enchant'; service: 'blacksmith' };

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
const RUNE_SECTION_ALIASES = new Set(['runes', 'rune']);
const CALOSTRYNN_ACTIVE_VENDOR_KEYS = new Set(['calostrynn-armory', 'calostrynn-brewery', 'calostrynn-blacksmith', 'calostrynn-city-market', 'calostrynn-library', 'calostrynn-spells']);
const MAGICAL_RESEARCH_TYPES = spellTypes;
const BREWERY_STRENGTHS = ['Lesser', 'Greater', 'Greatest'] as const;

function numberFromUnknown(value: unknown, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function isMythrilItem(item: InventoryItem) {
  return `${item.material ?? ''} ${item.name}`.toLowerCase().includes('mythril');
}
const ENHANCEMENT_OPTIONS = [
  { key: 'strength', label: 'Strength', catalyst: 'Titanvine Root' },
  { key: 'accuracy', label: 'Accuracy', catalyst: 'Hawkeye Blossom' },
  { key: 'intelligence', label: 'Intelligence', catalyst: 'Star Sage Orchid' },
  { key: 'vitality', label: 'Vitality', catalyst: 'Heartwood Sprout' },
  { key: 'magic_resist', label: 'Magic Resist', catalyst: 'Null Fern' },
  { key: 'stealth', label: 'Stealth', catalyst: 'Shade Moss' }
] as const;

function productToDraft(product: MarketProduct): ProductDraft {
  return {
    name: product.name,
    description: product.description,
    type: product.type,
    rarity: product.rarity,
    priceCoin: product.priceCoin,
    stockQuantity: product.stockQuantity ?? 0,
    available: product.available,
    section: product.section || '',
    quantityStep: product.quantityStep || quantityStepForItem(product)
  };
}

function vendorToDraft(vendor: ShopVendor): VendorDraft {
  return {
    name: vendor.name,
    npcName: vendor.npcName,
    facility: vendor.facility,
    category: vendor.category,
    hidden: vendor.hidden,
    order: vendor.order
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
  return Boolean(spellTypeFromProductSection(product.section));
}

function isMagicalResearchProduct(product: MarketProduct) {
  return product.key === 'library-magical-research' || product.name.toLowerCase() === 'magical research';
}

function isSinglePurchaseProduct(product: MarketProduct) {
  return isSpellProduct(product) || isMagicalResearchProduct(product);
}

function purchaseActionLabel(product: MarketProduct) {
  if (isSpellProduct(product)) return 'Learn';
  if (isMagicalResearchProduct(product)) return 'Research';
  return 'Buy';
}

function productEffectText(product: MarketProduct) {
  if (product.type === 'potion') return potionEffectText(product);
  if (isSpellProduct(product)) return product.description;
  return '';
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

function runeProducts(vendor: ShopVendor) {
  return vendor.products.filter((product) => RUNE_SECTION_ALIASES.has(productSection(product).toLowerCase()) || product.type === 'rune');
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
  return vendor.cityKey !== 'calostrynn' || CALOSTRYNN_ACTIVE_VENDOR_KEYS.has(vendor.key);
}

function sameCityName(left: string | null | undefined, right: string | null | undefined) {
  const normalizedLeft = (left ?? '').trim().toLowerCase();
  const normalizedRight = (right ?? '').trim().toLowerCase();
  return normalizedLeft.length > 0 && normalizedLeft === normalizedRight;
}

function forgeMaterialProducts(vendors: ShopVendor[], service: ForgeService) {
  const vendor = vendors.find(service === 'armory' ? isArmoryVendor : isBlacksmithVendor);
  const source = vendor ? materialProducts(vendor) : vendors.flatMap(materialProducts);
  return uniqueProductsByName(source)
    .filter((product) => FORGE_MATERIAL_ORDER.some((name) => name.toLowerCase() === product.name.toLowerCase()))
    .sort((a, b) => FORGE_MATERIAL_ORDER.findIndex((name) => name.toLowerCase() === a.name.toLowerCase()) - FORGE_MATERIAL_ORDER.findIndex((name) => name.toLowerCase() === b.name.toLowerCase()));
}

function sharedForgeRuneProducts(vendors: ShopVendor[]) {
  const blacksmith = vendors.find(isBlacksmithVendor);
  const source = blacksmith ? runeProducts(blacksmith) : vendors.flatMap(runeProducts);
  return uniqueProductsByName(source).sort((a, b) => a.name.localeCompare(b.name));
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

function walletTotalCoin(wallet: WalletBalance[]) {
  const values: Record<string, number> = { coin: 1, callis: 10, callor: 100, cal: 10000 };
  return wallet.reduce((total, entry) => total + entry.amount * (values[entry.unit.key.toLowerCase()] ?? 0), 0);
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
          <p>{formatCoinValue(product.priceCoin)} each</p>
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
      && ['weapon', 'shield'].includes(item.type)
      && isMythrilItem(item);
  });
}

function eligibleArmoryEnhancementTargets(items: InventoryItem[]) {
  return items.filter((item) => {
    return !item.enchantment
      && item.enhancementCount < 3
      && item.type === 'armor'
      && isMythrilItem(item);
  });
}

function eligibleEnchantmentTargets(items: InventoryItem[]) {
  return items.filter((item) => {
    return item.type === 'weapon'
      && !item.enchantment
      && item.enhancementCount <= 0
      && isMythrilItem(item);
  });
}

export function CitiesPanel({ profile }: { profile: Profile }) {
  const [payload, setPayload] = useState<CitiesPayload>(EMPTY_PAYLOAD);
  const [selectedCityKey, setSelectedCityKey] = useState('');
  const [shoppingAs, setShoppingAs] = useState('');
  const [selectedVendorId, setSelectedVendorId] = useState('');
  const [selectedProduct, setSelectedProduct] = useState<MarketProduct | null>(null);
  const [editProduct, setEditProduct] = useState<MarketProduct | null>(null);
  const [editVendor, setEditVendor] = useState<ShopVendor | null>(null);
  const [productDraft, setProductDraft] = useState<ProductDraft | null>(null);
  const [vendorDraft, setVendorDraft] = useState<VendorDraft | null>(null);
  const [quantity, setQuantity] = useState(1);
  const [researchType, setResearchType] = useState(MAGICAL_RESEARCH_TYPES[0]);
  const [craftModal, setCraftModal] = useState<CraftModalState | null>(null);
  const [craftInventory, setCraftInventory] = useState<InventoryItem[]>([]);
  const [craftHouseItems, setCraftHouseItems] = useState<InventoryItem[]>([]);
  const [craftWallet, setCraftWallet] = useState<WalletBalance[]>([]);
  const [craftMaterialProductId, setCraftMaterialProductId] = useState('');
  const [craftRuneProductId, setCraftRuneProductId] = useState('');
  const [craftTargetItemId, setCraftTargetItemId] = useState('');
  const [craftModifier, setCraftModifier] = useState('strength');
  const [craftRefreshSignal, setCraftRefreshSignal] = useState(0);
  const [craftConfirmOpen, setCraftConfirmOpen] = useState(false);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const isDm = profile.role === 'dm';

  const visibleCities = useMemo(() => [...payload.cities].sort((a, b) => a.order - b.order || a.name.localeCompare(b.name)), [payload.cities]);
  const selectedCity = visibleCities.find((city) => city.key === selectedCityKey) ?? visibleCities.find((city) => city.key === 'calostrynn') ?? visibleCities[0] ?? null;
  const shoppers = useMemo(() => payload.characters.filter((character) => isDm || character.ownerUserId === profile.id), [isDm, payload.characters, profile.id]);
  const selectedShopper = shoppers.find((character) => character.id === shoppingAs) ?? null;
  const selectedVendor = payload.vendors.find((vendor) => vendor.id === selectedVendorId && vendor.cityKey === selectedCity?.key && activeCityVendor(vendor)) ?? null;
  const cityLocked = Boolean(selectedCity?.locked);
  const shopperInCity = sameCityName(selectedShopper?.locationName, selectedCity?.name);
  const canShop = Boolean(selectedShopper && selectedCity && !cityLocked && shopperInCity);
  const blacksmithMaterials = useMemo(() => forgeMaterialProducts(payload.vendors, 'blacksmith'), [payload.vendors]);
  const armoryMaterials = useMemo(() => forgeMaterialProducts(payload.vendors, 'armory'), [payload.vendors]);
  const forgeRunes = useMemo(() => sharedForgeRuneProducts(payload.vendors), [payload.vendors]);
  const craftMaterials = craftModal?.service === 'armory' ? armoryMaterials : blacksmithMaterials;
  const canConfirmForge = useMemo(() => {
    if (!craftModal || !selectedVendor || !selectedShopper || !canShop) return false;
    const walletCoin = walletTotalCoin(craftWallet);
    if (craftModal.mode === 'craft') {
      const plan = buildMaterialPlan(craftModal.recipe, craftMaterials, craftMaterialProductId, craftInventory, craftHouseItems);
      const totalCost = plan.materialCost + recipeLaborCost(craftModal.service, selectedShopper, craftModal.recipe);
      return plan.canCover && walletCoin >= totalCost;
    }

    const requiredRunes = craftModal.mode === 'enchant' && isTalismanistClass(selectedShopper) ? 3 : craftModal.mode === 'enchant' ? 5 : 1;
    const rune = forgeRunes.find((product) => product.id === craftRuneProductId);
    if (!rune || !hasUsableStock(rune, requiredRunes)) return false;
    const targets = craftModal.mode === 'enhance'
      ? craftModal.service === 'armory' ? eligibleArmoryEnhancementTargets(craftInventory) : eligibleBlacksmithEnhancementTargets(craftInventory)
      : eligibleEnchantmentTargets(craftInventory);
    if (!craftTargetItemId || !targets.some((item) => item.id === craftTargetItemId)) return false;
    if (craftModal.mode === 'enhance' && !craftModifier) return false;
    const laborCost = craftModal.mode === 'enhance' && craftModal.service === 'armory' && isArmorCladClass(selectedShopper) ? 0 : 1000;
    return walletCoin >= laborCost + rune.priceCoin * requiredRunes;
  }, [canShop, craftHouseItems, craftInventory, craftMaterialProductId, craftMaterials, craftModal, craftModifier, craftRuneProductId, craftTargetItemId, craftWallet, forgeRunes, selectedShopper, selectedVendor]);

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
      setPayload(normalized);
      setShoppingAs((current) => current || normalized.characters.find((character) => isDm || character.ownerUserId === profile.id)?.id || '');
      setSelectedCityKey((current) => current || normalized.cities.find((city) => city.key === 'calostrynn')?.key || normalized.cities[0]?.key || '');
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
            materialProductId: craftMaterialProductId || null
          }
        : {
            action: craftModal.mode,
            characterId: selectedShopper.id,
            targetItemId: craftTargetItemId || null,
            runeProductId: craftRuneProductId || null,
            modifierKey: craftModifier
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
      setCraftRuneProductId('');
      setCraftTargetItemId('');
      setCraftModifier('strength');
    } catch (craftError) {
      setError(craftError instanceof Error ? craftError.message : 'Forge work failed.');
    } finally {
      setSaving(false);
    }
  }

  function openProductEdit(product: MarketProduct) {
    setEditProduct(product);
    setProductDraft(productToDraft(product));
  }

  function openVendorEdit(vendor: ShopVendor) {
    setEditVendor(vendor);
    setVendorDraft(vendorToDraft(vendor));
  }

  async function saveProduct(event: FormEvent) {
    event.preventDefault();
    if (!editProduct || !productDraft) return;
    const saved = await patchProduct(editProduct, productDraft);
    if (saved) {
      setEditProduct(null);
      setProductDraft(null);
    }
  }

  async function saveVendor(event: FormEvent) {
    event.preventDefault();
    if (!editVendor || !vendorDraft) return;
    const saved = await patchVendor(editVendor, vendorDraft);
    if (saved) {
      setEditVendor(null);
      setVendorDraft(null);
    }
  }

  function openCraftModal(next: CraftModalState) {
    const materials = next.service === 'armory' ? armoryMaterials : blacksmithMaterials;
    setCraftModal(next);
    setCraftMaterialProductId(next.mode === 'craft'
      ? (next.recipe.materialName ? materialProductByName(materials, next.recipe.materialName)?.id : materials[0]?.id) ?? ''
      : '');
    setCraftRuneProductId(forgeRunes.find((product) => hasUsableStock(product))?.id ?? '');
    setCraftTargetItemId('');
    setCraftModifier('strength');
    setCraftConfirmOpen(false);
  }

  function craftConfirmation() {
    if (!craftModal || !selectedShopper) return null;
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
    const rune = forgeRunes.find((product) => product.id === craftRuneProductId) ?? null;
    const requiredRunes = craftModal.mode === 'enchant' && isTalismanistClass(selectedShopper) ? 3 : craftModal.mode === 'enchant' ? 5 : 1;
    const laborCost = craftModal.mode === 'enhance' && craftModal.service === 'armory' && isArmorCladClass(selectedShopper) ? 0 : 1000;
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
          name: rune.name,
          type: rune.type,
          rarity: rune.rarity,
          quantity: requiredRunes
        }] : []),
        ...(laborCost > 0 ? [{
          key: 'labor',
          name: 'Labor',
          type: 'currency' as ItemType,
          rarity: 'Common' as ItemRarity,
          quantity: formatCoinValue(laborCost)
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

  const pageTitle = selectedVendor ? selectedVendor.name : (selectedCity?.name ?? 'Cities');
  const craftConfirm = craftConfirmation();

  return (
    <div className="space-y-4">
      <Card>
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <p className="eyebrow">Discovered Cities</p>
            <h2 className="mt-1 text-2xl font-black">{pageTitle}</h2>
            {selectedVendor && <p className="mt-1 text-sm font-bold text-[var(--muted)]">{selectedVendor.facility} · {selectedVendor.npcName}</p>}
          </div>
          <div className="flex flex-wrap gap-2">
            {selectedVendor && <Button variant="secondary" onClick={() => setSelectedVendorId('')}><ArrowLeft className="mr-2 inline" size={15} /> Return to Cities</Button>}
            <Button variant="secondary" className="p-3" onClick={() => void loadCities()} aria-label="Refresh cities"><RefreshCw size={16} /></Button>
            {isDm && !selectedVendor && selectedCity && <Button variant={cityLocked ? 'danger' : 'teal'} onClick={toggleCityLock} disabled={saving}>{cityLocked ? <Lock className="mr-2 inline" size={15} /> : <Unlock className="mr-2 inline" size={15} />}{cityLocked ? 'Locked' : 'Open'}</Button>}
          </div>
        </div>
        {error && <div className="mt-3 rounded-2xl border border-[var(--red)]/40 bg-[var(--red)]/10 p-3 text-sm text-[var(--red)]">{error}</div>}
        {!selectedVendor && (
          <div className="mt-4 grid gap-2 sm:grid-cols-2 xl:grid-cols-3">
            {visibleCities.map((city) => {
              const active = city.key === selectedCity?.key;
              const vendorCount = payload.vendors.filter((vendor) => vendor.cityKey === city.key && activeCityVendor(vendor) && (isDm || !vendor.hidden)).length;
              return (
                <button
                  key={city.key}
                  type="button"
                  onClick={() => {
                    setSelectedCityKey(city.key);
                    setSelectedVendorId('');
                  }}
                  className={`rounded-2xl border p-3 text-left transition ${active ? 'border-[var(--brass)] bg-[#d1a85b14]' : 'border-[var(--line)] bg-black/10 hover:border-[var(--brass)]/50'}`}
                >
                  <span className="flex items-start justify-between gap-3">
                    <span className="min-w-0">
                      <span className="block truncate font-black">{city.name}</span>
                      <span className="mt-1 block text-xs font-bold text-[var(--muted)]">{vendorCount} shop{vendorCount === 1 ? '' : 's'}</span>
                    </span>
                    <span className={`rounded-lg border px-2 py-1 text-[10px] font-black uppercase tracking-wide ${city.locked ? 'border-[var(--red)]/45 text-[var(--red)]' : 'border-[var(--teal)]/45 text-[var(--teal)]'}`}>{city.locked ? 'Locked' : 'Open'}</span>
                  </span>
                </button>
              );
            })}
          </div>
        )}
        <div className="mt-4 grid gap-3 md:grid-cols-[18rem_1fr]">
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
        </div>
      </Card>

      {!selectedCity ? (
        <Card><p className="text-sm text-[var(--muted)]">No cities have been discovered yet.</p></Card>
      ) : !selectedVendor ? (
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
              onEdit={() => openVendorEdit(vendor)}
              onToggleVisibility={() => void patchVendor(vendor, { hidden: !vendor.hidden }, 'Shop visibility could not be changed.')}
              onMove={(direction) => void moveVendor(vendor, direction)}
            />
          ))}
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
            </div>
            {isSinglePurchaseProduct(selectedProduct) ? (
              <div className="rounded-xl border border-[var(--line)] bg-black/15 px-4 py-3 text-sm font-black text-[var(--brass)]">{formatCoinValue(selectedProduct.priceCoin)}</div>
            ) : (
              <div className="grid gap-3 sm:grid-cols-[1fr_auto]">
                <NumberInput min={selectedProduct.quantityStep || quantityStepForItem(selectedProduct)} step={selectedProduct.quantityStep || quantityStepForItem(selectedProduct)} max={selectedProduct.stockQuantity ?? 999999} value={quantity} onValueChange={setQuantity} />
                <div className="rounded-xl border border-[var(--line)] bg-black/15 px-4 py-3 text-sm font-black text-[var(--brass)]">{formatCoinValue(selectedProduct.priceCoin * quantity)}</div>
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
        <Modal title={craftModal.mode === 'craft' ? craftModal.recipe.name : craftModal.mode === 'enhance' ? (craftModal.service === 'armory' ? 'Enhance Mythril Armor' : 'Enhance Mythril Gear') : 'Enchant Mythril Weapon'} onClose={() => setCraftModal(null)}>
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
            ) : (
              <MythrilServiceForm
                service={craftModal.service}
                mode={craftModal.mode}
                shopper={selectedShopper}
                inventory={craftInventory}
                runes={forgeRunes}
                wallet={craftWallet}
                targetItemId={craftTargetItemId}
                setTargetItemId={setCraftTargetItemId}
                runeProductId={craftRuneProductId}
                setRuneProductId={setCraftRuneProductId}
                modifier={craftModifier}
                setModifier={setCraftModifier}
              />
            )}
            <Button variant="primary" disabled={saving || !canConfirmForge} onClick={() => setCraftConfirmOpen(true)}>
              {craftModal.mode === 'craft' ? <Hammer className="mr-2 inline" size={15} /> : <WandSparkles className="mr-2 inline" size={15} />}
              Craft
            </Button>
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

      {editVendor && vendorDraft && (
        <Modal title={`Edit ${editVendor.name}`} onClose={() => setEditVendor(null)}>
          <form onSubmit={saveVendor} className="grid gap-3">
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

      {editProduct && productDraft && (
        <Modal title={`Edit ${editProduct.name}`} onClose={() => setEditProduct(null)}>
          <form onSubmit={saveProduct} className="grid gap-3">
            <TextField value={productDraft.name} onChange={(event) => setProductDraft({ ...productDraft, name: event.target.value })} />
            <TextAreaField rows={3} value={productDraft.description} onChange={(event) => setProductDraft({ ...productDraft, description: event.target.value })} />
            <div className="grid gap-2 sm:grid-cols-2">
              <SelectField value={productDraft.type} onChange={(event) => setProductDraft({ ...productDraft, type: event.target.value as ItemType })}>{ITEM_TYPES.map((type) => <option key={type} value={type}>{type}</option>)}</SelectField>
              <SelectField value={productDraft.rarity} onChange={(event) => setProductDraft({ ...productDraft, rarity: event.target.value as ItemRarity })}>{rarityOptions.map((rarity) => <option key={rarity} value={rarity}>{rarity}</option>)}</SelectField>
              <NumberInput min={0} value={productDraft.priceCoin} onValueChange={(priceCoin) => setProductDraft({ ...productDraft, priceCoin })} />
              <NumberInput min={0} step={productDraft.quantityStep || 1} value={productDraft.stockQuantity} onValueChange={(stockQuantity) => setProductDraft({ ...productDraft, stockQuantity })} />
              <TextField value={productDraft.section} onChange={(event) => setProductDraft({ ...productDraft, section: event.target.value })} placeholder="Shop section" />
              <NumberInput min={0.5} step={0.5} value={productDraft.quantityStep} onValueChange={(quantityStep) => setProductDraft({ ...productDraft, quantityStep })} />
            </div>
            <label className="flex items-center gap-2 rounded-xl border border-[var(--line)] bg-black/15 p-3 text-sm font-black">
              <input type="checkbox" checked={productDraft.available} onChange={(event) => setProductDraft({ ...productDraft, available: event.target.checked })} />
              Available for sale
            </label>
            <Button variant="primary" disabled={!productDraft.name.trim() || saving}><PackageCheck className="mr-2 inline" size={15} /> Save product</Button>
          </form>
        </Modal>
      )}
    </div>
  );
}

function ShopCard({ vendor, isDm, saving, index, total, onOpen, onEdit, onToggleVisibility, onMove }: {
  vendor: ShopVendor;
  isDm: boolean;
  saving: boolean;
  index: number;
  total: number;
  onOpen: () => void;
  onEdit: () => void;
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
          <Button variant="secondary" className="px-3 py-2 text-xs" onClick={onEdit} disabled={saving}>
            <Pencil className="mr-2 inline" size={13} /> Edit shop
          </Button>
          <Button variant={vendor.hidden ? 'teal' : 'secondary'} className="px-3 py-2 text-xs" onClick={onToggleVisibility} disabled={saving}>
            {vendor.hidden ? <Eye className="mr-2 inline" size={13} /> : <EyeOff className="mr-2 inline" size={13} />}
            {vendor.hidden ? 'Show shop' : 'Hide shop'}
          </Button>
          <Button variant="secondary" className="px-3 py-2 text-xs" onClick={() => onMove(-1)} disabled={saving || index <= 0} aria-label={`Move ${vendor.name} up`}><ArrowUp size={13} /></Button>
          <Button variant="secondary" className="px-3 py-2 text-xs" onClick={() => onMove(1)} disabled={saving || index >= total - 1} aria-label={`Move ${vendor.name} down`}><ArrowDown size={13} /></Button>
        </div>
      )}
    </Card>
  );
}

function ShopPage({ vendor, isDm, saving, canShop, onSelectProduct, onEditProduct, onPatchProduct }: {
  vendor: ShopVendor;
  isDm: boolean;
  saving: boolean;
  canShop: boolean;
  onSelectProduct: (product: MarketProduct) => void;
  onEditProduct: (product: MarketProduct) => void;
  onPatchProduct: (product: MarketProduct, patch: Partial<ProductDraft>) => void;
}) {
  return (
    <div className="grid gap-4">
      {groupProducts(vendor.products).map(([section, products]) => (
        <Card key={section}>
          <div className="rule-title mb-3"><h3 className="text-sm font-black uppercase tracking-wider">{section}</h3></div>
          <ProductGrid products={products} isDm={isDm} saving={saving} canShop={canShop} onSelectProduct={onSelectProduct} onEditProduct={onEditProduct} onPatchProduct={onPatchProduct} />
        </Card>
      ))}
    </div>
  );
}

function SpellShopPage({ vendor, isDm, saving, canShop, onSelectProduct, onEditProduct, onPatchProduct }: {
  vendor: ShopVendor;
  isDm: boolean;
  saving: boolean;
  canShop: boolean;
  onSelectProduct: (product: MarketProduct) => void;
  onEditProduct: (product: MarketProduct) => void;
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
                <ProductGrid products={products} isDm={isDm} saving={saving} canShop={canShop} onSelectProduct={onSelectProduct} onEditProduct={onEditProduct} onPatchProduct={onPatchProduct} />
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
            <h3 className="text-2xl font-black">Calostrynn Blacksmith</h3>
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
  onPatchProduct: (product: MarketProduct, patch: Partial<ProductDraft>) => void;
  onCraft: (state: CraftModalState) => void;
}) {
  const { sharedMaterials, onCraft } = props;
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
            <h3 className="text-2xl font-black">Calostrynn Armory</h3>
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
    </div>
  );
}

function BreweryPage({ vendor, shopper, isDm, saving, canShop, onSelectProduct, onEditProduct, onPatchProduct, onCitiesChanged, liveRefreshSignal, setError }: {
  vendor: ShopVendor;
  shopper: Character | null;
  isDm: boolean;
  saving: boolean;
  canShop: boolean;
  onSelectProduct: (product: MarketProduct) => void;
  onEditProduct: (product: MarketProduct) => void;
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

  const productGroups = groupProducts(vendor.products);

  useEffect(() => {
    if (!shopper || !canShop) {
      setBrewery({ definitions: [], availableItems: [], houseAccess: { accessible: false, city: 'Calostrynn' } });
      return;
    }

    let active = true;
    setBreweryLoading(true);
    fetch(`/api/cities/brewery?characterId=${shopper.id}`, { cache: 'no-store' })
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
  }, [canShop, liveRefreshSignal, setError, shopper]);

  useEffect(() => {
    setPropertySelections({});
    setStabilizerSelections({});
    setCatalystKey('');
    setResult(null);
  }, [shopper?.id, strength, propertyKey]);

  const selectedDefinition = brewery.definitions.find((definition) => definition.propertyKey === propertyKey) ?? brewery.definitions[0] ?? null;
  const requirements = breweryRequirements(strength);
  const propertyItems = brewery.availableItems.filter((item) => selectedDefinition && item.properties.includes(selectedDefinition.propertyKey));
  const stabilizerItems = brewery.availableItems.filter((item) => item.properties.includes('Stabilizer'));
  const catalystItems = brewery.availableItems.filter((item) => item.properties.includes('Catalyst'));
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
          strength,
          propertyKey: selectedDefinition.propertyKey,
          propertySelections: selectionsToPayload(propertySelections),
          stabilizerSelections: selectionsToPayload(stabilizerSelections),
          catalystSelection
        })
      });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(body.error ?? 'Brew failed.');
      setResult(normalizeBrewResult(body.result));
      setBrewery(normalizeBreweryState(body.brewery));
      onCitiesChanged(normalizeCitiesPayload(body.cities));
      setPropertySelections({});
      setStabilizerSelections({});
      setCatalystKey('');
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
            <h3 className="text-2xl font-black">Calostrynn Brewery</h3>
          </div>
        </div>
      </Card>

      {productGroups.map(([section, products]) => (
        <Card key={section}>
          <div className="rule-title mb-3"><h3 className="text-sm font-black uppercase tracking-wider">{section}</h3></div>
          <ProductGrid products={products} isDm={isDm} saving={saving} canShop={canShop} onSelectProduct={onSelectProduct} onEditProduct={onEditProduct} onPatchProduct={onPatchProduct} />
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

            <Button variant="primary" disabled={!canBrew} onClick={runBrew}>
              <Sparkles className="mr-2 inline" size={15} /> Brew potion
            </Button>
          </div>
        )}
      </Card>
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

function ProductGrid({ products, isDm, saving, canShop, onSelectProduct, onEditProduct, onPatchProduct }: {
  products: MarketProduct[];
  isDm: boolean;
  saving: boolean;
  canShop: boolean;
  onSelectProduct: (product: MarketProduct) => void;
  onEditProduct: (product: MarketProduct) => void;
  onPatchProduct: (product: MarketProduct, patch: Partial<ProductDraft>) => void;
}) {
  return (
    <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
      {products.map((product) => {
        const disabled = !hasUsableStock(product);
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
                </span>
              )}
            </span>
            <p className="line-clamp-2 min-h-8 text-xs text-[var(--muted)]">{productEffectText(product) || product.description}</p>
            {product.type === 'potion' && productEffectText(product) && (
              <span className="mt-2 block rounded-lg border border-[#56e2c2]/25 bg-[#56e2c2]/10 px-2 py-1 text-[10px] font-black uppercase tracking-wide text-[#56e2c2]">
                {productEffectText(product)}
              </span>
            )}
            <span className="mt-3 flex items-center justify-between gap-2 text-xs font-black">
              <span className="text-[var(--brass)]">{formatCoinValue(product.priceCoin)}</span>
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
            {materials.map((product) => <option key={product.id} value={product.id}>{product.name} · {formatCoinValue(product.priceCoin)} each · stock {product.stockQuantity ?? '∞'}</option>)}
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

function MythrilServiceForm({ service, mode, shopper, inventory, runes, wallet, targetItemId, setTargetItemId, runeProductId, setRuneProductId, modifier, setModifier }: {
  service: ForgeService;
  mode: 'enhance' | 'enchant';
  shopper: Character | null;
  inventory: InventoryItem[];
  runes: MarketProduct[];
  wallet: WalletBalance[];
  targetItemId: string;
  setTargetItemId: (value: string) => void;
  runeProductId: string;
  setRuneProductId: (value: string) => void;
  modifier: string;
  setModifier: (value: string) => void;
}) {
  const requiredRunes = mode === 'enchant' && isTalismanistClass(shopper) ? 3 : mode === 'enchant' ? 5 : 1;
  const usableRunes = runes.filter((product) => hasUsableStock(product, requiredRunes));
  const targets = mode === 'enhance'
    ? service === 'armory' ? eligibleArmoryEnhancementTargets(inventory) : eligibleBlacksmithEnhancementTargets(inventory)
    : eligibleEnchantmentTargets(inventory);
  const rune = runes.find((product) => product.id === runeProductId) ?? null;
  const laborCost = mode === 'enhance' && service === 'armory' && isArmorCladClass(shopper) ? 0 : 1000;
  const totalCost = laborCost + (rune?.priceCoin ?? 0) * requiredRunes;
  return (
    <div className="grid gap-3">
      <label>
        <span className="mb-1 block text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">Target</span>
        <SelectField value={targetItemId} onChange={(event) => setTargetItemId(event.target.value)}>
          <option value="">Choose eligible item</option>
          {targets.map((item) => <option key={item.id} value={item.id}>{item.name} · {item.rarity}{item.enhancementCount ? ` · ${item.enhancementCount}/3 enhancements` : ''}</option>)}
        </SelectField>
      </label>
      <label>
        <span className="mb-1 block text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">Rune</span>
        <SelectField value={runeProductId} onChange={(event) => setRuneProductId(event.target.value)}>
          <option value="">Choose rune</option>
          {usableRunes.map((product) => <option key={product.id} value={product.id}>{product.name} · {formatCoinValue(product.priceCoin)} · stock {product.stockQuantity ?? '∞'}</option>)}
        </SelectField>
      </label>
      {mode === 'enhance' && (
        <label>
          <span className="mb-1 block text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">Enhancement</span>
          <SelectField value={modifier} onChange={(event) => setModifier(event.target.value)}>
            {ENHANCEMENT_OPTIONS.map((option) => <option key={option.key} value={option.key}>{option.label} · 20 {option.catalyst}</option>)}
          </SelectField>
        </label>
      )}
      <div className="rounded-2xl border border-[var(--line)] bg-black/15 p-3 text-sm text-[var(--muted)]">
        {mode === 'enhance'
          ? `Costs ${formatCoinValue(laborCost)}, 1 rune, and 20 matching ingredients. Max 3 enhancements per item.`
          : `Costs 10 Callor and ${requiredRunes} matching runes. Only unenhanced Mythril weapons can be enchanted.`}
      </div>
      {rune && <SoftCard><p className="eyebrow">Total</p><p className="font-black text-[var(--brass)]">{formatCoinValue(totalCost)}</p></SoftCard>}
      {walletTotalCoin(wallet) < totalCost && <div className="rounded-2xl border border-[var(--red)]/40 bg-[var(--red)]/10 p-3 text-sm text-[var(--red)]">Not enough currency.</div>}
    </div>
  );
}
