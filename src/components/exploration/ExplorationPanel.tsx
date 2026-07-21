'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { Compass, Dice6, FileUp, Gift, Loader2, RefreshCw } from 'lucide-react';
import { ItemIcon } from '@/components/inventory/ItemIcon';
import { Button } from '@/components/ui/Button';
import { Card } from '@/components/ui/Card';
import { SelectField } from '@/components/ui/Field';
import { NumberInput } from '@/components/ui/NumberInput';
import { DEFAULT_LOOT_GENERATOR_SETTINGS, getLootMultiplier, getLootRollCount, normalizeExplorationPayload, normalizeLootRollPayload, type ExplorationPayload, type LootRollPayload } from '@/features/exploration/data';
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

export function ExplorationPanel() {
  const [payload, setPayload] = useState<ExplorationPayload>(EMPTY);
  const [biome, setBiome] = useState(DEFAULT_LOOT_GENERATOR_SETTINGS.biomes[0]);
  const [difficulty, setDifficulty] = useState(DEFAULT_LOOT_GENERATOR_SETTINGS.difficulties[0]);
  const [poolSize, setPoolSize] = useState('Medium Cave');
  const [roomType, setRoomType] = useState('Normal');
  const [rollPayload, setRollPayload] = useState<LootRollPayload | null>(null);
  const [awardDrafts, setAwardDrafts] = useState<Record<string, AwardDraft>>({});
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const multiplier = useMemo(() => getLootMultiplier(payload.settings, poolSize, roomType), [payload.settings, poolSize, roomType]);
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
        body: JSON.stringify({ biome, difficulty, poolSize, roomType })
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
      </Card>

      <Card>
        <div className="rule-title mb-3"><h3 className="text-sm font-black uppercase tracking-wider">Loot Generator</h3></div>
        <div className="grid gap-2 sm:grid-cols-2 xl:grid-cols-[1fr_7rem_1fr_1fr_auto]">
          <SelectField value={biome} onChange={(event) => setBiome(event.target.value)}>
            {payload.settings.biomes.map((entry) => <option key={entry} value={entry}>{entry}</option>)}
          </SelectField>
          <SelectField value={difficulty} onChange={(event) => setDifficulty(Number(event.target.value))}>
            {payload.settings.difficulties.map((entry) => <option key={entry} value={entry}>{entry}</option>)}
          </SelectField>
          <SelectField value={poolSize} onChange={(event) => setPoolSize(event.target.value)}>
            {payload.settings.poolSizes.map((entry) => <option key={entry} value={entry}>{entry}</option>)}
          </SelectField>
          <SelectField value={roomType} onChange={(event) => setRoomType(event.target.value)}>
            {payload.settings.roomTypes.map((entry) => <option key={entry} value={entry}>{entry}</option>)}
          </SelectField>
          <Button variant="primary" disabled={saving || !payload.items.length} onClick={generateLoot}><Dice6 className="mr-2 inline" size={15} /> Generate {rollCount}</Button>
        </div>
        <div className="mt-3 grid gap-2 rounded-2xl border border-[var(--line)] bg-black/10 p-3 text-xs font-bold text-[var(--muted)] sm:grid-cols-4">
          <span>Rare+ multiplier: <b className="text-[var(--paper)]">{multiplier.total.toFixed(2)}×</b></span>
          <span>Pool: <b className="text-[var(--paper)]">{multiplier.pool.toFixed(2)}×</b></span>
          <span>Room: <b className="text-[var(--paper)]">{multiplier.room.toFixed(2)}×</b></span>
          <span>Rolls: <b className="text-[var(--paper)]">{rollCount}</b></span>
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
                      <span className="mt-1 block text-xs uppercase tracking-wide text-[var(--muted)]">{drop.rarity} · {drop.type} · {drop.remaining}/{drop.quantity} left</span>
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
