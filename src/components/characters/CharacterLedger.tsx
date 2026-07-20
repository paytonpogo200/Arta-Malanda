'use client';

import { useCallback, useEffect, useMemo, useState, type FormEvent } from 'react';
import { ArrowLeft, Loader2, Plus, RefreshCw, UserRound } from 'lucide-react';
import { CharacterSheet } from '@/components/characters/CharacterSheet';
import { TradeModal } from '@/components/trades/TradeModal';
import { Button } from '@/components/ui/Button';
import { Card } from '@/components/ui/Card';
import { SelectField, TextAreaField, TextField } from '@/components/ui/Field';
import { normalizeLedgerPayload, type CampaignProfile } from '@/features/characters/data';
import { CLASS_TEMPLATES } from '@/lib/constants/classes';
import type { Character, ClassTemplate, Profile } from '@/lib/types';

type CreationDraft = {
  name: string;
  classKey: string;
  ownerUserId: string;
  personalPassives: string;
  tokenColor: string;
};

const EMPTY_DRAFT: CreationDraft = {
  name: '',
  classKey: CLASS_TEMPLATES[0]?.key ?? '',
  ownerUserId: '',
  personalPassives: '',
  tokenColor: CLASS_TEMPLATES[0]?.tokenColor ?? '#9caf79'
};

function ownerLabel(profile: CampaignProfile | undefined) {
  if (!profile) return 'Unassigned';
  return profile.displayName || profile.username || 'Player';
}

