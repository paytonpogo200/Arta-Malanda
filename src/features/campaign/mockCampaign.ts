import { CLASS_TEMPLATES } from '@/lib/constants/classes';
import { createId } from '@/lib/utils/ids';
import type { CampaignState, Character, ClassTemplate, InventoryItem } from '@/lib/types';

export const MOCK_OWNER_ID = 'profile-player';
export const MOCK_DM_ID = 'profile-dm';

export function characterFromClass(template: ClassTemplate, name: string, ownerUserId = MOCK_OWNER_ID): Character {
  return {
    id: createId('char'),
    name: name.trim() || `New ${template.name}`,
    kind: 'player',
    ownerUserId,
    classKey: template.key,
    className: template.name,
    level: 1,
    maxHp: template.baseHp,
    currentHp: template.baseHp,
    maxMana: template.baseMana,
    currentMana: template.baseMana,
    inventorySlots: template.inventorySlots,
    spellSlots: template.spellSlots,
    attributes: template.attributes,
    classPassives: template.passives,
    personalPassives: '',
    tokenColor: template.tokenColor,
    locationName: 'Calostrynn'
  };
}

function item(partial: Omit<InventoryItem, 'id'>): InventoryItem {
  return { id: createId('item'), ...partial };
}

const alchemist = characterFromClass(CLASS_TEMPLATES[0], 'Veyra Glassroot');
const knight = characterFromClass(CLASS_TEMPLATES.find((entry) => entry.key === 'knight')!, 'Sir Caldus');
const mage = characterFromClass(CLASS_TEMPLATES.find((entry) => entry.key === 'mage')!, 'Irin Vale');

export const initialCampaignState: CampaignState = {
  profile: {
    id: MOCK_DM_ID,
    displayName: 'Dungeon Master',
    role: 'dm'
  },
  classes: CLASS_TEMPLATES,
  characters: [alchemist, knight, mage],
  items: [
    item({
      characterId: alchemist.id,
      parentItemId: null,
      name: 'Glass Flask',
      type: 'misc',
      rarity: 'Common',
      quantity: 4,
      slotIndex: 0,
      loadoutSlot: null,
      isStorage: false,
      storageCapacity: 0,
      modifiers: {}
    }),
    item({
      characterId: alchemist.id,
      parentItemId: null,
      name: 'Minor Healing Potion',
      type: 'potion',
      rarity: 'Uncommon',
      quantity: 2,
      slotIndex: 1,
      loadoutSlot: null,
      isStorage: false,
      storageCapacity: 0,
      modifiers: {}
    }),
    item({
      characterId: knight.id,
      parentItemId: null,
      name: 'Calostrynn Longsword',
      type: 'weapon',
      rarity: 'Rare',
      quantity: 1,
      slotIndex: 0,
      loadoutSlot: 'weapon',
      isStorage: false,
      storageCapacity: 0,
      modifiers: { strength: 1 },
      spellImbue: 'Glimmering Edge'
    }),
    item({
      characterId: knight.id,
      parentItemId: null,
      name: 'Traveler Shield',
      type: 'shield',
      rarity: 'Common',
      quantity: 1,
      slotIndex: 1,
      loadoutSlot: 'shield',
      isStorage: false,
      storageCapacity: 0,
      modifiers: { vitality: 1 }
    }),
    item({
      characterId: mage.id,
      parentItemId: null,
      name: 'Bag of Holding',
      type: 'storage',
      rarity: 'Mythical',
      quantity: 1,
      slotIndex: 0,
      loadoutSlot: null,
      isStorage: true,
      storageCapacity: 999,
      modifiers: {}
    })
  ],
  battle: null,
  combatants: []
};
