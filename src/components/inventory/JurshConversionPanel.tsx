'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { ArrowRightLeft, Hammer, RefreshCw, ShieldAlert } from 'lucide-react';
import { ItemIcon } from '@/components/inventory/ItemIcon';
import { Button } from '@/components/ui/Button';
import { Card, SoftCard } from '@/components/ui/Card';
import { SelectField } from '@/components/ui/Field';
import { Modal } from '@/components/ui/Modal';
import { normalizeInventoryItem } from '@/features/inventory/data';
import { useLiveRefresh } from '@/hooks/useLiveRefresh';
import { rarityClass } from '@/lib/utils/rarity';
import type { InventoryItem, ItemRarity, ItemType } from '@/lib/types';

type ConversionRecipe = {
  key: string;
  itemName: string;
  itemType: ItemType;
  rarity: ItemRarity;
  material: string;
  scaleItemName: string;
  scaleQuantity: number;
  order: number;
};

type ConvertibleEntry = {
  item: InventoryItem;
  recipe: ConversionRecipe;
  hasExtras: boolean;
};

type ConversionState = {
  recipes: ConversionRecipe[];
  convertibleItems: ConvertibleEntry[];
  scaleTotals: Record<string, number>;
  dragonScaleTotal: number;
};

const EMPTY_STATE: ConversionState = {
  recipes: [],
  convertibleItems: [],
  scaleTotals: {},
  dragonScaleTotal: 0
};

const VALID_ITEM_TYPES: ItemType[] = ['weapon', 'armor', 'shield', 'pet', 'accessory', 'storage', 'material', 'catalyst', 'rune', 'ore', 'potion', 'food', 'plant', 'fabric', 'tool', 'quest', 'currency', 'misc'];
const VALID_RARITIES: ItemRarity[] = ['Common', 'Uncommon', 'Rare', 'Epic', 'Legendary', 'Mythical'];

