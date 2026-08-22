'use client';

import { memo, useEffect, useMemo, useRef, useState, type FormEvent } from 'react';
import { Heart, Loader2, MapPin, Save, Shield, Sparkles, Trash2, UserRound, WandSparkles } from 'lucide-react';
import { characterLevelFrameClass, LevelBadge } from '@/components/characters/LevelBadge';
import { Button } from '@/components/ui/Button';
import { Card, SoftCard } from '@/components/ui/Card';
import { HousePanel } from '@/components/houses/HousePanel';
import { InventoryPanel } from '@/components/inventory/InventoryPanel';
import { JurshConversionPanel } from '@/components/inventory/JurshConversionPanel';
import { SpellsPanel } from '@/components/spells/SpellsPanel';
import { ColorField, SelectField, TextAreaField, TextField } from '@/components/ui/Field';
import { NumberInput } from '@/components/ui/NumberInput';
import { ResourceBar } from '@/components/ui/ResourceBar';
import type { CampaignProfile } from '@/features/characters/data';
import { activeAttributeValue, calculateCharacterSheetStats } from '@/features/characters/stats';
import { ATTRIBUTE_KEYS, ATTRIBUTE_LABELS, type Character, type ClassTemplate, type InventoryItem, type Profile } from '@/lib/types';
import { signed } from '@/lib/utils/format';

type CharacterSheetProps = {
  character: Character;
  profile: Profile;
  profiles: CampaignProfile[];
  classes: ClassTemplate[];
  characters: Character[];
  locationOptions: string[];
  onSaved: (character: Character) => void;
  onDeleted?: (characterId: string) => void;
};

function characterLocationOptions(cityNames: string[]) {
  const seen = new Set<string>();
  return [...cityNames, 'Wild']
    .map((name) => name.trim())
    .filter((name) => {
      const key = name.toLowerCase();
      if (!name || seen.has(key)) return false;
      seen.add(key);
      return true;
    });
}

function labelClasses(value: number) {
  if (value > 0) return 'text-[var(--teal)]';
  if (value < 0) return 'text-[var(--red)]';
  return 'text-[var(--paper)]';
}

function ownerLabel(profile: CampaignProfile | undefined) {
  if (!profile) return 'Unassigned';
  return profile.displayName || profile.username || 'Player';
}

function isJurshBlacksmith(character: Character, profiles: CampaignProfile[]) {
  const owner = profiles.find((entry) => entry.id === character.ownerUserId);
  const ownerName = `${owner?.username ?? ''} ${owner?.displayName ?? ''}`.toLowerCase();
  return character.name.trim().toLowerCase() === 'jursh'
    && (character.classKey.trim().toLowerCase() === 'blacksmith' || character.className.trim().toLowerCase() === 'blacksmith')
    && ownerName.includes('eoshigande');
}

