'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { Loader2, RefreshCw, Save, Search, Waypoints, X } from 'lucide-react';
import { Button } from '@/components/ui/Button';
import { Card } from '@/components/ui/Card';
import { TextField } from '@/components/ui/Field';
import {
  generateCaveMap,
  normalizeCavesPayload,
  type CaveMap,
  type CaveMapEdge,
  type CaveMapNode,
  type CaveRecord
} from '@/features/exploration/caves';

function caveTitle(cave: CaveRecord) {
  return cave.nickname ? `Cave ${cave.number} - ${cave.nickname}` : `Cave ${cave.number}`;
}

function difficultyTone(difficulty: number) {
  if (difficulty <= 1) return 'border-[#56e2c2]/35 bg-[#56e2c2]/10 text-[#56e2c2]';
  if (difficulty === 2) return 'border-[#8fe388]/35 bg-[#8fe388]/10 text-[#8fe388]';
  if (difficulty === 3) return 'border-[var(--brass)]/45 bg-[var(--brass)]/10 text-[var(--brass)]';
  if (difficulty === 4) return 'border-[#f08a4b]/40 bg-[#f08a4b]/10 text-[#f08a4b]';
  return 'border-[var(--red)]/45 bg-[var(--red)]/10 text-[var(--red)]';
}

function edgeColor(edge: CaveMapEdge) {
  if (edge.type === 'secret') return 'rgba(244, 169, 112, 0.76)';
  return 'rgba(185, 238, 211, 0.9)';
}

function nodeFill(node: CaveMapNode) {
  if (node.type === 'start') return '#56e2c2';
  if (node.type === 'boss') return '#f26d6d';
  if (node.type === 'secret') return '#56e2c2';
  return '#f5d37e';
}

function cavePath(edge: CaveMapEdge) {
  const [first, ...rest] = edge.points;
  if (!first) return '';
  if (rest.length === 1) {
    const end = rest[0];
    const controlX = (first.x + end.x) / 2;
    const controlY = (first.y + end.y) / 2 - 18;
    return `M ${first.x} ${first.y} Q ${controlX} ${controlY} ${end.x} ${end.y}`;
  }
  return rest.reduce((path, point, index) => {
    const previous = index === 0 ? first : rest[index - 1];
    const controlX = (previous.x + point.x) / 2;
    const controlY = previous.y + (point.y - previous.y) * 0.22;
    return `${path} Q ${controlX} ${controlY} ${point.x} ${point.y}`;
  }, `M ${first.x} ${first.y}`);
}

function difficultyBadgeFill(difficulty = 1) {
  if (difficulty <= 1) return 'rgba(86, 226, 194, 0.22)';
  if (difficulty === 2) return 'rgba(143, 227, 136, 0.2)';
  if (difficulty === 3) return 'rgba(245, 211, 126, 0.22)';
  if (difficulty === 4) return 'rgba(240, 138, 75, 0.22)';
  return 'rgba(242, 109, 109, 0.24)';
}

function difficultyBadgeStroke(difficulty = 1) {
  if (difficulty <= 1) return '#56e2c2';
  if (difficulty === 2) return '#8fe388';
  if (difficulty === 3) return '#f5d37e';
  if (difficulty === 4) return '#f08a4b';
  return '#f26d6d';
}

function CaveMapView({ cave }: { cave: CaveRecord }) {
  const map = useMemo(() => generateCaveMap(cave), [cave]);

  return (
    <div className="overflow-hidden rounded-2xl border border-[var(--line)] bg-black/20">
      <svg
        role="img"
        aria-label={`${caveTitle(cave)} tunnel map`}
        viewBox={`0 0 ${map.width} ${map.height}`}
        className="h-auto w-full min-w-[68rem]"
      >
        <rect width={map.width} height={map.height} fill="rgba(7, 14, 14, 0.72)" />
        <MapGrid map={map} />
        {map.edges.map((edge) => (
          <g key={edge.id}>
            <path
              d={cavePath(edge)}
              fill="none"
              stroke="rgba(0, 0, 0, 0.48)"
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={edge.type === 'secret' ? 17 : 31}
            />
            <path
              d={cavePath(edge)}
              fill="none"
              stroke={edgeColor(edge)}
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={edge.type === 'secret' ? 7 : 15}
            />
          </g>
        ))}
        {map.nodes.map((node) => <MapNode key={node.id} node={node} />)}
      </svg>
    </div>
  );
}

