'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { Heart, Loader2, ShieldAlert, Sparkles, Swords, Trash2, XCircle } from 'lucide-react';
import { BattleMap } from '@/components/battle/BattleMap';
import { InventoryPanel } from '@/components/inventory/InventoryPanel';
import { SpellsPanel } from '@/components/spells/SpellsPanel';
import { Button } from '@/components/ui/Button';
import { Card } from '@/components/ui/Card';
import { NumberInput } from '@/components/ui/NumberInput';
import { ResourceBar } from '@/components/ui/ResourceBar';
import { SelectField } from '@/components/ui/Field';
import { calculateCharacterSheetStats } from '@/features/characters/stats';
import { normalizeBattleRoomPayload, type BattleRoomPayload } from '@/features/battle/data';
import type { Character, Combatant, InventoryItem, Profile } from '@/lib/types';

type TokenView = Combatant & { character: Character | undefined };

const EMPTY_ROOM: BattleRoomPayload = {
  battle: null,
  combatants: [],
  terrain: [],
  characters: [],
  classes: [],
  inventoryItems: [],
  bestiary: []
};

export function BattleRoom({ profile }: { profile: Profile }) {
  const [room, setRoom] = useState<BattleRoomPayload>(EMPTY_ROOM);
  const [selectedIds, setSelectedIds] = useState<string[]>([]);
  const [selectedCombatantId, setSelectedCombatantId] = useState<string | null>(null);
  const [bestiaryEntityId, setBestiaryEntityId] = useState('');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const isDm = profile.role === 'dm';

  const characterById = useMemo(() => new Map(room.characters.map((character) => [character.id, character])), [room.characters]);
  const classByKey = useMemo(() => new Map(room.classes.map((template) => [template.key, template])), [room.classes]);
  const loadoutItemsByCharacterId = useMemo(() => {
    const grouped = new Map<string, InventoryItem[]>();
    room.inventoryItems.forEach((item) => {
      if (!item.loadoutSlot) return;
      grouped.set(item.characterId, [...(grouped.get(item.characterId) ?? []), item]);
    });
    return grouped;
  }, [room.inventoryItems]);
  const tokens = useMemo<TokenView[]>(() => room.combatants.map((combatant) => ({
    ...combatant,
    character: characterById.get(combatant.characterId)
  })), [characterById, room.combatants]);
  const selectedCombatant = room.combatants.find((entry) => entry.id === selectedCombatantId) ?? null;
  const selectedCharacter = selectedCombatant ? characterById.get(selectedCombatant.characterId) ?? null : null;
  const myCombatants = tokens.filter((entry) => entry.character?.ownerUserId === profile.id);
  const bestiaryOptions = useMemo(() => room.bestiary.filter((entry) => entry.unlocked || isDm).sort((a, b) => a.name.localeCompare(b.name)), [isDm, room.bestiary]);

  const loadRoom = useCallback(async () => {
    setError('');
    try {
      const response = await fetch('/api/battle', { cache: 'no-store' });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.error ?? 'Battlefield could not be loaded.');
      const normalized = normalizeBattleRoomPayload(payload);
      setRoom(normalized);
      setBestiaryEntityId((current) => current || normalized.bestiary[0]?.id || '');
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : 'Battlefield could not be loaded.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void loadRoom();
  }, [loadRoom]);

  useEffect(() => {
    if (selectedCombatantId && !room.combatants.some((entry) => entry.id === selectedCombatantId)) {
      setSelectedCombatantId(null);
    }
  }, [room.combatants, selectedCombatantId]);

  function toggleParticipant(characterId: string) {
    setSelectedIds((current) => current.includes(characterId)
      ? current.filter((id) => id !== characterId)
      : [...current, characterId]
    );
  }

  async function startBattle() {
    if (!isDm || selectedIds.length === 0) return;
    setSaving(true);
    setError('');
    try {
      const response = await fetch('/api/battle', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ characterIds: selectedIds, gridWidth: 24, gridHeight: 24 })
      });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.error ?? 'Combat could not be started.');
      setRoom(normalizeBattleRoomPayload(payload));
      setSelectedIds([]);
    } catch (startError) {
      setError(startError instanceof Error ? startError.message : 'Combat could not be started.');
    } finally {
      setSaving(false);
    }
  }

  async function endBattle() {
    if (!isDm) return;
    setSaving(true);
    setError('');
    try {
      const response = await fetch('/api/battle', { method: 'DELETE' });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.error ?? 'Combat could not be ended.');
      setRoom(normalizeBattleRoomPayload(payload));
      setSelectedCombatantId(null);
    } catch (endError) {
      setError(endError instanceof Error ? endError.message : 'Combat could not be ended.');
    } finally {
      setSaving(false);
    }
  }

  async function updateCombatant(combatant: Combatant, patch: Partial<Combatant>) {
    if (!isDm) return;
    const previous = room.combatants;
    setRoom((current) => ({
      ...current,
      combatants: current.combatants.map((entry) => entry.id === combatant.id ? { ...entry, ...patch } : entry)
    }));

    try {
      const response = await fetch(`/api/battle/combatants/${combatant.id}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(patch)
      });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.error ?? 'Combatant could not be changed.');
      const updated = payload.combatant as Combatant | undefined;
      if (updated?.id) {
        setRoom((current) => ({
          ...current,
          combatants: current.combatants.map((entry) => entry.id === updated.id ? updated : entry)
        }));
      }
    } catch (updateError) {
      setRoom((current) => ({ ...current, combatants: previous }));
      setError(updateError instanceof Error ? updateError.message : 'Combatant could not be changed.');
    }
  }

  async function replaceRoomFromResponse(response: Response, fallback: string) {
    const payload = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(payload.error ?? fallback);
    const normalized = normalizeBattleRoomPayload(payload);
    setRoom(normalized);
    setBestiaryEntityId((current) => current || normalized.bestiary[0]?.id || '');
  }

  async function setTerrain(cells: { x: number; y: number }[]) {
    if (!isDm || !cells.length) return;
    try {
      await replaceRoomFromResponse(await fetch('/api/battle/terrain', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ cells })
      }), 'Terrain could not be changed.');
    } catch (terrainError) {
      setError(terrainError instanceof Error ? terrainError.message : 'Terrain could not be changed.');
    }
  }

  async function removeTerrain(cells: { x: number; y: number }[]) {
    if (!isDm || !cells.length) return;
    try {
      await replaceRoomFromResponse(await fetch('/api/battle/terrain', {
        method: 'DELETE',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ cells })
      }), 'Terrain could not be changed.');
    } catch (terrainError) {
      setError(terrainError instanceof Error ? terrainError.message : 'Terrain could not be changed.');
    }
  }

  async function clearTerrain() {
    if (!isDm) return;
    try {
      await replaceRoomFromResponse(await fetch('/api/battle/terrain', {
        method: 'DELETE',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({})
      }), 'Terrain could not be cleared.');
    } catch (terrainError) {
      setError(terrainError instanceof Error ? terrainError.message : 'Terrain could not be cleared.');
    }
  }

  async function addBestiaryCombatant() {
    if (!isDm || !bestiaryEntityId) return;
    setSaving(true);
    setError('');
    try {
      await replaceRoomFromResponse(await fetch('/api/battle/bestiary', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ entityId: bestiaryEntityId })
      }), 'Bestiary combatant could not be added.');
    } catch (bestiaryError) {
      setError(bestiaryError instanceof Error ? bestiaryError.message : 'Bestiary combatant could not be added.');
    } finally {
      setSaving(false);
    }
  }

  async function removeCombatant(combatant: Combatant) {
    if (!isDm) return;
    setSaving(true);
    setError('');
    try {
      const response = await fetch(`/api/battle/combatants/${combatant.id}`, { method: 'DELETE' });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.error ?? 'Combatant could not be removed.');
      setRoom(normalizeBattleRoomPayload(payload));
      setSelectedCombatantId(null);
    } catch (removeError) {
      setError(removeError instanceof Error ? removeError.message : 'Combatant could not be removed.');
    } finally {
      setSaving(false);
    }
  }

  if (loading) {
    return (
      <Card>
        <div className="grid h-40 place-items-center text-[var(--muted)]">
          <Loader2 className="animate-spin" />
        </div>
      </Card>
    );
  }

  if (!room.battle) {
    return (
      <div className="space-y-4">
        {error && <div className="rounded-2xl border border-[var(--red)]/40 bg-[var(--red)]/10 p-3 text-sm text-[var(--red)]">{error}</div>}
        <Card>
          <p className="eyebrow mb-2">Battlefield</p>
          <h2 className="text-2xl font-black tracking-tight">The field is quiet.</h2>
        </Card>

        {isDm && (
          <Card>
            <div className="mb-4 flex items-center justify-between gap-3">
              <div><h3 className="font-black">Assemble the party</h3><p className="text-xs text-[var(--muted)]">{selectedIds.length} selected</p></div>
              <Button variant="primary" disabled={selectedIds.length === 0 || saving} onClick={startBattle}><Swords className="mr-2 inline" size={17} /> Begin encounter</Button>
            </div>
            <div className="grid gap-2 sm:grid-cols-2">
              {room.characters.filter((entry) => entry.kind === 'player').map((character) => {
                const chosen = selectedIds.includes(character.id);
                return (
                  <button key={character.id} onClick={() => toggleParticipant(character.id)} className={`flex items-center gap-3 rounded-xl border p-3 text-left transition ${chosen ? 'border-[var(--brass)] bg-[#d1a85b0e]' : 'border-[var(--line)] bg-black/10'}`}>
                    <span className="grid h-10 w-10 place-items-center rounded-full border border-white/20 font-black" style={{ backgroundColor: character.tokenColor }}>{character.name[0]}</span>
                    <span className="min-w-0 flex-1"><span className="block truncate font-black">{character.name}</span><span className="block truncate text-xs text-[var(--muted)]">Level {character.level} {character.className}</span></span>
                    <span className={`h-5 w-5 rounded-md border ${chosen ? 'border-[var(--brass)] bg-[var(--brass)]' : 'border-[var(--muted)]'}`} />
                  </button>
                );
              })}
              {!room.characters.some((entry) => entry.kind === 'player') && <div className="rounded-2xl border border-[var(--line)] bg-black/10 p-4 text-sm text-[var(--muted)]">Create characters before starting combat.</div>}
            </div>
          </Card>
        )}
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-4">
      {error && <div className="rounded-2xl border border-[var(--red)]/40 bg-[var(--red)]/10 p-3 text-sm text-[var(--red)]">{error}</div>}
      <BattleMap
        battle={room.battle}
        tokens={tokens}
        terrain={room.terrain}
        profile={profile}
        selectedId={selectedCombatantId}
        onSelect={(id) => setSelectedCombatantId((current) => current === id ? null : id)}
        onMove={(id, x, y) => {
          const combatant = room.combatants.find((entry) => entry.id === id);
          if (combatant) void updateCombatant(combatant, { x, y });
          setSelectedCombatantId(null);
        }}
        onTerrainAdd={(cells) => void setTerrain(cells)}
        onTerrainRemove={(cells) => void removeTerrain(cells)}
        onTerrainClear={() => void clearTerrain()}
      />

      <Card>
        <div className="mb-3 flex flex-wrap items-center justify-between gap-3">
          <h3 className="font-black">Encounter Roster</h3>
          {isDm && (
            <div className="flex flex-wrap items-center gap-2">
              <SelectField value={bestiaryEntityId} onChange={(event) => setBestiaryEntityId(event.target.value)} className="min-w-52">
                <option value="">Add from bestiary</option>
                {bestiaryOptions.map((entity) => <option key={entity.id} value={entity.id}>{entity.name}</option>)}
              </SelectField>
              <Button variant="teal" disabled={!bestiaryEntityId || saving} onClick={addBestiaryCombatant}>Add</Button>
              <Button variant="danger" disabled={saving} onClick={endBattle}><XCircle className="mr-2 inline" size={16} /> End encounter</Button>
            </div>
          )}
        </div>
        <div className="grid gap-2 sm:grid-cols-2">
          {tokens.map((entry) => {
            const character = entry.character;
            const loadoutItems = character ? loadoutItemsByCharacterId.get(character.id) ?? [] : [];
            const sheetStats = character ? calculateCharacterSheetStats(character, loadoutItems, classByKey.get(character.classKey)) : null;
            return (
              <article key={entry.id} className={`rounded-xl border p-3 transition ${selectedCombatantId === entry.id ? 'border-[var(--brass)] bg-[#d1a85b0b]' : 'border-[var(--line)] bg-black/10'}`}>
                <button type="button" onClick={() => setSelectedCombatantId((current) => current === entry.id ? null : entry.id)} className="w-full text-left">
                  <div className="mb-2 flex items-center justify-between gap-2">
                    <span className="min-w-0 flex items-center gap-2">
                      <span className="truncate font-black">{character?.name ?? 'Unknown'}</span>
                      <span className="shrink-0 rounded-md border border-[var(--line)] bg-black/25 px-2 py-1 text-[10px] font-black uppercase tracking-wide text-[var(--muted)]">{character?.className ?? 'Adventurer'}</span>
                    </span>
                  </div>
                  <div className="grid gap-3">
                    <div className="grid grid-cols-2 gap-3">
                      <ResourceBar label="HP" tone="hp" current={entry.currentHp} max={sheetStats?.maxHp ?? character?.maxHp ?? 1} />
                      <ResourceBar label="Mana" tone="mana" current={entry.currentMana} max={sheetStats?.maxMana ?? character?.maxMana ?? 1} />
                    </div>
                    <div className="grid grid-cols-2 gap-2">
                      <span className="rounded-xl border border-[var(--line)] bg-black/15 p-2">
                        <span className="block text-[10px] font-black uppercase tracking-wide text-[var(--muted)]">Defense</span>
                        <span className="mt-1 block text-lg font-black text-[var(--paper)]">{sheetStats?.defense ?? 0}</span>
                      </span>
                      <span className="rounded-xl border border-[var(--line)] bg-black/15 p-2">
                        <span className="block text-[10px] font-black uppercase tracking-wide text-[var(--muted)]">Magic Resist</span>
                        <span className="mt-1 block text-lg font-black text-[var(--paper)]">{sheetStats?.magicResist ?? character?.magicResist ?? 0}</span>
                      </span>
                    </div>
                  </div>
                </button>
                {isDm && (
                  <div className="mt-3 flex justify-end">
                    <Button variant="secondary" className="px-3 py-2 text-xs" disabled={saving} onClick={() => removeCombatant(entry)}><Trash2 className="mr-1 inline" size={13} /> Remove</Button>
                  </div>
                )}
              </article>
            );
          })}
        </div>
      </Card>

      {isDm && selectedCombatant && selectedCharacter && (
        <Card>
          <div className="mb-4 flex items-center gap-2"><ShieldAlert size={18} className="text-[var(--brass)]" /><h3 className="font-black">DM Controls · {selectedCharacter.name}</h3></div>
          <div className="grid grid-cols-3 gap-2">
            <label><span className="mb-1 block text-[10px] font-black uppercase text-[var(--red)]"><Heart className="mr-1 inline" size={11} /> Health</span><NumberInput min={0} value={selectedCombatant.currentHp} onValueChange={(currentHp) => updateCombatant(selectedCombatant, { currentHp })} /></label>
            <label><span className="mb-1 block text-[10px] font-black uppercase text-[var(--blue)]"><Sparkles className="mr-1 inline" size={11} /> Mana</span><NumberInput min={0} value={selectedCombatant.currentMana} onValueChange={(currentMana) => updateCombatant(selectedCombatant, { currentMana })} /></label>
            <label><span className="mb-1 block text-[10px] font-black uppercase text-[var(--muted)]">Initiative</span><NumberInput min={1} max={20} value={selectedCombatant.initiative ?? 1} emptyFallback={1} onValueChange={(initiative) => updateCombatant(selectedCombatant, { initiative })} /></label>
          </div>
        </Card>
      )}

      {!isDm && myCombatants.length > 0 && (
        <div className="space-y-4">
          {myCombatants.map((entry) => entry.character && (
            <div key={entry.id} className="space-y-4">
              <SpellsPanel
                character={{ ...entry.character, currentHp: entry.currentHp, currentMana: entry.currentMana }}
                canManage
                canGrant={false}
                combatLocked
                onManaChanged={(currentMana) => setRoom((current) => ({
                  ...current,
                  combatants: current.combatants.map((combatant) => combatant.id === entry.id ? { ...combatant, currentMana } : combatant)
                }))}
              />
              <InventoryPanel character={{ ...entry.character, currentHp: entry.currentHp, currentMana: entry.currentMana }} canManage canAdd={false} />
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
