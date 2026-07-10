import type { ItemRarity } from '@/lib/types';

export function rarityClass(rarity?: ItemRarity | string) {
  return `rarity-card rarity-${String(rarity || 'Common').toLowerCase()}`;
}

export const rarityOptions: ItemRarity[] = ['Common', 'Uncommon', 'Rare', 'Epic', 'Legendary', 'Mythical'];
