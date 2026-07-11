import { redirect } from 'next/navigation';
import { DashboardClient } from '@/components/app-shell/DashboardClient';
import { createAuthDatabaseClient, toAuthProfile } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

export default async function DashboardPage() {
  const token = await readSessionToken();
  if (!token) redirect('/login');

  const supabase = createAuthDatabaseClient();
  if (!supabase) redirect('/login');

  const { data, error } = await supabase.rpc('get_campaign_session', { p_session_token: token });
  const row = Array.isArray(data) ? data[0] : data;
  if (error || !row) redirect('/login');

  return <DashboardClient profile={toAuthProfile(row)} />;
}
