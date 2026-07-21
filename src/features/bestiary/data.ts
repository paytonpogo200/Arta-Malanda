import type { BestiaryCategory, BestiaryCategoryRecord, BestiaryEntity } from '@/lib/types';

export type BestiaryPayload = {
  categories: BestiaryCategoryRecord[];
  entities: BestiaryEntity[];
  unlockedCount: number;
  totalCount: number;
};

function numberFrom(value: unknown, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function stringRecordFrom(value: unknown): Record<string, string> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return {};
  return Object.fromEntries(
    Object.entries(value as Record<string, unknown>)
      .map(([key, entry]) => [key, String(entry ?? '').trim()])
      .filter(([key, entry]) => key && entry)
  );
}

export function categoryLabel(category: BestiaryCategory) {
  return category
    .split(/[-_\s]+/)
    .filter(Boolean)
    .map((part) => part[0]?.toUpperCase() + part.slice(1))
    .join(' ') || 'Unknown';
}

export function normalizeBestiaryCategory(value: unknown): BestiaryCategoryRecord {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  const key = String(source.key ?? source.category ?? '').trim();
  return {
    key,
    name: String(source.name ?? categoryLabel(key)).trim() || categoryLabel(key),
    hidden: Boolean(source.hidden),
    order: numberFrom(source.order, 0)
  };
}

export function normalizeBestiaryEntity(value: unknown): BestiaryEntity {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  return {
    id: String(source.id ?? ''),
    key: String(source.key ?? ''),
    name: String(source.name ?? 'Unknown Entity'),
    category: String(source.category ?? 'beast'),
    habitat: String(source.habitat ?? ''),
    temperament: String(source.temperament ?? ''),
    wildScore: Math.max(0, numberFrom(source.wildScore, 0)),
    hp: Math.max(0, numberFrom(source.hp, 0)),
    mana: Math.max(0, numberFrom(source.mana, 0)),
    summary: String(source.summary ?? ''),
    details: String(source.details ?? ''),
    stats: stringRecordFrom(source.stats),
    unlocked: Boolean(source.unlocked),
    order: numberFrom(source.order, 0)
  };
}

export function normalizeBestiaryPayload(value: unknown): BestiaryPayload {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  const entities = Array.isArray(source.entities) ? source.entities.map(normalizeBestiaryEntity).filter((entity) => entity.id) : [];
  const derivedCategories = Array.from(new Set(entities.map((entity) => entity.category)))
    .map((key, index) => ({ key, name: categoryLabel(key), hidden: false, order: index * 10 }));
  const categories = Array.isArray(source.categories)
    ? source.categories.map(normalizeBestiaryCategory).filter((entry) => entry.key)
    : derivedCategories;

  return {
    categories,
    entities,
    unlockedCount: Math.max(0, numberFrom(source.unlockedCount, entities.filter((entity) => entity.unlocked).length)),
    totalCount: Math.max(0, numberFrom(source.totalCount, entities.length))
  };
}
