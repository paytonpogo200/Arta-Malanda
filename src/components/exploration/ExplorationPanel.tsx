'use client';

import Link from 'next/link';
import { Compass, Dice6 } from 'lucide-react';
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

      <Link
        href="/dashboard/exploration/loot"
        className="block rounded-3xl border border-[var(--line)] bg-black/20 p-4 text-[var(--paper)] transition hover:border-[var(--brass)] active:scale-[0.99]"
      >
        <span className="flex items-center gap-3">
          <span className="grid h-12 w-12 place-items-center rounded-2xl border border-[var(--line)] bg-black/25 text-[var(--brass)]">
            <Dice6 size={24} />
          </span>
          <span>
            <span className="block text-sm font-black uppercase tracking-wider text-[var(--brass)]">Loot Generator</span>
            <span className="mt-1 block text-sm font-bold text-[var(--muted)]">Open the full loot workbook import, odds preview, and loot rolling tool.</span>
          </span>
        </span>
      </Link>
    </div>
  );
}
