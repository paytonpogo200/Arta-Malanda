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
const BestiaryPanel = dynamic(() => import('@/components/bestiary/BestiaryPanel').then((module) => module.BestiaryPanel), { loading: () => <PanelLoading label="Bestiary" />, ssr: false });
const PersonalScrollPanel = dynamic(() => import('@/components/scroll/PersonalScrollPanel').then((module) => module.PersonalScrollPanel), { loading: () => <PanelLoading label="Personal Scroll" />, ssr: false });
const UpdateAssetsPanel = dynamic(() => import('@/components/assets/UpdateAssetsPanel').then((module) => module.UpdateAssetsPanel), { loading: () => <PanelLoading label="Update Assets" />, ssr: false });

function PanelLoading({ label }: { label: string }) {
  return (
    <Card>
      <p className="eyebrow">{label}</p>
      <div className="mt-4 h-24 animate-pulse rounded-2xl bg-black/20" />
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
      {tab === 'bestiary' && <BestiaryPanel profile={profile} />}
      {tab === 'exploration' && isDm && <ExplorationPanel />}
      {tab === 'scroll' && <PersonalScrollPanel />}
      {tab === 'assets' && isDm && <UpdateAssetsPanel />}
    </DashboardShell>
  );
}
