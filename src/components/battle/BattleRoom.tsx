'use client';

import { useCallback, useEffect, useMemo, useState, type ReactNode } from 'react';
import { Clock3, CopyPlus, Eye, FlaskConical, Heart, Loader2, Plus, ShieldAlert, ShieldCheck, Sparkles, Swords, Trash2, UserRound, XCircle } from 'lucide-react';
import { BattleMap } from '@/components/battle/BattleMap';
import { CombatStatusBadges } from '@/components/battle/CombatStatusBadges';
import { characterLevelFrameClass, LevelBadge } from '@/components/characters/LevelBadge';
import { InventoryPanel } from '@/components/inventory/InventoryPanel';
import { SpellsPanel } from '@/components/spells/SpellsPanel';
import { Button } from '@/components/ui/Button';
import { Card } from '@/components/ui/Card';
import { ResourceBar } from '@/components/ui/ResourceBar';
import { SelectField, TextField } from '@/components/ui/Field';
import { Modal } from '@/components/ui/Modal';
import { calculateCharacterSheetStats } from '@/features/characters/stats';
import { normalizeBattleRoomPayload, type BattleRoomPayload } from '@/features/battle/data';
import { useLiveRefresh } from '@/hooks/useLiveRefresh';
import type { Character, Combatant, CombatStatus, InventoryItem, Profile } from '@/lib/types';

type TokenView = Combatant & { character: Character | undefined };

const DM_VIEW = 'dm';
const SPECTATOR_VIEW = 'spectator';

const BATTLE_EFFECT_OPTIONS: Array<{ key: string; name: string; kind: 'buff' | 'debuff'; description: string }> = [
  { key: 'better-dice', name: 'Better Dice', kind: 'buff', description: 'Marks improved dice rolls.' },
  { key: 'bleeding', name: 'Bleeding', kind: 'debuff', description: 'Prevents every form of healing while active.' },
  { key: 'burning', name: 'Burning', kind: 'debuff', description: 'Deals 10 damage on Start Turn and prevents every form of healing.' },
  { key: 'counterattack', name: 'Counterattack', kind: 'buff', description: 'Marks the target as ready to counterattack.' },
  { key: 'invisible', name: 'Invisible', kind: 'buff', description: 'Marks the target as invisible.' },
  { key: 'ironskin', name: 'Ironskin', kind: 'buff', description: 'Marks the target with hardened defenses.' },
  { key: 'poison', name: 'Poison', kind: 'debuff', description: 'Adds a separate stack that deals 5 damage on Start Turn.' },
  { key: 'slowness', name: 'Slowness', kind: 'debuff', description: 'Marks reduced movement or speed.' },
  { key: 'strength', name: 'Strength', kind: 'buff', description: 'Marks increased physical strength.' },
  { key: 'stunned', name: 'Stunned', kind: 'debuff', description: 'Marks the target as stunned.' },
  { key: 'swiftness', name: 'Swiftness', kind: 'buff', description: 'Marks increased movement or speed.' },
  { key: 'weakness', name: 'Weakness', kind: 'debuff', description: 'Marks reduced physical power.' }
];

const EMPTY_ROOM: BattleRoomPayload = {
  battle: null,
  combatants: [],
  terrain: [],
  characters: [],
  classes: [],
  inventoryItems: [],
  bestiary: []
};

function CombatantStatField({
  label,
  icon,
  toneClass,
  value,
  min = 0,
  max,
  onCommit
}: {
  label: string;
  icon?: ReactNode;
  toneClass: string;
  value: number;
  min?: number;
  max?: number;
  onCommit: (value: number) => void;
}) {
  const [draft, setDraft] = useState(String(value));

  useEffect(() => {
    setDraft(String(value));
  }, [value]);

  const commit = useCallback(() => {
    const parsed = Number(draft);
    if (!Number.isFinite(parsed)) {
      setDraft(String(value));
      return;
    }
    const rounded = Math.round(parsed);
    const clamped = Math.max(min, max === undefined ? rounded : Math.min(max, rounded));
    setDraft(String(clamped));
    if (clamped !== value) onCommit(clamped);
  }, [draft, max, min, onCommit, value]);

  return (
    <label>
      <span className={`mb-1 block text-[10px] font-black uppercase ${toneClass}`}>{icon} {label}</span>
      <input
        type="number"
        min={min}
        max={max}
        value={draft}
        className="field"
        onChange={(event) => setDraft(event.target.value)}
        onBlur={commit}
        onKeyDown={(event) => {
          if (event.key === 'Enter') {
            event.currentTarget.blur();
          }
        }}
      />
    </label>
  );
}

