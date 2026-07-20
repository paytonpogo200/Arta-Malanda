'use client';

import { useCallback, useEffect, useMemo, useState, type FormEvent } from 'react';
import { ArrowDown, ArrowUp, ChevronDown, ChevronRight, Eye, EyeOff, Lock, PackageCheck, Pencil, RefreshCw, ShoppingBag, Store, Unlock, Users } from 'lucide-react';
import { ItemIcon } from '@/components/inventory/ItemIcon';
import { Button } from '@/components/ui/Button';
import { Card } from '@/components/ui/Card';
import { SelectField, TextAreaField, TextField } from '@/components/ui/Field';
import { Modal } from '@/components/ui/Modal';
import { NumberInput } from '@/components/ui/NumberInput';
import { formatCoinValue, normalizeCitiesPayload, type CitiesPayload } from '@/features/cities/data';
import { ITEM_TYPES } from '@/features/inventory/data';
import { rarityClass, rarityOptions } from '@/lib/utils/rarity';
import type { ItemRarity, ItemType, MarketProduct, Profile, ShopVendor } from '@/lib/types';

const EMPTY_PAYLOAD: CitiesPayload = { characters: [], cities: [], vendors: [] };

type ProductDraft = {
  name: string;
  description: string;
  type: ItemType;
  rarity: ItemRarity;
  priceCoin: number;
  stockQuantity: number;
  available: boolean;
};

type VendorDraft = {
  name: string;
  npcName: string;
  facility: string;
  category: string;
  hidden: boolean;
  order: number;
};

