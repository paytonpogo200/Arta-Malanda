'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { BookOpen, Loader2, RefreshCw, Sparkles } from 'lucide-react';
import { Button } from '@/components/ui/Button';
import { Card } from '@/components/ui/Card';
import { SelectField } from '@/components/ui/Field';
import { normalizeCharacterSpellsPayload, type CharacterSpellsPayload } from '@/features/spells/data';
import { rarityClass } from '@/lib/utils/rarity';
import type { Character, CharacterSpell } from '@/lib/types';

const EMPTY_SPELLS: CharacterSpellsPayload = {
  catalog: [],
  spells: [],
  activeBattle: false
};

function SpellCard({
  entry,
  canManage,
  activeBattle,
  onUse,
  onToggle
}: {
  entry: CharacterSpell;
  canManage: boolean;
  activeBattle: boolean;
  onUse: (entry: CharacterSpell) => void;
  onToggle: (entry: CharacterSpell, active: boolean) => void;
}) {
  return (
    <article className={`rounded-2xl border p-3 ${rarityClass(entry.spell.rarity)}`}>
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="truncate font-black">{entry.spell.name}</p>
          <p className="mt-1 text-xs font-black uppercase tracking-wide text-[var(--muted)]">{entry.spell.school} · {entry.spell.manaCost} mana</p>
        </div>
        <Sparkles size={16} className="shrink-0 text-[var(--brass)]" />
      </div>
      {entry.spell.summary && <p className="mt-2 text-sm leading-5 text-[var(--muted)]">{entry.spell.summary}</p>}
      {canManage && (
        <div className="mt-3 grid grid-cols-2 gap-2">
          <Button variant="primary" className="px-3 py-2 text-xs" disabled={!entry.active} onClick={() => onUse(entry)}>Use spell</Button>
          <Button variant="secondary" className="px-3 py-2 text-xs" disabled={activeBattle} onClick={() => onToggle(entry, !entry.active)}>{entry.active ? 'Dormant' : 'Activate'}</Button>
        </div>
      )}
    </article>
  );
}