export function BattleRoom({ profile }: { profile: Profile }) {
  const [room, setRoom] = useState<BattleRoomPayload>(EMPTY_ROOM);
  const [selectedIds, setSelectedIds] = useState<string[]>([]);
  const [selectedCombatantId, setSelectedCombatantId] = useState<string | null>(null);
  const [bestiaryEntityId, setBestiaryEntityId] = useState('');
  const [bestiarySearch, setBestiarySearch] = useState('');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [statusEditorOpen, setStatusEditorOpen] = useState(false);
  const [editingStatusId, setEditingStatusId] = useState<string | null>(null);
  const [statusNotice, setStatusNotice] = useState('');
  const isDm = profile.role === 'dm';
  const [viewingAs, setViewingAs] = useState(isDm ? DM_VIEW : SPECTATOR_VIEW);

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
  const inventoryItemsByCharacterId = useMemo(() => {
    const grouped = new Map<string, InventoryItem[]>();
    room.inventoryItems.forEach((item) => {
      grouped.set(item.characterId, [...(grouped.get(item.characterId) ?? []), item]);
    });
    return grouped;
  }, [room.inventoryItems]);
  const tokens = useMemo<TokenView[]>(() => room.combatants.map((combatant) => ({
    ...combatant,
    character: characterById.get(combatant.characterId)
  })), [characterById, room.combatants]);
  const orderedTokens = useMemo(() => [...tokens].sort((a, b) => {
    const initiativeA = a.initiative ?? -1;
    const initiativeB = b.initiative ?? -1;
    if (initiativeA !== initiativeB) return initiativeB - initiativeA;
    return (a.character?.name ?? '').localeCompare(b.character?.name ?? '');
  }), [tokens]);
  const selectedCombatant = room.combatants.find((entry) => entry.id === selectedCombatantId) ?? null;
  const selectedCharacter = selectedCombatant ? characterById.get(selectedCombatant.characterId) ?? null : null;
  const playerViewTokens = useMemo(() => orderedTokens.filter((entry) => entry.character?.kind === 'player'), [orderedTokens]);
  const myCombatants = useMemo(() => playerViewTokens.filter((entry) => entry.character?.ownerUserId === profile.id), [playerViewTokens, profile.id]);
  const viewerOptions = useMemo(() => {
    return (isDm ? playerViewTokens : myCombatants)
      .filter((entry) => entry.character)
      .map((entry) => ({ id: entry.id, label: entry.character?.name ?? 'Unknown character' }));
  }, [isDm, myCombatants, playerViewTokens]);
  const viewedCombatant = orderedTokens.find((entry) => entry.id === viewingAs) ?? null;
  const viewedCharacter = viewedCombatant?.character ?? null;
  const spellBookTargets = useMemo(() => orderedTokens
    .filter((entry) => entry.character?.kind === 'player')
    .map((entry) => ({
      ...entry.character!,
      currentHp: entry.currentHp,
      currentMana: entry.currentMana
    })), [orderedTokens]);
  const canUseDmTools = isDm && viewingAs === DM_VIEW;
  const isSpectator = !isDm && myCombatants.length === 0;
  const bestiaryOptions = useMemo(() => room.bestiary.filter((entry) => entry.unlocked || isDm).sort((a, b) => a.name.localeCompare(b.name)), [isDm, room.bestiary]);
  const filteredBestiaryOptions = useMemo(() => {
    const needle = bestiarySearch.trim().toLowerCase();
    if (!needle) return bestiaryOptions;
    return bestiaryOptions.filter((entity) => `${entity.name} ${entity.category} ${entity.summary}`.toLowerCase().includes(needle));
  }, [bestiaryOptions, bestiarySearch]);

  const loadRoom = useCallback(async (showLoading = true) => {
    if (showLoading) setLoading(true);
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
      if (showLoading) setLoading(false);
    }
  }, []);

  useLiveRefresh(['battle', 'characters', 'inventory', 'spells', 'bestiary'], () => loadRoom(false), { debounceMs: 150 });

  useEffect(() => {
    void loadRoom();
  }, [loadRoom]);

  useEffect(() => {
    if (selectedCombatantId && !room.combatants.some((entry) => entry.id === selectedCombatantId)) {
      setSelectedCombatantId(null);
    }
  }, [room.combatants, selectedCombatantId]);

  useEffect(() => {
    const validIds = new Set(viewerOptions.map((entry) => entry.id));
    const fallback = isDm ? DM_VIEW : viewerOptions[0]?.id ?? SPECTATOR_VIEW;
    if (viewingAs !== DM_VIEW && !validIds.has(viewingAs)) setViewingAs(fallback);
  }, [isDm, viewerOptions, viewingAs]);

  useEffect(() => {
    if (canUseDmTools) return;
    setSelectedCombatantId(null);
  }, [canUseDmTools]);

  useEffect(() => {
    if (!bestiaryEntityId || filteredBestiaryOptions.some((entity) => entity.id === bestiaryEntityId)) return;
    setBestiaryEntityId('');
  }, [bestiaryEntityId, filteredBestiaryOptions]);

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
    if (!canUseDmTools) return;
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
    if (!canUseDmTools) return;
    const previous = room.combatants;
    setRoom((current) => ({
      ...current,
      combatants: current.combatants.map((entry) => entry.id === combatant.id || (patch.currentHp !== undefined && entry.characterId === combatant.characterId)
        ? { ...entry, ...patch }
        : entry)
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
          combatants: current.combatants.map((entry) => entry.id === updated.id
            ? updated
            : patch.currentHp !== undefined && entry.characterId === updated.characterId
              ? { ...entry, currentHp: updated.currentHp }
              : entry)
        }));
      }
    } catch (updateError) {
      setRoom((current) => ({ ...current, combatants: previous }));
      setError(updateError instanceof Error ? updateError.message : 'Combatant could not be changed.');
    }
  }

  async function splitCombatant(combatant: Combatant) {
    if (!canUseDmTools) return;
    setSaving(true);
    setError('');
    try {
      const response = await fetch(`/api/battle/combatants/${combatant.id}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ action: 'split' })
      });
      await replaceRoomFromResponse(response, 'The Malignant Neoplasm could not split.');
    } catch (splitError) {
      setError(splitError instanceof Error ? splitError.message : 'The Malignant Neoplasm could not split.');
    } finally {
      setSaving(false);
    }
  }

  async function updateCombatantStatuses(combatant: Combatant, action: 'add' | 'set-duration' | 'extend-poison' | 'start-turn' | 'cleanse', options: { statusKey?: string; statusId?: string; duration?: number } = {}) {
    if (!canUseDmTools) return;
    setSaving(true);
    setError('');
    setStatusNotice('');
    try {
      const response = await fetch(`/api/battle/combatants/${combatant.id}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ action, ...options })
      });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.error ?? 'Battle effects could not be changed.');
      const updated = payload.combatant as Combatant | undefined;
      if (updated?.id) {
        setRoom((current) => ({
          ...current,
          combatants: current.combatants.map((entry) => entry.id === updated.id
            ? updated
            : entry.characterId === updated.characterId
              ? { ...entry, currentHp: updated.currentHp, currentMana: updated.currentMana, statuses: updated.statuses }
              : entry)
        }));
      }
      if (action === 'start-turn') {
        const gains = [payload.healthRestored > 0 ? `${payload.healthRestored} HP restored` : '', payload.manaRestored > 0 ? `${payload.manaRestored} Mana restored` : ''].filter(Boolean).join(' and ');
        const damage = payload.damage > 0 ? `${payload.damage} damage dealt` : 'no damage dealt';
        setStatusNotice(`${gains ? `${gains}, then ` : ''}${damage}. Durations advanced.`);
      }
      if (action === 'cleanse') setStatusNotice('All debuffs cleansed without dealing damage.');
    } catch (statusError) {
      setError(statusError instanceof Error ? statusError.message : 'Battle effects could not be changed.');
    } finally {
      setSaving(false);
    }
  }

  function openStatusEditor(status?: CombatStatus) {
    setEditingStatusId(status?.id ?? null);
    setStatusNotice('');
    setStatusEditorOpen(true);
  }

  function updateLocalCombatant(combatantId: string, patch: Partial<Combatant>) {
    setRoom((current) => ({
      ...current,
      combatants: current.combatants.map((combatant) => combatant.id === combatantId ? { ...combatant, ...patch } : combatant)
    }));
  }

  async function replaceRoomFromResponse(response: Response, fallback: string) {
    const payload = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(payload.error ?? fallback);
    const normalized = normalizeBattleRoomPayload(payload);
    setRoom(normalized);
    setBestiaryEntityId((current) => current || normalized.bestiary[0]?.id || '');
  }

  async function setTerrain(cells: { x: number; y: number }[]) {
    if (!canUseDmTools || !cells.length) return;
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
    if (!canUseDmTools || !cells.length) return;
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
    if (!canUseDmTools) return;
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
    if (!canUseDmTools || !bestiaryEntityId) return;
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
    if (!canUseDmTools) return;
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
                  <button key={character.id} onClick={() => toggleParticipant(character.id)} className={`flex items-center gap-3 rounded-xl border p-3 text-left transition ${characterLevelFrameClass(character.level, 'ledger')} ${chosen ? 'border-[var(--brass)] bg-[#d1a85b0e]' : 'border-[var(--line)] bg-black/10'}`}>
                    <span className="grid h-10 w-10 place-items-center rounded-full border border-white/20 font-black" style={{ background: character.tokenColor }}>{character.name[0]}</span>
                    <span className="min-w-0 flex-1">
                      <span className="flex min-w-0 items-center gap-2">
                        <span className="truncate font-black">{character.name}</span>
                        <LevelBadge level={character.level} compact />
                      </span>
                      <span className="block truncate text-xs text-[var(--muted)]">{character.className}</span>
                    </span>
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
      <Card>
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <p className="eyebrow">Viewing As</p>
            <h2 className="mt-1 flex items-center gap-2 text-xl font-black">
              {canUseDmTools ? <ShieldAlert size={18} className="text-[var(--brass)]" /> : isSpectator ? <Eye size={18} className="text-[var(--muted)]" /> : <UserRound size={18} className="text-[var(--teal)]" />}
              {canUseDmTools ? 'Dungeon Master' : isSpectator ? 'Spectator' : viewedCharacter?.name ?? 'Character'}
            </h2>
          </div>
          <div className="flex min-w-56 flex-wrap items-center gap-2">
            {viewerOptions.length > 0 ? (
              <SelectField value={viewingAs === DM_VIEW ? '' : viewingAs} onChange={(event) => setViewingAs(event.target.value)} className="min-w-56">
                {isDm && <option value="">View a character screen</option>}
                {viewerOptions.map((option) => <option key={option.id} value={option.id}>{option.label}</option>)}
              </SelectField>
            ) : (
              <div className="rounded-xl border border-[var(--line)] bg-black/20 px-4 py-3 text-sm font-black text-[var(--muted)]">Spectator</div>
            )}
            {isDm && !canUseDmTools && <Button variant="secondary" className="px-3 py-2 text-xs" onClick={() => setViewingAs(DM_VIEW)}>DM View</Button>}
          </div>
        </div>
      </Card>
      <BattleMap
        battle={room.battle}
        tokens={orderedTokens}
        terrain={room.terrain}
        profile={profile}
        canEditMap={canUseDmTools}
        viewingCharacterId={viewedCharacter?.id ?? null}
        selectedId={canUseDmTools ? selectedCombatantId : null}
        onSelect={canUseDmTools ? setSelectedCombatantId : () => undefined}
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
          {canUseDmTools && (
            <Button variant="danger" disabled={saving} onClick={endBattle}><XCircle className="mr-2 inline" size={16} /> End encounter</Button>
          )}
        </div>
        {canUseDmTools && (
          <div className="mb-4 grid gap-2 rounded-2xl border border-[var(--line)] bg-black/10 p-3 lg:grid-cols-[1fr_1fr_auto]">
            <label>
              <span className="mb-1 block text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">Search Bestiary</span>
              <TextField value={bestiarySearch} onChange={(event) => setBestiarySearch(event.target.value)} placeholder="Search entity name, category, or summary" />
            </label>
            <label>
              <span className="mb-1 block text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">Entity</span>
              <SelectField value={bestiaryEntityId} onChange={(event) => setBestiaryEntityId(event.target.value)}>
                <option value="">{filteredBestiaryOptions.length ? 'Choose from bestiary' : 'No matching entities'}</option>
                {filteredBestiaryOptions.map((entity) => <option key={entity.id} value={entity.id}>{entity.name}</option>)}
              </SelectField>
            </label>
            <div className="flex items-end">
              <Button variant="teal" className="w-full lg:w-auto" disabled={!bestiaryEntityId || saving || !filteredBestiaryOptions.some((entity) => entity.id === bestiaryEntityId)} onClick={addBestiaryCombatant}>Add Entity</Button>
            </div>
          </div>
        )}
        <div className="grid gap-2 sm:grid-cols-2">
          {orderedTokens.map((entry) => {
            const character = entry.character;
            const loadoutItems = character ? loadoutItemsByCharacterId.get(character.id) ?? [] : [];
            const sheetStats = character ? calculateCharacterSheetStats(character, loadoutItems, classByKey.get(character.classKey)) : null;
            return (
              <article key={entry.id} className={`rounded-xl border p-3 transition ${characterLevelFrameClass(character?.level, 'battle-card')} ${selectedCombatantId === entry.id ? 'border-[var(--brass)] bg-[#d1a85b0b]' : 'border-[var(--line)] bg-black/10'}`}>
                <button type="button" onClick={canUseDmTools ? () => setSelectedCombatantId((current) => current === entry.id ? null : entry.id) : undefined} className={`w-full text-left ${canUseDmTools ? '' : 'cursor-default'}`}>
                  <div className="mb-2 flex items-center justify-between gap-2">
                    <span className="min-w-0 flex items-center gap-2">
                      <span className="truncate font-black">{character?.name ?? 'Unknown'}</span>
                      <LevelBadge level={character?.level} compact />
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
                    <span className="rounded-xl border border-[var(--line)] bg-black/15 p-2">
                      <span className="block text-[10px] font-black uppercase tracking-wide text-[var(--muted)]">Initiative</span>
                      <span className="mt-1 block text-lg font-black text-[var(--paper)]">{entry.initiative ?? 'Unset'}</span>
                    </span>
                    {!!entry.statuses.length && <span className="flex items-center gap-2 rounded-xl border border-[var(--line)] bg-black/15 p-2"><span className="text-[10px] font-black uppercase tracking-wide text-[var(--muted)]">Effects</span><CombatStatusBadges statuses={entry.statuses} compact /></span>}
                  </div>
                </button>
                {canUseDmTools && (
                  <div className="mt-3 flex justify-end">
                    <Button variant="secondary" className="px-3 py-2 text-xs" disabled={saving} onClick={() => removeCombatant(entry)}><Trash2 className="mr-1 inline" size={13} /> Remove</Button>
                  </div>
                )}
              </article>
            );
          })}
        </div>
      </Card>

      {canUseDmTools && selectedCombatant && selectedCharacter && (
        <Card>
          <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
            <div className="flex items-center gap-2"><ShieldAlert size={18} className="text-[var(--brass)]" /><h3 className="font-black">DM Controls - {selectedCharacter.name}</h3></div>
            <div className="flex flex-wrap gap-2">
              <Button variant="danger" className="px-3 py-2 text-xs" disabled={saving} onClick={() => openStatusEditor()}><Plus className="mr-1 inline" size={13} /> Add Buff/Debuff</Button>
              <Button variant="primary" className="px-3 py-2 text-xs" disabled={saving} onClick={() => void updateCombatantStatuses(selectedCombatant, 'start-turn')}><Clock3 className="mr-1 inline" size={13} /> Start Turn</Button>
              {selectedCharacter.name.trim().toLowerCase() === 'the malignant neoplasm' && <Button variant="teal" className="px-3 py-2 text-xs" disabled={saving} onClick={() => void splitCombatant(selectedCombatant)}><CopyPlus className="mr-1 inline" size={13} /> Split</Button>}
            </div>
          </div>
          <div className="grid gap-2 sm:grid-cols-3">
            <CombatantStatField label="Health" icon={<Heart className="mr-1 inline" size={11} />} toneClass="text-[var(--red)]" value={selectedCombatant.currentHp} onCommit={(currentHp) => updateCombatant(selectedCombatant, { currentHp })} />
            <CombatantStatField label="Mana" icon={<Sparkles className="mr-1 inline" size={11} />} toneClass="text-[var(--blue)]" value={selectedCombatant.currentMana} onCommit={(currentMana) => updateCombatant(selectedCombatant, { currentMana })} />
            <CombatantStatField label="Initiative" toneClass="text-[var(--muted)]" value={selectedCombatant.initiative ?? 1} min={1} max={20} onCommit={(initiative) => updateCombatant(selectedCombatant, { initiative })} />
          </div>
          {!!selectedCombatant.statuses.length && <div className="mt-3 rounded-xl border border-[var(--line)] bg-black/15 p-3"><p className="mb-2 text-[10px] font-black uppercase tracking-wide text-[var(--muted)]">Active effects - tap a timed effect to edit its duration</p><CombatStatusBadges statuses={selectedCombatant.statuses} onStatusClick={openStatusEditor} /></div>}
          {statusNotice && <p className="mt-3 rounded-xl border border-[var(--line)] bg-black/15 p-3 text-sm font-bold text-[var(--paper)]">{statusNotice}</p>}
        </Card>
      )}

      {viewedCombatant && viewedCharacter && (
        <div className="space-y-4">
          <SpellsPanel
            character={{ ...viewedCharacter, currentHp: viewedCombatant.currentHp, currentMana: viewedCombatant.currentMana }}
            canManage
            canGrant={false}
            combatLocked
            activeOnly
            enchantedItems={inventoryItemsByCharacterId.get(viewedCharacter.id) ?? []}
            onManaChanged={(currentMana) => updateLocalCombatant(viewedCombatant.id, { currentMana })}
          />
          <InventoryPanel
            character={{ ...viewedCharacter, currentHp: viewedCombatant.currentHp, currentMana: viewedCombatant.currentMana }}
            canManage
            canAdd={false}
            tradeCharacters={room.characters}
            showBattleStats
            classTemplate={classByKey.get(viewedCharacter.classKey)}
            onResourceChanged={(patch) => updateLocalCombatant(viewedCombatant.id, patch)}
            spellBookTargets={spellBookTargets}
            onSpellBookUsed={(result) => {
              const caster = room.combatants.find((entry) => entry.characterId === result.characterId);
              if (caster) updateLocalCombatant(caster.id, { currentMana: result.currentMana });
              const target = room.combatants.find((entry) => entry.characterId === result.targetCharacterId);
              if (target) updateLocalCombatant(target.id, { currentHp: result.targetCurrentHp, currentMana: result.targetCurrentMana });
            }}
          />
        </div>
      )}
      {statusEditorOpen && selectedCombatant && selectedCharacter && (
        <Modal title={`Battle Effects - ${selectedCharacter.name}`} onClose={() => { setStatusEditorOpen(false); setEditingStatusId(null); }}>
          <div className="space-y-4 pb-2">
            {editingStatusId && (() => {
              const status = selectedCombatant.statuses.find((entry) => entry.id === editingStatusId);
              if (!status || status.duration === null) return null;
              const duration = status.duration;
              return <section className="rounded-2xl border border-[var(--line)] bg-black/15 p-4"><p className="eyebrow">Edit duration</p><div className="mt-2 flex items-center justify-between gap-3"><CombatStatusBadges statuses={[status]} /><div className="flex items-center gap-2"><Button variant="secondary" className="h-10 w-10 p-0" disabled={saving || duration <= 1} onClick={() => void updateCombatantStatuses(selectedCombatant, 'set-duration', { statusId: status.id, duration: duration - 1 })}>-</Button><span className="min-w-10 text-center text-xl font-black">{duration}</span><Button variant="secondary" className="h-10 w-10 p-0" disabled={saving || duration >= 99} onClick={() => void updateCombatantStatuses(selectedCombatant, 'set-duration', { statusId: status.id, duration: duration + 1 })}>+</Button></div></div></section>;
            })()}
            <section>
              <p className="eyebrow mb-2">Add an effect</p>
              <div className="grid gap-3 sm:grid-cols-2">
                {(['buff', 'debuff'] as const).map((kind) => (
                  <div key={kind} className={`rounded-2xl border p-3 ${kind === 'buff' ? 'border-[#4c9ed3]/70 bg-[#174e732b]' : 'border-[#d65b52]/70 bg-[#72231f2b]'}`}>
                    <p className={`mb-2 text-xs font-black uppercase tracking-wider ${kind === 'buff' ? 'text-[#9fdcff]' : 'text-[#ffafa7]'}`}>{kind === 'buff' ? 'Buffs' : 'Debuffs'}</p>
                    <div className="grid gap-2">
                      {BATTLE_EFFECT_OPTIONS.filter((effect) => effect.kind === kind).map((effect) => (
                        <button key={effect.key} type="button" disabled={saving} onClick={() => void updateCombatantStatuses(selectedCombatant, 'add', { statusKey: effect.key })} className={`flex items-center gap-3 rounded-xl border p-3 text-left transition disabled:opacity-50 ${kind === 'buff' ? 'border-[#4c9ed3] bg-[#174e7355] hover:bg-[#174e7377]' : 'border-[#d65b52] bg-[#72231f55] hover:bg-[#72231f77]'}`}>
                          <CombatStatusBadges statuses={[{ id: `option-${effect.key}`, key: effect.key, name: effect.name, kind: effect.kind, duration: 1, amount: 0 }]} compact />
                          <span><span className={`block font-black ${kind === 'buff' ? 'text-[#9fdcff]' : 'text-[#ffafa7]'}`}>{effect.name}</span><span className="text-xs text-[var(--muted)]">{effect.description}</span></span>
                        </button>
                      ))}
                    </div>
                  </div>
                ))}
              </div>
            </section>
            {!!selectedCombatant.statuses.length && (
              <div className="grid gap-3 sm:grid-cols-2">
                <div className="rounded-2xl border border-[#4c9ed3]/50 bg-[#174e7322] p-3">
                  <p className="mb-2 text-[10px] font-black uppercase tracking-wider text-[#9fdcff]">Active buffs</p>
                  {selectedCombatant.statuses.some((entry) => entry.kind !== 'debuff')
                    ? <CombatStatusBadges statuses={selectedCombatant.statuses.filter((entry) => entry.kind !== 'debuff')} onStatusClick={(status) => setEditingStatusId(status.id)} />
                    : <p className="text-xs font-bold text-[var(--muted)]">None</p>}
                </div>
                <div className="rounded-2xl border border-[#d65b52]/50 bg-[#72231f22] p-3">
                  <p className="mb-2 text-[10px] font-black uppercase tracking-wider text-[#ffafa7]">Active debuffs</p>
                  {selectedCombatant.statuses.some((entry) => entry.kind === 'debuff')
                    ? <CombatStatusBadges statuses={selectedCombatant.statuses.filter((entry) => entry.kind === 'debuff')} onStatusClick={(status) => setEditingStatusId(status.id)} />
                    : <p className="text-xs font-bold text-[var(--muted)]">None</p>}
                </div>
              </div>
            )}
            {selectedCombatant.statuses.some((entry) => entry.key === 'poison') && <Button variant="secondary" className="w-full" disabled={saving} onClick={() => void updateCombatantStatuses(selectedCombatant, 'extend-poison')}><FlaskConical className="mr-2 inline" size={15} /> Increase all poison durations by 1</Button>}
            {statusNotice && <p className="rounded-xl border border-[var(--line)] bg-black/15 p-3 text-sm font-bold">{statusNotice}</p>}
            <div className="flex justify-end gap-2 border-t border-[var(--line)] pt-3"><Button variant="teal" disabled={saving || !selectedCombatant.statuses.some((entry) => entry.kind === 'debuff')} onClick={() => void updateCombatantStatuses(selectedCombatant, 'cleanse')}><ShieldCheck className="mr-2 inline" size={16} /> Cleanse</Button><Button variant="secondary" onClick={() => { setStatusEditorOpen(false); setEditingStatusId(null); }}>Close</Button></div>
          </div>
        </Modal>
      )}
    </div>
  );
}
