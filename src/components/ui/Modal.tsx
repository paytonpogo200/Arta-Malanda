'use client';

import { X } from 'lucide-react';
import { createPortal } from 'react-dom';
import type { ReactNode } from 'react';
import { Button } from '@/components/ui/Button';

export function Modal({ title, children, onClose, size = 'default' }: { title?: string; children: ReactNode; onClose: () => void; size?: 'default' | 'wide' }) {
  if (typeof document === 'undefined') return null;

  const widthClass = size === 'wide' ? 'w-[min(96vw,72rem)]' : 'w-[min(94vw,42rem)]';

  return createPortal(
    <div className="modal-backdrop" role="dialog" aria-modal="true">
      <section className={`modal-panel surface flex max-h-[calc(100dvh-var(--bottom-nav-space)-1rem)] ${widthClass} flex-col overflow-hidden rounded-2xl p-4`}>
        <div className="mb-4 flex shrink-0 items-start justify-between gap-3">
          {title ? <h3 className="text-2xl font-black">{title}</h3> : <span />}
          <Button variant="ghost" className="p-2" onClick={onClose} aria-label="Close">
            <X size={18} />
          </Button>
        </div>
        <div className="modal-body thin-scrollbar min-h-0 flex-1 overflow-y-auto pr-1">
          {children}
        </div>
      </section>
    </div>,
    document.body
  );
}
