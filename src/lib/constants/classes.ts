import { DEFAULT_ATTRIBUTES, type CharacterAttributes, type ClassTemplate } from '@/lib/types';

function stats(values: Partial<CharacterAttributes>): CharacterAttributes {
  return { ...DEFAULT_ATTRIBUTES, ...values };
}

export const CLASS_TEMPLATES: ClassTemplate[] = [
  {
    id: 'class-alchemist',
    key: 'alchemist',
    name: 'Alchemist',
    role: 'Support · Decent sustain',
    armor: 'Light armor',
    identity: "Alchemists are intellegent and resourceful, knowing much of the land, yet always yearn for more knowledge. They are cunning and rumor has it, that an order of alchemists pass secrets of the world around to one another. Perhaps its just fables and overexhaderations, but then again I've never really seen them ever at a brewery.",
    inventorySlots: 16,
    spellSlots: 2,
    baseHp: 110,
    baseMana: 50,
    baseMagicResist: 8,
    attributes: stats({ strength: -1, accuracy: 0, intelligence: 1, vitality: -1, recovery: 1, mana_regen: 0, charisma: 0, wisdom_cunning: 3, perception: 0, alchemy: 5, stealth: 0, agility: 0 }),
    passives: [
      'Once per combat, an Alchemist can use or make a potion or alchemical item without spending their main action or movement',
      'Has unlimited flasks and Arcane Nectar (Base ingredient in potions) as long as they have a house or residence'
    ],
    tokenColor: '#4d8f83'
  },
  {
    id: 'class-apothecary',
    key: 'apothecary',
    name: 'Apothecary',
    role: 'Support · Great sustain',
    armor: 'Medium armor',
    identity: 'Apothecaries are increadibly durible mages, known for their legendary support in combat and on the battlefield. They are extremely formitable as mages, and sometimes, even in the frontline. Many a great apothecary was known for their priceless support in battle. But a few, are some of the most feared names Arda Malanda has heard.',
    inventorySlots: 15,
    spellSlots: 5,
    baseHp: 130,
    baseMana: 90,
    baseMagicResist: 11,
    attributes: stats({ strength: -3, accuracy: -1, intelligence: 0, vitality: 1, recovery: 2, mana_regen: 2, charisma: 0, wisdom_cunning: 2, perception: 0, alchemy: 2, stealth: -2, agility: -1 }),
    passives: ['Can heal an ally for 10 hp in place of a movement'],
    tokenColor: '#5579a8'
  },
  {
    id: 'class-apprentice',
    key: 'apprentice',
    name: 'Apprentice',
    role: 'Hybrid · Decent sustain',
    armor: 'Medium armor',
    identity: 'Apprentices are learners, and are naturally talented mages, but enjoy the freedom of some extra sustainability, as oposed to utility. Their resourcefulness is often a great contrabution to many sucessful expeditions.',
    inventorySlots: 16,
    spellSlots: 5,
    baseHp: 100,
    baseMana: 75,
    baseMagicResist: 8,
    attributes: stats({ strength: 0, accuracy: 0, intelligence: 1, vitality: -1, recovery: 0, mana_regen: 1, charisma: 0, wisdom_cunning: 1, perception: 0, alchemy: 1, stealth: 0, agility: 1 }),
    passives: ['When paired with a mage, has +1 Intelligence. When paired with a knight, has +1 Strength. When paired with a ranger, has +1 Accuracy. These can stack.'],
    tokenColor: '#8a6da1'
  },
  {
    id: 'class-armor-clad',
    key: 'armor-clad',
    name: 'Armor-clad',
    role: 'Defense · Great sustain',
    armor: 'Heavy armor',
    identity: "Armor-clad warriors are amazing front liners. They are incredibly hard to take down and provide an amazing presence on the battlefield. What they lack in quickness, they make up for in annoying defensive utility. They are often seen as scary or mad due to their nature on the battlefield, or at least thats what they say. Hasn't been one in ages.",
    inventorySlots: 10,
    spellSlots: 1,
    baseHp: 165,
    baseMana: 50,
    baseMagicResist: 9,
    attributes: stats({ strength: 2, accuracy: 0, intelligence: -3, vitality: 3, recovery: 0, mana_regen: 0, charisma: -1, wisdom_cunning: -2, perception: -1, alchemy: 1, stealth: -3, agility: -3 }),
    passives: [
      "Has the ability _Distribution_, which will direct 50% of a target's damage to yourself",
      'Does not pay armor labor, only materials. Armor-clad cannot receive extra defensive bonuses from shields'
    ],
    tokenColor: '#9a6e52'
  },
  {
    id: 'class-beastmaster',
    key: 'beastmaster',
    name: 'Beastmaster',
    role: 'Hybrid · Poor sustain',
    armor: 'Light armor',
    identity: 'Beastmasters are incredibly rare, but invaluable as an asset. Many have never been much on the battlefield themselves, but their way with the animals and beasts of the land is marvelling. They say a couple hundred years ago, an elvish beastmaster once tamed a dragon, and one must wonder if it was the childs story we all were told, or if there is even a smidgent of truth hidden within.',
    inventorySlots: 20,
    spellSlots: 1,
    baseHp: 90,
    baseMana: 50,
    baseMagicResist: 8,
    attributes: stats({ strength: -3, accuracy: 1, intelligence: 0, vitality: 0, recovery: 1, mana_regen: 0, charisma: 3, wisdom_cunning: 2, perception: 2, alchemy: 0, stealth: 0, agility: 1 }),
    passives: [
      'Has the Spell "Tame" (doesn\'t take a spell slot), which allows for a tame roll, which is a d6 plus charisma plus buffs vs the animal\'s wild score. If the resulting number is positive, the animal/beast is tamed, but health isn\'t restored. If the resulting number is zero, heads on a coin flip tames. Tame can only be attempted on creatures below 50% health. Creatures below 10% health yield a +3 bonus to a tame roll. Any below 5% yields a +5 to a tame roll.',
      'All Attacks from a Beast master will only ever bring an animal or beast to 1hp, never killing it',
      'Will always crit against animals and beasts',
      'Can bring 20 wild score worth of beasts per mission. Each beast operates independently of the beastmaster with its own initiative and turns.'
    ],
    tokenColor: '#77875a'
  },
  {
    id: 'class-blacksmith',
    key: 'blacksmith',
    name: 'Blacksmith',
    role: 'Support · Decent sustain',
    armor: 'Medium armor',
    identity: 'Blacksmiths are highly valued assets in the realm, in all kindoms. Their utility and knack for anything with their hands is to be much admired. There are many kinds of blacksmiths, but the great runesmith Argon "The Hammer" Tyborgarian has been showing the realm just how versitile runes and magic can be in tools and armor, forming a new study within the craft as we speak.',
    inventorySlots: 18,
    spellSlots: 3,
    baseHp: 125,
    baseMana: 50,
    baseMagicResist: 8,
    attributes: stats({ strength: 2, accuracy: 0, intelligence: 0, vitality: 1, recovery: 0, mana_regen: 0, charisma: 2, wisdom_cunning: 1, perception: 0, alchemy: 1, stealth: -1, agility: -1 }),
    passives: [
      "Doesn't need to pay for smithing labor, only materials",
      'Has the ability to create weapons away from a forge with a properly made fire',
      'Once per combat, enhance a melee weapon of choice with +1 strength. Ends after combat/scene'
    ],
    tokenColor: '#b28b45'
  },
  {
    id: 'class-knight',
    key: 'knight',
    name: 'Knight',
    role: 'Attack · Decent sustain',
    armor: 'Medium armor',
    identity: 'Knights are talented swords men and combat experts, and pair well with horses. Well liked knights have been known to have been shown favor even when purchacing one and have a larger political sway. They are your classic all around attack type with a nice amount of sustainability.',
    inventorySlots: 14,
    spellSlots: 2,
    baseHp: 125,
    baseMana: 25,
    baseMagicResist: 8,
    attributes: stats({ strength: 1, accuracy: 1, intelligence: -1, vitality: 1, recovery: 0, mana_regen: -2, charisma: 2, wisdom_cunning: 1, perception: 0, alchemy: -1, stealth: 0, agility: 0 }),
    passives: [
      '+1 Strength while on a Horse.',
      'Every hit received, roll for a parry, 18-20 will grant a 100% reduction of damage. 15-17 will grant a 50% (rounding up) reduction',
      'Rally the troops: Once per combat, choose a target for the entire party to all attack at once; as long as this attack hits, all others will as well.'
    ],
    tokenColor: '#a05e5a'
  },
  {
    id: 'class-mage',
    key: 'mage',
    name: 'Mage',
    role: 'Attack · Poor sustain',
    armor: 'Light armor',
    identity: 'Mages are the hot shots of Calostrynn, their pride and joy. They pack a punch, much like the rangers, but what the rangers have in range and recon, the mages more than make up for in versitility. With enough knowledge, there is nearly a spell for almost all occasions.',
    inventorySlots: 10,
    spellSlots: 10,
    baseHp: 70,
    baseMana: 100,
    baseMagicResist: 10,
    attributes: stats({ strength: -3, accuracy: 0, intelligence: 3, vitality: -3, recovery: 0, mana_regen: 1, charisma: 1, wisdom_cunning: 2, perception: 0, alchemy: 0, stealth: 0, agility: 0 }),
    passives: ['Regain 10 Mana for every enemy killed with a spell'],
    tokenColor: '#567a7f'
  },
  {
    id: 'class-mendrunner',
    key: 'mendrunner',
    name: 'Mendrunner',
    role: 'Hybrid · Poor sustain',
    armor: 'Medium armor',
    identity: 'Mendrunners are a unique lot. They specialize in botany and natural remedies, resenting magic and its simple life style. They are increadibly nimble and many have once been or sometimes become rogues. Little is known about them though due to their lack of number.',
    inventorySlots: 20,
    spellSlots: 0,
    baseHp: 85,
    baseMana: 0,
    baseMagicResist: 7,
    attributes: stats({ strength: -1, accuracy: 1, intelligence: -5, vitality: 0, recovery: 3, mana_regen: 0, charisma: -3, wisdom_cunning: 3, perception: 3, alchemy: 4, stealth: 1, agility: 3 }),
    passives: [
      'Heal an ally for 2d6 + Recovery + Alchemy and remove a debuff or negative effect. Cooldown of 1 turn.',
      'Is immune to poison and Illness'
    ],
    tokenColor: '#6b8f68'
  },
  {
    id: 'class-ranger',
    key: 'ranger',
    name: 'Ranger',
    role: 'Attack · Poor sustain',
    armor: 'Light armor',
    identity: 'Ranged class is known for being a backline attack type. They can pack a punch and provide great support form range, and can even act as very nice recon, but are very vulnerable alone in most situations. A master archer especially has been the sole reason for many concussions to wars, a much under appreciated craft, given their grand role in previous wars.',
    inventorySlots: 15,
    spellSlots: 1,
    baseHp: 90,
    baseMana: 50,
    baseMagicResist: 10,
    attributes: stats({ strength: -2, accuracy: 2, intelligence: 1, vitality: -2, recovery: 0, mana_regen: 0, charisma: 0, wisdom_cunning: 2, perception: 2, alchemy: 0, stealth: 1, agility: 1 }),
    passives: [
      'Can tame birds',
      '3 times per combat, shoot 3 arrows in one draw. Must roll for accuracy for each arrow.',
      'Allowed to buy and craft element or effect-tipped arrows'
    ],
    tokenColor: '#7c8a49'
  },
  {
    id: 'class-rogue',
    key: 'rogue',
    name: 'Rogue',
    role: 'Attack · Poor sustain',
    armor: 'Light armor',
    identity: 'Rogues are shifty and cunning. They might not be stong in groups but are amazing duelests and specialize in catching enemies off guard. Their reputation preceeds them, and not always in the best of ways, but they are always more than nice outside and within the castle walls.',
    inventorySlots: 16,
    spellSlots: 3,
    baseHp: 90,
    baseMana: 50,
    baseMagicResist: 7,
    attributes: stats({ strength: -1, accuracy: 0, intelligence: 0, vitality: -1, recovery: 0, mana_regen: 0, charisma: -3, wisdom_cunning: 3, perception: 3, alchemy: 1, stealth: 3, agility: 2 }),
    passives: [
      'Has the ability *Backstab* which when attacking from behind, from stealth, or against a pinned or otherwise defenseless enemy, Rogue deals double damage.',
      'May use Agility instead of Strength for any attack that procs *Backstab*'
    ],
    tokenColor: '#6b617e'
  },
  {
    id: 'class-sage',
    key: 'sage',
    name: 'Sage',
    role: 'Support · Poor sustain',
    armor: 'Medium armor',
    identity: 'Sages are loved and appreciated by all. In a world of war and selfish interest, they walk a path of selflessness, aiding others in their prosperity and support on the battlefield. Those who have mastered their craft are known to have boundless mana and spell casting.',
    inventorySlots: 12,
    spellSlots: 5,
    baseHp: 70,
    baseMana: 100,
    baseMagicResist: 12,
    attributes: stats({ strength: -2, accuracy: -2, intelligence: -5, vitality: -2, recovery: 3, mana_regen: 2, charisma: 2, wisdom_cunning: 4, perception: 0, alchemy: 0, stealth: 0, agility: 2 }),
    passives: [
      'Healing and enhancement spells use _Recovery_ instead of Intelligence when using magic rolls',
      'Heals also heal an additional ally for half (rounding up) of the heals amount. Can be used on the same target'
    ],
    tokenColor: '#7581a0'
  },
  {
    id: 'class-muscle',
    key: 'the-muscle',
    name: 'The Muscle',
    role: 'Defense · Great sustain',
    armor: 'Medium armor',
    identity: 'The Muscle is notorious for their large frame and small brains. They specialize on sustain and being...well, the muscle of a group. When paired with a sage or apothecary, these hulkish freaks of nature are unstoppable.',
    inventorySlots: 10,
    spellSlots: 1,
    baseHp: 150,
    baseMana: 40,
    baseMagicResist: 7,
    attributes: stats({ strength: 3, accuracy: -2, intelligence: -3, vitality: 1, recovery: 2, mana_regen: 0, charisma: -2, wisdom_cunning: -3, perception: -1, alchemy: -2, stealth: -2, agility: -2 }),
    passives: ['When The Muscle kills an enemy, gain 1 d6 for ensuing damage rolls. Resets after each combat/scene ends. Max of 5 d6'],
    tokenColor: '#9f6540'
  },
  {
    id: 'class-talismanist',
    key: 'talismanist',
    name: 'Talismanist',
    role: 'Attack · Decent sustain',
    armor: 'Medium armor',
    identity: 'Talismanists are experts at using weapons and armor forced with runes, and almost exclusively use weapons that hold spells or magical properties within them. This new class of warriors only recently came about, given the studies and smithsmanship from Argon "The Hammer" Tyborgarian.',
    inventorySlots: 10,
    spellSlots: 0,
    baseHp: 125,
    baseMana: 100,
    baseMagicResist: 10,
    attributes: stats({ strength: 1, accuracy: 1, intelligence: 1, vitality: 1, recovery: 0, mana_regen: 0, charisma: 0, wisdom_cunning: 1, perception: 0, alchemy: -1, stealth: -2, agility: 0 }),
    passives: [
      'Inherits 3 random low-level runes.',
      'Requires only 3 runes to force spells into weapons as opposed to 5, with each rune beyond that increasing the chance of a stronger spell.',
      'Each spell-infused weapon on hand can cast its spell twice per combat'
    ],
    tokenColor: '#926d9f'
  },
  {
    id: 'class-warden',
    key: 'warden',
    name: 'Warden',
    role: 'Hybrid · Decent sustain',
    armor: 'Medium armor',
    identity: 'Wardens are your classic Jack-of-all trades mast of none. They bring great all around helpfulness and can be plug and play in most settings. Wardens are known for their survival skills and cunning, but are shunned for a lack of a profitable or secure occupation.',
    inventorySlots: 20,
    spellSlots: 3,
    baseHp: 110,
    baseMana: 75,
    baseMagicResist: 9,
    attributes: stats({ strength: 0, accuracy: 0, intelligence: 0, vitality: 0, recovery: 0, mana_regen: 0, charisma: -2, wisdom_cunning: 3, perception: 2, alchemy: 1, stealth: 0, agility: 0 }),
    passives: [
      'Once per combat or exploration scene, Warden may reroll a failed Perception, Alchemy, Survival, or Utility check.',
      'Gains a +2 modifier of choice in a single category where the party has no bonuses'
    ],
    tokenColor: '#79895f'
  }
];

export const DEFAULT_CLASS_TEMPLATE = CLASS_TEMPLATES[0];
