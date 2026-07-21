'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { Compass, Dice6, FileUp, Gift, Loader2, Mountain, RefreshCw } from 'lucide-react';
import { ItemIcon } from '@/components/inventory/ItemIcon';
import { Button } from '@/components/ui/Button';
import { Card } from '@/components/ui/Card';
import { SelectField } from '@/components/ui/Field';
import { NumberInput } from '@/components/ui/NumberInput';
import { estimateLootRollCount, normalizeExplorationPayload, normalizeLootRollPayload, type ExplorationPayload } from '@/features/exploration/data';
import { rarityClass } from '@/lib/utils/rarity';
import type { LootDrop } from '@/lib/types';

const EMPTY: ExplorationPayload = {
  characters: [],
  pools: [],
  items: [],
  settings: {
    biomes: ['Any'],
    difficulties: [1, 2, 3, 4, 5],
    poolSizes: ['Medium Cave'],
    roomTypes: ['Normal'],
    baseRollsByPoolSize: { 'Medium Cave': 15 },
    rareMultiplierKeywords: { capital: 5, base: 2, camp: 1.33 },
    rareBoostRarities: ['Rare', 'Epic', 'Legendary', 'Mythical'],
    towerBoostRarities: ['Epic', 'Legendary', 'Mythical'],
    towerBoostMultiplier: 2,
    specialRoomBoostRarities: ['Epic', 'Legendary', 'Mythical'],
    specialRoomTypes: ['Secret Room', 'Tower Boss Room'],
    specialRoomMultiplier: 2,
    sourceFormulas: {}
  }
};

const ADVENTURE_NOTES = [
  { title: 'Bases', text: 'Organized enemy holdings. Expect patrols, locked rooms, storage areas, and a leader space. Good for structured missions.' },
  { title: 'Multi caves', text: 'Many separate paths are available early. Most tunnels lead toward their own encounter or boss room.' },
  { title: 'Forking caves', text: 'Several branches split from main tunnels. Some resemble trees, some become maze-like, and branches may start halfway down a path.' },
  { title: 'Snaking caves', text: 'A longer route where progress usually pushes deeper through one tunnel and boss room before the next path opens.' }
];

