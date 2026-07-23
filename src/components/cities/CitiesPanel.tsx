'use client';

import { useCallback, useEffect, useMemo, useState, type FormEvent } from 'react';
import { ArrowDown, ArrowLeft, ArrowUp, Eye, EyeOff, Hammer, Lock, PackageCheck, Pencil, RefreshCw, ShoppingBag, Sparkles, Store, Unlock, Users, WandSparkles } from 'lucide-react';
import { ItemIcon } from '@/components/inventory/ItemIcon';
import { Button } from '@/components/ui/Button';
import { Card, SoftCard } from '@/components/ui/Card';
import { SelectField, TextAreaField, TextField } from '@/components/ui/Field';
import { Modal } from '@/components/ui/Modal';
import { NumberInput } from '@/components/ui/NumberInput';
import { formatCoinValue, normalizeCitiesPayload, type CitiesPayload } from '@/features/cities/data';
import { ITEM_TYPES, normalizeCharacterInventoryPayload, quantityStepForItem } from '@/features/inventory/data';
import { rarityClass, rarityOptions } from '@/lib/utils/rarity';
import type { InventoryItem, ItemRarity, ItemType, MarketProduct, Profile, ShopVendor } from '@/lib/types';

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
  twoHanded?: boolean;
  note?: string;
};

type CraftModalState =
  | { mode: 'craft'; recipe: CraftRecipe }
  | { mode: 'enhance' }
  | { mode: 'enchant' };

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
const MATERIAL_SECTION_ALIASES = new Set(['material scales', 'materials', 'scales']);
const RUNE_SECTION_ALIASES = new Set(['runes', 'rune']);
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
    return a.localeCompare(b);
  });
}

function materialProducts(vendor: ShopVendor) {
  return vendor.products.filter((product) => MATERIAL_SECTION_ALIASES.has(productSection(product).toLowerCase()) || product.name.toLowerCase().endsWith(' scale'));
}

function runeProducts(vendor: ShopVendor) {
  return vendor.products.filter((product) => RUNE_SECTION_ALIASES.has(productSection(product).toLowerCase()) || product.type === 'rune');
}

