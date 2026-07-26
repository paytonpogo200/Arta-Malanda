import type { Character, ClassTemplate, InventoryItem, LoadoutModifiers, AttributeKey } from '@/lib/types';

export function armorDefenseBase(armor?: string) {
  const normalized = (armor ?? '').toLowerCase();
  if (normalized.includes('heavy')) return 13;
  if (normalized.includes('medium')) return 10;
  if (normalized.includes('light')) return 7;
  return 0;
}

function modifierNumber(modifiers: LoadoutModifiers, key: keyof LoadoutModifiers) {
  const value = Number(modifiers[key] ?? 0);
  return Number.isFinite(value) ? value : 0;
}

export function loadoutModifierTotal(items: InventoryItem[], keys: Array<keyof LoadoutModifiers>) {
  return items
    .filter((item) => item.loadoutSlot)
    .reduce((total, item) => total + keys.reduce((sum, key) => sum + modifierNumber(item.modifiers, key), 0), 0);
}

export function activeAttributeValue(character: Character, items: InventoryItem[], key: AttributeKey) {
  return (character.attributes[key] ?? 0) + loadoutModifierTotal(items, [key]);
}

export function calculateCharacterSheetStats(character: Character, items: InventoryItem[], classTemplate?: ClassTemplate) {
  const vitality = activeAttributeValue(character, items, 'vitality');
  const hasActiveArmor = items.some((item) => item.loadoutSlot === 'armor' && item.type === 'armor');
  const defense = (hasActiveArmor ? armorDefenseBase(classTemplate?.armor) : 0) + vitality + loadoutModifierTotal(items, ['armor', 'shield', 'defense', 'defence']);
  const magicResist = character.magicResist + loadoutModifierTotal(items, ['magic_resist', 'magicResist', 'magicResistance']);
  const maxHp = Math.max(0, character.maxHp + loadoutModifierTotal(items, ['health', 'hp', 'maxHp', 'max_hp']));
  const maxMana = Math.max(0, character.maxMana + loadoutModifierTotal(items, ['mana', 'maxMana', 'max_mana']));
  return { defense, magicResist, maxHp, maxMana };
}
