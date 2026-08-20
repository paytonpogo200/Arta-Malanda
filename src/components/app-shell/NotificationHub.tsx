'use client';

import { useEffect, useMemo, useState, type FormEvent } from 'react';
import { Bell, Check, Loader2, Megaphone, X } from 'lucide-react';
import { createPortal } from 'react-dom';
import { Button } from '@/components/ui/Button';
import { SelectField, TextAreaField, TextField } from '@/components/ui/Field';
import { normalizeCitiesPayload } from '@/features/cities/data';
import type { DashboardNotice } from '@/features/dashboard/state';
import type { Profile, TradeStatus } from '@/lib/types';

type NotificationHubProps = {
  profile: Profile;
  notices: DashboardNotice[];
  onRefresh: () => void;
};

function noticeLabel(kind: DashboardNotice['kind']) {
  if (kind === 'trade') return 'Trade';
  if (kind === 'announcement') return 'Announcement';
  if (kind === 'system') return 'System';
  return 'Notice';
}

function cleanNotificationText(value: string) {
  return value
    .replace(/\b(\d+)\.(\d*?[1-9])0{2,}\b/g, '$1.$2')
    .replace(/\b(\d+)\.0{2,}\b/g, '$1');
}

export function NotificationHub({ profile, notices, onRefresh }: NotificationHubProps) {
  const [open, setOpen] = useState(false);
  const [announcing, setAnnouncing] = useState(false);
  const [busyId, setBusyId] = useState('');
  const [noticeError, setNoticeError] = useState('');
  const [announcement, setAnnouncement] = useState({
    title: '',
    body: '',
    locationName: 'All locations',
    inWorld: false
  });
  const [locationOptions, setLocationOptions] = useState<string[]>(['All locations', 'Calostrynn', 'Wild']);
  const unreadCount = notices.length;
  const isDm = profile.role === 'dm';

  const orderedNotices = useMemo(() => {
    return [...notices].sort((a, b) => String(b.createdAt ?? '').localeCompare(String(a.createdAt ?? '')));
  }, [notices]);

  useEffect(() => {
    if (!isDm) return;
    let active = true;

    async function loadCityLocations() {
      try {
        const response = await fetch('/api/cities', { cache: 'no-store' });
        const payload = await response.json().catch(() => ({}));
        if (!response.ok) throw new Error(payload.error ?? 'Cities could not be loaded.');
        const cities = normalizeCitiesPayload(payload)
          .cities
          .slice()
          .sort((a, b) => a.order - b.order || a.name.localeCompare(b.name))
          .map((city) => city.name);
        if (active && cities.length) setLocationOptions(['All locations', ...cities, 'Wild']);
      } catch {
        if (active) setLocationOptions((current) => current.length ? current : ['All locations', 'Calostrynn', 'Wild']);
      }
    }

    void loadCityLocations();
    return () => {
      active = false;
    };
  }, [isDm]);

  async function markRead(noticeId: string) {
    setBusyId(noticeId);
    setNoticeError('');
    try {
      await fetch(`/api/notifications/${noticeId}`, { method: 'PATCH' });
      onRefresh();
    } catch {
      // Notification dismissal is intentionally non-blocking.
    } finally {
      setBusyId('');
    }
  }

  async function respondToTrade(tradeId: string, status: TradeStatus) {
    setBusyId(`${tradeId}:${status}`);
    setNoticeError('');
    try {
      const response = await fetch(`/api/trades/${tradeId}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ status })
      });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.error ?? 'Trade could not be updated.');
      onRefresh();
    } catch (error) {
      setNoticeError(error instanceof Error ? error.message : 'Trade could not be updated.');
    } finally {
      setBusyId('');
    }
  }

  async function sendAnnouncement(event: FormEvent) {
    event.preventDefault();
    if (!isDm || !announcement.title.trim()) return;
    setBusyId('announcement');
    setNoticeError('');
    try {
      const response = await fetch('/api/notifications/announcements', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          ...announcement,
          locationName: announcement.locationName === 'All locations' ? '' : announcement.locationName
        })
      });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.error ?? 'Announcement could not be sent.');
      setAnnouncement({ title: '', body: '', locationName: 'All locations', inWorld: false });
      setAnnouncing(false);
      onRefresh();
    } catch (error) {
      setNoticeError(error instanceof Error ? error.message : 'Announcement could not be sent.');
    } finally {
      setBusyId('');
    }
  }

  return (
    <>
      <button
        type="button"
        onClick={() => {
          setOpen(true);
          onRefresh();
        }}
        className="relative rounded-xl border border-[var(--line)] bg-black/20 p-3 text-[var(--muted)] transition active:scale-95"
        aria-label="Open notifications"
      >
        <Bell size={18} />
        {unreadCount > 0 && (
          <span className="absolute -right-1 -top-1 grid h-5 min-w-5 place-items-center rounded-full bg-[var(--red)] px-1 text-[10px] font-black text-white">
            {unreadCount > 9 ? '9+' : unreadCount}
          </span>
        )}
      </button>

      {open && typeof document !== 'undefined' && createPortal(
        <div className="modal-backdrop" role="dialog" aria-modal="true" aria-label="Notifications">
          <section className="modal-panel surface flex max-h-[calc(100dvh-var(--bottom-nav-space)-1rem)] w-[min(94vw,32rem)] flex-col overflow-hidden rounded-2xl p-4 sm:p-5">
            <div className="mb-4 flex items-center justify-between gap-3">
              <div>
                <p className="eyebrow">Campaign</p>
                <h2 className="mt-1 text-2xl font-black">Notifications</h2>
              </div>
              <div className="flex gap-2">
                {isDm && (
                  <button
                    type="button"
                    onClick={() => setAnnouncing((value) => !value)}
                    className="rounded-xl border border-[var(--line)] bg-black/20 p-3 text-[var(--muted)]"
                    aria-label="Draft announcement"
                  >
                    <Megaphone size={18} />
                  </button>
                )}
                <button
                  type="button"
                  onClick={() => setOpen(false)}
                  className="rounded-xl border border-[var(--line)] bg-black/20 p-3 text-[var(--muted)]"
                  aria-label="Close notifications"
                >
                  <X size={18} />
                </button>
              </div>
            </div>

            {noticeError && <div className="mb-3 rounded-xl border border-[var(--red)]/40 bg-[var(--red)]/10 p-3 text-sm text-[var(--red)]">{noticeError}</div>}

            {announcing && (
              <form onSubmit={sendAnnouncement} className="mb-4 grid gap-2 rounded-2xl border border-[var(--line)] bg-black/15 p-3">
                <TextField placeholder="Announcement title" value={announcement.title} onChange={(event) => setAnnouncement({ ...announcement, title: event.target.value })} />
                <TextAreaField rows={4} placeholder="Announcement text" value={announcement.body} onChange={(event) => setAnnouncement({ ...announcement, body: event.target.value })} />
                <div className="grid gap-2 sm:grid-cols-[1fr_auto]">
                  <SelectField value={announcement.locationName} onChange={(event) => setAnnouncement({ ...announcement, locationName: event.target.value })}>
                    {locationOptions.map((location) => <option key={location} value={location}>{location}</option>)}
                  </SelectField>
                  <label className="flex items-center gap-2 rounded-xl border border-[var(--line)] bg-black/20 px-3 py-2 text-xs font-black uppercase tracking-wide text-[var(--muted)]">
                    <input type="checkbox" checked={announcement.inWorld} onChange={(event) => setAnnouncement({ ...announcement, inWorld: event.target.checked })} />
                    NPC voice
                  </label>
                </div>
                <Button variant="primary" disabled={!announcement.title.trim() || busyId === 'announcement'} className="flex items-center justify-center gap-2">
                  {busyId === 'announcement' ? <Loader2 size={15} className="animate-spin" /> : <Megaphone size={15} />} Send announcement
                </Button>
              </form>
            )}

            <div className="modal-body thin-scrollbar grid min-h-0 flex-1 gap-2 overflow-y-auto pr-1">
              {orderedNotices.map((notice) => (
                <article key={notice.id} className="rounded-2xl border border-[var(--line)] bg-black/15 p-3">
                  <div className="flex items-start justify-between gap-3">
                    <div>
                      <p className="text-[10px] font-black uppercase tracking-[0.2em] text-[var(--brass)]">{noticeLabel(notice.kind)}</p>
                      <h3 className="mt-1 text-base font-black">{notice.title}</h3>
                    </div>
                    <button type="button" onClick={() => markRead(notice.id)} className="rounded-lg border border-[var(--line)] bg-black/20 p-2 text-[var(--muted)]" aria-label="Mark read">
                      {busyId === notice.id ? <Loader2 size={14} className="animate-spin" /> : <Check size={14} />}
                    </button>
                  </div>
                  {notice.body && <p className="mt-2 whitespace-pre-line text-sm leading-6 text-[var(--muted)]">{cleanNotificationText(notice.body)}</p>}
                  {notice.kind === 'trade' && notice.sourceId && (
                    <div className="mt-3 grid grid-cols-2 gap-2">
                      <Button variant="teal" onClick={() => respondToTrade(notice.sourceId!, 'accepted')} disabled={busyId.startsWith(notice.sourceId)}>
                        Accept
                      </Button>
                      <Button variant="danger" onClick={() => respondToTrade(notice.sourceId!, 'declined')} disabled={busyId.startsWith(notice.sourceId)}>
                        Decline
                      </Button>
                    </div>
                  )}
                </article>
              ))}

              {!orderedNotices.length && (
                <div className="rounded-2xl border border-[var(--line)] bg-black/15 p-4 text-sm text-[var(--muted)]">
                  No notices.
                </div>
              )}
            </div>
          </section>
        </div>,
        document.body
      )}
    </>
  );
}
