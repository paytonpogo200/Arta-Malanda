'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { ChevronDown, Compass, Dice6, FileUp, Gift, Loader2, RefreshCw } from 'lucide-react';
import { ItemIcon } from '@/components/inventory/ItemIcon';
import { Button } from '@/components/ui/Button';
import { Card } from '@/components/ui/Card';
import { SelectField } from '@/components/ui/Field';
import { NumberInput } from '@/components/ui/NumberInput';
import {
  DEFAULT_LOOT_GENERATOR_SETTINGS,
  MULTIPLIER_RARITIES,
  getLootRaritySummary,
  getLootRollCount,
  normalizeExplorationPayload,
  normalizeLootRollPayload,
  type ExplorationPayload,
  type LootRarityMath,
  type LootRollPayload
} from '@/features/exploration/data';
import { rarityClass } from '@/lib/utils/rarity';

const EMPTY: ExplorationPayload = {
  characters: [],
  pools: [],
  items: [],
  settings: DEFAULT_LOOT_GENERATOR_SETTINGS
};

type AwardDraft = {
  characterId: string;
  quantity: number;
};

type ChoiceValue = string | number;

function formatMultiplier(value: number) {
  return `${value.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}x`;
}

function formatChance(value: number) {
  if (value > 0 && value < 0.01) return '<0.01%';
  return `${value.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}%`;
}

function findRarity(rarities: LootRarityMath[], rarity: LootRarityMath['rarity']) {
  return rarities.find((entry) => entry.rarity === rarity) ?? {
    rarity,
    multiplier: 1,
    itemCount: 0,
    weight: 0,
    chance: 0
  };
}

function ChoiceDisclosure({
  label,
  value,
  options,
  onChange,
  columns = 'sm:grid-cols-2'
}: {
  label: string;
  value: ChoiceValue;
  options: ChoiceValue[];
  onChange: (value: ChoiceValue) => void;
  columns?: string;
}) {
  return (
    <details className="shop-section-disclosure">
      <summary>
        <span className="min-w-0">
          <span className="eyebrow">{label}</span>
          <span className="mt-1 block truncate text-xl font-black leading-tight">{String(value)}</span>
          <span className="mt-1 block text-xs font-bold text-[var(--muted)]">{options.length} options</span>
        </span>
        <ChevronDown className="shop-section-chevron" size={18} />
      </summary>
      <div className={`shop-section-body grid gap-2 ${columns}`}>
        {options.map((option) => {
          const selected = String(option) === String(value);
          return (
            <button
              key={String(option)}
              type="button"
              onClick={() => onChange(option)}
              className={`rounded-xl border p-3 text-left text-sm font-black transition hover:border-[var(--brass)] ${selected ? 'border-[var(--brass)] bg-[#d1a85b1c] text-[var(--paper)]' : 'border-[var(--line)] bg-black/15 text-[var(--muted)]'}`}
            >
              {String(option)}
            </button>
          );
        })}
      </div>
    </details>
  );
}

