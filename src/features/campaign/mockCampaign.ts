import { CLASS_TEMPLATES } from '@/lib/constants/classes';
import { createId } from '@/lib/utils/ids';
import type { CampaignState, Character, ClassTemplate } from '@/lib/types';

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
    magicResist: template.baseMagicResist,
    inventorySlots: template.inventorySlots,
    spellSlots: template.spellSlots,
    attributes: template.attributes,
    classPassives: template.passives,
    personalPassives: '',
    tokenColor: template.tokenColor,
    locationName: 'Calostrynn'
  };
}

export const initialCampaignState: CampaignState = {
  profile: {
    id: MOCK_DM_ID,
    displayName: 'Dungeon Master',
    role: 'dm'
  },
  classes: CLASS_TEMPLATES,
  characters: [],
  items: [],
  battle: null,
  combatants: []
};
