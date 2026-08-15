'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { ArrowRightLeft, Hammer, RefreshCw, ShieldAlert, Sparkles } from 'lucide-react';
import { ItemIcon } from '@/components/inventory/ItemIcon';
import { Button } from '@/components/ui/Button';
import { Card, SoftCard } from '@/components/ui/Card';
import { Modal } from '@/components/ui/Modal';
import { NumberInput } from '@/components/ui/NumberInput';
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

type SourceEntry = {
  source: 'inventory';
  item: InventoryItem;
};

type ConversionState = {
  recipes: ConversionRecipe[];
  convertibleItems: ConvertibleEntry[];
  scaleItems: SourceEntry[];
  dragonScaleItems: SourceEntry[];
  dragonScaleTotal: number;
};

type BreakdownSelection = {
  entry: ConvertibleEntry;
  quantity: number;
};

type ConversionConfirmMode = 'breakdown' | 'forge' | 'dragon-scales';

const EMPTY_STATE: ConversionState = {
  recipes: [],
  convertibleItems: [],
  scaleItems: [],
  dragonScaleItems: [],
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

function normalizeSourceEntry(value: unknown): SourceEntry | null {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  const item = normalizeInventoryItem(source.item);
  return item.id ? { source: 'inventory', item } : null;
}

function normalizeState(value: unknown): ConversionState {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
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
    scaleItems: Array.isArray(source.scaleItems)
      ? source.scaleItems.map(normalizeSourceEntry).filter((entry): entry is SourceEntry => Boolean(entry))
      : [],
    dragonScaleItems: Array.isArray(source.dragonScaleItems)
      ? source.dragonScaleItems.map(normalizeSourceEntry).filter((entry): entry is SourceEntry => Boolean(entry))
      : [],
    dragonScaleTotal: numberFrom(source.dragonScaleTotal, 0)
  };
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

function sourceItemKey(entry: SourceEntry) {
  return `${entry.source}:${entry.item.id}`;
}

function selectedEntries(items: SourceEntry[], selections: Record<string, number>) {
  return items
    .map((entry) => ({ ...entry, quantity: Math.max(0, selections[sourceItemKey(entry)] ?? 0) }))
    .filter((entry) => entry.quantity > 0);
}

export function JurshConversionPanel({ characterId, onConverted }: { characterId: string; onConverted: () => void }) {
  const [state, setState] = useState<ConversionState>(EMPTY_STATE);
  const [breakdownPickerOpen, setBreakdownPickerOpen] = useState(false);
  const [scalePickerOpen, setScalePickerOpen] = useState(false);
  const [dragonPickerOpen, setDragonPickerOpen] = useState(false);
  const [breakdownSelection, setBreakdownSelection] = useState<BreakdownSelection | null>(null);
  const [scaleSelections, setScaleSelections] = useState<Record<string, number>>({});
  const [dragonSelections, setDragonSelections] = useState<Record<string, number>>({});
  const [selectedRecipeKey, setSelectedRecipeKey] = useState('');
  const [confirmConversion, setConfirmConversion] = useState<ConversionConfirmMode | null>(null);
  const [confirmBreakdown, setConfirmBreakdown] = useState<BreakdownSelection | null>(null);
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
      setState(normalizeState(body));
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

  const selectedScaleItems = useMemo(() => selectedEntries(state.scaleItems, scaleSelections), [scaleSelections, state.scaleItems]);
  const selectedDragonItems = useMemo(() => selectedEntries(state.dragonScaleItems, dragonSelections), [dragonSelections, state.dragonScaleItems]);
  const selectedScaleTotal = selectedScaleItems.reduce((total, entry) => total + entry.quantity, 0);
  const selectedDragonTotal = selectedDragonItems.reduce((total, entry) => total + entry.quantity, 0);
  const selectedDragonOutput = dragonScaleOutputQuantity(selectedDragonTotal);
  const selectedDragonConsumed = dragonScaleConsumedQuantity(selectedDragonTotal);
  const selectedDragonReturned = dragonScaleReturnedQuantity(selectedDragonTotal);
  const selectedScaleNames = Array.from(new Set(selectedScaleItems.map((entry) => entry.item.name)));
  const selectedScaleName = selectedScaleNames.length === 1 ? selectedScaleNames[0] : '';
  const compatibleForgeRecipes = useMemo(() => selectedScaleName
    ? state.recipes
      .filter((recipe) => recipe.scaleItemName.toLowerCase() === selectedScaleName.toLowerCase() && recipe.scaleQuantity <= selectedScaleTotal)
      .sort((a, b) => a.scaleQuantity - b.scaleQuantity || a.order - b.order || a.itemName.localeCompare(b.itemName))
    : [], [selectedScaleName, selectedScaleTotal, state.recipes]);
  const selectedForgeRecipe = compatibleForgeRecipes.find((recipe) => recipe.key === selectedRecipeKey) ?? null;

  useEffect(() => {
    if (selectedRecipeKey && !compatibleForgeRecipes.some((recipe) => recipe.key === selectedRecipeKey)) {
      setSelectedRecipeKey('');
    }
  }, [compatibleForgeRecipes, selectedRecipeKey]);

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
      if (payload.needsConfirmation && breakdownSelection) {
        setConfirmBreakdown(breakdownSelection);
      } else {
        setState(normalizeState(payload));
        setBreakdownSelection(null);
        setScaleSelections({});
        setDragonSelections({});
        setSelectedRecipeKey('');
        setConfirmConversion(null);
        setConfirmBreakdown(null);
        onConverted();
      }
    } catch (actionError) {
      setError(actionError instanceof Error ? actionError.message : 'Conversion failed.');
    } finally {
      setSaving(false);
    }
  }

  function convertBreakdown(selection: BreakdownSelection, confirmDestroyExtras = false) {
    void runAction({
      action: 'item-to-scales',
      itemId: selection.entry.item.id,
      quantity: selection.quantity,
      confirmDestroyExtras
    });
  }

  function runConfirmedConversion() {
    if (confirmConversion === 'breakdown' && breakdownSelection) {
      convertBreakdown(breakdownSelection, breakdownSelection.entry.hasExtras);
      return;
    }

    if (confirmConversion === 'forge' && selectedForgeRecipe) {
      void runAction({
        action: 'scales-to-item',
        recipeKey: selectedForgeRecipe.key,
        selections: selectedScaleItems.map((entry) => ({ source: entry.source, itemId: entry.item.id, quantity: entry.quantity }))
      });
      return;
    }

    if (confirmConversion === 'dragon-scales' && selectedDragonTotal >= 25) {
      void runAction({
        action: 'dragon-scales',
        selections: selectedDragonItems.map((entry) => ({ source: entry.source, itemId: entry.item.id, quantity: entry.quantity }))
      });
    }
  }

  return (
    <Card>
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <p className="eyebrow">Blacksmith Specialty</p>
          <h3 className="mt-1 text-3xl font-black tracking-tight">Jursh Conversion Forge</h3>
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
          <div className="grid gap-3 xl:grid-cols-2">
            <SoftCard>
              <div className="mb-3 flex items-center gap-2 text-[var(--brass)]">
                <ArrowRightLeft size={18} />
                <p className="font-black">Break gear into scales</p>
              </div>
              <Button variant="secondary" onClick={() => setBreakdownPickerOpen(true)}>Choose Gear Input</Button>
              {breakdownSelection ? (
                <ConversionPreview
                  inputName={breakdownSelection.entry.item.displayName || breakdownSelection.entry.item.name}
                  inputType={breakdownSelection.entry.item.type}
                  inputRarity={breakdownSelection.entry.item.rarity}
                  inputQuantity={breakdownSelection.quantity}
                  outputName={breakdownSelection.entry.recipe.scaleItemName}
                  outputType="material"
                  outputRarity={breakdownSelection.entry.recipe.rarity}
                  outputQuantity={breakdownSelection.entry.recipe.scaleQuantity * breakdownSelection.quantity}
                  warning={breakdownSelection.entry.hasExtras ? 'This destroys modifiers, enhancements, runes, and enchantments.' : ''}
                />
              ) : (
                <p className="mt-3 rounded-xl border border-[var(--line)] bg-black/15 p-3 text-sm font-bold text-[var(--muted)]">Choose a compatible gear stack before converting.</p>
              )}
              <Button
                className="mt-3 w-full"
                variant="primary"
                disabled={saving || !breakdownSelection}
                onClick={() => setConfirmConversion('breakdown')}
              >
                Convert to Scales
              </Button>
            </SoftCard>

            <SoftCard>
              <div className="mb-3 flex items-center gap-2 text-[var(--brass)]">
                <Hammer size={18} />
                <p className="font-black">Forge gear from scales</p>
              </div>
              <Button variant="secondary" onClick={() => setScalePickerOpen(true)}>Choose Scale Inputs</Button>
              <p className="mt-3 text-sm font-bold text-[var(--muted)]">Selected {formatQuantity(selectedScaleTotal)} scale{selectedScaleTotal === 1 ? '' : 's'}{selectedScaleName ? ` of ${selectedScaleName}` : ''}</p>
              {selectedScaleItems.length > 0 && !selectedScaleName && (
                <div className="mt-3 rounded-2xl border border-[var(--red)]/40 bg-[var(--red)]/10 p-3 text-sm text-[var(--red)]">Choose one scale material at a time.</div>
              )}
              {selectedScaleName && compatibleForgeRecipes.length > 0 && (
                <div className="mt-3 grid gap-2 sm:grid-cols-2">
                  {compatibleForgeRecipes.map((recipe) => (
                    <button
                      key={recipe.key}
                      type="button"
                      onClick={() => setSelectedRecipeKey(recipe.key)}
                      className={`rounded-2xl border p-3 text-left transition ${selectedRecipeKey === recipe.key ? 'border-[var(--brass)] ring-2 ring-[var(--brass)]/35' : 'border-[var(--line)]'} ${rarityClass(recipe.rarity)}`}
                    >
                      <span className="flex items-start gap-3">
                        <span className="grid h-10 w-10 shrink-0 place-items-center rounded-xl bg-black/25 text-[var(--brass)]"><ItemIcon type={recipe.itemType} size={20} /></span>
                        <span>
                          <span className="block font-black">{recipe.itemName}</span>
                          <span className="mt-1 block text-xs font-black uppercase tracking-wider text-[var(--muted)]">Uses {formatQuantity(recipe.scaleQuantity)} {recipe.scaleItemName}</span>
                        </span>
                      </span>
                    </button>
                  ))}
                </div>
              )}
              {selectedScaleName && selectedScaleTotal > 0 && compatibleForgeRecipes.length === 0 && (
                <div className="mt-3 rounded-2xl border border-[var(--line)] bg-black/15 p-3 text-sm font-bold text-[var(--muted)]">No output can be made from that amount yet.</div>
              )}
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
                />
              )}
              <Button
                className="mt-3 w-full"
                variant="primary"
                disabled={saving || !selectedForgeRecipe}
                onClick={() => setConfirmConversion('forge')}
              >
                Forge Item
              </Button>
            </SoftCard>
          </div>

          <SoftCard>
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div>
                <p className="eyebrow">Dragon Scale Refining</p>
                <p className="mt-1 font-black">Every 25 chosen dragon scale fragments &rarr; 1 Dragonscale Scale</p>
                <p className={`mt-1 text-sm font-black ${selectedDragonTotal >= 25 ? 'text-[var(--teal)]' : 'text-[var(--muted)]'}`}>Selected {formatQuantity(selectedDragonTotal)} / 25+</p>
                {selectedDragonTotal >= 25 && (
                  <p className="mt-1 text-xs font-black uppercase tracking-wider text-[var(--muted)]">
                    Creates {formatQuantity(selectedDragonOutput)} scale{selectedDragonOutput === 1 ? '' : 's'}
                    {selectedDragonReturned > 0 ? `, returns ${formatQuantity(selectedDragonReturned)} fragment${selectedDragonReturned === 1 ? '' : 's'}` : ''}
                  </p>
                )}
              </div>
              <div className="flex flex-wrap gap-2">
                <Button variant="secondary" onClick={() => setDragonPickerOpen(true)}>Choose Fragments</Button>
                <Button variant="teal" disabled={saving || selectedDragonTotal < 25} onClick={() => setConfirmConversion('dragon-scales')}>
                  Forge Dragonscale Scale
                </Button>
              </div>
            </div>
          </SoftCard>
        </div>
      )}

      {breakdownPickerOpen && (
        <Modal title="Choose Gear Input" onClose={() => setBreakdownPickerOpen(false)}>
          <BreakdownInputPicker
            entries={state.convertibleItems}
            current={breakdownSelection}
            onChoose={(selection) => {
              setBreakdownSelection(selection);
              setBreakdownPickerOpen(false);
            }}
          />
        </Modal>
      )}

      {scalePickerOpen && (
        <Modal title="Choose Scale Inputs" onClose={() => setScalePickerOpen(false)}>
          <SourceQuantityPicker
            items={state.scaleItems}
            selections={scaleSelections}
            onChange={(next) => {
              setScaleSelections(next);
              setSelectedRecipeKey('');
            }}
            total={selectedScaleTotal}
            emptyText="Jursh has no material scale stacks to use."
          />
          <div className="mt-4 grid grid-cols-2 gap-2">
            <Button variant="secondary" onClick={() => { setScaleSelections({}); setSelectedRecipeKey(''); }}>Clear</Button>
            <Button variant="primary" disabled={selectedScaleTotal <= 0 || selectedScaleNames.length !== 1} onClick={() => setScalePickerOpen(false)}>Use These Inputs</Button>
          </div>
        </Modal>
      )}

      {dragonPickerOpen && (
        <Modal title="Choose Dragon Scale Fragments" onClose={() => setDragonPickerOpen(false)}>
          <SourceQuantityPicker
            items={state.dragonScaleItems}
            selections={dragonSelections}
            onChange={setDragonSelections}
            total={selectedDragonTotal}
            requiredTotal={25}
            emptyText="Jursh has no compatible dragon scale fragments."
          />
          <div className="mt-4 grid grid-cols-2 gap-2">
            <Button variant="secondary" onClick={() => setDragonSelections({})}>Clear</Button>
            <Button variant="primary" disabled={selectedDragonTotal < 25} onClick={() => setDragonPickerOpen(false)}>Use These Inputs</Button>
          </div>
        </Modal>
      )}

      {confirmConversion && (
        <Modal
          title={confirmConversion === 'breakdown' ? 'Confirm Breakdown' : confirmConversion === 'forge' ? 'Confirm Forge' : 'Confirm Dragon Scale Refining'}
          onClose={() => setConfirmConversion(null)}
        >
          <div className="grid gap-4">
            {confirmConversion === 'breakdown' && breakdownSelection && (
              <ConversionPreview
                inputName={breakdownSelection.entry.item.displayName || breakdownSelection.entry.item.name}
                inputType={breakdownSelection.entry.item.type}
                inputRarity={breakdownSelection.entry.item.rarity}
                inputQuantity={breakdownSelection.quantity}
                outputName={breakdownSelection.entry.recipe.scaleItemName}
                outputType="material"
                outputRarity={breakdownSelection.entry.recipe.rarity}
                outputQuantity={breakdownSelection.entry.recipe.scaleQuantity * breakdownSelection.quantity}
                warning={breakdownSelection.entry.hasExtras ? 'This will destroy modifiers, enhancements, runes, and enchantments on the selected gear.' : ''}
              />
            )}

            {confirmConversion === 'forge' && selectedForgeRecipe && (
              <ConversionPreview
                inputName={selectedForgeRecipe.scaleItemName}
                inputType="material"
                inputRarity={selectedForgeRecipe.rarity}
                inputQuantity={selectedForgeRecipe.scaleQuantity}
                outputName={selectedForgeRecipe.itemName}
                outputType={selectedForgeRecipe.itemType}
                outputRarity={selectedForgeRecipe.rarity}
                outputQuantity={1}
                warning={selectedScaleTotal > selectedForgeRecipe.scaleQuantity ? `${formatQuantity(selectedScaleTotal - selectedForgeRecipe.scaleQuantity)} unused scale${selectedScaleTotal - selectedForgeRecipe.scaleQuantity === 1 ? '' : 's'} stay in Jursh's inventory.` : ''}
              />
            )}

            {confirmConversion === 'dragon-scales' && (
              <div className="grid items-center gap-3 md:grid-cols-[1fr_auto_1fr]">
                <div className="grid gap-2">
                  <p className="eyebrow">Using</p>
                  {selectedDragonItems.map((entry) => (
                    <PreviewItem
                      key={sourceItemKey(entry)}
                      name={entry.item.displayName || entry.item.name}
                      type={entry.item.type}
                      rarity={entry.item.rarity}
                      quantity={entry.quantity}
                    />
                  ))}
                </div>
                <ConversionArrow />
                <div className="grid gap-2">
                  <p className="eyebrow">Creating</p>
                  <PreviewItem
                    name="Dragonscale Scale"
                    type="material"
                    rarity="Legendary"
                    quantity={selectedDragonOutput}
                    featured
                  />
                  {selectedDragonReturned > 0 && (
                    <div className="rounded-2xl border border-[var(--line)] bg-black/15 p-3 text-sm font-bold text-[var(--muted)]">
                      {formatQuantity(selectedDragonConsumed)} fragments are consumed. {formatQuantity(selectedDragonReturned)} extra fragment{selectedDragonReturned === 1 ? '' : 's'} stay in Jursh&apos;s inventory.
                    </div>
                  )}
                </div>
              </div>
            )}

            <div className="grid grid-cols-2 gap-2">
              <Button variant="secondary" disabled={saving} onClick={() => setConfirmConversion(null)}>Back</Button>
              <Button
                variant="primary"
                disabled={saving || (confirmConversion === 'breakdown' && !breakdownSelection) || (confirmConversion === 'forge' && !selectedForgeRecipe) || (confirmConversion === 'dragon-scales' && selectedDragonTotal < 25)}
                onClick={runConfirmedConversion}
              >
                Confirm Craft
              </Button>
            </div>
          </div>
        </Modal>
      )}

      {confirmBreakdown && (
        <Modal title="Destroy Item Extras?" onClose={() => setConfirmBreakdown(null)}>
          <div className="grid gap-4">
            <div className="rounded-2xl border border-[var(--red)]/40 bg-[var(--red)]/10 p-4">
              <div className="flex items-start gap-3">
                <ShieldAlert className="mt-1 shrink-0 text-[var(--red)]" size={22} />
                <div>
                  <p className="font-black">{confirmBreakdown.entry.item.displayName || confirmBreakdown.entry.item.name}</p>
                  <p className="mt-1 text-sm leading-6 text-[var(--muted)]">
                    This conversion destroys modifiers, enhancements, runes, and enchantments on the selected item. The output is only {formatQuantity(confirmBreakdown.entry.recipe.scaleQuantity * confirmBreakdown.quantity)} {confirmBreakdown.entry.recipe.scaleItemName}.
                  </p>
                </div>
              </div>
            </div>
            <div className="grid grid-cols-2 gap-2">
              <Button variant="secondary" disabled={saving} onClick={() => setConfirmBreakdown(null)}>Cancel</Button>
              <Button variant="danger" disabled={saving} onClick={() => void runAction({
                action: 'item-to-scales',
                itemId: confirmBreakdown.entry.item.id,
                quantity: confirmBreakdown.quantity,
                confirmDestroyExtras: true
              })}>Proceed</Button>
            </div>
          </div>
        </Modal>
      )}
    </Card>
  );
}

