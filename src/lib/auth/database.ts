import { createClient } from '@supabase/supabase-js';
import type { AuthProfile } from '@/lib/auth/session';

type AuthRow = {
  user_id: string;
  username: string;
  display_name: string;
  role: 'player' | 'dm';
  session_token?: string;
  expires_at?: string;
};

export function createAuthDatabaseClient() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  if (!url || !key) return null;
  return createClient(url, key, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false
    }
  });
}

export function toAuthProfile(row: AuthRow): AuthProfile {
  return {
    id: row.user_id,
    username: row.username,
    displayName: row.display_name,
    role: row.role
  };
}