function numberFrom(value: unknown, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function normalizeItemType(value: unknown): ItemType {
  return VALID_ITEM_TYPES.includes(value as ItemType) ? value as ItemType : 'misc';
}

function normalizeRarity(value: unknown): ItemRarity {
  return VALID_RARITIES.includes(value as ItemRarity) ? value as ItemRarity : 'Common';
}

function normalizeRecipe(value: unknown): ConversionRecipe | null {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  const key = String(source.key ?? '');
  const itemName = String(source.itemName ?? '');
  const scaleItemName = String(source.scaleItemName ?? '');
  if (!key || !itemName || !scaleItemName) return null;
  return {
    key,
    itemName,
    itemType: normalizeItemType(source.itemType),
    rarity: normalizeRarity(source.rarity),
    material: String(source.material ?? ''),
    scaleItemName,
    scaleQuantity: Math.max(0.5, numberFrom(source.scaleQuantity, 1)),
    order: numberFrom(source.order, 0)
  };
}

function normalizeState(value: unknown): ConversionState {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  const scaleSource = source.scaleTotals && typeof source.scaleTotals === 'object' && !Array.isArray(source.scaleTotals)
    ? source.scaleTotals as Record<string, unknown>
    : {};
  return {
    recipes: Array.isArray(source.recipes)
      ? source.recipes.map(normalizeRecipe).filter((recipe): recipe is ConversionRecipe => Boolean(recipe))
      : [],
    convertibleItems: Array.isArray(source.convertibleItems)
      ? source.convertibleItems.map((entry) => {
          const row = entry && typeof entry === 'object' ? entry as Record<string, unknown> : {};
          const recipe = normalizeRecipe(row.recipe);
          const item = normalizeInventoryItem(row.item);
          return recipe && item.id ? { item, recipe, hasExtras: Boolean(row.hasExtras) } : null;
        }).filter((entry): entry is ConvertibleEntry => Boolean(entry))
      : [],
    scaleTotals: Object.fromEntries(Object.entries(scaleSource).map(([key, value]) => [key, numberFrom(value, 0)])),
    dragonScaleTotal: numberFrom(source.dragonScaleTotal, 0)
  };
}

function formatQuantity(value: number) {
  return Number.isInteger(value) ? String(value) : value.toFixed(1);
}

export function JurshConversionPanel({ characterId, onConverted }: { characterId: string; onConverted: () => void }) {
  const [state, setState] = useState<ConversionState>(EMPTY_STATE);
  const [selectedItemId, setSelectedItemId] = useState('');
  const [selectedScaleName, setSelectedScaleName] = useState('');
  const [selectedRecipeKey, setSelectedRecipeKey] = useState('');
  const [confirmEntry, setConfirmEntry] = useState<ConvertibleEntry | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const loadState = useCallback(async (showLoading = true) => {
    if (showLoading) setLoading(true);
    setError('');
    try {
      const response = await fetch(`/api/characters/${characterId}/jursh-conversions`, { cache: 'no-store' });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(body.error ?? 'Jursh conversions could not be loaded.');
      const normalized = normalizeState(body);
      setState(normalized);
      setSelectedItemId((current) => current && normalized.convertibleItems.some((entry) => entry.item.id === current) ? current : normalized.convertibleItems[0]?.item.id ?? '');
      const firstScale = Object.keys(normalized.scaleTotals).find((scale) => normalized.scaleTotals[scale] > 0) ?? normalized.recipes[0]?.scaleItemName ?? '';
      setSelectedScaleName((current) => current && current in normalized.scaleTotals ? current : firstScale);
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : 'Jursh conversions could not be loaded.');
    } finally {
      if (showLoading) setLoading(false);
    }
  }, [characterId]);

  useEffect(() => {
    void loadState();
  }, [loadState]);

  useLiveRefresh(['inventory', 'cities', 'assets'], () => {
    void loadState(false);
  });

  const selectedEntry = state.convertibleItems.find((entry) => entry.item.id === selectedItemId) ?? null;
  const scaleNames = useMemo(() => Array.from(new Set(state.recipes.map((recipe) => recipe.scaleItemName))), [state.recipes]);
  const forgeRecipes = useMemo(() => state.recipes
    .filter((recipe) => recipe.scaleItemName === selectedScaleName)
    .sort((a, b) => a.scaleQuantity - b.scaleQuantity || a.order - b.order || a.itemName.localeCompare(b.itemName)), [selectedScaleName, state.recipes]);
  const selectedForgeRecipe = forgeRecipes.find((recipe) => recipe.key === selectedRecipeKey) ?? forgeRecipes.find((recipe) => (state.scaleTotals[recipe.scaleItemName] ?? 0) >= recipe.scaleQuantity) ?? forgeRecipes[0] ?? null;

  useEffect(() => {
    setSelectedRecipeKey((current) => current && forgeRecipes.some((recipe) => recipe.key === current) ? current : forgeRecipes[0]?.key ?? '');
  }, [forgeRecipes]);

  async function runAction(body: Record<string, unknown>) {
    setSaving(true);
    setError('');
    try {
      const response = await fetch(`/api/characters/${characterId}/jursh-conversions`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body)
      });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.error ?? 'Conversion failed.');
      if (payload.needsConfirmation && selectedEntry) {
        setConfirmEntry(selectedEntry);
      } else {
        setState(normalizeState(payload));
        setConfirmEntry(null);
        onConverted();
      }
    } catch (actionError) {
      setError(actionError instanceof Error ? actionError.message : 'Conversion failed.');
    } finally {
      setSaving(false);
    }
  }

  const canForgeDragonScale = state.dragonScaleTotal >= 25;
  const canForgeRecipe = Boolean(selectedForgeRecipe && (state.scaleTotals[selectedForgeRecipe.scaleItemName] ?? 0) >= selectedForgeRecipe.scaleQuantity);

  return (
    <Card>
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <p className="eyebrow">Jursh Conversion Forge</p>
          <h3 className="mt-1 text-2xl font-black">Scales In, Gear Out</h3>
        </div>
        <Button variant="secondary" className="p-3" disabled={saving} onClick={() => void loadState()} aria-label="Refresh Jursh conversions">
          <RefreshCw size={16} />
        </Button>
      </div>

      {error && <div className="mt-3 rounded-2xl border border-[var(--red)]/40 bg-[var(--red)]/10 p-3 text-sm text-[var(--red)]">{error}</div>}

      {loading ? (
        <div className="mt-4 h-24 animate-pulse rounded-2xl bg-black/20" />
      ) : (
        <div className="mt-4 grid gap-4">
          <div className="grid gap-3 lg:grid-cols-2">
            <SoftCard>
              <div className="mb-3 flex items-center gap-2 text-[var(--brass)]">
                <ArrowRightLeft size={18} />
                <p className="font-black">Break gear into scales</p>
              </div>
              <label className="grid gap-2">
                <span className="text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">Convertible item</span>
                <SelectField value={selectedItemId} onChange={(event) => setSelectedItemId(event.target.value)}>
                  <option value="">Choose item</option>
                  {state.convertibleItems.map((entry) => (
                    <option key={entry.item.id} value={entry.item.id}>
                      {entry.item.displayName || entry.item.name} &rarr; {formatQuantity(entry.recipe.scaleQuantity)} {entry.recipe.scaleItemName}{entry.hasExtras ? ' (extras)' : ''}
                    </option>
                  ))}
                </SelectField>
              </label>
              {selectedEntry ? (
                <ConversionPreview
                  inputName={selectedEntry.item.displayName || selectedEntry.item.name}
                  inputType={selectedEntry.item.type}
                  inputRarity={selectedEntry.item.rarity}
                  inputQuantity={1}
                  outputName={selectedEntry.recipe.scaleItemName}
                  outputType="material"
                  outputRarity={selectedEntry.recipe.rarity}
                  outputQuantity={selectedEntry.recipe.scaleQuantity}
                  warning={selectedEntry.hasExtras ? 'This destroys modifiers, enhancements, runes, and enchantments.' : ''}
                />
              ) : (
                <p className="mt-3 rounded-xl border border-[var(--line)] bg-black/15 p-3 text-sm font-bold text-[var(--muted)]">Jursh has no convertible gear on hand.</p>
              )}
              <Button
                className="mt-3 w-full"
                variant="primary"
                disabled={saving || !selectedEntry}
                onClick={() => selectedEntry?.hasExtras ? setConfirmEntry(selectedEntry) : void runAction({ action: 'item-to-scales', itemId: selectedEntry?.item.id })}
              >
                Convert to Scales
              </Button>
            </SoftCard>

            <SoftCard>
              <div className="mb-3 flex items-center gap-2 text-[var(--brass)]">
                <Hammer size={18} />
                <p className="font-black">Forge gear from scales</p>
              </div>
              <div className="grid gap-2 sm:grid-cols-2">
                <label className="grid gap-2">
                  <span className="text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">Scale stock</span>
                  <SelectField value={selectedScaleName} onChange={(event) => setSelectedScaleName(event.target.value)}>
                    {scaleNames.map((scaleName) => (
                      <option key={scaleName} value={scaleName}>
                        {scaleName} x{formatQuantity(state.scaleTotals[scaleName] ?? 0)}
                      </option>
                    ))}
                  </SelectField>
                </label>
                <label className="grid gap-2">
                  <span className="text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">Output</span>
                  <SelectField value={selectedForgeRecipe?.key ?? ''} onChange={(event) => setSelectedRecipeKey(event.target.value)}>
                    {forgeRecipes.map((recipe) => (
                      <option key={recipe.key} value={recipe.key}>
                        {recipe.itemName} - {formatQuantity(recipe.scaleQuantity)} scales
                      </option>
                    ))}
                  </SelectField>
                </label>
              </div>
              {selectedForgeRecipe && (
                <ConversionPreview
                  inputName={selectedForgeRecipe.scaleItemName}
                  inputType="material"
                  inputRarity={selectedForgeRecipe.rarity}
                  inputQuantity={selectedForgeRecipe.scaleQuantity}
                  outputName={selectedForgeRecipe.itemName}
                  outputType={selectedForgeRecipe.itemType}
                  outputRarity={selectedForgeRecipe.rarity}
                  outputQuantity={1}
                  warning={canForgeRecipe ? '' : `Need ${formatQuantity(selectedForgeRecipe.scaleQuantity)} ${selectedForgeRecipe.scaleItemName}.`}
                />
              )}
              <Button
                className="mt-3 w-full"
                variant="primary"
                disabled={saving || !selectedForgeRecipe || !canForgeRecipe}
                onClick={() => void runAction({ action: 'scales-to-item', recipeKey: selectedForgeRecipe?.key })}
              >
                Forge Item
              </Button>
            </SoftCard>
          </div>

          <SoftCard>
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div>
                <p className="eyebrow">Dragon Scale Refining</p>
                <p className="mt-1 font-black">25 mixed dragon scale fragments &rarr; 1 Dragonscale Scale</p>
                <p className="mt-1 text-sm font-bold text-[var(--muted)]">Jursh has {formatQuantity(state.dragonScaleTotal)} / 25 fragments on hand.</p>
              </div>
              <Button variant="teal" disabled={saving || !canForgeDragonScale} onClick={() => void runAction({ action: 'dragon-scales' })}>
                Forge Dragonscale Scale
              </Button>
            </div>
          </SoftCard>
        </div>
      )}

      {confirmEntry && (
        <Modal title="Destroy Item Extras?" onClose={() => setConfirmEntry(null)}>
          <div className="grid gap-4">
            <div className="rounded-2xl border border-[var(--red)]/40 bg-[var(--red)]/10 p-4">
              <div className="flex items-start gap-3">
                <ShieldAlert className="mt-1 shrink-0 text-[var(--red)]" size={22} />
                <div>
                  <p className="font-black">{confirmEntry.item.displayName || confirmEntry.item.name}</p>
                  <p className="mt-1 text-sm leading-6 text-[var(--muted)]">
                    This conversion destroys modifiers, enhancements, runes, and enchantments on the item. The output is only {formatQuantity(confirmEntry.recipe.scaleQuantity)} {confirmEntry.recipe.scaleItemName}.
                  </p>
                </div>
              </div>
            </div>
            <div className="grid grid-cols-2 gap-2">
              <Button variant="secondary" disabled={saving} onClick={() => setConfirmEntry(null)}>Cancel</Button>
              <Button variant="danger" disabled={saving} onClick={() => void runAction({ action: 'item-to-scales', itemId: confirmEntry.item.id, confirmDestroyExtras: true })}>Proceed</Button>
            </div>
          </div>
        </Modal>
      )}
    </Card>
  );
}

