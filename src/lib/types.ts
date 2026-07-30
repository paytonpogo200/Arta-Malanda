export type UserRole = 'player' | 'dm';
export type CharacterKind = 'player' | 'enemy' | 'npc' | 'tamed_beast';
export type BattleStatus = 'active' | 'ended';
export type ItemRarity = 'Common' | 'Uncommon' | 'Rare' | 'Epic' | 'Legendary' | 'Mythical';
export type ItemType =
  | 'weapon'
  | 'armor'
  | 'shield'
  | 'pet'
  | 'accessory'
  | 'storage'
  | 'material'
  | 'catalyst'
  | 'rune'
  | 'ore'
  | 'potion'
  | 'food'
  | 'plant'
  | 'fabric'
  | 'tool'
  | 'quest'
  | 'currency'
  | 'misc';

export const ATTRIBUTE_KEYS = [
  'strength',
  'accuracy',
  'intelligence',
  'vitality',
  'recovery',
  'mana_regen',
  'charisma',
  'wisdom_cunning',
  'perception',
  'alchemy',
  'stealth',
  'agility'
] as const;

export type AttributeKey = (typeof ATTRIBUTE_KEYS)[number];
export type CharacterAttributes = Record<AttributeKey, number>;

export const DEFAULT_ATTRIBUTES: CharacterAttributes = {
  strength: 0,
  accuracy: 0,
  intelligence: 0,
  vitality: 0,
  recovery: 0,
  mana_regen: 0,
  charisma: 0,
  wisdom_cunning: 0,
  perception: 0,
  alchemy: 0,
  stealth: 0,
  agility: 0
};

export const ATTRIBUTE_LABELS: Record<AttributeKey, string> = {
  strength: 'Strength',
  accuracy: 'Accuracy',
  intelligence: 'Intelligence',
  vitality: 'Vitality',
  recovery: 'Recovery',
  mana_regen: 'Mana Regen',
  charisma: 'Charisma',
  wisdom_cunning: 'Wisdom/Cunning',
  perception: 'Perception',
  alchemy: 'Alchemy',
  stealth: 'Stealth',
  agility: 'Agility'
};

export type LoadoutModifierKey =
  | AttributeKey
  | 'armor'
  | 'shield'
  | 'defense'
  | 'defence'
  | 'magic_resist'
  | 'magicResist'
  | 'magicResistance'
  | 'health'
  | 'hp'
  | 'maxHp'
  | 'max_hp'
  | 'mana'
  | 'maxMana'
  | 'max_mana';
export type LoadoutModifiers = Partial<Record<LoadoutModifierKey, number>>;

export type ItemCatalogEntry = {
  id: string;
  key: string;
  name: string;
  type: ItemType;
  rarity: ItemRarity;
  category: string;
  properties: string[];
  quantityStep: number;
  stackable: boolean;
  defaultModifiers: LoadoutModifiers;
  material: string;
  isTwoHanded: boolean;
  storageCapacity: number;
  notes: string;
  active: boolean;
  order: number;
};

export type Profile = {
  id: string;
  displayName: string;
  role: UserRole;
};

export type ClassTemplate = {
  id: string;
  key: string;
  name: string;
  role: string;
  armor: string;
  identity: string;
  inventorySlots: number;
  spellSlots: number;
  baseHp: number;
  baseMana: number;
  baseMagicResist: number;
  attributes: CharacterAttributes;
  passives: string[];
  tokenColor: string;
};

export type Character = {
  id: string;
  name: string;
  kind: CharacterKind;
  ownerUserId: string | null;
  classKey: string;
  className: string;
  level: number;
  maxHp: number;
  currentHp: number;
  maxMana: number;
  currentMana: number;
  magicResist: number;
  inventorySlots: number;
  inventoryOpenSlots?: number;
  spellSlots: number;
  attributes: CharacterAttributes;
  classPassives: string[];
  personalPassives: string;
  tokenColor: string;
  locationName: string;
  previousOwnerName?: string;
};

export type LoadoutSlot =
  | 'weapon'
  | 'armor'
  | 'shield'
  | 'active-pet'
  | 'accessory-1'
  | 'accessory-2'
  | 'accessory-3'
  | 'accessory-4';

export type InventoryItem = {
  id: string;
  characterId: string;
  parentItemId: string | null;
  name: string;
  displayName?: string;
  itemDescription?: string;
  type: ItemType;
  rarity: ItemRarity;
  quantity: number;
  slotIndex: number;
  loadoutSlot: LoadoutSlot | null;
  isStorage: boolean;
  storageCapacity: number;
  modifiers: LoadoutModifiers;
  enchantment?: string;
  runeName?: string;
  material?: string;
  enhancementCount: number;
  isTwoHanded: boolean;
  potionStrength?: string;
  potionProperty?: string;
  potionQuality?: string;
};

export type CurrencyUnit = {
  id: string;
  key: string;
  name: string;
  symbol: string;
  order: number;
};