export function LootGeneratorPanel() {
  const [payload, setPayload] = useState<ExplorationPayload>(EMPTY);
  const [biome, setBiome] = useState(DEFAULT_LOOT_GENERATOR_SETTINGS.biomes[0]);
  const [difficulty, setDifficulty] = useState(DEFAULT_LOOT_GENERATOR_SETTINGS.difficulties[0]);
  const [poolSize, setPoolSize] = useState('Medium Cave');
  const [roomType, setRoomType] = useState('Normal');
  const [luckPotion, setLuckPotion] = useState('None');
  const [rollPayload, setRollPayload] = useState<LootRollPayload | null>(null);
  const [awardDrafts, setAwardDrafts] = useState<Record<string, AwardDraft>>({});
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const raritySummary = useMemo(
    () => getLootRaritySummary(payload.items, payload.settings, biome, difficulty, poolSize, roomType, luckPotion),
    [payload.items, payload.settings, biome, difficulty, poolSize, roomType, luckPotion]
  );
  const rollCount = useMemo(() => getLootRollCount(payload.settings, poolSize, roomType), [payload.settings, poolSize, roomType]);
  const defaultCharacterId = payload.characters[0]?.id ?? '';

  const loadExploration = useCallback(async () => {
    setError('');
    try {
      const response = await fetch('/api/exploration', { cache: 'no-store' });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(body.error ?? 'Exploration tools could not be loaded.');
      const normalized = normalizeExplorationPayload(body);
      setPayload(normalized);
      setBiome((current) => normalized.settings.biomes.includes(current) ? current : normalized.settings.biomes[0] || 'Any');
      setDifficulty((current) => normalized.settings.difficulties.includes(current) ? current : normalized.settings.difficulties[0] || 1);
      setPoolSize((current) => normalized.settings.poolSizes.includes(current) ? current : normalized.settings.poolSizes[0] || 'Medium Cave');
      setRoomType((current) => normalized.settings.roomTypes.includes(current) ? current : normalized.settings.roomTypes[0] || 'Normal');
      setLuckPotion((current) => normalized.settings.luckPotionOptions.includes(current) ? current : 'None');
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : 'Exploration tools could not be loaded.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void loadExploration();
  }, [loadExploration]);

  async function importWorkbook(file: File | null) {
    if (!file) return;
    setSaving(true);
    setError('');
    try {
      const form = new FormData();
      form.append('file', file);
      const response = await fetch('/api/exploration/import', { method: 'POST', body: form });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(body.error ?? 'Loot workbook import failed.');
      const normalized = normalizeExplorationPayload(body);
      setPayload(normalized);
      setBiome(normalized.settings.biomes[0] || 'Any');
      setDifficulty(normalized.settings.difficulties[0] || 1);
      setPoolSize(normalized.settings.poolSizes.includes('Medium Cave') ? 'Medium Cave' : normalized.settings.poolSizes[0] || 'Medium Cave');
      setRoomType(normalized.settings.roomTypes[0] || 'Normal');
      setLuckPotion(normalized.settings.luckPotionOptions.includes('None') ? 'None' : normalized.settings.luckPotionOptions[0] || 'None');
      setRollPayload(null);
      setAwardDrafts({});
    } catch (importError) {
      setError(importError instanceof Error ? importError.message : 'Loot workbook import failed.');
    } finally {
      setSaving(false);
    }
  }

  async function generateLoot() {
    setSaving(true);
    setError('');
    try {
      const response = await fetch('/api/exploration/generate', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ biome, difficulty, poolSize, roomType, luckPotion })
      });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(body.error ?? 'Loot could not be generated.');
      const normalized = normalizeLootRollPayload(body);
      setRollPayload(normalized);
      setAwardDrafts(Object.fromEntries(normalized.drops.map((drop) => [drop.id, { characterId: defaultCharacterId, quantity: Math.max(1, Math.min(drop.remaining, drop.quantity)) }])));
    } catch (generateError) {
      setError(generateError instanceof Error ? generateError.message : 'Loot could not be generated.');
    } finally {
      setSaving(false);
    }
  }

  async function giveDrop(dropId: string) {
    const drop = rollPayload?.drops.find((entry) => entry.id === dropId);
    const draft = awardDrafts[dropId];
    if (!drop || !draft?.characterId || drop.remaining <= 0) return;
    const quantity = Math.max(1, Math.min(draft.quantity, drop.remaining));
    setSaving(true);
    setError('');
    try {
      const response = await fetch('/api/exploration/award', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ itemId: drop.itemId, characterId: draft.characterId, quantity })
      });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(body.error ?? 'Loot could not be given.');
      setRollPayload((current) => current ? {
        ...current,
        drops: current.drops.map((entry) => entry.id === dropId ? { ...entry, remaining: Math.max(0, entry.remaining - quantity) } : entry)
      } : current);
      setAwardDrafts((current) => ({
        ...current,
        [dropId]: { ...draft, quantity: Math.max(1, Math.min(drop.remaining - quantity, quantity)) }
      }));
    } catch (awardError) {
      setError(awardError instanceof Error ? awardError.message : 'Loot could not be given.');
    } finally {
      setSaving(false);
    }
  }

  if (loading) {
    return <Card><div className="grid h-32 place-items-center text-[var(--muted)]"><Loader2 className="animate-spin" /></div></Card>;
  }

  return (
    <div className="space-y-4">
      <Card>
        <div className="flex items-center justify-between gap-3">
          <div>
            <p className="eyebrow">DM Tools</p>
            <h2 className="mt-1 flex items-center gap-2 text-2xl font-black"><Compass className="text-[var(--brass)]" /> Exploration</h2>
          </div>
          <Button variant="secondary" className="p-3" onClick={loadExploration} aria-label="Refresh exploration"><RefreshCw size={16} /></Button>
        </div>
        {error && <div className="mt-3 rounded-2xl border border-[var(--red)]/40 bg-[var(--red)]/10 p-3 text-sm text-[var(--red)]">{error}</div>}
      </Card>

      <Card>
        <div className="rule-title mb-3"><h3 className="text-sm font-black uppercase tracking-wider">Loot Workbook</h3></div>
        <label className="grid cursor-pointer gap-2 rounded-2xl border border-dashed border-[var(--line)] bg-black/15 p-4 text-center transition hover:border-[var(--brass)]">
          <FileUp className="mx-auto text-[var(--brass)]" size={22} />
          <span className="text-sm font-black">Upload Loot Drops workbook</span>
          <input
            type="file"
            accept=".xlsx,.xlsm,.xls"
            className="sr-only"
            disabled={saving}
            onChange={(event) => void importWorkbook(event.target.files?.[0] ?? null)}
          />
        </label>
        <div className="mt-3 grid gap-2 rounded-2xl border border-[var(--line)] bg-black/10 p-3 text-xs font-bold text-[var(--muted)] sm:grid-cols-3">
          <span>Items: <b className="text-[var(--paper)]">{payload.items.length}</b></span>
          <span>Biomes: <b className="text-[var(--paper)]">{payload.settings.biomes.length}</b></span>
          <span>Pool sizes: <b className="text-[var(--paper)]">{payload.settings.poolSizes.length}</b></span>
        </div>
        <details className="mt-3 rounded-2xl border border-[var(--line)] bg-black/10 p-3 text-xs text-[var(--muted)]">
          <summary className="cursor-pointer font-black uppercase tracking-wide text-[var(--brass)]">Import diagnostics</summary>
          <div className="mt-3 grid gap-3">
            <div className="grid gap-2 sm:grid-cols-2 xl:grid-cols-4">
              <span>Room types: <b className="text-[var(--paper)]">{payload.settings.roomTypes.join(', ') || 'None'}</b></span>
              <span>Difficulties: <b className="text-[var(--paper)]">{payload.settings.difficulties.join(', ') || 'None'}</b></span>
              <span>Luck: <b className="text-[var(--paper)]">{payload.settings.luckPotionOptions.join(', ') || 'None'}</b></span>
              <span>Rare boost: <b className="text-[var(--paper)]">{payload.settings.rareBoostRarities.join(', ') || 'None'}</b></span>
            </div>
            {!!Object.keys(payload.settings.sourceFormulas).length && (
              <div className="grid gap-2">
                {Object.entries(payload.settings.sourceFormulas).map(([key, formula]) => (
                  <div key={key} className="rounded-xl border border-[var(--line)] bg-black/15 p-2">
                    <span className="block text-[10px] font-black uppercase tracking-wide text-[var(--brass)]">{key}</span>
                    <code className="mt-1 block max-h-20 overflow-auto whitespace-pre-wrap break-words text-[0.68rem] text-[var(--paper)]">{formula || 'Not found'}</code>
                  </div>
                ))}
              </div>
            )}
          </div>
        </details>
      </Card>

      <Card>
        <div className="rule-title mb-3"><h3 className="text-sm font-black uppercase tracking-wider">Loot Generator</h3></div>
        <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-5">
          <ChoiceDisclosure label="Biome" value={biome} options={payload.settings.biomes} onChange={(value) => setBiome(String(value))} />
          <ChoiceDisclosure label="Difficulty" value={difficulty} options={payload.settings.difficulties} onChange={(value) => setDifficulty(Number(value))} columns="grid-cols-3" />
          <ChoiceDisclosure label="Pool Size" value={poolSize} options={payload.settings.poolSizes} onChange={(value) => setPoolSize(String(value))} />
          <ChoiceDisclosure label="Room Type" value={roomType} options={payload.settings.roomTypes} onChange={(value) => setRoomType(String(value))} />
          <ChoiceDisclosure label="Luck Potion" value={luckPotion} options={payload.settings.luckPotionOptions} onChange={(value) => setLuckPotion(String(value))} />
        </div>
        <div className="mt-3 flex justify-end">
          <Button variant="primary" disabled={saving || !payload.items.length} onClick={generateLoot}><Dice6 className="mr-2 inline" size={15} /> Generate {rollCount}</Button>
        </div>
        <div className="mt-3 space-y-3 rounded-2xl border border-[var(--line)] bg-black/10 p-3">
          <div>
            <p className="mb-2 text-[0.65rem] font-black uppercase tracking-[0.18em] text-[var(--muted)]">Rarity multipliers</p>
            <div className="grid gap-2 sm:grid-cols-4">
              {MULTIPLIER_RARITIES.map((rarity) => {
                const entry = findRarity(raritySummary.rarities, rarity);
                return (
                  <div key={rarity} className={`rounded-2xl border p-3 ${rarityClass(rarity)}`}>
                    <span className="block text-[0.65rem] font-black uppercase tracking-wider text-[var(--muted)]">{rarity}</span>
                    <b className="mt-1 block text-lg text-[var(--paper)]">{formatMultiplier(entry.multiplier)}</b>
                  </div>
                );
              })}
            </div>
          </div>
          <div>
            <p className="mb-2 text-[0.65rem] font-black uppercase tracking-[0.18em] text-[var(--muted)]">Odds per roll</p>
            <div className="grid gap-2 sm:grid-cols-3 xl:grid-cols-6">
              {raritySummary.rarities.map((entry) => (
                <div key={entry.rarity} className={`rounded-2xl border p-3 ${rarityClass(entry.rarity)}`}>
                  <span className="block text-[0.65rem] font-black uppercase tracking-wider text-[var(--muted)]">{entry.rarity}</span>
                  <b className="mt-1 block text-lg text-[var(--paper)]">{formatChance(entry.chance)}</b>
                  <span className="mt-1 block text-[0.65rem] font-bold text-[var(--muted)]">{entry.itemCount} item{entry.itemCount === 1 ? '' : 's'}</span>
                </div>
              ))}
            </div>
          </div>
          <div className="grid gap-2 rounded-xl border border-[var(--line)] bg-black/10 p-2 text-xs font-bold text-[var(--muted)] sm:grid-cols-3">
            <span>Rolls: <b className="text-[var(--paper)]">{rollCount}</b></span>
            <span>Eligible items: <b className="text-[var(--paper)]">{raritySummary.eligibleCount}</b></span>
            <span>Total weight: <b className="text-[var(--paper)]">{raritySummary.totalWeight.toFixed(2)}</b></span>
          </div>
        </div>
      </Card>

      {rollPayload && (
        <Card>
          <div className="rule-title mb-3"><h3 className="text-sm font-black uppercase tracking-wider">Generated Loot</h3></div>
          <div className="mb-3 grid gap-2 rounded-2xl border border-[var(--line)] bg-black/10 p-3 text-xs font-bold text-[var(--muted)] sm:grid-cols-3">
            <span>Eligible items: <b className="text-[var(--paper)]">{rollPayload.eligibleCount}</b></span>
            <span>Total weight: <b className="text-[var(--paper)]">{rollPayload.totalWeight.toFixed(2)}</b></span>
            <span>Rolled: <b className="text-[var(--paper)]">{rollPayload.rolls}</b></span>
          </div>
          <div className="grid gap-3">
            {rollPayload.drops.map((drop) => {
              const draft = awardDrafts[drop.id] ?? { characterId: defaultCharacterId, quantity: Math.max(1, drop.remaining) };
              return (
                <div key={drop.id} className={`rounded-2xl border p-3 ${rarityClass(drop.rarity)}`}>
                  <div className="flex flex-wrap items-start gap-3">
                    <span className="rounded-xl border border-[var(--line)] bg-black/20 p-2 text-[var(--brass)]"><ItemIcon type={drop.type} size={18} /></span>
                    <span className="min-w-0 flex-1">
                      <span className="block break-words font-black">#{drop.rollNumber} {drop.name}</span>
                      <span className="mt-1 block text-xs uppercase tracking-wide text-[var(--muted)]">{drop.rarity}; {drop.type}; {drop.remaining}/{drop.quantity} left</span>
                    </span>
                  </div>
                  {drop.remaining > 0 ? (
                    <div className="mt-3 grid gap-2 sm:grid-cols-[1fr_8rem_auto]">
                      <SelectField value={draft.characterId} onChange={(event) => setAwardDrafts((current) => ({ ...current, [drop.id]: { ...draft, characterId: event.target.value } }))}>
                        {payload.characters.map((character) => <option key={character.id} value={character.id}>{character.name}</option>)}
                      </SelectField>
                      <NumberInput min={1} max={drop.remaining} value={Math.max(1, Math.min(draft.quantity, drop.remaining))} onValueChange={(quantity) => setAwardDrafts((current) => ({ ...current, [drop.id]: { ...draft, quantity } }))} />
                      <Button variant="teal" disabled={!draft.characterId || saving} onClick={() => void giveDrop(drop.id)}><Gift className="mr-2 inline" size={15} /> Give</Button>
                    </div>
                  ) : (
                    <p className="mt-3 rounded-xl border border-[var(--line)] bg-black/20 p-2 text-xs font-black uppercase tracking-wide text-[var(--teal)]">Fully distributed</p>
                  )}
                </div>
              );
            })}
          </div>
        </Card>
      )}
    </div>
  );
}
