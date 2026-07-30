import { ATTRIBUTE_KEYS, DEFAULT_ATTRIBUTES, type Character, type CharacterAttributes, type ClassTemplate, type Profile } from '@/lib/types';

export type CampaignProfile = Profile & {
  username?: string;
};

export type CharacterLedgerPayload = {
  profile: CampaignProfile;
  profiles: CampaignProfile[];
  classes: ClassTemplate[];
  characters: Character[];
};

const TEXT_LIST_FALLBACK: string[] = [];

function numberFrom(value: unknown, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function normalizeAttributes(value: unknown): CharacterAttributes {
  const source = value && typeof value === 'object' && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};

  return ATTRIBUTE_KEYS.reduce<CharacterAttributes>((attributes, key) => {
    attributes[key] = numberFrom(source[key], DEFAULT_ATTRIBUTES[key]);
    return attributes;
  }, { ...DEFAULT_ATTRIBUTES });
}

function normalizeTextList(value: unknown) {
  if (!Array.isArray(value)) return TEXT_LIST_FALLBACK;
  return value.filter((entry): entry is string => typeof entry === 'string' && entry.trim().length > 0);
}

export function normalizeClassTemplate(value: unknown): ClassTemplate {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};

  return {
    id: String(source.id ?? source.key ?? ''),
    key: String(source.key ?? ''),
    name: String(source.name ?? 'Adventurer'),
    role: String(source.role ?? ''),
    armor: String(source.armor ?? ''),
    identity: String(source.identity ?? ''),
    inventorySlots: numberFrom(source.inventorySlots, 12),
    spellSlots: numberFrom(source.spellSlots, 0),
    baseHp: numberFrom(source.baseHp, 100),
    baseMana: numberFrom(source.baseMana, 0),
    baseMagicResist: numberFrom(source.baseMagicResist, 0),
    attributes: normalizeAttributes(source.attributes),
    passives: normalizeTextList(source.passives),
    tokenColor: String(source.tokenColor ?? '#9caf79')
  };
}

export function normalizeCharacter(value: unknown): Character {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};

  return {
    id: String(source.id ?? ''),
    name: String(source.name ?? 'Unnamed Character'),
    kind: (source.kind === 'enemy' || source.kind === 'npc' || source.kind === 'tamed_beast') ? source.kind : 'player',
    ownerUserId: source.ownerUserId ? String(source.ownerUserId) : null,
    classKey: String(source.classKey ?? 'adventurer'),
    className: String(source.className ?? 'Adventurer'),
    level: numberFrom(source.level, 1),
    maxHp: numberFrom(source.maxHp, 100),
    currentHp: numberFrom(source.currentHp, 100),
    maxMana: numberFrom(source.maxMana, 0),
    currentMana: numberFrom(source.currentMana, 0),
    magicResist: numberFrom(source.magicResist, 0),
    inventorySlots: numberFrom(source.inventorySlots, 12),
    inventoryOpenSlots: source.inventoryOpenSlots === undefined ? undefined : Math.max(0, numberFrom(source.inventoryOpenSlots, 0)),
    spellSlots: numberFrom(source.spellSlots, 0),
    attributes: normalizeAttributes(source.attributes),
    classPassives: normalizeTextList(source.classPassives),
    personalPassives: String(source.personalPassives ?? ''),
    tokenColor: String(source.tokenColor ?? '#9caf79'),
    locationName: String(source.locationName ?? 'Calostrynn'),
    previousOwnerName: source.previousOwnerName ? String(source.previousOwnerName) : undefined
  };
}

export function normalizeProfile(value: unknown): CampaignProfile {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};

  return {
    id: String(source.id ?? ''),
    username: source.username ? String(source.username) : undefined,
    displayName: String(source.displayName ?? source.username ?? 'Player'),
    role: source.role === 'dm' ? 'dm' : 'player'
  };
}

export function normalizeLedgerPayload(value: unknown): CharacterLedgerPayload {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  const profiles = Array.isArray(source.profiles) ? source.profiles.map(normalizeProfile).filter((profile) => profile.id) : [];
  const classes = Array.isArray(source.classes) ? source.classes.map(normalizeClassTemplate).filter((template) => template.key) : [];
  const characters = Array.isArray(source.characters) ? source.characters.map(normalizeCharacter).filter((character) => character.id) : [];

  return {
    profile: normalizeProfile(source.profile),
    profiles,
    classes,
    characters
  };
}
