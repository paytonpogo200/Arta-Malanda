import type { BestiaryCategory, BestiaryEntity } from '@/lib/types';

export type BestiaryPayload = {
  entities: BestiaryEntity[];
  unlockedCount: number;
  totalCount: number;
};

export const BESTIARY_CATEGORIES: BestiaryCategory[] = ['animal', 'beast', 'being', 'monster', 'spirit'];

function numberFrom(value: unknown, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function normalizeCategory(value: unknown): BestiaryCategory {
  return BESTIARY_CATEGORIES.includes(value as BestiaryCategory) ? value as BestiaryCategory : 'beast';
}

export function normalizeBestiaryEntity(value: unknown): BestiaryEntity {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  return {
    id: String(source.id ?? ''),
    key: String(source.key ?? ''),
    name: String(source.name ?? 'Unknown Entity'),
    category: normalizeCategory(source.category),
    habitat: String(source.habitat ?? ''),
    temperament: String(source.temperament ?? ''),
    wildScore: Math.max(0, numberFrom(source.wildScore, 0)),
    hp: Math.max(0, numberFrom(source.hp, 0)),
    mana: Math.max(0, numberFrom(source.mana, 0)),
    summary: String(source.summary ?? ''),
    details: String(source.details ?? ''),
    unlocked: Boolean(source.unlocked),
    order: numberFrom(source.order, 0)
  };
}

export function normalizeBestiaryPayload(value: unknown): BestiaryPayload {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  const entities = Array.isArray(source.entities) ? source.entities.map(normalizeBestiaryEntity).filter((entity) => entity.id) : [];
  return {
    entities,
    unlockedCount: Math.max(0, numberFrom(source.unlockedCount, entities.filter((entity) => entity.unlocked).length)),
    totalCount: Math.max(0, numberFrom(source.totalCount, entities.length))
  };
}
