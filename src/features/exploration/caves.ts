export type CaveCreatureType = 'Beast' | 'Goblin' | 'Hybrid';
export type CaveLayoutType = 'Snaking Cave' | 'Forking Cave' | 'Multi Cave';
export type CaveMapNodeType = 'start' | 'entrance' | 'boss' | 'secret' | 'label';
export type CaveMapEdgeType = 'connector' | 'tunnel' | 'secret';

export type CaveRecord = {
  number: number;
  nickname?: string;
  creatureType: CaveCreatureType;
  layoutType: CaveLayoutType;
  tunnelCount: number;
  secretRoomCount: number;
  tunnelDifficulties: number[];
  notes?: string;
};

export type CaveMapPoint = {
  x: number;
  y: number;
};

export type CaveMapNode = CaveMapPoint & {
  id: string;
  type: CaveMapNodeType;
  label: string;
  tunnelIndex?: number;
  difficulty?: number;
};

export type CaveMapEdge = {
  id: string;
  type: CaveMapEdgeType;
  points: CaveMapPoint[];
  tunnelIndex?: number;
};

export type CaveMap = {
  width: number;
  height: number;
  nodes: CaveMapNode[];
  edges: CaveMapEdge[];
};

type CaveSourceRow = readonly [
  number: number,
  tunnelCount: number,
  creatureType: CaveCreatureType,
  secretRoomCount: number,
  layoutType: CaveLayoutType,
  tunnelDifficulties: readonly number[],
  notes?: string
];

