import Link from 'next/link';
import { redirect } from 'next/navigation';
import { ArrowLeft } from 'lucide-react';
import { LootGeneratorPanel } from '@/components/exploration/LootGeneratorPanel';
import { Card } from '@/components/ui/Card';
import { createAuthDatabaseClient, toAuthProfile } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

export default async function LootGeneratorPage() {
  const token = await readSessionToken();
  if (!token) redirect('/login');

  const supabase = createAuthDatabaseClient();
  if (!supabase) redirect('/login');

  const { data, error } = await supabase.rpc('get_campaign_session', { p_session_token: token });
  const row = Array.isArray(data) ? data[0] : data;
  if (error || !row) redirect('/login');

  const profile = toAuthProfile(row);
  if (profile.role !== 'dm') redirect('/dashboard');

  return (
    <main className="app-shell min-h-screen px-4 py-4 text-[var(--paper)]">
      <section className="mx-auto grid max-w-6xl gap-4">
        <Card>
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div>
              <p className="eyebrow">Exploration</p>
              <h1 className="text-2xl font-black">Loot Generator</h1>
            </div>
            <Link
              href="/dashboard"
              className="rounded-xl border border-[var(--line)] bg-black/20 px-4 py-3 text-sm font-black text-[var(--paper)] transition active:scale-[0.98]"
            >
              <ArrowLeft className="mr-2 inline" size={15} /> Dashboard
            </Link>
          </div>
        </Card>
        <LootGeneratorPanel />
      </section>
    </main>
  );
}