function productToDraft(product: MarketProduct): ProductDraft {
  return {
    name: product.name,
    description: product.description,
    type: product.type,
    rarity: product.rarity,
    priceCoin: product.priceCoin,
    stockQuantity: product.stockQuantity ?? 0,
    available: product.available
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

export function CitiesPanel({ profile }: { profile: Profile }) {
  const [payload, setPayload] = useState<CitiesPayload>(EMPTY_PAYLOAD);
  const [shoppingAs, setShoppingAs] = useState('');
  const [expandedVendors, setExpandedVendors] = useState<Set<string>>(() => new Set());
  const [selectedProduct, setSelectedProduct] = useState<MarketProduct | null>(null);
  const [editProduct, setEditProduct] = useState<MarketProduct | null>(null);
  const [editVendor, setEditVendor] = useState<ShopVendor | null>(null);
  const [productDraft, setProductDraft] = useState<ProductDraft | null>(null);
  const [vendorDraft, setVendorDraft] = useState<VendorDraft | null>(null);
  const [quantity, setQuantity] = useState(1);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const isDm = profile.role === 'dm';

  const calostrynn = payload.cities.find((city) => city.key === 'calostrynn') ?? payload.cities[0];
  const shoppers = useMemo(() => payload.characters.filter((character) => isDm || character.ownerUserId === profile.id), [isDm, payload.characters, profile.id]);
  const selectedShopper = shoppers.find((character) => character.id === shoppingAs) ?? null;
  const cityLocked = Boolean(calostrynn?.locked);
  const shopperInCity = selectedShopper?.locationName === (calostrynn?.name ?? 'Calostrynn');
  const canShop = Boolean(selectedShopper && calostrynn && !cityLocked && shopperInCity);

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

  async function replaceFromResponse(response: Response, fallback: string) {
    const body = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(body.error ?? fallback);
    setPayload(normalizeCitiesPayload(body));
  }

  function toggleVendorExpanded(vendorId: string) {
    setExpandedVendors((current) => {
      const next = new Set(current);
      if (next.has(vendorId)) next.delete(vendorId);
      else next.add(vendorId);
      return next;
    });
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
    const cityVendors = payload.vendors
      .filter((entry) => entry.cityKey === vendor.cityKey)
      .sort((a, b) => a.order - b.order || a.name.localeCompare(b.name));
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

  if (loading) {
    return <Card><div className="h-32 animate-pulse rounded-2xl bg-black/20" /></Card>;
  }

  return (
    <div className="space-y-4">
      <Card>
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <p className="eyebrow">Discovered Cities</p>
            <h2 className="mt-1 text-2xl font-black">{calostrynn?.name ?? 'Calostrynn'}</h2>
          </div>
          <div className="flex gap-2">
            <Button variant="secondary" className="p-3" onClick={loadCities} aria-label="Refresh cities"><RefreshCw size={16} /></Button>
            {isDm && <Button variant={cityLocked ? 'danger' : 'teal'} onClick={toggleCityLock} disabled={saving}>{cityLocked ? <Lock className="mr-2 inline" size={15} /> : <Unlock className="mr-2 inline" size={15} />}{cityLocked ? 'Locked' : 'Open'}</Button>}
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

      {payload.vendors.map((vendor) => {
        if (vendor.hidden && !isDm) return null;
        const expanded = expandedVendors.has(vendor.id);
        const cityVendors = payload.vendors.filter((entry) => entry.cityKey === vendor.cityKey).sort((a, b) => a.order - b.order || a.name.localeCompare(b.name));
        const vendorIndex = cityVendors.findIndex((entry) => entry.id === vendor.id);
        return (
          <Card key={vendor.id} className={`overflow-hidden ${vendor.hidden ? 'opacity-75' : ''}`}>
            <div className="relative">
              <button
                type="button"
                onClick={() => toggleVendorExpanded(vendor.id)}
                className="group w-full rounded-2xl border border-[var(--line)] bg-gradient-to-br from-[rgba(245,180,76,0.18)] via-black/10 to-[rgba(31,120,117,0.14)] p-4 text-left transition hover:border-[var(--brass)]/70"
              >
                <span className="flex items-start justify-between gap-3">
                  <span className="flex min-w-0 gap-3">
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
                  <span className="flex shrink-0 items-center gap-2">
                    {vendor.hidden && <span className="hidden rounded-full border border-[var(--red)]/35 bg-[var(--red)]/10 px-2 py-1 text-[10px] font-black uppercase text-[var(--red)] sm:inline">Hidden</span>}
                    <span className="rounded-full border border-[var(--line)] bg-black/25 p-2 text-[var(--brass)]">
                      {expanded ? <ChevronDown size={18} /> : <ChevronRight size={18} />}
                    </span>
                  </span>
                </span>
              </button>

              {isDm && (
                <div className="mt-3 flex flex-wrap gap-2">
                  <Button variant="secondary" className="px-3 py-2 text-xs" onClick={() => openVendorEdit(vendor)} disabled={saving}>
                    <Pencil className="mr-2 inline" size={13} /> Edit shop
                  </Button>
                  <Button variant={vendor.hidden ? 'teal' : 'secondary'} className="px-3 py-2 text-xs" onClick={() => void patchVendor(vendor, { hidden: !vendor.hidden }, 'Shop visibility could not be changed.')} disabled={saving}>
                    {vendor.hidden ? <Eye className="mr-2 inline" size={13} /> : <EyeOff className="mr-2 inline" size={13} />}
                    {vendor.hidden ? 'Show shop' : 'Hide shop'}
                  </Button>
                  <Button variant="secondary" className="px-3 py-2 text-xs" onClick={() => void moveVendor(vendor, -1)} disabled={saving || vendorIndex <= 0} aria-label={`Move ${vendor.name} up`}><ArrowUp size={13} /></Button>
                  <Button variant="secondary" className="px-3 py-2 text-xs" onClick={() => void moveVendor(vendor, 1)} disabled={saving || vendorIndex < 0 || vendorIndex >= cityVendors.length - 1} aria-label={`Move ${vendor.name} down`}><ArrowDown size={13} /></Button>
                </div>
              )}
            </div>

            {expanded && (
              <div className="mt-4 grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
                {vendor.products.map((product) => {
                  const disabled = !product.available || product.stockQuantity === 0;
                  return (
                    <button
                      key={product.id}
                      type="button"
                      onClick={() => {
                        if (!disabled) {
                          setSelectedProduct(product);
                          setQuantity(1);
                        }
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
                            <span role="button" tabIndex={0} onClick={(event) => { event.stopPropagation(); void patchProduct(product, { available: !product.available }, 'Item visibility could not be changed.'); }} className="rounded-lg border border-[var(--line)] bg-black/25 p-2 text-[var(--muted)]">
                              {product.available ? <Eye size={13} /> : <EyeOff size={13} />}
                            </span>
                            <span role="button" tabIndex={0} onClick={(event) => { event.stopPropagation(); openProductEdit(product); }} className="rounded-lg border border-[var(--line)] bg-black/25 p-2 text-[var(--muted)]"><Pencil size={13} /></span>
                          </span>
                        )}
                      </span>
                      <p className="line-clamp-2 min-h-8 text-xs text-[var(--muted)]">{product.description}</p>
                      <span className="mt-3 flex items-center justify-between gap-2 text-xs font-black">
                        <span className="text-[var(--brass)]">{formatCoinValue(product.priceCoin)}</span>
                        <span className="text-[var(--muted)]">{product.stockQuantity === null ? 'Stock ∞' : `Stock ${product.stockQuantity}`}</span>
                      </span>
                    </button>
                  );
                })}
              </div>
            )}
          </Card>
        );
      })}

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
              <NumberInput min={1} max={selectedProduct.stockQuantity ?? 999} value={quantity} onValueChange={setQuantity} />
              <div className="rounded-xl border border-[var(--line)] bg-black/15 px-4 py-3 text-sm font-black text-[var(--brass)]">{formatCoinValue(selectedProduct.priceCoin * quantity)}</div>
            </div>
            <div className="grid grid-cols-2 gap-2">
              <Button variant="secondary" onClick={() => setSelectedProduct(null)}>I'll pass</Button>
              <Button variant="primary" disabled={!canShop || saving} onClick={buyProduct}><ShoppingBag className="mr-2 inline" size={15} /> Buy</Button>
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
              <NumberInput min={0} value={productDraft.stockQuantity} onValueChange={(stockQuantity) => setProductDraft({ ...productDraft, stockQuantity })} />
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
