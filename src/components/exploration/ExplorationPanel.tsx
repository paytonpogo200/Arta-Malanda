'use client';

import Link from 'next/link';
import { ChevronRight, Compass, Waypoints } from 'lucide-react';
import { Card } from '@/components/ui/Card';

export function ExplorationPanel() {
  return (
    <div className="space-y-4">
      <Card>
        <div className="flex items-center gap-3">
          <span className="grid h-12 w-12 place-items-center rounded-2xl border border-[var(--brass)]/45 bg-[var(--brass)]/15 text-[var(--brass)]">
            <Compass size={24} />
          </span>
          <div>
            <p className="eyebrow">DM Tools</p>
            <h2 className="text-2xl font-black">Exploration</h2>
          </div>
        </div>
      </Card>

      <div className="grid gap-3 md:grid-cols-2">
        <Card className="overflow-hidden">
          <Link
            href="/dashboard/exploration/loot"
            className="group block w-full rounded-2xl border border-[var(--line)] bg-gradient-to-br from-[rgba(245,180,76,0.16)] via-black/10 to-[rgba(31,120,117,0.14)] p-4 text-left text-[var(--paper)] transition hover:border-[var(--brass)]/70 active:scale-[0.99]"
          >
            <span className="flex items-start justify-between gap-3">
              <span className="min-w-0">
                <span className="eyebrow">Exploration Tool</span>
                <span className="mt-1 block text-xl font-black leading-tight">Loot Generator</span>
                <span className="mt-1 block text-xs font-bold text-[var(--muted)]">Workbook import, odds preview, and loot rolling</span>
              </span>
              <span className="rounded-full border border-[var(--line)] bg-black/25 p-2 text-[var(--brass)]">
                <ChevronRight size={18} />
              </span>
            </span>
          </Link>
        </Card>

        <Card className="overflow-hidden">
          <Link
            href="/dashboard/exploration/caves"
            className="group block w-full rounded-2xl border border-[var(--line)] bg-gradient-to-br from-[rgba(86,226,194,0.13)] via-black/10 to-[rgba(245,180,76,0.16)] p-4 text-left text-[var(--paper)] transition hover:border-[var(--brass)]/70 active:scale-[0.99]"
          >
            <span className="flex items-start justify-between gap-3">
              <span className="min-w-0">
                <span className="eyebrow">Exploration Tool</span>
                <span className="mt-1 flex items-center gap-2 text-xl font-black leading-tight"><Waypoints size={20} className="text-[var(--brass)]" /> Caves</span>
                <span className="mt-1 block text-xs font-bold text-[var(--muted)]">Cave catalog, tunnel details, nicknames, and generated maps</span>
              </span>
              <span className="rounded-full border border-[var(--line)] bg-black/25 p-2 text-[var(--brass)]">
                <ChevronRight size={18} />
              </span>
            </span>
          </Link>
        </Card>
      </div>
    </div>
  );
}