function MapGrid({ map }: { map: CaveMap }) {
  return (
    <g opacity="0.18">
      {Array.from({ length: Math.ceil(map.width / 80) }, (_, index) => (
        <line key={`v-${index}`} x1={index * 80} y1={0} x2={index * 80} y2={map.height} stroke="#f5d37e" strokeWidth="1" />
      ))}
      {Array.from({ length: Math.ceil(map.height / 80) }, (_, index) => (
        <line key={`h-${index}`} x1={0} y1={index * 80} x2={map.width} y2={index * 80} stroke="#f5d37e" strokeWidth="1" />
      ))}
    </g>
  );
}

function MapNode({ node }: { node: CaveMapNode }) {
  if (node.type === 'label') {
    const badgeWidth = 188;
    const badgeHeight = 50;
    return (
      <g>
        <rect
          x={node.x - badgeWidth / 2}
          y={node.y - badgeHeight / 2}
          width={badgeWidth}
          height={badgeHeight}
          rx="16"
          fill={difficultyBadgeFill(node.difficulty)}
          stroke={difficultyBadgeStroke(node.difficulty)}
          strokeWidth="3"
        />
        <text x={node.x} y={node.y - 3} textAnchor="middle" className="fill-[var(--paper)] text-[18px] font-black">
          Tunnel {node.tunnelIndex}
        </text>
        <text x={node.x} y={node.y + 17} textAnchor="middle" fill={difficultyBadgeStroke(node.difficulty)} className="text-[18px] font-black">
          Difficulty {node.difficulty}
        </text>
      </g>
    );
  }

  if (node.type === 'secret') {
    const secretNumber = node.id.replace('secret-', 'S');
    return (
      <g>
        <rect x={node.x - 24} y={node.y - 18} width="48" height="36" rx="12" fill="rgba(244, 169, 112, 0.2)" stroke="#f4a970" strokeWidth="3" />
        <text x={node.x} y={node.y + 6} textAnchor="middle" className="fill-[#ffe7b0] text-[16px] font-black">
          {secretNumber}
        </text>
      </g>
    );
  }

  if (node.type === 'boss') {
    return (
      <g>
        <rect x={node.x - 45} y={node.y - 21} width="90" height="42" rx="13" fill="rgba(242, 109, 109, 0.18)" stroke={nodeFill(node)} strokeWidth="3" />
        <text x={node.x} y={node.y + 7} textAnchor="middle" className="fill-[var(--paper)] text-[18px] font-black">
          {node.label}
        </text>
      </g>
    );
  }

  return (
    <g>
      <circle cx={node.x} cy={node.y} r={node.type === 'start' ? 22 : 16} fill="rgba(245, 211, 126, 0.16)" stroke={nodeFill(node)} strokeWidth="4" />
      <text x={node.type === 'start' ? node.x + 34 : node.x} y={node.y + (node.type === 'start' ? 7 : 34)} textAnchor={node.type === 'start' ? 'start' : 'middle'} className="fill-[var(--paper)] text-[18px] font-black">
        {node.label}
      </text>
    </g>
  );
}

