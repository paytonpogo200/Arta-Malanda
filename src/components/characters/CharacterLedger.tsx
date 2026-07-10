'use client';

import { useMemo, useState, type FormEvent } from 'react';
import { Plus, UserRound } from 'lucide-react';
import { Button } from '@/components/ui/Button';
import { Card, SoftCard } from '@/components/ui/Card';
import { SelectField, TextAreaField, TextField } from '@/components/ui/Field';
import { CharacterSheet } from '@/components/characters/CharacterSheet';
import { useCampaignDispatch, useCampaignState } from '@/features/campaign/CampaignProvider';

export function CharacterLedger() {
  const state = useCampaignState();
  const dispatch = useCampaignDispatch();
  const [selectedId, setSelectedId] = useState(state.characters[0]?.id ?? '');
  const [creating, setCreating] = useState(false);
  const [draft, setDraft] = useState({ name: '', classKey: state.classes[0]?.key ?? '', personalPassives: '' });

  const orderedCharacters = useMemo(() => {
    return [...state.characters].sort((a, b) => {
      const aMine = a.ownerUserId === state.profile.id ? 0 : 1;
      const bMine = b.ownerUserId === state.profile.id ? 0 : 1;
      return aMine - bMine || a.name.localeCompare(b.name);
    });
  }, [state.characters, state.profile.id]);

  const selectedCharacter = state.characters.find((entry) => entry.id === selectedId) ?? orderedCharacters[0] ?? null;

  function createCharacter(event: FormEvent) {
    event.preventDefault();
    dispatch({ type: 'character/create', classKey: draft.classKey, name: draft.name, personalPassives: draft.personalPassives });
    setDraft({ name: '', classKey: state.classes[0]?.key ?? '', personalPassives: '' });
    setCreating(false);
  }

  return (
    <div className="grid gap-4 lg:grid-cols-[20rem_1fr]">
      <aside className="space-y-4 lg:sticky lg:top-24 lg:self-start">
        <Card>
          <div className="mb-4 flex items-center justify-between gap-3">
            <div>
              <p className="eyebrow">Character Ledger</p>
              <h2 className="mt-1 text-2xl font-black">Party roster</h2>
            </div>
            {state.profile.role === 'dm' && (
              <Button variant="primary" className="p-3" onClick={() => setCreating((value) => !value)} aria-label="Create character">
                <Plus size={17} />
              </Button>
            )}
          </div>

          {creating && (
            <form onSubmit={createCharacter} className="mb-4 grid gap-2 rounded-2xl border border-[var(--line)] bg-black/15 p-3">
              <TextField autoFocus placeholder="Character name" value={draft.name} onChange={(event) => setDraft({ ...draft, name: event.target.value })} />
              <SelectField value={draft.classKey} onChange={(event) => setDraft({ ...draft, classKey: event.target.value })}>
                {state.classes.map((template) => <option key={template.key} value={template.key}>{template.name}</option>)}
              </SelectField>
              <TextAreaField rows={3} placeholder="Personal passives (optional)" value={draft.personalPassives} onChange={(event) => setDraft({ ...draft, personalPassives: event.target.value })} />
              <Button variant="teal" disabled={!draft.name.trim()}>Create</Button>
            </form>
          )}

          <div className="thin-scrollbar grid max-h-[62vh] gap-2 overflow-y-auto pr-1">
            {orderedCharacters.map((character) => {
              const mine = character.ownerUserId === state.profile.id;
              const selected = selectedCharacter?.id === character.id;
              return (
                <button
                  key={character.id}
                  onClick={() => setSelectedId(character.id)}
                  className={`rounded-xl border p-3 text-left transition ${selected ? 'border-[var(--brass)] bg-[#d1a85b12]' : 'border-[var(--line)] bg-black/10'}`}
                >
                  <span className="flex items-center gap-3">
                    <span className="grid h-11 w-11 shrink-0 place-items-center rounded-full border border-white/20" style={{ backgroundColor: character.tokenColor }}>
                      <UserRound size={19} />
                    </span>
                    <span className="min-w-0 flex-1">
                      <span className="block truncate font-black">{character.name}</span>
                      <span className="block truncate text-xs text-[var(--muted)]">{mine ? 'Your character' : 'Other character'} · {character.className}</span>
                      <span className="mt-1 block text-[10px] font-black uppercase tracking-wide text-[var(--brass)]">{character.locationName}</span>
                    </span>
                  </span>
                </button>
              );
            })}
          </div>
        </Card>

        <SoftCard>
          <p className="text-xs leading-5 text-[var(--muted)]">
            This rebuild keeps the ledger light: the list stays mounted, but each sheet opens only the selected character’s systems.
          </p>
        </SoftCard>
      </aside>

      {selectedCharacter ? <CharacterSheet character={selectedCharacter} /> : <Card>No characters yet.</Card>}
    </div>
  );
}
