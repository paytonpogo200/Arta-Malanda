import type { CharacterSpell, ItemRarity, Spell, SpellSchool } from '@/lib/types';

export type CharacterSpellsPayload = {
  catalog: Spell[];
  spells: CharacterSpell[];
  activeBattle: boolean;
};

export const SPELL_SCHOOLS: SpellSchool[] = ['arcane', 'restoration', 'nature', 'alchemy', 'rune', 'shadow', 'martial'];
const RARITIES: ItemRarity[] = ['Common', 'Uncommon', 'Rare', 'Epic', 'Legendary', 'Mythical'];

function numberFrom(value: unknown, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function normalizeSchool(value: unknown): SpellSchool {
  return SPELL_SCHOOLS.includes(value as SpellSchool) ? value as SpellSchool : 'arcane';
}

function normalizeRarity(value: unknown): ItemRarity {
  return RARITIES.includes(value as ItemRarity) ? value as ItemRarity : 'Common';
}

export function normalizeSpell(value: unknown): Spell {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  return {
    id: String(source.id ?? ''),
    key: String(source.key ?? ''),
    name: String(source.name ?? 'Unknown Spell'),
    school: normalizeSchool(source.school),
    manaCost: Math.max(0, numberFrom(source.manaCost, 0)),
    summary: String(source.summary ?? ''),
    details: String(source.details ?? ''),
    rarity: normalizeRarity(source.rarity)
  };
}

export function normalizeCharacterSpell(value: unknown): CharacterSpell {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  return {
    id: String(source.id ?? ''),
    characterId: String(source.characterId ?? ''),
    spellId: String(source.spellId ?? ''),
    active: Boolean(source.active),
    slotIndex: source.slotIndex === null || source.slotIndex === undefined ? null : Math.max(0, numberFrom(source.slotIndex, 0)),
    spell: normalizeSpell(source.spell)
  };
}

export function normalizeCharacterSpellsPayload(value: unknown): CharacterSpellsPayload {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  return {
    catalog: Array.isArray(source.catalog) ? source.catalog.map(normalizeSpell).filter((spell) => spell.id) : [],
    spells: Array.isArray(source.spells) ? source.spells.map(normalizeCharacterSpell).filter((entry) => entry.id) : [],
    activeBattle: Boolean(source.activeBattle)
  };
}
