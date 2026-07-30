export type CaveCreatureType = 'Beast' | 'Goblin' | 'Hybrid';
export type CaveLayoutType = 'Snaking Cave' | 'Forking Cave' | 'Multi Cave';
export type CaveMapNodeType = 'start' | 'boss' | 'secret' | 'label';
export type CaveMapEdgeType = 'tunnel' | 'secret';

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

type MapBox = {
  left: number;
  right: number;
  top: number;
  bottom: number;
};

type CaveLabelRequest = {
  tunnel: number;
  difficulty: number;
  path: CaveMapPoint[];
  laneY: number;
};

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

function clamp(value: number, min: number, max: number) {
  return Math.max(min, Math.min(max, value));
}

function boxesOverlap(a: MapBox, b: MapBox) {
  return a.left < b.right && a.right > b.left && a.top < b.bottom && a.bottom > b.top;
}

function difficultyLabelBox(point: CaveMapPoint): MapBox {
  return { left: point.x - 108, right: point.x + 108, top: point.y - 42, bottom: point.y + 32 };
}

function secretRoomBox(point: CaveMapPoint): MapBox {
  return { left: point.x - 34, right: point.x + 34, top: point.y - 28, bottom: point.y + 28 };
}

function expandBox(box: MapBox, padding: number): MapBox {
  return {
    left: box.left - padding,
    right: box.right + padding,
    top: box.top - padding,
    bottom: box.bottom + padding
  };
}

function pointInBox(point: CaveMapPoint, box: MapBox) {
  return point.x >= box.left && point.x <= box.right && point.y >= box.top && point.y <= box.bottom;
}

function cubicPoint(points: CaveMapPoint[], percent: number): CaveMapPoint {
  const [start, controlOne, controlTwo, end] = points;
  const t = clamp(percent, 0, 1);
  const inverse = 1 - t;
  return {
    x: inverse ** 3 * start.x + 3 * inverse ** 2 * t * controlOne.x + 3 * inverse * t ** 2 * controlTwo.x + t ** 3 * end.x,
    y: inverse ** 3 * start.y + 3 * inverse ** 2 * t * controlOne.y + 3 * inverse * t ** 2 * controlTwo.y + t ** 3 * end.y
  };
}

function pointOnPath(points: CaveMapPoint[], percent: number) {
  if (points.length === 4) return cubicPoint(points, percent);
  const clamped = Math.max(0, Math.min(1, percent));
  const position = clamped * (points.length - 1);
  const index = Math.min(points.length - 2, Math.floor(position));
  const local = position - index;
  const start = points[index];
  const end = points[index + 1];
  return {
    x: start.x + (end.x - start.x) * local,
    y: start.y + (end.y - start.y) * local
  };
}

function sampledPath(points: CaveMapPoint[], samples = 72) {
  return Array.from({ length: samples + 1 }, (_, index) => pointOnPath(points, index / samples));
}

function boxTouchesPath(box: MapBox, path: CaveMapPoint[]) {
  const expanded = expandBox(box, 24);
  return sampledPath(path).some((point) => pointInBox(point, expanded));
}

function chooseLabelPosition(request: CaveLabelRequest, paths: CaveMapPoint[][], occupiedBoxes: MapBox[], width: number, height: number): CaveMapPoint {
  const percentOptions = [0.52, 0.38, 0.66, 0.28, 0.78, 0.18, 0.88];
  const verticalOptions = [-104, 104, -146, 146, -188, 188, -232, 232, -276, 276];
  const horizontalOptions = [0, -86, 86, -150, 150, -224, 224, -304, 304];

  for (const percent of percentOptions) {
    const anchor = pointOnPath(request.path, percent);
    for (const vertical of verticalOptions) {
      for (const horizontal of horizontalOptions) {
        const candidate = roundedPoint({
          x: clamp(anchor.x + horizontal, 126, width - 126),
          y: clamp(anchor.y + vertical, 58, height - 66)
        });
        const box = difficultyLabelBox(candidate);
        if (occupiedBoxes.some((occupied) => boxesOverlap(occupied, box))) continue;
        if (paths.some((path) => boxTouchesPath(box, path))) continue;
        return candidate;
      }
    }
  }

  const fallback = roundedPoint({
    x: clamp(pointOnPath(request.path, 0.52).x, 126, width - 126),
    y: clamp(request.laneY - 118, 58, height - 66)
  });
  return fallback;
}