export type WalletBalance = {
  unit: CurrencyUnit;
  amount: number;
};

export type PropertyType = 'animal' | 'wagon' | 'pet' | 'mount' | 'other';
export type PropertyLocation = 'with_character' | 'at_house';

export type House = {
  id: string;
  ownerUserId: string;
  cityName: string;
  inventorySlots: number;
  propertySlots: number;
  locked: boolean;
};

export type CampaignProperty = {
  id: string;
  ownerUserId: string;
  caretakerCharacterId: string | null;
  name: string;
  type: PropertyType;
  location: PropertyLocation;
  isPet: boolean;
  slotIndex: number;
  storageCapacity: number;
};

export type BattleTerrain = {
  id: string;
  battleId: string;
  x: number;
  y: number;
  type: 'blocked';
};

export type City = {
  id: string;
  key: string;
  name: string;
  locked: boolean;
  order: number;
};

export type MarketProduct = {
  id: string;
  vendorId: string;
  key: string;
  name: string;
  description: string;
  type: ItemType;
  rarity: ItemRarity;
  priceCoin: number;
  stockQuantity: number | null;
  available: boolean;
  catalogItemKey: string;
  section: string;
  quantityStep: number;
};

export type ShopVendor = {
  id: string;
  cityKey: string;
  key: string;
  name: string;
  npcName: string;
  facility: string;
  category: string;
  hidden: boolean;
  order: number;
  products: MarketProduct[];
};

export type SpellSchool = 'arcane' | 'restoration' | 'nature' | 'alchemy' | 'rune' | 'shadow' | 'martial';
export type SpellType = 'Ember' | 'Frost' | 'Lightning' | 'Earth' | 'Wind' | 'Energy' | 'Defensive Support' | 'Offensive Support' | 'Enhancement' | 'Utility';

export type Spell = {
  id: string;
  key: string;
  name: string;
  school: SpellSchool;
  type: SpellType;
  manaCost: number;
  manaLabel: string;
  summary: string;
  details: string;
  rarity: ItemRarity;
};

export type CharacterSpell = {
  id: string;
  characterId: string;
  spellId: string;
  active: boolean;
  slotIndex: number | null;
  spell: Spell;
};

export type LootPool = {
  id: string;
  key: string;
  name: string;
  description: string;
  order: number;
};

export type LootItem = {
  id: string;
  poolId: string;
  name: string;
  category: string;
  biomes: string[];
  minDifficulty: number;
  maxDifficulty: number;
  type: ItemType;
  rarity: ItemRarity;
  minQuantity: number;
  maxQuantity: number;
  weight: number;
  towerBaseOnly: boolean;
  notes: string;
};

export type LootGeneratorSettings = {
  biomes: string[];
  difficulties: number[];
  poolSizes: string[];
  roomTypes: string[];
  luckPotionOptions: string[];
  baseRollsByPoolSize: Record<string, number>;
  poolMultipliers: Record<string, number>;
  roomMultipliers: Record<string, number>;
  luckPotionMultipliers: Record<string, { legendary: number; mythical: number }>;
  rareBoostRarities: ItemRarity[];
  sourceFormulas: Record<string, string>;
};

export type LootDrop = {
  id: string;
  rollNumber: number;
  itemId: string;
  name: string;
  type: ItemType;
  rarity: ItemRarity;
  quantity: number;
  remaining: number;
};

export type BestiaryCategory = string;

export type BestiaryCategoryRecord = {
  key: string;
  name: string;
  hidden: boolean;
  order: number;
};

export type BestiaryEntity = {
  id: string;
  key: string;
  name: string;
  category: BestiaryCategory;
  habitat: string;
  temperament: string;
  wildScore: number;
  hp: number;
  mana: number;
  summary: string;
  details: string;
  stats: Record<string, string>;
  unlocked: boolean;
  order: number;
};

export type PersonalScroll = {
  profileId: string;
  contentHtml: string;
  drawingDataUrl: string;
  updatedAt: string | null;
};

export type TradeStatus = 'pending' | 'accepted' | 'declined' | 'cancelled';

export type TradeOffer = {
  id: string;
  senderUserId: string;
  recipientUserId: string;
  senderCharacterId: string;
  targetCharacterId: string;
  senderCharacterName: string;
  targetCharacterName: string;
  status: TradeStatus;
  offerNote: string;
  requestNote: string;
  message: string;
  createdAt: string | null;
  updatedAt: string | null;
};

export type Battle = {
  id: string;
  status: BattleStatus;
  gridWidth: number;
  gridHeight: number;
};

export type Combatant = {
  id: string;
  battleId: string;
  characterId: string;
  x: number;
  y: number;
  currentHp: number;
  currentMana: number;
  initiative: number | null;
};

export type CampaignState = {
  profile: Profile;
  classes: ClassTemplate[];
  characters: Character[];
  items: InventoryItem[];
  battle: Battle | null;
  combatants: Combatant[];
};
