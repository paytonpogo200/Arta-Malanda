import { normalizeCharacter, normalizeClassTemplate } from '@/features/characters/data';
import { normalizeInventoryItem } from '@/features/inventory/data';
import { normalizeBestiaryEntity } from '@/features/bestiary/data';
import type { Battle, BattleTerrain, BattleTilePaint, BestiaryEntity, Character, ClassTemplate, Combatant, CombatStatus, InventoryItem } from '@/lib/types';

export type BattleRoomPayload = {
  battle: Battle | null;
  combatants: Combatant[];
  terrain: BattleTerrain[];
  tilePaint: BattleTilePaint[];
  characters: Character[];
  classes: ClassTemplate[];
  inventoryItems: InventoryItem[];
  bestiary: BestiaryEntity[];
};

function numberFrom(value: unknown, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

export function normalizeBattle(value: unknown): Battle | null {
  if (!value || typeof value !== 'object') return null;
  const source = value as Record<string, unknown>;
  const id = String(source.id ?? '');
  if (!id) return null;

  return {
    id,
    status: source.status === 'ended' ? 'ended' : 'active',
    gridWidth: Math.max(5, numberFrom(source.gridWidth, 24)),
    gridHeight: Math.max(5, numberFrom(source.gridHeight, 24))
  };
}

export function normalizeCombatant(value: unknown): Combatant {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};

  return {
    id: String(source.id ?? ''),
    battleId: String(source.battleId ?? ''),
    characterId: String(source.characterId ?? ''),
    x: Math.max(0, numberFrom(source.x, 0)),
    y: Math.max(0, numberFrom(source.y, 0)),
    currentHp: Math.max(0, numberFrom(source.currentHp, 0)),
    currentMana: Math.max(0, numberFrom(source.currentMana, 0)),
    initiative: source.initiative === null || source.initiative === undefined ? null : Math.max(1, Math.min(20, numberFrom(source.initiative, 1))),
    statuses: Array.isArray(source.statuses) ? source.statuses.map(normalizeCombatStatus).filter((status) => status.id && status.key) : []
  };
}

export function normalizeCombatStatus(value: unknown): CombatStatus {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  const key = String(source.key ?? '').trim().toLowerCase();
  return {
    id: String(source.id ?? ''),
    key,
    name: String(source.name ?? (key ? key[0].toUpperCase() + key.slice(1) : 'Effect')),
    kind: source.kind === 'permanent' ? 'permanent' : source.kind === 'buff' ? 'buff' : 'debuff',
    duration: source.duration === null || source.duration === undefined ? null : Math.max(1, Math.min(99, Math.round(numberFrom(source.duration, 1)))),
    amount: Math.max(0, Math.round(numberFrom(source.amount, 0)))
  };
}

export function normalizeBattleTerrain(value: unknown): BattleTerrain {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  return {
    id: String(source.id ?? ''),
    battleId: String(source.battleId ?? ''),
    x: Math.max(0, numberFrom(source.x, 0)),
    y: Math.max(0, numberFrom(source.y, 0)),
    type: 'blocked'
  };
}

export function normalizeBattleTilePaint(value: unknown): BattleTilePaint | null {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  const battleId = String(source.battleId ?? '');
  const color = String(source.color ?? '').trim().toLowerCase();
  const x = numberFrom(source.x, -1);
  const y = numberFrom(source.y, -1);
  if (!battleId || !/^#[0-9a-f]{6}$/.test(color) || !Number.isInteger(x) || !Number.isInteger(y) || x < 0 || y < 0) return null;
  return { battleId, x, y, color };
}

export function normalizeBattleRoomPayload(value: unknown): BattleRoomPayload {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};

  return {
    battle: normalizeBattle(source.battle),
    combatants: Array.isArray(source.combatants) ? source.combatants.map(normalizeCombatant).filter((entry) => entry.id) : [],
    terrain: Array.isArray(source.terrain) ? source.terrain.map(normalizeBattleTerrain).filter((entry) => entry.id) : [],
    tilePaint: Array.isArray(source.tilePaint) ? source.tilePaint.map(normalizeBattleTilePaint).filter((entry): entry is BattleTilePaint => entry !== null) : [],
    characters: Array.isArray(source.characters) ? source.characters.map(normalizeCharacter).filter((entry) => entry.id) : [],
    classes: Array.isArray(source.classes) ? source.classes.map(normalizeClassTemplate).filter((entry) => entry.key) : [],
    inventoryItems: Array.isArray(source.inventoryItems) ? source.inventoryItems.map(normalizeInventoryItem).filter((entry) => entry.id) : [],
    bestiary: Array.isArray(source.bestiary) ? source.bestiary.map(normalizeBestiaryEntity).filter((entry) => entry.id) : []
  };
}