const CAVE_SOURCE_ROWS: CaveSourceRow[] = [
  [1, 5, 'Beast', 2, 'Multi Cave', [4, 5, 4, 2, 4]],
  [2, 3, 'Beast', 1, 'Forking Cave', [2, 3, 4]],
  [3, 4, 'Beast', 1, 'Snaking Cave', [4, 3, 4, 2]],
  [4, 5, 'Beast', 1, 'Multi Cave', [1, 5, 3, 3, 4]],
  [5, 3, 'Beast', 3, 'Forking Cave', [4, 1, 3]],
  [6, 5, 'Beast', 1, 'Snaking Cave', [1, 5, 4, 3, 2]],
  [7, 3, 'Beast', 1, 'Forking Cave', [4, 2, 1]],
  [8, 2, 'Goblin', 2, 'Snaking Cave', [2, 3]],
  [9, 4, 'Goblin', 2, 'Multi Cave', [3, 5, 3, 5]],
  [10, 3, 'Beast', 2, 'Forking Cave', [2, 4, 1]],
  [11, 5, 'Goblin', 3, 'Multi Cave', [1, 4, 1, 1, 5]],
  [12, 4, 'Goblin', 3, 'Forking Cave', [2, 4, 4, 2]],
  [13, 4, 'Goblin', 2, 'Snaking Cave', [1, 5, 4, 5]],
  [14, 2, 'Beast', 1, 'Snaking Cave', [2, 4]],
  [15, 3, 'Goblin', 1, 'Forking Cave', [1, 2, 3]],
  [16, 5, 'Beast', 2, 'Multi Cave', [3, 3, 3, 3, 3], 'Mountain'],
  [17, 4, 'Hybrid', 2, 'Multi Cave', [2, 3, 5, 4]],
  [18, 3, 'Beast', 0, 'Snaking Cave', [1, 2, 2]],
  [19, 5, 'Goblin', 1, 'Forking Cave', [2, 5, 3, 1, 4]],
  [20, 4, 'Beast', 2, 'Snaking Cave', [4, 4, 3, 2]],
  [21, 2, 'Hybrid', 1, 'Forking Cave', [3, 5]],
  [22, 5, 'Beast', 3, 'Multi Cave', [5, 2, 4, 3, 5]],
  [23, 3, 'Goblin', 2, 'Forking Cave', [2, 1, 4]],
  [24, 4, 'Beast', 1, 'Multi Cave', [3, 4, 1, 3]],
  [25, 5, 'Hybrid', 2, 'Snaking Cave', [2, 4, 5, 3, 1]],
  [26, 2, 'Goblin', 0, 'Snaking Cave', [1, 2]],
  [27, 3, 'Beast', 1, 'Forking Cave', [5, 3, 2]],
  [28, 4, 'Hybrid', 3, 'Multi Cave', [4, 2, 5, 3]],
  [29, 5, 'Goblin', 2, 'Multi Cave', [1, 3, 3, 4, 2]],
  [30, 3, 'Beast', 2, 'Snaking Cave', [4, 5, 3]],
  [31, 4, 'Goblin', 1, 'Forking Cave', [2, 2, 1, 4]],
  [32, 5, 'Beast', 1, 'Multi Cave', [3, 5, 4, 4, 2]],
  [33, 2, 'Hybrid', 2, 'Forking Cave', [4, 1]],
  [34, 3, 'Goblin', 0, 'Snaking Cave', [2, 3, 1]],
  [35, 4, 'Beast', 2, 'Multi Cave', [5, 4, 2, 3]],
  [36, 5, 'Hybrid', 3, 'Multi Cave', [3, 1, 5, 4, 5]],
  [37, 3, 'Beast', 1, 'Forking Cave', [1, 4, 2]],
  [38, 4, 'Goblin', 2, 'Snaking Cave', [3, 2, 5, 4]],
  [39, 5, 'Beast', 0, 'Snaking Cave', [2, 2, 3, 4, 1]],
  [40, 2, 'Goblin', 1, 'Forking Cave', [5, 3]],
  [41, 4, 'Hybrid', 1, 'Multi Cave', [1, 4, 2, 5]],
  [42, 3, 'Beast', 3, 'Forking Cave', [3, 5, 4]],
  [43, 5, 'Goblin', 2, 'Multi Cave', [2, 1, 4, 3, 5]],
  [44, 4, 'Beast', 1, 'Snaking Cave', [4, 3, 3, 2]],
  [45, 3, 'Hybrid', 2, 'Forking Cave', [5, 2, 4]],
  [46, 5, 'Beast', 3, 'Multi Cave', [1, 5, 5, 3, 4]],
  [47, 2, 'Beast', 0, 'Snaking Cave', [3, 1]],
  [48, 4, 'Goblin', 3, 'Forking Cave', [2, 4, 5, 1]],
  [49, 5, 'Hybrid', 1, 'Multi Cave', [4, 2, 3, 5, 3]],
  [50, 3, 'Goblin', 1, 'Snaking Cave', [1, 3, 2]],
  [51, 4, 'Beast', 2, 'Multi Cave', [5, 5, 4, 2]],
  [52, 5, 'Goblin', 0, 'Forking Cave', [3, 1, 2, 4, 4]],
  [53, 3, 'Hybrid', 3, 'Multi Cave', [2, 5, 3]],
  [54, 4, 'Beast', 1, 'Snaking Cave', [1, 4, 4, 5]],
  [55, 2, 'Goblin', 2, 'Forking Cave', [2, 5]],
  [56, 5, 'Beast', 2, 'Multi Cave', [3, 4, 2, 1, 5]],
  [57, 4, 'Hybrid', 2, 'Forking Cave', [5, 3, 1, 4]],
  [58, 3, 'Beast', 0, 'Snaking Cave', [2, 2, 4]],
  [59, 5, 'Goblin', 3, 'Multi Cave', [1, 5, 2, 3, 4]],
  [60, 4, 'Beast', 2, 'Snaking Cave', [4, 1, 5, 3]],
  [61, 3, 'Hybrid', 1, 'Forking Cave', [3, 4, 5]],
  [62, 5, 'Beast', 1, 'Multi Cave', [2, 3, 5, 4, 1]],
  [63, 2, 'Goblin', 0, 'Snaking Cave', [1, 4]],
  [64, 4, 'Hybrid', 3, 'Multi Cave', [5, 2, 3, 5]],
  [65, 3, 'Beast', 2, 'Forking Cave', [4, 1, 2]],
  [66, 5, 'Goblin', 1, 'Snaking Cave', [3, 3, 2, 5, 4]],
  [67, 4, 'Beast', 2, 'Multi Cave', [1, 5, 4, 3]],
  [68, 3, 'Hybrid', 0, 'Snaking Cave', [2, 5, 1]],
  [69, 5, 'Beast', 3, 'Multi Cave', [4, 2, 5, 5, 3]],
  [70, 2, 'Goblin', 1, 'Forking Cave', [3, 2]],
  [71, 4, 'Goblin', 2, 'Snaking Cave', [1, 4, 3, 5]],
  [72, 5, 'Hybrid', 2, 'Multi Cave', [2, 5, 1, 4, 3]],
  [73, 3, 'Beast', 1, 'Forking Cave', [5, 3, 4]],
  [74, 4, 'Hybrid', 1, 'Snaking Cave', [3, 2, 4, 1]],
  [75, 5, 'Goblin', 3, 'Multi Cave', [4, 1, 5, 2, 3]],
  [76, 2, 'Beast', 2, 'Forking Cave', [5, 4]],
  [77, 3, 'Goblin', 1, 'Snaking Cave', [2, 1, 3]],
  [78, 4, 'Beast', 3, 'Multi Cave', [4, 5, 2, 5]],
  [79, 5, 'Hybrid', 0, 'Snaking Cave', [1, 3, 2, 4, 5]],
  [80, 4, 'Goblin', 2, 'Forking Cave', [3, 5, 4, 2]]
];

