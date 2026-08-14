'use client';

import { useCallback, useEffect, useMemo, useRef, useState, type ChangeEvent, type CSSProperties, type MouseEvent, type PointerEvent, type WheelEvent } from 'react';
import { Flag, ImageUp, Loader2, LocateFixed, Map, MapPin, Minus, MousePointer2, Package, Plus, Puzzle, Skull, Sprout, Swords, Trash2, type LucideIcon } from 'lucide-react';
import { Button } from '@/components/ui/Button';
import { Card } from '@/components/ui/Card';
import { TextAreaField } from '@/components/ui/Field';
import { Modal } from '@/components/ui/Modal';
import { normalizeWorldMapPayload, type WorldMapImage, type WorldMapPin, type WorldMapPinType } from '@/features/world-map/data';
import { useLiveRefresh } from '@/hooks/useLiveRefresh';
import type { Profile } from '@/lib/types';

type PinDraft = {
  x: number;
  y: number;
};

type DragState = {
  pointerId: number;
  startX: number;
  startY: number;
  originX: number;
  originY: number;
};

const PIN_TYPES: Array<{ type: WorldMapPinType; label: string; Icon: LucideIcon; className: string }> = [
  { type: 'sword', label: 'Sword', Icon: Swords, className: 'border-[#f87171] bg-[#451717] text-[#fecaca]' },
  { type: 'puzzle', label: 'Puzzle', Icon: Puzzle, className: 'border-[#c084fc] bg-[#30144e] text-[#ead6ff]' },
  { type: 'skull', label: 'Danger', Icon: Skull, className: 'border-[#e5e7eb] bg-[#27272a] text-white' },
  { type: 'flag', label: 'Flag', Icon: Flag, className: 'border-[#facc15] bg-[#4a3708] text-[#fef08a]' },
  { type: 'plant', label: 'Plant', Icon: Sprout, className: 'border-[#86efac] bg-[#10391f] text-[#bbf7d0]' },
  { type: 'chest', label: 'Chest', Icon: Package, className: 'border-[#f59e0b] bg-[#3b2108] text-[#fed7aa]' }
];

function pinConfig(type: WorldMapPinType) {
  return PIN_TYPES.find((entry) => entry.type === type) ?? PIN_TYPES[0];
}

function clamp(value: number, min: number, max: number) {
  return Math.min(max, Math.max(min, value));
}

