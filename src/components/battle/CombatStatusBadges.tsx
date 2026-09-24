'use client';

import { Accessibility, BicepsFlexed, Cross, Dices, Droplet, Flame, FlaskConical, Footprints, Link2, RefreshCcw, Shield, Shell, Sparkles, Wind } from 'lucide-react';
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
  if (Icon) return <Icon size={size} />;
  if (status.key === 'swiftness') return <span className="relative grid place-items-center"><Footprints size={size} /><Wind className="absolute -right-1 -top-1" size={Math.max(8, size - 4)} /></span>;
  if (status.key === 'invisible') return <span className="grid place-items-center rounded-full border border-dashed border-current p-px opacity-80"><Accessibility size={Math.max(9, size - 2)} /></span>;
  if (status.key === 'bleeding') return <span className="relative grid place-items-center"><Cross size={size} /><Link2 className="absolute rotate-45" size={Math.max(9, size - 2)} /><Link2 className="absolute -rotate-45" size={Math.max(9, size - 2)} /></span>;
  if (status.key === 'slowness') return <span className="relative grid place-items-center"><Footprints size={size} /><span className="absolute h-[2px] w-[120%] rotate-[-35deg] bg-current" /></span>;
  if (status.key === 'weakness') return <span className="relative grid place-items-center"><BicepsFlexed size={size} /><span className="absolute h-[2px] w-[120%] rotate-[-35deg] bg-current" /></span>;
  return <Sparkles size={size} />;
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
          ? 'border-[#64b878] bg-[#174d2c] text-[#d9ffe2]'
          : status.kind === 'buff'
            ? 'border-[#62aee0] bg-[#174e73] text-[#d9f2ff]'
            : 'border-[#df665d] bg-[#72231f] text-[#ffe0da]';
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