export function CavesPanel() {
  const [caves, setCaves] = useState<CaveRecord[]>([]);
  const [selectedNumber, setSelectedNumber] = useState(1);
  const [search, setSearch] = useState('');
  const [nicknameDrafts, setNicknameDrafts] = useState<Record<number, string>>({});
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const selectedCave = caves.find((cave) => cave.number === selectedNumber) ?? caves[0] ?? null;
  const filteredCaves = useMemo(() => {
    const term = search.trim().toLowerCase();
    if (!term) return caves;
    return caves.filter((cave) => [
      `cave ${cave.number}`,
      cave.nickname ?? '',
      cave.creatureType,
      cave.layoutType,
      cave.notes ?? '',
      cave.tunnelDifficulties.join(' ')
    ].join(' ').toLowerCase().includes(term));
  }, [caves, search]);

  const loadCaves = useCallback(async () => {
    setError('');
    try {
      const response = await fetch('/api/exploration/caves', { cache: 'no-store' });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(body.error ?? 'Caves could not be loaded.');
      const normalized = normalizeCavesPayload(body);
      setCaves(normalized);
      setNicknameDrafts(Object.fromEntries(normalized.map((cave) => [cave.number, cave.nickname ?? ''])));
      setSelectedNumber((current) => normalized.some((cave) => cave.number === current) ? current : normalized[0]?.number ?? 1);
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : 'Caves could not be loaded.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void loadCaves();
  }, [loadCaves]);

  async function saveNickname(cave: CaveRecord, nickname: string) {
    setSaving(true);
    setError('');
    try {
      const response = await fetch(`/api/exploration/caves/${cave.number}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ nickname })
      });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(body.error ?? 'Cave nickname could not be saved.');
      const updated = body.cave ? normalizeCavesPayload({ caves: [body.cave] })[0] : { ...cave, nickname: nickname.trim() || undefined };
      setCaves((current) => current.map((entry) => entry.number === cave.number ? updated : entry));
      setNicknameDrafts((current) => ({ ...current, [cave.number]: updated.nickname ?? '' }));
    } catch (saveError) {
      setError(saveError instanceof Error ? saveError.message : 'Cave nickname could not be saved.');
    } finally {
      setSaving(false);
    }
  }

  if (loading) {
    return <Card><div className="grid h-32 place-items-center text-[var(--muted)]"><Loader2 className="animate-spin" /></div></Card>;
  }

  return (
    <div className="grid min-w-0 gap-4 xl:grid-cols-[26rem_minmax(0,1fr)]">
      <Card className="xl:sticky xl:top-4 xl:max-h-[calc(100dvh-2rem)] xl:overflow-y-auto">
        <div className="flex items-center justify-between gap-3">
          <div>
            <p className="eyebrow">Exploration Tool</p>
            <h2 className="mt-1 flex items-center gap-2 text-2xl font-black"><Waypoints className="text-[var(--brass)]" /> Caves</h2>
          </div>
          <Button variant="secondary" className="p-3" onClick={loadCaves} aria-label="Refresh caves"><RefreshCw size={16} /></Button>
        </div>
        {error && <div className="mt-3 rounded-2xl border border-[var(--red)]/40 bg-[var(--red)]/10 p-3 text-sm text-[var(--red)]">{error}</div>}
        <label className="relative mt-4 block">
          <Search className="pointer-events-none absolute left-4 top-1/2 -translate-y-1/2 text-[var(--muted)]" size={17} />
          <TextField
            value={search}
            onChange={(event) => setSearch(event.target.value)}
            placeholder="Search caves"
            className="pl-11"
          />
        </label>
        <div className="mt-3 grid gap-2">
          {filteredCaves.map((cave) => (
            <button
              key={cave.number}
              type="button"
              onClick={() => setSelectedNumber(cave.number)}
              data-selected={selectedCave?.number === cave.number}
              className="rounded-2xl border border-[var(--line)] bg-black/15 p-3 text-left transition hover:border-[var(--brass)]/60 data-[selected=true]:border-[var(--brass)] data-[selected=true]:bg-[var(--brass)]/10 active:scale-[0.99]"
            >
              <span className="flex items-start justify-between gap-3">
                <span className="min-w-0">
                  <span className="block truncate text-base font-black">{caveTitle(cave)}</span>
                  <span className="mt-1 block text-xs font-black uppercase tracking-wide text-[var(--muted)]">{cave.creatureType} - {cave.layoutType}</span>
                </span>
                <span className="shrink-0 rounded-full border border-[var(--line)] bg-black/25 px-2 py-1 text-xs font-black text-[var(--brass)]">{cave.tunnelCount}T</span>
              </span>
              <span className="mt-2 flex flex-wrap gap-1.5">
                {cave.tunnelDifficulties.map((difficulty, index) => (
                  <span key={`${cave.number}:${index}`} className={`rounded-full border px-2 py-1 text-[10px] font-black ${difficultyTone(difficulty)}`}>
                    T{index + 1}: D{difficulty}
                  </span>
                ))}
              </span>
            </button>
          ))}
        </div>
      </Card>

      {selectedCave && (
        <div className="grid min-w-0 gap-4">
          <Card>
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div>
                <p className="eyebrow">Cave Details</p>
                <h2 className="mt-1 text-3xl font-black">{caveTitle(selectedCave)}</h2>
                {selectedCave.nickname && <p className="mt-1 text-xs font-black uppercase tracking-wide text-[var(--muted)]">Official number: Cave {selectedCave.number}</p>}
              </div>
              <div className="grid grid-cols-2 gap-2 text-xs font-black uppercase tracking-wide text-[var(--muted)] sm:grid-cols-4">
                <span className="rounded-xl border border-[var(--line)] bg-black/15 p-3"><b className="block text-lg text-[var(--paper)]">{selectedCave.tunnelCount}</b> Tunnels</span>
                <span className="rounded-xl border border-[var(--line)] bg-black/15 p-3"><b className="block text-lg text-[var(--paper)]">{selectedCave.secretRoomCount}</b> Secrets</span>
                <span className="rounded-xl border border-[var(--line)] bg-black/15 p-3"><b className="block text-lg text-[var(--paper)]">{selectedCave.creatureType}</b> Type</span>
                <span className="rounded-xl border border-[var(--line)] bg-black/15 p-3"><b className="block text-lg text-[var(--paper)]">{selectedCave.layoutType.replace(' Cave', '')}</b> Shape</span>
              </div>
            </div>
            <div className="mt-4 grid gap-2 rounded-2xl border border-[var(--line)] bg-black/10 p-3 sm:grid-cols-[1fr_auto_auto]">
              <TextField
                value={nicknameDrafts[selectedCave.number] ?? ''}
                onChange={(event) => setNicknameDrafts((current) => ({ ...current, [selectedCave.number]: event.target.value }))}
                placeholder={`Nickname Cave ${selectedCave.number}`}
                maxLength={80}
              />
              <Button variant="primary" disabled={saving} onClick={() => void saveNickname(selectedCave, nicknameDrafts[selectedCave.number] ?? '')}>
                <Save className="mr-2 inline" size={15} /> Save
              </Button>
              <Button variant="secondary" disabled={saving || !(nicknameDrafts[selectedCave.number] ?? '').trim()} onClick={() => void saveNickname(selectedCave, '')}>
                <X className="mr-2 inline" size={15} /> Clear
              </Button>
            </div>
            {selectedCave.notes && <p className="mt-3 rounded-2xl border border-[var(--brass)]/30 bg-[var(--brass)]/10 p-3 text-sm font-bold text-[var(--brass)]">{selectedCave.notes}</p>}
          </Card>

          <Card>
            <div className="rule-title mb-3"><h3 className="text-sm font-black uppercase tracking-wider">Generated Cave Map</h3></div>
            <div className="max-w-full overflow-x-auto pb-2">
              <CaveMapView cave={selectedCave} />
            </div>
          </Card>
        </div>
      )}
    </div>
  );
}
