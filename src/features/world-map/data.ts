export type WorldMapImage = {
  id: string;
  fileName: string;
  mimeType: string;
  imageDataUrl: string;
  createdAt: string;
};

export type WorldMapPayload = {
  map: WorldMapImage | null;
};

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

export function normalizeWorldMapPayload(value: unknown): WorldMapPayload {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  return {
    map: normalizeWorldMapImage(source.map)
  };
}
