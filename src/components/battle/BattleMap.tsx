'use client';

import { memo, useCallback, useEffect, useMemo, useRef, useState, type MouseEvent, type PointerEvent } from 'react';
import { Brush, Check, LocateFixed, Minus, PaintBucket, Palette, Pencil, Plus, RotateCcw, RotateCw, Square, Trash2 } from 'lucide-react';
import { characterLevelTokenClass, LevelPips } from '@/components/characters/LevelBadge';
import { Button } from '@/components/ui/Button';
import { Modal } from '@/components/ui/Modal';
import { percent, clamp } from '@/lib/utils/format';
import type { Battle, BattleTerrain, BattleTilePaint, Character, Combatant, Profile } from '@/lib/types';

const CELL_SIZE = 76;
const STARTING_ZOOM = 0.82;

type TokenView = Combatant & { character: Character | undefined };
type Cell = { x: number; y: number };
type TerrainAction = { action: 'add' | 'remove'; cells: Cell[] };
type BorderBrush = 'draw' | 'fill';
type MapMode = 'move' | 'border' | 'paint';

const TILE_PAINT_PRESETS = [
  { name: 'Red', color: '#b83a3a' },
  { name: 'Blue', color: '#3974b8' },
  { name: 'Green', color: '#3f874f' },
  { name: 'Yellow', color: '#d6b63f' },
  { name: 'Orange', color: '#c76b2c' },
  { name: 'Purple', color: '#7850a8' },
  { name: 'Black', color: '#111111' },
  { name: 'White', color: '#eeeeea' },
  { name: 'Brown', color: '#765038' },
  { name: 'Gray', color: '#6b7280' }
] as const;

