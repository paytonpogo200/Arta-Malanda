export type WorldMapImage = {
  id: string;
  fileName: string;
  mimeType: string;
  imageDataUrl: string;
  createdAt: string;
};

export type WorldMapPinType = 'sword' | 'puzzle' | 'skull' | 'flag' | 'plant' | 'chest';

export type WorldMapPin = {
  id: string;
  mapId: string;
  type: WorldMapPinType;
  x: number;
  y: number;
  description: string;
  createdBy: string;
  createdByName: string;
  createdAt: string;
};

export type WorldMapPayload = {
  map: WorldMapImage | null;
  pins: WorldMapPin[];
};

const PIN_TYPES = new Set<WorldMapPinType>(['sword', 'puzzle', 'skull', 'flag', 'plant', 'chest']);

function clampCoordinate(value: unknown) {
  const number = Number(value);
  if (!Number.isFinite(number)) return 0;
  return Math.min(1, Math.max(0, number));
}

export function normalizeWorldMapImage(value: unknown): WorldMapImage | null {
  if (!value || typeof value !== 'object') return null;
  const source = value as Record<string, unknown>;
  const id = String(source.id ?? '');
  const imageDataUrl = String(source.imageDataUrl ?? '');
  if (!id || !imageDataUrl.startsWith('data:image/')) return null;
  return {
    id,
    fileName: String(source.fileName ?? 'world-map'),
    mimeType: String(source.mimeType ?? 'image/png'),
    imageDataUrl,
    createdAt: String(source.createdAt ?? '')
  };
}

export function normalizeWorldMapPin(value: unknown): WorldMapPin | null {
  if (!value || typeof value !== 'object') return null;
  const source = value as Record<string, unknown>;
  const id = String(source.id ?? '');
  const mapId = String(source.mapId ?? '');
  const type = String(source.type ?? '');
  const description = String(source.description ?? '').trim();
  const createdBy = String(source.createdBy ?? '');
  if (!id || !mapId || !PIN_TYPES.has(type as WorldMapPinType) || !description || !createdBy) return null;
  return {
    id,
    mapId,
    type: type as WorldMapPinType,
    x: clampCoordinate(source.x),
    y: clampCoordinate(source.y),
    description,
    createdBy,
    createdByName: String(source.createdByName ?? 'Unknown'),
    createdAt: String(source.createdAt ?? '')
  };
}

export function normalizeWorldMapPayload(value: unknown): WorldMapPayload {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  return {
    map: normalizeWorldMapImage(source.map),
    pins: Array.isArray(source.pins) ? source.pins.map(normalizeWorldMapPin).filter((pin): pin is WorldMapPin => Boolean(pin)) : []
  };
}
