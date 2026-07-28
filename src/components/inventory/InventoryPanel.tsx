'use client';

import { useCallback, useEffect, useMemo, useState, type FormEvent } from 'react';
import { Loader2, PackageOpen, RefreshCw, Search } from 'lucide-react';
import { ItemIcon } from '@/components/inventory/ItemIcon';
import { InventorySlot } from '@/components/inventory/InventorySlot';
import { LoadoutPanel } from '@/components/inventory/LoadoutPanel';
import { Button } from '@/components/ui/Button';
import { Card } from '@/components/ui/Card';
import { SelectField, TextAreaField, TextField } from '@/components/ui/Field';
import { Modal } from '@/components/ui/Modal';
import { NumberInput } from '@/components/ui/NumberInput';
import { normalizeUpdateAssetsPayload } from '@/features/assets/data';
import { normalizeHousePayload } from '@/features/houses/data';
import { ITEM_TYPES, acceptsLoadoutItem, normalizeCharacterInventoryPayload, normalizeInventoryItem, quantityStepForItem } from '@/features/inventory/data';
import {
  EDITABLE_MODIFIER_FIELDS,
  canApplyRune,
  canManuallyEnchant,
  canManuallyEnhance,
  cleanModifiers,
  itemHasEnhancementVisual,
  modifierEntries,
  modifierText,
  modifierToneClass,
  spellForEnchantment
} from '@/features/inventory/itemDetails';
import { rarityClass, rarityOptions } from '@/lib/utils/rarity';
import { spellManaText } from '@/lib/utils/spells';
import type { Character, InventoryItem, ItemCatalogEntry, ItemRarity, ItemType, LoadoutModifierKey, LoadoutModifiers, LoadoutSlot, Spell, WalletBalance } from '@/lib/types';

type SlotTarget = {
  slot: number;
  parentItemId: string | null;
  item?: InventoryItem;
  source?: 'inventory' | 'wagon';
  wagonId?: string;
};

type AvailableRune = {
  source: 'inventory' | 'house';
  item: InventoryItem;
};

type WagonStorage = {
  wagon: InventoryItem;
  ownerCharacterId: string;
  ownerName: string;
  ownerUserId: string | null;
  canManage: boolean;
};

type ItemDraft = {
  name: string;
  displayName: string;
  itemDescription: string;
  type: ItemType;
  rarity: ItemRarity;
  quantity: number;
  storageCapacity: number;
  enchantment: string;
  material: string;
  enhancementCount: number;
  isTwoHanded: boolean;
  modifiers: LoadoutModifiers;
  potionStrength: string;
  potionProperty: string;
  potionQuality: string;
};

function normalizeWagonPayload(source: unknown) {
  const payload = source && typeof source === 'object' ? source as Record<string, unknown> : {};
  const wagons = Array.isArray(payload.wagons) ? payload.wagons.map((entry) => {
    const record = entry && typeof entry === 'object' ? entry as Record<string, unknown> : {};
    return {
      wagon: normalizeInventoryItem(record.wagon),
      ownerCharacterId: String(record.ownerCharacterId ?? ''),
      ownerName: String(record.ownerName ?? 'Unknown'),
      ownerUserId: record.ownerUserId ? String(record.ownerUserId) : null,
      canManage: Boolean(record.canManage)
    };
  }).filter((entry) => entry.wagon.id) : [];
  const items = Array.isArray(payload.items) ? payload.items.map(normalizeInventoryItem).filter((entry) => entry.id) : [];
  return { wagons, items };
}

const EMPTY_DRAFT: ItemDraft = {
  name: '',
  displayName: '',
  itemDescription: '',
  type: 'misc',
  rarity: 'Common',
  quantity: 1,
  storageCapacity: 0,
  enchantment: '',
  material: '',
  enhancementCount: 0,
  isTwoHanded: false,
  modifiers: {},
  potionStrength: '',
  potionProperty: '',
  potionQuality: ''
};

const POTION_STRENGTHS = ['Lesser', 'Greater', 'Greatest'];
const POTION_QUALITIES = ['Shoddy', 'Basic', 'Fine', 'Strong', 'Enriched'];
const POTION_PROPERTIES = [
  { key: 'Healing', label: 'Healing' },
  { key: 'Speed', label: 'Swiftness' },
  { key: 'Agility', label: 'Agility' },
  { key: 'Strength', label: 'Strength' },
  { key: 'Sorcery', label: 'Sorcery' },
  { key: 'Mana Regen', label: 'Mana' },
  { key: 'Luck', label: 'Luck' },
  { key: 'Antidote', label: 'Antidote' },
  { key: 'Warming', label: 'Warming' },
  { key: 'Cooling', label: 'Cooling' },
  { key: 'Night-Eye', label: 'Night-Eye' },
  { key: 'Thickskin', label: 'Thickskin' },
  { key: 'Clear-Mind', label: 'Clear-Mind' },
  { key: 'Wake-Up', label: 'Wake-Up' },
  { key: 'Clotting', label: 'Clotting' }
];

function sameContainer(item: InventoryItem, parentItemId: string | null) {
  return (item.parentItemId ?? null) === parentItemId && item.loadoutSlot === null;
}

function inferStorageCapacity(itemName: string) {
  const normalized = itemName.toLowerCase();
  if (normalized.includes('bag of holding')) return 100;
  if (normalized.includes('heavy wagon')) return 60;
  if (normalized.includes('light wagon')) return 25;
  if (normalized.includes('heavy duffle')) return 10;
  if (normalized.includes('light duffle')) return 6;
  if (normalized.includes('back bag') || normalized.includes('backpack')) return 3;
  if (normalized.includes('waist pouch') || normalized.includes('pouch')) return 1;
  if (normalized.includes('satchel')) return 3;
  return 6;
}

function firstOpenSlot(items: InventoryItem[], parentItemId: string | null, capacity: number) {
  const occupied = new Set(items.filter((item) => sameContainer(item, parentItemId)).map((item) => item.slotIndex));
  for (let slot = 0; slot < capacity; slot += 1) {
    if (!occupied.has(slot)) return slot;
  }
  return null;
}

function itemSupportsLoadoutDetails(type: ItemType) {
  return type === 'weapon' || type === 'armor' || type === 'shield' || type === 'accessory' || type === 'pet';
}

function normalizedItemName(name: string) {
  const clean = name.trim().toLowerCase();
  if (clean === 'glass flask' || clean === 'glass flasks' || clean === 'empty flasks') return 'empty flask';
  if (clean === 'mana recovery potion') return 'mana potion';
  return clean;
}

function isEmptyFlask(item: Pick<InventoryItem, 'name'> | Pick<ItemDraft, 'name'>) {
  return normalizedItemName(item.name) === 'empty flask';
}

function isArcaneNector(item: Pick<InventoryItem, 'name'> | Pick<ItemDraft, 'name'>) {
  return normalizedItemName(item.name) === 'arcane nector';
}

