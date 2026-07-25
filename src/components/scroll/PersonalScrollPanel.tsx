'use client';

import { useCallback, useEffect, useMemo, useRef, useState, type PointerEvent, type ReactNode } from 'react';
import { AlignCenter, AlignLeft, AlignRight, Bold, Brush, Eraser, Heading1, Heading2, Italic, List, ListOrdered, Loader2, Quote, Redo2, RotateCcw, Type, Underline, Undo2 } from 'lucide-react';
import { Button } from '@/components/ui/Button';
import { Card } from '@/components/ui/Card';
import { normalizePersonalScroll } from '@/features/scroll/data';

type DrawTool = 'brush' | 'eraser';

const CANVAS_WIDTH = 1200;
const CANVAS_HEIGHT = 1600;
const EMPTY_SCROLL = '<p><br></p>';
const ALLOWED_SCROLL_TAGS = new Set(['B', 'BLOCKQUOTE', 'BR', 'DIV', 'EM', 'FONT', 'H2', 'H3', 'I', 'LI', 'OL', 'P', 'SPAN', 'STRONG', 'U', 'UL']);
const ALLOWED_TEXT_ALIGN = new Set(['center', 'left', 'right']);

function clamp(value: number, min: number, max: number) {
  return Math.max(min, Math.min(max, value));
}

function canvasPoint(canvas: HTMLCanvasElement, event: PointerEvent<HTMLCanvasElement>) {
  const rect = canvas.getBoundingClientRect();
  return {
    x: ((event.clientX - rect.left) / rect.width) * CANVAS_WIDTH,
    y: ((event.clientY - rect.top) / rect.height) * CANVAS_HEIGHT
  };
}

function ToolbarButton({ active, label, onClick, children }: { active?: boolean; label: string; onClick: () => void; children: ReactNode }) {
  return (
    <button
      type="button"
      onMouseDown={(event) => event.preventDefault()}
      onClick={onClick}
      className={`rounded-xl border px-3 py-2 transition active:scale-95 ${active ? 'border-[var(--brass)] bg-[var(--brass)] text-[#1b0f06]' : 'border-[var(--line)] bg-black/20 text-[var(--paper)]'}`}
      aria-label={label}
      title={label}
    >
      {children}
    </button>
  );
}

function sanitizeScrollHtml(html: string) {
  const template = document.createElement('template');
  template.innerHTML = html || EMPTY_SCROLL;

  function sanitizeChild(node: ChildNode) {
    if (node.nodeType === Node.TEXT_NODE) return;
    if (node.nodeType !== Node.ELEMENT_NODE) {
      node.remove();
      return;
    }

    const element = node as HTMLElement;
    for (const child of Array.from(element.childNodes)) sanitizeChild(child);

    if (!ALLOWED_SCROLL_TAGS.has(element.tagName)) {
      element.replaceWith(...Array.from(element.childNodes));
      return;
    }

    const color = element.style.color || element.getAttribute('color') || '';
    const textAlign = element.style.textAlign || '';
    for (const attribute of Array.from(element.attributes)) element.removeAttribute(attribute.name);
    if (color && CSS.supports('color', color)) element.style.color = color;
    if (ALLOWED_TEXT_ALIGN.has(textAlign)) element.style.textAlign = textAlign;
  }

  for (const child of Array.from(template.content.childNodes)) sanitizeChild(child);
  const sanitized = template.innerHTML.trim();
  return sanitized.length ? sanitized : EMPTY_SCROLL;
}

