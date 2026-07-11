'use client';

import dynamic from 'next/dynamic';
import { useEffect, useState } from 'react';
import { BookOpen, Compass, Landmark, LogOut, PawPrint, ScrollText, Settings2, Shield, Swords } from 'lucide-react';
import { Card } from '@/components/ui/Card';
import type { Profile } from '@/lib/types';

const CharacterLedger = dynamic(() => import('@/components/characters/CharacterLedger').then((module) => module.CharacterLedger), { loading: () => <PanelLoading label="Characters" />, ssr: false });

type TabId = 'characters' | 'battle' | 'cities' | 'bestiary' | 'exploration' | 'scroll' | 'assets';

function PanelLoading({ label }: { label: string }) {
  return (
    <Card>
      <p className="eyebrow">{label}</p>
      <div className="mt-4 h-24 animate-pulse rounded-2xl bg-black/20" />
    </Card>
  );
}

function FuturePanel({ title, moduleName }: { title: string; moduleName?: string }) {
  return (
    <Card>
      <p className="eyebrow">{moduleName ?? 'Queued rebuild module'}</p>
      <h2 className="mt-2 text-3xl font-black">{title}</h2>
    </Card>
  );
}

export function DashboardClient({ profile }: { profile: Profile }) {
  const isDm = profile.role === 'dm';
  const activeBattle = false;
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
            <h1 className="truncate text-lg font-black tracking-tight">{profile.displayName}</h1>
          </div>
          <div className="flex items-center gap-2">
            <button type="button" onClick={logout} className="rounded-xl border border-[var(--line)] bg-black/20 p-3 text-[var(--muted)]" aria-label="Log out">
              <LogOut size={18} />
            </button>
          </div>
        </div>
      </header>

      <section className="mx-auto max-w-6xl px-4 py-4 pb-32">
        {tab === 'characters' && <CharacterLedger profile={profile} />}
        {tab === 'battle' && <FuturePanel title="Battlefield" />}
        {tab === 'cities' && <FuturePanel title="Discovered Cities" />}
        {tab === 'bestiary' && <FuturePanel title="Bestiary" />}
        {tab === 'exploration' && isDm && <FuturePanel title="Exploration" moduleName="DM module" />}
        {tab === 'scroll' && <FuturePanel title="Personal Scroll" />}
        {tab === 'assets' && isDm && <FuturePanel title="Update Assets" moduleName="DM module" />}
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
