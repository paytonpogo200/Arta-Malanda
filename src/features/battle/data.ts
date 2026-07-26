import { normalizeCharacter } from '@/features/characters/data';
import { normalizeBestiaryEntity } from '@/features/bestiary/data';
import type { Battle, BattleTerrain, BestiaryEntity, Character, Combatant } from '@/lib/types';

export type BattleRoomPayload = {
  battle: Battle | null;
  combatants: Combatant[];
  terrain: BattleTerrain[];
  characters: Character[];
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
    initiative: source.initiative === null || source.initiative === undefined ? null : Math.max(1, Math.min(20, numberFrom(source.initiative, 1)))
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

export function normalizeBattleRoomPayload(value: unknown): BattleRoomPayload {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};

  return {
    battle: normalizeBattle(source.battle),
    combatants: Array.isArray(source.combatants) ? source.combatants.map(normalizeCombatant).filter((entry) => entry.id) : [],
    terrain: Array.isArray(source.terrain) ? source.terrain.map(normalizeBattleTerrain).filter((entry) => entry.id) : [],
    characters: Array.isArray(source.characters) ? source.characters.map(normalizeCharacter).filter((entry) => entry.id) : [],
    bestiary: Array.isArray(source.bestiary) ? source.bestiary.map(normalizeBestiaryEntity).filter((entry) => entry.id) : []
  };
}