export const CAVE_RECORDS: CaveRecord[] = CAVE_SOURCE_ROWS.map(([number, tunnelCount, creatureType, secretRoomCount, layoutType, tunnelDifficulties, notes]) => ({
  number,
  creatureType,
  layoutType,
  tunnelCount,
  secretRoomCount,
  tunnelDifficulties: [...tunnelDifficulties],
  notes
}));

function seedFor(cave: CaveRecord) {
  return cave.number * 97
    + cave.tunnelCount * 31
    + cave.secretRoomCount * 17
    + cave.tunnelDifficulties.reduce((sum, difficulty, index) => sum + difficulty * (index + 11), 0);
}

function offset(seed: number, step: number, spread: number) {
  return ((seed + step * 37) % (spread * 2 + 1)) - spread;
}

function roundedPoint(point: CaveMapPoint) {
  return { x: Math.round(point.x), y: Math.round(point.y) };
}

export function mergeCaveNicknames(nicknames: Record<number, string>): CaveRecord[] {
  return CAVE_RECORDS.map((cave) => ({
    ...cave,
    nickname: nicknames[cave.number]?.trim() || undefined
  }));
}

export function normalizeCaveRecord(value: unknown): CaveRecord {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  const tunnelDifficulties = Array.isArray(source.tunnelDifficulties)
    ? source.tunnelDifficulties.map((entry) => Number(entry)).filter((entry) => Number.isFinite(entry))
    : [];
  const creatureType = source.creatureType === 'Goblin' || source.creatureType === 'Hybrid' ? source.creatureType : 'Beast';
  const layoutType = source.layoutType === 'Forking Cave' || source.layoutType === 'Multi Cave' ? source.layoutType : 'Snaking Cave';
  return {
    number: Number(source.number ?? 0),
    nickname: String(source.nickname ?? '').trim() || undefined,
    creatureType,
    layoutType,
    tunnelCount: Math.max(0, Number(source.tunnelCount ?? tunnelDifficulties.length)),
    secretRoomCount: Math.max(0, Number(source.secretRoomCount ?? 0)),
    tunnelDifficulties,
    notes: String(source.notes ?? '').trim() || undefined
  };
}

export function normalizeCavesPayload(value: unknown): CaveRecord[] {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  return Array.isArray(source.caves) ? source.caves.map(normalizeCaveRecord).filter((cave) => cave.number > 0) : [];
}

