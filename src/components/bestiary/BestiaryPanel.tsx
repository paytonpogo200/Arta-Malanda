'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { ArrowDown, ArrowUp, ChevronDown, ChevronRight, Eye, EyeOff, Loader2, PawPrint, RefreshCw, Search, Upload } from 'lucide-react';
import { Button } from '@/components/ui/Button';
import { Card } from '@/components/ui/Card';
import { TextField } from '@/components/ui/Field';
import { categoryLabel, normalizeBestiaryPayload, type BestiaryPayload } from '@/features/bestiary/data';
import type { BestiaryCategoryRecord, BestiaryEntity, Profile } from '@/lib/types';

const EMPTY: BestiaryPayload = {
  categories: [],
  entities: [],
  unlockedCount: 0,
  totalCount: 0
};

const PRIMARY_STAT_LABELS = ['HP', 'Mana', 'Wild Score', 'Damage', 'Strength', 'Vitality', 'Magic Res', 'Armor / Hide', 'Armor', 'Str/Acc/Int', 'Strength / Accuracy / Intelligence'];

function cleanStatValue(value: string | number | undefined) {
  const text = String(value ?? '').trim();
  return text && text !== '—' ? text : '';
}

function entityStatEntries(entity: BestiaryEntity) {
  const stats = { ...entity.stats };
  if (entity.hp) stats.HP = String(entity.hp);
  if (entity.mana) stats.Mana = String(entity.mana);
  if (entity.wildScore) stats['Wild Score'] = String(entity.wildScore);
  return Object.entries(stats)
    .map(([label, value]) => [label, cleanStatValue(value)] as const)
    .filter(([, value]) => value);
}

function EntityCard({
  entity,
  categoryName,
  isDm,
  saving,
  onToggle
}: {
  entity: BestiaryEntity;
  categoryName: string;
  isDm: boolean;
  saving: boolean;
  onToggle: (entity: BestiaryEntity) => void;
}) {
  const statEntries = entityStatEntries(entity);
  const primaryStats = statEntries.filter(([label]) => PRIMARY_STAT_LABELS.includes(label));
  const secondaryStats = statEntries.filter(([label]) => !PRIMARY_STAT_LABELS.includes(label));

  return (
    <article className={`rounded-2xl border p-4 transition ${entity.unlocked ? 'border-[var(--line)] bg-black/15' : 'border-dashed border-[var(--line)] bg-black/10 opacity-75'}`}>
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="eyebrow">{categoryName}</p>
          <h3 className="mt-1 text-xl font-black leading-tight">{entity.name}</h3>
        </div>
        {isDm && (
          <Button variant={entity.unlocked ? 'teal' : 'secondary'} className="shrink-0 px-3 py-2 text-xs" disabled={saving} onClick={() => onToggle(entity)}>
            {entity.unlocked ? <Eye className="mr-1 inline" size={13} /> : <EyeOff className="mr-1 inline" size={13} />}
            {entity.unlocked ? 'Visible' : 'Hidden'}
          </Button>
        )}
      </div>

      {entity.summary && <p className="mt-3 rounded-xl border border-[var(--line)] bg-black/10 p-3 text-sm leading-6 text-[var(--muted)]">{entity.summary}</p>}

      <div className="mt-4 grid grid-cols-2 gap-2 sm:grid-cols-3">
        {primaryStats.map(([label, value]) => (
          <div key={label} className="rounded-xl border border-[var(--line)] bg-black/15 p-2 text-center">
            <p className="text-[10px] font-black uppercase text-[var(--muted)]">{label}</p>
            <p className="break-words font-black text-[var(--paper)]">{value}</p>
          </div>
        ))}
      </div>

      {!!secondaryStats.length && (
        <div className="mt-3 grid gap-2 text-xs sm:grid-cols-2">
          {secondaryStats.map(([label, value]) => (
            <p key={label} className="rounded-xl border border-[var(--line)] bg-black/10 p-2 leading-5 text-[var(--muted)]">
              <span className="font-black uppercase text-[var(--paper)]">{label}:</span> {value}
            </p>
          ))}
        </div>
      )}

      {(entity.habitat || entity.temperament) && (
        <div className="mt-3 grid gap-2 text-xs text-[var(--muted)] sm:grid-cols-2">
          {entity.habitat && <p><span className="font-black uppercase text-[var(--paper)]">Habitat:</span> {entity.habitat}</p>}
          {entity.temperament && <p><span className="font-black uppercase text-[var(--paper)]">Temper:</span> {entity.temperament}</p>}
        </div>
      )}

      {entity.details && <p className="mt-3 whitespace-pre-line rounded-xl bg-black/15 p-3 text-sm leading-6 text-[var(--muted)]">{entity.details}</p>}
    </article>
  );
}

