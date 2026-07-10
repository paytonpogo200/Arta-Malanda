import { percent } from '@/lib/utils/format';

export function ResourceBar({ current, max, tone, label }: { current: number; max: number; tone: 'hp' | 'mana'; label: string }) {
  const color = tone === 'hp' ? 'from-[#b9332e] to-[#ff9c8e]' : 'from-[#336cbb] to-[#9ed1ff]';
  return (
    <div>
      <div className="mb-1 flex justify-between text-[10px] font-black uppercase tracking-wide text-[var(--muted)]">
        <span>{label}</span>
        <span>{current}/{max}</span>
      </div>
      <div className="stat-bar">
        <span className={`bg-gradient-to-r ${color}`} style={{ width: `${percent(current, max)}%` }} />
      </div>
    </div>
  );
}