export function generateCaveMap(cave: CaveRecord): CaveMap {
  const seed = seedFor(cave);
  const laneGap = 112;
  const top = 82;
  const width = 960;
  const height = top * 2 + (cave.tunnelCount - 1) * laneGap;
  const midY = top + ((cave.tunnelCount - 1) * laneGap) / 2;
  const nodes: CaveMapNode[] = [{ id: 'start', type: 'start', label: 'Cave Opening', x: 60, y: midY }];
  const edges: CaveMapEdge[] = [];
  const anchors: Array<{ entry: CaveMapPoint; mid: CaveMapPoint; boss: CaveMapPoint }> = [];

  for (let index = 0; index < cave.tunnelCount; index += 1) {
    const tunnel = index + 1;
    const difficulty = cave.tunnelDifficulties[index] ?? 1;
    const laneY = top + index * laneGap;
    const bossX = 830 + offset(seed, index, 38);
    let source = nodes[0];
    let entryX = 145 + offset(seed, index + 3, 34);

    if (index > 0 && cave.layoutType === 'Snaking Cave') {
      const previous = anchors[index - 1];
      source = (seed + index) % 4 === 0
        ? { id: `mid-${index}`, type: 'label', label: '', ...previous.mid }
        : { id: `boss-${index}`, type: 'boss', label: '', ...previous.boss };
      entryX = 182 + offset(seed, index + 9, 25);
    } else if (index > 0 && cave.layoutType === 'Forking Cave') {
      const parent = anchors[Math.max(0, index - 1)];
      source = (seed + index) % 3 === 0
        ? nodes[0]
        : { id: `fork-${index}`, type: 'label', label: '', ...parent.mid };
      entryX = source.id === 'start' ? 145 + offset(seed, index + 7, 30) : Math.min(610, source.x + 78 + offset(seed, index, 12));
    } else if (index > 0 && cave.layoutType === 'Multi Cave') {
      const frontTunnelCount = Math.max(2, Math.ceil(cave.tunnelCount * 0.7));
      if (index >= frontTunnelCount) {
        const parent = anchors[index - 1];
        source = { id: `branch-${index}`, type: 'label', label: '', ...parent.mid };
        entryX = Math.min(570, source.x + 76 + offset(seed, index, 18));
      }
    }

    const entry = { x: entryX, y: laneY };
    const wiggleA = offset(seed, index + 13, 20);
    const wiggleB = offset(seed, index + 29, 18);
    const mid = { x: Math.round((entryX + bossX) / 2), y: laneY + wiggleA };
    const boss = { x: bossX, y: laneY };
    const path = [
      roundedPoint(entry),
      roundedPoint({ x: entryX + 150 + offset(seed, index + 21, 18), y: laneY + wiggleA }),
      roundedPoint({ x: bossX - 150 + offset(seed, index + 33, 18), y: laneY - wiggleB }),
      roundedPoint(boss)
    ];

    edges.push({ id: `connector-${tunnel}`, type: 'connector', tunnelIndex: tunnel, points: [roundedPoint(source), roundedPoint(entry)] });
    edges.push({ id: `tunnel-${tunnel}`, type: 'tunnel', tunnelIndex: tunnel, points: path });
    nodes.push({ id: `entrance-${tunnel}`, type: 'entrance', label: `T${tunnel}`, tunnelIndex: tunnel, difficulty, ...roundedPoint(entry) });
    nodes.push({ id: `boss-${tunnel}`, type: 'boss', label: `Boss T${tunnel}`, tunnelIndex: tunnel, difficulty, ...roundedPoint(boss) });
    nodes.push({ id: `label-${tunnel}`, type: 'label', label: `Tunnel ${tunnel} - D${difficulty}`, tunnelIndex: tunnel, difficulty, x: mid.x, y: laneY - 32 });
    anchors.push({ entry, mid, boss });
  }

  for (let index = 0; index < cave.secretRoomCount; index += 1) {
    const tunnelIndex = (seed + index * 2) % cave.tunnelCount;
    const tunnel = anchors[tunnelIndex];
    const side = (seed + index) % 2 === 0 ? -1 : 1;
    const anchor = {
      x: Math.min(tunnel.boss.x - 82, tunnel.entry.x + 185 + ((seed + index * 41) % 180)),
      y: tunnel.entry.y + offset(seed, index + 45, 12)
    };
    const secret = {
      x: anchor.x + 50 + ((seed + index * 11) % 28),
      y: anchor.y + side * (42 + ((seed + index * 7) % 12))
    };
    edges.push({ id: `secret-edge-${index + 1}`, type: 'secret', tunnelIndex: tunnelIndex + 1, points: [roundedPoint(anchor), roundedPoint(secret)] });
    nodes.push({ id: `secret-${index + 1}`, type: 'secret', label: `Secret ${index + 1}`, tunnelIndex: tunnelIndex + 1, ...roundedPoint(secret) });
  }

  return { width, height, nodes, edges };
}

function mapSignature(map: CaveMap) {
  return JSON.stringify({
    n: map.nodes.map((node) => [node.type, node.label, node.x, node.y]),
    e: map.edges.map((edge) => [edge.type, edge.points.map((point) => [point.x, point.y])])
  });
}

function validateCaveData() {
  const errors: string[] = [];
  const seenNumbers = new Set<number>();
  const seenMaps = new Set<string>();
  if (CAVE_RECORDS.length !== 80) errors.push(`Expected 80 caves, found ${CAVE_RECORDS.length}.`);

  for (const cave of CAVE_RECORDS) {
    if (seenNumbers.has(cave.number)) errors.push(`Duplicate cave number ${cave.number}.`);
    seenNumbers.add(cave.number);
    if (cave.tunnelCount !== cave.tunnelDifficulties.length) errors.push(`Cave ${cave.number} has ${cave.tunnelCount} tunnels but ${cave.tunnelDifficulties.length} difficulties.`);
    for (const difficulty of cave.tunnelDifficulties) {
      if (difficulty < 1 || difficulty > 5) errors.push(`Cave ${cave.number} has invalid difficulty ${difficulty}.`);
    }
    const map = generateCaveMap(cave);
    const bossCount = map.nodes.filter((node) => node.type === 'boss').length;
    const secretCount = map.nodes.filter((node) => node.type === 'secret').length;
    if (bossCount !== cave.tunnelCount) errors.push(`Cave ${cave.number} map has ${bossCount} boss rooms.`);
    if (secretCount !== cave.secretRoomCount) errors.push(`Cave ${cave.number} map has ${secretCount} secret rooms.`);
    const signature = mapSignature(map);
    if (seenMaps.has(signature)) errors.push(`Cave ${cave.number} generated a duplicate map.`);
    seenMaps.add(signature);
  }

  return errors;
}

const CAVE_DATA_ERRORS = validateCaveData();
if (CAVE_DATA_ERRORS.length) {
  throw new Error(`Invalid cave data: ${CAVE_DATA_ERRORS.join(' ')}`);
}
