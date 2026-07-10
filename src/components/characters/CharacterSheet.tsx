'use client';

import { memo, useEffect, useMemo, useState, type FormEvent } from 'react';
import { Heart, MapPin, Save, Sparkles, UserRound } from 'lucide-react';
import { InventoryPanel } from '@/components/inventory/InventoryPanel';
import { Button } from '@/components/ui/Button';
import { Card, SoftCard } from '@/components/ui/Card';
import { TextAreaField, TextField } from '@/components/ui/Field';
import { NumberInput } from '@/components/ui/NumberInput';
import { ResourceBar } from '@/components/ui/ResourceBar';
import { ATTRIBUTE_KEYS, ATTRIBUTE_LABELS, type Character } from '@/lib/types';
import { signed } from '@/lib/utils/format';
import { useCampaignDispatch, useCampaignState } from '@/features/campaign/CampaignProvider';

export const CharacterSheet = memo(function CharacterSheet({ character }: { character: Character }) {
  const state = useCampaignState();
  const dispatch = useCampaignDispatch();
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState(character);

  const canEdit = state.profile.role === 'dm' || character.ownerUserId === state.profile.id;
  const owned = character.ownerUserId === state.profile.id;

  useEffect(() => {
    setDraft(character);
    setEditing(false);
  }, [character]);

  const attributeRows = useMemo(() => ATTRIBUTE_KEYS.map((key) => ({
    key,
    label: ATTRIBUTE_LABELS[key],
    value: character.attributes[key] ?? 0
  })), [character.attributes]);

  function save(event: FormEvent) {
    event.preventDefault();
    dispatch({ type: 'character/update', characterId: character.id, patch: draft });
    setEditing(false);
  }

  return (
    <div className="space-y-4">
      <Card>
        <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
          <div className="flex items-start gap-3">
            <div className="grid h-14 w-14 shrink-0 place-items-center rounded-full border border-white/20" style={{ backgroundColor: character.tokenColor }}>
              <UserRound size={24} />
            </div>
            <div>
              <p className="eyebrow">{owned ? 'Controlled character' : 'Campaign character'}</p>
              <h2 className="mt-1 text-3xl font-black tracking-tight">{character.name}</h2>
              <p className="mt-1 text-sm text-[var(--muted)]">Level {character.level} {character.className}</p>
              <p className="mt-2 flex items-center gap-2 text-xs font-black uppercase tracking-wide text-[var(--brass)]"><MapPin size={13} /> {character.locationName}</p>
            </div>
          </div>
          {canEdit && <Button variant={editing ? 'primary' : 'secondary'} onClick={() => editing ? undefined : setEditing(true)} form={editing ? 'character-edit-form' : undefined} type={editing ? 'submit' : 'button'}>{editing ? <span className="flex items-center gap-2"><Save size={16} /> Save sheet</span> : 'Edit sheet'}</Button>}
        </div>

        {editing ? (
          <form id="character-edit-form" onSubmit={save} className="mt-5 grid gap-3">
            <TextField value={draft.name} onChange={(event) => setDraft({ ...draft, name: event.target.value })} />
            <div className="grid gap-2 sm:grid-cols-4">
              <label><span className="mb-1 block text-[10px] font-black uppercase text-[var(--red)]">Current HP</span><NumberInput value={draft.currentHp} min={0} onValueChange={(currentHp) => setDraft({ ...draft, currentHp })} /></label>
              <label><span className="mb-1 block text-[10px] font-black uppercase text-[var(--red)]">Max HP</span><NumberInput value={draft.maxHp} min={0} onValueChange={(maxHp) => setDraft({ ...draft, maxHp })} /></label>
              <label><span className="mb-1 block text-[10px] font-black uppercase text-[var(--blue)]">Current Mana</span><NumberInput value={draft.currentMana} min={0} onValueChange={(currentMana) => setDraft({ ...draft, currentMana })} /></label>
              <label><span className="mb-1 block text-[10px] font-black uppercase text-[var(--blue)]">Max Mana</span><NumberInput value={draft.maxMana} min={0} onValueChange={(maxMana) => setDraft({ ...draft, maxMana })} /></label>
            </div>
            <TextAreaField rows={3} value={draft.personalPassives} onChange={(event) => setDraft({ ...draft, personalPassives: event.target.value })} placeholder="Personal passives" />
          </form>
        ) : (
          <div className="mt-5 grid gap-3 sm:grid-cols-2">
            <SoftCard>
              <div className="flex items-center gap-2 text-xs font-black uppercase tracking-wider text-[var(--red)]"><Heart size={14} /> Health</div>
              <p className="mt-2 text-2xl font-black">{character.currentHp}<span className="text-sm text-[var(--muted)]"> / {character.maxHp}</span></p>
            </SoftCard>
            <SoftCard>
              <div className="flex items-center gap-2 text-xs font-black uppercase tracking-wider text-[var(--blue)]"><Sparkles size={14} /> Mana</div>
              <p className="mt-2 text-2xl font-black">{character.currentMana}<span className="text-sm text-[var(--muted)]"> / {character.maxMana}</span></p>
            </SoftCard>
          </div>
        )}
      </Card>

      <div className="grid gap-4 xl:grid-cols-[1fr_20rem]">
        <div className="space-y-4">
          <Card>
            <div className="rule-title mb-3"><h3 className="text-sm font-black uppercase tracking-wider">Attributes & Skills</h3></div>
            <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
              {attributeRows.map((entry) => (
                <div key={entry.key} className="rounded-xl border border-[var(--line)] bg-black/15 p-3">
                  <p className="text-[10px] font-black uppercase tracking-wide text-[var(--muted)]">{entry.label}</p>
                  <p className={`mt-1 text-lg font-black ${entry.value > 0 ? 'text-[var(--teal)]' : entry.value < 0 ? 'text-[var(--red)]' : 'text-[var(--paper)]'}`}>{signed(entry.value)}</p>
                </div>
              ))}
            </div>
          </Card>

          <InventoryPanel character={character} canEdit={canEdit} />
        </div>

        <div className="space-y-4">
          <Card>
            <div className="rule-title mb-3"><h3 className="text-sm font-black uppercase tracking-wider">Passives</h3></div>
            <div className="space-y-3">
              <div>
                <p className="mb-2 text-[10px] font-black uppercase tracking-wider text-[var(--brass)]">Class passives</p>
                <ul className="space-y-2 text-sm leading-6 text-[var(--muted)]">
                  {character.classPassives.map((passive) => <li key={passive} className="rounded-xl bg-black/15 p-3">{passive}</li>)}
                </ul>
              </div>
              {character.personalPassives.trim() && (
                <div>
                  <p className="mb-2 text-[10px] font-black uppercase tracking-wider text-[var(--brass)]">Personal passives</p>
                  <p className="whitespace-pre-line rounded-xl bg-black/15 p-3 text-sm leading-6 text-[var(--muted)]">{character.personalPassives}</p>
                </div>
              )}
            </div>
          </Card>

          <Card>
            <div className="rule-title mb-3"><h3 className="text-sm font-black uppercase tracking-wider">Vitals</h3></div>
            <div className="grid gap-3">
              <ResourceBar label="Health" tone="hp" current={character.currentHp} max={character.maxHp} />
              <ResourceBar label="Mana" tone="mana" current={character.currentMana} max={character.maxMana} />
            </div>
          </Card>
        </div>
      </div>
    </div>
  );
});
