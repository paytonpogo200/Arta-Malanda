'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { Compass, Dice6, FileUp, Gift, Loader2, Mountain, RefreshCw } from 'lucide-react';
import { ItemIcon } from '@/components/inventory/ItemIcon';
import { Button } from '@/components/ui/Button';
import { Card } from '@/components/ui/Card';
import { SelectField, TextAreaField } from '@/components/ui/Field';
import { NumberInput } from '@/components/ui/NumberInput';
import { normalizeExplorationPayload, normalizeLootRollPayload, parseLootImport, type ExplorationPayload } from '@/features/exploration/data';
import { rarityClass } from '@/lib/utils/rarity';
import type { LootDrop } from '@/lib/types';

const EMPTY: ExplorationPayload = { characters: [], pools: [], items: [] };

const ADVENTURE_NOTES = [
  { title: 'Bases', text: 'Organized enemy holdings. Expect patrols, locked rooms, storage areas, and a leader space. Good for structured missions.' },
  { title: 'Multi caves', text: 'Many separate paths are available early. Most tunnels lead toward their own encounter or boss room.' },
  { title: 'Forking caves', text: 'Several branches split from main tunnels. Some resemble trees, some become maze-like, and branches may start halfway down a path.' },
  { title: 'Snaking caves', text: 'A longer route where progress usually pushes deeper through one tunnel and boss room before the next path opens.' }
];

export function ExplorationPanel() {
  const [payload, setPayload] = useState<ExplorationPayload>(EMPTY);
  const [poolId, setPoolId] = useState('');
  const [rolls, setRolls] = useState(3);
  const [drops, setDrops] = useState<LootDrop[]>([]);
  const [selectedDropId, setSelectedDropId] = useState('');
  const [characterId, setCharacterId] = useState('');
  const [awardQuantity, setAwardQuantity] = useState(1);
  const [importText, setImportText] = useState('');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const selectedDrop = useMemo(() => drops.find((drop) => drop.id === selectedDropId) ?? drops[0] ?? null, [drops, selectedDropId]);

  const loadExploration = useCallback(async () => {
    setError('');
    try {
      const response = await fetch('/api/exploration', { cache: 'no-store' });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(body.error ?? 'Exploration tools could not be loaded.');
      const normalized = normalizeExplorationPayload(body);
      setPayload(normalized);
      setPoolId((current) => current || normalized.pools[0]?.id || '');
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
    if (!poolId) return;
    setSaving(true);
    setError('');
    try {
      const response = await fetch('/api/exploration/roll', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ poolId, rolls })
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

  async function importLoot() {
    setSaving(true);
    setError('');
    try {
      const rows = parseLootImport(importText);
      const response = await fetch('/api/exploration/import', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ rows })
      });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(body.error ?? 'Loot import failed.');
      setPayload(normalizeExplorationPayload(body));
      setImportText('');
    } catch (importError) {
      setError(importError instanceof Error ? importError.message : 'Loot import failed.');
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
            <div className="grid gap-2 sm:grid-cols-[1fr_8rem_auto]">
              <SelectField value={poolId} onChange={(event) => setPoolId(event.target.value)}>
                {payload.pools.map((pool) => <option key={pool.id} value={pool.id}>{pool.name}</option>)}
              </SelectField>
              <NumberInput min={1} max={200} value={rolls} onValueChange={setRolls} />
              <Button variant="primary" disabled={!poolId || saving} onClick={rollLoot}><Dice6 className="mr-2 inline" size={15} /> Roll</Button>
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
            <TextAreaField rows={6} value={importText} onChange={(event) => setImportText(event.target.value)} placeholder="CSV headers: pool,name,type,rarity,min,max,weight,notes&#10;or paste a JSON array with those fields." />
            <Button className="mt-2" variant="secondary" disabled={!importText.trim() || saving} onClick={importLoot}><FileUp className="mr-2 inline" size={15} /> Import rows</Button>
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
