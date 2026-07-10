'use client';

import { memo, useEffect, useMemo, useRef, useState } from 'react';
import { LocateFixed, Minus, Plus } from 'lucide-react';
import { Button } from '@/components/ui/Button';
import { percent, clamp } from '@/lib/utils/format';
import type { Battle, Character, Combatant, Profile } from '@/lib/types';

const CELL_SIZE = 76;
const STARTING_ZOOM = 0.82;

type TokenView = Combatant & { character: Character | undefined };

const BattleToken = memo(function BattleToken({
  token,
  selected,
  mine,
  onSelect
}: {
  token: TokenView;
  selected: boolean;
  mine: boolean;
  onSelect: (id: string) => void;
}) {
  const character = token.character;
  const enemy = character?.kind === 'enemy';
  return (
    <button
      data-token
      onClick={(event) => {
        event.stopPropagation();
        onSelect(token.id);
      }}
      className={`absolute flex h-[70px] w-[70px] flex-col items-center justify-end gap-2 overflow-visible rounded-[22px] border-2 px-2 pb-2.5 pt-7 shadow-[inset_0_1px_0_rgba(255,255,255,0.22),0_12px_20px_rgba(0,0,0,0.34)] active:scale-95 ${
        selected ? 'border-[var(--brass)] ring-4 ring-[#d1a85b33]' : mine ? 'border-[var(--teal)]' : enemy ? 'border-[#d76a6299]' : 'border-white/25'
      }`}
      style={{
        left: token.x * CELL_SIZE + 3,
        top: token.y * CELL_SIZE + 3,
        backgroundColor: character?.tokenColor ?? '#5c665f',
        backgroundImage: 'radial-gradient(circle at 32% 22%, rgba(255,255,255,0.24), rgba(255,255,255,0) 34%), linear-gradient(180deg, rgba(255,255,255,0.08), rgba(0,0,0,0.22))'
      }}
      title={character?.name}
    >
      <span className="pointer-events-none absolute left-1/2 top-2.5 z-20 max-w-[11rem] -translate-x-1/2 whitespace-nowrap px-1 text-center text-[12px] font-black leading-none text-white [text-shadow:0_2px_3px_rgba(0,0,0,0.95),0_0_9px_rgba(0,0,0,0.85)]">
        {character?.name ?? 'Token'}
      </span>
      <span className="grid w-full gap-1.5">
        <span className="h-2.5 w-full overflow-hidden rounded-full border border-black/20 bg-black/50 shadow-inner">
          <span className="block h-full rounded-full bg-gradient-to-r from-[#b9332e] to-[#ff9c8e]" style={{ width: `${percent(token.currentHp, character?.maxHp ?? 1)}%` }} />
        </span>
        <span className="h-2.5 w-full overflow-hidden rounded-full border border-black/20 bg-black/50 shadow-inner">
          <span className="block h-full rounded-full bg-gradient-to-r from-[#336cbb] to-[#9ed1ff]" style={{ width: `${percent(token.currentMana, character?.maxMana ?? 1)}%` }} />
        </span>
      </span>
    </button>
  );
});