function laneY(index: number, tunnelCount: number, height: number) {
  const usableTop = 158;
  const usableBottom = height - 128;
  if (tunnelCount === 1) return height / 2;
  return usableTop + ((usableBottom - usableTop) * index) / (tunnelCount - 1);
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
  const width = 1280;
  const height = 900;
  const midY = height / 2;
  const nodes: CaveMapNode[] = [{ id: 'start', type: 'start', label: 'Cave Opening', x: 72, y: midY }];
  const edges: CaveMapEdge[] = [];
  const anchors: Array<{ entry: CaveMapPoint; boss: CaveMapPoint; path: CaveMapPoint[]; attach: CaveMapPoint[] }> = [];
  const labelRequests: CaveLabelRequest[] = [];

  for (let index = 0; index < cave.tunnelCount; index += 1) {
    const tunnel = index + 1;
    const difficulty = cave.tunnelDifficulties[index] ?? 1;
    const y = laneY(index, cave.tunnelCount, height);
    const roll = (seed + index * 53) % 100;
    let source = nodes[0];

    if (index > 0 && cave.layoutType === 'Snaking Cave') {
      const previous = anchors[index - 1];
      const older = anchors[Math.max(0, index - 2)];
      const attachPoint = roll < 62
        ? previous.boss
        : roll < 82
          ? previous.attach[(seed + index) % previous.attach.length]
          : roll < 92
            ? nodes[0]
            : older.attach[(seed + index * 2) % older.attach.length];
      source = { id: `snake-source-${index}`, type: 'label', label: '', ...attachPoint };
    } else if (index > 0 && cave.layoutType === 'Forking Cave') {
      const parent = anchors[Math.max(0, index - 1 - ((seed + index) % Math.min(index, 2)))];
      const attachPoint = roll < 64
        ? parent.attach[(seed + index * 3) % parent.attach.length]
        : roll < 82
          ? nodes[0]
          : parent.boss;
      source = { id: `fork-source-${index}`, type: 'label', label: '', ...attachPoint };
    } else if (index > 0 && cave.layoutType === 'Multi Cave') {
      const parent = anchors[Math.max(0, index - 1 - ((seed + index) % Math.min(index, 3)))];
      const attachPoint = roll < 86
        ? nodes[0]
        : roll < 95
          ? parent.attach[(seed + index * 5) % parent.attach.length]
          : parent.boss;
      source = { id: `multi-source-${index}`, type: 'label', label: '', ...attachPoint };
    }

    const entry = roundedPoint(source);
    const minimumBossX = source.x > 850 ? source.x + 116 : 1010;
    const boss = {
      x: clamp(minimumBossX + offset(seed, index, 96), source.x + 92, width - 118),
      y: clamp(y + offset(seed, index + 31, 28), 72, height - 72)
    };
    const span = boss.x - entry.x;
    const laneDelta = y - entry.y;
    const laneWiggle = offset(seed, index + 23, 34);
    const branchWiggle = source.id === 'start' ? 0 : offset(seed, index + 10, 24);
    const path = [
      roundedPoint(entry),
      roundedPoint({
        x: entry.x + span * 0.28 + offset(seed, index + 21, 64),
        y: entry.y + laneDelta * 0.18 + branchWiggle + laneWiggle * 1.7
      }),
      roundedPoint({
        x: entry.x + span * 0.72 + offset(seed, index + 33, 64),
        y: boss.y - laneDelta * 0.14 - laneWiggle * 1.35 + offset(seed, index + 41, 26)
      }),
      roundedPoint(boss)
    ];
    const attach = [pointOnPath(path, 0.28), pointOnPath(path, 0.48), pointOnPath(path, 0.68)].map(roundedPoint);

    edges.push({ id: `tunnel-${tunnel}`, type: 'tunnel', tunnelIndex: tunnel, points: path });
    nodes.push({ id: `boss-${tunnel}`, type: 'boss', label: `Boss T${tunnel}`, tunnelIndex: tunnel, difficulty, ...roundedPoint(boss) });
    labelRequests.push({ tunnel, difficulty, path, laneY: y });
    anchors.push({ entry, boss, path, attach });
  }

  const occupiedLabelBoxes: MapBox[] = [];
  const tunnelPaths = edges.filter((edge) => edge.type === 'tunnel').map((edge) => edge.points);
  for (const request of labelRequests) {
    const labelPoint = chooseLabelPosition(request, tunnelPaths, occupiedLabelBoxes, width, height);
    const labelNode = {
      id: `label-${request.tunnel}`,
      type: 'label' as const,
      label: `T${request.tunnel}: Difficulty ${request.difficulty}`,
      tunnelIndex: request.tunnel,
      difficulty: request.difficulty,
      ...labelPoint
    };
    nodes.push(labelNode);
    occupiedLabelBoxes.push(difficultyLabelBox(labelNode));
  }

  for (let index = 0; index < cave.secretRoomCount; index += 1) {
    const tunnelIndex = (seed + index * 2) % cave.tunnelCount;
    const tunnel = anchors[tunnelIndex];
    const basePercent = 0.34 + ((seed + index * 17) % 42) / 100;
    const preferredAnchor = pointOnPath(tunnel.path, basePercent);
    const preferredSide = preferredAnchor.y < height - 132 ? 1 : -1;
    const sideOptions = [preferredSide, -preferredSide];
    const percentOptions = [basePercent, basePercent + 0.07, basePercent - 0.08, 0.24, 0.38, 0.52, 0.66, 0.8].map((percent) => clamp(percent, 0.18, 0.86));
    const xOptions = [0, 42, -42, 84, -84];
    let anchor = preferredAnchor;
    let secret = roundedPoint({
      x: clamp(anchor.x + 84 + ((seed + index * 11) % 40), 132, width - 86),
      y: clamp(anchor.y + preferredSide * (76 + ((seed + index * 7) % 24)), 72, height - 72)
    });

    for (const percent of percentOptions) {
      const candidateAnchor = pointOnPath(tunnel.path, percent);
      let foundOpenSpot = false;
      for (const side of sideOptions) {
        for (const distance of [82, 114, 146, 178, 210]) {
          for (const xShift of xOptions) {
            const candidate = roundedPoint({
              x: clamp(candidateAnchor.x + 78 + xShift + ((seed + index * 11 + distance) % 42), 132, width - 86),
              y: clamp(candidateAnchor.y + side * distance, 72, height - 72)
            });
            if (!occupiedLabelBoxes.some((box) => boxesOverlap(box, secretRoomBox(candidate)))) {
              anchor = candidateAnchor;
              secret = candidate;
              foundOpenSpot = true;
              break;
            }
          }
          if (foundOpenSpot) break;
        }
        if (foundOpenSpot) break;
      }
      if (foundOpenSpot) break;
    }

    occupiedLabelBoxes.push(secretRoomBox(secret));
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
    const tunnelEdgeCount = map.edges.filter((edge) => edge.type === 'tunnel').length;
    if (bossCount !== cave.tunnelCount) errors.push(`Cave ${cave.number} map has ${bossCount} boss rooms.`);
    if (secretCount !== cave.secretRoomCount) errors.push(`Cave ${cave.number} map has ${secretCount} secret rooms.`);
    if (tunnelEdgeCount !== cave.tunnelCount) errors.push(`Cave ${cave.number} map has ${tunnelEdgeCount} continuous tunnel paths.`);
    const labelBoxes = map.nodes.filter((node) => node.type === 'label').map((node) => ({ node, box: difficultyLabelBox(node) }));
    for (let index = 0; index < labelBoxes.length; index += 1) {
      for (let next = index + 1; next < labelBoxes.length; next += 1) {
        if (boxesOverlap(labelBoxes[index].box, labelBoxes[next].box)) errors.push(`Cave ${cave.number} has overlapping tunnel difficulty labels.`);
      }
    }
    const tunnelPaths = map.edges.filter((edge) => edge.type === 'tunnel').map((edge) => edge.points);
    for (const { box } of labelBoxes) {
      if (tunnelPaths.some((path) => boxTouchesPath(box, path))) errors.push(`Cave ${cave.number} has a tunnel passing under a difficulty label.`);
    }
    for (const secret of map.nodes.filter((node) => node.type === 'secret')) {
      const secretBox = secretRoomBox(secret);
      if (labelBoxes.some(({ box }) => boxesOverlap(box, secretBox))) errors.push(`Cave ${cave.number} has a secret room overlapping a tunnel difficulty label.`);
    }
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
