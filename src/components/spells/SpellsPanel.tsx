'use client';

import { useCallback, useEffect, useMemo, useState, type DragEvent } from 'react';
import { BookOpen, ChevronDown, ChevronRight, Eye, Loader2, RefreshCw, Sparkles } from 'lucide-react';
import { Button } from '@/components/ui/Button';
import { Card } from '@/components/ui/Card';
import { Modal } from '@/components/ui/Modal';
import { NumberInput } from '@/components/ui/NumberInput';
import { SelectField, TextAreaField, TextField } from '@/components/ui/Field';
import { normalizeCharacterSpellsPayload, type CharacterSpellsPayload } from '@/features/spells/data';
import { spellForEnchantment } from '@/features/inventory/itemDetails';
import { useLiveRefresh } from '@/hooks/useLiveRefresh';
import { spellManaText, spellTypeClass, spellTypes } from '@/lib/utils/spells';
import type { Character, CharacterSpell, InventoryItem, Spell } from '@/lib/types';

const EMPTY_SPELLS: CharacterSpellsPayload = {
  catalog: [],
  spells: [],
  activeBattle: false
};

function SpellCard({
  entry,
  canManage,
  activeBattle,
  canActivate,
  onUse,
  onToggle,
  onInspect
}: {
  entry: CharacterSpell;
  canManage: boolean;
  activeBattle: boolean;
  canActivate: boolean;
  onUse: (entry: CharacterSpell) => void;
  onToggle: (entry: CharacterSpell, active: boolean) => void;
  onInspect: (entry: CharacterSpell) => void;
}) {
  return (
    <article
      draggable={canManage && !activeBattle}
      onDragStart={(event) => {
        if (!canManage || activeBattle) return;
        event.dataTransfer.setData('application/x-arta-spell', entry.id);
        event.dataTransfer.effectAllowed = 'move';
      }}
      className={`rounded-2xl border p-3 ${spellTypeClass(entry.spell.type)} ${entry.active ? '' : 'spell-card-inactive'} ${canManage && !activeBattle ? 'cursor-grab active:cursor-grabbing' : ''}`}
    >
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="truncate font-black">{entry.spell.name}</p>
          <p className="mt-1 text-xs font-black uppercase tracking-wide text-[var(--muted)]">{entry.spell.type}; {spellManaText(entry.spell)}</p>
        </div>
        <Sparkles size={16} className="shrink-0 text-[var(--brass)]" />
      </div>
      {entry.spell.summary && <p className="mt-2 text-sm leading-5 text-[var(--muted)]">{entry.spell.summary}</p>}
      <div className="mt-3 grid gap-2">
        <Button variant="secondary" className="px-3 py-2 text-xs" onClick={() => onInspect(entry)}>
          <Eye className="mr-2 inline" size={14} /> Inspect
        </Button>
        {canManage && (entry.active ? (
            <div className="grid grid-cols-2 gap-2">
              <Button variant="primary" className="px-3 py-2 text-xs" onClick={() => onUse(entry)}>Use spell</Button>
              <Button variant="secondary" className="px-3 py-2 text-xs" disabled={activeBattle} onClick={() => onToggle(entry, false)}>Bench</Button>
            </div>
          ) : (
            <Button variant="teal" className="px-3 py-2 text-xs" disabled={activeBattle || !canActivate} onClick={() => onToggle(entry, true)}>{canActivate ? 'Activate' : 'No open slot'}</Button>
          ))}
      </div>
    </article>
  );
}

function EnchantedSpellCard({
  item,
  spell,
  canManage,
  onUse,
  onInspect
}: {
  item: InventoryItem;
  spell: Spell;
  canManage: boolean;
  onUse: (item: InventoryItem, spell: Spell) => void;
  onInspect: (spell: Spell) => void;
}) {
  return (
    <article className={`rounded-2xl border p-3 ${spellTypeClass(spell.type)}`}>
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="truncate font-black">{spell.name}</p>
          <p className="mt-1 text-xs font-black uppercase tracking-wide text-[var(--muted)]">Weapon enchantment; {spellManaText(spell)}</p>
          <p className="mt-1 truncate text-xs font-black text-[var(--brass)]">{item.displayName || item.name}</p>
        </div>
        <Sparkles size={16} className="shrink-0 text-[var(--brass)]" />
      </div>
      {spell.summary && <p className="mt-2 text-sm leading-5 text-[var(--muted)]">{spell.summary}</p>}
      <div className="mt-3 grid gap-2">
        <Button variant="secondary" className="px-3 py-2 text-xs" onClick={() => onInspect(spell)}><Eye className="mr-2 inline" size={14} /> Inspect</Button>
        {canManage && <Button variant="primary" className="px-3 py-2 text-xs" onClick={() => onUse(item, spell)}>Use spell</Button>}
      </div>
    </article>
  );
}