export function BattleMap({
  battle,
  tokens,
  profile,
  selectedId,
  onSelect,
  onMove
}: {
  battle: Battle;
  tokens: TokenView[];
  profile: Profile;
  selectedId: string | null;
  onSelect: (id: string) => void;
  onMove: (id: string, x: number, y: number) => void;
}) {
  const viewportRef = useRef<HTMLDivElement | null>(null);
  const mapRef = useRef<HTMLDivElement | null>(null);
  const panRef = useRef({ x: 16, y: 16 });
  const zoomRef = useRef(STARTING_ZOOM);
  const dragRef = useRef<{ id: number; x: number; y: number; baseX: number; baseY: number; moved: boolean } | null>(null);
  const pointersRef = useRef(new Map<number, { x: number; y: number }>());
  const pinchRef = useRef<{ distance: number; zoom: number } | null>(null);
  const [zoom, setZoom] = useState(STARTING_ZOOM);

  const size = useMemo(() => ({ width: battle.gridWidth * CELL_SIZE, height: battle.gridHeight * CELL_SIZE }), [battle.gridWidth, battle.gridHeight]);
  const isDm = profile.role === 'dm';

  function applyTransform() {
    if (!mapRef.current) return;
    const pan = panRef.current;
    mapRef.current.style.transform = `translate3d(${pan.x}px, ${pan.y}px, 0) scale(${zoomRef.current})`;
  }

  function setZoomValue(next: number) {
    zoomRef.current = clamp(next, 0.42, 2);
    setZoom(zoomRef.current);
    applyTransform();
  }

  function centerView(nextZoom = STARTING_ZOOM) {
    const viewport = viewportRef.current;
    const viewportWidth = viewport?.clientWidth ?? 900;
    const viewportHeight = viewport?.clientHeight ?? 520;
    const visible = tokens.filter((token) => Number.isFinite(token.x) && Number.isFinite(token.y));
    const center = visible.length
      ? {
          x: visible.reduce((sum, token) => sum + token.x, 0) / visible.length + 0.5,
          y: visible.reduce((sum, token) => sum + token.y, 0) / visible.length + 0.5
        }
      : { x: battle.gridWidth / 2, y: battle.gridHeight / 2 };
    zoomRef.current = nextZoom;
    setZoom(nextZoom);
    panRef.current = {
      x: viewportWidth / 2 - center.x * CELL_SIZE * nextZoom,
      y: viewportHeight / 2 - center.y * CELL_SIZE * nextZoom
    };
    applyTransform();
  }

  useEffect(() => {
    const frame = window.requestAnimationFrame(() => centerView());
    return () => window.cancelAnimationFrame(frame);
  }, [battle.id, tokens.length]);

  function pointerDown(event: React.PointerEvent<HTMLDivElement>) {
    pointersRef.current.set(event.pointerId, { x: event.clientX, y: event.clientY });
    event.currentTarget.setPointerCapture(event.pointerId);
    if (pointersRef.current.size === 2) {
      const points = [...pointersRef.current.values()];
      pinchRef.current = { distance: Math.hypot(points[0].x - points[1].x, points[0].y - points[1].y), zoom: zoomRef.current };
      dragRef.current = null;
      return;
    }
    if ((event.target as HTMLElement).closest('[data-token]')) return;
    dragRef.current = { id: event.pointerId, x: event.clientX, y: event.clientY, baseX: panRef.current.x, baseY: panRef.current.y, moved: false };
  }

  function pointerMove(event: React.PointerEvent<HTMLDivElement>) {
    if (pointersRef.current.has(event.pointerId)) pointersRef.current.set(event.pointerId, { x: event.clientX, y: event.clientY });
    if (pointersRef.current.size === 2 && pinchRef.current) {
      const points = [...pointersRef.current.values()];
      const distance = Math.hypot(points[0].x - points[1].x, points[0].y - points[1].y);
      setZoomValue(pinchRef.current.zoom * (distance / Math.max(1, pinchRef.current.distance)));
      return;
    }

    const drag = dragRef.current;
    if (!drag || drag.id !== event.pointerId) return;
    const dx = event.clientX - drag.x;
    const dy = event.clientY - drag.y;
    drag.moved = drag.moved || Math.abs(dx) + Math.abs(dy) > 7;
    panRef.current = { x: drag.baseX + dx, y: drag.baseY + dy };
    applyTransform();
  }

  function pointerUp(event: React.PointerEvent<HTMLDivElement>) {
    pointersRef.current.delete(event.pointerId);
    pinchRef.current = null;
    const drag = dragRef.current;
    if (!drag || drag.id !== event.pointerId) return;
    const selected = tokens.find((token) => token.id === selectedId);
    if (!drag.moved && isDm && selected && viewportRef.current) {
      const rect = viewportRef.current.getBoundingClientRect();
      const pan = panRef.current;
      const x = Math.floor((event.clientX - rect.left - pan.x) / zoomRef.current / CELL_SIZE);
      const y = Math.floor((event.clientY - rect.top - pan.y) / zoomRef.current / CELL_SIZE);
      if (x >= 0 && x < battle.gridWidth && y >= 0 && y < battle.gridHeight) onMove(selected.id, x, y);
    }
    dragRef.current = null;
  }

  return (
    <section className="surface overflow-hidden rounded-2xl">
      <div className="flex items-center justify-between gap-3 border-b border-white/[0.07] p-3">
        <div>
          <p className="eyebrow">Live encounter</p>
          <h2 className="font-black">Battlefield</h2>
        </div>
        <div className="flex items-center gap-1.5">
          <Button className="p-2.5" onClick={() => setZoomValue(zoomRef.current - 0.12)} aria-label="Zoom out"><Minus size={16} /></Button>
          <span className="flex min-w-12 items-center justify-center text-xs font-black text-[var(--muted)]">{Math.round(zoom * 100)}%</span>
          <Button className="p-2.5" onClick={() => setZoomValue(zoomRef.current + 0.12)} aria-label="Zoom in"><Plus size={16} /></Button>
          <Button className="p-2.5" onClick={() => centerView()} aria-label="Center view"><LocateFixed size={16} /></Button>
        </div>
      </div>

      <div
        ref={viewportRef}
        className="relative h-[56vh] min-h-[410px] touch-none overflow-hidden bg-[#090d0c]"
        onPointerDown={pointerDown}
        onPointerMove={pointerMove}
        onPointerUp={pointerUp}
        onPointerCancel={pointerUp}
        onWheel={(event) => {
          if (!event.ctrlKey) return;
          event.preventDefault();
          setZoomValue(zoomRef.current - event.deltaY * 0.001);
        }}
      >
        <div ref={mapRef} className="absolute left-0 top-0 origin-top-left will-change-transform" style={{ transform: `translate3d(${panRef.current.x}px, ${panRef.current.y}px, 0) scale(${zoom})` }}>
          <div className="map-grid-bg relative rounded-lg" style={{ width: size.width, height: size.height, backgroundSize: `${CELL_SIZE}px ${CELL_SIZE}px` }}>
            {tokens.map((token) => (
              <BattleToken key={token.id} token={token} selected={token.id === selectedId} mine={token.character?.ownerUserId === profile.id} onSelect={onSelect} />
            ))}
          </div>
        </div>
        <div className="pointer-events-none absolute bottom-3 left-3 right-3 flex justify-center">
          <div className="rounded-full border border-white/10 bg-[#0d1110dc] px-4 py-2 text-center text-[11px] font-bold text-[var(--muted)]">
            {isDm && selectedId ? 'Tap a square to move · tap token again to cancel' : 'Drag to pan · pinch or Ctrl-wheel to zoom'}
          </div>
        </div>
      </div>
    </section>
  );
}
