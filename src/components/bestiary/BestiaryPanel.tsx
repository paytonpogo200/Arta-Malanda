'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { Eye, EyeOff, Loader2, PawPrint, RefreshCw, Search } from 'lucide-react';
import { Button } from '@/components/ui/Button';
import { Card } from '@/components/ui/Card';
import { TextField } from '@/components/ui/Field';
import { BESTIARY_CATEGORIES, normalizeBestiaryPayload, type BestiaryPayload } from '@/features/bestiary/data';
import type { BestiaryCategory, BestiaryEntity, Profile } from '@/lib/types';

const EMPTY: BestiaryPayload = {
  entities: [],
  unlockedCount: 0,
  totalCount: 0
};

function categoryLabel(category: BestiaryCategory) {
  return category[0].toUpperCase() + category.slice(1);
}

function EntityCard({
  entity,
  isDm,
  saving,
  onToggle
}: {
  entity: BestiaryEntity;
  isDm: boolean;
  saving: boolean;
  onToggle: (entity: BestiaryEntity) => void;
}) {
  return (
    <article className={`rounded-2xl border p-4 transition ${entity.unlocked ? 'border-[var(--line)] bg-black/15' : 'border-dashed border-[var(--line)] bg-black/10 opacity-75'}`}>
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="eyebrow">{categoryLabel(entity.category)}</p>
          <h3 className="mt-1 truncate text-xl font-black">{entity.name}</h3>
        </div>
        {isDm && (
          <Button variant={entity.unlocked ? 'teal' : 'secondary'} className="px-3 py-2 text-xs" disabled={saving} onClick={() => onToggle(entity)}>
            {entity.unlocked ? <Eye className="mr-1 inline" size={13} /> : <EyeOff className="mr-1 inline" size={13} />}
            {entity.unlocked ? 'Visible' : 'Hidden'}
          </Button>
        )}
      </div>

      <p className="mt-3 text-sm leading-6 text-[var(--muted)]">{entity.summary || 'No field notes yet.'}</p>

      <div className="mt-4 grid grid-cols-3 gap-2 text-center">
        <div className="rounded-xl border border-[var(--line)] bg-black/15 p-2">
          <p className="text-[10px] font-black uppercase text-[var(--muted)]">Wild</p>
          <p className="font-black text-[var(--brass)]">{entity.wildScore}</p>
        </div>
        <div className="rounded-xl border border-[var(--line)] bg-black/15 p-2">
          <p className="text-[10px] font-black uppercase text-[var(--muted)]">HP</p>
          <p className="font-black">{entity.hp}</p>
        </div>
        <div className="rounded-xl border border-[var(--line)] bg-black/15 p-2">
          <p className="text-[10px] font-black uppercase text-[var(--muted)]">Mana</p>
          <p className="font-black">{entity.mana}</p>
        </div>
      </div>

      <div className="mt-3 grid gap-2 text-xs text-[var(--muted)] sm:grid-cols-2">
        <p><span className="font-black uppercase text-[var(--paper)]">Habitat:</span> {entity.habitat || 'Unknown'}</p>
        <p><span className="font-black uppercase text-[var(--paper)]">Temper:</span> {entity.temperament || 'Unknown'}</p>
      </div>

      {entity.details && <p className="mt-3 rounded-xl bg-black/15 p-3 text-sm leading-6 text-[var(--muted)]">{entity.details}</p>}
    </article>
  );
}

export function BestiaryPanel({ profile }: { profile: Profile }) {
  const [payload, setPayload] = useState<BestiaryPayload>(EMPTY);
  const [query, setQuery] = useState('');
  const [category, setCategory] = useState<BestiaryCategory | 'all'>('all');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
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

  const filtered = useMemo(() => {
    const needle = query.trim().toLowerCase();
    return payload.entities.filter((entity) => {
      if (category !== 'all' && entity.category !== category) return false;
      if (!needle) return true;
      return `${entity.name} ${entity.summary} ${entity.habitat} ${entity.temperament}`.toLowerCase().includes(needle);
    });
  }, [category, payload.entities, query]);

  async function toggleEntity(entity: BestiaryEntity) {
    if (!isDm) return;
    setSaving(true);
    setError('');
    try {
      const response = await fetch(`/api/bestiary/entities/${entity.id}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ unlocked: !entity.unlocked })
      });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(body.error ?? 'Bestiary entry could not be changed.');
      setPayload(normalizeBestiaryPayload(body));
    } catch (toggleError) {
      setError(toggleError instanceof Error ? toggleError.message : 'Bestiary entry could not be changed.');
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
          <Button variant="secondary" className="p-3" onClick={loadBestiary} aria-label="Refresh bestiary"><RefreshCw size={16} /></Button>
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

        <div className="mt-4 grid gap-2 md:grid-cols-[1fr_auto]">
          <label className="relative">
            <Search className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-[var(--muted)]" size={16} />
            <TextField value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search known creatures" className="pl-10" />
          </label>
          <div className="thin-scrollbar flex gap-1 overflow-x-auto">
            <Button variant={category === 'all' ? 'primary' : 'secondary'} className="whitespace-nowrap px-3 py-2 text-xs" onClick={() => setCategory('all')}>All</Button>
            {BESTIARY_CATEGORIES.map((entry) => (
              <Button key={entry} variant={category === entry ? 'primary' : 'secondary'} className="whitespace-nowrap px-3 py-2 text-xs" onClick={() => setCategory(entry)}>{categoryLabel(entry)}</Button>
            ))}
          </div>
        </div>
      </Card>

      <div className="grid gap-3 lg:grid-cols-2">
        {filtered.map((entity) => <EntityCard key={entity.id} entity={entity} isDm={isDm} saving={saving} onToggle={toggleEntity} />)}
        {!filtered.length && <Card><p className="text-sm text-[var(--muted)]">{isDm ? 'No matching entries.' : 'The bestiary is blank for now.'}</p></Card>}
      </div>
    </div>
  );
}
