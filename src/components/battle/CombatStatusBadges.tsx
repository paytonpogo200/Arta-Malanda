'use client';

import { Accessibility, BicepsFlexed, Cross, Dices, Droplet, Flame, FlaskConical, Link2, RefreshCcw, Shield, Shell, Sparkles } from 'lucide-react';
import type { CombatStatus } from '@/lib/types';

export function orderedCombatStatuses(statuses: CombatStatus[]) {
  return [...statuses].sort((a, b) => {
    const priority = (status: CombatStatus) => status.kind === 'permanent' ? 0 : status.kind === 'buff' ? 1 : 2;
    return priority(a) - priority(b) || a.name.localeCompare(b.name) || a.id.localeCompare(b.id);
  });
}

function StatusIcon({ status, size }: { status: CombatStatus; size: number }) {
  const simpleIcons: Record<string, typeof Sparkles> = {
    'health-regeneration': Cross,
    'mana-regeneration': Droplet,
    strength: BicepsFlexed,
    ironskin: Shield,
    'better-dice': Dices,
    counterattack: RefreshCcw,
    burning: Flame,
    poison: FlaskConical,
    stunned: Shell
  };
  const Icon = simpleIcons[status.key];
  if (Icon) return <Icon size={size} strokeWidth={2.8} />;
  if (status.key === 'swiftness') return <SwiftBootIcon size={size} />;
  if (status.key === 'invisible') return <span className="grid place-items-center rounded-full border border-dashed border-current p-px opacity-80"><Accessibility size={Math.max(9, size - 2)} /></span>;
  if (status.key === 'bleeding') return <span className="relative grid place-items-center"><Cross size={size} strokeWidth={2.8} /><Link2 className="absolute rotate-45" size={Math.max(9, size - 2)} strokeWidth={2.8} /><Link2 className="absolute -rotate-45" size={Math.max(9, size - 2)} strokeWidth={2.8} /></span>;
  if (status.key === 'slowness') return <WornBootIcon size={size} />;
  if (status.key === 'weakness') return <span className="relative grid place-items-center"><BicepsFlexed size={size} /><span className="absolute h-[2px] w-[120%] rotate-[-35deg] bg-current" /></span>;
  return <Sparkles size={size} strokeWidth={2.8} />;
}

function SwiftBootIcon({ size }: { size: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" aria-hidden="true" className="overflow-visible">
      <path d="M8.2 4.2v7.3c0 1.2.7 2.3 1.8 2.8l3.1 1.4c1.4.6 2.9.7 4.3.2l2.4-.8v3.1H6.1c-1.2 0-2.1-1-2-2.2l.3-2.5 2.1-.8V4.2h1.7Z" fill="currentColor" stroke="currentColor" strokeWidth="1.4" strokeLinejoin="round" />
      <path d="M7 5.3C4.5 3.1 2.5 3.4 1.5 4c1.2 1.8 2.8 2.8 5.5 2.7M7 7.7c-2.9-.8-4.8.2-5.5 1 1.7 1.3 3.5 1.6 5.5.5" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
      <path d="M5 15.5h6.8" stroke="var(--status-icon-cut, #17324a)" strokeWidth="1.3" strokeLinecap="round" opacity=".75" />
    </svg>
  );
}

function WornBootIcon({ size }: { size: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" aria-hidden="true" className="overflow-visible">
      <path d="M5.2 3.7h5.1l-.5 7.1c-.1 1.4.7 2.7 2 3.2l2.8 1.1c1.5.6 3.1.6 4.6 0l2.1-.7-.4 3.8H4c-1.1 0-1.9-1-1.7-2.1l.5-3 2.1-.7.3-8.7Z" fill="currentColor" stroke="currentColor" strokeWidth="1.4" strokeLinejoin="round" />
      <path d="m6.4 7.2 2.9 2.2-2.8 1.9 2.7 1.7M12.7 15.1l-1.5 3.1m5.2-2.4-1.1 2.4" stroke="var(--status-icon-cut, #5a1714)" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

export function CombatStatusBadges({
  statuses,
  compact = false,
  onStatusClick
}: {
  statuses: CombatStatus[];
  compact?: boolean;
  onStatusClick?: (status: CombatStatus) => void;
}) {
  if (!statuses.length) return null;
  return (
    <span className="flex flex-wrap items-center gap-1" aria-label="Active battle effects">
      {orderedCombatStatuses(statuses).map((status) => {
        const classes = status.kind === 'permanent'
          ? '[--status-icon-cut:#174d2c] border-[#84e09a] bg-[#174d2c] text-[#effff2] shadow-[0_0_8px_rgba(100,210,125,0.35),inset_0_1px_0_rgba(255,255,255,0.18)]'
          : status.kind === 'buff'
            ? '[--status-icon-cut:#174e73] border-[#83ccfa] bg-[#174e73] text-white shadow-[0_0_8px_rgba(89,185,245,0.38),inset_0_1px_0_rgba(255,255,255,0.18)]'
            : '[--status-icon-cut:#72231f] border-[#ff8278] bg-[#72231f] text-white shadow-[0_0_8px_rgba(239,91,80,0.38),inset_0_1px_0_rgba(255,255,255,0.18)]';
        const effectText = status.duration === null ? (status.amount > 0 ? `+${status.amount * 5}` : '') : String(status.duration);
        const title = status.duration === null
          ? `${status.name}: permanent${status.amount > 0 ? `, restores ${status.amount * 5} per turn` : ''}`
          : `${status.name}: ${status.duration} turn${status.duration === 1 ? '' : 's'}`;
        const content = <><StatusIcon status={status} size={compact ? 11 : 14} />{effectText && <span className="font-black leading-none">{effectText}</span>}</>;
        return onStatusClick && status.duration !== null ? (
          <button key={status.id} type="button" title={`${title}${status.duration === null ? '' : '. Edit duration.'}`} onClick={(event) => { event.stopPropagation(); onStatusClick(status); }} className={`inline-flex items-center gap-1 rounded-lg border shadow-md ${compact ? 'px-1.5 py-1 text-[10px]' : 'px-2 py-1.5 text-xs'} ${classes}`}>{content}</button>
        ) : (
          <span key={status.id} title={title} className={`inline-flex items-center gap-1 rounded-lg border shadow-md ${compact ? 'px-1.5 py-1 text-[10px]' : 'px-2 py-1.5 text-xs'} ${classes}`}>{content}</span>
        );
      })}
    </span>
  );
}
