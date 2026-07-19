'use client';

import { useCallback, useEffect, useMemo, useState, type FormEvent } from 'react';
import { Lock, PackageCheck, Pencil, RefreshCw, ShoppingBag, Store, Unlock } from 'lucide-react';
import { ItemIcon } from '@/components/inventory/ItemIcon';
import { Button } from '@/components/ui/Button';
import { Card } from '@/components/ui/Card';
import { SelectField, TextAreaField, TextField } from '@/components/ui/Field';
import { Modal } from '@/components/ui/Modal';
import { NumberInput } from '@/components/ui/NumberInput';
import { formatCoinValue, normalizeCitiesPayload, type CitiesPayload } from '@/features/cities/data';
import { ITEM_TYPES } from '@/features/inventory/data';
import { rarityOptions } from '@/lib/utils/rarity';
import { rarityClass } from '@/lib/utils/rarity';
import type { Character, ItemRarity, ItemType, MarketProduct, Profile } from '@/lib/types';

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

export function CitiesPanel({ profile }: { profile: Profile }) {
  const [payload, setPayload] = useState<CitiesPayload>(EMPTY_PAYLOAD);
  const [shoppingAs, setShoppingAs] = useState('');
  const [selectedProduct, setSelectedProduct] = useState<MarketProduct | null>(null);
  const [editProduct, setEditProduct] = useState<MarketProduct | null>(null);
  const [draft, setDraft] = useState<ProductDraft | null>(null);
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

  function openEdit(product: MarketProduct) {
    setEditProduct(product);
    setDraft(productToDraft(product));
  }

  async function saveProduct(event: FormEvent) {
    event.preventDefault();
    if (!isDm || !editProduct || !draft) return;
    setSaving(true);
    setError('');
    try {
      await replaceFromResponse(await fetch(`/api/cities/products/${editProduct.id}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(draft)
      }), 'Shop stock could not be changed.');
      setEditProduct(null);
      setDraft(null);
    } catch (saveError) {
      setError(saveError instanceof Error ? saveError.message : 'Shop stock could not be changed.');
    } finally {
      setSaving(false);
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
        return (
          <Card key={vendor.id}>
            <div className="mb-4 flex items-center justify-between gap-3">
              <div>
                <p className="eyebrow">{vendor.facility}</p>
                <h3 className="mt-1 flex items-center gap-2 text-xl font-black"><Store size={18} className="text-[var(--brass)]" /> {vendor.name}</h3>
              </div>
              <span className="rounded-full border border-[var(--line)] bg-black/20 px-3 py-1 text-[10px] font-black uppercase text-[var(--muted)]">{vendor.category}</span>
            </div>
            <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
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
                      {isDm && <span role="button" tabIndex={0} onClick={(event) => { event.stopPropagation(); openEdit(product); }} className="rounded-lg border border-[var(--line)] bg-black/25 p-2 text-[var(--muted)]"><Pencil size={13} /></span>}
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
              <Button variant="secondary" onClick={() => setSelectedProduct(null)}>I’ll pass</Button>
              <Button variant="primary" disabled={!canShop || saving} onClick={buyProduct}><ShoppingBag className="mr-2 inline" size={15} /> Buy</Button>
            </div>
          </div>
        </Modal>
      )}

      {editProduct && draft && (
        <Modal title={`Edit ${editProduct.name}`} onClose={() => setEditProduct(null)}>
          <form onSubmit={saveProduct} className="grid gap-3">
            <TextField value={draft.name} onChange={(event) => setDraft({ ...draft, name: event.target.value })} />
            <TextAreaField rows={3} value={draft.description} onChange={(event) => setDraft({ ...draft, description: event.target.value })} />
            <div className="grid gap-2 sm:grid-cols-2">
              <SelectField value={draft.type} onChange={(event) => setDraft({ ...draft, type: event.target.value as ItemType })}>{ITEM_TYPES.map((type) => <option key={type} value={type}>{type}</option>)}</SelectField>
              <SelectField value={draft.rarity} onChange={(event) => setDraft({ ...draft, rarity: event.target.value as ItemRarity })}>{rarityOptions.map((rarity) => <option key={rarity} value={rarity}>{rarity}</option>)}</SelectField>
              <NumberInput min={0} value={draft.priceCoin} onValueChange={(priceCoin) => setDraft({ ...draft, priceCoin })} />
              <NumberInput min={0} value={draft.stockQuantity} onValueChange={(stockQuantity) => setDraft({ ...draft, stockQuantity })} />
            </div>
            <label className="flex items-center gap-2 rounded-xl border border-[var(--line)] bg-black/15 p-3 text-sm font-black">
              <input type="checkbox" checked={draft.available} onChange={(event) => setDraft({ ...draft, available: event.target.checked })} />
              Available for sale
            </label>
            <Button variant="primary" disabled={!draft.name.trim() || saving}><PackageCheck className="mr-2 inline" size={15} /> Save product</Button>
          </form>
        </Modal>
      )}
    </div>
  );
}
