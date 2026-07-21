'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { Compass, FileUp, Loader2, RefreshCw } from 'lucide-react';
import { ItemIcon } from '@/components/inventory/ItemIcon';
import { Button } from '@/components/ui/Button';
import { Card } from '@/components/ui/Card';
import { normalizeItemCatalogPayload, type ItemCatalogPayload } from '@/features/exploration/data';
import { rarityClass } from '@/lib/utils/rarity';

const EMPTY: ItemCatalogPayload = {
  pools: [],
  items: []
};

export function ExplorationPanel() {
  const [payload, setPayload] = useState<ItemCatalogPayload>(EMPTY);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const loadCatalog = useCallback(async () => {
    setError('');
    try {
      const response = await fetch('/api/exploration', { cache: 'no-store' });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(body.error ?? 'Item catalog could not be loaded.');
      setPayload(normalizeItemCatalogPayload(body));
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : 'Item catalog could not be loaded.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void loadCatalog();
  }, [loadCatalog]);

  const grouped = useMemo(() => {
    return payload.pools
      .map((pool) => ({
        pool,
        items: payload.items.filter((item) => item.poolId === pool.id)
      }))
      .filter((group) => group.items.length)
      .sort((a, b) => a.pool.order - b.pool.order || a.pool.name.localeCompare(b.pool.name));
  }, [payload.items, payload.pools]);

  async function importWorkbook(file: File | null) {
    if (!file) return;
    setSaving(true);
    setError('');
    try {
      const form = new FormData();
      form.append('file', file);
      const response = await fetch('/api/exploration/import', { method: 'POST', body: form });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(body.error ?? 'Item catalog import failed.');
      setPayload(normalizeItemCatalogPayload(body));
    } catch (importError) {
      setError(importError instanceof Error ? importError.message : 'Item catalog import failed.');
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
        <div className="flex items-center justify-between gap-3">
          <div>
            <p className="eyebrow">DM Tools</p>
            <h2 className="mt-1 flex items-center gap-2 text-2xl font-black"><Compass className="text-[var(--brass)]" /> Exploration</h2>
          </div>
          <Button variant="secondary" className="p-3" onClick={loadCatalog} aria-label="Refresh item catalog"><RefreshCw size={16} /></Button>
        </div>
        {error && <div className="mt-3 rounded-2xl border border-[var(--red)]/40 bg-[var(--red)]/10 p-3 text-sm text-[var(--red)]">{error}</div>}
      </Card>

      <Card>
        <div className="rule-title mb-3"><h3 className="text-sm font-black uppercase tracking-wider">Item Catalog</h3></div>
        <label className="grid cursor-pointer gap-2 rounded-2xl border border-dashed border-[var(--line)] bg-black/15 p-4 text-center transition hover:border-[var(--brass)]">
          <FileUp className="mx-auto text-[var(--brass)]" size={22} />
          <span className="text-sm font-black">Upload Loot Drops workbook</span>
          <input
            type="file"
            accept=".xlsx,.xlsm,.xls"
            className="sr-only"
            disabled={saving}
            onChange={(event) => void importWorkbook(event.target.files?.[0] ?? null)}
          />
        </label>
        <div className="mt-3 grid gap-2 rounded-2xl border border-[var(--line)] bg-black/10 p-3 text-xs font-bold text-[var(--muted)] sm:grid-cols-2">
          <span>Catalog groups: <b className="text-[var(--paper)]">{payload.pools.length}</b></span>
          <span>Catalog items: <b className="text-[var(--paper)]">{payload.items.length}</b></span>
        </div>
      </Card>

      {grouped.map(({ pool, items }) => (
        <Card key={pool.id}>
          <div className="rule-title mb-3"><h3 className="text-sm font-black uppercase tracking-wider">{pool.name}</h3></div>
          <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
            {items.map((item) => (
              <div key={item.id} className={`rounded-2xl border p-3 ${rarityClass(item.rarity)}`}>
                <div className="flex items-start gap-2">
                  <span className="mt-0.5 text-[var(--brass)]"><ItemIcon type={item.type} size={18} /></span>
                  <span className="min-w-0">
                    <span className="block break-words font-black">{item.name}</span>
                    <span className="mt-1 block text-xs uppercase tracking-wide text-[var(--muted)]">{item.rarity} · {item.type} · {item.minQuantity}-{item.maxQuantity}</span>
                  </span>
                </div>
              </div>
            ))}
          </div>
        </Card>
      ))}
    </div>
  );
}