function BreakdownInputPicker({ entries, current, onChoose }: {
  entries: ConvertibleEntry[];
  current: BreakdownSelection | null;
  onChoose: (selection: BreakdownSelection) => void;
}) {
  const [quantities, setQuantities] = useState<Record<string, number>>(() => current ? { [current.entry.item.id]: current.quantity } : {});
  return (
    <div className="grid gap-3">
      {entries.length ? (
        <div className="thin-scrollbar grid max-h-[60vh] gap-2 overflow-y-auto pr-1">
          {entries.map((entry) => {
            const quantity = Math.min(entry.item.quantity, Math.max(1, quantities[entry.item.id] ?? 1));
            return (
              <div key={entry.item.id} className={`grid gap-3 rounded-2xl border p-3 sm:grid-cols-[1fr_7rem_auto] ${rarityClass(entry.item.rarity)}`}>
                <div className="flex min-w-0 items-start gap-3">
                  <span className="grid h-10 w-10 shrink-0 place-items-center rounded-xl bg-black/25 text-[var(--brass)]"><ItemIcon type={entry.item.type} size={20} /></span>
                  <div className="min-w-0">
                    <p className="break-words font-black leading-5">{entry.item.displayName || entry.item.name}</p>
                    <p className="mt-1 text-xs font-bold text-[var(--muted)]">Creates {formatQuantity(entry.recipe.scaleQuantity * quantity)} {entry.recipe.scaleItemName}{entry.hasExtras ? ' - destroys extras' : ''}</p>
                  </div>
                </div>
                <NumberInput min={1} max={entry.item.quantity} step={1} value={quantity} onValueChange={(value) => setQuantities({ ...quantities, [entry.item.id]: Math.min(entry.item.quantity, Math.max(1, Math.floor(value))) })} />
                <Button variant="primary" onClick={() => onChoose({ entry, quantity })}>Use</Button>
              </div>
            );
          })}
        </div>
      ) : (
        <div className="rounded-2xl border border-[var(--line)] bg-black/15 p-3 text-sm font-bold text-[var(--muted)]">
          Jursh has no compatible gear to break down.
        </div>
      )}
    </div>
  );
}

