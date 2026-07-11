'use client';

import { memo, useEffect, useMemo, useState, type FormEvent } from 'react';
import { Heart, Loader2, MapPin, Save, Sparkles, UserRound } from 'lucide-react';
import { Button } from '@/components/ui/Button';
import { Card, SoftCard } from '@/components/ui/Card';
import { SelectField, TextAreaField, TextField } from '@/components/ui/Field';
import { NumberInput } from '@/components/ui/NumberInput';
import { ResourceBar } from '@/components/ui/ResourceBar';
import type { CampaignProfile } from '@/features/characters/data';
import { ATTRIBUTE_KEYS, ATTRIBUTE_LABELS, type Character, type ClassTemplate, type Profile } from '@/lib/types';
import { signed } from '@/lib/utils/format';

type CharacterSheetProps = {
  character: Character;
  profile: Profile;
  profiles: CampaignProfile[];
  classes: ClassTemplate[];
  onSaved: (character: Character) => void;
};

const LOCATION_PRESETS = ['Calostrynn', 'Wild Party 1', 'Wild Party 2', 'Wild Party 3'];

function labelClasses(value: number) {
  if (value > 0) return 'text-[var(--teal)]';
  if (value < 0) return 'text-[var(--red)]';
  return 'text-[var(--paper)]';
}

function ownerLabel(profile: CampaignProfile | undefined) {
  if (!profile) return 'Unassigned';
  return profile.displayName || profile.username || 'Player';
}

export const CharacterSheet = memo(function CharacterSheet({ character, profile, profiles, classes, onSaved }: CharacterSheetProps) {
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState(character);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const isDm = profile.role === 'dm';
  const owned = character.ownerUserId === profile.id;
  const classTemplate = useMemo(() => classes.find((entry) => entry.key === character.classKey), [character.classKey, classes]);

  useEffect(() => {
    setDraft(character);
    setEditing(false);
    setError('');
  }, [character]);

  const attributeRows = useMemo(() => ATTRIBUTE_KEYS.map((key) => ({
    key,
    label: ATTRIBUTE_LABELS[key],
    value: character.attributes[key] ?? 0
  })), [character.attributes]);

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
          inventorySlots: draft.inventorySlots,
          spellSlots: draft.spellSlots,
          attributes: draft.attributes,
          personalPassives: draft.personalPassives,
          tokenColor: draft.tokenColor,
          locationName: draft.locationName,
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
      inventorySlots: template.inventorySlots,
      spellSlots: template.spellSlots,
      attributes: template.attributes,
      classPassives: template.passives,
      tokenColor: template.tokenColor
    });
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
          {isDm && (
            <Button
              variant={editing ? 'primary' : 'secondary'}
              onClick={() => editing ? undefined : setEditing(true)}
              form={editing ? 'character-edit-form' : undefined}
              type={editing ? 'submit' : 'button'}
              disabled={saving}
            >
              {editing ? <span className="flex items-center gap-2">{saving ? <Loader2 size={16} className="animate-spin" /> : <Save size={16} />} Save sheet</span> : 'Edit sheet'}
            </Button>
          )}
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
                <SelectField value={LOCATION_PRESETS.includes(draft.locationName) ? draft.locationName : 'custom'} onChange={(event) => setDraft({ ...draft, locationName: event.target.value === 'custom' ? draft.locationName : event.target.value })}>
                  {LOCATION_PRESETS.map((location) => <option key={location} value={location}>{location}</option>)}
                  <option value="custom">Custom</option>
                </SelectField>
              </label>
            </div>
            {!LOCATION_PRESETS.includes(draft.locationName) && (
              <TextField value={draft.locationName} onChange={(event) => setDraft({ ...draft, locationName: event.target.value })} placeholder="Custom location" />
            )}
            <div className="grid gap-2 sm:grid-cols-4">
              <label><span className="mb-1 block text-[10px] font-black uppercase text-[var(--red)]">Current HP</span><NumberInput value={draft.currentHp} min={0} onValueChange={(currentHp) => setDraft({ ...draft, currentHp })} /></label>
              <label><span className="mb-1 block text-[10px] font-black uppercase text-[var(--red)]">Max HP</span><NumberInput value={draft.maxHp} min={0} onValueChange={(maxHp) => setDraft({ ...draft, maxHp })} /></label>
              <label><span className="mb-1 block text-[10px] font-black uppercase text-[var(--blue)]">Current Mana</span><NumberInput value={draft.currentMana} min={0} onValueChange={(currentMana) => setDraft({ ...draft, currentMana })} /></label>
              <label><span className="mb-1 block text-[10px] font-black uppercase text-[var(--blue)]">Max Mana</span><NumberInput value={draft.maxMana} min={0} onValueChange={(maxMana) => setDraft({ ...draft, maxMana })} /></label>
            </div>
            <div className="grid gap-2 sm:grid-cols-3">
              <label><span className="mb-1 block text-[10px] font-black uppercase text-[var(--muted)]">Inventory slots</span><NumberInput value={draft.inventorySlots} min={0} onValueChange={(inventorySlots) => setDraft({ ...draft, inventorySlots })} /></label>
              <label><span className="mb-1 block text-[10px] font-black uppercase text-[var(--muted)]">Spell slots</span><NumberInput value={draft.spellSlots} min={0} onValueChange={(spellSlots) => setDraft({ ...draft, spellSlots })} /></label>
              <label><span className="mb-1 block text-[10px] font-black uppercase text-[var(--muted)]">Class color</span><TextField aria-label="Token color" type="color" value={draft.tokenColor} onChange={(event) => setDraft({ ...draft, tokenColor: event.target.value })} /></label>
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
                  <p className={`mt-1 text-lg font-black ${labelClasses(entry.value)}`}>{signed(entry.value)}</p>
                </div>
              ))}
            </div>
          </Card>

          <Card>
            <div className="rule-title mb-3"><h3 className="text-sm font-black uppercase tracking-wider">Capacity</h3></div>
            <div className="grid grid-cols-2 gap-2">
              <div className="rounded-xl border border-[var(--line)] bg-black/15 p-3">
                <p className="text-[10px] font-black uppercase tracking-wide text-[var(--muted)]">Inventory slots</p>
                <p className="mt-1 text-lg font-black text-[var(--paper)]">{character.inventorySlots}</p>
              </div>
              <div className="rounded-xl border border-[var(--line)] bg-black/15 p-3">
                <p className="text-[10px] font-black uppercase tracking-wide text-[var(--muted)]">Spell slots</p>
                <p className="mt-1 text-lg font-black text-[var(--paper)]">{character.spellSlots}</p>
              </div>
            </div>
          </Card>
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
              <ResourceBar label="Health" tone="hp" current={character.currentHp} max={character.maxHp} />
              <ResourceBar label="Mana" tone="mana" current={character.currentMana} max={character.maxMana} />
            </div>
          </Card>
        </div>
      </div>
    </div>
  );
});