export function WorldMapPanel({ profile }: { profile: Profile }) {
  const isDm = profile.role === 'dm';
  const fileInputRef = useRef<HTMLInputElement | null>(null);
  const frameRef = useRef<HTMLDivElement | null>(null);
  const containerRef = useRef<HTMLDivElement | null>(null);
  const [map, setMap] = useState<WorldMapImage | null>(null);
  const [pins, setPins] = useState<WorldMapPin[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [imageSize, setImageSize] = useState<{ width: number; height: number } | null>(null);
  const [containerWidth, setContainerWidth] = useState(0);
  const [viewportHeight, setViewportHeight] = useState(720);
  const [zoom, setZoom] = useState(1);
  const [offset, setOffset] = useState({ x: 0, y: 0 });
  const [drag, setDrag] = useState<DragState | null>(null);
  const [addMode, setAddMode] = useState(false);
  const [pinDraft, setPinDraft] = useState<PinDraft | null>(null);
  const [pinType, setPinType] = useState<WorldMapPinType>('flag');
  const [pinDescription, setPinDescription] = useState('');
  const [selectedPin, setSelectedPin] = useState<WorldMapPin | null>(null);

  const aspectRatio = imageSize && imageSize.height > 0 ? imageSize.width / imageSize.height : 16 / 9;
  const maxFrameHeight = Math.max(300, viewportHeight - 220);
  const frameWidth = containerWidth > 0 && imageSize ? Math.min(containerWidth, maxFrameHeight * aspectRatio) : containerWidth;
  const frameHeight = frameWidth > 0 ? frameWidth / aspectRatio : Math.min(maxFrameHeight, 620);
  const frameStyle: CSSProperties = frameWidth > 0
    ? { width: frameWidth, height: frameHeight }
    : { aspectRatio: `${aspectRatio}`, width: '100%' };

  const canDeleteSelectedPin = Boolean(selectedPin && (isDm || selectedPin.createdBy === profile.id));
  const selectedPinConfig = selectedPin ? pinConfig(selectedPin.type) : null;
  const SelectedPinIcon = selectedPinConfig?.Icon ?? MapPin;

  const clampOffset = useCallback((next: { x: number; y: number }, nextZoom = zoom) => {
    if (nextZoom <= 1 || frameWidth <= 0 || frameHeight <= 0) return { x: 0, y: 0 };
    const maxX = (frameWidth * (nextZoom - 1)) / 2;
    const maxY = (frameHeight * (nextZoom - 1)) / 2;
    return {
      x: clamp(next.x, -maxX, maxX),
      y: clamp(next.y, -maxY, maxY)
    };
  }, [frameHeight, frameWidth, zoom]);

  const setPayload = useCallback((payloadValue: unknown) => {
    const payload = normalizeWorldMapPayload(payloadValue);
    setMap((currentMap) => {
      if (currentMap?.id !== payload.map?.id) setImageSize(null);
      return payload.map;
    });
    setPins(payload.pins);
  }, []);

  const loadMap = useCallback(async (showLoading = true) => {
    if (showLoading) setLoading(true);
    setError('');
    try {
      const response = await fetch('/api/world-map', { cache: 'no-store' });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.error ?? 'World map could not be loaded.');
      setPayload(payload);
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : 'World map could not be loaded.');
    } finally {
      if (showLoading) setLoading(false);
    }
  }, [setPayload]);

  useEffect(() => {
    void loadMap();
  }, [loadMap]);

  useEffect(() => {
    const updateViewport = () => setViewportHeight(window.innerHeight);
    updateViewport();
    window.addEventListener('resize', updateViewport);
    return () => window.removeEventListener('resize', updateViewport);
  }, []);

  useEffect(() => {
    const node = containerRef.current;
    if (!node) return undefined;
    const observer = new ResizeObserver((entries) => {
      setContainerWidth(entries[0]?.contentRect.width ?? 0);
    });
    observer.observe(node);
    return () => observer.disconnect();
  }, []);

  useEffect(() => {
    setOffset((current) => clampOffset(current));
  }, [clampOffset, zoom]);

  useLiveRefresh(['world-map'], () => loadMap(false));

  const mapTransform = useMemo(() => ({
    transform: `translate(${offset.x}px, ${offset.y}px) scale(${zoom})`
  }), [offset.x, offset.y, zoom]);

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
      setPayload(payload);
      setZoom(1);
      setOffset({ x: 0, y: 0 });
    } catch (uploadError) {
      setError(uploadError instanceof Error ? uploadError.message : 'World map could not be updated.');
    } finally {
      setSaving(false);
    }
  }

  function changeZoom(delta: number) {
    setZoom((current) => {
      const next = clamp(Number((current + delta).toFixed(2)), 1, 3);
      setOffset((offsetCurrent) => clampOffset(offsetCurrent, next));
      return next;
    });
  }

  function resetView() {
    setZoom(1);
    setOffset({ x: 0, y: 0 });
  }

  function mapPointFromPointer(clientX: number, clientY: number) {
    const frame = frameRef.current;
    if (!frame) return null;
    const rect = frame.getBoundingClientRect();
    const x = (clientX - rect.left - offset.x - rect.width / 2) / zoom + rect.width / 2;
    const y = (clientY - rect.top - offset.y - rect.height / 2) / zoom + rect.height / 2;
    return {
      x: clamp(x / rect.width, 0, 1),
      y: clamp(y / rect.height, 0, 1)
    };
  }

  function handleFrameClick(event: MouseEvent<HTMLDivElement>) {
    if (!map || !addMode) return;
    const point = mapPointFromPointer(event.clientX, event.clientY);
    if (!point) return;
    setPinDraft(point);
    setPinType('flag');
    setPinDescription('');
    setAddMode(false);
  }

  function handlePointerDown(event: PointerEvent<HTMLDivElement>) {
    if (addMode || zoom <= 1 || (event.target as HTMLElement).closest('[data-map-pin]')) return;
    event.currentTarget.setPointerCapture(event.pointerId);
    setDrag({
      pointerId: event.pointerId,
      startX: event.clientX,
      startY: event.clientY,
      originX: offset.x,
      originY: offset.y
    });
  }

  function handlePointerMove(event: PointerEvent<HTMLDivElement>) {
    if (!drag || drag.pointerId !== event.pointerId) return;
    setOffset(clampOffset({
      x: drag.originX + event.clientX - drag.startX,
      y: drag.originY + event.clientY - drag.startY
    }));
  }

  function handlePointerUp(event: PointerEvent<HTMLDivElement>) {
    if (drag?.pointerId === event.pointerId) setDrag(null);
  }

  function handleWheel(event: WheelEvent<HTMLDivElement>) {
    if (!map) return;
    event.preventDefault();
    changeZoom(event.deltaY > 0 ? -0.15 : 0.15);
  }

  async function savePin() {
    if (!pinDraft || !map) return;
    setSaving(true);
    setError('');
    try {
      const response = await fetch('/api/world-map/pins', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          type: pinType,
          x: pinDraft.x,
          y: pinDraft.y,
          description: pinDescription
        })
      });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.error ?? 'Map pin could not be placed.');
      setPayload(payload);
      setPinDraft(null);
      setPinDescription('');
    } catch (pinError) {
      setError(pinError instanceof Error ? pinError.message : 'Map pin could not be placed.');
    } finally {
      setSaving(false);
    }
  }

  async function deletePin(pin: WorldMapPin) {
    setSaving(true);
    setError('');
    try {
      const response = await fetch(`/api/world-map/pins/${pin.id}`, { method: 'DELETE' });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.error ?? 'Map pin could not be deleted.');
      setPayload(payload);
      setSelectedPin(null);
    } catch (deleteError) {
      setError(deleteError instanceof Error ? deleteError.message : 'Map pin could not be deleted.');
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="grid gap-4">
      <Card className="overflow-hidden">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div className="flex min-w-0 items-center gap-3">
            <span className="grid h-12 w-12 shrink-0 place-items-center rounded-2xl border border-[var(--brass)]/45 bg-[var(--brass)]/15 text-[var(--brass)] shadow-[0_0_22px_rgba(245,180,76,0.14)]">
              <Map size={24} />
            </span>
            <div className="min-w-0">
              <p className="eyebrow">Campaign Atlas</p>
              <h2 className="truncate text-3xl font-black leading-tight">World Map</h2>
            </div>
          </div>

          <div className="flex flex-wrap justify-end gap-2">
            <Button variant={addMode ? 'primary' : 'secondary'} className="px-3 py-2 text-xs sm:text-sm" disabled={!map || saving} onClick={() => setAddMode((current) => !current)}>
              <MapPin className="mr-2 inline" size={15} />
              Add pin
            </Button>
            <Button variant="ghost" className="px-3 py-2" disabled={!map || zoom <= 1} onClick={() => changeZoom(-0.25)} aria-label="Zoom out"><Minus size={16} /></Button>
            <Button variant="ghost" className="px-3 py-2" disabled={!map || zoom >= 3} onClick={() => changeZoom(0.25)} aria-label="Zoom in"><Plus size={16} /></Button>
            <Button variant="ghost" className="px-3 py-2" disabled={!map || (zoom === 1 && offset.x === 0 && offset.y === 0)} onClick={resetView} aria-label="Reset map view"><LocateFixed size={16} /></Button>
            {isDm && (
              <>
                <input ref={fileInputRef} type="file" accept="image/png,image/jpeg,image/webp,image/gif" className="hidden" onChange={uploadMap} />
                <Button variant="primary" className="px-3 py-2 text-xs sm:px-4 sm:text-sm" disabled={saving} onClick={() => fileInputRef.current?.click()}>
                  {saving ? <Loader2 className="mr-2 inline animate-spin" size={15} /> : <ImageUp className="mr-2 inline" size={15} />}
                  Upload
                </Button>
              </>
            )}
          </div>
        </div>
      </Card>

      {error && <p className="rounded-2xl border border-[var(--red)]/40 bg-[var(--red)]/10 p-3 text-sm font-black text-[var(--red)]">{error}</p>}

      {addMode && (
        <div className="flex items-center gap-2 rounded-2xl border border-[var(--brass)]/45 bg-[var(--brass)]/15 p-3 text-sm font-black text-[var(--brass)]">
          <MousePointer2 size={18} />
          Tap the exact place on the map for the new pin.
        </div>
      )}

      <section ref={containerRef} className={`relative min-h-[18rem] overflow-hidden rounded-2xl ${map ? 'border border-transparent bg-transparent p-0 shadow-none' : 'border border-[var(--line)] bg-[radial-gradient(circle_at_20%_10%,rgba(245,180,76,0.18),transparent_34%),linear-gradient(135deg,rgba(11,20,18,0.96),rgba(32,20,15,0.92))] p-2 shadow-[0_24px_80px_rgba(0,0,0,0.35)] sm:p-4'}`}>
        <div className="relative grid min-h-[18rem] place-items-center">
          {loading ? (
            <Loader2 className="animate-spin text-[var(--brass)]" size={32} />
          ) : map ? (
            <div
              ref={frameRef}
              className={`relative mx-auto overflow-hidden rounded-xl border border-[var(--brass)]/35 bg-transparent shadow-[0_20px_70px_rgba(0,0,0,0.4)] ${addMode ? 'cursor-crosshair' : zoom > 1 ? 'cursor-grab active:cursor-grabbing' : ''}`}
              style={frameStyle}
              onClick={handleFrameClick}
              onPointerDown={handlePointerDown}
              onPointerMove={handlePointerMove}
              onPointerUp={handlePointerUp}
              onPointerCancel={handlePointerUp}
              onWheel={handleWheel}
              onDoubleClick={() => changeZoom(0.35)}
            >
              <div className="absolute inset-0 origin-center transition-transform duration-100 ease-out" style={mapTransform}>
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img
                  src={map.imageDataUrl}
                  alt="World Map"
                  draggable={false}
                  className="h-full w-full select-none object-fill"
                  onLoad={(event) => setImageSize({ width: event.currentTarget.naturalWidth, height: event.currentTarget.naturalHeight })}
                />
                {pins.map((pin) => {
                  const config = pinConfig(pin.type);
                  const Icon = config.Icon;
                  return (
                    <button
                      key={pin.id}
                      data-map-pin
                      type="button"
                      className={`absolute grid h-8 w-8 place-items-center rounded-full border-2 shadow-[0_4px_16px_rgba(0,0,0,0.38)] transition hover:scale-110 ${config.className}`}
                      style={{
                        left: `${pin.x * 100}%`,
                        top: `${pin.y * 100}%`,
                        transform: `translate(-50%, -50%) scale(${1 / zoom})`,
                        transformOrigin: 'center'
                      }}
                      onClick={(event) => {
                        event.stopPropagation();
                        setSelectedPin(pin);
                      }}
                      aria-label={`${config.label} map pin`}
                    >
                      <Icon size={16} strokeWidth={2.7} />
                    </button>
                  );
                })}
              </div>
            </div>
          ) : (
            <div className="grid min-h-[18rem] place-items-center gap-3 text-center text-[var(--muted)]">
              <Map size={52} className="text-[var(--brass)]" />
              {isDm && <Button variant="secondary" onClick={() => fileInputRef.current?.click()}>Upload World Map</Button>}
            </div>
          )}
        </div>
      </section>

      {pinDraft && (
        <Modal title="Place Map Pin" onClose={() => setPinDraft(null)}>
          <div className="grid gap-4">
            <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
              {PIN_TYPES.map(({ type, label, Icon, className }) => (
                <button
                  key={type}
                  type="button"
                  className={`flex items-center gap-2 rounded-xl border p-3 text-sm font-black transition ${className} ${pinType === type ? 'ring-2 ring-[var(--brass)]' : 'opacity-80 hover:opacity-100'}`}
                  onClick={() => setPinType(type)}
                >
                  <Icon size={18} />
                  {label}
                </button>
              ))}
            </div>
            <TextAreaField
              rows={8}
              className="min-h-48 resize-y"
              placeholder="Describe what everyone should know about this location."
              value={pinDescription}
              onChange={(event) => setPinDescription(event.target.value)}
            />
            <div className="flex justify-end gap-2">
              <Button variant="ghost" onClick={() => setPinDraft(null)}>Cancel</Button>
              <Button variant="primary" disabled={saving || !pinDescription.trim()} onClick={savePin}>
                {saving && <Loader2 className="mr-2 inline animate-spin" size={15} />}
                Place pin
              </Button>
            </div>
          </div>
        </Modal>
      )}

      {selectedPin && selectedPinConfig && (
        <Modal title={selectedPinConfig.label} onClose={() => setSelectedPin(null)}>
          <div className="grid gap-4">
            <div className={`flex items-center gap-3 rounded-2xl border p-4 ${selectedPinConfig.className}`}>
              <span className="grid h-11 w-11 place-items-center rounded-full bg-black/25">
                <SelectedPinIcon size={22} />
              </span>
              <div>
                <p className="text-sm font-black">Placed by {selectedPin.createdByName}</p>
                <p className="text-xs opacity-80">{new Date(selectedPin.createdAt).toLocaleString()}</p>
              </div>
            </div>
            <p className="whitespace-pre-line rounded-2xl border border-[var(--line)] bg-black/20 p-4 text-sm leading-6 text-[var(--paper)]">{selectedPin.description}</p>
            {canDeleteSelectedPin && (
              <div className="flex justify-end">
                <Button variant="danger" disabled={saving} onClick={() => deletePin(selectedPin)}>
                  {saving ? <Loader2 className="mr-2 inline animate-spin" size={15} /> : <Trash2 className="mr-2 inline" size={15} />}
                  Delete pin
                </Button>
              </div>
            )}
          </div>
        </Modal>
      )}
    </div>
  );
}
