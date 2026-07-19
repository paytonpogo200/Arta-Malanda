import type { PersonalScroll } from '@/lib/types';

export function normalizePersonalScroll(value: unknown): PersonalScroll {
  const source = (value ?? {}) as Record<string, unknown>;
  return {
    profileId: String(source.profileId ?? source.profile_id ?? ''),
    contentHtml: String(source.contentHtml ?? source.content_html ?? ''),
    drawingDataUrl: String(source.drawingDataUrl ?? source.drawing_data_url ?? ''),
    updatedAt: source.updatedAt || source.updated_at ? String(source.updatedAt ?? source.updated_at) : null
  };
}
