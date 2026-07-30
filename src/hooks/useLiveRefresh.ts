'use client';

import { useEffect, useRef } from 'react';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';

type LiveRefreshOptions = {
  enabled?: boolean;
  debounceMs?: number;
};

type LiveUpdateRow = {
  scope?: string;
};

let liveClient: SupabaseClient | null | undefined;

function getLiveClient() {
  if (liveClient !== undefined) return liveClient;
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  liveClient = url && key
    ? createClient(url, key, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUrl: false
      }
    })
    : null;
  return liveClient;
}

export function useLiveRefresh(scopes: string[], onRefresh: () => void | Promise<void>, options: LiveRefreshOptions = {}) {
  const refreshRef = useRef(onRefresh);
  const scopesKey = scopes.join('|');
  const debounceMs = options.debounceMs ?? 250;
  const enabled = options.enabled ?? true;

  useEffect(() => {
    refreshRef.current = onRefresh;
  }, [onRefresh]);

  useEffect(() => {
    if (!enabled || !scopesKey) return undefined;
    const client = getLiveClient();
    if (!client) return undefined;

    const scopeSet = new Set(scopesKey.split('|').filter(Boolean));
    let timer: number | null = null;
    const channel = client.channel(`arta-live-${scopesKey}-${Math.random().toString(36).slice(2)}`);

    function queueRefresh() {
      if (timer !== null) window.clearTimeout(timer);
      timer = window.setTimeout(() => {
        timer = null;
        void refreshRef.current();
      }, debounceMs);
    }

    channel
      .on('postgres_changes', { event: '*', schema: 'public', table: 'app_live_updates' }, (payload) => {
        const row = payload.new as LiveUpdateRow | null;
        const scope = row?.scope ?? '';
        if (scopeSet.has(scope) || scopeSet.has('*')) queueRefresh();
      })
      .subscribe();

    return () => {
      if (timer !== null) window.clearTimeout(timer);
      void client.removeChannel(channel);
    };
  }, [debounceMs, enabled, scopesKey]);
}