function isPotionConsumable(item: InventoryItem) {
  return item.type === 'potion' && !isEmptyFlask(item);
}

function potionQualityCanApply(item: Pick<ItemDraft, 'name' | 'type' | 'potionProperty'>) {
  if (item.type !== 'potion' || isEmptyFlask(item) || isArcaneNector(item)) return false;
  const property = item.potionProperty || '';
  if (property === 'Healing' || property === 'Mana Regen') return false;
  const name = normalizedItemName(item.name);
  return !name.includes('healing potion') && !name.includes('mana potion');
}

function draftFromItem(item: InventoryItem): ItemDraft {
  return {
    name: item.name,
    displayName: item.displayName ?? '',
    itemDescription: item.itemDescription ?? '',
    type: item.type,
    rarity: item.rarity,
    quantity: item.quantity,
    storageCapacity: item.storageCapacity,
    enchantment: item.enchantment ?? '',
    material: item.material ?? '',
    enhancementCount: item.enhancementCount,
    isTwoHanded: item.isTwoHanded,
    modifiers: cleanModifiers(item.modifiers),
    potionStrength: item.potionStrength ?? '',
    potionProperty: item.potionProperty ?? '',
    potionQuality: item.potionQuality ?? ''
  };
}

export function InventoryPanel({
  character,
  canManage,
  canAdd,
  refreshSignal = 0,
  onItemsChanged,
  onResourceChanged
}: {
  character: Character;
  canManage: boolean;
  canAdd: boolean;
  refreshSignal?: number;
  onItemsChanged?: (items: InventoryItem[]) => void;
  onResourceChanged?: (patch: { currentHp?: number; currentMana?: number }) => void;
}) {
  const [items, setItems] = useState<InventoryItem[]>([]);
  const [wallet, setWallet] = useState<WalletBalance[]>([]);
  const [walletDraft, setWalletDraft] = useState<Record<string, number>>({});
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [target, setTarget] = useState<string | null>(null);
  const [modal, setModal] = useState<SlotTarget | null>(null);
  const [draft, setDraft] = useState<ItemDraft>(EMPTY_DRAFT);
  const [dropQuantity, setDropQuantity] = useState(1);
  const [catalog, setCatalog] = useState<ItemCatalogEntry[]>([]);
  const [spells, setSpells] = useState<Spell[]>([]);
  const [catalogLoading, setCatalogLoading] = useState(false);
  const [catalogSearch, setCatalogSearch] = useState('');
  const [addMode, setAddMode] = useState<'catalog' | 'custom'>('catalog');
  const [enhanceOpen, setEnhanceOpen] = useState(false);
  const [enhanceStat, setEnhanceStat] = useState<LoadoutModifierKey>('strength');
  const [houseRunes, setHouseRunes] = useState<InventoryItem[]>([]);
  const [nearbyWagons, setNearbyWagons] = useState<WagonStorage[]>([]);
  const [nearbyWagonItems, setNearbyWagonItems] = useState<InventoryItem[]>([]);
  const [runeLoading, setRuneLoading] = useState(false);
  const [runeError, setRuneError] = useState('');

  const loadWagons = useCallback(async () => {
    if (!canManage && !canAdd) {
      setNearbyWagons([]);
      setNearbyWagonItems([]);
      return;
    }

    try {
      const response = await fetch(`/api/characters/${character.id}/wagons`, { cache: 'no-store' });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.error ?? 'Nearby wagons could not be loaded.');
      const normalized = normalizeWagonPayload(payload);
      const sharedWagons = normalized.wagons.filter((entry) => entry.ownerCharacterId !== character.id);
      const sharedWagonIds = new Set(sharedWagons.map((entry) => entry.wagon.id));
      setNearbyWagons(sharedWagons);
      setNearbyWagonItems(normalized.items.filter((item) => item.parentItemId && sharedWagonIds.has(item.parentItemId)));
    } catch {
      setNearbyWagons([]);
      setNearbyWagonItems([]);
    }
  }, [canAdd, canManage, character.id]);

  const loadInventory = useCallback(async () => {
    setLoading(true);
    setError('');
    try {
      const response = await fetch(`/api/characters/${character.id}/inventory`, { cache: 'no-store' });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.error ?? 'Inventory could not be loaded.');
      const normalized = normalizeCharacterInventoryPayload(payload);
      setItems(normalized.items);
      onItemsChanged?.(normalized.items);
      setWallet(normalized.wallet);
      setWalletDraft(Object.fromEntries(normalized.wallet.map((entry) => [entry.unit.id, entry.amount])));
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : 'Inventory could not be loaded.');
    } finally {
      setLoading(false);
    }
  }, [character.id, onItemsChanged]);

  useEffect(() => {
    void loadInventory();
    void loadWagons();
  }, [loadInventory, loadWagons, refreshSignal]);

  useEffect(() => {
    if (!modal?.item || !canApplyRune(modal.item) || !character.ownerUserId) {
      setHouseRunes([]);
      setRuneError('');
      return;
    }

    let cancelled = false;
    setRuneLoading(true);
    setRuneError('');
    fetch(`/api/houses/${character.ownerUserId}`, { cache: 'no-store' })
      .then(async (response) => {
        const payload = await response.json().catch(() => ({}));
        if (!response.ok) throw new Error(payload.error ?? 'House runes could not be loaded.');
        if (!cancelled) {
          const normalized = normalizeHousePayload(payload);
          setHouseRunes(normalized.items.filter((item) => item.type === 'rune' && item.quantity > 0));
        }
      })
      .catch((loadError) => {
        if (!cancelled) {
          setHouseRunes([]);
          setRuneError(loadError instanceof Error ? loadError.message : 'House runes could not be loaded.');
        }
      })
      .finally(() => {
        if (!cancelled) setRuneLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, [character.ownerUserId, modal?.item]);

  const loadCatalog = useCallback(async () => {
    if (!canAdd) return;
    setCatalogLoading(true);
    try {
      const response = await fetch('/api/assets', { cache: 'no-store' });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) return;
      const normalized = normalizeUpdateAssetsPayload(payload);
      setSpells(normalized.spells.sort((a, b) => a.name.localeCompare(b.name)));
      const uniqueByName = new Map<string, ItemCatalogEntry>();
      const catalogSource = normalized.itemCatalog.length
        ? normalized.itemCatalog.filter((entry) => entry.type !== 'currency' && entry.active)
        : normalized.lootItems.filter((entry) => entry.type !== 'currency').map((entry) => ({
          id: entry.id,
          key: entry.name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, ''),
          name: entry.name,
          type: entry.type,
          rarity: entry.rarity,
          category: entry.category,
          properties: [],
          quantityStep: 1,
          stackable: true,
          defaultModifiers: {},
          material: '',
          isTwoHanded: false,
          storageCapacity: entry.type === 'storage' ? inferStorageCapacity(entry.name) : 0,
          notes: entry.notes,
          active: true,
          order: 0
        } satisfies ItemCatalogEntry));
      for (const item of catalogSource) {
        const key = `${item.name.toLowerCase()}|${item.rarity}|${item.type}`;
        if (!uniqueByName.has(key)) uniqueByName.set(key, item);
      }
      setCatalog([...uniqueByName.values()].sort((a, b) => a.name.localeCompare(b.name)));
    } finally {
      setCatalogLoading(false);
    }
  }, [canAdd]);

  useEffect(() => {
    void loadCatalog();
  }, [loadCatalog]);

  const mainItems = useMemo(() => items.filter((item) => sameContainer(item, null) && !item.isStorage), [items]);
  const itemByMainSlot = useMemo(() => new Map(mainItems.map((item) => [item.slotIndex, item])), [mainItems]);
  const storageItems = useMemo(() => items.filter((item) => item.isStorage), [items]);
  const nearbyWagonItemIds = useMemo(() => new Set(nearbyWagonItems.map((item) => item.id)), [nearbyWagonItems]);
  const filteredCatalog = useMemo(() => {
    const search = catalogSearch.trim().toLowerCase();
    const source = search
      ? catalog.filter((item) => `${item.name} ${item.type} ${item.rarity} ${item.category} ${item.properties.join(' ')}`.toLowerCase().includes(search))
      : catalog;
    return source.slice(0, 80);
  }, [catalog, catalogSearch]);
  const modalSpell = useMemo(() => modal?.item ? spellForEnchantment(spells, modal.item.enchantment) : null, [modal, spells]);
  const sortedSpells = useMemo(() => [...spells].sort((a, b) => a.name.localeCompare(b.name)), [spells]);
  const availableRunes = useMemo<AvailableRune[]>(() => {
    if (!modal?.item || !canApplyRune(modal.item)) return [];
    const inventoryRunes = items
      .filter((item) => item.type === 'rune' && item.quantity > 0)
      .map((item) => ({ source: 'inventory' as const, item }));
    const homeRunes = houseRunes.map((item) => ({ source: 'house' as const, item }));
    return [...inventoryRunes, ...homeRunes].sort((a, b) => a.item.name.localeCompare(b.item.name) || a.source.localeCompare(b.source));
  }, [houseRunes, items, modal?.item]);

  function openSlot(slot: number, parentItemId: string | null, item?: InventoryItem) {
    if (!item && !canAdd) return;
    setModal({ slot, parentItemId, item });
    setDraft(item ? draftFromItem(item) : EMPTY_DRAFT);
    setDropQuantity(item?.quantity ?? 1);
    setCatalogSearch('');
    setAddMode(item ? 'custom' : 'catalog');
    setEnhanceOpen(false);
    setEnhanceStat('strength');
  }

  function chooseCatalogItem(item: ItemCatalogEntry) {
    setDraft({
      name: item.name,
      displayName: '',
      itemDescription: '',
      type: item.type,
      rarity: item.rarity,
      quantity: Math.max(item.quantityStep || 1, item.quantityStep || 1),
      storageCapacity: item.type === 'storage' ? item.storageCapacity || inferStorageCapacity(item.name) : 0,
      enchantment: '',
      material: item.material,
      enhancementCount: 0,
      isTwoHanded: item.isTwoHanded,
      modifiers: cleanModifiers(item.defaultModifiers),
      potionStrength: '',
      potionProperty: '',
      potionQuality: ''
    });
  }

  function updateDraftEnchantment(enchantment: string) {
    setDraft({
      ...draft,
      enchantment,
      enhancementCount: enchantment.trim() ? 0 : draft.enhancementCount
    });
  }

  function confirmDraftEnhancement() {
    if (!canManuallyEnhance(draft) || draft.enhancementCount >= 3) return;
    const currentValue = Number(draft.modifiers[enhanceStat] ?? 0);
    setDraft({
      ...draft,
      modifiers: cleanModifiers({ ...draft.modifiers, [enhanceStat]: currentValue + 1 }),
      enhancementCount: Math.min(3, draft.enhancementCount + 1),
      enchantment: ''
    });
    setEnhanceOpen(false);
  }

  function updateDraftModifier(key: LoadoutModifierKey, value: number) {
    setDraft({
      ...draft,
      modifiers: cleanModifiers({ ...draft.modifiers, [key]: value })
    });
  }

  async function requestInventoryChange(url: string, init: RequestInit) {
    setSaving(true);
    setError('');
    try {
      const response = await fetch(url, init);
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.error ?? 'Inventory action failed.');
      setModal(null);
      await loadInventory();
    } catch (actionError) {
      setError(actionError instanceof Error ? actionError.message : 'Inventory action failed.');
    } finally {
      setSaving(false);
    }
  }

  async function patchItemState(itemId: string, patch: Record<string, unknown>, optimisticItems: InventoryItem[]) {
    const previousItems = items;
    setItems(optimisticItems);
    onItemsChanged?.(optimisticItems);
    setError('');
    try {
      const response = await fetch(`/api/inventory/items/${itemId}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(patch)
      });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.error ?? 'Inventory action failed.');
      const updated = payload.item ? normalizeInventoryItem(payload.item) : null;
      if (!updated) {
        setItems((current) => {
          const next = current.filter((item) => item.id !== itemId);
          onItemsChanged?.(next);
          return next;
        });
        setModal((current) => current?.item?.id === itemId ? null : current);
        return;
      }
      setModal((current) => current?.item?.id === updated.id ? { ...current, item: updated } : current);
      setItems((current) => {
        const withoutMoved = current.filter((item) => item.id !== itemId);
        const replaced = withoutMoved.map((item) => item.id === updated.id ? updated : item);
        const next = replaced.some((item) => item.id === updated.id) ? replaced : [...withoutMoved, updated];
        onItemsChanged?.(next);
        return next;
      });
    } catch (actionError) {
      setItems(previousItems);
      onItemsChanged?.(previousItems);
      setError(actionError instanceof Error ? actionError.message : 'Inventory action failed.');
    }
  }

  async function addItem(event: FormEvent) {
    event.preventDefault();
    if (!modal || modal.item || !canAdd || !draft.name.trim()) return;
    await requestInventoryChange(`/api/characters/${character.id}/inventory`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        ...draft,
        parentItemId: modal.parentItemId,
        slotIndex: modal.slot,
        isStorage: draft.type === 'storage',
        storageCapacity: draft.type === 'storage' ? Math.max(1, draft.storageCapacity || 6) : 0,
        enchantment: draft.enchantment.trim() || null,
        material: draft.material.trim(),
        enhancementCount: draft.enhancementCount,
        isTwoHanded: draft.isTwoHanded,
        modifiers: cleanModifiers(draft.modifiers),
        itemDescription: draft.itemDescription.trim(),
        potionStrength: draft.potionStrength,
        potionProperty: draft.potionProperty,
        potionQuality: potionQualityCanApply(draft) ? draft.potionQuality : ''
      })
    });
  }

  async function updateItem(event: FormEvent) {
    event.preventDefault();
    if (!modal?.item || !canAdd || !draft.name.trim()) return;
    await requestInventoryChange(`/api/inventory/items/${modal.item.id}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        name: draft.name.trim(),
        type: draft.type,
        rarity: draft.rarity,
        quantity: Math.max(quantityStepForItem(draft), draft.quantity),
        isStorage: draft.type === 'storage',
        storageCapacity: draft.type === 'storage' ? Math.max(1, draft.storageCapacity || 6) : 0,
        enchantment: draft.enchantment.trim() || null,
        material: draft.material.trim(),
        enhancementCount: draft.enhancementCount,
        isTwoHanded: draft.isTwoHanded,
        modifiers: cleanModifiers(draft.modifiers),
        itemDescription: draft.itemDescription.trim(),
        potionStrength: draft.potionStrength,
        potionProperty: draft.potionProperty,
        potionQuality: potionQualityCanApply(draft) ? draft.potionQuality : ''
      })
    });
  }

  async function savePetDisplayName(event: FormEvent) {
    event.preventDefault();
    if (!modal?.item || modal.item.type !== 'pet' || !canManage) return;
    const displayName = draft.displayName.trim();
    const optimisticItems = items.map((item) => item.id === modal.item!.id ? { ...item, displayName: displayName || undefined } : item);
    setDraft({ ...draft, displayName });
    await patchItemState(modal.item.id, { displayName: displayName || null }, optimisticItems);
  }

  async function applyRune(source: AvailableRune) {
    if (!modal?.item || !canManage || !canApplyRune(modal.item)) return;
    await requestInventoryChange(`/api/inventory/items/${modal.item.id}/rune`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ runeItemId: source.item.id, source: source.source })
    });
  }

  async function moveItem(itemId: string, slot: number, parentItemId: string | null) {
    if (!canManage) return;
    if (nearbyWagonItemIds.has(itemId)) {
      await takeFromWagon(itemId, slot, parentItemId);
      return;
    }

    const movingItem = items.find((item) => item.id === itemId);
    if (movingItem && sameContainer(movingItem, parentItemId) && movingItem.slotIndex === slot && !movingItem.loadoutSlot) return;

    setTarget(`${parentItemId ?? 'main'}:${slot}`);
    const targetItem = items.find((item) => item.id !== itemId && sameContainer(item, parentItemId) && item.slotIndex === slot);
    let optimisticItems = items;
    if (movingItem) {
      const targetCapacity = parentItemId
        ? items.find((item) => item.id === parentItemId)?.storageCapacity ?? 0
        : character.inventorySlots;
      const targetFallbackSlot = targetItem && movingItem.loadoutSlot
        ? firstOpenSlot(items, parentItemId, targetCapacity)
        : null;
      optimisticItems = items.map((item) => {
        if (item.id === movingItem.id) return { ...item, parentItemId, slotIndex: slot, loadoutSlot: null };
        if (targetItem && item.id === targetItem.id) {
          return {
            ...item,
            parentItemId: movingItem.loadoutSlot ? parentItemId : movingItem.parentItemId,
            slotIndex: movingItem.loadoutSlot ? targetFallbackSlot ?? item.slotIndex : movingItem.slotIndex,
            loadoutSlot: null
          };
        }
        return item;
      });
    }
    await patchItemState(itemId, { parentItemId, slotIndex: slot, loadoutSlot: null }, optimisticItems);
    window.setTimeout(() => setTarget(null), 120);
  }

  async function moveItemToWagon(itemId: string, wagonId: string, slot: number) {
    if (!canManage) return;
    const movingItem = items.find((item) => item.id === itemId);
    if (!movingItem) return;
    setTarget(`${wagonId}:${slot}`);
    setSaving(true);
    setError('');
    try {
      const response = await fetch(`/api/inventory/items/${itemId}/send-wagon`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ characterId: character.id, wagonId, slotIndex: slot })
      });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.error ?? 'Item could not be moved into the wagon.');
      setItems((current) => {
        const next = current.filter((item) => item.id !== itemId);
        onItemsChanged?.(next);
        return next;
      });
      const normalized = normalizeWagonPayload(payload);
      setNearbyWagons(normalized.wagons.filter((entry) => entry.ownerCharacterId !== character.id));
      setNearbyWagonItems(normalized.items);
      setModal(null);
    } catch (actionError) {
      setError(actionError instanceof Error ? actionError.message : 'Item could not be moved into the wagon.');
      await loadInventory();
      await loadWagons();
    } finally {
      setSaving(false);
      window.setTimeout(() => setTarget(null), 120);
    }
  }

  async function takeFromWagon(itemId: string, slot?: number, parentItemId: string | null = null) {
    if (!canManage) return;
    setSaving(true);
    setError('');
    try {
      const response = await fetch(`/api/wagons/items/${itemId}/take`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ characterId: character.id, parentItemId, slotIndex: slot })
      });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.error ?? 'Item could not be taken from the wagon.');
      const normalized = normalizeCharacterInventoryPayload(payload);
      setItems(normalized.items);
      onItemsChanged?.(normalized.items);
      setWallet(normalized.wallet);
      setWalletDraft(Object.fromEntries(normalized.wallet.map((entry) => [entry.unit.id, entry.amount])));
      await loadWagons();
      setModal(null);
    } catch (actionError) {
      setError(actionError instanceof Error ? actionError.message : 'Item could not be taken from the wagon.');
    } finally {
      setSaving(false);
      window.setTimeout(() => setTarget(null), 120);
    }
  }

  async function equipItem(itemId: string, loadoutSlot: LoadoutSlot | null) {
    if (!canManage) return;
    const optimisticItems = loadoutSlot
      ? items.map((item) => item.id === itemId ? { ...item, loadoutSlot, parentItemId: null } : item)
      : items.map((item) => item.id === itemId ? { ...item, loadoutSlot: null } : item);
    await patchItemState(itemId, { loadoutSlot }, optimisticItems);
  }

  async function dropItem(item: InventoryItem) {
    if (!canManage) return;
    await requestInventoryChange(`/api/inventory/items/${item.id}?quantity=${Math.max(quantityStepForItem(item), dropQuantity)}`, { method: 'DELETE' });
  }

  async function sendToHouse(item: InventoryItem) {
    if (!canManage || !character.ownerUserId) return;
    await requestInventoryChange(`/api/inventory/items/${item.id}/send-house`, { method: 'POST' });
  }

  async function consumePotion(item: InventoryItem, confirmDropFlask = false) {
    if (!canManage || !isPotionConsumable(item)) return;
    setSaving(true);
    setError('');
    try {
      const response = await fetch(`/api/inventory/items/${item.id}/consume`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ confirmDropFlask })
      });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.error ?? 'Potion could not be consumed.');
      if (payload.needsFlaskDropConfirmation) {
        setSaving(false);
        const confirmed = window.confirm(payload.message ?? 'No open inventory slot for the Empty Flask. Drink it anyway and drop the flask?');
        if (confirmed) await consumePotion(item, true);
        return;
      }
      const normalized = normalizeCharacterInventoryPayload(payload.inventory ?? {});
      setItems(normalized.items);
      onItemsChanged?.(normalized.items);
      setWallet(normalized.wallet);
      setWalletDraft(Object.fromEntries(normalized.wallet.map((entry) => [entry.unit.id, entry.amount])));
      const effect = payload.effect && typeof payload.effect === 'object' ? payload.effect as Record<string, unknown> : null;
      const newValue = Number(effect?.newValue);
      if (effect?.type === 'health' && Number.isFinite(newValue)) onResourceChanged?.({ currentHp: newValue });
      if (effect?.type === 'mana' && Number.isFinite(newValue)) onResourceChanged?.({ currentMana: newValue });
      setModal(null);
    } catch (consumeError) {
      setError(consumeError instanceof Error ? consumeError.message : 'Potion could not be consumed.');
    } finally {
      setSaving(false);
    }
  }

  async function saveWallet() {
    if (!canAdd) return;
    setSaving(true);
    setError('');
    try {
      const response = await fetch(`/api/characters/${character.id}/wallet`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          balances: wallet.map((entry) => ({
            unitId: entry.unit.id,
            amount: Math.max(0, walletDraft[entry.unit.id] ?? 0)
          }))
        })
      });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.error ?? 'Wallet could not be saved.');
      const normalized = normalizeCharacterInventoryPayload(payload);
      setWallet(normalized.wallet);
      setWalletDraft(Object.fromEntries(normalized.wallet.map((entry) => [entry.unit.id, entry.amount])));
    } catch (walletError) {
      setError(walletError instanceof Error ? walletError.message : 'Wallet could not be saved.');
    } finally {
      setSaving(false);
    }
  }

  function renderItemDraftControls() {
    const modifierList = modifierEntries(draft.modifiers);
    const showLoadoutDetails = itemSupportsLoadoutDetails(draft.type) || Boolean(draft.material.trim()) || Boolean(draft.enchantment.trim()) || draft.enhancementCount > 0 || modifierList.length > 0;
    const enchantable = canManuallyEnchant(draft) || Boolean(draft.enchantment.trim());
    const enhanceable = canManuallyEnhance(draft);
    const legendaryWeapon = draft.type === 'weapon' && draft.rarity === 'Legendary';
    const hasCurrentCustomSpell = Boolean(draft.enchantment.trim()) && !sortedSpells.some((spell) => spell.name === draft.enchantment);

    return (
      <>
        <TextField placeholder="Item name" value={draft.name} onChange={(event) => setDraft({ ...draft, name: event.target.value })} />
        <div className="grid gap-2 sm:grid-cols-3">
          <SelectField value={draft.type} onChange={(event) => setDraft({ ...draft, type: event.target.value as ItemType })}>{ITEM_TYPES.map((type) => <option key={type} value={type}>{type}</option>)}</SelectField>
          <SelectField value={draft.rarity} onChange={(event) => setDraft({ ...draft, rarity: event.target.value as ItemRarity })}>{rarityOptions.map((rarity) => <option key={rarity} value={rarity}>{rarity}</option>)}</SelectField>
          <NumberInput min={quantityStepForItem(draft)} step={quantityStepForItem(draft)} value={draft.quantity} onValueChange={(quantity) => setDraft({ ...draft, quantity })} />
        </div>
        {draft.type === 'storage' && <NumberInput aria-label="Storage capacity" min={1} value={draft.storageCapacity || 6} onValueChange={(storageCapacity) => setDraft({ ...draft, storageCapacity })} />}

        {legendaryWeapon && (
          <details className="rounded-2xl border border-[var(--brass)]/40 bg-[var(--brass)]/10">
            <summary className="cursor-pointer list-none p-3 font-black text-[var(--brass)]">Legendary weapon details</summary>
            <div className="grid gap-3 border-t border-[var(--line)] p-3">
              <TextAreaField
                rows={4}
                value={draft.itemDescription}
                onChange={(event) => setDraft({ ...draft, itemDescription: event.target.value })}
                placeholder="Inspection description for this legendary weapon"
              />
              <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
                {EDITABLE_MODIFIER_FIELDS.map((field) => (
                  <label key={field.key}>
                    <span className="mb-1 block text-[10px] font-black uppercase text-[var(--muted)]">{field.label}</span>
                    <NumberInput value={Number(draft.modifiers[field.key] ?? 0)} onValueChange={(value) => updateDraftModifier(field.key, value)} />
                  </label>
                ))}
              </div>
            </div>
          </details>
        )}

        {draft.type === 'potion' && !isEmptyFlask(draft) && !isArcaneNector(draft) && (
          <div className="grid gap-2 rounded-2xl border border-[#56e2c2]/30 bg-[#56e2c2]/10 p-3">
            <p className="eyebrow text-[#56e2c2]">Potion details</p>
            <div className="grid gap-2 sm:grid-cols-3">
              <SelectField value={draft.potionStrength} onChange={(event) => setDraft({ ...draft, potionStrength: event.target.value })}>
                <option value="">Infer strength</option>
                {POTION_STRENGTHS.map((strength) => <option key={strength} value={strength}>{strength}</option>)}
              </SelectField>
              <SelectField value={draft.potionProperty} onChange={(event) => setDraft({ ...draft, potionProperty: event.target.value, potionQuality: event.target.value === 'Healing' || event.target.value === 'Mana Regen' ? '' : draft.potionQuality })}>
                <option value="">Infer property</option>
                {POTION_PROPERTIES.map((property) => <option key={property.key} value={property.key}>{property.label}</option>)}
              </SelectField>
              {potionQualityCanApply(draft) ? (
                <SelectField value={draft.potionQuality} onChange={(event) => setDraft({ ...draft, potionQuality: event.target.value })}>
                  <option value="">No quality</option>
                  {POTION_QUALITIES.map((quality) => <option key={quality} value={quality}>{quality}</option>)}
                </SelectField>
              ) : (
                <div className="rounded-xl border border-[var(--line)] bg-black/15 px-3 py-3 text-sm font-black text-[var(--muted)]">
                  No quality
                </div>
              )}
            </div>
          </div>
        )}

        {showLoadoutDetails && (
          <div className="grid gap-2 rounded-2xl border border-[var(--line)] bg-black/10 p-3">
            <p className="eyebrow">Equipment details</p>
            <div className="grid gap-2 sm:grid-cols-2">
              <TextField placeholder="Material, e.g. Mythril" value={draft.material} onChange={(event) => setDraft({ ...draft, material: event.target.value })} />
              {draft.type === 'weapon' && (
                <label className="flex min-h-12 items-center gap-2 rounded-xl border border-[var(--line)] bg-black/15 px-3 text-sm font-black">
                  <input type="checkbox" checked={draft.isTwoHanded} onChange={(event) => setDraft({ ...draft, isTwoHanded: event.target.checked })} />
                  Two-handed weapon
                </label>
              )}
            </div>
          </div>
        )}

        {enchantable && (
          <div className="grid gap-2 rounded-2xl border border-[#56e2c2]/35 bg-[#56e2c2]/10 p-3">
            <div>
              <p className="eyebrow text-[#56e2c2]">Enchantment</p>
              <p className="mt-1 text-xs leading-5 text-[var(--muted)]">Mythril weapons can carry one spell. Confirming an enhancement removes it.</p>
            </div>
            <SelectField value={draft.enchantment} disabled={draft.enhancementCount > 0} onChange={(event) => updateDraftEnchantment(event.target.value)}>
              <option value="">No enchantment</option>
              {hasCurrentCustomSpell && <option value={draft.enchantment}>{draft.enchantment}</option>}
              {sortedSpells.map((spell) => <option key={spell.id} value={spell.name}>{spell.name} · {spellManaText(spell)}</option>)}
            </SelectField>
            {draft.enhancementCount > 0 && <p className="text-xs font-black text-[var(--red)]">Remove enhancements before adding an enchantment.</p>}
          </div>
        )}

        {enhanceable && (
          <div className="grid gap-2 rounded-2xl border border-[var(--brass)]/35 bg-[var(--brass)]/10 p-3">
            <div>
              <p className="eyebrow">Manual enhancement</p>
              <p className="mt-1 text-xs leading-5 text-[var(--muted)]">{draft.enhancementCount}/3 enhancements used. Each confirm adds +1 to the chosen stat.</p>
            </div>
            {modifierList.length > 0 && (
              <div className="flex flex-wrap gap-1.5">
                {modifierList.map((modifier) => (
                  <span key={modifier.key} className={`rounded-full bg-black/35 px-2 py-1 text-[10px] font-black uppercase ${modifierToneClass(modifier.value)}`}>
                    {modifierText(modifier.value)} {modifier.label}
                  </span>
                ))}
              </div>
            )}
            {draft.enhancementCount >= 3 ? (
              <p className="rounded-xl border border-[var(--line)] bg-black/15 p-3 text-sm font-black text-[var(--muted)]">Enhancement limit reached.</p>
            ) : enhanceOpen ? (
              <div className="grid gap-2 rounded-xl border border-[var(--line)] bg-black/15 p-3">
                <SelectField value={enhanceStat} onChange={(event) => setEnhanceStat(event.target.value as LoadoutModifierKey)}>
                  {EDITABLE_MODIFIER_FIELDS.map((field) => <option key={field.key} value={field.key}>{field.label}</option>)}
                </SelectField>
                {draft.enchantment && <p className="text-xs font-black text-[var(--red)]">Confirming removes {draft.enchantment} from this item.</p>}
                <div className="grid grid-cols-2 gap-2">
                  <Button type="button" variant="secondary" onClick={() => setEnhanceOpen(false)}>Cancel</Button>
                  <Button type="button" variant="teal" onClick={confirmDraftEnhancement}>Confirm +1</Button>
                </div>
              </div>
            ) : (
              <Button type="button" variant="teal" onClick={() => setEnhanceOpen(true)}>Enhance</Button>
            )}
          </div>
        )}

        {!enhanceable && modifierList.length > 0 && (
          <div className="rounded-2xl border border-[var(--line)] bg-black/10 p-3">
            <p className="eyebrow">Loadout modifiers</p>
            <div className="mt-2 flex flex-wrap gap-1.5">
              {modifierList.map((modifier) => (
                <span key={modifier.key} className={`rounded-full bg-black/35 px-2 py-1 text-[10px] font-black uppercase ${modifierToneClass(modifier.value)}`}>
                  {modifierText(modifier.value)} {modifier.label}
                </span>
              ))}
            </div>
          </div>
        )}
      </>
    );
  }

  return (
    <Card>
      <div className="mb-4 flex items-center justify-between gap-3">
        <div>
          <p className="eyebrow">Possessions</p>
          <h3 className="mt-1 text-xl font-black">Inventory & Loadout</h3>
        </div>
        <Button variant="secondary" className="p-3" onClick={loadInventory} aria-label="Refresh inventory">
          <RefreshCw size={16} />
        </Button>
      </div>

      {error && <div className="mb-3 rounded-2xl border border-[var(--red)]/40 bg-[var(--red)]/10 p-3 text-sm text-[var(--red)]">{error}</div>}

      {loading ? (
        <div className="grid h-32 place-items-center rounded-2xl border border-[var(--line)] bg-black/10 text-[var(--muted)]">
          <Loader2 className="animate-spin" />
        </div>
      ) : (
        <>
          <section className="mb-5">
            <div className="rule-title mb-3"><h3 className="text-sm font-black uppercase tracking-wider">Wallet</h3></div>
            <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
              {wallet.map((entry) => (
                <label key={entry.unit.id} className="rounded-xl border border-[var(--line)] bg-black/15 p-3">
                  <span className="text-[10px] font-black uppercase tracking-wide text-[var(--muted)]">{entry.unit.name}</span>
                  {canAdd ? (
                    <NumberInput min={0} value={walletDraft[entry.unit.id] ?? 0} onValueChange={(amount) => setWalletDraft({ ...walletDraft, [entry.unit.id]: amount })} className="mt-2" />
                  ) : (
                    <span className="mt-1 block text-lg font-black text-[var(--paper)]">{entry.amount}</span>
                  )}
                </label>
              ))}
            </div>
            {canAdd && <Button variant="teal" className="mt-2" onClick={saveWallet} disabled={saving}>Save wallet</Button>}
          </section>

          <LoadoutPanel items={items} spells={spells} canMove={canManage} onOpen={(item) => openSlot(item.slotIndex, item.parentItemId, item)} onEquip={equipItem} />

          <div className="mt-5 rule-title mb-3"><h3 className="text-sm font-black uppercase tracking-wider">Inventory</h3></div>
          <div className="inventory-grid grid grid-cols-2 gap-2 min-[430px]:grid-cols-3 sm:grid-cols-4 lg:grid-cols-6">
            {Array.from({ length: character.inventorySlots }, (_, slot) => {
              const item = itemByMainSlot.get(slot);
              return (
                <InventorySlot
                  key={slot}
                  slot={slot}
                  item={item}
                  canEdit={canManage}
                  canAdd={canAdd}
                  target={target === `main:${slot}`}
                  onOpen={() => openSlot(slot, null, item)}
                  onDropItem={(itemId) => moveItem(itemId, slot, null)}
                />
              );
            })}
          </div>

          {storageItems.length > 0 && (
            <div className="mt-5 space-y-2">
              <div className="rule-title mb-3"><h3 className="text-sm font-black uppercase tracking-wider">Additional Storage</h3></div>
              {storageItems.map((storage) => {
                const childItems = items.filter((item) => sameContainer(item, storage.id));
                const childBySlot = new Map(childItems.map((item) => [item.slotIndex, item]));
                return (
                  <details key={storage.id} className="rounded-2xl border border-[#d1a85b2f] bg-black/15">
                    <summary className="flex cursor-pointer list-none items-center justify-between gap-3 p-3">
                      <span className="flex items-center gap-2 font-black"><PackageOpen size={16} className="text-[var(--brass)]" /> {storage.name}</span>
                      <span className="text-xs text-[var(--muted)]">{childItems.length}/{storage.storageCapacity} slots</span>
                    </summary>
                    <div className="flex justify-end border-t border-[var(--line)] px-3 py-2">
                      <Button variant="secondary" className="px-3 py-2 text-xs" onClick={() => openSlot(storage.slotIndex, storage.parentItemId, storage)}>Inspect storage</Button>
                    </div>
                    <div className="inventory-grid grid grid-cols-2 gap-2 border-t border-[var(--line)] p-3 min-[430px]:grid-cols-3 sm:grid-cols-4 lg:grid-cols-5">
                      {Array.from({ length: storage.storageCapacity }, (_, slot) => {
                        const item = childBySlot.get(slot);
                        return (
                          <InventorySlot
                            key={slot}
                            slot={slot}
                            item={item}
                            canEdit={canManage}
                            canAdd={canAdd}
                            target={target === `${storage.id}:${slot}`}
                            onOpen={() => openSlot(slot, storage.id, item)}
                            onDropItem={(itemId) => moveItem(itemId, slot, storage.id)}
                          />
                        );
                      })}
                    </div>
                  </details>
                );
              })}
            </div>
          )}

          {nearbyWagons.length > 0 && (
            <div className="mt-5 space-y-2">
              <div className="rule-title mb-3"><h3 className="text-sm font-black uppercase tracking-wider">Nearby Wagons</h3></div>
              {nearbyWagons.map(({ wagon, ownerName }) => {
                const childItems = nearbyWagonItems.filter((item) => item.parentItemId === wagon.id);
                const childBySlot = new Map(childItems.map((item) => [item.slotIndex, item]));
                return (
                  <details key={wagon.id} className="rounded-2xl border border-[#56e2c24a] bg-black/15">
                    <summary className="flex cursor-pointer list-none items-center justify-between gap-3 p-3">
                      <span className="flex min-w-0 items-center gap-2 font-black">
                        <PackageOpen size={16} className="shrink-0 text-[#56e2c2]" />
                        <span className="truncate">{wagon.displayName || wagon.name}</span>
                      </span>
                      <span className="shrink-0 text-xs text-[var(--muted)]">{ownerName}; {childItems.length}/{wagon.storageCapacity} slots</span>
                    </summary>
                    <div className="inventory-grid grid grid-cols-2 gap-2 border-t border-[var(--line)] p-3 min-[430px]:grid-cols-3 sm:grid-cols-4 lg:grid-cols-5">
                      {Array.from({ length: wagon.storageCapacity }, (_, slot) => {
                        const item = childBySlot.get(slot);
                        return (
                          <InventorySlot
                            key={slot}
                            slot={slot}
                            item={item}
                            canEdit={canManage}
                            canAdd={false}
                            target={target === `${wagon.id}:${slot}`}
                            onOpen={() => setModal({ slot, parentItemId: wagon.id, item, source: 'wagon', wagonId: wagon.id })}
                            onDropItem={(itemId) => moveItemToWagon(itemId, wagon.id, slot)}
                          />
                        );
                      })}
                    </div>
                  </details>
                );
              })}
            </div>
          )}
        </>
      )}

      {modal && (
        <Modal title={modal.item ? (modal.item.displayName || modal.item.name) : 'Add item'} onClose={() => setModal(null)}>
          {modal.item ? (
            <div className="space-y-3">
              <div className={`rarity-card rounded-2xl border p-3 ${rarityClass(modal.item.rarity)} ${modal.item.enchantment ? 'inventory-enchanted' : ''} ${itemHasEnhancementVisual(modal.item) ? 'inventory-enhanced' : ''}`}>
                <div className="relative z-10 flex items-start gap-3">
                  <span className="grid h-11 w-11 shrink-0 place-items-center rounded-xl bg-black/25 text-[var(--brass)]"><ItemIcon type={modal.item.type} size={22} /></span>
                  <div className="min-w-0 flex-1">
                    <p className="text-lg font-black leading-5">{modal.item.displayName || modal.item.name}</p>
                    <p className="mt-1 text-xs font-black uppercase tracking-wider text-[var(--muted)]">{modal.item.type} · {modal.item.rarity} · Quantity {modal.item.quantity}</p>
                    {modal.item.itemDescription && <p className="mt-3 whitespace-pre-line text-sm leading-6 text-[var(--paper)]">{modal.item.itemDescription}</p>}
                    {modal.item.type === 'pet' && (
                      <p className="mt-1 text-xs font-black uppercase tracking-wider text-[var(--brass)]">Animal: {modal.item.name}</p>
                    )}
                    {modal.item.material && <p className="mt-1 text-xs text-[var(--muted)]">Material: {modal.item.material}</p>}
                    {modal.item.enhancementCount > 0 && <p className="mt-1 text-xs font-black text-[var(--brass)]">{modal.item.enhancementCount}/3 enhancements</p>}
                    {modal.item.runeName && <p className="mt-1 text-xs font-black uppercase tracking-wider text-[#56e2c2]">Rune: {modal.item.runeName}</p>}
                    {modal.item.enchantment && (
                      <div className="mt-3 rounded-xl border border-[#56e2c2]/30 bg-[#56e2c2]/10 p-3">
                        <p className="text-xs font-black uppercase tracking-wider text-[#56e2c2]">Enchantment: {modalSpell?.name ?? modal.item.enchantment}</p>
                        {modalSpell ? (
                          <div className="mt-1 space-y-1 text-xs leading-5 text-[var(--paper)]">
                            <p><span className="font-black">Mana:</span> {spellManaText(modalSpell)}</p>
                            <p>{modalSpell.details || modalSpell.summary || 'No spell description entered yet.'}</p>
                          </div>
                        ) : (
                          <p className="mt-1 text-xs leading-5 text-[var(--muted)]">Spell details were not found in the global spell list.</p>
                        )}
                      </div>
                    )}
                    {modifierEntries(modal.item.modifiers).length > 0 && (
                      <div className="mt-3 flex flex-wrap gap-1.5">
                        {modifierEntries(modal.item.modifiers).map((modifier) => (
                          <span key={modifier.key} className={`rounded-full bg-black/35 px-2 py-1 text-[10px] font-black uppercase ${modifierToneClass(modifier.value)}`}>
                            {modifierText(modifier.value)} {modifier.label}
                          </span>
                        ))}
                      </div>
                    )}
                  </div>
                </div>
              </div>
              {modal.source === 'wagon' && canManage && (
                <div className="grid gap-2 rounded-2xl border border-[#56e2c2]/30 bg-[#56e2c2]/10 p-3">
                  <p className="text-xs font-black uppercase tracking-wider text-[#56e2c2]">Shared wagon storage</p>
                  <Button variant="teal" disabled={saving} onClick={() => takeFromWagon(modal.item!.id)}>Take to first open inventory slot</Button>
                </div>
              )}
              {modal.source !== 'wagon' && canManage && modal.item.type === 'pet' && (
                <form onSubmit={savePetDisplayName} className="grid gap-2 rounded-2xl border border-[var(--line)] bg-black/10 p-3">
                  <label>
                    <span className="mb-1 block text-[10px] font-black uppercase text-[var(--muted)]">Pet display name</span>
                    <TextField
                      placeholder={modal.item.name}
                      value={draft.displayName}
                      onChange={(event) => setDraft({ ...draft, displayName: event.target.value })}
                    />
                  </label>
                  <Button variant="secondary" disabled={saving}>Save pet name</Button>
                </form>
              )}
              {modal.source !== 'wagon' && canManage && canApplyRune(modal.item) && (
                <div className="grid gap-2 rounded-2xl border border-[#56e2c2]/30 bg-[#56e2c2]/10 p-3">
                  <div>
                    <p className="text-xs font-black uppercase tracking-wider text-[#56e2c2]">Apply rune</p>
                    <p className="mt-1 text-xs leading-5 text-[var(--muted)]">
                      Adds a visible rune mark to this Mythril item. It does not change stats.
                    </p>
                  </div>
                  {runeLoading ? (
                    <div className="grid h-12 place-items-center rounded-xl border border-[var(--line)] bg-black/10 text-[var(--muted)]"><Loader2 className="animate-spin" size={16} /></div>
                  ) : availableRunes.length ? (
                    <div className="grid gap-2 sm:grid-cols-2">
                      {availableRunes.map((rune) => (
                        <Button
                          key={`${rune.source}:${rune.item.id}`}
                          variant="secondary"
                          className="justify-start px-3 py-2 text-left text-xs"
                          disabled={saving}
                          onClick={() => applyRune(rune)}
                        >
                          {rune.item.name} x{rune.item.quantity} · {rune.source === 'house' ? 'House' : 'Inventory'}
                        </Button>
                      ))}
                    </div>
                  ) : (
                    <p className="rounded-xl border border-[var(--line)] bg-black/10 p-3 text-xs text-[var(--muted)]">
                      No runes available.
                    </p>
                  )}
                  {runeError && <p className="text-xs font-black text-[var(--red)]">{runeError}</p>}
                </div>
              )}
              {modal.source !== 'wagon' && canManage && (
                <div className="grid gap-2">
                  {!modal.item.loadoutSlot && (
                    <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
                      {(['weapon', 'armor', 'shield', 'active-pet', 'accessory-1', 'accessory-2', 'accessory-3', 'accessory-4'] as LoadoutSlot[])
                        .filter((slot) => acceptsLoadoutItem(slot, modal.item!.type))
                        .map((slot) => <Button key={slot} variant="secondary" onClick={() => equipItem(modal.item!.id, slot)}>Equip {slot.replace('-', ' ')}</Button>)}
                    </div>
                  )}
                  {modal.item.loadoutSlot && <Button variant="secondary" onClick={() => equipItem(modal.item!.id, null)}>Unequip to first open slot</Button>}
                  {isPotionConsumable(modal.item) && <Button variant="teal" onClick={() => consumePotion(modal.item!)} disabled={saving}>Consume</Button>}
                  {character.ownerUserId && <Button variant="secondary" onClick={() => sendToHouse(modal.item!)}>Send to house</Button>}
                  <div className="grid gap-2 sm:grid-cols-[1fr_auto]">
                    <NumberInput min={quantityStepForItem(modal.item)} step={quantityStepForItem(modal.item)} max={modal.item.quantity} value={dropQuantity} onValueChange={setDropQuantity} />
                    <Button variant="danger" onClick={() => dropItem(modal.item!)} disabled={saving}>Drop</Button>
                  </div>
                </div>
              )}
              {modal.source !== 'wagon' && canAdd && (
                <form onSubmit={updateItem} className="grid gap-3 rounded-2xl border border-[var(--line)] bg-black/10 p-3">
                  {renderItemDraftControls()}
                  <Button variant="primary" className="sticky bottom-0 z-20 shadow-[0_-14px_28px_rgba(10,4,1,.55)]" disabled={!draft.name.trim() || saving}>Save item</Button>
                </form>
              )}
            </div>
          ) : (
            <form onSubmit={addItem} className="grid gap-3">
              <div className="grid grid-cols-2 gap-2 rounded-2xl border border-[var(--line)] bg-black/15 p-1">
                <Button type="button" variant={addMode === 'catalog' ? 'primary' : 'ghost'} className="py-2" onClick={() => setAddMode('catalog')}>Catalog</Button>
                <Button type="button" variant={addMode === 'custom' ? 'primary' : 'ghost'} className="py-2" onClick={() => setAddMode('custom')}>Custom</Button>
              </div>

              {addMode === 'catalog' && (
                <div className="grid gap-3">
                  <label className="relative block">
                    <Search className="pointer-events-none absolute left-4 top-1/2 -translate-y-1/2 text-[var(--muted)]" size={17} />
                    <TextField
                      placeholder="Search loot catalog"
                      value={catalogSearch}
                      onChange={(event) => setCatalogSearch(event.target.value)}
                      className="catalog-search-input"
                    />
                  </label>
                  <div className="catalog-picker thin-scrollbar grid max-h-[46dvh] gap-3 overflow-y-auto rounded-2xl border border-[var(--line)] bg-black/10 p-3">
                    {catalogLoading ? (
                      <div className="grid h-24 place-items-center rounded-2xl border border-[var(--line)] bg-black/10 text-[var(--muted)]">
                        <Loader2 className="animate-spin" />
                      </div>
                    ) : filteredCatalog.length ? filteredCatalog.map((item) => (
                      <button
                        type="button"
                        key={item.id}
                        onClick={() => chooseCatalogItem(item)}
                        data-rarity={item.rarity}
                        data-selected={draft.name === item.name && draft.rarity === item.rarity && draft.type === item.type}
                        className="catalog-item text-left transition active:scale-[0.99]"
                      >
                        <span className="catalog-item-inner">
                          <span className="catalog-item-icon"><ItemIcon type={item.type} size={20} /></span>
                          <span className="catalog-item-copy">
                            <span className="catalog-item-title">{item.name}</span>
                            <span className="catalog-item-meta">{item.rarity} · {item.type}</span>
                          </span>
                        </span>
                      </button>
                    )) : (
                      <div className="rounded-2xl border border-[var(--line)] bg-black/10 p-4 text-sm text-[var(--muted)]">
                        No catalog items found.
                      </div>
                    )}
                  </div>
                </div>
              )}

              {renderItemDraftControls()}
              <Button variant="primary" className="sticky bottom-0 z-20 shadow-[0_-14px_28px_rgba(10,4,1,.55)]" disabled={!draft.name.trim() || saving}>Add item</Button>
            </form>
          )}
        </Modal>
      )}
    </Card>
  );
}