export const CharacterSheet = memo(function CharacterSheet({ character, profile, profiles, classes, characters, locationOptions, onSaved, onDeleted }: CharacterSheetProps) {
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState(character);
  const [inventoryItems, setInventoryItems] = useState<InventoryItem[]>([]);
  const [inventoryRefreshSignal, setInventoryRefreshSignal] = useState(0);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const characterIdRef = useRef(character.id);

  const isDm = profile.role === 'dm';
  const owned = character.ownerUserId === profile.id;
  const classTemplate = useMemo(() => classes.find((entry) => entry.key === character.classKey), [character.classKey, classes]);
  const showJurshConversions = isJurshBlacksmith(character, profiles) && (isDm || owned);
  const availableLocations = useMemo(() => characterLocationOptions(locationOptions), [locationOptions]);
  const draftLocation = availableLocations.includes(draft.locationName) ? draft.locationName : 'Wild';

  useEffect(() => {
    if (characterIdRef.current !== character.id) {
      characterIdRef.current = character.id;
      setDraft(character);
      setInventoryItems([]);
      setEditing(false);
      setError('');
      return;
    }

    if (!editing) {
      setDraft(character);
      setError('');
    }
  }, [character, editing]);

  const attributeRows = useMemo(() => ATTRIBUTE_KEYS.map((key) => ({
    key,
    label: ATTRIBUTE_LABELS[key],
    value: activeAttributeValue(character, inventoryItems, key)
  })), [character, inventoryItems]);

  const sheetStats = useMemo(() => calculateCharacterSheetStats(character, inventoryItems, classTemplate), [character, classTemplate, inventoryItems]);

  async function save(event: FormEvent) {
    event.preventDefault();
    if (!isDm || saving) return;
    setSaving(true);
    setError('');

    try {
      const response = await fetch(`/api/characters/${character.id}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          name: draft.name,
          level: draft.level,
          maxHp: draft.maxHp,
          currentHp: draft.currentHp,
          maxMana: draft.maxMana,
          currentMana: draft.currentMana,
          magicResist: draft.magicResist,
          inventorySlots: draft.inventorySlots,
          spellSlots: draft.spellSlots,
          attributes: draft.attributes,
          personalPassives: draft.personalPassives,
          tokenColor: draft.tokenColor,
          locationName: draftLocation,
          ownerUserId: draft.ownerUserId,
          classKey: draft.classKey,
          className: draft.className,
          classPassives: draft.classPassives
        })
      });
      const payload = await response.json().catch(() => ({}));

      if (!response.ok) {
        throw new Error(payload.error ?? 'The character could not be saved.');
      }

      onSaved(payload.character as Character);
      setEditing(false);
    } catch (saveError) {
      setError(saveError instanceof Error ? saveError.message : 'The character could not be saved.');
    } finally {
      setSaving(false);
    }
  }

  async function deleteCharacter() {
    if (!isDm || saving) return;
    const confirmed = window.confirm(`Delete ${character.name}? This removes the character sheet, inventory, spells, wallet, and battle token.`);
    if (!confirmed) return;

    setSaving(true);
    setError('');
    try {
      const response = await fetch(`/api/characters/${character.id}`, { method: 'DELETE' });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.error ?? 'The character could not be deleted.');
      onDeleted?.(character.id);
    } catch (deleteError) {
      setError(deleteError instanceof Error ? deleteError.message : 'The character could not be deleted.');
    } finally {
      setSaving(false);
    }
  }

  function applyClassTemplate(classKey: string) {
    const template = classes.find((entry) => entry.key === classKey);
    if (!template) {
      setDraft({ ...draft, classKey });
      return;
    }

    setDraft({
      ...draft,
      classKey: template.key,
      className: template.name,
      maxHp: template.baseHp,
      currentHp: template.baseHp,
      maxMana: template.baseMana,
      currentMana: template.baseMana,
      magicResist: template.baseMagicResist,
      inventorySlots: template.inventorySlots,
      spellSlots: template.spellSlots,
      attributes: template.attributes,
      classPassives: template.passives,
      tokenColor: template.tokenColor
    });
  }

  return (
    <div className="space-y-4">
      <Card className={characterLevelFrameClass(character.level, editing ? 'sheet-edit' : 'sheet')}>
        <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
          <div className="flex items-start gap-3">
            <div className="grid h-14 w-14 shrink-0 place-items-center rounded-full border border-white/20" style={{ background: character.tokenColor }}>
              <UserRound size={24} />
            </div>
            <div>
              <p className="eyebrow">{owned ? 'Controlled character' : 'Campaign character'}</p>
              <div className="mt-1 flex flex-wrap items-center gap-2">
                <h2 className="text-3xl font-black tracking-tight">{character.name}</h2>
                <LevelBadge level={character.level} />
              </div>
              <p className="mt-1 text-sm text-[var(--muted)]">{character.className}</p>
              <p className="mt-2 flex items-center gap-2 text-xs font-black uppercase tracking-wide text-[var(--brass)]"><MapPin size={13} /> {character.locationName}</p>
              {!character.ownerUserId && character.previousOwnerName && (
                <p className="mt-2 rounded-full border border-[var(--line)] bg-black/15 px-3 py-1 text-xs font-black text-[var(--muted)]">
                  Unclaimed · formerly {character.previousOwnerName}
                </p>
              )}
            </div>
          </div>
          <div className="flex flex-wrap gap-2">
            {isDm && (editing ? (
              <>
                <Button variant="secondary" type="button" disabled={saving} onClick={() => { setDraft(character); setEditing(false); }}>Cancel</Button>
                <Button variant="primary" form="character-edit-form" type="submit" disabled={saving}>
                  <span className="flex items-center gap-2">{saving ? <Loader2 size={16} className="animate-spin" /> : <Save size={16} />} Save sheet</span>
                </Button>
              </>
            ) : (
              <>
                <Button variant="secondary" type="button" onClick={() => setEditing(true)}>Edit sheet</Button>
                <Button variant="danger" type="button" disabled={saving} onClick={deleteCharacter}>
                  <Trash2 className="mr-2 inline" size={15} />
                  Delete
                </Button>
              </>
            ))}
          </div>
        </div>

        {error && <div className="mt-4 rounded-2xl border border-[var(--red)]/40 bg-[var(--red)]/10 p-3 text-sm text-[var(--red)]">{error}</div>}

        {editing ? (
          <form id="character-edit-form" onSubmit={save} className="mt-5 grid gap-3">
            <div className="grid gap-2 sm:grid-cols-[1fr_9rem]">
              <TextField value={draft.name} onChange={(event) => setDraft({ ...draft, name: event.target.value })} />
              <NumberInput aria-label="Level" value={draft.level} min={1} onValueChange={(level) => setDraft({ ...draft, level })} />
            </div>
            <div className="grid gap-2 sm:grid-cols-3">
              <label>
                <span className="mb-1 block text-[10px] font-black uppercase text-[var(--muted)]">Assigned player</span>
                <SelectField value={draft.ownerUserId ?? ''} onChange={(event) => setDraft({ ...draft, ownerUserId: event.target.value || null })}>
                  <option value="">Unassigned</option>
                  {profiles.map((entry) => <option key={entry.id} value={entry.id}>{ownerLabel(entry)}</option>)}
                </SelectField>
              </label>
              <label>
                <span className="mb-1 block text-[10px] font-black uppercase text-[var(--muted)]">Class</span>
                <SelectField value={draft.classKey} onChange={(event) => applyClassTemplate(event.target.value)}>
                  {classes.map((template) => <option key={template.key} value={template.key}>{template.name}</option>)}
                </SelectField>
              </label>
              <label>
                <span className="mb-1 block text-[10px] font-black uppercase text-[var(--muted)]">Location</span>
                <SelectField value={draftLocation} onChange={(event) => setDraft({ ...draft, locationName: event.target.value })}>
                  {availableLocations.map((location) => <option key={location} value={location}>{location}</option>)}
                </SelectField>
              </label>
            </div>
            <div className="grid gap-2 sm:grid-cols-5">
              <label><span className="mb-1 block text-[10px] font-black uppercase text-[var(--red)]">Current HP</span><NumberInput value={draft.currentHp} min={0} onValueChange={(currentHp) => setDraft({ ...draft, currentHp })} /></label>
              <label><span className="mb-1 block text-[10px] font-black uppercase text-[var(--red)]">Max HP</span><NumberInput value={draft.maxHp} min={0} onValueChange={(maxHp) => setDraft({ ...draft, maxHp })} /></label>
              <label><span className="mb-1 block text-[10px] font-black uppercase text-[var(--blue)]">Current Mana</span><NumberInput value={draft.currentMana} min={0} onValueChange={(currentMana) => setDraft({ ...draft, currentMana })} /></label>
              <label><span className="mb-1 block text-[10px] font-black uppercase text-[var(--blue)]">Max Mana</span><NumberInput value={draft.maxMana} min={0} onValueChange={(maxMana) => setDraft({ ...draft, maxMana })} /></label>
              <label><span className="mb-1 block text-[10px] font-black uppercase text-[var(--teal)]">Magic Resist</span><NumberInput value={draft.magicResist} min={0} onValueChange={(magicResist) => setDraft({ ...draft, magicResist })} /></label>
            </div>
            <div className="grid gap-2 sm:grid-cols-3">
              <label><span className="mb-1 block text-[10px] font-black uppercase text-[var(--muted)]">Inventory slots</span><NumberInput value={draft.inventorySlots} min={0} onValueChange={(inventorySlots) => setDraft({ ...draft, inventorySlots })} /></label>
              <label><span className="mb-1 block text-[10px] font-black uppercase text-[var(--muted)]">Spell slots</span><NumberInput value={draft.spellSlots} min={0} onValueChange={(spellSlots) => setDraft({ ...draft, spellSlots })} /></label>
              <label><span className="mb-1 block text-[10px] font-black uppercase text-[var(--muted)]">Class color</span><ColorField aria-label="Token color" value={draft.tokenColor} onChange={(event) => setDraft({ ...draft, tokenColor: event.target.value })} /></label>
            </div>
            <Card className="p-3">
              <div className="rule-title mb-3"><h3 className="text-sm font-black uppercase tracking-wider">Attributes & Skills</h3></div>
              <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
                {ATTRIBUTE_KEYS.map((key) => (
                  <label key={key}>
                    <span className="mb-1 block text-[10px] font-black uppercase text-[var(--muted)]">{ATTRIBUTE_LABELS[key]}</span>
                    <NumberInput value={draft.attributes[key] ?? 0} onValueChange={(value) => setDraft({ ...draft, attributes: { ...draft.attributes, [key]: value } })} />
                  </label>
                ))}
              </div>
            </Card>
            <TextAreaField rows={3} value={draft.personalPassives} onChange={(event) => setDraft({ ...draft, personalPassives: event.target.value })} placeholder="Personal passives" />
          </form>
        ) : (
          <div className="mt-5 grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
            <SoftCard>
              <div className="flex items-center gap-2 text-xs font-black uppercase tracking-wider text-[var(--red)]"><Heart size={14} /> Health</div>
              <p className="mt-2 text-2xl font-black">{Math.min(character.currentHp, sheetStats.maxHp)}<span className="text-sm text-[var(--muted)]"> / {sheetStats.maxHp}</span></p>
            </SoftCard>
            <SoftCard>
              <div className="flex items-center gap-2 text-xs font-black uppercase tracking-wider text-[var(--blue)]"><Sparkles size={14} /> Mana</div>
              <p className="mt-2 text-2xl font-black">{Math.min(character.currentMana, sheetStats.maxMana)}<span className="text-sm text-[var(--muted)]"> / {sheetStats.maxMana}</span></p>
            </SoftCard>
            <SoftCard>
              <div className="flex items-center gap-2 text-xs font-black uppercase tracking-wider text-[var(--brass)]"><Shield size={14} /> Defense</div>
              <p className="mt-2 text-2xl font-black">{sheetStats.defense}</p>
            </SoftCard>
            <SoftCard>
              <div className="flex items-center gap-2 text-xs font-black uppercase tracking-wider text-[var(--teal)]"><WandSparkles size={14} /> Magic Resist</div>
              <p className="mt-2 text-2xl font-black">{sheetStats.magicResist}</p>
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
                  <p className={`mt-1 text-lg font-black ${labelClasses(entry.value)}`}>{signed(entry.value)}</p>
                </div>
              ))}
            </div>
          </Card>

          <SpellsPanel
            character={character}
            canManage={isDm || owned}
            canGrant={isDm}
            enchantedItems={inventoryItems}
            onManaChanged={(currentMana) => onSaved({ ...character, currentMana })}
          />
          <InventoryPanel
            character={character}
            canManage={isDm || owned}
            canAdd={isDm}
            refreshSignal={inventoryRefreshSignal}
            tradeCharacters={characters}
            profiles={profiles}
            viewerUserId={profile.id}
            onItemsChanged={setInventoryItems}
            onResourceChanged={(patch) => onSaved({ ...character, ...patch })}
            spellBookTargets={characters}
            onSpellBookUsed={(result) => {
              if (result.characterId === character.id) onSaved({ ...character, currentMana: result.currentMana });
              if (result.targetCharacterId === character.id) onSaved({ ...character, currentHp: result.targetCurrentHp, currentMana: result.targetCurrentMana });
            }}
          />
          {showJurshConversions && (
            <JurshConversionPanel
              characterId={character.id}
              onConverted={() => setInventoryRefreshSignal((value) => value + 1)}
            />
          )}
          <HousePanel
            ownerUserId={character.ownerUserId}
            caretakerCharacterId={character.id}
            viewerUserId={profile.id}
            profiles={profiles}
            characters={characters}
            canManage={isDm || owned}
            canAdd={isDm}
            onCharacterInventoryChanged={() => setInventoryRefreshSignal((value) => value + 1)}
          />
        </div>

        <div className="space-y-4">
          <Card>
            <div className="rule-title mb-3"><h3 className="text-sm font-black uppercase tracking-wider">Class</h3></div>
            <div className="grid gap-2 text-sm text-[var(--muted)]">
              <div className="grid grid-cols-2 gap-2">
                <div className="rounded-xl border border-[var(--line)] bg-black/15 p-3">
                  <p className="text-[10px] font-black uppercase tracking-wide text-[var(--muted)]">Role</p>
                  <p className="mt-1 font-black text-[var(--paper)]">{classTemplate?.role || character.className}</p>
                </div>
                <div className="rounded-xl border border-[var(--line)] bg-black/15 p-3">
                  <p className="text-[10px] font-black uppercase tracking-wide text-[var(--muted)]">Armor</p>
                  <p className="mt-1 font-black text-[var(--paper)]">{classTemplate?.armor || '—'}</p>
                </div>
              </div>
            </div>
          </Card>

          <Card>
            <div className="rule-title mb-3"><h3 className="text-sm font-black uppercase tracking-wider">Passives</h3></div>
            <div className="space-y-3">
              <div>
                <p className="mb-2 text-[10px] font-black uppercase tracking-wider text-[var(--brass)]">Class passives</p>
                <ul className="space-y-2 text-sm leading-6 text-[var(--muted)]">
                  {character.classPassives.map((passive) => <li key={passive} className="rounded-xl bg-black/15 p-3">{passive}</li>)}
                  {!character.classPassives.length && <li className="rounded-xl bg-black/15 p-3">None</li>}
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
              <ResourceBar label="Health" tone="hp" current={Math.min(character.currentHp, sheetStats.maxHp)} max={sheetStats.maxHp} />
              <ResourceBar label="Mana" tone="mana" current={Math.min(character.currentMana, sheetStats.maxMana)} max={sheetStats.maxMana} />
              <div className="grid grid-cols-2 gap-2">
                <div className="rounded-xl border border-[var(--line)] bg-black/15 p-3">
                  <p className="text-[10px] font-black uppercase tracking-wide text-[var(--muted)]">Defense</p>
                  <p className="mt-1 text-lg font-black text-[var(--paper)]">{sheetStats.defense}</p>
                </div>
                <div className="rounded-xl border border-[var(--line)] bg-black/15 p-3">
                  <p className="text-[10px] font-black uppercase tracking-wide text-[var(--muted)]">Magic Resist</p>
                  <p className="mt-1 text-lg font-black text-[var(--paper)]">{sheetStats.magicResist}</p>
                </div>
              </div>
            </div>
          </Card>
        </div>
      </div>
    </div>
  );
});