function cellsBetween(start: Cell, end: Cell) {
  const cells: Cell[] = [];
  let x = start.x;
  let y = start.y;
  const dx = Math.abs(end.x - start.x);
  const dy = Math.abs(end.y - start.y);
  const stepX = start.x < end.x ? 1 : -1;
  const stepY = start.y < end.y ? 1 : -1;
  let error = dx - dy;

  while (true) {
    cells.push({ x, y });
    if (x === end.x && y === end.y) break;
    const doubled = error * 2;
    if (doubled > -dy) {
      error -= dy;
      x += stepX;
    }
    if (doubled < dx) {
      error += dx;
      y += stepY;
    }
  }
  return cells;
}

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
      data-token-id={token.id}
      onClick={(event) => {
        event.stopPropagation();
        onSelect(token.id);
      }}
      className={`absolute z-30 flex h-[70px] w-[70px] flex-col items-center justify-end gap-2 overflow-visible rounded-[22px] border-2 px-2 pb-2.5 pt-7 shadow-[inset_0_1px_0_rgba(255,255,255,0.22),0_12px_20px_rgba(0,0,0,0.34)] active:scale-95 ${characterLevelTokenClass(character?.level)} ${
        selected ? 'border-[var(--brass)] ring-4 ring-[#d1a85b33]' : mine ? 'border-[var(--teal)]' : enemy ? 'border-[#d76a6299]' : 'border-white/25'
      }`}
      style={{
        left: token.x * CELL_SIZE + 3,
        top: token.y * CELL_SIZE + 3,
        background: `radial-gradient(circle at 32% 22%, rgba(255,255,255,0.24), rgba(255,255,255,0) 34%), linear-gradient(180deg, rgba(255,255,255,0.08), rgba(0,0,0,0.22)), ${character?.tokenColor ?? '#5c665f'}`
      }}
      title={character?.name}
    >
      <LevelPips level={character?.level} />
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
  terrain,
  tilePaint,
  profile,
  canEditMap,
  viewingCharacterId,
  selectedId,
  onSelect,
  onMove,
  onTerrainAdd,
  onTerrainRemove,
  onTerrainClear,
  onTilePaint,
  onTilePaintClear
}: {
  battle: Battle;
  tokens: TokenView[];
  terrain: BattleTerrain[];
  tilePaint: BattleTilePaint[];
  profile: Profile;
  canEditMap: boolean;
  viewingCharacterId?: string | null;
  selectedId: string | null;
  onSelect: (id: string) => void;
  onMove: (id: string, x: number, y: number) => void;
  onTerrainAdd: (cells: Cell[]) => void;
  onTerrainRemove: (cells: Cell[]) => void;
  onTerrainClear: () => void;
  onTilePaint: (cells: Cell[], color: string) => void;
  onTilePaintClear: () => void;
}) {
  const viewportRef = useRef<HTMLDivElement | null>(null);
  const mapRef = useRef<HTMLDivElement | null>(null);
  const tilePaintCanvasRef = useRef<HTMLCanvasElement | null>(null);
  const tilePaintPreviewCanvasRef = useRef<HTMLCanvasElement | null>(null);
  const panRef = useRef({ x: 16, y: 16 });
  const zoomRef = useRef(STARTING_ZOOM);
  const tokensRef = useRef(tokens);
  const dragRef = useRef<{ id: number; x: number; y: number; baseX: number; baseY: number; moved: boolean } | null>(null);
  const paintRef = useRef<{ id: number; cells: Map<string, Cell> } | null>(null);
  const tilePaintRef = useRef<{ id: number; cells: Map<string, Cell>; lastCell: Cell | null; color: string } | null>(null);
  const suppressClickRef = useRef(false);
  const moveHandledRef = useRef(false);
  const pointersRef = useRef(new Map<number, { x: number; y: number }>());
  const pinchRef = useRef<{ distance: number; zoom: number } | null>(null);
  const [zoom, setZoom] = useState(STARTING_ZOOM);
  const [mode, setMode] = useState<MapMode>('move');
  const [borderBrush, setBorderBrush] = useState<BorderBrush>('draw');
  const [paintColor, setPaintColor] = useState<string>(TILE_PAINT_PRESETS[0].color);
  const [confirmClearPaint, setConfirmClearPaint] = useState(false);
  const [paintPreviewCells, setPaintPreviewCells] = useState<Cell[]>([]);
  const [undoStack, setUndoStack] = useState<TerrainAction[]>([]);
  const [redoStack, setRedoStack] = useState<TerrainAction[]>([]);

  const size = useMemo(() => ({ width: battle.gridWidth * CELL_SIZE, height: battle.gridHeight * CELL_SIZE }), [battle.gridWidth, battle.gridHeight]);
  const terrainKeys = useMemo(() => new Set(terrain.map((cell) => `${cell.x}:${cell.y}`)), [terrain]);
  const tilePaintByCell = useMemo(() => new Map(tilePaint.map((cell) => [`${cell.x}:${cell.y}`, cell.color])), [tilePaint]);
  const occupiedKeys = useMemo(() => new Set(tokens.map((token) => `${token.x}:${token.y}`)), [tokens]);
  tokensRef.current = tokens;

  useEffect(() => {
    if (canEditMap) return;
    setMode('move');
    setBorderBrush('draw');
  }, [canEditMap]);

  useEffect(() => {
    const canvas = tilePaintCanvasRef.current;
    const context = canvas?.getContext('2d');
    if (!canvas || !context) return;
    context.clearRect(0, 0, battle.gridWidth, battle.gridHeight);
    tilePaint.forEach((cell) => {
      if (cell.x < 0 || cell.x >= battle.gridWidth || cell.y < 0 || cell.y >= battle.gridHeight) return;
      context.fillStyle = cell.color;
      context.fillRect(cell.x, cell.y, 1, 1);
    });
  }, [battle.gridHeight, battle.gridWidth, tilePaint]);

  function clearTilePaintPreview() {
    const context = tilePaintPreviewCanvasRef.current?.getContext('2d');
    context?.clearRect(0, 0, battle.gridWidth, battle.gridHeight);
  }

  function cancelActiveGesture() {
    paintRef.current = null;
    tilePaintRef.current = null;
    setPaintPreviewCells([]);
    clearTilePaintPreview();
  }

  function chooseMode(nextMode: MapMode) {
    cancelActiveGesture();
    setMode(nextMode);
    if (nextMode !== 'border') setBorderBrush('draw');
    if (nextMode === 'border') fitWholeMap();
  }

  function applyTransform() {
    if (!mapRef.current) return;
    const pan = panRef.current;
    mapRef.current.style.transform = `translate3d(${pan.x}px, ${pan.y}px, 0) scale(${zoomRef.current})`;
  }

  function setZoomValue(next: number) {
    zoomRef.current = clamp(next, 0.05, 2);
    setZoom(zoomRef.current);
    applyTransform();
  }

  const centerView = useCallback((nextZoom = STARTING_ZOOM) => {
    const viewport = viewportRef.current;
    const viewportWidth = viewport?.clientWidth ?? 900;
    const viewportHeight = viewport?.clientHeight ?? 520;
    const visible = tokensRef.current.filter((token) => Number.isFinite(token.x) && Number.isFinite(token.y));
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
  }, [battle.gridHeight, battle.gridWidth]);

  const fitWholeMap = useCallback(() => {
    const viewport = viewportRef.current;
    const viewportWidth = viewport?.clientWidth ?? 900;
    const viewportHeight = viewport?.clientHeight ?? 520;
    const nextZoom = clamp(Math.min((viewportWidth - 32) / size.width, (viewportHeight - 32) / size.height), 0.05, 1.2);
    zoomRef.current = nextZoom;
    setZoom(nextZoom);
    panRef.current = {
      x: (viewportWidth - size.width * nextZoom) / 2,
      y: (viewportHeight - size.height * nextZoom) / 2
    };
    applyTransform();
  }, [size.height, size.width]);

  useEffect(() => {
    const frame = window.requestAnimationFrame(() => centerView());
    return () => window.cancelAnimationFrame(frame);
  }, [battle.id, centerView, tokens.length]);

  function cellFromPointer(event: Pick<PointerEvent<HTMLDivElement> | MouseEvent<HTMLDivElement>, 'clientX' | 'clientY'>) {
    const rect = viewportRef.current?.getBoundingClientRect();
    if (!rect) return null;
    const pan = panRef.current;
    const x = Math.floor((event.clientX - rect.left - pan.x) / zoomRef.current / CELL_SIZE);
    const y = Math.floor((event.clientY - rect.top - pan.y) / zoomRef.current / CELL_SIZE);
    if (x < 0 || x >= battle.gridWidth || y < 0 || y >= battle.gridHeight) return null;
    return { x, y };
  }

  function cellKey(cell: Cell) {
    return `${cell.x}:${cell.y}`;
  }

  function floodOpenRegion(start: Cell | null) {
    if (!start) return [];
    const blocked = new Set([...terrainKeys, ...occupiedKeys]);
    if (blocked.has(cellKey(start))) return [];

    const cells: Cell[] = [];
    const seen = new Set<string>();
    const stack = [start];

    while (stack.length) {
      const cell = stack.pop();
      if (!cell || cell.x < 0 || cell.x >= battle.gridWidth || cell.y < 0 || cell.y >= battle.gridHeight) continue;

      const key = cellKey(cell);
      if (seen.has(key) || blocked.has(key)) continue;
      seen.add(key);
      cells.push(cell);

      stack.push(
        { x: cell.x + 1, y: cell.y },
        { x: cell.x - 1, y: cell.y },
        { x: cell.x, y: cell.y + 1 },
        { x: cell.x, y: cell.y - 1 }
      );
    }

    return cells;
  }

  function collectPaintCell(event: PointerEvent<HTMLDivElement>) {
    const paint = paintRef.current;
    const cell = cellFromPointer(event);
    if (!paint || !cell) return;
    if (occupiedKeys.has(cellKey(cell))) return;
    paint.cells.set(cellKey(cell), cell);
    setPaintPreviewCells([...paint.cells.values()]);
  }

  function collectTilePaintCell(event: PointerEvent<HTMLDivElement>) {
    const gesture = tilePaintRef.current;
    const cell = cellFromPointer(event);
    const context = tilePaintPreviewCanvasRef.current?.getContext('2d');
    if (!gesture || !cell || !context) return;

    const path = gesture.lastCell ? cellsBetween(gesture.lastCell, cell) : [cell];
    context.fillStyle = gesture.color;
    path.forEach((pathCell) => {
      const key = cellKey(pathCell);
      if (gesture.cells.has(key)) return;
      gesture.cells.set(key, pathCell);
      context.fillRect(pathCell.x, pathCell.y, 1, 1);
    });
    gesture.lastCell = cell;
  }

  function moveSelectedToCell(cell: Cell | null) {
    const selected = tokensRef.current.find((token) => token.id === selectedId);
    if (!canEditMap || mode !== 'move' || !selected || !cell) return false;
    const key = cellKey(cell);
    if (terrainKeys.has(key)) return false;
    if (tokensRef.current.some((token) => token.id !== selected.id && token.x === cell.x && token.y === cell.y)) return false;
    if (selected.x === cell.x && selected.y === cell.y) return false;
    onMove(selected.id, cell.x, cell.y);
    return true;
  }

  function clickMap(event: MouseEvent<HTMLDivElement>) {
    if (suppressClickRef.current || moveHandledRef.current) {
      suppressClickRef.current = false;
      moveHandledRef.current = false;
      return;
    }
    if ((event.target as HTMLElement).closest('[data-token]')) return;
    const cell = cellFromPointer(event);
    void moveSelectedToCell(cell);
  }

  function pointerDown(event: PointerEvent<HTMLDivElement>) {
    const tokenElement = (event.target as HTMLElement).closest<HTMLElement>('[data-token-id]');
    if (mode === 'move' && tokenElement?.dataset.tokenId) {
      event.preventDefault();
      onSelect(tokenElement.dataset.tokenId);
      return;
    }
    if (mode === 'paint' && tokenElement) return;

    pointersRef.current.set(event.pointerId, { x: event.clientX, y: event.clientY });
    event.currentTarget.setPointerCapture(event.pointerId);

    if (pointersRef.current.size === 2) {
      const points = [...pointersRef.current.values()];
      cancelActiveGesture();
      pinchRef.current = { distance: Math.hypot(points[0].x - points[1].x, points[0].y - points[1].y), zoom: zoomRef.current };
      dragRef.current = null;
      return;
    }

    if (canEditMap && mode === 'border') {
      event.preventDefault();
      if (borderBrush === 'fill') {
        const cells = floodOpenRegion(cellFromPointer(event));
        if (cells.length) {
          setUndoStack((current) => [...current, { action: 'add', cells }]);
          setRedoStack([]);
          onTerrainAdd(cells);
        }
        setMode('move');
        setBorderBrush('draw');
        suppressClickRef.current = true;
        return;
      }

      paintRef.current = { id: event.pointerId, cells: new Map() };
      setPaintPreviewCells([]);
      collectPaintCell(event);
      return;
    }

    if (canEditMap && mode === 'paint') {
      event.preventDefault();
      clearTilePaintPreview();
      tilePaintRef.current = { id: event.pointerId, cells: new Map(), lastCell: null, color: paintColor };
      collectTilePaintCell(event);
      return;
    }

    if ((event.target as HTMLElement).closest('[data-token]')) return;
    dragRef.current = { id: event.pointerId, x: event.clientX, y: event.clientY, baseX: panRef.current.x, baseY: panRef.current.y, moved: false };
  }

  function pointerMove(event: PointerEvent<HTMLDivElement>) {
    if (tilePaintRef.current?.id === event.pointerId) {
      collectTilePaintCell(event);
      return;
    }
    if (paintRef.current?.id === event.pointerId) {
      collectPaintCell(event);
      return;
    }

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

  function pointerUp(event: PointerEvent<HTMLDivElement>) {
    pointersRef.current.delete(event.pointerId);
    pinchRef.current = null;

    const tilePaintGesture = tilePaintRef.current;
    if (tilePaintGesture?.id === event.pointerId) {
      const cells = [...tilePaintGesture.cells.values()].filter((cell) => tilePaintByCell.get(cellKey(cell)) !== tilePaintGesture.color);
      tilePaintRef.current = null;
      if (cells.length) onTilePaint(cells, tilePaintGesture.color);
      suppressClickRef.current = true;
      window.requestAnimationFrame(clearTilePaintPreview);
      return;
    }

    const paint = paintRef.current;
    if (paint?.id === event.pointerId) {
      const cells = [...paint.cells.values()].filter((cell) => !terrainKeys.has(cellKey(cell)));
      if (cells.length) {
        setUndoStack((current) => [...current, { action: 'add', cells }]);
        setRedoStack([]);
        onTerrainAdd(cells);
      }
      paintRef.current = null;
      setPaintPreviewCells([]);
      return;
    }

    const drag = dragRef.current;
    if (!drag || drag.id !== event.pointerId) return;
    suppressClickRef.current = drag.moved;
    if (!drag.moved) {
      moveHandledRef.current = moveSelectedToCell(cellFromPointer(event));
    }
    dragRef.current = null;
  }

  function pointerCancel(event: PointerEvent<HTMLDivElement>) {
    pointersRef.current.delete(event.pointerId);
    pinchRef.current = null;
    if (paintRef.current?.id === event.pointerId) {
      paintRef.current = null;
      setPaintPreviewCells([]);
    }
    if (tilePaintRef.current?.id === event.pointerId) {
      tilePaintRef.current = null;
      clearTilePaintPreview();
    }
    if (dragRef.current?.id === event.pointerId) dragRef.current = null;
  }

  function undoTerrain() {
    const entry = undoStack.at(-1);
    if (!entry) return;
    setUndoStack((current) => current.slice(0, -1));
    setRedoStack((current) => [...current, entry]);
    if (entry.action === 'add') onTerrainRemove(entry.cells);
    else onTerrainAdd(entry.cells);
  }

  function redoTerrain() {
    const entry = redoStack.at(-1);
    if (!entry) return;
    setRedoStack((current) => current.slice(0, -1));
    setUndoStack((current) => [...current, entry]);
    if (entry.action === 'add') onTerrainAdd(entry.cells);
    else onTerrainRemove(entry.cells);
  }

  return (
    <section className="surface overflow-hidden rounded-2xl">
      <div className="flex flex-wrap items-center justify-between gap-3 border-b border-white/[0.07] p-3">
        <div>
          <p className="eyebrow">Live encounter</p>
          <h2 className="font-black">Battlefield</h2>
        </div>
        <div className="flex flex-wrap items-center gap-1.5">
          {canEditMap && (
            <>
              <Button variant={mode === 'move' ? 'teal' : 'secondary'} className="px-3 py-2 text-xs" onClick={() => chooseMode('move')}><LocateFixed className="mr-2 inline" size={14} /> Move</Button>
              <Button variant={mode === 'border' ? 'teal' : 'secondary'} className="px-3 py-2 text-xs" onClick={() => chooseMode('border')}><Square className="mr-2 inline" size={14} /> Border</Button>
              <Button variant={mode === 'paint' ? 'teal' : 'secondary'} className="px-3 py-2 text-xs" onClick={() => chooseMode('paint')}><Brush className="mr-2 inline" size={14} /> Paint Tiles</Button>
              {mode === 'border' && (
                <span className="flex rounded-xl border border-[var(--line)] bg-black/20 p-1">
                  <Button variant={borderBrush === 'draw' ? 'teal' : 'ghost'} className="px-3 py-2 text-xs" onClick={() => setBorderBrush('draw')}><Pencil className="mr-1 inline" size={13} /> Draw</Button>
                  <Button variant={borderBrush === 'fill' ? 'teal' : 'ghost'} className="px-3 py-2 text-xs" onClick={() => setBorderBrush('fill')}><PaintBucket className="mr-1 inline" size={13} /> Fill</Button>
                </span>
              )}
              <Button className="p-2.5" onClick={undoTerrain} disabled={!undoStack.length} aria-label="Undo terrain"><RotateCcw size={16} /></Button>
              <Button className="p-2.5" onClick={redoTerrain} disabled={!redoStack.length} aria-label="Redo terrain"><RotateCw size={16} /></Button>
              <Button variant="danger" className="p-2.5" onClick={() => { setUndoStack((current) => [...current, { action: 'remove', cells: terrain.map((cell) => ({ x: cell.x, y: cell.y })) }]); setRedoStack([]); onTerrainClear(); }} disabled={!terrain.length} aria-label="Delete all terrain"><Trash2 size={16} /></Button>
              {mode === 'paint' && (
                <span className="flex flex-wrap items-center gap-1 rounded-xl border border-[var(--line)] bg-black/20 p-1.5" aria-label="Tile paint colors">
                  {TILE_PAINT_PRESETS.map((preset) => {
                    const selected = paintColor === preset.color;
                    return (
                      <button
                        key={preset.name}
                        type="button"
                        title={preset.name}
                        aria-label={`${preset.name} tile paint`}
                        aria-pressed={selected}
                        onClick={() => setPaintColor(preset.color)}
                        className={`grid h-7 w-7 place-items-center rounded-lg border transition ${selected ? 'scale-110 border-[var(--paper)] shadow-[0_0_0_2px_rgba(209,168,91,0.5)]' : 'border-white/20 hover:border-white/60'}`}
                        style={{ backgroundColor: preset.color }}
                      >
                        {selected && <Check size={14} strokeWidth={3} className={preset.name === 'White' || preset.name === 'Yellow' ? 'text-black' : 'text-white'} />}
                      </button>
                    );
                  })}
                  <label className="relative grid h-7 w-7 cursor-pointer place-items-center overflow-hidden rounded-lg border border-white/25" title="Custom tile color">
                    <input className="absolute inset-0 h-full w-full cursor-pointer opacity-0" type="color" value={paintColor} onChange={(event) => setPaintColor(event.target.value.toLowerCase())} aria-label="Custom tile paint color" />
                    <span className="absolute inset-0" style={{ background: `conic-gradient(#d94747, #e4bd45, #50a45c, #4892d0, #8258b8, #d94747)` }} />
                    <Palette className="relative z-10 text-white drop-shadow-md" size={15} />
                  </label>
                  <span className="ml-1 flex items-center gap-2 rounded-lg border border-white/10 bg-black/30 px-2 py-1 text-[10px] font-black uppercase text-[var(--muted)]">
                    <span className="h-4 w-4 rounded border border-white/30" style={{ backgroundColor: paintColor }} />
                    {paintColor}
                  </span>
                  <Button variant="danger" className="ml-1 px-2.5 py-1.5 text-[10px]" disabled={!tilePaint.length} onClick={() => setConfirmClearPaint(true)}><Trash2 className="mr-1 inline" size={13} /> Clear All Paint</Button>
                </span>
              )}
            </>
          )}
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
        onPointerCancel={pointerCancel}
        onWheel={(event) => {
          if (!event.ctrlKey) return;
          event.preventDefault();
          setZoomValue(zoomRef.current - event.deltaY * 0.001);
        }}
      >
        <div ref={mapRef} className="absolute left-0 top-0 origin-top-left will-change-transform" style={{ transform: `translate3d(${panRef.current.x}px, ${panRef.current.y}px, 0) scale(${zoom})` }}>
          <div className="map-grid-bg relative rounded-lg" style={{ width: size.width, height: size.height, backgroundSize: `${CELL_SIZE}px ${CELL_SIZE}px` }} onClick={clickMap}>
            <canvas
              ref={tilePaintCanvasRef}
              width={battle.gridWidth}
              height={battle.gridHeight}
              className="pointer-events-none absolute inset-0 z-0 h-full w-full opacity-[0.82] [image-rendering:pixelated]"
              aria-hidden="true"
            />
            <canvas
              ref={tilePaintPreviewCanvasRef}
              width={battle.gridWidth}
              height={battle.gridHeight}
              className="pointer-events-none absolute inset-0 z-[1] h-full w-full opacity-[0.82] [image-rendering:pixelated]"
              aria-hidden="true"
            />
            {terrain.map((cell) => (
              <span
                key={cell.id}
                className="pointer-events-none absolute z-10 rounded-md border border-[#d1a85b55] bg-[#704225]"
                style={{ left: cell.x * CELL_SIZE + 4, top: cell.y * CELL_SIZE + 4, width: CELL_SIZE - 8, height: CELL_SIZE - 8 }}
              />
            ))}
            {paintPreviewCells.map((cell) => (
              <span
                key={`${cell.x}:${cell.y}`}
                className="pointer-events-none absolute z-10 rounded-md border border-[#f2c879] bg-[#9a5a2f]/80 shadow-[0_0_14px_rgba(209,168,91,0.28)]"
                style={{ left: cell.x * CELL_SIZE + 4, top: cell.y * CELL_SIZE + 4, width: CELL_SIZE - 8, height: CELL_SIZE - 8 }}
              />
            ))}
            <span className="map-grid-lines pointer-events-none absolute inset-0 z-20 rounded-lg" style={{ backgroundSize: `${CELL_SIZE}px ${CELL_SIZE}px` }} aria-hidden="true" />
            {tokens.map((token) => (
              <BattleToken key={token.id} token={token} selected={token.id === selectedId} mine={viewingCharacterId ? token.characterId === viewingCharacterId : token.character?.ownerUserId === profile.id} onSelect={onSelect} />
            ))}
          </div>
        </div>
        <div className="pointer-events-none absolute bottom-3 left-3 right-3 flex justify-center">
          <div className="rounded-full border border-white/10 bg-[#0d1110dc] px-4 py-2 text-center text-[11px] font-bold text-[var(--muted)]">
            {canEditMap && mode === 'border'
              ? borderBrush === 'fill' ? 'Fill mode: tap a connected open region to block it' : 'Border mode: tap or drag cells to make blocked terrain'
              : canEditMap && mode === 'paint'
                ? 'Paint Tiles: tap or drag across the grid; choose Move to pan'
                : canEditMap && selectedId ? 'Tap an open square to move the selected token' : 'Drag to pan; pinch or Ctrl-wheel to zoom'}
          </div>
        </div>
      </div>
      {confirmClearPaint && (
        <Modal title="Clear all tile paint?" onClose={() => setConfirmClearPaint(false)}>
          <p className="text-sm font-bold leading-6 text-[var(--muted)]">This removes every painted tile from the active battlefield. Borders, tokens, positions, grid settings, and all other battle data stay exactly as they are.</p>
          <div className="mt-5 flex justify-end gap-2">
            <Button variant="secondary" onClick={() => setConfirmClearPaint(false)}>Cancel</Button>
            <Button variant="danger" onClick={() => { setConfirmClearPaint(false); onTilePaintClear(); }}><Trash2 className="mr-2 inline" size={15} /> Clear All Paint</Button>
          </div>
        </Modal>
      )}
    </section>
  );
}
