'use client';

import { useCallback, useEffect, useMemo, useState, type FormEvent } from 'react';
import { Loader2, Pencil, RefreshCw, Save } from 'lucide-react';
import { Button } from '@/components/ui/Button';
import { Card } from '@/components/ui/Card';
import { Modal } from '@/components/ui/Modal';
import { NumberInput } from '@/components/ui/NumberInput';
import { ColorField, SelectField, TextAreaField, TextField } from '@/components/ui/Field';
import { normalizeUpdateAssetsPayload, type UpdateAssetsPayload } from '@/features/assets/data';
import { ITEM_TYPES } from '@/features/inventory/data';
import { SPELL_SCHOOLS, SPELL_TYPES } from '@/features/spells/data';
import { useLiveRefresh } from '@/hooks/useLiveRefresh';
import { ATTRIBUTE_KEYS, ATTRIBUTE_LABELS, type BestiaryEntity, type ClassTemplate, type ItemCatalogEntry, type ItemRarity, type LootItem, type MarketProduct, type Spell } from '@/lib/types';
import { rarityOptions } from '@/lib/utils/rarity';
import { spellManaText } from '@/lib/utils/spells';

type EditorTarget =
  | { kind: 'class'; value: ClassTemplate }
  | { kind: 'product'; value: MarketProduct }
  | { kind: 'item'; value: ItemCatalogEntry }
  | { kind: 'spell'; value: Spell }
  | { kind: 'loot'; value: LootItem }
  | { kind: 'bestiary'; value: BestiaryEntity };

const EMPTY_ASSETS: UpdateAssetsPayload = {
  classes: [],
  cities: [],
  vendors: [],
  itemCatalog: [],
  spells: [],
  lootPools: [],
  lootItems: [],
  bestiary: []
};

function endpointFor(target: EditorTarget) {
  if (target.kind === 'class') return `/api/assets/classes/${target.value.id}`;
  if (target.kind === 'product') return `/api/cities/products/${target.value.id}`;
  if (target.kind === 'item') return `/api/assets/items/${target.value.id}`;
  if (target.kind === 'spell') return `/api/assets/spells/${target.value.id}`;
  if (target.kind === 'loot') return `/api/assets/loot/${target.value.id}`;
  return `/api/bestiary/entities/${target.value.id}`;
}

function titleFor(target: EditorTarget) {
  if (target.kind === 'class') return `Edit ${target.value.name}`;
  if (target.kind === 'product') return `Edit ${target.value.name}`;
  if (target.kind === 'item') return `Edit ${target.value.name}`;
  if (target.kind === 'spell') return `Edit ${target.value.name}`;
  if (target.kind === 'loot') return `Edit ${target.value.name}`;
  return `Edit ${target.value.name}`;
}

function parsePassives(text: string) {
  return text.split(/\r?\n/).map((line) => line.trim()).filter(Boolean);
}

