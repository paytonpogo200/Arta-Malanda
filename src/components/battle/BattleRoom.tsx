'use client';

import { useMemo, useState } from 'react';
import { Heart, ShieldAlert, Sparkles, Swords, XCircle } from 'lucide-react';
import { BattleMap } from '@/components/battle/BattleMap';
import { InventoryPanel } from '@/components/inventory/InventoryPanel';
import { Button } from '@/components/ui/Button';
import { Card } from '@/components/ui/Card';
import { NumberInput } from '@/components/ui/NumberInput';
import { ResourceBar } from '@/components/ui/ResourceBar';
import { useCampaignDispatch, useCampaignState } from '@/features/campaign/CampaignProvider';
import type { Combatant } from '@/lib/types';

export function BattleRoom() {
  const state = useCampaignState();
  const dispatch = useCampaignDispatch();
  const [selectedIds, setSelectedIds] = useState<string[]>([]);
  const [selectedCombatantId, setSelectedCombatantId] = useState<string | null>(null);
  const isDm = state.profile.role === 'dm';

  const tokens = useMemo(() => state.combatants.map((combatant) => ({
    ...combatant,
    character: state.characters.find((character) => character.id === combatant.characterId)
  })), [state.combatants, state.characters]);
  const selectedCombatant = state.combatants.find((entry) => entry.id === selectedCombatantId) ?? null;
  const selectedCharacter = selectedCombatant ? state.characters.find((entry) => entry.id === selectedCombatant.characterId) ?? null : null;
  const myCombatants = tokens.filter((entry) => entry.character?.ownerUserId === state.profile.id);

  function updateCombatant(combatant: Combatant, patch: Partial<Combatant>) {
    dispatch({ type: 'battle/update', combatantId: combatant.id, patch });
  }

  if (!state.battle) {
    return (
      <div className="space-y-4">
        <Card>
          <p className="eyebrow mb-2">Battlefield</p>
          <h2 className="text-2xl font-black tracking-tight">The field is quiet.</h2>
        </Card>

        {isDm && (
          <Card>
            <div className="mb-4 flex items-center justify-between gap-3">
              <div><h3 className="font-black">Assemble the party</h3><p className="text-xs text-[var(--muted)]">{selectedIds.length} selected</p></div>
              <Button variant="primary" disabled={selectedIds.length === 0} onClick={() => dispatch({ type: 'battle/start', characterIds: selectedIds })}><Swords className="mr-2 inline" size={17} /> Begin encounter</Button>
            </div>
            <div className="grid gap-2 sm:grid-cols-2">
              {state.characters.filter((entry) => entry.kind === 'player').map((character) => {
                const chosen = selectedIds.includes(character.id);
                return (
                  <button key={character.id} onClick={() => setSelectedIds((current) => chosen ? current.filter((id) => id !== character.id) : [...current, character.id])} className={`flex items-center gap-3 rounded-xl border p-3 text-left transition ${chosen ? 'border-[var(--brass)] bg-[#d1a85b0e]' : 'border-[var(--line)] bg-black/10'}`}>
                    <span className="grid h-10 w-10 place-items-center rounded-full border border-white/20 font-black" style={{ backgroundColor: character.tokenColor }}>{character.name[0]}</span>
                    <span className="min-w-0 flex-1"><span className="block truncate font-black">{character.name}</span><span className="block truncate text-xs text-[var(--muted)]">Level {character.level} {character.className}</span></span>
                    <span className={`h-5 w-5 rounded-md border ${chosen ? 'border-[var(--brass)] bg-[var(--brass)]' : 'border-[var(--muted)]'}`} />
                  </button>
                );
              })}
            </div>
          </Card>
        )}
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-4">
      <BattleMap
        battle={state.battle}
        tokens={tokens}
        profile={state.profile}
        selectedId={selectedCombatantId}
        onSelect={(id) => setSelectedCombatantId((current) => current === id ? null : id)}
        onMove={(id, x, y) => {
          dispatch({ type: 'battle/move', combatantId: id, x, y });
          setSelectedCombatantId(null);
        }}
      />

      <Card>
        <div className="mb-3 flex items-center justify-between gap-3">
          <h3 className="font-black">Encounter Roster</h3>
          {isDm && <Button variant="danger" onClick={() => dispatch({ type: 'battle/end' })}><XCircle className="mr-2 inline" size={16} /> End encounter</Button>}
        </div>
        <div className="grid gap-2 sm:grid-cols-2">
          {tokens.map((entry) => {
            const character = entry.character;
            return (
              <article key={entry.id} className={`rounded-xl border p-3 transition ${selectedCombatantId === entry.id ? 'border-[var(--brass)] bg-[#d1a85b0b]' : 'border-[var(--line)] bg-black/10'}`}>
                <button type="button" onClick={() => setSelectedCombatantId((current) => current === entry.id ? null : entry.id)} className="w-full text-left">
                  <div className="mb-2 flex items-center justify-between gap-2">
                    <span className="min-w-0 flex items-center gap-2">
                      <span className="truncate font-black">{character?.name ?? 'Unknown'}</span>
                      <span className="shrink-0 rounded-md border border-[var(--line)] bg-black/25 px-2 py-1 text-[10px] font-black uppercase tracking-wide text-[var(--muted)]">{character?.className ?? 'Adventurer'}</span>
                    </span>
                    <span className="rounded-md bg-black/30 px-2 py-1 text-[10px] font-black text-[var(--brass)]">INIT {entry.initiative ?? '—'}</span>
                  </div>
                  <div className="grid grid-cols-2 gap-3">
                    <ResourceBar label="HP" tone="hp" current={entry.currentHp} max={character?.maxHp ?? 1} />
                    <ResourceBar label="Mana" tone="mana" current={entry.currentMana} max={character?.maxMana ?? 1} />
                  </div>
                </button>
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
            <InventoryPanel key={entry.id} character={{ ...entry.character, currentHp: entry.currentHp, currentMana: entry.currentMana }} canManage canAdd={false} />
          ))}
        </div>
      )}
    </div>
  );
}