function ConversionPreview({
  inputName,
  inputType,
  inputRarity,
  inputQuantity,
  outputName,
  outputType,
  outputRarity,
  outputQuantity,
  warning
}: {
  inputName: string;
  inputType: ItemType;
  inputRarity: ItemRarity;
  inputQuantity: number;
  outputName: string;
  outputType: ItemType;
  outputRarity: ItemRarity;
  outputQuantity: number;
  warning?: string;
}) {
  return (
    <div className="mt-3 grid items-center gap-3 md:grid-cols-[1fr_auto_1fr]">
      <PreviewItem name={inputName} type={inputType} rarity={inputRarity} quantity={inputQuantity} />
      <div className="grid place-items-center text-[var(--brass)]"><ArrowRightLeft size={24} /></div>
      <PreviewItem name={outputName} type={outputType} rarity={outputRarity} quantity={outputQuantity} featured />
      {warning && <p className="md:col-span-3 rounded-xl border border-[var(--red)]/35 bg-[var(--red)]/10 p-3 text-xs font-bold text-[var(--red)]">{warning}</p>}
    </div>
  );
}

function PreviewItem({ name, type, rarity, quantity, featured = false }: {
  name: string;
  type: ItemType;
  rarity: ItemRarity;
  quantity: number;
  featured?: boolean;
}) {
  return (
    <div className={`rounded-2xl border p-3 ${rarityClass(rarity)} ${featured ? 'ring-2 ring-[var(--brass)] ring-offset-2 ring-offset-[#120907]' : ''}`}>
      <div className="flex items-start gap-3">
        <span className="grid h-10 w-10 shrink-0 place-items-center rounded-xl bg-black/25 text-[var(--brass)]"><ItemIcon type={type} size={20} /></span>
        <span className="min-w-0">
          <span className="block break-words text-sm font-black leading-5">{name}</span>
          <span className="mt-1 block text-xs font-black uppercase tracking-wider text-[var(--muted)]">{rarity} {type} - x{formatQuantity(quantity)}</span>
        </span>
      </div>
    </div>
  );
}