export function CharacterLedger({ profile }: { profile: Profile }) {
  const [profiles, setProfiles] = useState<CampaignProfile[]>([]);
  const [classes, setClasses] = useState<ClassTemplate[]>(CLASS_TEMPLATES);
  const [characters, setCharacters] = useState<Character[]>([]);
  const [selectedId, setSelectedId] = useState('');
  const [creating, setCreating] = useState(false);
  const [draft, setDraft] = useState<CreationDraft>(EMPTY_DRAFT);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [tradeTarget, setTradeTarget] = useState<Character | null>(null);

  const isDm = profile.role === 'dm';

  const loadLedger = useCallback(async () => {
    setLoading(true);
    setError('');

    try {
      const response = await fetch('/api/characters/ledger', { cache: 'no-store' });
      const payload = await response.json().catch(() => ({}));

      if (!response.ok) {
        throw new Error(payload.error ?? 'The character ledger could not be loaded.');
      }

      const ledger = normalizeLedgerPayload(payload);
      setProfiles(ledger.profiles);
      setClasses(ledger.classes.length ? ledger.classes : CLASS_TEMPLATES);
      setCharacters(ledger.characters);
      setSelectedId((current) => ledger.characters.some((character) => character.id === current) ? current : '');
      setDraft((current) => ({
        ...current,
        classKey: current.classKey || ledger.classes[0]?.key || CLASS_TEMPLATES[0]?.key || '',
        ownerUserId: current.ownerUserId || ledger.profiles[0]?.id || profile.id
      }));
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : 'The character ledger could not be loaded.');
    } finally {
      setLoading(false);
    }
  }, [profile.id]);

  useEffect(() => {
    void loadLedger();
  }, [loadLedger]);

  const profileById = useMemo(() => new Map(profiles.map((entry) => [entry.id, entry])), [profiles]);
  const selectedClass = useMemo(() => classes.find((entry) => entry.key === draft.classKey) ?? classes[0], [classes, draft.classKey]);

  const orderedCharacters = useMemo(() => {
    return [...characters].sort((a, b) => {
      const aMine = a.ownerUserId === profile.id ? 0 : 1;
      const bMine = b.ownerUserId === profile.id ? 0 : 1;
      return aMine - bMine || a.name.localeCompare(b.name);
    });
  }, [characters, profile.id]);

  const selectedCharacter = characters.find((entry) => entry.id === selectedId) ?? null;
  const canOfferTrades = useMemo(() => characters.some((character) => character.ownerUserId === profile.id), [characters, profile.id]);

  async function createCharacter(event: FormEvent) {
    event.preventDefault();
    if (!isDm || saving) return;
    setSaving(true);
    setError('');

    try {
      const response = await fetch('/api/characters', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(draft)
      });
      const payload = await response.json().catch(() => ({}));

      if (!response.ok) {
        throw new Error(payload.error ?? 'The character could not be created.');
      }

      const character = payload.character as Character;
      setCharacters((current) => [...current, character]);
      setSelectedId(character.id);
      setDraft({
        ...EMPTY_DRAFT,
        classKey: selectedClass?.key ?? EMPTY_DRAFT.classKey,
        ownerUserId: draft.ownerUserId,
        tokenColor: selectedClass?.tokenColor ?? EMPTY_DRAFT.tokenColor
      });
      setCreating(false);
    } catch (createError) {
      setError(createError instanceof Error ? createError.message : 'The character could not be created.');
    } finally {
      setSaving(false);
    }
  }

  function updateCharacter(character: Character) {
    setCharacters((current) => current.map((entry) => entry.id === character.id ? character : entry));
    setSelectedId(character.id);
  }

  return (
    <div className="space-y-4">
      {selectedCharacter ? (
        <>
          <Card className="p-3">
            <Button variant="secondary" type="button" onClick={() => setSelectedId('')} className="w-full justify-center sm:w-auto">
              <span className="flex items-center justify-center gap-2"><ArrowLeft size={16} /> Back to character list</span>
            </Button>
          </Card>
          <CharacterSheet
            character={selectedCharacter}
            profile={profile}
            profiles={profiles}
            classes={classes}
            onSaved={updateCharacter}
            onOfferTrade={canOfferTrades ? setTradeTarget : undefined}
          />
        </>
      ) : (
        <Card>
          <div className="mb-4 flex items-center justify-between gap-3">
            <div>
              <p className="eyebrow">Character Ledger</p>
              <h2 className="mt-1 text-2xl font-black">Party roster</h2>
            </div>
            <div className="flex gap-2">
              <Button variant="secondary" className="p-3" onClick={loadLedger} aria-label="Refresh ledger">
                <RefreshCw size={17} />
              </Button>
              {isDm && (
                <Button variant="primary" className="p-3" onClick={() => setCreating((value) => !value)} aria-label="Create character">
                  <Plus size={17} />
                </Button>
              )}
            </div>
          </div>

          {creating && (
            <form onSubmit={createCharacter} className="mb-4 grid gap-2 rounded-2xl border border-[var(--line)] bg-black/15 p-3">
              <TextField autoFocus placeholder="Character name" value={draft.name} onChange={(event) => setDraft({ ...draft, name: event.target.value })} />
              <SelectField
                value={draft.classKey}
                onChange={(event) => {
                  const template = classes.find((entry) => entry.key === event.target.value);
                  setDraft({ ...draft, classKey: event.target.value, tokenColor: template?.tokenColor ?? draft.tokenColor });
                }}
              >
                {classes.map((template) => <option key={template.key} value={template.key}>{template.name}</option>)}
              </SelectField>
              <SelectField value={draft.ownerUserId} onChange={(event) => setDraft({ ...draft, ownerUserId: event.target.value })}>
                {profiles.map((entry) => <option key={entry.id} value={entry.id}>{ownerLabel(entry)}</option>)}
                {!profiles.length && <option value={profile.id}>{profile.displayName}</option>}
              </SelectField>
              <div className="grid gap-2 sm:grid-cols-[1fr_4.5rem]">
                <TextField aria-label="Token color" type="color" value={draft.tokenColor} onChange={(event) => setDraft({ ...draft, tokenColor: event.target.value })} />
                <div className="grid min-h-12 place-items-center rounded-xl border border-white/20" style={{ backgroundColor: draft.tokenColor }}>
                  <UserRound size={20} />
                </div>
              </div>
              {selectedClass && (
                <div className="rounded-2xl border border-[var(--line)] bg-black/10 p-3 text-xs text-[var(--muted)]">
                  <div className="grid grid-cols-2 gap-2">
                    <span><b className="text-[var(--paper)]">HP</b> {selectedClass.baseHp}</span>
                    <span><b className="text-[var(--paper)]">Mana</b> {selectedClass.baseMana}</span>
                    <span><b className="text-[var(--paper)]">Inventory</b> {selectedClass.inventorySlots}</span>
                    <span><b className="text-[var(--paper)]">Spells</b> {selectedClass.spellSlots}</span>
                  </div>
                </div>
              )}
              <TextAreaField rows={3} placeholder="Personal passives (optional)" value={draft.personalPassives} onChange={(event) => setDraft({ ...draft, personalPassives: event.target.value })} />
              <Button variant="teal" disabled={!draft.name.trim() || saving}>
                {saving ? <span className="flex items-center justify-center gap-2"><Loader2 size={15} className="animate-spin" /> Creating</span> : 'Create'}
              </Button>
            </form>
          )}

          {error && <div className="mb-3 rounded-2xl border border-[var(--red)]/40 bg-[var(--red)]/10 p-3 text-sm text-[var(--red)]">{error}</div>}

          {loading ? (
            <div className="grid h-40 place-items-center rounded-2xl border border-[var(--line)] bg-black/10 text-[var(--muted)]">
              <Loader2 className="animate-spin" />
            </div>
          ) : (
            <div className="grid gap-2 sm:grid-cols-2 xl:grid-cols-3">
              {orderedCharacters.map((character) => {
                const mine = character.ownerUserId === profile.id;
                const owner = character.ownerUserId
                  ? ownerLabel(profileById.get(character.ownerUserId))
                  : character.legacyOwnerName
                    ? `Unclaimed · formerly ${character.legacyOwnerName}`
                    : 'Unassigned';
                return (
                  <button
                    key={character.id}
                    onClick={() => setSelectedId(character.id)}
                    className="rounded-2xl border border-[var(--line)] bg-black/10 p-3 text-left transition hover:border-[var(--brass)] active:scale-[0.99]"
                  >
                    <span className="flex items-center gap-3">
                      <span className="grid h-11 w-11 shrink-0 place-items-center rounded-full border border-white/20" style={{ backgroundColor: character.tokenColor }}>
                        <UserRound size={19} />
                      </span>
                      <span className="min-w-0 flex-1">
                        <span className="block truncate font-black">{character.name}</span>
                        <span className="block truncate text-xs text-[var(--muted)]">{mine ? 'Your character' : owner} · {character.className}</span>
                        <span className="mt-1 block text-[10px] font-black uppercase tracking-wide text-[var(--brass)]">{character.locationName}</span>
                      </span>
                    </span>
                  </button>
                );
              })}

              {!orderedCharacters.length && (
                <div className="rounded-2xl border border-[var(--line)] bg-black/10 p-4 text-sm text-[var(--muted)]">
                  No characters yet.
                </div>
              )}
            </div>
          )}
        </Card>
      )}

      {tradeTarget && <TradeModal target={tradeTarget} characters={characters} profileId={profile.id} onClose={() => setTradeTarget(null)} />}
    </div>
  );
}