function SourceQuantityPicker({ items, selections, onChange, total, requiredTotal, emptyText }: {
  items: SourceEntry[];
  selections: Record<string, number>;
  onChange: (next: Record<string, number>) => void;
  total: number;
  requiredTotal?: number;
  emptyText: string;
}) {
  return (
    <div className="grid gap-3">
      <div className="rounded-2xl border border-[var(--line)] bg-black/15 p-3">
        <p className="eyebrow">Selected</p>
        <p className={`mt-1 text-2xl font-black ${requiredTotal && total >= requiredTotal ? 'text-[var(--teal)]' : 'text-[var(--brass)]'}`}>
          {formatQuantity(total)}{requiredTotal ? ` / ${requiredTotal}+` : ''}
        </p>
        {requiredTotal === 25 && total >= 25 && (
          <p className="mt-1 text-xs font-black uppercase tracking-wider text-[var(--muted)]">
            Creates {formatQuantity(dragonScaleOutputQuantity(total))} scale{dragonScaleOutputQuantity(total) === 1 ? '' : 's'}
            {dragonScaleReturnedQuantity(total) > 0 ? `, returns ${formatQuantity(dragonScaleReturnedQuantity(total))}` : ''}
          </p>
        )}
      </div>
      {items.length ? (
        <div className="thin-scrollbar grid max-h-[60vh] gap-2 overflow-y-auto pr-1">
          {items.map((entry) => {
            const key = sourceItemKey(entry);
            const selected = Math.min(entry.item.quantity, Math.max(0, selections[key] ?? 0));
            const step = entry.item.name.toLowerCase().includes('scale') && !entry.item.name.toLowerCase().includes('dragon') ? 0.5 : 1;
            return (
              <div key={key} className={`grid gap-3 rounded-2xl border p-3 sm:grid-cols-[1fr_8rem] ${rarityClass(entry.item.rarity)}`}>
                <div className="flex min-w-0 items-start gap-3">
                  <span className="grid h-10 w-10 shrink-0 place-items-center rounded-xl bg-black/25 text-[var(--brass)]"><ItemIcon type={entry.item.type} size={20} /></span>
                  <div className="min-w-0">
                    <p className="break-words font-black leading-5">{entry.item.displayName || entry.item.name}</p>
                    <p className="mt-1 text-xs font-bold text-[var(--muted)]">Available {formatQuantity(entry.item.quantity)}</p>
                  </div>
                </div>
                <NumberInput min={0} max={entry.item.quantity} step={step} value={selected} onValueChange={(quantity) => onChange({ ...selections, [key]: Math.min(entry.item.quantity, Math.max(0, quantity)) })} />
              </div>
            );
          })}
        </div>
      ) : (
        <div className="rounded-2xl border border-[var(--line)] bg-black/15 p-3 text-sm font-bold text-[var(--muted)]">
          {emptyText}
        </div>
      )}
    </div>
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

function ConversionArrow() {
  return (
    <div className="relative grid h-16 w-full min-w-24 place-items-center text-[var(--brass)] md:h-24 md:w-24">
      <span className="absolute h-1 w-full rounded-full bg-gradient-to-r from-transparent via-[var(--brass)] to-[var(--brass)] shadow-[0_0_18px_rgba(209,168,91,.45)]" />
      <span className="absolute right-1 h-5 w-5 rotate-45 border-r-4 border-t-4 border-[var(--brass)] shadow-[0_0_18px_rgba(209,168,91,.45)]" />
      <Sparkles size={20} className="relative rounded-full bg-[#1a100c] p-0.5 text-[var(--brass)]" />
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
