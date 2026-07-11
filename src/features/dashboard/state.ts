export type DashboardNotice = {
  id: string;
  title: string;
  body?: string;
  kind: 'notice' | 'trade' | 'announcement' | 'system';
  createdAt?: string;
};

export type DashboardStatePayload = {
  activeBattle: boolean;
  activeBattleId: string | null;
  notifications: DashboardNotice[];
};

const EMPTY_DASHBOARD_STATE: DashboardStatePayload = {
  activeBattle: false,
  activeBattleId: null,
  notifications: []
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
      : []
  };
}
