import type { ReactNode } from 'react';

function normalizedLevel(level: number | null | undefined) {
  return Math.max(1, Math.floor(Number(level) || 1));
}

export type CharacterLevelFrameVariant = 'ledger' | 'sheet' | 'sheet-edit' | 'battle-card';

export function characterLevelFrameClass(level: number | null | undefined, variant: CharacterLevelFrameVariant = 'sheet') {
  const value = normalizedLevel(level);
  if (value >= 3) return `character-level-frame character-level-frame-${variant} character-level-frame-3`;
  if (value >= 2) return `character-level-frame character-level-frame-${variant} character-level-frame-2`;
  return '';
}

export function characterLevelTokenClass(level: number | null | undefined) {
  const value = normalizedLevel(level);
  if (value >= 3) return 'character-level-token character-level-token-3';
  if (value >= 2) return 'character-level-token character-level-token-2';
  return '';
}

export function LevelBadge({ level, compact = false }: { level: number | null | undefined; compact?: boolean }) {
  const value = normalizedLevel(level);
  if (value <= 1) return null;
  return (
    <span className={`level-badge level-badge-${value >= 3 ? '3' : '2'} ${compact ? 'level-badge-compact' : ''}`}>
      Lv. {value}
    </span>
  );
}

export function LevelPips({ level }: { level: number | null | undefined }) {
  const value = normalizedLevel(level);
  if (value <= 1) return null;
  const pipCount = value >= 3 ? 2 : 1;
  const pips: ReactNode[] = [];
  for (let index = 0; index < pipCount; index += 1) {
    pips.push(<span key={index} />);
  }
  return <span className={`level-pips level-pips-${value >= 3 ? '3' : '2'}`}>{pips}</span>;
}