export function PersonalScrollPanel() {
  const editorRef = useRef<HTMLDivElement | null>(null);
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const saveTimerRef = useRef<number | null>(null);
  const latestHtmlRef = useRef(EMPTY_SCROLL);
  const latestDrawingRef = useRef('');
  const drawingRef = useRef(false);
  const lastPointRef = useRef<{ x: number; y: number } | null>(null);
  const undoRef = useRef<string[]>([]);
  const redoRef = useRef<string[]>([]);

  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [mode, setMode] = useState<'text' | 'stylus'>('text');
  const [tool, setTool] = useState<DrawTool>('brush');
  const [inkColor, setInkColor] = useState('#3a1f11');
  const [inkSize, setInkSize] = useState(5);
  const [undoCount, setUndoCount] = useState(0);
  const [redoCount, setRedoCount] = useState(0);

  const canUndo = undoCount > 0;
  const canRedo = redoCount > 0;

  const updateHistoryState = useCallback(() => {
    setUndoCount(undoRef.current.length);
    setRedoCount(redoRef.current.length);
  }, []);

  const captureCanvas = useCallback(() => {
    const canvas = canvasRef.current;
    if (!canvas) return '';
    return canvas.toDataURL('image/png');
  }, []);

  const drawImageData = useCallback((dataUrl: string) => {
    const canvas = canvasRef.current;
    const context = canvas?.getContext('2d');
    if (!canvas || !context) return;

    context.clearRect(0, 0, CANVAS_WIDTH, CANVAS_HEIGHT);
    if (!dataUrl) return;

    const image = new Image();
    image.onload = () => {
      context.clearRect(0, 0, CANVAS_WIDTH, CANVAS_HEIGHT);
      context.drawImage(image, 0, 0, CANVAS_WIDTH, CANVAS_HEIGHT);
    };
    image.src = dataUrl;
  }, []);

  const save = useCallback(async () => {
    try {
      setError('');
      latestHtmlRef.current = sanitizeScrollHtml(latestHtmlRef.current);
      const payload = {
        contentHtml: latestHtmlRef.current || EMPTY_SCROLL,
        drawingDataUrl: latestDrawingRef.current
      };
      const response = await fetch('/api/scroll', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      });
      if (!response.ok) {
        const data = await response.json().catch(() => ({}));
        throw new Error(String(data.error ?? 'Personal Scroll could not be saved.'));
      }
    } catch (saveError) {
      setError(saveError instanceof Error ? saveError.message : 'Personal Scroll could not be saved.');
    }
  }, []);

  const queueSave = useCallback(() => {
    if (saveTimerRef.current) window.clearTimeout(saveTimerRef.current);
    saveTimerRef.current = window.setTimeout(() => {
      saveTimerRef.current = null;
      void save();
    }, 700);
  }, [save]);

  useEffect(() => {
    let alive = true;

    async function load() {
      try {
        setLoading(true);
        setError('');
        const response = await fetch('/api/scroll', { cache: 'no-store' });
        if (!response.ok) {
          const data = await response.json().catch(() => ({}));
          throw new Error(String(data.error ?? 'Personal Scroll could not be opened.'));
        }
        const scroll = normalizePersonalScroll(await response.json().catch(() => ({})));
        if (!alive) return;

        const html = sanitizeScrollHtml(scroll.contentHtml || EMPTY_SCROLL);
        latestHtmlRef.current = html;
        latestDrawingRef.current = scroll.drawingDataUrl;
        if (editorRef.current) editorRef.current.innerHTML = html;
        drawImageData(scroll.drawingDataUrl);
      } catch (loadError) {
        if (alive) setError(loadError instanceof Error ? loadError.message : 'Personal Scroll could not be opened.');
      } finally {
        if (alive) setLoading(false);
      }
    }

    void load();
    return () => {
      alive = false;
      if (saveTimerRef.current) window.clearTimeout(saveTimerRef.current);
    };
  }, [drawImageData]);

  const textTools = useMemo(
    () => [
      { label: 'Bold', icon: Bold, action: () => document.execCommand('bold') },
      { label: 'Italic', icon: Italic, action: () => document.execCommand('italic') },
      { label: 'Underline', icon: Underline, action: () => document.execCommand('underline') },
      { label: 'Header 1', icon: Heading1, action: () => document.execCommand('formatBlock', false, 'h2') },
      { label: 'Header 2', icon: Heading2, action: () => document.execCommand('formatBlock', false, 'h3') },
      { label: 'Bullets', icon: List, action: () => document.execCommand('insertUnorderedList') },
      { label: 'Numbers', icon: ListOrdered, action: () => document.execCommand('insertOrderedList') },
      { label: 'Quote', icon: Quote, action: () => document.execCommand('formatBlock', false, 'blockquote') },
      { label: 'Left', icon: AlignLeft, action: () => document.execCommand('justifyLeft') },
      { label: 'Center', icon: AlignCenter, action: () => document.execCommand('justifyCenter') },
      { label: 'Right', icon: AlignRight, action: () => document.execCommand('justifyRight') },
      { label: 'Clear style', icon: RotateCcw, action: () => document.execCommand('removeFormat') }
    ],
    []
  );

  function runTextTool(action: () => void) {
    editorRef.current?.focus();
    action();
    latestHtmlRef.current = sanitizeScrollHtml(editorRef.current?.innerHTML || EMPTY_SCROLL);
    queueSave();
  }

  function applyTextColor(color: string) {
    editorRef.current?.focus();
    document.execCommand('foreColor', false, color);
    latestHtmlRef.current = sanitizeScrollHtml(editorRef.current?.innerHTML || EMPTY_SCROLL);
    queueSave();
  }

  function handleInput() {
    latestHtmlRef.current = sanitizeScrollHtml(editorRef.current?.innerHTML || EMPTY_SCROLL);
    queueSave();
  }

  function handlePaste(event: React.ClipboardEvent<HTMLDivElement>) {
    event.preventDefault();
    const text = event.clipboardData.getData('text/plain');
    document.execCommand('insertText', false, text);
    handleInput();
  }

  function pushUndoSnapshot() {
    undoRef.current = [...undoRef.current.slice(-29), captureCanvas()];
    redoRef.current = [];
    updateHistoryState();
  }

  function beginDrawing(event: PointerEvent<HTMLCanvasElement>) {
    if (mode !== 'stylus') return;
    const canvas = canvasRef.current;
    if (!canvas) return;
    event.preventDefault();
    canvas.setPointerCapture(event.pointerId);
    pushUndoSnapshot();
    drawingRef.current = true;
    lastPointRef.current = canvasPoint(canvas, event);
  }

  function continueDrawing(event: PointerEvent<HTMLCanvasElement>) {
    if (!drawingRef.current || mode !== 'stylus') return;
    const canvas = canvasRef.current;
    const context = canvas?.getContext('2d');
    const lastPoint = lastPointRef.current;
    if (!canvas || !context || !lastPoint) return;

    event.preventDefault();
    const nextPoint = canvasPoint(canvas, event);
    context.save();
    context.lineCap = 'round';
    context.lineJoin = 'round';
    context.lineWidth = clamp(inkSize, 1, 42);
    context.globalCompositeOperation = tool === 'eraser' ? 'destination-out' : 'source-over';
    context.strokeStyle = tool === 'eraser' ? 'rgba(0,0,0,1)' : inkColor;
    context.beginPath();
    context.moveTo(lastPoint.x, lastPoint.y);
    context.lineTo(nextPoint.x, nextPoint.y);
    context.stroke();
    context.restore();
    lastPointRef.current = nextPoint;
  }

  function endDrawing(event: PointerEvent<HTMLCanvasElement>) {
    if (!drawingRef.current) return;
    const canvas = canvasRef.current;
    drawingRef.current = false;
    lastPointRef.current = null;
    if (canvas?.hasPointerCapture(event.pointerId)) canvas.releasePointerCapture(event.pointerId);
    latestDrawingRef.current = captureCanvas();
    updateHistoryState();
    queueSave();
  }

  function undoDrawing() {
    if (!canUndo) return;
    const current = captureCanvas();
    const previous = undoRef.current.pop() ?? '';
    redoRef.current = [...redoRef.current, current];
    latestDrawingRef.current = previous;
    drawImageData(previous);
    updateHistoryState();
    queueSave();
  }

  function redoDrawing() {
    if (!canRedo) return;
    const current = captureCanvas();
    const next = redoRef.current.pop() ?? '';
    undoRef.current = [...undoRef.current, current];
    latestDrawingRef.current = next;
    drawImageData(next);
    updateHistoryState();
    queueSave();
  }

  function clearDrawing() {
    pushUndoSnapshot();
    latestDrawingRef.current = '';
    drawImageData('');
    queueSave();
  }

  return (
    <div className="grid gap-4">
      <Card className="overflow-hidden">
        <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <div className="text-center sm:text-left">
            <p className="eyebrow">Private notes</p>
            <h2 className="scroll-title mt-1 text-4xl font-black">Personal Scroll</h2>
          </div>

          <div className="flex flex-wrap justify-center gap-2">
            <Button variant={mode === 'text' ? 'primary' : 'secondary'} className="flex items-center gap-2" onClick={() => setMode('text')}>
              <Type size={16} /> Text
            </Button>
            <Button variant={mode === 'stylus' ? 'teal' : 'secondary'} className="flex items-center gap-2" onClick={() => setMode('stylus')}>
              <Brush size={16} /> Stylus mode
            </Button>
          </div>
        </div>

        {error && <div className="mt-4 rounded-xl border border-[#d2735855] bg-[#d2735814] p-3 text-sm text-[var(--red)]">{error}</div>}

        <div className="thin-scrollbar mt-4 flex gap-2 overflow-x-auto rounded-2xl border border-[var(--line)] bg-black/20 p-2">
          {mode === 'text' ? (
            <>
              {textTools.map(({ label, icon: Icon, action }) => (
                <ToolbarButton key={label} label={label} onClick={() => runTextTool(action)}>
                  <Icon size={16} />
                </ToolbarButton>
              ))}
              <label className="flex shrink-0 items-center gap-2 rounded-xl border border-[var(--line)] bg-black/20 px-3 py-2 text-xs font-black uppercase tracking-wide text-[var(--muted)]">
                Color
                <input type="color" className="h-7 w-9 cursor-pointer rounded border border-[var(--line)] bg-transparent" onChange={(event) => applyTextColor(event.target.value)} />
              </label>
            </>
          ) : (
            <>
              <ToolbarButton active={tool === 'brush'} label="Brush" onClick={() => setTool('brush')}>
                <Brush size={16} />
              </ToolbarButton>
              <ToolbarButton active={tool === 'eraser'} label="Eraser" onClick={() => setTool('eraser')}>
                <Eraser size={16} />
              </ToolbarButton>
              <ToolbarButton label="Undo drawing" onClick={undoDrawing}>
                <Undo2 size={16} />
              </ToolbarButton>
              <ToolbarButton label="Redo drawing" onClick={redoDrawing}>
                <Redo2 size={16} />
              </ToolbarButton>
              <ToolbarButton label="Clear drawing layer" onClick={clearDrawing}>
                <RotateCcw size={16} />
              </ToolbarButton>
              <label className="flex shrink-0 items-center gap-2 rounded-xl border border-[var(--line)] bg-black/20 px-3 py-2 text-xs font-black uppercase tracking-wide text-[var(--muted)]">
                Ink
                <input type="color" value={inkColor} className="h-7 w-9 cursor-pointer rounded border border-[var(--line)] bg-transparent" onChange={(event) => setInkColor(event.target.value)} />
              </label>
              <label className="flex min-w-44 shrink-0 items-center gap-2 rounded-xl border border-[var(--line)] bg-black/20 px-3 py-2 text-xs font-black uppercase tracking-wide text-[var(--muted)]">
                Size
                <input type="range" min="1" max="42" value={inkSize} onChange={(event) => setInkSize(Number(event.target.value))} className="w-28 accent-[var(--brass)]" />
                <span className="w-6 text-right">{inkSize}</span>
              </label>
            </>
          )}
        </div>
      </Card>

      <Card className="relative overflow-hidden p-2 sm:p-3">
        {loading && (
          <div className="absolute inset-0 z-10 grid place-items-center bg-[#160c05]/55 backdrop-blur-sm">
            <Loader2 className="animate-spin text-[var(--brass)]" size={28} />
          </div>
        )}

        <div className="scroll-paper relative mx-auto min-h-[72dvh] overflow-hidden rounded-[1.6rem] p-5 sm:p-10">
          <div
            ref={editorRef}
            contentEditable={mode === 'text'}
            suppressContentEditableWarning
            spellCheck
            onInput={handleInput}
            onPaste={handlePaste}
            className="scroll-editor relative z-[1] min-h-[68dvh] outline-none"
            aria-label="Personal Scroll editor"
          />

          <canvas
            ref={canvasRef}
            width={CANVAS_WIDTH}
            height={CANVAS_HEIGHT}
            onPointerDown={beginDrawing}
            onPointerMove={continueDrawing}
            onPointerUp={endDrawing}
            onPointerCancel={endDrawing}
            className={`absolute inset-0 z-[2] h-full w-full touch-none ${mode === 'stylus' ? 'pointer-events-auto cursor-crosshair' : 'pointer-events-none'}`}
            aria-label="Personal Scroll drawing layer"
          />
        </div>
      </Card>
    </div>
  );
}
