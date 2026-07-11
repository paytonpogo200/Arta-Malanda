'use client';

import { useMemo, useState } from 'react';
import { Bell, X } from 'lucide-react';
import type { DashboardNotice } from '@/features/dashboard/state';

type NotificationHubProps = {
  notices: DashboardNotice[];
  onRefresh: () => void;
};

function noticeLabel(kind: DashboardNotice['kind']) {
  if (kind === 'trade') return 'Trade';
  if (kind === 'announcement') return 'Announcement';
  if (kind === 'system') return 'System';
  return 'Notice';
}

export function NotificationHub({ notices, onRefresh }: NotificationHubProps) {
  const [open, setOpen] = useState(false);
  const unreadCount = notices.length;

  const orderedNotices = useMemo(() => {
    return [...notices].sort((a, b) => String(b.createdAt ?? '').localeCompare(String(a.createdAt ?? '')));
  }, [notices]);

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

      {open && (
        <div className="modal-backdrop" role="dialog" aria-modal="true" aria-label="Notifications">
          <section className="surface w-full max-w-md rounded-2xl p-4 sm:p-5">
            <div className="mb-4 flex items-center justify-between gap-3">
              <div>
                <p className="eyebrow">Campaign</p>
                <h2 className="mt-1 text-2xl font-black">Notifications</h2>
              </div>
              <button
                type="button"
                onClick={() => setOpen(false)}
                className="rounded-xl border border-[var(--line)] bg-black/20 p-3 text-[var(--muted)]"
                aria-label="Close notifications"
              >
                <X size={18} />
              </button>
            </div>

            <div className="grid gap-2">
              {orderedNotices.map((notice) => (
                <article key={notice.id} className="rounded-2xl border border-[var(--line)] bg-black/15 p-3">
                  <p className="text-[10px] font-black uppercase tracking-[0.2em] text-[var(--brass)]">{noticeLabel(notice.kind)}</p>
                  <h3 className="mt-1 text-base font-black">{notice.title}</h3>
                  {notice.body && <p className="mt-2 text-sm leading-6 text-[var(--muted)]">{notice.body}</p>}
                </article>
              ))}

              {!orderedNotices.length && (
                <div className="rounded-2xl border border-[var(--line)] bg-black/15 p-4 text-sm text-[var(--muted)]">
                  No notices.
                </div>
              )}
            </div>
          </section>
        </div>
      )}
    </>
  );
}