export function BestiaryPanel({ profile }: { profile: Profile }) {
  const [payload, setPayload] = useState<BestiaryPayload>(EMPTY);
  const [query, setQuery] = useState('');
  const [expandedCategories, setExpandedCategories] = useState<Set<string>>(() => new Set());
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const fileRef = useRef<HTMLInputElement | null>(null);
  const isDm = profile.role === 'dm';

  const loadBestiary = useCallback(async () => {
    setError('');
    try {
      const response = await fetch('/api/bestiary', { cache: 'no-store' });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(body.error ?? 'Bestiary could not be loaded.');
      setPayload(normalizeBestiaryPayload(body));
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : 'Bestiary could not be loaded.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void loadBestiary();
  }, [loadBestiary]);

  const progress = payload.totalCount ? Math.round((payload.unlockedCount / payload.totalCount) * 100) : 0;

  const categoryMap = useMemo(() => {
    return new Map(payload.categories.map((entry) => [entry.key, entry]));
  }, [payload.categories]);

  const grouped = useMemo(() => {
    const needle = query.trim().toLowerCase();
    const visibleCategories = payload.categories
      .filter((entry) => isDm || !entry.hidden)
      .sort((a, b) => a.order - b.order || a.name.localeCompare(b.name));

    return visibleCategories.map((entry) => {
      const entities = payload.entities
        .filter((entity) => entity.category === entry.key)
        .filter((entity) => isDm || entity.unlocked)
        .filter((entity) => {
          if (!needle) return true;
          return `${entity.name} ${entity.summary} ${entity.details} ${entity.habitat} ${entity.temperament} ${Object.values(entity.stats).join(' ')}`.toLowerCase().includes(needle);
        })
        .sort((a, b) => a.order - b.order || a.name.localeCompare(b.name));
      return { category: entry, entities };
    }).filter((group) => isDm || group.entities.length);
  }, [isDm, payload.categories, payload.entities, query]);

  async function replaceFromResponse(response: Response, fallback: string) {
    const body = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(body.error ?? fallback);
    setPayload(normalizeBestiaryPayload(body));
  }

  function toggleCategoryOpen(categoryKey: string) {
    setExpandedCategories((current) => {
      const next = new Set(current);
      if (next.has(categoryKey)) next.delete(categoryKey);
      else next.add(categoryKey);
      return next;
    });
  }

  async function toggleEntity(entity: BestiaryEntity) {
    if (!isDm) return;
    setSaving(true);
    setError('');
    try {
      await replaceFromResponse(await fetch(`/api/bestiary/entities/${entity.id}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ unlocked: !entity.unlocked })
      }), 'Bestiary entry could not be changed.');
    } catch (toggleError) {
      setError(toggleError instanceof Error ? toggleError.message : 'Bestiary entry could not be changed.');
    } finally {
      setSaving(false);
    }
  }

  async function patchCategory(category: BestiaryCategoryRecord, patch: Partial<BestiaryCategoryRecord>, fallback = 'Bestiary category could not be changed.') {
    if (!isDm) return false;
    setSaving(true);
    setError('');
    try {
      await replaceFromResponse(await fetch(`/api/bestiary/categories/${category.key}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(patch)
      }), fallback);
      return true;
    } catch (categoryError) {
      setError(categoryError instanceof Error ? categoryError.message : fallback);
      return false;
    } finally {
      setSaving(false);
    }
  }

  async function moveCategory(category: BestiaryCategoryRecord, direction: -1 | 1) {
    const ordered = payload.categories.slice().sort((a, b) => a.order - b.order || a.name.localeCompare(b.name));
    const currentIndex = ordered.findIndex((entry) => entry.key === category.key);
    const swapWith = ordered[currentIndex + direction];
    if (!swapWith) return;
    setSaving(true);
    setError('');
    try {
      await replaceFromResponse(await fetch(`/api/bestiary/categories/${category.key}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ order: swapWith.order })
      }), 'Bestiary category order could not be changed.');
      await replaceFromResponse(await fetch(`/api/bestiary/categories/${swapWith.key}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ order: category.order })
      }), 'Bestiary category order could not be changed.');
    } catch (moveError) {
      setError(moveError instanceof Error ? moveError.message : 'Bestiary category order could not be changed.');
    } finally {
      setSaving(false);
    }
  }

  async function importMarkdown(file: File | null) {
    if (!file || !isDm) return;
    setSaving(true);
    setError('');
    try {
      const markdown = await file.text();
      await replaceFromResponse(await fetch('/api/bestiary/import', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ markdown })
      }), 'Bestiary import failed.');
      if (fileRef.current) fileRef.current.value = '';
    } catch (importError) {
      setError(importError instanceof Error ? importError.message : 'Bestiary import failed.');
    } finally {
      setSaving(false);
    }
  }

  if (loading) {
    return <Card><div className="grid h-32 place-items-center text-[var(--muted)]"><Loader2 className="animate-spin" /></div></Card>;
  }

  return (
    <div className="space-y-4">
      <Card>
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <p className="eyebrow">Known Creatures</p>
            <h2 className="mt-1 flex items-center gap-2 text-2xl font-black"><PawPrint className="text-[var(--brass)]" /> Bestiary</h2>
          </div>
          <div className="flex flex-wrap gap-2">
            {isDm && (
              <>
                <input ref={fileRef} type="file" accept=".md,text/markdown,text/plain" className="hidden" onChange={(event) => void importMarkdown(event.target.files?.[0] ?? null)} />
                <Button variant="teal" className="px-3 py-2 text-xs" disabled={saving} onClick={() => fileRef.current?.click()}>
                  <Upload className="mr-2 inline" size={14} /> Import .md
                </Button>
              </>
            )}
            <Button variant="secondary" className="p-3" onClick={loadBestiary} aria-label="Refresh bestiary"><RefreshCw size={16} /></Button>
          </div>
        </div>

        {error && <div className="mt-3 rounded-2xl border border-[var(--red)]/40 bg-[var(--red)]/10 p-3 text-sm text-[var(--red)]">{error}</div>}

        <div className="mt-4 rounded-2xl border border-[var(--line)] bg-black/15 p-3">
          <div className="mb-2 flex items-center justify-between gap-3 text-sm font-black">
            <span>{payload.unlockedCount} / {payload.totalCount} unlocked</span>
            <span className="text-[var(--brass)]">{progress}%</span>
          </div>
          <div className="h-3 overflow-hidden rounded-full bg-black/40">
            <div className="h-full rounded-full bg-gradient-to-r from-[var(--teal)] to-[var(--brass)]" style={{ width: `${progress}%` }} />
          </div>
        </div>

        <div className="mt-4">
          <label className="relative block">
            <Search className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-[var(--muted)]" size={16} />
            <TextField value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search known creatures" className="bestiary-search-input" />
          </label>
        </div>
      </Card>

      <div className="space-y-3">
        {grouped.map(({ category, entities }) => {
          const expanded = expandedCategories.has(category.key);
          const categoryIndex = payload.categories.slice().sort((a, b) => a.order - b.order || a.name.localeCompare(b.name)).findIndex((entry) => entry.key === category.key);
          const totalInCategory = payload.entities.filter((entity) => entity.category === category.key).length;
          const visibleInCategory = payload.entities.filter((entity) => entity.category === category.key && entity.unlocked).length;
          return (
            <Card key={category.key} className={`overflow-hidden ${category.hidden ? 'opacity-75' : ''}`}>
              <button
                type="button"
                onClick={() => toggleCategoryOpen(category.key)}
                className="group w-full rounded-2xl border border-[var(--line)] bg-gradient-to-br from-[rgba(245,180,76,0.16)] via-black/10 to-[rgba(31,120,117,0.14)] p-4 text-left transition hover:border-[var(--brass)]/70"
              >
                <span className="flex items-start justify-between gap-3">
                  <span className="min-w-0">
                    <span className="eyebrow">Bestiary Category</span>
                    <span className="mt-1 block text-xl font-black leading-tight">{category.name || categoryLabel(category.key)}</span>
                    <span className="mt-1 flex flex-wrap gap-2 text-xs font-bold text-[var(--muted)]">
                      <span>{visibleInCategory}/{totalInCategory} visible</span>
                      <span>{entities.length} shown here</span>
                      {category.hidden && <span className="text-[var(--red)]">Hidden from players</span>}
                    </span>
                  </span>
                  <span className="rounded-full border border-[var(--line)] bg-black/25 p-2 text-[var(--brass)]">
                    {expanded ? <ChevronDown size={18} /> : <ChevronRight size={18} />}
                  </span>
                </span>
              </button>

              {isDm && (
                <div className="mt-3 flex flex-wrap gap-2">
                  <Button variant={category.hidden ? 'teal' : 'secondary'} className="px-3 py-2 text-xs" onClick={() => void patchCategory(category, { hidden: !category.hidden }, 'Category visibility could not be changed.')} disabled={saving}>
                    {category.hidden ? <Eye className="mr-2 inline" size={13} /> : <EyeOff className="mr-2 inline" size={13} />}
                    {category.hidden ? 'Show category' : 'Hide category'}
                  </Button>
                  <Button variant="secondary" className="px-3 py-2 text-xs" onClick={() => void moveCategory(category, -1)} disabled={saving || categoryIndex <= 0} aria-label={`Move ${category.name} up`}><ArrowUp size={13} /></Button>
                  <Button variant="secondary" className="px-3 py-2 text-xs" onClick={() => void moveCategory(category, 1)} disabled={saving || categoryIndex < 0 || categoryIndex >= payload.categories.length - 1} aria-label={`Move ${category.name} down`}><ArrowDown size={13} /></Button>
                </div>
              )}

              {expanded && (
                <div className="mt-4 grid gap-3 lg:grid-cols-2">
                  {entities.map((entity) => (
                    <EntityCard
                      key={entity.id}
                      entity={entity}
                      categoryName={categoryMap.get(entity.category)?.name ?? categoryLabel(entity.category)}
                      isDm={isDm}
                      saving={saving}
                      onToggle={toggleEntity}
                    />
                  ))}
                  {!entities.length && <p className="rounded-2xl border border-[var(--line)] bg-black/10 p-3 text-sm text-[var(--muted)]">{isDm ? 'No matching entries in this category.' : 'No known entries here yet.'}</p>}
                </div>
              )}
            </Card>
          );
        })}
        {!grouped.length && <Card><p className="text-sm text-[var(--muted)]">{isDm ? 'No matching entries.' : 'The bestiary is blank for now.'}</p></Card>}
      </div>
    </div>
  );
}
