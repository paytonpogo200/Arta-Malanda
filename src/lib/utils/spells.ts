import type { Spell, SpellType } from '@/lib/types';

export const spellTypes: SpellType[] = [
  'Ember',
  'Frost',
  'Lightning',
  'Earth',
  'Wind',
  'Energy',
  'Defensive Support',
  'Offensive Support',
  'Enhancement',
  'Utility'
];

export function normalizeSpellType(value?: string): SpellType {
  if (value === 'Enhancment') return 'Enhancement';
  return spellTypes.includes(value as SpellType) ? value as SpellType : 'Utility';
}

export function spellTypeClass(value?: string) {
  return `spell-type-card spell-type-${normalizeSpellType(value).toLowerCase().replace(/[^a-z0-9]+/g, '-')}`;
}

export function spellManaText(spell: Pick<Spell, 'manaCost' | 'manaLabel'>) {
  return spell.manaLabel || `${spell.manaCost} mana`;
}

export function spellTypeFromProductSection(section?: string) {
  const normalized = String(section || '').replace(/\s+Spells$/i, '').trim();
  return spellTypes.includes(normalized as SpellType) ? normalized as SpellType : null;
}
