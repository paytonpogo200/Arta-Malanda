import { ATTRIBUTE_LABELS, type InventoryItem, type ItemType, type LoadoutModifierKey, type LoadoutModifiers, type Spell } from '@/lib/types';
import { signed } from '@/lib/utils/format';

export const EDITABLE_MODIFIER_FIELDS: Array<{ key: LoadoutModifierKey; label: string }> = [
  { key: 'strength', label: ATTRIBUTE_LABELS.strength },
  { key: 'accuracy', label: ATTRIBUTE_LABELS.accuracy },
  { key: 'intelligence', label: ATTRIBUTE_LABELS.intelligence },
  { key: 'vitality', label: ATTRIBUTE_LABELS.vitality },
  { key: 'recovery', label: ATTRIBUTE_LABELS.recovery },
  { key: 'mana_regen', label: ATTRIBUTE_LABELS.mana_regen },
  { key: 'charisma', label: ATTRIBUTE_LABELS.charisma },
  { key: 'wisdom_cunning', label: ATTRIBUTE_LABELS.wisdom_cunning },
  { key: 'perception', label: ATTRIBUTE_LABELS.perception },
  { key: 'alchemy', label: ATTRIBUTE_LABELS.alchemy },
  { key: 'stealth', label: ATTRIBUTE_LABELS.stealth },
  { key: 'agility', label: ATTRIBUTE_LABELS.agility },
  { key: 'defense', label: 'Defense' },
  { key: 'magic_resist', label: 'Magic Resist' },
  { key: 'health', label: 'Health' },
  { key: 'mana', label: 'Mana' }
];

const modifierOrder = new Map(EDITABLE_MODIFIER_FIELDS.map((field, index) => [field.key, index]));

export type ItemDetailLike = {
  name: string;
  type: ItemType;
  material?: string;
  enchantment?: string;
  modifiers?: LoadoutModifiers;
};

function numberFrom(value: unknown) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

export function cleanModifiers(modifiers: LoadoutModifiers = {}) {
  return Object.fromEntries(
    Object.entries(modifiers)
      .map(([key, value]) => [key, numberFrom(value)] as const)
      .filter(([, value]) => value !== 0)
  ) as LoadoutModifiers;
}

export function modifierLabel(key: string) {
  if (key in ATTRIBUTE_LABELS) return ATTRIBUTE_LABELS[key as keyof typeof ATTRIBUTE_LABELS];
  if (key === 'magic_resist' || key === 'magicResist' || key === 'magicResistance') return 'Magic Resist';
  if (key === 'health' || key === 'hp' || key === 'maxHp' || key === 'max_hp') return 'Health';
  if (key === 'mana' || key === 'maxMana' || key === 'max_mana') return 'Mana';
  if (key === 'defence') return 'Defense';
  return key.replace(/_/g, ' ').replace(/\b\w/g, (letter) => letter.toUpperCase());
}

export function modifierEntries(modifiers: LoadoutModifiers = {}) {
  return Object.entries(cleanModifiers(modifiers))
    .map(([key, value]) => ({
      key: key as LoadoutModifierKey,
      label: modifierLabel(key),
      value
    }))
    .sort((a, b) => (modifierOrder.get(a.key) ?? 999) - (modifierOrder.get(b.key) ?? 999) || a.label.localeCompare(b.label));
}

export function modifierText(value: number) {
  return signed(value);
}

export function modifierToneClass(value: number) {
  if (value > 0) return 'text-[var(--teal)]';
  if (value < 0) return 'text-[var(--red)]';
  return 'text-[var(--paper)]';
}

export function isMythrilItem(item: ItemDetailLike) {
  return `${item.material ?? ''} ${item.name}`.toLowerCase().includes('mythril');
}

export function canManuallyEnhance(item: ItemDetailLike) {
  return isMythrilItem(item) && (item.type === 'weapon' || item.type === 'shield' || item.type === 'armor');
}

export function canManuallyEnchant(item: ItemDetailLike) {
  return isMythrilItem(item) && item.type === 'weapon';
}

function normalizedSpellName(value: string) {
  return value.trim().toLowerCase().replace(/[^a-z0-9]+/g, ' ');
}

export function spellForEnchantment(spells: Spell[], enchantment?: string) {
  if (!enchantment?.trim()) return null;
  const wanted = normalizedSpellName(enchantment);
  return spells.find((spell) => normalizedSpellName(spell.name) === wanted || normalizedSpellName(spell.key) === wanted) ?? null;
}

export function itemHasEnhancementVisual(item: Pick<InventoryItem, 'enhancementCount'>) {
  return item.enhancementCount > 0;
}
