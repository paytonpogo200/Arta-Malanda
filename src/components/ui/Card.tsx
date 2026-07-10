import type { HTMLAttributes, ReactNode } from 'react';

export function Card({ className = '', children, ...props }: HTMLAttributes<HTMLElement> & { children: ReactNode }) {
  return (
    <section {...props} className={`surface rounded-2xl p-4 sm:p-5 ${className}`}>
      {children}
    </section>
  );
}

export function SoftCard({ className = '', children, ...props }: HTMLAttributes<HTMLDivElement> & { children: ReactNode }) {
  return (
    <div {...props} className={`surface-soft rounded-xl p-3 ${className}`}>
      {children}
    </div>
  );
}
