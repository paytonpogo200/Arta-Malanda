export type DashboardNotice = {
  id: string;
  title: string;
  body?: string;
  kind: 'notice' | 'trade' | 'announcement' | 'system';
  sourceId?: string;
  sourceType?: string;
  readAt?: string | null;
  createdAt?: string;
};

export type DashboardStatePayload = {
  activeBattle: boolean;
  activeBattleId: string | null;
  notifications: DashboardNotice[];
  dailyRewards: {
    available: boolean;
    today: string;
  };
};

const EMPTY_DASHBOARD_STATE: DashboardStatePayload = {
  activeBattle: false,
  activeBattleId: null,
  notifications: [],
  dailyRewards: {
    available: false,
    today: ''
  }
};

function normalizeNotice(value: unknown): DashboardNotice | null {
  if (!value || typeof value !== 'object') return null;
  const source = value as Record<string, unknown>;
  const title = String(source.title ?? '').trim();
  if (!title) return null;

  const kind = source.kind === 'trade' || source.kind === 'announcement' || source.kind === 'system'
    ? source.kind
    : 'notice';

  return {
    id: String(source.id ?? `${kind}-${title}-${String(source.createdAt ?? '')}`),
    title,
    body: source.body ? String(source.body) : undefined,
    kind,
    sourceId: source.sourceId ? String(source.sourceId) : undefined,
    sourceType: source.sourceType ? String(source.sourceType) : undefined,
    readAt: source.readAt ? String(source.readAt) : null,
    createdAt: source.createdAt ? String(source.createdAt) : undefined
  };
}

export function normalizeDashboardState(value: unknown): DashboardStatePayload {
  if (!value || typeof value !== 'object') return EMPTY_DASHBOARD_STATE;
  const source = value as Record<string, unknown>;

  return {
    activeBattle: Boolean(source.activeBattle),
    activeBattleId: source.activeBattleId ? String(source.activeBattleId) : null,
    notifications: Array.isArray(source.notifications)
      ? source.notifications.map(normalizeNotice).filter((notice): notice is DashboardNotice => Boolean(notice))
      : [],
    dailyRewards: {
      available: Boolean((source.dailyRewards as Record<string, unknown> | undefined)?.available),
      today: String((source.dailyRewards as Record<string, unknown> | undefined)?.today ?? '')
    }
  };
}