export function UpdateAssetsPanel() {
  const [assets, setAssets] = useState<UpdateAssetsPayload>(EMPTY_ASSETS);
  const [target, setTarget] = useState<EditorTarget | null>(null);
  const [draft, setDraft] = useState<Record<string, unknown>>({});
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const loadAssets = useCallback(async (showLoading = true) => {
    if (showLoading) setLoading(true);
    setError('');
    try {
      const response = await fetch('/api/assets', { cache: 'no-store' });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.error ?? 'Assets could not be loaded.');
      setAssets(normalizeUpdateAssetsPayload(payload));
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : 'Assets could not be loaded.');
    } finally {
      if (showLoading) setLoading(false);
    }
  }, []);

  useLiveRefresh(['assets', 'cities', 'bestiary', 'spells', 'exploration'], () => loadAssets(false));

  useEffect(() => {
    void loadAssets();
  }, [loadAssets]);

  const productsByCity = useMemo(() => {
    return assets.cities.map((city) => ({
      city,
      vendors: assets.vendors.filter((vendor) => vendor.cityKey === city.key)
    }));
  }, [assets.cities, assets.vendors]);

  const lootByPool = useMemo(() => {
    return assets.lootPools.map((pool) => ({
      pool,
      items: assets.lootItems.filter((item) => item.poolId === pool.id)
    }));
  }, [assets.lootItems, assets.lootPools]);

  const bestiaryCategoryOptions = useMemo(() => {
    return Array.from(new Set(assets.bestiary.map((entity) => entity.category).filter(Boolean))).sort((a, b) => a.localeCompare(b));
  }, [assets.bestiary]);

  function openEditor(next: EditorTarget) {
    setTarget(next);
    if (next.kind === 'class') {
      setDraft({
        ...next.value,
        passivesText: next.value.passives.join('\n'),
        applyToCharacters: false
      });
      return;
    }
    if (next.kind === 'loot') {
      setDraft({
        ...next.value,
        biomesText: next.value.biomes.join(', ')
      });
      return;
    }
    setDraft(next.value);
  }

  async function saveTarget(event: FormEvent) {
    event.preventDefault();
    if (!target || saving) return;
    setSaving(true);
    setError('');
    try {
      const body = target.kind === 'class'
        ? { ...draft, passives: parsePassives(String(draft.passivesText ?? '')) }
        : draft;
      const response = await fetch(endpointFor(target), {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body)
      });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.error ?? 'Asset could not be saved.');
      const normalized = normalizeUpdateAssetsPayload(payload);
      if (normalized.classes.length || normalized.vendors.length || normalized.itemCatalog.length || normalized.spells.length || normalized.lootItems.length || normalized.bestiary.length) {
        setAssets(normalized);
      } else {
        await loadAssets(false);
      }
      setTarget(null);
    } catch (saveError) {
      setError(saveError instanceof Error ? saveError.message : 'Asset could not be saved.');
    } finally {
      setSaving(false);
    }
  }

  function updateDraft(key: string, value: unknown) {
    setDraft((current) => ({ ...current, [key]: value }));
  }

  return (
    <div className="grid gap-4">
      <Card>
        <div className="flex items-center justify-between gap-3">
          <div>
            <p className="eyebrow">Dungeon Master</p>
            <h2 className="mt-1 text-3xl font-black">Update Assets</h2>
          </div>
          <Button variant="secondary" className="p-3" onClick={() => void loadAssets()} aria-label="Refresh assets">
            <RefreshCw size={17} />
          </Button>
        </div>
        {error && <div className="mt-4 rounded-2xl border border-[var(--red)]/40 bg-[var(--red)]/10 p-3 text-sm text-[var(--red)]">{error}</div>}
      </Card>

      {loading ? (
        <Card>
          <div className="grid h-40 place-items-center text-[var(--muted)]"><Loader2 className="animate-spin" /></div>
        </Card>
      ) : (
        <>
          <Card>
            <div className="rule-title mb-3"><h3 className="text-sm font-black uppercase tracking-wider">Classes</h3></div>
            <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
              {assets.classes.map((entry) => (
                <AssetButton key={entry.id} title={entry.name} subtitle={`${entry.baseHp} HP · ${entry.baseMana} Mana · ${entry.inventorySlots} slots`} onClick={() => openEditor({ kind: 'class', value: entry })} />
              ))}
            </div>
          </Card>

          <Card>
            <div className="rule-title mb-3"><h3 className="text-sm font-black uppercase tracking-wider">Stores by City</h3></div>
            <div className="grid gap-3">
              {productsByCity.map(({ city, vendors }) => (
                <details key={city.id} className="rounded-2xl border border-[var(--line)] bg-black/15">
                  <summary className="cursor-pointer list-none p-3 font-black">{city.name}</summary>
                  <div className="grid gap-3 border-t border-[var(--line)] p-3">
                    {vendors.map((vendor) => (
                      <div key={vendor.id}>
                        <p className="mb-2 text-xs font-black uppercase tracking-wide text-[var(--brass)]">{vendor.facility} · {vendor.name}</p>
                        <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
                          {vendor.products.map((product) => (
                            <AssetButton key={product.id} title={product.name} subtitle={`${product.rarity} · ${product.priceCoin} coin · ${product.stockQuantity ?? '∞'} stock`} onClick={() => openEditor({ kind: 'product', value: product })} />
                          ))}
                        </div>
                      </div>
                    ))}
                  </div>
                </details>
              ))}
            </div>
          </Card>

          <Card>
            <div className="rule-title mb-3"><h3 className="text-sm font-black uppercase tracking-wider">Spells</h3></div>
            <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
              {assets.spells.map((entry) => (
                <AssetButton key={entry.id} title={entry.name} subtitle={`${entry.type} · ${spellManaText(entry)} · ${entry.rarity}`} onClick={() => openEditor({ kind: 'spell', value: entry })} />
              ))}
            </div>
          </Card>

          <Card>
            <div className="rule-title mb-3"><h3 className="text-sm font-black uppercase tracking-wider">Global Item Catalog</h3></div>
            <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
              {assets.itemCatalog.map((item) => (
                <AssetButton
                  key={item.id}
                  title={item.name}
                  subtitle={`${item.rarity} · ${item.type} · step ${item.quantityStep}`}
                  onClick={() => openEditor({ kind: 'item', value: item })}
                />
              ))}
              {!assets.itemCatalog.length && <p className="text-sm text-[var(--muted)]">No catalog items loaded.</p>}
            </div>
          </Card>

          <Card>
            <div className="rule-title mb-3"><h3 className="text-sm font-black uppercase tracking-wider">Loot Generator Items</h3></div>
            <div className="grid gap-3">
              {lootByPool.map(({ pool, items }) => (
                <details key={pool.id} className="rounded-2xl border border-[var(--line)] bg-black/15">
                  <summary className="cursor-pointer list-none p-3 font-black">{pool.name}</summary>
                  <div className="grid gap-2 border-t border-[var(--line)] p-3 sm:grid-cols-2 lg:grid-cols-3">
                    {items.map((item) => <AssetButton key={item.id} title={item.name} subtitle={`${item.rarity} · ${item.type} · ${item.minQuantity}-${item.maxQuantity}`} onClick={() => openEditor({ kind: 'loot', value: item })} />)}
                  </div>
                </details>
              ))}
            </div>
          </Card>

          <Card>
            <div className="rule-title mb-3"><h3 className="text-sm font-black uppercase tracking-wider">Bestiary</h3></div>
            <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
              {assets.bestiary.map((entry) => (
                <AssetButton key={entry.id} title={entry.name} subtitle={`${entry.category} · ${entry.unlocked ? 'Visible' : 'Hidden'} · Wild ${entry.wildScore}`} onClick={() => openEditor({ kind: 'bestiary', value: entry })} />
              ))}
            </div>
          </Card>
        </>
      )}

      {target && (
        <Modal title={titleFor(target)} onClose={() => setTarget(null)}>
          <form onSubmit={saveTarget} className="grid gap-3">
            {target.kind === 'class' && (
              <>
                <TextField value={String(draft.name ?? '')} onChange={(event) => updateDraft('name', event.target.value)} placeholder="Class name" />
                <div className="grid gap-2 sm:grid-cols-2">
                  <TextField value={String(draft.role ?? '')} onChange={(event) => updateDraft('role', event.target.value)} placeholder="Role" />
                  <TextField value={String(draft.armor ?? '')} onChange={(event) => updateDraft('armor', event.target.value)} placeholder="Armor" />
                </div>
                <TextAreaField rows={3} value={String(draft.identity ?? '')} onChange={(event) => updateDraft('identity', event.target.value)} placeholder="Identity" />
                <div className="grid gap-2 sm:grid-cols-5">
                  <label><span className="mb-1 block text-[10px] font-black uppercase text-[var(--muted)]">Health</span><NumberInput value={Number(draft.baseHp ?? 0)} onValueChange={(value) => updateDraft('baseHp', value)} /></label>
                  <label><span className="mb-1 block text-[10px] font-black uppercase text-[var(--muted)]">Mana</span><NumberInput value={Number(draft.baseMana ?? 0)} onValueChange={(value) => updateDraft('baseMana', value)} /></label>
                  <label><span className="mb-1 block text-[10px] font-black uppercase text-[var(--muted)]">Magic Resist</span><NumberInput value={Number(draft.baseMagicResist ?? 0)} onValueChange={(value) => updateDraft('baseMagicResist', value)} /></label>
                  <label><span className="mb-1 block text-[10px] font-black uppercase text-[var(--muted)]">Inventory</span><NumberInput value={Number(draft.inventorySlots ?? 0)} onValueChange={(value) => updateDraft('inventorySlots', value)} /></label>
                  <label><span className="mb-1 block text-[10px] font-black uppercase text-[var(--muted)]">Spells</span><NumberInput value={Number(draft.spellSlots ?? 0)} onValueChange={(value) => updateDraft('spellSlots', value)} /></label>
                </div>
                <ColorField aria-label="Class color" value={String(draft.tokenColor ?? '#9caf79')} onChange={(event) => updateDraft('tokenColor', event.target.value)} />
                <div className="grid gap-2 sm:grid-cols-3">
                  {ATTRIBUTE_KEYS.map((key) => {
                    const attrs = (draft.attributes ?? {}) as Record<string, number>;
                    return (
                      <label key={key}>
                        <span className="mb-1 block text-[10px] font-black uppercase text-[var(--muted)]">{ATTRIBUTE_LABELS[key]}</span>
                        <NumberInput value={Number(attrs[key] ?? 0)} onValueChange={(value) => updateDraft('attributes', { ...attrs, [key]: value })} />
                      </label>
                    );
                  })}
                </div>
                <TextAreaField rows={5} value={String(draft.passivesText ?? '')} onChange={(event) => updateDraft('passivesText', event.target.value)} placeholder="One passive per line" />
                <label className="flex items-center gap-2 rounded-xl border border-[var(--line)] bg-black/20 p-3 text-sm font-black">
                  <input type="checkbox" checked={Boolean(draft.applyToCharacters)} onChange={(event) => updateDraft('applyToCharacters', event.target.checked)} />
                  Apply these class stats/passives to existing characters of this class
                </label>
              </>
            )}

            {target.kind === 'product' && (
              <>
                <TextField value={String(draft.name ?? '')} onChange={(event) => updateDraft('name', event.target.value)} placeholder="Item name" />
                <TextAreaField rows={3} value={String(draft.description ?? '')} onChange={(event) => updateDraft('description', event.target.value)} placeholder="Description" />
                <div className="grid gap-2 sm:grid-cols-2">
                  <SelectField value={String(draft.type ?? 'misc')} onChange={(event) => updateDraft('type', event.target.value)}>{ITEM_TYPES.map((type) => <option key={type} value={type}>{type}</option>)}</SelectField>
                  <SelectField value={String(draft.rarity ?? 'Common')} onChange={(event) => updateDraft('rarity', event.target.value as ItemRarity)}>{rarityOptions.map((rarity) => <option key={rarity} value={rarity}>{rarity}</option>)}</SelectField>
                  <NumberInput value={Number(draft.priceCoin ?? 0)} onValueChange={(value) => updateDraft('priceCoin', value)} />
                  <NumberInput value={Number(draft.stockQuantity ?? 0)} onValueChange={(value) => updateDraft('stockQuantity', value)} />
                </div>
                <label className="flex items-center gap-2 rounded-xl border border-[var(--line)] bg-black/20 p-3 text-sm font-black"><input type="checkbox" checked={Boolean(draft.available)} onChange={(event) => updateDraft('available', event.target.checked)} /> Available</label>
              </>
            )}

            {target.kind === 'item' && (
              <>
                <TextField value={String(draft.name ?? '')} onChange={(event) => updateDraft('name', event.target.value)} placeholder="Item name" />
                <div className="grid gap-2 sm:grid-cols-2">
                  <SelectField value={String(draft.type ?? 'misc')} onChange={(event) => updateDraft('type', event.target.value)}>{ITEM_TYPES.map((type) => <option key={type} value={type}>{type}</option>)}</SelectField>
                  <SelectField value={String(draft.rarity ?? 'Common')} onChange={(event) => updateDraft('rarity', event.target.value as ItemRarity)}>{rarityOptions.map((rarity) => <option key={rarity} value={rarity}>{rarity}</option>)}</SelectField>
                  <TextField value={String(draft.category ?? '')} onChange={(event) => updateDraft('category', event.target.value)} placeholder="Category" />
                  <TextField value={String(draft.material ?? '')} onChange={(event) => updateDraft('material', event.target.value)} placeholder="Material" />
                  <NumberInput value={Number(draft.quantityStep ?? 1)} min={0.5} step={0.5} onValueChange={(value) => updateDraft('quantityStep', value)} />
                  <NumberInput value={Number(draft.storageCapacity ?? 0)} min={0} onValueChange={(value) => updateDraft('storageCapacity', value)} />
                </div>
                <TextAreaField rows={3} value={Array.isArray(draft.properties) ? draft.properties.join('\n') : String(draft.properties ?? '')} onChange={(event) => updateDraft('properties', event.target.value.split(/\r?\n/).map((line) => line.trim()).filter(Boolean))} placeholder="One property per line" />
                <TextAreaField rows={3} value={JSON.stringify(draft.defaultModifiers ?? {}, null, 2)} onChange={(event) => {
                  try {
                    updateDraft('defaultModifiers', JSON.parse(event.target.value));
                  } catch {
                    updateDraft('defaultModifiers', draft.defaultModifiers ?? {});
                  }
                }} placeholder="Modifier JSON" />
                <TextAreaField rows={3} value={String(draft.notes ?? '')} onChange={(event) => updateDraft('notes', event.target.value)} placeholder="Notes" />
                <div className="grid gap-2 sm:grid-cols-3">
                  <label className="flex items-center gap-2 rounded-xl border border-[var(--line)] bg-black/20 p-3 text-sm font-black"><input type="checkbox" checked={Boolean(draft.stackable)} onChange={(event) => updateDraft('stackable', event.target.checked)} /> Stackable</label>
                  <label className="flex items-center gap-2 rounded-xl border border-[var(--line)] bg-black/20 p-3 text-sm font-black"><input type="checkbox" checked={Boolean(draft.isTwoHanded)} onChange={(event) => updateDraft('isTwoHanded', event.target.checked)} /> Two-handed</label>
                  <label className="flex items-center gap-2 rounded-xl border border-[var(--line)] bg-black/20 p-3 text-sm font-black"><input type="checkbox" checked={Boolean(draft.active)} onChange={(event) => updateDraft('active', event.target.checked)} /> Visible</label>
                </div>
              </>
            )}

            {target.kind === 'spell' && (
              <>
                <TextField value={String(draft.name ?? '')} onChange={(event) => updateDraft('name', event.target.value)} placeholder="Spell name" />
                <div className="grid gap-2 sm:grid-cols-4">
                  <SelectField value={String(draft.type ?? 'Utility')} onChange={(event) => updateDraft('type', event.target.value)}>{SPELL_TYPES.map((type) => <option key={type} value={type}>{type}</option>)}</SelectField>
                  <SelectField value={String(draft.school ?? 'arcane')} onChange={(event) => updateDraft('school', event.target.value)}>{SPELL_SCHOOLS.map((school) => <option key={school} value={school}>{school}</option>)}</SelectField>
                  <NumberInput value={Number(draft.manaCost ?? 0)} onValueChange={(value) => updateDraft('manaCost', value)} />
                  <SelectField value={String(draft.rarity ?? 'Common')} onChange={(event) => updateDraft('rarity', event.target.value as ItemRarity)}>{rarityOptions.map((rarity) => <option key={rarity} value={rarity}>{rarity}</option>)}</SelectField>
                </div>
                <TextField value={String(draft.manaLabel ?? '')} onChange={(event) => updateDraft('manaLabel', event.target.value)} placeholder="Mana label" />
                <TextAreaField rows={3} value={String(draft.summary ?? '')} onChange={(event) => updateDraft('summary', event.target.value)} placeholder="Summary" />
                <TextAreaField rows={5} value={String(draft.details ?? '')} onChange={(event) => updateDraft('details', event.target.value)} placeholder="Details" />
              </>
            )}

            {target.kind === 'loot' && (
              <>
                <TextField value={String(draft.name ?? '')} onChange={(event) => updateDraft('name', event.target.value)} placeholder="Loot item" />
                <div className="grid gap-2 sm:grid-cols-2">
                  <SelectField value={String(draft.type ?? 'misc')} onChange={(event) => updateDraft('type', event.target.value)}>{ITEM_TYPES.map((type) => <option key={type} value={type}>{type}</option>)}</SelectField>
                  <SelectField value={String(draft.rarity ?? 'Common')} onChange={(event) => updateDraft('rarity', event.target.value as ItemRarity)}>{rarityOptions.map((rarity) => <option key={rarity} value={rarity}>{rarity}</option>)}</SelectField>
                  <NumberInput value={Number(draft.minDifficulty ?? 1)} onValueChange={(value) => updateDraft('minDifficulty', value)} />
                  <NumberInput value={Number(draft.maxDifficulty ?? 5)} onValueChange={(value) => updateDraft('maxDifficulty', value)} />
                  <NumberInput value={Number(draft.weight ?? 1)} onValueChange={(value) => updateDraft('weight', value)} />
                  <NumberInput value={Number(draft.minQuantity ?? 1)} onValueChange={(value) => updateDraft('minQuantity', value)} />
                  <NumberInput value={Number(draft.maxQuantity ?? 1)} onValueChange={(value) => updateDraft('maxQuantity', value)} />
                </div>
                <TextField value={String(draft.biomesText ?? 'Any')} onChange={(event) => updateDraft('biomesText', event.target.value)} placeholder="Biomes, comma separated" />
                <label className="flex items-center gap-2 rounded-xl border border-[var(--line)] bg-black/20 p-3 text-sm font-black">
                  <input type="checkbox" checked={Boolean(draft.towerBaseOnly)} onChange={(event) => updateDraft('towerBaseOnly', event.target.checked)} />
                  Tower/Base only
                </label>
                <label className="flex items-center gap-2 rounded-xl border border-[var(--line)] bg-black/20 p-3 text-sm font-black">
                  <input type="checkbox" checked={draft.stackable === undefined ? true : Boolean(draft.stackable)} onChange={(event) => updateDraft('stackable', event.target.checked)} />
                  Stackable
                </label>
                <TextAreaField rows={3} value={String(draft.notes ?? '')} onChange={(event) => updateDraft('notes', event.target.value)} placeholder="Notes" />
              </>
            )}

            {target.kind === 'bestiary' && (
              <>
                <TextField value={String(draft.name ?? '')} onChange={(event) => updateDraft('name', event.target.value)} placeholder="Entity name" />
                <div className="grid gap-2 sm:grid-cols-3">
                  <SelectField value={String(draft.category ?? bestiaryCategoryOptions[0] ?? '')} onChange={(event) => updateDraft('category', event.target.value)}>
                    {bestiaryCategoryOptions.map((category) => <option key={category} value={category}>{category}</option>)}
                  </SelectField>
                  <NumberInput value={Number(draft.wildScore ?? 0)} onValueChange={(value) => updateDraft('wildScore', value)} />
                  <label className="flex items-center gap-2 rounded-xl border border-[var(--line)] bg-black/20 p-3 text-sm font-black"><input type="checkbox" checked={Boolean(draft.unlocked)} onChange={(event) => updateDraft('unlocked', event.target.checked)} /> Visible</label>
                </div>
                <div className="grid gap-2 sm:grid-cols-2">
                  <TextField value={String(draft.habitat ?? '')} onChange={(event) => updateDraft('habitat', event.target.value)} placeholder="Habitat" />
                  <TextField value={String(draft.temperament ?? '')} onChange={(event) => updateDraft('temperament', event.target.value)} placeholder="Temperament" />
                  <NumberInput value={Number(draft.hp ?? 0)} onValueChange={(value) => updateDraft('hp', value)} />
                  <NumberInput value={Number(draft.mana ?? 0)} onValueChange={(value) => updateDraft('mana', value)} />
                </div>
                <TextAreaField rows={3} value={String(draft.summary ?? '')} onChange={(event) => updateDraft('summary', event.target.value)} placeholder="Summary" />
                <TextAreaField rows={5} value={String(draft.details ?? '')} onChange={(event) => updateDraft('details', event.target.value)} placeholder="Details" />
              </>
            )}

            <Button variant="primary" disabled={saving} className="flex items-center justify-center gap-2">
              {saving ? <Loader2 size={16} className="animate-spin" /> : <Save size={16} />} Save asset
            </Button>
          </form>
        </Modal>
      )}
    </div>
  );
}

function AssetButton({ title, subtitle, onClick }: { title: string; subtitle: string; onClick: () => void }) {
  return (
    <button type="button" onClick={onClick} className="rounded-2xl border border-[var(--line)] bg-black/15 p-3 text-left transition hover:border-[var(--brass)] active:scale-[0.99]">
      <span className="flex items-start justify-between gap-2">
        <span className="min-w-0">
          <span className="block truncate font-black">{title}</span>
          <span className="mt-1 block truncate text-xs text-[var(--muted)]">{subtitle}</span>
        </span>
        <Pencil size={15} className="shrink-0 text-[var(--brass)]" />
      </span>
    </button>
  );
}
