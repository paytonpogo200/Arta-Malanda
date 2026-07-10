'use client';

import { createContext, useContext, useMemo, useReducer, type ReactNode } from 'react';
import { characterFromClass, initialCampaignState } from '@/features/campaign/mockCampaign';
import { createId } from '@/lib/utils/ids';
import type { CampaignState, Character, Combatant, InventoryItem, LoadoutSlot } from '@/lib/types';

type CampaignAction =
  | { type: 'profile/toggle-role' }
  | { type: 'character/create'; classKey: string; name: string; personalPassives?: string }
  | { type: 'character/update'; characterId: string; patch: Partial<Character> }
  | { type: 'inventory/add'; item: Omit<InventoryItem, 'id'> }
  | { type: 'inventory/move'; itemId: string; slotIndex: number; parentItemId: string | null }
  | { type: 'inventory/equip'; itemId: string; loadoutSlot: LoadoutSlot | null }
  | { type: 'inventory/stack'; sourceItemId: string; targetItemId: string }
  | { type: 'battle/start'; characterIds: string[] }
  | { type: 'battle/end' }
  | { type: 'battle/move'; combatantId: string; x: number; y: number }
  | { type: 'battle/update'; combatantId: string; patch: Partial<Combatant> };

const StateContext = createContext<CampaignState | null>(null);
const DispatchContext = createContext<React.Dispatch<CampaignAction> | null>(null);

function nextOpenSlot(items: InventoryItem[], characterId: string, parentItemId: string | null, preferred = 0) {
  const occupied = new Set(items.filter((item) => item.characterId === characterId && item.parentItemId === parentItemId && item.loadoutSlot === null).map((item) => item.slotIndex));
  if (!occupied.has(preferred)) return preferred;
  for (let index = 0; index < 120; index += 1) {
    if (!occupied.has(index)) return index;
  }
  return preferred;
}

function canStack(a: InventoryItem, b: InventoryItem) {
  return a.id !== b.id
    && !a.isStorage
    && !b.isStorage
    && a.name.trim().toLowerCase() === b.name.trim().toLowerCase()
    && a.rarity === b.rarity
    && a.type === b.type
    && (a.spellImbue ?? '') === (b.spellImbue ?? '');
}

function centeredPosition(index: number, gridWidth: number, gridHeight: number) {
  const columns = 5;
  const x = Math.floor(gridWidth / 2) + (index % columns) - Math.floor(columns / 2);
  const y = Math.floor(gridHeight / 2) + Math.floor(index / columns);
  return {
    x: Math.max(0, Math.min(gridWidth - 1, x)),
    y: Math.max(0, Math.min(gridHeight - 1, y))
  };
}

function campaignReducer(state: CampaignState, action: CampaignAction): CampaignState {
  switch (action.type) {
    case 'profile/toggle-role':
      return {
        ...state,
        profile: { ...state.profile, role: state.profile.role === 'dm' ? 'player' : 'dm', displayName: state.profile.role === 'dm' ? 'Party Member' : 'Dungeon Master' }
      };

    case 'character/create': {
      const template = state.classes.find((entry) => entry.key === action.classKey) ?? state.classes[0];
      const character = characterFromClass(template, action.name, state.profile.id);
      character.personalPassives = action.personalPassives?.trim() ?? '';
      return { ...state, characters: [character, ...state.characters] };
    }

    case 'character/update':
      return {
        ...state,
        characters: state.characters.map((character) => character.id === action.characterId ? { ...character, ...action.patch } : character)
      };

    case 'inventory/add':
      return {
        ...state,
        items: [{ id: createId('item'), ...action.item }, ...state.items]
      };

    case 'inventory/move': {
      const moved = state.items.find((item) => item.id === action.itemId);
      const target = state.items.find((item) => moved && item.characterId === moved.characterId && item.parentItemId === action.parentItemId && item.slotIndex === action.slotIndex && item.loadoutSlot === null);
      if (moved && target && canStack(moved, target)) {
        return {
          ...state,
          items: state.items
            .filter((item) => item.id !== moved.id)
            .map((item) => item.id === target.id ? { ...item, quantity: item.quantity + moved.quantity } : item)
        };
      }
      return {
        ...state,
        items: state.items.map((item) => item.id === action.itemId ? { ...item, parentItemId: action.parentItemId, slotIndex: action.slotIndex, loadoutSlot: null } : item)
      };
    }

    case 'inventory/equip':
      return {
        ...state,
        items: state.items.map((item) => {
          if (item.id === action.itemId) return { ...item, loadoutSlot: action.loadoutSlot, parentItemId: null, slotIndex: nextOpenSlot(state.items, item.characterId, null, item.slotIndex) };
          if (action.loadoutSlot && item.loadoutSlot === action.loadoutSlot) return { ...item, loadoutSlot: null };
          return item;
        })
      };

    case 'inventory/stack': {
      const source = state.items.find((item) => item.id === action.sourceItemId);
      const target = state.items.find((item) => item.id === action.targetItemId);
      if (!source || !target || !canStack(source, target)) return state;
      return {
        ...state,
        items: state.items
          .filter((item) => item.id !== source.id)
          .map((item) => item.id === target.id ? { ...item, quantity: item.quantity + source.quantity } : item)
      };
    }

    case 'battle/start': {
      const battle = { id: createId('battle'), status: 'active' as const, gridWidth: 24, gridHeight: 24 };
      const combatants = action.characterIds.map((characterId, index) => {
        const character = state.characters.find((entry) => entry.id === characterId);
        const position = centeredPosition(index, battle.gridWidth, battle.gridHeight);
        return {
          id: createId('combatant'),
          battleId: battle.id,
          characterId,
          x: position.x,
          y: position.y,
          currentHp: character?.currentHp ?? 0,
          currentMana: character?.currentMana ?? 0,
          initiative: null
        };
      });
      return { ...state, battle, combatants };
    }

    case 'battle/end':
      return {
        ...state,
        battle: null,
        combatants: [],
        characters: state.characters.map((character) => {
          const combatant = state.combatants.find((entry) => entry.characterId === character.id);
          return combatant ? { ...character, currentHp: combatant.currentHp, currentMana: combatant.currentMana } : character;
        })
      };

    case 'battle/move':
      return {
        ...state,
        combatants: state.combatants.map((combatant) => combatant.id === action.combatantId ? { ...combatant, x: action.x, y: action.y } : combatant)
      };

    case 'battle/update':
      return {
        ...state,
        combatants: state.combatants.map((combatant) => combatant.id === action.combatantId ? { ...combatant, ...action.patch } : combatant)
      };

    default:
      return state;
  }
}

export function CampaignProvider({ children }: { children: ReactNode }) {
  const [state, dispatch] = useReducer(campaignReducer, initialCampaignState);
  const stateValue = useMemo(() => state, [state]);
  return (
    <StateContext.Provider value={stateValue}>
      <DispatchContext.Provider value={dispatch}>{children}</DispatchContext.Provider>
    </StateContext.Provider>
  );
}

export function useCampaignState() {
  const value = useContext(StateContext);
  if (!value) throw new Error('useCampaignState must be used inside CampaignProvider');
  return value;
}

export function useCampaignDispatch() {
  const value = useContext(DispatchContext);
  if (!value) throw new Error('useCampaignDispatch must be used inside CampaignProvider');
  return value;
}
