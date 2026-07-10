'use client';

import { useEffect, useState, type InputHTMLAttributes } from 'react';

type Props = Omit<InputHTMLAttributes<HTMLInputElement>, 'type' | 'value' | 'onChange'> & {
  value: number;
  onValueChange: (value: number) => void;
  emptyFallback?: number;
};

export function NumberInput({ value, onValueChange, emptyFallback = 0, onBlur, className = '', ...props }: Props) {
  const [draft, setDraft] = useState(String(value));

  useEffect(() => {
    setDraft(String(value));
  }, [value]);

  return (
    <input
      {...props}
      type="number"
      value={draft}
      className={`field ${className}`}
      onChange={(event) => {
        const next = event.target.value;
        setDraft(next);
        if (next !== '' && next !== '-' && Number.isFinite(Number(next))) onValueChange(Number(next));
      }}
      onBlur={(event) => {
        if (draft === '' || draft === '-' || !Number.isFinite(Number(draft))) {
          setDraft(String(emptyFallback));
          onValueChange(emptyFallback);
        }
        onBlur?.(event);
      }}
    />
  );
}