function eligibleEnhancementTargets(items: InventoryItem[]) {
  return items.filter((item) => {
    return !item.enchantment
      && item.enhancementCount < 3
      && ['weapon', 'shield', 'armor'].includes(item.type)
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
  const [shoppingAs, setShoppingAs] = useState('');
  const [selectedVendorId, setSelectedVendorId] = useState('');
  const [selectedProduct, setSelectedProduct] = useState<MarketProduct | null>(null);
  const [editProduct, setEditProduct] = useState<MarketProduct | null>(null);
  const [editVendor, setEditVendor] = useState<ShopVendor | null>(null);
  const [productDraft, setProductDraft] = useState<ProductDraft | null>(null);
  const [vendorDraft, setVendorDraft] = useState<VendorDraft | null>(null);
  const [quantity, setQuantity] = useState(1);
  const [craftModal, setCraftModal] = useState<CraftModalState | null>(null);
  const [craftInventory, setCraftInventory] = useState<InventoryItem[]>([]);
  const [craftMaterialProductId, setCraftMaterialProductId] = useState('');
  const [craftRuneProductId, setCraftRuneProductId] = useState('');
  const [craftTargetItemId, setCraftTargetItemId] = useState('');
  const [craftModifier, setCraftModifier] = useState('strength');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const isDm = profile.role === 'dm';

  const calostrynn = payload.cities.find((city) => city.key === 'calostrynn') ?? payload.cities[0];
  const shoppers = useMemo(() => payload.characters.filter((character) => isDm || character.ownerUserId === profile.id), [isDm, payload.characters, profile.id]);
  const selectedShopper = shoppers.find((character) => character.id === shoppingAs) ?? null;
  const selectedVendor = payload.vendors.find((vendor) => vendor.id === selectedVendorId) ?? null;
  const cityLocked = Boolean(calostrynn?.locked);
  const shopperInCity = selectedShopper?.locationName === (calostrynn?.name ?? 'Calostrynn');
  const canShop = Boolean(selectedShopper && calostrynn && !cityLocked && shopperInCity);

  const cityVendors = useMemo(() => payload.vendors
    .filter((vendor) => vendor.cityKey === calostrynn?.key)
    .filter((vendor) => isDm || !vendor.hidden)
    .sort((a, b) => a.order - b.order || a.name.localeCompare(b.name)), [calostrynn?.key, isDm, payload.vendors]);

  const loadCities = useCallback(async () => {
    setError('');
    try {
      const response = await fetch('/api/cities', { cache: 'no-store' });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(body.error ?? 'Discovered cities could not be loaded.');
      const normalized = normalizeCitiesPayload(body);
      setPayload(normalized);
      setShoppingAs((current) => current || normalized.characters.find((character) => isDm || character.ownerUserId === profile.id)?.id || '');
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : 'Discovered cities could not be loaded.');
    } finally {
      setLoading(false);
    }
  }, [isDm, profile.id]);

  useEffect(() => {
    void loadCities();
  }, [loadCities]);

  useEffect(() => {
    if (!craftModal || !selectedShopper) {
      setCraftInventory([]);
      return;
    }
    let active = true;
    fetch(`/api/characters/${selectedShopper.id}/inventory`, { cache: 'no-store' })
      .then((response) => response.json())
      .then((body) => {
        if (!active) return;
        setCraftInventory(normalizeCharacterInventoryPayload(body).items);
      })
      .catch(() => {
        if (active) setCraftInventory([]);
      });
    return () => {
      active = false;
    };
  }, [craftModal, selectedShopper]);

  async function replaceFromResponse(response: Response, fallback: string) {
    const body = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(body.error ?? fallback);
    const normalized = normalizeCitiesPayload(body);
    setPayload(normalized);
    if (selectedVendorId && !normalized.vendors.some((vendor) => vendor.id === selectedVendorId)) setSelectedVendorId('');
  }

  async function toggleCityLock() {
    if (!isDm || !calostrynn) return;
    setSaving(true);
    setError('');
    try {
      await replaceFromResponse(await fetch(`/api/cities/${calostrynn.key}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ locked: !calostrynn.locked })
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
      await replaceFromResponse(await fetch('/api/cities/purchase', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ productId: selectedProduct.id, characterId: selectedShopper.id, quantity })
      }), 'Purchase failed.');
      setSelectedProduct(null);
      setQuantity(1);
    } catch (buyError) {
      setError(buyError instanceof Error ? buyError.message : 'Purchase failed.');
    } finally {
      setSaving(false);
    }
  }

  async function runBlacksmithAction() {
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
      await replaceFromResponse(await fetch('/api/cities/blacksmith/craft', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body)
      }), 'Blacksmith work failed.');
      setCraftModal(null);
      setCraftMaterialProductId('');
      setCraftRuneProductId('');
      setCraftTargetItemId('');
      setCraftModifier('strength');
    } catch (craftError) {
      setError(craftError instanceof Error ? craftError.message : 'Blacksmith work failed.');
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
    setCraftModal(next);
    setCraftMaterialProductId(selectedVendor ? materialProducts(selectedVendor).find((product) => product.available)?.id ?? '' : '');
    setCraftRuneProductId(selectedVendor ? runeProducts(selectedVendor).find((product) => product.available)?.id ?? '' : '');
    setCraftTargetItemId('');
    setCraftModifier('strength');
  }

  if (loading) {
    return <Card><div className="h-32 animate-pulse rounded-2xl bg-black/20" /></Card>;
  }

  const pageTitle = selectedVendor ? selectedVendor.name : (calostrynn?.name ?? 'Calostrynn');

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
            <Button variant="secondary" className="p-3" onClick={loadCities} aria-label="Refresh cities"><RefreshCw size={16} /></Button>
            {isDm && !selectedVendor && <Button variant={cityLocked ? 'danger' : 'teal'} onClick={toggleCityLock} disabled={saving}>{cityLocked ? <Lock className="mr-2 inline" size={15} /> : <Unlock className="mr-2 inline" size={15} />}{cityLocked ? 'Locked' : 'Open'}</Button>}
          </div>
        </div>
        {error && <div className="mt-3 rounded-2xl border border-[var(--red)]/40 bg-[var(--red)]/10 p-3 text-sm text-[var(--red)]">{error}</div>}
        <div className="mt-4 grid gap-3 md:grid-cols-[18rem_1fr]">
          <label>
            <span className="mb-1 block text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">Shopping as</span>
            <SelectField value={shoppingAs} onChange={(event) => setShoppingAs(event.target.value)}>
              <option value="">Choose character</option>
              {shoppers.map((character) => <option key={character.id} value={character.id}>{character.name}</option>)}
            </SelectField>
          </label>
          <div className="rounded-2xl border border-[var(--line)] bg-black/10 p-3 text-sm text-[var(--muted)]">
            {!selectedShopper ? 'Choose who is shopping.' : cityLocked ? 'The city is locked by the DM.' : !shopperInCity ? `${selectedShopper.name} is in ${selectedShopper.locationName}, not ${calostrynn?.name ?? 'Calostrynn'}.` : `${selectedShopper.name} can shop here.`}
          </div>
        </div>
      </Card>

      {!selectedVendor ? (
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
            <div className={`rounded-2xl border p-4 ${rarityClass(selectedProduct.rarity)}`}>
              <div className="flex items-center gap-3">
                <span className="text-[var(--brass)]"><ItemIcon type={selectedProduct.type} size={22} /></span>
                <div>
                  <p className="font-black">{selectedProduct.rarity} {selectedProduct.type}</p>
                  <p className="text-sm text-[var(--muted)]">{selectedProduct.description}</p>
                </div>
              </div>
            </div>
            <div className="grid gap-3 sm:grid-cols-[1fr_auto]">
              <NumberInput min={selectedProduct.quantityStep || quantityStepForItem(selectedProduct)} step={selectedProduct.quantityStep || quantityStepForItem(selectedProduct)} max={selectedProduct.stockQuantity ?? 999999} value={quantity} onValueChange={setQuantity} />
              <div className="rounded-xl border border-[var(--line)] bg-black/15 px-4 py-3 text-sm font-black text-[var(--brass)]">{formatCoinValue(selectedProduct.priceCoin * quantity)}</div>
            </div>
            <div className="grid grid-cols-2 gap-2">
              <Button variant="secondary" onClick={() => setSelectedProduct(null)}>I'll pass</Button>
              <Button variant="primary" disabled={!canShop || saving} onClick={buyProduct}><ShoppingBag className="mr-2 inline" size={15} /> Buy</Button>
            </div>
          </div>
        </Modal>
      )}

      {craftModal && selectedVendor && (
        <Modal title={craftModal.mode === 'craft' ? craftModal.recipe.name : craftModal.mode === 'enhance' ? 'Enhance Mythril Item' : 'Enchant Mythril Weapon'} onClose={() => setCraftModal(null)}>
          <div className="grid gap-4">
            {!selectedShopper && <div className="rounded-2xl border border-[var(--red)]/40 bg-[var(--red)]/10 p-3 text-sm text-[var(--red)]">Choose a character first.</div>}
            {craftModal.mode === 'craft' ? (
              <CraftRecipeForm vendor={selectedVendor} recipe={craftModal.recipe} materialProductId={craftMaterialProductId} setMaterialProductId={setCraftMaterialProductId} />
            ) : (
              <MythrilServiceForm
                vendor={selectedVendor}
                mode={craftModal.mode}
                inventory={craftInventory}
                targetItemId={craftTargetItemId}
                setTargetItemId={setCraftTargetItemId}
                runeProductId={craftRuneProductId}
                setRuneProductId={setCraftRuneProductId}
                modifier={craftModifier}
                setModifier={setCraftModifier}
              />
            )}
            <Button variant="primary" disabled={!canShop || saving || !selectedShopper} onClick={runBlacksmithAction}>
              {craftModal.mode === 'craft' ? <Hammer className="mr-2 inline" size={15} /> : <WandSparkles className="mr-2 inline" size={15} />}
              Confirm work
            </Button>
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
          <span className="min-w-0">
            <span className="eyebrow">{vendor.facility}</span>
            <span className="mt-1 block truncate text-xl font-black">{vendor.name}</span>
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
                onClick={() => onCraft({ mode: 'craft', recipe })}
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
          <Button variant="teal" onClick={() => onCraft({ mode: 'enhance' })}><Sparkles className="mr-2 inline" size={15} /> Enhance Mythril Item</Button>
          <Button variant="primary" onClick={() => onCraft({ mode: 'enchant' })}><WandSparkles className="mr-2 inline" size={15} /> Enchant Mythril Weapon</Button>
        </div>
      </Card>
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
        const disabled = !product.available || product.stockQuantity === 0;
        return (
          <button
            key={product.id}
            type="button"
            onClick={() => {
              if (!disabled && canShop) onSelectProduct(product);
            }}
            className={`relative rounded-2xl border p-3 text-left transition active:scale-[0.99] ${rarityClass(product.rarity)} ${disabled ? 'opacity-45' : ''}`}
          >
            <span className="mb-2 flex items-start justify-between gap-3">
              <span className="flex min-w-0 items-center gap-2">
                <span className="text-[var(--brass)]"><ItemIcon type={product.type} /></span>
                <span className="min-w-0">
                  <span className="block truncate font-black">{product.name}</span>
                  <span className="block text-xs text-[var(--muted)]">{product.type} · {product.rarity}</span>
                </span>
              </span>
              {isDm && (
                <span className="flex shrink-0 gap-1">
                  <span role="button" tabIndex={0} onClick={(event) => { event.stopPropagation(); onPatchProduct(product, { available: !product.available }); }} className="rounded-lg border border-[var(--line)] bg-black/25 p-2 text-[var(--muted)]">
                    {product.available ? <Eye size={13} /> : <EyeOff size={13} />}
                  </span>
                  <span role="button" tabIndex={0} onClick={(event) => { event.stopPropagation(); onEditProduct(product); }} className="rounded-lg border border-[var(--line)] bg-black/25 p-2 text-[var(--muted)]"><Pencil size={13} /></span>
                </span>
              )}
            </span>
            <p className="line-clamp-2 min-h-8 text-xs text-[var(--muted)]">{product.description}</p>
            <span className="mt-3 flex items-center justify-between gap-2 text-xs font-black">
              <span className="text-[var(--brass)]">{formatCoinValue(product.priceCoin)}</span>
              <span className="text-[var(--muted)]">{product.stockQuantity === null ? 'Stock ∞' : `Stock ${product.stockQuantity}`}</span>
            </span>
            {!canShop && !disabled && <span className="mt-2 block text-[10px] font-black uppercase text-[var(--muted)]">Unavailable from current location</span>}
          </button>
        );
      })}
    </div>
  );
}

function CraftRecipeForm({ vendor, recipe, materialProductId, setMaterialProductId }: {
  vendor: ShopVendor;
  recipe: CraftRecipe;
  materialProductId: string;
  setMaterialProductId: (value: string) => void;
}) {
  const materials = materialProducts(vendor).filter((product) => product.available);
  const selectedMaterial = materials.find((product) => product.id === materialProductId) ?? null;
  const materialCost = recipe.materialQuantity && selectedMaterial ? selectedMaterial.priceCoin * recipe.materialQuantity : 0;
  const totalCost = materialCost + recipe.laborCoin;
  return (
    <div className="grid gap-3">
      <SoftCard>
        <p className="text-sm font-black">{recipe.name}</p>
        <p className="mt-1 text-xs text-[var(--muted)]">{recipe.materialQuantity ? `${recipe.materialQuantity} material scale required.` : 'No material scale required.'}</p>
      </SoftCard>
      {recipe.materialQuantity > 0 && (
        <label>
          <span className="mb-1 block text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">Material</span>
          <SelectField value={materialProductId} onChange={(event) => setMaterialProductId(event.target.value)}>
            <option value="">Choose material scale</option>
            {materials.map((product) => <option key={product.id} value={product.id}>{product.name} · {formatCoinValue(product.priceCoin)} each · stock {product.stockQuantity ?? '∞'}</option>)}
          </SelectField>
        </label>
      )}
      <div className="grid gap-2 sm:grid-cols-3">
        <SoftCard><p className="eyebrow">Materials</p><p className="font-black">{formatCoinValue(materialCost)}</p></SoftCard>
        <SoftCard><p className="eyebrow">Labor</p><p className="font-black">{formatCoinValue(recipe.laborCoin)}</p></SoftCard>
        <SoftCard><p className="eyebrow">Total</p><p className="font-black text-[var(--brass)]">{formatCoinValue(totalCost)}</p></SoftCard>
      </div>
    </div>
  );
}

function MythrilServiceForm({ vendor, mode, inventory, targetItemId, setTargetItemId, runeProductId, setRuneProductId, modifier, setModifier }: {
  vendor: ShopVendor;
  mode: 'enhance' | 'enchant';
  inventory: InventoryItem[];
  targetItemId: string;
  setTargetItemId: (value: string) => void;
  runeProductId: string;
  setRuneProductId: (value: string) => void;
  modifier: string;
  setModifier: (value: string) => void;
}) {
  const runes = runeProducts(vendor).filter((product) => product.available);
  const targets = mode === 'enhance' ? eligibleEnhancementTargets(inventory) : eligibleEnchantmentTargets(inventory);
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
          {runes.map((product) => <option key={product.id} value={product.id}>{product.name} · {formatCoinValue(product.priceCoin)} · stock {product.stockQuantity ?? '∞'}</option>)}
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
          ? 'Costs 10 Callor, 1 rune, and 20 matching ingredients. Max 3 enhancements per item.'
          : 'Costs 10 Callor and matching runes. Only unenhanced Mythril weapons can be enchanted.'}
      </div>
    </div>
  );
}