export function SpellsPanel({
  character,
  canManage,
  canGrant,
  combatLocked = false,
  onManaChanged
}: {
  character: Character;
  canManage: boolean;
  canGrant: boolean;
  combatLocked?: boolean;
  onManaChanged?: (currentMana: number) => void;
}) {
  const [payload, setPayload] = useState<CharacterSpellsPayload>(EMPTY_SPELLS);
  const [grantSpellId, setGrantSpellId] = useState('');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const activeBattle = payload.activeBattle || combatLocked;
  const activeSpells = useMemo(() => payload.spells.filter((entry) => entry.active).sort((a, b) => (a.slotIndex ?? 999) - (b.slotIndex ?? 999)), [payload.spells]);
  const dormantSpells = useMemo(() => payload.spells.filter((entry) => !entry.active).sort((a, b) => a.spell.name.localeCompare(b.spell.name)), [payload.spells]);
  const learnedIds = useMemo(() => new Set(payload.spells.map((entry) => entry.spellId)), [payload.spells]);
  const grantOptions = useMemo(() => payload.catalog.filter((spell) => !learnedIds.has(spell.id)), [learnedIds, payload.catalog]);

  const loadSpells = useCallback(async () => {
    setLoading(true);
    setError('');
    try {
      const response = await fetch(`/api/characters/${character.id}/spells`, { cache: 'no-store' });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(body.error ?? 'Spells could not be loaded.');
      const normalized = normalizeCharacterSpellsPayload(body);
      setPayload(normalized);
      setGrantSpellId((current) => current || normalized.catalog.find((spell) => !normalized.spells.some((entry) => entry.spellId === spell.id))?.id || '');
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : 'Spells could not be loaded.');
    } finally {
      setLoading(false);
    }
  }, [character.id]);

  useEffect(() => {
    void loadSpells();
  }, [loadSpells]);

  async function replaceFromResponse(response: Response, fallback: string) {
    const body = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(body.error ?? fallback);
    setPayload(normalizeCharacterSpellsPayload(body));
  }

  async function grantSpell() {
    if (!canGrant || !grantSpellId) return;
    setSaving(true);
    setError('');
    try {
      await replaceFromResponse(await fetch(`/api/characters/${character.id}/spells`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ spellId: grantSpellId })
      }), 'Spell could not be granted.');
      setGrantSpellId('');
    } catch (grantError) {
      setError(grantError instanceof Error ? grantError.message : 'Spell could not be granted.');
    } finally {
      setSaving(false);
    }
  }

  async function toggleSpell(entry: CharacterSpell, active: boolean) {
    if (!canManage) return;
    setSaving(true);
    setError('');
    try {
      await replaceFromResponse(await fetch(`/api/characters/spells/${entry.id}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ active })
      }), 'Spell could not be changed.');
    } catch (toggleError) {
      setError(toggleError instanceof Error ? toggleError.message : 'Spell could not be changed.');
    } finally {
      setSaving(false);
    }
  }

  async function useSpell(entry: CharacterSpell) {
    if (!canManage || !entry.active) return;
    setSaving(true);
    setError('');
    try {
      const response = await fetch(`/api/characters/spells/${entry.id}/use`, { method: 'POST' });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(body.error ?? 'Spell could not be used.');
      if (typeof body.currentMana === 'number') onManaChanged?.(body.currentMana);
    } catch (useError) {
      setError(useError instanceof Error ? useError.message : 'Spell could not be used.');
    } finally {
      setSaving(false);
    }
  }

  return (
    <Card>
      <div className="mb-4 flex items-center justify-between gap-3">
        <div>
          <p className="eyebrow">Spellwork</p>
          <h3 className="mt-1 flex items-center gap-2 text-xl font-black"><BookOpen size={18} className="text-[var(--brass)]" /> Spells</h3>
        </div>
        <Button variant="secondary" className="p-3" onClick={loadSpells} aria-label="Refresh spells"><RefreshCw size={16} /></Button>
      </div>

      {error && <div className="mb-3 rounded-2xl border border-[var(--red)]/40 bg-[var(--red)]/10 p-3 text-sm text-[var(--red)]">{error}</div>}

      {loading ? (
        <div className="grid h-28 place-items-center rounded-2xl border border-[var(--line)] bg-black/10 text-[var(--muted)]"><Loader2 className="animate-spin" /></div>
      ) : (
        <div className="space-y-4">
          {canGrant && (
            <div className="grid gap-2 sm:grid-cols-[1fr_auto]">
              <SelectField value={grantSpellId} onChange={(event) => setGrantSpellId(event.target.value)}>
                <option value="">Grant spell</option>
                {grantOptions.map((spell) => <option key={spell.id} value={spell.id}>{spell.name} · {spell.manaCost} mana</option>)}
              </SelectField>
              <Button variant="teal" disabled={!grantSpellId || saving} onClick={grantSpell}>Grant</Button>
            </div>
          )}

          <section>
            <div className="rule-title mb-3"><h3 className="text-sm font-black uppercase tracking-wider">Active slots {activeSpells.length}/{character.spellSlots}</h3></div>
            <div className="grid gap-2 sm:grid-cols-2">
              {Array.from({ length: Math.max(character.spellSlots, activeSpells.length) }, (_, slot) => {
                const entry = activeSpells.find((spell) => spell.slotIndex === slot) ?? activeSpells[slot];
                return entry ? (
                  <SpellCard key={entry.id} entry={entry} canManage={canManage} activeBattle={activeBattle} onUse={useSpell} onToggle={toggleSpell} />
                ) : (
                  <div key={slot} className="rounded-2xl border border-dashed border-[var(--line)] bg-black/10 p-4 text-center text-sm text-[var(--muted)]">Empty slot</div>
                );
              })}
            </div>
          </section>

          {dormantSpells.length > 0 && (
            <details className="rounded-2xl border border-[var(--line)] bg-black/10">
              <summary className="cursor-pointer list-none p-3 font-black">Dormant spells · {dormantSpells.length}</summary>
              <div className="grid gap-2 border-t border-[var(--line)] p-3 sm:grid-cols-2">
                {dormantSpells.map((entry) => <SpellCard key={entry.id} entry={entry} canManage={canManage} activeBattle={activeBattle} onUse={useSpell} onToggle={toggleSpell} />)}
              </div>
            </details>
          )}

          {activeBattle && <p className="rounded-2xl border border-[var(--line)] bg-black/15 p-3 text-xs font-black uppercase tracking-wide text-[var(--muted)]">Spell swapping is locked during combat.</p>}
        </div>
      )}
    </Card>
  );
}
