'use client';

import dynamic from 'next/dynamic';
import { useState } from 'react';
import { DashboardShell, type DashboardTabId } from '@/components/app-shell/DashboardShell';
import { Card } from '@/components/ui/Card';
import type { Profile } from '@/lib/types';

const CharacterLedger = dynamic(() => import('@/components/characters/CharacterLedger').then((module) => module.CharacterLedger), { loading: () => <PanelLoading label="Characters" />, ssr: false });
const BattleRoom = dynamic(() => import('@/components/battle/BattleRoom').then((module) => module.BattleRoom), { loading: () => <PanelLoading label="Battlefield" />, ssr: false });
const CitiesPanel = dynamic(() => import('@/components/cities/CitiesPanel').then((module) => module.CitiesPanel), { loading: () => <PanelLoading label="Discovered Cities" />, ssr: false });
const ExplorationPanel = dynamic(() => import('@/components/exploration/ExplorationPanel').then((module) => module.ExplorationPanel), { loading: () => <PanelLoading label="Exploration" />, ssr: false });

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
  const [tab, setTab] = useState<DashboardTabId>('characters');
  const isDm = profile.role === 'dm';

  return (
    <DashboardShell profile={profile} activeTab={tab} onTabChange={setTab}>
      {tab === 'battle' && <BattleRoom profile={profile} />}
      {tab === 'characters' && <CharacterLedger profile={profile} />}
      {tab === 'cities' && <CitiesPanel profile={profile} />}
      {tab === 'bestiary' && <FuturePanel title="Bestiary" />}
      {tab === 'exploration' && isDm && <ExplorationPanel />}
      {tab === 'scroll' && <FuturePanel title="Personal Scroll" />}
      {tab === 'assets' && isDm && <FuturePanel title="Update Assets" moduleName="DM module" />}
    </DashboardShell>
  );
}