function GrantSpellButton({
  spell,
  selected,
  onSelect
}: {
  spell: Spell;
  selected: boolean;
  onSelect: (spellId: string) => void;
}) {
  return (
    <button
      type="button"
      onClick={() => onSelect(spell.id)}
      className={`rounded-xl border px-3 py-2 text-left transition hover:scale-[1.01] ${spellTypeClass(spell.type)} ${selected ? 'ring-2 ring-[var(--brass)] ring-offset-2 ring-offset-[#100907]' : ''}`}
    >
      <span className="block truncate text-sm font-black leading-tight">{spell.name}</span>
      <span className="mt-1 block text-xs font-black uppercase tracking-wide text-[var(--muted)]">{spell.type}; {spellManaText(spell)}</span>
    </button>
  );
}

export function SpellsPanel({
  character,
  canManage,
  canGrant,
  combatLocked = false,
  activeOnly = false,
  enchantedItems = [],
  onManaChanged
}: {
  character: Character;
  canManage: boolean;
  canGrant: boolean;
  combatLocked?: boolean;
  activeOnly?: boolean;
  enchantedItems?: InventoryItem[];
  onManaChanged?: (currentMana: number) => void;
}) {
  const [payload, setPayload] = useState<CharacterSpellsPayload>(EMPTY_SPELLS);
  const [grantSpellId, setGrantSpellId] = useState('');
  const [grantSearch, setGrantSearch] = useState('');
  const [expandedGrantTypes, setExpandedGrantTypes] = useState<Set<string>>(() => new Set());
  const [grantModalOpen, setGrantModalOpen] = useState(false);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [inspectedOwnedSpell, setInspectedOwnedSpell] = useState<CharacterSpell | null>(null);
  const [inspectedSpell, setInspectedSpell] = useState<Spell | null>(null);
  const [editingSpell, setEditingSpell] = useState(false);
  const [spellDraft, setSpellDraft] = useState({ name: '', details: '', manaCost: 0 });

  const activeBattle = payload.activeBattle || combatLocked;
  const activeSpells = useMemo(() => payload.spells.filter((entry) => entry.active).sort((a, b) => (a.slotIndex ?? 999) - (b.slotIndex ?? 999)), [payload.spells]);
  const inactiveSpells = useMemo(() => payload.spells.filter((entry) => !entry.active).sort((a, b) => a.spell.name.localeCompare(b.spell.name)), [payload.spells]);
  const grantOptions = useMemo(() => payload.catalog, [payload.catalog]);
  const filteredGrantOptions = useMemo(() => {
    const needle = grantSearch.trim().toLowerCase();
    if (!needle) return grantOptions;
    return grantOptions.filter((spell) => `${spell.name} ${spell.type} ${spell.school} ${spellManaText(spell)}`.toLowerCase().includes(needle));
  }, [grantOptions, grantSearch]);
  const grantGroups = useMemo(() => spellTypes
    .map((type) => ({
      type,
      spells: filteredGrantOptions.filter((spell) => spell.type === type).sort((a, b) => a.name.localeCompare(b.name))
    }))
    .filter((group) => group.spells.length), [filteredGrantOptions]);
  const selectedGrantSpell = useMemo(() => grantOptions.find((spell) => spell.id === grantSpellId) ?? null, [grantOptions, grantSpellId]);
  const activeSlotCount = Math.max(0, character.spellSlots);
  const activeSlots = useMemo(() => new Map(activeSpells.filter((entry) => entry.slotIndex !== null).map((entry) => [entry.slotIndex, entry])), [activeSpells]);
  const unplacedActiveSpells = useMemo(() => activeSpells.filter((entry) => entry.slotIndex === null), [activeSpells]);
  const canActivateInactive = activeSpells.length < activeSlotCount;
  const enchantedSpells = useMemo(() => enchantedItems
    .filter((item) => item.type === 'weapon' && Boolean(item.enchantment?.trim()))
    .map((item) => ({ item, spell: spellForEnchantment(payload.catalog, item.enchantment) }))
    .filter((entry): entry is { item: InventoryItem; spell: Spell } => Boolean(entry.spell))
    .sort((a, b) => a.spell.name.localeCompare(b.spell.name) || (a.item.displayName || a.item.name).localeCompare(b.item.displayName || b.item.name)), [enchantedItems, payload.catalog]);

  const loadSpells = useCallback(async (showLoading = true) => {
    if (showLoading) setLoading(true);
    setError('');
    try {
      const response = await fetch(`/api/characters/${character.id}/spells`, { cache: 'no-store' });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(body.error ?? 'Spells could not be loaded.');
      const normalized = normalizeCharacterSpellsPayload(body);
      setPayload(normalized);
      setGrantSpellId((current) => current || normalized.catalog[0]?.id || '');
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : 'Spells could not be loaded.');
    } finally {
      if (showLoading) setLoading(false);
    }
  }, [character.id]);

  useLiveRefresh(['spells', 'characters', 'battle', 'inventory'], () => loadSpells(false));

  useEffect(() => {
    void loadSpells();
  }, [loadSpells]);

  useEffect(() => {
    if (!inspectedOwnedSpell) return;
    const freshEntry = payload.spells.find((entry) => entry.id === inspectedOwnedSpell.id);
    if (freshEntry && freshEntry !== inspectedOwnedSpell) setInspectedOwnedSpell(freshEntry);
    if (!freshEntry) setInspectedOwnedSpell(null);
  }, [inspectedOwnedSpell, payload.spells]);

  useEffect(() => {
    if (!inspectedOwnedSpell || editingSpell) return;
    setSpellDraft({
      name: inspectedOwnedSpell.spell.name,
      details: inspectedOwnedSpell.spell.details || inspectedOwnedSpell.spell.summary,
      manaCost: inspectedOwnedSpell.spell.manaCost
    });
  }, [editingSpell, inspectedOwnedSpell]);

  async function replaceFromResponse(response: Response, fallback: string) {
    const body = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(body.error ?? fallback);
    const normalized = normalizeCharacterSpellsPayload(body);
    setPayload(normalized);
    return normalized;
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
      setGrantModalOpen(false);
    } catch (grantError) {
      setError(grantError instanceof Error ? grantError.message : 'Spell could not be granted.');
    } finally {
      setSaving(false);
    }
  }

  async function patchSpell(entry: CharacterSpell, patch: { active?: boolean; slotIndex?: number }) {
    if (!canManage) return;
    setSaving(true);
    setError('');
    try {
      await replaceFromResponse(await fetch(`/api/characters/spells/${entry.id}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(patch)
      }), 'Spell could not be changed.');
    } catch (patchError) {
      setError(patchError instanceof Error ? patchError.message : 'Spell could not be changed.');
    } finally {
      setSaving(false);
    }
  }

  async function saveOwnedSpell() {
    if (!canManage || !inspectedOwnedSpell) return;
    setSaving(true);
    setError('');
    try {
      const normalized = await replaceFromResponse(await fetch(`/api/characters/spells/${inspectedOwnedSpell.id}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          name: spellDraft.name,
          summary: spellDraft.details,
          details: spellDraft.details,
          manaCost: Math.max(0, Math.round(spellDraft.manaCost))
        })
      }), 'Spell could not be saved.');
      setInspectedOwnedSpell(normalized.spells.find((entry) => entry.id === inspectedOwnedSpell.id) ?? null);
      setEditingSpell(false);
    } catch (saveError) {
      setError(saveError instanceof Error ? saveError.message : 'Spell could not be saved.');
    } finally {
      setSaving(false);
    }
  }

  function toggleSpell(entry: CharacterSpell, active: boolean) {
    void patchSpell(entry, { active });
  }

  function toggleGrantType(type: string) {
    setExpandedGrantTypes((current) => {
      const next = new Set(current);
      if (next.has(type)) next.delete(type);
      else next.add(type);
      return next;
    });
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

  async function useEnchantedSpell(item: InventoryItem, spell: Spell) {
    if (!canManage) return;
    setSaving(true);
    setError('');
    try {
      const response = await fetch(`/api/characters/${character.id}/spells/enchantment/use`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ itemId: item.id, spellId: spell.id })
      });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(body.error ?? 'Enchanted spell could not be used.');
      if (typeof body.currentMana === 'number') onManaChanged?.(body.currentMana);
    } catch (useError) {
      setError(useError instanceof Error ? useError.message : 'Enchanted spell could not be used.');
    } finally {
      setSaving(false);
    }
  }

  function dragOverSpell(event: DragEvent<HTMLElement>) {
    if (!canManage || activeBattle || !Array.from(event.dataTransfer.types).includes('application/x-arta-spell')) return;
    event.preventDefault();
    event.dataTransfer.dropEffect = 'move';
  }

  function droppedSpellId(event: DragEvent<HTMLElement>) {
    if (!canManage || activeBattle) return '';
    const id = event.dataTransfer.getData('application/x-arta-spell');
    if (id) event.preventDefault();
    return id;
  }

  function dropSpellToActive(event: DragEvent<HTMLElement>, slotIndex: number) {
    const id = droppedSpellId(event);
    if (!id) return;
    const entry = payload.spells.find((spell) => spell.id === id);
    if (!entry) return;
    if (entry.active && entry.slotIndex === slotIndex) return;
    void patchSpell(entry, { active: true, slotIndex });
  }

  function dropSpellToInactive(event: DragEvent<HTMLElement>) {
    const id = droppedSpellId(event);
    if (!id) return;
    const entry = payload.spells.find((spell) => spell.id === id);
    if (!entry || !entry.active) return;
    void patchSpell(entry, { active: false });
  }

  return (
    <Card>
      <div className="mb-4 flex items-center justify-between gap-3">
        <div>
          <p className="eyebrow">Spellwork</p>
          <h3 className="mt-1 flex items-center gap-2 text-xl font-black"><BookOpen size={18} className="text-[var(--brass)]" /> Spells</h3>
        </div>
        <div className="flex gap-2">
          {canGrant && <Button variant="teal" type="button" onClick={() => setGrantModalOpen(true)}>Add spell</Button>}
          <Button variant="secondary" type="button" className="p-3" onClick={() => void loadSpells()} aria-label="Refresh spells"><RefreshCw size={16} /></Button>
        </div>
      </div>

      {error && <div className="mb-3 rounded-2xl border border-[var(--red)]/40 bg-[var(--red)]/10 p-3 text-sm text-[var(--red)]">{error}</div>}

      {loading ? (
        <div className="grid h-28 place-items-center rounded-2xl border border-[var(--line)] bg-black/10 text-[var(--muted)]"><Loader2 className="animate-spin" /></div>
      ) : (
        <div className="space-y-4">
          <section>
            <div className="rule-title mb-3"><h3 className="text-sm font-black uppercase tracking-wider">{activeOnly ? 'Active spells' : 'Active slots'} {activeSpells.length}/{character.spellSlots}</h3></div>
            {activeOnly ? (
              <div className="grid gap-2 sm:grid-cols-2">
                {activeSpells.map((entry) => <SpellCard key={entry.id} entry={entry} canManage={canManage} activeBattle={activeBattle} canActivate={canActivateInactive} onUse={useSpell} onToggle={toggleSpell} onInspect={(spellEntry) => { setInspectedOwnedSpell(spellEntry); setInspectedSpell(null); setEditingSpell(false); }} />)}
                {enchantedSpells.map(({ item, spell }) => <EnchantedSpellCard key={`${item.id}:${spell.id}`} item={item} spell={spell} canManage={canManage} onUse={useEnchantedSpell} onInspect={(spellValue) => { setInspectedSpell(spellValue); setInspectedOwnedSpell(null); setEditingSpell(false); }} />)}
                {!activeSpells.length && !enchantedSpells.length && <div className="rounded-2xl border border-dashed border-[var(--line)] bg-black/10 p-4 text-center text-sm text-[var(--muted)]">No active spells slotted.</div>}
              </div>
            ) : (
              <div className="grid gap-2 sm:grid-cols-2">
                {Array.from({ length: Math.max(activeSlotCount, activeSpells.length) }, (_, slot) => {
                  const entry = activeSlots.get(slot) ?? unplacedActiveSpells[slot - activeSlotCount];
                  return entry ? (
                    <div key={entry.id} onDragOver={dragOverSpell} onDrop={(event) => dropSpellToActive(event, slot)}>
                      <SpellCard entry={entry} canManage={canManage} activeBattle={activeBattle} canActivate={canActivateInactive} onUse={useSpell} onToggle={toggleSpell} onInspect={(spellEntry) => { setInspectedOwnedSpell(spellEntry); setInspectedSpell(null); setEditingSpell(false); }} />
                    </div>
                  ) : (
                    <div key={slot} onDragOver={dragOverSpell} onDrop={(event) => dropSpellToActive(event, slot)} className="rounded-2xl border border-dashed border-[var(--line)] bg-black/10 p-4 text-center text-sm text-[var(--muted)]">Empty slot</div>
                  );
                })}
              </div>
            )}
          </section>

          {!activeOnly && (
            <details className="rounded-2xl border border-[var(--line)] bg-black/10">
              <summary className="cursor-pointer list-none p-3 font-black">Inactive spells; {inactiveSpells.length}</summary>
              <div onDragOver={dragOverSpell} onDrop={dropSpellToInactive} className="grid min-h-24 gap-2 border-t border-[var(--line)] p-3 sm:grid-cols-2">
                {inactiveSpells.map((entry) => <SpellCard key={entry.id} entry={entry} canManage={canManage} activeBattle={activeBattle} canActivate={canActivateInactive} onUse={useSpell} onToggle={toggleSpell} onInspect={(spellEntry) => { setInspectedOwnedSpell(spellEntry); setInspectedSpell(null); setEditingSpell(false); }} />)}
                {!inactiveSpells.length && <div className="rounded-2xl border border-dashed border-[var(--line)] bg-black/10 p-4 text-center text-sm text-[var(--muted)]">Drop spells here to bench them.</div>}
              </div>
            </details>
          )}

          {activeBattle && <p className="rounded-2xl border border-[var(--line)] bg-black/15 p-3 text-xs font-black uppercase tracking-wide text-[var(--muted)]">Spell swapping is locked during combat.</p>}
        </div>
      )}

      {canGrant && grantModalOpen && (
        <Modal title="Add spell" onClose={() => setGrantModalOpen(false)}>
          <div className="grid gap-3">
            <div className="grid gap-2 lg:grid-cols-[minmax(12rem,1fr)_minmax(12rem,1fr)]">
              <TextField value={grantSearch} onChange={(event) => setGrantSearch(event.target.value)} placeholder="Search spells by name, type, or school" />
              <SelectField value={grantSpellId} onChange={(event) => setGrantSpellId(event.target.value)}>
                <option value="">Choose spell</option>
                {filteredGrantOptions.map((spell) => <option key={spell.id} value={spell.id}>{spell.name} · {spell.type} · {spellManaText(spell)}</option>)}
              </SelectField>
            </div>
            {selectedGrantSpell && (
              <div className={`rounded-xl border px-3 py-2 text-xs ${spellTypeClass(selectedGrantSpell.type)}`}>
                <p className="font-black">{selectedGrantSpell.name} · {selectedGrantSpell.type} · {spellManaText(selectedGrantSpell)}</p>
                {selectedGrantSpell.summary && <p className="mt-1 line-clamp-2 text-[var(--muted)]">{selectedGrantSpell.summary}</p>}
              </div>
            )}
            <div className="thin-scrollbar grid max-h-[55dvh] gap-3 overflow-y-auto pr-1">
              {grantGroups.map(({ type, spells }) => {
                const expanded = expandedGrantTypes.has(type);
                return (
                  <div key={type} className="overflow-hidden rounded-2xl border border-[var(--line)] bg-black/10">
                    <button
                      type="button"
                      onClick={() => toggleGrantType(type)}
                      className={`group w-full p-4 text-left transition hover:bg-black/15 ${spellTypeClass(type)}`}
                    >
                      <span className="flex items-start justify-between gap-3">
                        <span className="min-w-0">
                          <span className="eyebrow">Spell Category</span>
                          <span className="mt-1 block text-xl font-black leading-tight">{type} Spells</span>
                          <span className="mt-1 flex flex-wrap gap-2 text-xs font-bold text-[var(--muted)]">
                            <span>{spells.length} available</span>
                            {selectedGrantSpell?.type === type && <span>selected {selectedGrantSpell.name}</span>}
                          </span>
                        </span>
                        <span className="rounded-full border border-[var(--line)] bg-black/25 p-2 text-[var(--brass)]">
                          {expanded ? <ChevronDown size={18} /> : <ChevronRight size={18} />}
                        </span>
                      </span>
                    </button>
                    {expanded && (
                      <div className="grid gap-2 border-t border-[var(--line)] p-2 sm:grid-cols-2 lg:grid-cols-3">
                        {spells.map((spell) => <GrantSpellButton key={spell.id} spell={spell} selected={spell.id === grantSpellId} onSelect={setGrantSpellId} />)}
                      </div>
                    )}
                  </div>
                );
              })}
              {!grantGroups.length && <div className="rounded-2xl border border-[var(--line)] bg-black/10 p-4 text-sm text-[var(--muted)]">No spells match that search.</div>}
            </div>
            <div className="grid grid-cols-2 gap-2">
              <Button variant="secondary" type="button" onClick={() => setGrantModalOpen(false)}>Cancel</Button>
              <Button variant="teal" type="button" disabled={!grantSpellId || saving} onClick={grantSpell}>{selectedGrantSpell ? `Grant ${selectedGrantSpell.name}` : 'Grant spell'}</Button>
            </div>
          </div>
        </Modal>
      )}

      {inspectedOwnedSpell && (
        <Modal title={inspectedOwnedSpell.spell.name} onClose={() => { setInspectedOwnedSpell(null); setEditingSpell(false); }}>
          <div className={`grid gap-3 rounded-2xl border p-4 ${spellTypeClass(inspectedOwnedSpell.spell.type)}`}>
            <div>
              <p className="eyebrow">{inspectedOwnedSpell.spell.type} Spell</p>
              <h3 className="mt-1 text-2xl font-black">{inspectedOwnedSpell.spell.name}</h3>
              <p className="mt-1 text-xs font-black uppercase tracking-wider text-[var(--muted)]">{inspectedOwnedSpell.spell.school} - {spellManaText(inspectedOwnedSpell.spell)} - {inspectedOwnedSpell.spell.rarity}</p>
            </div>
            <div className="rounded-xl border border-[var(--line)] bg-black/20 p-3 text-sm leading-6 text-[var(--paper)]">
              {inspectedOwnedSpell.spell.details || inspectedOwnedSpell.spell.summary || 'No spell description entered yet.'}
            </div>
            {canManage && !editingSpell && (
              <Button variant="teal" type="button" onClick={() => setEditingSpell(true)}>Edit owned spell</Button>
            )}
            {canManage && editingSpell && (
              <div className="grid gap-3 rounded-xl border border-[var(--line)] bg-black/20 p-3">
                <label>
                  <span className="mb-1 block text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">Personal spell name</span>
                  <TextField value={spellDraft.name} onChange={(event) => setSpellDraft({ ...spellDraft, name: event.target.value })} placeholder="Spell name" />
                </label>
                <label>
                  <span className="mb-1 block text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">Personal mana cost</span>
                  <NumberInput value={spellDraft.manaCost} min={0} onValueChange={(manaCost) => setSpellDraft({ ...spellDraft, manaCost })} />
                </label>
                <label>
                  <span className="mb-1 block text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">Personal description</span>
                  <TextAreaField rows={6} value={spellDraft.details} onChange={(event) => setSpellDraft({ ...spellDraft, details: event.target.value })} placeholder="Spell description" />
                </label>
                <div className="grid grid-cols-2 gap-2">
                  <Button variant="secondary" type="button" disabled={saving} onClick={() => setEditingSpell(false)}>Cancel</Button>
                  <Button variant="teal" type="button" disabled={saving} onClick={saveOwnedSpell}>Save spell</Button>
                </div>
              </div>
            )}
          </div>
        </Modal>
      )}

      {inspectedSpell && (
        <Modal title={inspectedSpell.name} onClose={() => setInspectedSpell(null)}>
          <div className={`grid gap-3 rounded-2xl border p-4 ${spellTypeClass(inspectedSpell.type)}`}>
            <div>
              <p className="eyebrow">{inspectedSpell.type} Spell</p>
              <h3 className="mt-1 text-2xl font-black">{inspectedSpell.name}</h3>
              <p className="mt-1 text-xs font-black uppercase tracking-wider text-[var(--muted)]">{inspectedSpell.school} - {spellManaText(inspectedSpell)} - {inspectedSpell.rarity}</p>
            </div>
            <div className="rounded-xl border border-[var(--line)] bg-black/20 p-3 text-sm leading-6 text-[var(--paper)]">
              {inspectedSpell.details || inspectedSpell.summary || 'No spell description entered yet.'}
            </div>
          </div>
        </Modal>
      )}
    </Card>
  );
}
