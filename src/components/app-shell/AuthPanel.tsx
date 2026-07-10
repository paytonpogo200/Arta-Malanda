'use client';

import { useState, type FormEvent } from 'react';
import Link from 'next/link';
import { BookOpen, Map, ScrollText } from 'lucide-react';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/Field';
import { createClient } from '@/lib/supabase/client';

export function AuthPanel() {
  const supabase = createClient();
  const [mode, setMode] = useState<'login' | 'signup'>('login');
  const [displayName, setDisplayName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [message, setMessage] = useState('');
  const [busy, setBusy] = useState(false);

  async function submit(event: FormEvent) {
    event.preventDefault();
    setMessage('');

    if (!supabase) {
      setMessage('Preview mode: Supabase is not connected yet. Use the demo dashboard.');
      return;
    }

    if (mode === 'signup' && password !== confirmPassword) {
      setMessage('Passwords must match.');
      return;
    }

    setBusy(true);
    const result = mode === 'login'
      ? await supabase.auth.signInWithPassword({ email, password })
      : await supabase.auth.signUp({ email, password, options: { data: { display_name: displayName || email.split('@')[0] } } });
    setBusy(false);

    if (result.error) {
      setMessage(result.error.message);
      return;
    }

    window.location.href = '/dashboard';
  }

  return (
    <main className="app-shell flex min-h-screen items-center justify-center px-4 py-10">
      <section className="surface w-full max-w-5xl overflow-hidden rounded-[2rem] p-0">
        <div className="grid min-h-[38rem] md:grid-cols-[1.08fr_0.92fr]">
          <div className="flex flex-col justify-between gap-8 p-6 sm:p-8">
            <div>
              <p className="eyebrow mb-3">Ladders and Snakes Campaign Table</p>
              <h1 className="fantasy-title text-4xl font-black tracking-[-0.04em] sm:text-6xl">Welcome! To the world of Arta Malanda.</h1>
              <p className="mt-5 max-w-xl text-base leading-7 text-[var(--muted)] sm:text-lg">
                In a world gone bleak after the Dozen-Year War, what possibilities await?
              </p>
            </div>

            <div className="grid gap-3 sm:grid-cols-3">
              {[
                { icon: Map, label: 'Battle map' },
                { icon: BookOpen, label: 'Character Sheets' },
                { icon: ScrollText, label: 'Working Shops' }
              ].map(({ icon: Icon, label }) => (
                <div key={label} className="surface-soft rounded-2xl p-4">
                  <Icon className="mb-3 text-[var(--brass)]" size={22} />
                  <p className="text-sm font-black">{label}</p>
                </div>
              ))}
            </div>
          </div>

          <form onSubmit={submit} className="border-t border-[var(--line)] bg-black/20 p-6 sm:p-8 md:border-l md:border-t-0">
            <div className="mb-5 grid grid-cols-2 gap-2 rounded-2xl bg-black/25 p-1 text-sm font-black">
              <button type="button" onClick={() => setMode('login')} className={`rounded-xl py-3 ${mode === 'login' ? 'bg-[var(--paper)] text-[#201006]' : 'text-[var(--muted)]'}`}>Login</button>
              <button type="button" onClick={() => setMode('signup')} className={`rounded-xl py-3 ${mode === 'signup' ? 'bg-[var(--paper)] text-[#201006]' : 'text-[var(--muted)]'}`}>Sign up</button>
            </div>

            <div className="grid gap-3">
              {mode === 'signup' && <TextField value={displayName} onChange={(event) => setDisplayName(event.target.value)} placeholder="Display name" />}
              <TextField required type="email" value={email} onChange={(event) => setEmail(event.target.value)} placeholder="Email" />
              <TextField required type="password" value={password} onChange={(event) => setPassword(event.target.value)} placeholder="Password" />
              {mode === 'signup' && <TextField required type="password" value={confirmPassword} onChange={(event) => setConfirmPassword(event.target.value)} placeholder="Confirm password" />}
            </div>

            <Button variant="primary" disabled={busy} className="mt-4 w-full">
              {busy ? 'Working…' : mode === 'login' ? 'Enter the table' : 'Create account'}
            </Button>

            <div className="mt-4 flex flex-wrap items-center justify-between gap-3 text-sm">
              <Link className="text-[var(--muted)] underline decoration-[var(--line)] underline-offset-4" href="/reset-password">Recover password</Link>
              <Link className="font-black text-[var(--brass)]" href="/dashboard">Open demo dashboard</Link>
            </div>
            {message && <p className="mt-4 rounded-xl border border-[var(--line)] bg-black/20 p-3 text-sm leading-6 text-[var(--muted)]">{message}</p>}
          </form>
        </div>
      </section>
    </main>
  );
}