export function ExplorationPanel() {
  const [payload, setPayload] = useState<ExplorationPayload>(EMPTY);
  const [biome, setBiome] = useState('Any');
  const [difficulty, setDifficulty] = useState(1);
  const [poolSize, setPoolSize] = useState('Medium Cave');
  const [roomType, setRoomType] = useState('Normal');
  const [drops, setDrops] = useState<LootDrop[]>([]);
  const [selectedDropId, setSelectedDropId] = useState('');
  const [characterId, setCharacterId] = useState('');
  const [awardQuantity, setAwardQuantity] = useState(1);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const selectedDrop = useMemo(() => drops.find((drop) => drop.id === selectedDropId) ?? drops[0] ?? null, [drops, selectedDropId]);
  const rollCount = useMemo(() => estimateLootRollCount(payload.settings, poolSize, roomType), [payload.settings, poolSize, roomType]);

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
      setCharacterId((current) => current || normalized.characters[0]?.id || '');
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : 'Exploration tools could not be loaded.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void loadExploration();
  }, [loadExploration]);

  async function rollLoot() {
    setSaving(true);
    setError('');
    try {
      const response = await fetch('/api/exploration/roll', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ biome, difficulty, poolSize, roomType })
      });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(body.error ?? 'Loot could not be rolled.');
      const normalized = normalizeLootRollPayload(body);
      setDrops(normalized.drops);
      setSelectedDropId(normalized.drops[0]?.id || '');
      setAwardQuantity(normalized.drops[0]?.quantity || 1);
    } catch (rollError) {
      setError(rollError instanceof Error ? rollError.message : 'Loot could not be rolled.');
    } finally {
      setSaving(false);
    }
  }

  async function awardLoot() {
    if (!selectedDrop || !characterId) return;
    setSaving(true);
    setError('');
    try {
      const response = await fetch('/api/exploration/award', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ itemId: selectedDrop.itemId, characterId, quantity: awardQuantity })
      });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(body.error ?? 'Loot could not be awarded.');
    } catch (awardError) {
      setError(awardError instanceof Error ? awardError.message : 'Loot could not be awarded.');
    } finally {
      setSaving(false);
    }
  }

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
      setDrops([]);
      setSelectedDropId('');
    } catch (importError) {
      setError(importError instanceof Error ? importError.message : 'Loot workbook import failed.');
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

      <div className="grid gap-4 xl:grid-cols-[1fr_22rem]">
        <div className="space-y-4">
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
              <Button variant="primary" disabled={saving} onClick={rollLoot}><Dice6 className="mr-2 inline" size={15} /> Roll {rollCount}</Button>
            </div>

            {drops.length > 0 && (
              <div className="mt-4 grid gap-2 sm:grid-cols-2">
                {drops.map((drop) => (
                  <button key={drop.id} type="button" onClick={() => { setSelectedDropId(drop.id); setAwardQuantity(drop.quantity); }} className={`rounded-2xl border p-3 text-left ${rarityClass(drop.rarity)} ${selectedDropId === drop.id ? 'ring-2 ring-[var(--brass)]' : ''}`}>
                    <span className="flex items-center gap-2">
                      <span className="text-[var(--brass)]"><ItemIcon type={drop.type} /></span>
                      <span className="font-black">{drop.name}</span>
                      <span className="ml-auto rounded-full bg-black/35 px-2 py-1 text-xs font-black">x{drop.quantity}</span>
                    </span>
                    <span className="mt-1 block text-xs uppercase tracking-wide text-[var(--muted)]">{drop.rarity} · {drop.type}</span>
                  </button>
                ))}
              </div>
            )}
          </Card>

          <Card>
            <div className="rule-title mb-3"><h3 className="text-sm font-black uppercase tracking-wider">Award Selected Loot</h3></div>
            <div className="grid gap-2 sm:grid-cols-[1fr_8rem_1fr_auto]">
              <SelectField value={selectedDropId} onChange={(event) => setSelectedDropId(event.target.value)}>
                {drops.map((drop) => <option key={drop.id} value={drop.id}>{drop.name} x{drop.quantity}</option>)}
              </SelectField>
              <NumberInput min={1} max={selectedDrop?.quantity ?? 999} value={awardQuantity} onValueChange={setAwardQuantity} />
              <SelectField value={characterId} onChange={(event) => setCharacterId(event.target.value)}>
                {payload.characters.map((character) => <option key={character.id} value={character.id}>{character.name}</option>)}
              </SelectField>
              <Button variant="teal" disabled={!selectedDrop || !characterId || saving} onClick={awardLoot}><Gift className="mr-2 inline" size={15} /> Give</Button>
            </div>
          </Card>

          <Card>
            <div className="rule-title mb-3"><h3 className="text-sm font-black uppercase tracking-wider">Loot Import</h3></div>
            <label className="mb-3 grid cursor-pointer gap-2 rounded-2xl border border-dashed border-[var(--line)] bg-black/15 p-4 text-center transition hover:border-[var(--brass)]">
              <FileUp className="mx-auto text-[var(--brass)]" size={22} />
              <span className="text-sm font-black">Upload Loot Drops.xlsx</span>
              <span className="text-xs text-[var(--muted)]">Replaces the generator catalog with workbook items, settings, and formula rules.</span>
              <input
                type="file"
                accept=".xlsx,.xls"
                className="sr-only"
                disabled={saving}
                onChange={(event) => void importWorkbook(event.target.files?.[0] ?? null)}
              />
            </label>
            <div className="grid gap-2 rounded-2xl border border-[var(--line)] bg-black/10 p-3 text-xs font-bold text-[var(--muted)] sm:grid-cols-2">
              <span>Biomes: <b className="text-[var(--paper)]">{payload.settings.biomes.length}</b></span>
              <span>Pool sizes: <b className="text-[var(--paper)]">{payload.settings.poolSizes.length}</b></span>
              <span>Room types: <b className="text-[var(--paper)]">{payload.settings.roomTypes.length}</b></span>
              <span>Catalog items: <b className="text-[var(--paper)]">{payload.items.length}</b></span>
            </div>
          </Card>
        </div>

        <div className="space-y-4">
          <Card>
            <div className="rule-title mb-3"><h3 className="text-sm font-black uppercase tracking-wider">Adventure Cheat Sheet</h3></div>
            <div className="space-y-2">
              {ADVENTURE_NOTES.map((note) => (
                <details key={note.title} className="rounded-2xl border border-[var(--line)] bg-black/10">
                  <summary className="flex cursor-pointer list-none items-center gap-2 p-3 font-black"><Mountain size={15} className="text-[var(--brass)]" /> {note.title}</summary>
                  <p className="border-t border-[var(--line)] p-3 text-sm leading-6 text-[var(--muted)]">{note.text}</p>
                </details>
              ))}
            </div>
          </Card>
        </div>
      </div>
    </div>
  );
}
