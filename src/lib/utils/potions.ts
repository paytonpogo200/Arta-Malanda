import type { InventoryItem, MarketProduct } from '@/lib/types';

type PotionLike = Pick<InventoryItem, 'name' | 'type' | 'potionStrength' | 'potionProperty' | 'potionQuality'> | Pick<MarketProduct, 'name' | 'type'>;

const PROPERTY_ALIASES: Record<string, string> = {
  swiftness: 'Speed',
  speed: 'Speed',
  agility: 'Agility',
  strength: 'Strength',
  sorcery: 'Sorcery',
  mana: 'Mana Regen',
  'mana regen': 'Mana Regen',
  luck: 'Luck',
  antidote: 'Antidote',
  warming: 'Warming',
  cooling: 'Cooling',
  'night-eye': 'Night-Eye',
  'night eye': 'Night-Eye',
  thickskin: 'Thickskin',
  'clear-mind': 'Clear-Mind',
  'clear mind': 'Clear-Mind',
  'wake-up': 'Wake-Up',
  'wake up': 'Wake-Up',
  clotting: 'Clotting',
  healing: 'Healing'
};

function normalizedName(name: string) {
  return name.trim().toLowerCase().replace(/\s+/g, ' ');
}

export function potionStrengthFromName(name: string) {
  const clean = normalizedName(name);
  if (clean.startsWith('lesser ')) return 'Lesser';
  if (clean.startsWith('greater ')) return 'Greater';
  if (clean.startsWith('greatest ')) return 'Greatest';
  return '';
}

export function potionPropertyFromName(name: string) {
  const clean = normalizedName(name)
    .replace(/\s+\([^)]*\)\s*$/, '')
    .replace(/^(lesser|greater|greatest)\s+/, '')
    .replace(/\s+potion$/, '');
  return PROPERTY_ALIASES[clean] ?? '';
}

export function potionQualityFromName(name: string) {
  const match = name.match(/\(([^)]*)\)\s*$/);
  return match?.[1]?.trim() ?? '';
}

export function potionEffectText(item: PotionLike) {
  if (item.type !== 'potion') return '';
  const strength = 'potionStrength' in item ? item.potionStrength || potionStrengthFromName(item.name) : potionStrengthFromName(item.name);
  const property = 'potionProperty' in item ? item.potionProperty || potionPropertyFromName(item.name) : potionPropertyFromName(item.name);
  const quality = 'potionQuality' in item ? item.potionQuality || potionQualityFromName(item.name) : potionQualityFromName(item.name);
  if (!strength || !property) return '';

  const ranked: Record<string, Record<string, string>> = {
    Healing: {
      Lesser: '+20 Health',
      Greater: '+50 Health',
      Greatest: 'Full Health Recovery'
    },
    Speed: {
      Lesser: '+1 Speed',
      Greater: '+2 Speed',
      Greatest: '+5 Speed'
    },
    Agility: {
      Lesser: '+1 Agility',
      Greater: '+2 Agility',
      Greatest: '+5 Agility'
    },
    Strength: {
      Lesser: '+1 Strength',
      Greater: '+2 Strength',
      Greatest: '+5 Strength'
    },
    Sorcery: {
      Lesser: '+1 Intelligence',
      Greater: '+2 Intelligence',
      Greatest: '+5 Intelligence'
    },
    'Mana Regen': {
      Lesser: '+15 Mana',
      Greater: '+40 Mana',
      Greatest: 'Full Mana Recovery'
    },
    Luck: {
      Lesser: '+1 Rolls',
      Greater: '+3 Rolls',
      Greatest: '+5 Rolls'
    },
    Antidote: {
      Lesser: 'Removes poison',
      Greater: 'Removes poison and grants poison resistance for 3 turns',
      Greatest: 'Removes poison and grants poison immunity for 1 scene'
    },
    Warming: {
      Lesser: 'Protects from cold for 1 scene or travel stretch',
      Greater: 'Protects from extreme cold for 1 scene or travel stretch',
      Greatest: 'Protects from cold, frost damage, and frost-based slowing for 1 scene'
    },
    Cooling: {
      Lesser: 'Protects from heat for 1 scene or travel stretch',
      Greater: 'Protects from extreme heat for 1 scene or travel stretch',
      Greatest: 'Protects from heat, fire damage, and burning for 1 scene'
    },
    'Night-Eye': {
      Lesser: 'Allows better sight in darkness for 1 scene',
      Greater: 'Allows clear sight in darkness for 1 scene',
      Greatest: 'Allows clear sight in magical or unnatural darkness for 1 scene'
    },
    Thickskin: {
      Lesser: '+1 Armor for 3 turns',
      Greater: '+2 Armor for 3 turns',
      Greatest: '+4 Armor for 3 turns'
    },
    'Clear-Mind': {
      Lesser: '+1 Magic Res for 3 turns',
      Greater: '+2 Magic Res for 3 turns',
      Greatest: '+4 Magic Res for 3 turns'
    },
    'Wake-Up': {
      Lesser: 'Wakes an unconscious or magically sleeping target. If unconscious from damage, they wake at 1 HP',
      Greater: 'Wakes an unconscious or magically sleeping target at 10 HP',
      Greatest: 'Wakes an unconscious or magically sleeping target at 25 HP'
    },
    Clotting: {
      Lesser: 'Stops bleeding effects',
      Greater: 'Stops bleeding effects and restores 10 Health',
      Greatest: 'Stops bleeding effects, restores 25 Health, and prevents bleeding for 1 scene'
    }
  };

  const effect = ranked[property]?.[strength] ?? '';
  if (!effect) return '';
  return quality ? `${effect}. Quality: ${quality}.` : effect;
}
