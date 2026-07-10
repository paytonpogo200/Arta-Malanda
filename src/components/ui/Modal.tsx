'use client';

import { X } from 'lucide-react';
import { createPortal } from 'react-dom';
import type { ReactNode } from 'react';
import { Button } from '@/components/ui/Button';

export function Modal({ title, children, onClose }: { title?: string; children: ReactNode; onClose: () => void }) {
  if (typeof document === 'undefined') return null;

  return createPortal(
    <div className="modal-backdrop" role="dialog" aria-modal="true">
      <section className="surface w-[min(94vw,42rem)] rounded-2xl p-4">
        <div className="mb-4 flex items-start justify-between gap-3">
          {title ? <h3 className="text-2xl font-black">{title}</h3> : <span />}
          <Button variant="ghost" className="p-2" onClick={onClose} aria-label="Close">
            <X size={18} />
          </Button>
        </div>
        {children}
      </section>
    </div>,
    document.body
  );
}
