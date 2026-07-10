'use client';

import dynamic from 'next/dynamic';
import { useEffect, useState } from 'react';
import { BookOpen, Compass, Landmark, LogOut, PawPrint, ScrollText, Settings2, Shield, Swords } from 'lucide-react';
import { Button } from '@/components/ui/Button';
import { Card } from '@/components/ui/Card';
import { CampaignProvider, useCampaignDispatch, useCampaignState } from '@/features/campaign/CampaignProvider';

const CharacterLedger = dynamic(() => import('@/components/characters/CharacterLedger').then((module) => module.CharacterLedger), { loading: () => <PanelLoading label="Characters" />, ssr: false });
const BattleRoom = dynamic(() => import('@/components/battle/BattleRoom').then((module) => module.BattleRoom), { loading: () => <PanelLoading label="Battlefield" />, ssr: false });

type TabId = 'characters' | 'battle' | 'cities' | 'bestiary' | 'exploration' | 'scroll' | 'assets';

function PanelLoading({ label }: { label: string }) {
  return (
    <Card>
      <p className="eyebrow">{label}</p>
      <div className="mt-4 h-24 animate-pulse rounded-2xl bg-black/20" />
    </Card>
  );
}

function FuturePanel({ title }: { title: string }) {
  return (
    <Card>
      <p className="eyebrow">Future module</p>
      <h2 className="mt-2 text-3xl font-black">{title}</h2>
      <p className="mt-3 text-sm leading-6 text-[var(--muted)]">Reserved for the clean rebuild. This tab is intentionally light until the core foundation proves smooth.</p>
    </Card>
  );
}

function DashboardInner() {
  const state = useCampaignState();
  const dispatch = useCampaignDispatch();
  const isDm = state.profile.role === 'dm';
  const activeBattle = Boolean(state.battle);
  const [tab, setTab] = useState<TabId>('characters');

  const tabs = [
    { id: 'characters' as const, label: 'Characters', icon: BookOpen },
    { id: 'battle' as const, label: 'Battlefield', icon: Swords },
    { id: 'cities' as const, label: 'Discovered Cities', icon: Landmark },
    { id: 'bestiary' as const, label: 'Bestiary', icon: PawPrint },
    ...(isDm ? [
      { id: 'exploration' as const, label: 'Exploration', icon: Compass },
      { id: 'scroll' as const, label: 'Personal Scroll', icon: ScrollText },
      { id: 'assets' as const, label: 'Update Assets', icon: Settings2 }
    ] : [
      { id: 'scroll' as const, label: 'Personal Scroll', icon: ScrollText }
    ])
  ];

  useEffect(() => {
    if (activeBattle && !isDm) setTab('battle');
  }, [activeBattle, isDm]);

  async function logout() {
    await fetch('/api/auth/logout', { method: 'POST' }).catch(() => undefined);
    window.location.href = '/login';
  }

  return (
    <main className="app-shell min-h-screen">
      <header className="campaign-header sticky top-0 z-40 border-b px-4 py-3">
        <div className="mx-auto flex max-w-6xl items-center justify-between gap-3">
          <div className="min-w-0">
            <div className="flex items-center gap-2">
              <span className="eyebrow">{isDm ? 'Dungeon Master' : 'Party Member'}</span>
              {isDm && <Shield size={13} className="text-[var(--brass)]" />}
            </div>
            <h1 className="truncate text-lg font-black tracking-tight">{state.profile.displayName}</h1>
          </div>
          <div className="flex items-center gap-2">
            <Button variant="secondary" className="px-3 py-2 text-xs" onClick={() => dispatch({ type: 'profile/toggle-role' })}>
              {isDm ? 'View as player' : 'View as DM'}
            </Button>
            <button type="button" onClick={logout} className="rounded-xl border border-[var(--line)] bg-black/20 p-3 text-[var(--muted)]" aria-label="Log out">
              <LogOut size={18} />
            </button>
          </div>
        </div>
      </header>

      <section className="mx-auto max-w-6xl px-4 py-4 pb-32">
        {tab === 'characters' && <CharacterLedger />}
        {tab === 'battle' && <BattleRoom />}
        {tab === 'cities' && <FuturePanel title="Discovered Cities" />}
        {tab === 'bestiary' && <FuturePanel title="Bestiary" />}
        {tab === 'exploration' && isDm && <FuturePanel title="Exploration" />}
        {tab === 'scroll' && <FuturePanel title="Personal Scroll" />}
        {tab === 'assets' && isDm && <FuturePanel title="Update Assets" />}
      </section>

      {(!activeBattle || isDm) && (
        <nav className="campaign-nav fixed bottom-0 left-0 right-0 z-50 border-t px-2 pb-[max(0.5rem,env(safe-area-inset-bottom))] pt-2 sm:px-4 sm:pb-[max(0.75rem,env(safe-area-inset-bottom))] sm:pt-3">
          <div className={isDm ? 'thin-scrollbar mx-auto flex max-w-6xl gap-1 overflow-x-auto sm:grid sm:grid-cols-7' : 'mx-auto grid max-w-4xl grid-cols-5 gap-1'}>
            {tabs.map(({ id, label, icon: Icon }) => (
              <button
                key={id}
                onClick={() => setTab(id)}
                className={`flex ${isDm ? 'min-w-[4.8rem] sm:min-w-0' : 'min-w-0'} flex-col items-center justify-center gap-1 rounded-xl px-1 py-1.5 text-[9px] font-black leading-tight transition sm:flex-row sm:px-3 sm:py-3 sm:text-sm ${
                  tab === id ? 'bg-[var(--paper)] text-[#141915]' : 'text-[var(--muted)]'
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

export function DashboardClient() {
  return (
    <CampaignProvider>
      <DashboardInner />
    </CampaignProvider>
  );
}
