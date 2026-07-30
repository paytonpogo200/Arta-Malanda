'use client';

import { useCallback, useEffect, useMemo, useState, type ComponentType, type ReactNode } from 'react';
import { BookOpen, Compass, Landmark, LogOut, PawPrint, ScrollText, Settings2, Shield, Swords } from 'lucide-react';
import { NotificationHub } from '@/components/app-shell/NotificationHub';
import type { DashboardStatePayload } from '@/features/dashboard/state';
import { normalizeDashboardState } from '@/features/dashboard/state';
import { useLiveRefresh } from '@/hooks/useLiveRefresh';
import type { Profile } from '@/lib/types';

export type DashboardTabId = 'battle' | 'characters' | 'cities' | 'bestiary' | 'exploration' | 'scroll' | 'assets';

type DashboardTab = {
  id: DashboardTabId;
  label: string;
  icon: ComponentType<{ size?: number; className?: string }>;
  dmOnly?: boolean;
};

type DashboardShellProps = {
  profile: Profile;
  activeTab: DashboardTabId;
  onTabChange: (tab: DashboardTabId) => void;
  children: ReactNode;
};

const PLAYER_TABS: DashboardTab[] = [
  { id: 'battle', label: 'Battlefield', icon: Swords },
  { id: 'characters', label: 'Characters', icon: BookOpen },
  { id: 'cities', label: 'Discovered Cities', icon: Landmark },
  { id: 'bestiary', label: 'Bestiary', icon: PawPrint },
  { id: 'scroll', label: 'Personal Scroll', icon: ScrollText }
];

const DM_TABS: DashboardTab[] = [
  { id: 'battle', label: 'Battlefield', icon: Swords },
  { id: 'characters', label: 'Characters', icon: BookOpen },
  { id: 'cities', label: 'Discovered Cities', icon: Landmark },
  { id: 'bestiary', label: 'Bestiary', icon: PawPrint },
  { id: 'exploration', label: 'Exploration', icon: Compass, dmOnly: true },
  { id: 'scroll', label: 'Personal Scroll', icon: ScrollText },
  { id: 'assets', label: 'Update Assets', icon: Settings2, dmOnly: true }
];

function useDashboardState(isDm: boolean, onBattleLock: () => void) {
  const [state, setState] = useState<DashboardStatePayload>({
    activeBattle: false,
    activeBattleId: null,
    notifications: []
  });

  const refresh = useCallback(async () => {
    try {
      const response = await fetch('/api/dashboard/state', { cache: 'no-store' });
      if (!response.ok) return;
      const payload = normalizeDashboardState(await response.json().catch(() => ({})));
      setState((current) => {
        if (
          current.activeBattle === payload.activeBattle &&
          current.activeBattleId === payload.activeBattleId &&
          current.notifications.length === payload.notifications.length
        ) {
          return current;
        }
        return payload;
      });
      if (payload.activeBattle && !isDm) onBattleLock();
    } catch {
      // The shell should not crash if the background refresh blips.
    }
  }, [isDm, onBattleLock]);

  useEffect(() => {
    void refresh();

    const interval = window.setInterval(refresh, 15000);
    const onVisibilityChange = () => {
      if (document.visibilityState === 'visible') void refresh();
    };

    document.addEventListener('visibilitychange', onVisibilityChange);
    return () => {
      window.clearInterval(interval);
      document.removeEventListener('visibilitychange', onVisibilityChange);
    };
  }, [refresh]);

  useLiveRefresh(['dashboard', 'battle', 'notifications', 'trades'], refresh);

  return { state, refresh };
}

export function DashboardShell({ profile, activeTab, onTabChange, children }: DashboardShellProps) {
  const isDm = profile.role === 'dm';
  const tabs = isDm ? DM_TABS : PLAYER_TABS;
  const battleLock = useCallback(() => onTabChange('battle'), [onTabChange]);
  const { state, refresh } = useDashboardState(isDm, battleLock);

  const navVisible = !state.activeBattle || isDm;
  const contentPadding = state.activeBattle && !isDm ? 'pb-8' : isDm ? 'pb-28 sm:pb-32' : 'pb-32';

  const headerLabel = useMemo(() => {
    if (state.activeBattle && !isDm) return 'Active Encounter';
    return isDm ? 'Dungeon Master' : 'Party Member';
  }, [isDm, state.activeBattle]);

  async function logout() {
    await fetch('/api/auth/logout', { method: 'POST' }).catch(() => undefined);
    window.location.href = '/login';
  }

  return (
    <main className="app-shell min-h-screen text-[var(--paper)]">
      <header className="campaign-header sticky top-0 z-40 border-b px-4 py-3">
        <div className="mx-auto flex max-w-6xl items-center justify-between gap-3">
          <div className="min-w-0">
            <div className="flex items-center gap-2">
              <span className="eyebrow">{headerLabel}</span>
              {isDm && <Shield size={13} className="text-[var(--brass)]" />}
            </div>
            <h1 className="truncate text-lg font-black tracking-tight">{profile.displayName}</h1>
          </div>

          <div className="flex gap-2">
            <NotificationHub profile={profile} notices={state.notifications} onRefresh={refresh} />
            <button
              type="button"
              onClick={logout}
              className="rounded-xl border border-[var(--line)] bg-black/20 p-3 text-[var(--muted)] transition active:scale-95"
              aria-label="Log out"
            >
              <LogOut size={18} />
            </button>
          </div>
        </div>
      </header>

      <section className={`mx-auto max-w-6xl px-4 py-4 ${contentPadding}`}>
        {children}
      </section>

      {navVisible && (
        <nav className="campaign-nav fixed bottom-0 left-0 right-0 z-50 border-t px-2 pb-[max(0.5rem,env(safe-area-inset-bottom))] pt-2 sm:px-4 sm:pb-[max(0.75rem,env(safe-area-inset-bottom))] sm:pt-3">
          <div className={isDm ? 'thin-scrollbar mx-auto flex max-w-6xl gap-1 overflow-x-auto sm:grid sm:grid-cols-7' : 'mx-auto grid max-w-4xl grid-cols-5 gap-1'}>
            {tabs.map(({ id, label, icon: Icon }) => (
              <button
                key={id}
                type="button"
                onClick={() => onTabChange(id)}
                className={`flex ${isDm ? 'min-w-[4.6rem] sm:min-w-0' : 'min-w-0'} flex-col items-center justify-center gap-1 rounded-xl px-1 py-1.5 text-[9px] font-black leading-tight transition active:scale-95 sm:flex-row sm:px-3 sm:py-3 sm:text-sm ${
                  activeTab === id ? 'bg-[var(--paper)] text-[#141915]' : 'text-[var(--muted)]'
                }`}
              >
                <Icon size={17} /> {label}
              </button>
            ))}
          </div>
        </nav>
      )}
    </main>
  );
}
