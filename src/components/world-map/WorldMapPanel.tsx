'use client';

import { useCallback, useEffect, useRef, useState, type ChangeEvent } from 'react';
import { ImageUp, Loader2, Map } from 'lucide-react';
import { Button } from '@/components/ui/Button';
import { Card } from '@/components/ui/Card';
import { normalizeWorldMapPayload, type WorldMapImage } from '@/features/world-map/data';
import { useLiveRefresh } from '@/hooks/useLiveRefresh';
import type { Profile } from '@/lib/types';

export function WorldMapPanel({ profile }: { profile: Profile }) {
  const isDm = profile.role === 'dm';
  const fileInputRef = useRef<HTMLInputElement | null>(null);
  const [map, setMap] = useState<WorldMapImage | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const loadMap = useCallback(async (showLoading = true) => {
    if (showLoading) setLoading(true);
    setError('');
    try {
      const response = await fetch('/api/world-map', { cache: 'no-store' });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.error ?? 'World map could not be loaded.');
      setMap(normalizeWorldMapPayload(payload).map);
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : 'World map could not be loaded.');
    } finally {
      if (showLoading) setLoading(false);
    }
  }, []);

  useEffect(() => {
    void loadMap();
  }, [loadMap]);

  useLiveRefresh(['world-map'], () => loadMap(false));

  async function uploadMap(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    event.target.value = '';
    if (!file || !isDm) return;

    const form = new FormData();
    form.set('image', file);
    setSaving(true);
    setError('');
    try {
      const response = await fetch('/api/world-map', {
        method: 'POST',
        body: form
      });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.error ?? 'World map could not be updated.');
      setMap(normalizeWorldMapPayload(payload).map);
    } catch (uploadError) {
      setError(uploadError instanceof Error ? uploadError.message : 'World map could not be updated.');
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="grid gap-4">
      <Card className="overflow-hidden">
        <div className="flex items-center justify-between gap-3">
          <div className="flex min-w-0 items-center gap-3">
            <span className="grid h-12 w-12 shrink-0 place-items-center rounded-2xl border border-[var(--brass)]/45 bg-[var(--brass)]/15 text-[var(--brass)] shadow-[0_0_22px_rgba(245,180,76,0.14)]">
              <Map size={24} />
            </span>
            <div className="min-w-0">
              <p className="eyebrow">Campaign Atlas</p>
              <h2 className="truncate text-3xl font-black leading-tight">World Map</h2>
            </div>
          </div>

          {isDm && (
            <div className="shrink-0">
              <input ref={fileInputRef} type="file" accept="image/png,image/jpeg,image/webp,image/gif" className="hidden" onChange={uploadMap} />
              <Button variant="primary" className="px-3 py-2 text-xs sm:px-4 sm:py-3 sm:text-sm" disabled={saving} onClick={() => fileInputRef.current?.click()}>
                {saving ? <Loader2 className="mr-2 inline animate-spin" size={15} /> : <ImageUp className="mr-2 inline" size={15} />}
                Upload
              </Button>
            </div>
          )}
        </div>
      </Card>

      {error && <p className="rounded-2xl border border-[var(--red)]/40 bg-[var(--red)]/10 p-3 text-sm font-black text-[var(--red)]">{error}</p>}

      <section className="relative min-h-[calc(100dvh-14rem)] overflow-hidden rounded-2xl border border-[var(--line)] bg-[radial-gradient(circle_at_20%_10%,rgba(245,180,76,0.18),transparent_34%),linear-gradient(135deg,rgba(11,20,18,0.96),rgba(32,20,15,0.92))] shadow-[0_24px_80px_rgba(0,0,0,0.35)] sm:min-h-[calc(100dvh-13rem)]">
        <div className="absolute inset-0 opacity-[0.18] [background-image:linear-gradient(rgba(245,180,76,0.32)_1px,transparent_1px),linear-gradient(90deg,rgba(245,180,76,0.32)_1px,transparent_1px)] [background-size:48px_48px]" />
        <div className="relative grid min-h-[calc(100dvh-14rem)] place-items-center p-2 sm:min-h-[calc(100dvh-13rem)] sm:p-4">
          {loading ? (
            <Loader2 className="animate-spin text-[var(--brass)]" size={32} />
          ) : map ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={map.imageDataUrl}
              alt="World Map"
              className="max-h-[calc(100dvh-15rem)] w-auto max-w-full rounded-xl border border-[var(--brass)]/35 object-contain shadow-[0_20px_70px_rgba(0,0,0,0.4)] sm:max-h-[calc(100dvh-14rem)]"
            />
          ) : (
            <div className="grid place-items-center gap-3 text-center text-[var(--muted)]">
              <Map size={52} className="text-[var(--brass)]" />
              {isDm && <Button variant="secondary" onClick={() => fileInputRef.current?.click()}>Upload World Map</Button>}
            </div>
          )}
        </div>
      </section>
    </div>
  );
}
