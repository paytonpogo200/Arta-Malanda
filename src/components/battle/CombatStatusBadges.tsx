'use client';

import { Flame, FlaskConical, Sparkles } from 'lucide-react';
import type { CombatStatus } from '@/lib/types';

export function orderedCombatStatuses(statuses: CombatStatus[]) {
  return [...statuses].sort((a, b) => {
    const priority = (status: CombatStatus) => status.key === 'burning' ? 0 : status.key === 'poison' ? 1 : status.kind === 'debuff' ? 2 : 3;
    return priority(a) - priority(b) || a.name.localeCompare(b.name) || a.id.localeCompare(b.id);
  });
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
        const isBurning = status.key === 'burning';
        const isPoison = status.key === 'poison';
        const isDebuff = status.kind === 'debuff';
        const Icon = isBurning ? Flame : isPoison ? FlaskConical : Sparkles;
        const classes = isDebuff
          ? isBurning ? 'border-[#ff765f] bg-[#8b261f] text-[#ffe0d5]' : 'border-[#d96b8d] bg-[#681f3a] text-[#ffd9e6]'
          : 'border-[#67b7e8] bg-[#164d73] text-[#d9f2ff]';
        const content = <><Icon size={compact ? 11 : 14} /><span className="font-black leading-none">{status.duration}</span></>;
        return onStatusClick ? (
          <button key={status.id} type="button" title={`${status.name}: ${status.duration} turn${status.duration === 1 ? '' : 's'}. Edit duration.`} onClick={(event) => { event.stopPropagation(); onStatusClick(status); }} className={`inline-flex items-center gap-1 rounded-lg border shadow-md ${compact ? 'px-1.5 py-1 text-[10px]' : 'px-2 py-1.5 text-xs'} ${classes}`}>{content}</button>
        ) : (
          <span key={status.id} title={`${status.name}: ${status.duration} turn${status.duration === 1 ? '' : 's'}`} className={`inline-flex items-center gap-1 rounded-lg border shadow-md ${compact ? 'px-1.5 py-1 text-[10px]' : 'px-2 py-1.5 text-xs'} ${classes}`}>{content}</span>
        );
      })}
    </span>
  );
}
