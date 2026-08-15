import type { InputHTMLAttributes, SelectHTMLAttributes, TextareaHTMLAttributes } from 'react';

export function TextField(props: InputHTMLAttributes<HTMLInputElement>) {
  return <input {...props} className={`field ${props.className ?? ''}`} />;
}

export function ColorField({ value, className, ...props }: InputHTMLAttributes<HTMLInputElement>) {
  const color = typeof value === 'string' ? value : '#9caf79';
  return (
    <label className={`field flex min-h-14 cursor-pointer items-center gap-3 px-3 py-2 ${className ?? ''}`}>
      <input {...props} type="color" value={color} className="sr-only" />
      <span className="h-10 w-16 shrink-0 rounded-xl border border-white/25 shadow-inner" style={{ backgroundColor: color }} />
      <span className="font-black uppercase tracking-wider text-[var(--paper)]">{color}</span>
    </label>
  );
}

export function SelectField(props: SelectHTMLAttributes<HTMLSelectElement>) {
  return <select {...props} className={`field ${props.className ?? ''}`} />;
}

export function TextAreaField(props: TextareaHTMLAttributes<HTMLTextAreaElement>) {
  return <textarea {...props} className={`field ${props.className ?? ''}`} />;
}
