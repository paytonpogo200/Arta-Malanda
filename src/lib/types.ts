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
  | 'ore'
  | 'potion'
  | 'food'
  | 'plant'
  | 'fabric'
  | 'tool'
  | 'quest'
  | 'misc';

export const ATTRIBUTE_KEYS = [
  'strength',
  'agility',
  'vitality',
  'intelligence',
  'recovery',
  'charisma',
  'accuracy',
  'range',
  'mana_regen',
  'perception',
  'alchemy',
  'stealth'
] as const;

export type AttributeKey = (typeof ATTRIBUTE_KEYS)[number];
export type CharacterAttributes = Record<AttributeKey, number>;

export const DEFAULT_ATTRIBUTES: CharacterAttributes = {
  strength: 0,
  agility: 0,
  vitality: 0,
  intelligence: 0,
  recovery: 0,
  charisma: 0,
  accuracy: 0,
  range: 0,
  mana_regen: 0,
  perception: 0,
  alchemy: 0,
  stealth: 0
};

export const ATTRIBUTE_LABELS: Record<AttributeKey, string> = {
  strength: 'Strength',
  agility: 'Agility',
  vitality: 'Vitality',
  intelligence: 'Intelligence',
  recovery: 'Recovery',
  charisma: 'Charisma',
  accuracy: 'Accuracy',
  range: 'Range',
  mana_regen: 'Mana Regen',
  perception: 'Perception',
  alchemy: 'Alchemy',
  stealth: 'Stealth'
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
  inventorySlots: number;
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
  type: ItemType;
  rarity: ItemRarity;
  quantity: number;
  slotIndex: number;
  loadoutSlot: LoadoutSlot | null;
  isStorage: boolean;
  storageCapacity: number;
  modifiers: Partial<CharacterAttributes>;
  spellImbue?: string;
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

export type Spell = {
  id: string;
  key: string;
  name: string;
  school: SpellSchool;
  manaCost: number;
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
  type: ItemType;
  rarity: ItemRarity;
  minQuantity: number;
  maxQuantity: number;
  notes: string;
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
