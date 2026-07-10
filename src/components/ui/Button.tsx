import type { ButtonHTMLAttributes, ReactNode } from 'react';

type ButtonVariant = 'primary' | 'secondary' | 'ghost' | 'danger' | 'teal';

const variantClass: Record<ButtonVariant, string> = {
  primary: 'primary-button',
  teal: 'teal-button',
  secondary: 'border border-[var(--line)] bg-black/20 text-[var(--paper)]',
  ghost: 'text-[var(--muted)] hover:text-[var(--paper)]',
  danger: 'border border-[#d2735855] bg-[#d2735812] text-[var(--red)]'
};

export function Button({
  variant = 'secondary',
  className = '',
  children,
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & { variant?: ButtonVariant; children: ReactNode }) {
  return (
    <button
      {...props}
      className={`rounded-xl px-4 py-3 text-sm font-black transition active:scale-[0.98] disabled:cursor-not-allowed disabled:opacity-45 ${variantClass[variant]} ${className}`}
    >
      {children}
    </button>
  );
}
