import { normalizeCharacter } from '@/features/characters/data';
import { normalizeItemCatalogEntry } from '@/features/cities/data';
import type { Character, ItemCatalogEntry } from '@/lib/types';

export type DailyRewardKind = 'none' | 'item' | 'currency';
export type DailyRewardStatus = 'empty' | 'available' | 'received' | 'missed' | 'upcoming';

export type DailyRewardCurrency = {
  id: string;
  systemKey: string;
  key: string;
  name: string;
  symbol: string;
  order: number;
};

export type DailyRewardEntry = {
  date: string;
  dayOfWeek: number;
  dayName: string;
  weekOffset: 0 | 1;
  scheduleId: string | null;
  rewardKind: DailyRewardKind;
  quantity: number;
  item: ItemCatalogEntry | null;
  currency: DailyRewardCurrency | null;
  status: DailyRewardStatus;
  available: boolean;
};

export type DailyRewardsPayload = {
  today: string;
  currentWeekStart: string;
  nextWeekStart: string;
  available: boolean;
  rewards: DailyRewardEntry[];
  characters: Character[];
  catalog: ItemCatalogEntry[];
  currencyUnits: DailyRewardCurrency[];
};

const EMPTY_DAILY_REWARDS: DailyRewardsPayload = {
  today: '',
  currentWeekStart: '',
  nextWeekStart: '',
  available: false,
  rewards: [],
  characters: [],
  catalog: [],
  currencyUnits: []
};

function numberFrom(value: unknown, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function normalizeRewardKind(value: unknown): DailyRewardKind {
  return value === 'item' || value === 'currency' ? value : 'none';
}

function normalizeRewardStatus(value: unknown): DailyRewardStatus {
  if (value === 'available' || value === 'received' || value === 'missed' || value === 'upcoming') return value;
  return 'empty';
}

export function normalizeDailyRewardCurrency(value: unknown): DailyRewardCurrency {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  return {
    id: String(source.id ?? ''),
    systemKey: String(source.systemKey ?? source.system_key ?? 'common'),
    key: String(source.key ?? source.unitKey ?? source.unit_key ?? ''),
    name: String(source.name ?? 'Currency'),
    symbol: String(source.symbol ?? ''),
    order: numberFrom(source.order ?? source.unitOrder ?? source.unit_order, 0)
  };
}

export function normalizeDailyRewardEntry(value: unknown): DailyRewardEntry {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  const rewardKind = normalizeRewardKind(source.rewardKind ?? source.reward_kind);
  const item = source.item && typeof source.item === 'object' ? normalizeItemCatalogEntry(source.item) : null;
  const currency = source.currency && typeof source.currency === 'object' ? normalizeDailyRewardCurrency(source.currency) : null;
  return {
    date: String(source.date ?? ''),
    dayOfWeek: numberFrom(source.dayOfWeek ?? source.day_of_week, 0),
    dayName: String(source.dayName ?? source.day_name ?? ''),
    weekOffset: numberFrom(source.weekOffset ?? source.week_offset, 0) === 1 ? 1 : 0,
    scheduleId: source.scheduleId || source.schedule_id ? String(source.scheduleId ?? source.schedule_id) : null,
    rewardKind,
    quantity: Math.max(0, numberFrom(source.quantity, 0)),
    item,
    currency,
    status: normalizeRewardStatus(source.status),
    available: Boolean(source.available)
  };
}

export function normalizeDailyRewardsPayload(value: unknown): DailyRewardsPayload {
  if (!value || typeof value !== 'object') return EMPTY_DAILY_REWARDS;
  const source = value as Record<string, unknown>;
  const currencyUnitSource = Array.isArray(source.currencyUnits)
    ? source.currencyUnits
    : Array.isArray(source.currency_units)
      ? source.currency_units
      : [];
  return {
    today: String(source.today ?? ''),
    currentWeekStart: String(source.currentWeekStart ?? source.current_week_start ?? ''),
    nextWeekStart: String(source.nextWeekStart ?? source.next_week_start ?? ''),
    available: Boolean(source.available),
    rewards: Array.isArray(source.rewards)
      ? source.rewards.map(normalizeDailyRewardEntry).filter((entry) => entry.date)
      : [],
    characters: Array.isArray(source.characters)
      ? source.characters.map(normalizeCharacter).filter((character) => character.id)
      : [],
    catalog: Array.isArray(source.catalog)
      ? source.catalog.map(normalizeItemCatalogEntry).filter((item) => item.id)
      : [],
    currencyUnits: currencyUnitSource.map(normalizeDailyRewardCurrency).filter((unit) => unit.id)
  };
}
