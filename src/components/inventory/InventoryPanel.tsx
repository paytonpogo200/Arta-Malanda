'use client';

import { useCallback, useEffect, useMemo, useRef, useState, type FormEvent } from 'react';
import { ArrowRightLeft, Gift, Loader2, PackageOpen, RefreshCw, Scissors, Search, Trash2 } from 'lucide-react';
import { ItemIcon } from '@/components/inventory/ItemIcon';
import { EMPTY_ITEM_DRAFT, ItemEditorFields, draftFromInventoryItem, itemDraftPayload, type ItemDraft } from '@/components/inventory/ItemEditorFields';
import { InventorySlot } from '@/components/inventory/InventorySlot';
import { LoadoutPanel } from '@/components/inventory/LoadoutPanel';
import { Button } from '@/components/ui/Button';
import { Card } from '@/components/ui/Card';
import { SelectField, TextField } from '@/components/ui/Field';
import { Modal } from '@/components/ui/Modal';
import { NumberInput } from '@/components/ui/NumberInput';
import { normalizeUpdateAssetsPayload } from '@/features/assets/data';
import { activeAttributeValue, calculateCharacterSheetStats } from '@/features/characters/stats';
import { normalizeHousePayload } from '@/features/houses/data';
import { acceptsLoadoutItem, normalizeCharacterInventoryPayload, normalizeInventoryItem, quantityStepForItem } from '@/features/inventory/data';
import { normalizeWagonPayload, type WagonActivity, type WagonStorage } from '@/features/inventory/wagons';
import { useDragAutoScroll } from '@/hooks/useDragAutoScroll';
import { useLiveRefresh } from '@/hooks/useLiveRefresh';
import {
  canApplyRune,
  cleanModifiers,
  itemHasEnhancementVisual,
  modifierEntries,
  modifierText,
  modifierToneClass,
  spellForEnchantment
} from '@/features/inventory/itemDetails';
import { rarityClass } from '@/lib/utils/rarity';
import { potionEffectText } from '@/lib/utils/potions';
import { spellManaText } from '@/lib/utils/spells';
import { signed } from '@/lib/utils/format';
import { ATTRIBUTE_KEYS, ATTRIBUTE_LABELS, type Character, type ClassTemplate, type InventoryItem, type ItemCatalogEntry, type LoadoutModifierKey, type LoadoutSlot, type Spell, type WalletBalance } from '@/lib/types';

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

type ItemActionModal = null | 'transfer' | 'gift' | 'trade' | 'drop' | 'split';

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

function normalizedItemName(name: string) {
  const clean = name.trim().toLowerCase();
  if (clean === 'glass flask' || clean === 'glass flasks' || clean === 'empty flasks') return 'empty flask';
  if (clean === 'mana recovery potion') return 'mana potion';
  return clean;
}

function isEmptyFlask(item: Pick<InventoryItem, 'name'> | Pick<ItemDraft, 'name'>) {
  return normalizedItemName(item.name) === 'empty flask';
}

function isPotionConsumable(item: InventoryItem) {
  return item.type === 'potion' && !isEmptyFlask(item);
}

function isWagonStorage(item: Pick<InventoryItem, 'name' | 'isStorage'>) {
  return item.isStorage && item.name.toLowerCase().includes('wagon');
}

function quantityText(quantity: number) {
  return Number.isInteger(quantity) ? quantity.toString() : quantity.toFixed(1);
}

function clampQuantity(value: number, min: number, max: number) {
  if (!Number.isFinite(value)) return min;
  return Math.min(max, Math.max(min, value));
}

function statToneClass(value: number) {
  if (value > 0) return 'text-[var(--teal)]';
  if (value < 0) return 'text-[var(--red)]';
  return 'text-[var(--paper)]';
}

export function InventoryPanel({
  character,
  canManage,
  canAdd,
  refreshSignal = 0,
  tradeCharacters,
  showBattleStats = false,
  classTemplate,
  onItemsChanged,
  onResourceChanged
}: {
  character: Character;
  canManage: boolean;
  canAdd: boolean;
  refreshSignal?: number;
  tradeCharacters?: Character[];
  showBattleStats?: boolean;
  classTemplate?: ClassTemplate;
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
  const [draft, setDraft] = useState<ItemDraft>(EMPTY_ITEM_DRAFT);
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
  const [nearbyWagonActivity, setNearbyWagonActivity] = useState<WagonActivity[]>([]);
  const [runeLoading, setRuneLoading] = useState(false);
  const [runeError, setRuneError] = useState('');
  const [notice, setNotice] = useState('');
  const [tradeTargetId, setTradeTargetId] = useState('');
  const [tradeQuantity, setTradeQuantity] = useState(1);
  const [tradeMessage, setTradeMessage] = useState('');
  const [itemActionModal, setItemActionModal] = useState<ItemActionModal>(null);
  const [splitQuantity, setSplitQuantity] = useState(1);
  const [offerCurrencyDraft, setOfferCurrencyDraft] = useState<Record<string, number>>({});
  const [requestCurrencyDraft, setRequestCurrencyDraft] = useState<Record<string, number>>({});
  const [requestItemId, setRequestItemId] = useState('');
  const [requestQuantity, setRequestQuantity] = useState(1);
  const [targetPreview, setTargetPreview] = useState<{ items: InventoryItem[]; wallet: WalletBalance[] } | null>(null);
  const [targetPreviewLoading, setTargetPreviewLoading] = useState(false);
  const [targetPreviewError, setTargetPreviewError] = useState('');
  const [giftOpen, setGiftOpen] = useState(character.giftInventoryOpen);
  const inventoryLoadedRef = useRef(false);
  const loadedCharacterIdRef = useRef(character.id);
  useDragAutoScroll();

  const loadWagons = useCallback(async () => {
    if (!canManage && !canAdd) {
      setNearbyWagons([]);
      setNearbyWagonItems([]);
      setNearbyWagonActivity([]);
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
      setNearbyWagonActivity(normalized.activity.filter((entry) => sharedWagonIds.has(entry.wagonId)));
    } catch {
      setNearbyWagons([]);
      setNearbyWagonItems([]);
      setNearbyWagonActivity([]);
    }
  }, [canAdd, canManage, character.id]);

  const loadInventory = useCallback(async (showLoading = true) => {
    if (showLoading) setLoading(true);
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
      inventoryLoadedRef.current = true;
      if (showLoading) setLoading(false);
    }
  }, [character.id, onItemsChanged]);

  useEffect(() => {
    if (loadedCharacterIdRef.current === character.id) return;
    loadedCharacterIdRef.current = character.id;
    inventoryLoadedRef.current = false;
    setItems([]);
    setWallet([]);
    setLoading(true);
  }, [character.id]);

  useLiveRefresh(['inventory', 'house', 'wagon', 'characters', 'trades'], () => {
    void loadInventory(false);
    void loadWagons();
  });

  useEffect(() => {
    void loadInventory(!inventoryLoadedRef.current);
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
  const modalPotionEffect = useMemo(() => modal?.item ? potionEffectText(modal.item) : '', [modal]);
  const sortedSpells = useMemo(() => [...spells].sort((a, b) => a.name.localeCompare(b.name)), [spells]);
  const availableRunes = useMemo<AvailableRune[]>(() => {
    if (!modal?.item || !canApplyRune(modal.item)) return [];
    const inventoryRunes = items
      .filter((item) => item.type === 'rune' && item.quantity > 0)
      .map((item) => ({ source: 'inventory' as const, item }));
    const homeRunes = houseRunes.map((item) => ({ source: 'house' as const, item }));
    return [...inventoryRunes, ...homeRunes].sort((a, b) => a.item.name.localeCompare(b.item.name) || a.source.localeCompare(b.source));
  }, [houseRunes, items, modal?.item]);
  const tradeTargets = useMemo(() => (tradeCharacters ?? [])
    .filter((entry) => entry.id !== character.id && Boolean(entry.ownerUserId))
    .sort((a, b) => a.name.localeCompare(b.name)), [character.id, tradeCharacters]);
  const tradeTargetCharacter = useMemo(() => tradeTargets.find((entry) => entry.id === tradeTargetId) ?? null, [tradeTargetId, tradeTargets]);
  const targetPreviewItems = useMemo(() => (targetPreview?.items ?? [])
    .filter((item) => !item.isStorage && !item.loadoutSlot && item.quantity > 0)
    .sort((a, b) => (a.slotIndex - b.slotIndex) || a.name.localeCompare(b.name)), [targetPreview]);
  const requestedItem = useMemo(() => targetPreviewItems.find((item) => item.id === requestItemId) ?? null, [requestItemId, targetPreviewItems]);
  const battleStats = useMemo(() => calculateCharacterSheetStats(character, items, classTemplate), [character, classTemplate, items]);
  const attributeRows = useMemo(() => ATTRIBUTE_KEYS.map((key) => ({
    key,
    label: ATTRIBUTE_LABELS[key],
    value: activeAttributeValue(character, items, key)
  })), [character, items]);

  useEffect(() => {
    setTradeTargetId((current) => tradeTargets.some((entry) => entry.id === current) ? current : tradeTargets[0]?.id ?? '');
  }, [tradeTargets]);

  useEffect(() => {
    setGiftOpen(character.giftInventoryOpen);
  }, [character.giftInventoryOpen, character.id]);

  const loadTradePreview = useCallback(async (targetCharacterId: string) => {
    if (!targetCharacterId) {
      setTargetPreview(null);
      return;
    }
    setTargetPreviewLoading(true);
    setTargetPreviewError('');
    try {
      const response = await fetch(`/api/characters/${targetCharacterId}/trade-preview`, { cache: 'no-store' });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.error ?? 'Trade inventory could not be loaded.');
      const normalized = normalizeCharacterInventoryPayload(payload);
      setTargetPreview(normalized);
      const firstItem = normalized.items.find((item) => !item.isStorage && !item.loadoutSlot && item.quantity > 0);
      setRequestItemId((current) => normalized.items.some((item) => item.id === current) ? current : firstItem?.id ?? '');
      setRequestQuantity(firstItem ? quantityStepForItem(firstItem) : 1);
    } catch (previewError) {
      setTargetPreview(null);
      setTargetPreviewError(previewError instanceof Error ? previewError.message : 'Trade inventory could not be loaded.');
    } finally {
      setTargetPreviewLoading(false);
    }
  }, []);

  useEffect(() => {
    if (itemActionModal !== 'trade' || !tradeTargetId) return;
    void loadTradePreview(tradeTargetId);
  }, [itemActionModal, loadTradePreview, tradeTargetId]);

  function openSlot(slot: number, parentItemId: string | null, item?: InventoryItem) {
    if (!item && !canAdd) return;
    setModal({ slot, parentItemId, item });
    setDraft(item ? draftFromInventoryItem(item) : EMPTY_ITEM_DRAFT);
    setDropQuantity(item?.quantity ?? 1);
    setCatalogSearch('');
    setAddMode(item ? 'custom' : 'catalog');
    setEnhanceOpen(false);
    setEnhanceStat('strength');
    setNotice('');
    const step = item ? quantityStepForItem(item) : 1;
    setTradeQuantity(step);
    setSplitQuantity(step);
    setTradeMessage('');
    setItemActionModal(null);
    setOfferCurrencyDraft({});
    setRequestCurrencyDraft({});
    setRequestItemId('');
    setRequestQuantity(1);
    setTargetPreview(null);
    setTargetPreviewError('');
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
      isAccessory: false,
      modifiers: cleanModifiers(item.defaultModifiers),
      potionStrength: '',
      potionProperty: '',
      potionQuality: ''
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
      await loadInventory(false);
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
        await loadInventory(false);
        setItems((current) => {
          const next = current.filter((item) => item.id !== itemId);
          onItemsChanged?.(next);
          return next;
        });
        setModal((current) => current?.item?.id === itemId ? null : current);
        return;
      }
      setModal((current) => current?.item?.id === updated.id ? { ...current, item: updated } : current);
      await loadInventory(false);
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
        ...itemDraftPayload(draft),
        parentItemId: modal.parentItemId,
        slotIndex: modal.slot
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
        ...itemDraftPayload({
          ...draft,
          quantity: Math.max(quantityStepForItem(draft), draft.quantity)
        })
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
      await loadInventory(false);
      const normalized = normalizeWagonPayload(payload);
      const sharedWagons = normalized.wagons.filter((entry) => entry.ownerCharacterId !== character.id);
      const sharedWagonIds = new Set(sharedWagons.map((entry) => entry.wagon.id));
      setNearbyWagons(sharedWagons);
      setNearbyWagonItems(normalized.items.filter((item) => item.parentItemId && sharedWagonIds.has(item.parentItemId)));
      setNearbyWagonActivity(normalized.activity.filter((entry) => sharedWagonIds.has(entry.wagonId)));
      setModal(null);
    } catch (actionError) {
      setError(actionError instanceof Error ? actionError.message : 'Item could not be moved into the wagon.');
      await loadInventory(false);
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

  async function splitItemStack(item: InventoryItem, confirmDrop = false) {
    if (!canManage || !item.stackable || item.quantity <= quantityStepForItem(item)) return;
    const step = quantityStepForItem(item);
    const maxSplit = Math.max(step, item.quantity - step);
    const quantity = clampQuantity(splitQuantity, step, maxSplit);
    setSaving(true);
    setError('');
    setNotice('');
    try {
      const response = await fetch(`/api/inventory/items/${item.id}/split`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ quantity, confirmDrop })
      });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.error ?? 'Stack could not be split.');
      if (payload.needsDropConfirmation) {
        setSaving(false);
        const confirmed = window.confirm(payload.message ?? 'No open inventory slot. Split anyway and drop the new stack?');
        if (confirmed) await splitItemStack(item, true);
        return;
      }
      const normalized = normalizeCharacterInventoryPayload(payload.inventory ?? {});
      setItems(normalized.items);
      onItemsChanged?.(normalized.items);
      setWallet(normalized.wallet);
      setWalletDraft(Object.fromEntries(normalized.wallet.map((entry) => [entry.unit.id, entry.amount])));
      setModal(null);
      setNotice(payload.droppedQuantity ? `${quantityText(Number(payload.droppedQuantity))} ${item.name} split off and dropped.` : 'Stack split into the closest open slot.');
    } catch (splitError) {
      setError(splitError instanceof Error ? splitError.message : 'Stack could not be split.');
    } finally {
      setSaving(false);
    }
  }

  async function sendToHouse(item: InventoryItem) {
    if (!canManage || !character.ownerUserId) return;
    await requestInventoryChange(`/api/inventory/items/${item.id}/send-house`, { method: 'POST' });
  }

  async function sendItemTrade(item: InventoryItem) {
    if (!canManage || !tradeTargetId || item.loadoutSlot || item.isStorage) return;
    setSaving(true);
    setError('');
    setNotice('');
    try {
      const quantity = Math.min(item.quantity, Math.max(quantityStepForItem(item), tradeQuantity));
      const requested = requestedItem
        ? `${quantityText(Math.min(requestedItem.quantity, Math.max(quantityStepForItem(requestedItem), requestQuantity)))} ${requestedItem.displayName || requestedItem.name}`
        : '';
      const offeredCurrency = wallet
        .map((entry) => ({ unitId: entry.unit.id, amount: Math.floor(clampQuantity(offerCurrencyDraft[entry.unit.id] ?? 0, 0, entry.amount)) }))
        .filter((entry) => entry.amount > 0);
      const requestedCurrency = (targetPreview?.wallet ?? [])
        .map((entry) => ({ unitId: entry.unit.id, amount: Math.floor(clampQuantity(requestCurrencyDraft[entry.unit.id] ?? 0, 0, entry.amount)) }))
        .filter((entry) => entry.amount > 0);
      const offeredCurrencyText = offeredCurrency
        .map((entry) => {
          const unit = wallet.find((balance) => balance.unit.id === entry.unitId)?.unit;
          return unit ? `${entry.amount} ${unit.name}` : '';
        })
        .filter(Boolean)
        .join(' + ');
      const requestedCurrencyText = requestedCurrency
        .map((entry) => {
          const unit = targetPreview?.wallet.find((balance) => balance.unit.id === entry.unitId)?.unit;
          return unit ? `${entry.amount} ${unit.name}` : '';
        })
        .filter(Boolean)
        .join(' + ');
      const wantedParts = [requested, requestedCurrencyText].filter(Boolean);
      const offeredParts = [`${quantityText(quantity)} ${item.displayName || item.name}`, offeredCurrencyText].filter(Boolean);
      const response = await fetch('/api/trades', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          senderCharacterId: character.id,
          targetCharacterId: tradeTargetId,
          offeredItemId: item.id,
          offeredQuantity: quantity,
          offerNote: offeredParts.join(' + '),
          requestNote: wantedParts.length ? wantedParts.join(' + ') : 'Table-negotiated return',
          message: tradeMessage,
          requestedItemId: requestedItem?.id ?? null,
          requestedQuantity: requestedItem ? Math.min(requestedItem.quantity, Math.max(quantityStepForItem(requestedItem), requestQuantity)) : 1,
          offeredCurrency,
          requestedCurrency
        })
      });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.error ?? 'Trade offer could not be sent.');
      setNotice('Trade request sent. The other player will see it in notifications.');
      setTradeMessage('');
      setItemActionModal(null);
    } catch (tradeError) {
      setError(tradeError instanceof Error ? tradeError.message : 'Trade offer could not be sent.');
    } finally {
      setSaving(false);
    }
  }

  async function giftItem(item: InventoryItem) {
    if (!canManage || !tradeTargetId || item.loadoutSlot || item.isStorage) return;
    const targetCharacter = tradeTargetCharacter;
    if (!targetCharacter) return;
    if (targetCharacter.ownerUserId !== character.ownerUserId && !targetCharacter.giftInventoryOpen) {
      window.alert('This persons inventory is closed from gifting efforts and grows tired of your pranks');
      return;
    }

    setSaving(true);
    setError('');
    setNotice('');
    try {
      const quantity = Math.min(item.quantity, Math.max(quantityStepForItem(item), tradeQuantity));
      const response = await fetch(`/api/inventory/items/${item.id}/gift`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          targetCharacterId: targetCharacter.id,
          quantity
        })
      });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.error ?? 'Gift could not be delivered.');
      const normalized = normalizeCharacterInventoryPayload(payload.inventory ?? {});
      setItems(normalized.items);
      onItemsChanged?.(normalized.items);
      setWallet(normalized.wallet);
      setWalletDraft(Object.fromEntries(normalized.wallet.map((entry) => [entry.unit.id, entry.amount])));
      setModal(null);
      setNotice(`Gift delivered to ${targetCharacter.name}.`);
      setItemActionModal(null);
    } catch (giftError) {
      const message = giftError instanceof Error ? giftError.message : 'Gift could not be delivered.';
      setError(message);
      if (message.includes('gifting efforts')) window.alert(message);
    } finally {
      setSaving(false);
    }
  }

  async function toggleGiftInventoryOpen() {
    if (!canManage) return;
    const nextOpen = !giftOpen;
    setGiftOpen(nextOpen);
    setError('');
    setNotice('');
    try {
      const response = await fetch(`/api/characters/${character.id}/gifting`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ open: nextOpen })
      });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.error ?? 'Gift access could not be changed.');
      setGiftOpen(Boolean(payload.character?.giftInventoryOpen));
    } catch (giftError) {
      setGiftOpen(!nextOpen);
      setError(giftError instanceof Error ? giftError.message : 'Gift access could not be changed.');
    }
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
    return (
      <ItemEditorFields
        draft={draft}
        spells={sortedSpells}
        quantityStep={quantityStepForItem(draft)}
        enhanceOpen={enhanceOpen}
        enhanceStat={enhanceStat}
        onDraftChange={setDraft}
        onEnhanceOpenChange={setEnhanceOpen}
        onEnhanceStatChange={setEnhanceStat}
      />
    );
  }

  function renderTargetSelect() {
    return (
      <SelectField
        value={tradeTargetId}
        onChange={(event) => {
          setTradeTargetId(event.target.value);
          setRequestItemId('');
          setTargetPreview(null);
        }}
      >
        {tradeTargets.map((target) => (
          <option key={target.id} value={target.id}>
            {target.name}{target.ownerUserId === character.ownerUserId ? ' - your character' : target.giftInventoryOpen ? ' - gifts open' : ' - gifts closed'}
          </option>
        ))}
      </SelectField>
    );
  }

  function renderQuantityRange(value: number, min: number, max: number, step: number, onChange: (value: number) => void) {
    return (
      <div className="grid gap-2">
        <input
          type="range"
          min={min}
          max={max}
          step={step}
          value={clampQuantity(value, min, max)}
          onChange={(event) => onChange(clampQuantity(Number(event.target.value), min, max))}
          className="w-full accent-[var(--brass)]"
        />
        <NumberInput min={min} max={max} step={step} value={clampQuantity(value, min, max)} onValueChange={(next) => onChange(clampQuantity(next, min, max))} />
      </div>
    );
  }

  function renderCurrencyInputs(
    balances: WalletBalance[],
    draftValues: Record<string, number>,
    onChange: (values: Record<string, number>) => void
  ) {
    if (!balances.length) return null;
    return (
      <div className="grid gap-2 sm:grid-cols-2">
        {balances.map((entry) => (
          <label key={entry.unit.id} className="rounded-xl border border-[var(--line)] bg-black/15 p-3">
            <span className="mb-1 block text-[10px] font-black uppercase text-[var(--muted)]">{entry.unit.name} available {entry.amount}</span>
            <NumberInput
              min={0}
              max={entry.amount}
              step={1}
              value={Math.floor(clampQuantity(draftValues[entry.unit.id] ?? 0, 0, entry.amount))}
              onValueChange={(amount) => onChange({ ...draftValues, [entry.unit.id]: Math.floor(clampQuantity(amount, 0, entry.amount)) })}
            />
          </label>
        ))}
      </div>
    );
  }

  function renderItemActionModal() {
    if (!modal?.item || !itemActionModal) return null;
    const item = modal.item;
    const step = quantityStepForItem(item);
    const maxQuantity = Math.max(step, item.quantity);
    const maxSplit = Math.max(step, item.quantity - step);
    const splitAmount = clampQuantity(splitQuantity, step, maxSplit);

    if (itemActionModal === 'transfer') {
      return (
        <Modal title="Gift or trade" onClose={() => setItemActionModal(null)}>
          <div className="grid gap-3">
            <div className="rounded-2xl border border-[var(--line)] bg-black/10 p-3">
              <p className="text-xs font-black uppercase tracking-wider text-[var(--muted)]">Selected item</p>
              <p className="mt-1 text-lg font-black">{item.displayName || item.name}</p>
              <p className="text-xs text-[var(--muted)]">Quantity {quantityText(item.quantity)}</p>
            </div>
            <div className="grid gap-2 sm:grid-cols-2">
              <Button variant="teal" onClick={() => setItemActionModal('gift')}>
                <Gift className="mr-2 inline" size={15} />
                Gift
              </Button>
              <Button variant="secondary" onClick={() => setItemActionModal('trade')}>
                <ArrowRightLeft className="mr-2 inline" size={15} />
                Trade request
              </Button>
            </div>
          </div>
        </Modal>
      );
    }

    if (itemActionModal === 'gift') {
      return (
        <Modal title="Gift item" onClose={() => setItemActionModal(null)}>
          <div className="grid gap-3">
            <label className="grid gap-1">
              <span className="text-[10px] font-black uppercase text-[var(--muted)]">Recipient</span>
              {renderTargetSelect()}
            </label>
            {tradeTargetCharacter && tradeTargetCharacter.ownerUserId !== character.ownerUserId && !tradeTargetCharacter.giftInventoryOpen && (
              <p className="rounded-xl border border-[var(--red)]/35 bg-[var(--red)]/10 p-3 text-xs font-black text-[var(--red)]">
                This character is closed to gifts.
              </p>
            )}
            <label className="grid gap-2">
              <span className="text-[10px] font-black uppercase text-[var(--muted)]">Quantity</span>
              {renderQuantityRange(tradeQuantity, step, maxQuantity, step, setTradeQuantity)}
            </label>
            <Button variant="teal" onClick={() => giftItem(item)} disabled={!tradeTargetId || saving}>
              <Gift className="mr-2 inline" size={15} />
              {tradeTargetCharacter?.ownerUserId === character.ownerUserId ? 'Move now' : 'Gift now'}
            </Button>
          </div>
        </Modal>
      );
    }

    if (itemActionModal === 'trade') {
      return (
        <Modal title="Trade request" onClose={() => setItemActionModal(null)}>
          <div className="grid gap-4">
            <label className="grid gap-1">
              <span className="text-[10px] font-black uppercase text-[var(--muted)]">Trade with</span>
              {renderTargetSelect()}
            </label>
            <section className="grid gap-3 rounded-2xl border border-[#56e2c2]/30 bg-[#56e2c2]/10 p-3">
              <p className="text-xs font-black uppercase tracking-wider text-[#56e2c2]">You give</p>
              <div>
                <p className="font-black">{item.displayName || item.name}</p>
                <p className="text-xs text-[var(--muted)]">Available {quantityText(item.quantity)}</p>
              </div>
              {renderQuantityRange(tradeQuantity, step, maxQuantity, step, setTradeQuantity)}
              {renderCurrencyInputs(wallet, offerCurrencyDraft, setOfferCurrencyDraft)}
            </section>
            <section className="grid gap-3 rounded-2xl border border-[var(--line)] bg-black/10 p-3">
              <div>
                <p className="text-xs font-black uppercase tracking-wider text-[var(--brass)]">You want</p>
                <p className="text-xs text-[var(--muted)]">Pick from their visible inventory and add money if needed.</p>
              </div>
              {targetPreviewLoading ? (
                <div className="grid h-20 place-items-center rounded-xl border border-[var(--line)] bg-black/10 text-[var(--muted)]"><Loader2 className="animate-spin" size={16} /></div>
              ) : targetPreviewError ? (
                <p className="rounded-xl border border-[var(--red)]/35 bg-[var(--red)]/10 p-3 text-xs font-black text-[var(--red)]">{targetPreviewError}</p>
              ) : (
                <>
                  {targetPreviewItems.length > 0 ? (
                    <div className="thin-scrollbar grid max-h-64 gap-2 overflow-y-auto pr-1">
                      {targetPreviewItems.map((previewItem) => (
                        <button
                          key={previewItem.id}
                          type="button"
                          onClick={() => {
                            setRequestItemId(previewItem.id);
                            setRequestQuantity(quantityStepForItem(previewItem));
                          }}
                          className={`rounded-xl border p-3 text-left transition ${requestItemId === previewItem.id ? 'border-[var(--brass)] bg-[var(--brass)]/15' : 'border-[var(--line)] bg-black/15'}`}
                        >
                          <span className="block font-black">{previewItem.displayName || previewItem.name}</span>
                          <span className="text-xs text-[var(--muted)]">{previewItem.rarity} - {previewItem.type} - Qty {quantityText(previewItem.quantity)}</span>
                        </button>
                      ))}
                    </div>
                  ) : (
                    <p className="rounded-xl border border-[var(--line)] bg-black/10 p-3 text-xs text-[var(--muted)]">No tradeable items visible in that inventory.</p>
                  )}
                  {requestedItem && renderQuantityRange(requestQuantity, quantityStepForItem(requestedItem), requestedItem.quantity, quantityStepForItem(requestedItem), setRequestQuantity)}
                  {renderCurrencyInputs(targetPreview?.wallet ?? [], requestCurrencyDraft, setRequestCurrencyDraft)}
                </>
              )}
            </section>
            <TextField value={tradeMessage} onChange={(event) => setTradeMessage(event.target.value)} placeholder="Optional note for the trade notification" />
            <Button variant="teal" onClick={() => sendItemTrade(item)} disabled={!tradeTargetId || saving}>
              <ArrowRightLeft className="mr-2 inline" size={15} />
              Send trade request
            </Button>
          </div>
        </Modal>
      );
    }

    if (itemActionModal === 'split') {
      return (
        <Modal title="Split stack" onClose={() => setItemActionModal(null)}>
          <div className="grid gap-3">
            <div className="grid grid-cols-2 gap-2">
              <div className="rounded-xl border border-[var(--line)] bg-black/15 p-3">
                <p className="text-[10px] font-black uppercase text-[var(--muted)]">Original keeps</p>
                <p className="mt-1 text-xl font-black">{quantityText(item.quantity - splitAmount)}</p>
              </div>
              <div className="rounded-xl border border-[var(--brass)]/45 bg-[var(--brass)]/10 p-3">
                <p className="text-[10px] font-black uppercase text-[var(--muted)]">New stack gets</p>
                <p className="mt-1 text-xl font-black">{quantityText(splitAmount)}</p>
              </div>
            </div>
            {renderQuantityRange(splitQuantity, step, maxSplit, step, setSplitQuantity)}
            <Button variant="teal" onClick={() => splitItemStack(item)} disabled={saving}>Split stack</Button>
          </div>
        </Modal>
      );
    }

    return (
      <Modal title="Drop item" onClose={() => setItemActionModal(null)}>
        <div className="grid gap-3">
          <div className="rounded-2xl border border-[var(--line)] bg-black/10 p-3">
            <p className="font-black">{item.displayName || item.name}</p>
            <p className="text-xs text-[var(--muted)]">Available {quantityText(item.quantity)}</p>
          </div>
          {renderQuantityRange(dropQuantity, step, maxQuantity, step, setDropQuantity)}
          <Button variant="danger" onClick={() => dropItem(item)} disabled={saving}>
            <Trash2 className="mr-2 inline" size={15} />
            Drop {quantityText(clampQuantity(dropQuantity, step, maxQuantity))}
          </Button>
        </div>
      </Modal>
    );
  }

  return (
    <Card>
      <div className="mb-4 flex items-center justify-between gap-3">
        <div>
          <p className="eyebrow">Possessions</p>
          <h3 className="mt-1 text-xl font-black">Inventory & Loadout</h3>
        </div>
        <Button variant="secondary" className="p-3" onClick={() => void loadInventory()} aria-label="Refresh inventory">
          <RefreshCw size={16} />
        </Button>
      </div>

      {error && <div className="mb-3 rounded-2xl border border-[var(--red)]/40 bg-[var(--red)]/10 p-3 text-sm text-[var(--red)]">{error}</div>}
      {notice && <div className="mb-3 rounded-2xl border border-[#56e2c2]/40 bg-[#56e2c2]/10 p-3 text-sm text-[#56e2c2]">{notice}</div>}

      {loading ? (
        <div className="grid h-32 place-items-center rounded-2xl border border-[var(--line)] bg-black/10 text-[var(--muted)]">
          <Loader2 className="animate-spin" />
        </div>
      ) : (
        <>
          {showBattleStats ? (
            <section className="mb-5 space-y-4">
              <div>
                <div className="rule-title mb-3"><h3 className="text-sm font-black uppercase tracking-wider">Combat Stats</h3></div>
                <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
                  <div className="rounded-xl border border-[var(--line)] bg-black/15 p-3">
                    <span className="text-[10px] font-black uppercase tracking-wide text-[var(--muted)]">Max HP</span>
                    <span className="mt-1 block text-lg font-black text-[var(--paper)]">{battleStats.maxHp}</span>
                  </div>
                  <div className="rounded-xl border border-[var(--line)] bg-black/15 p-3">
                    <span className="text-[10px] font-black uppercase tracking-wide text-[var(--muted)]">Max Mana</span>
                    <span className="mt-1 block text-lg font-black text-[var(--paper)]">{battleStats.maxMana}</span>
                  </div>
                  <div className="rounded-xl border border-[var(--line)] bg-black/15 p-3">
                    <span className="text-[10px] font-black uppercase tracking-wide text-[var(--muted)]">Defense</span>
                    <span className="mt-1 block text-lg font-black text-[var(--paper)]">{battleStats.defense}</span>
                  </div>
                  <div className="rounded-xl border border-[var(--line)] bg-black/15 p-3">
                    <span className="text-[10px] font-black uppercase tracking-wide text-[var(--muted)]">Magic Resist</span>
                    <span className="mt-1 block text-lg font-black text-[var(--paper)]">{battleStats.magicResist}</span>
                  </div>
                </div>
              </div>
              <div>
                <div className="rule-title mb-3"><h3 className="text-sm font-black uppercase tracking-wider">Attributes & Skills</h3></div>
                <div className="grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-4">
                  {attributeRows.map((entry) => (
                    <div key={entry.key} className="rounded-xl border border-[var(--line)] bg-black/15 p-3">
                      <p className="text-[10px] font-black uppercase tracking-wide text-[var(--muted)]">{entry.label}</p>
                      <p className={`mt-1 text-lg font-black ${statToneClass(entry.value)}`}>{signed(entry.value)}</p>
                    </div>
                  ))}
                </div>
              </div>
            </section>
          ) : (
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
          )}

          <LoadoutPanel items={items} spells={spells} canMove={canManage} onOpen={(item) => openSlot(item.slotIndex, item.parentItemId, item)} onEquip={equipItem} />

          <div className="mt-5 mb-3 flex flex-wrap items-center justify-between gap-2">
            <div className="rule-title min-w-0 flex-1"><h3 className="text-sm font-black uppercase tracking-wider">Inventory</h3></div>
            {canManage && (
              <Button
                variant={giftOpen ? 'teal' : 'secondary'}
                className="px-3 py-2 text-xs"
                onClick={toggleGiftInventoryOpen}
                disabled={saving}
              >
                <Gift className="mr-2 inline" size={14} />
                {giftOpen ? 'Open to gifts' : 'Closed to gifts'}
              </Button>
            )}
          </div>
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
                      <span className="flex shrink-0 flex-wrap justify-end gap-1.5 text-xs text-[var(--muted)]">
                        {isWagonStorage(storage) && <span className="rounded-full border border-[#56e2c2]/35 bg-[#56e2c2]/10 px-2 py-1 font-black uppercase text-[#56e2c2]">Shared at {character.locationName || 'current location'}</span>}
                        <span>{childItems.length}/{storage.storageCapacity} slots</span>
                      </span>
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
              {nearbyWagons.map(({ wagon, ownerName, locationName }) => {
                const childItems = nearbyWagonItems.filter((item) => item.parentItemId === wagon.id);
                const childBySlot = new Map(childItems.map((item) => [item.slotIndex, item]));
                const activity = nearbyWagonActivity.filter((entry) => entry.wagonId === wagon.id).slice(0, 4);
                return (
                  <details key={wagon.id} className="rounded-2xl border border-[#56e2c24a] bg-black/15">
                    <summary className="flex cursor-pointer list-none items-center justify-between gap-3 p-3">
                      <span className="flex min-w-0 items-center gap-2 font-black">
                        <PackageOpen size={16} className="shrink-0 text-[#56e2c2]" />
                        <span className="truncate">{wagon.displayName || wagon.name}</span>
                      </span>
                      <span className="flex shrink-0 flex-wrap justify-end gap-1.5 text-xs text-[var(--muted)]">
                        <span className="rounded-full border border-[#56e2c2]/35 bg-[#56e2c2]/10 px-2 py-1 font-black uppercase text-[#56e2c2]">Owner {ownerName}</span>
                        <span className="rounded-full border border-[var(--line)] bg-black/20 px-2 py-1 font-black uppercase">{locationName || character.locationName || 'Nearby'}</span>
                        <span className="px-1 py-1">{childItems.length}/{wagon.storageCapacity} slots</span>
                      </span>
                    </summary>
                    <div className="grid gap-1 border-t border-[var(--line)] px-3 py-2 text-xs text-[var(--muted)]">
                      {activity.length ? activity.map((entry) => (
                        <p key={entry.id}>
                          <span className="font-black text-[var(--paper)]">{entry.actorName}</span> {entry.action === 'stored' ? 'stored' : 'took'} {quantityText(entry.quantity)} {entry.itemName}
                        </p>
                      )) : (
                        <p>No wagon activity recorded yet.</p>
                      )}
                    </div>
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
        <Modal title={modal.item ? (modal.item.displayName || modal.item.name) : 'Add item'} onClose={() => {
          setItemActionModal(null);
          setModal(null);
        }}>
          {modal.item ? (
            <div className="space-y-3">
              <div className={`rarity-card rounded-2xl border p-3 ${rarityClass(modal.item.rarity)} ${modal.item.enchantment ? 'inventory-enchanted' : ''} ${itemHasEnhancementVisual(modal.item) ? 'inventory-enhanced' : ''}`}>
                <div className="relative z-10 flex items-start gap-3">
                  <span className="grid h-11 w-11 shrink-0 place-items-center rounded-xl bg-black/25 text-[var(--brass)]"><ItemIcon type={modal.item.type} size={22} /></span>
                  <div className="min-w-0 flex-1">
                    <p className="text-lg font-black leading-5">{modal.item.displayName || modal.item.name}</p>
                    <p className="mt-1 text-xs font-black uppercase tracking-wider text-[var(--muted)]">{modal.item.type} · {modal.item.rarity} · Quantity {modal.item.quantity}</p>
                    {modal.item.itemDescription && <p className="mt-3 whitespace-pre-line text-sm leading-6 text-[var(--paper)]">{modal.item.itemDescription}</p>}
                    {modalPotionEffect && (
                      <div className="mt-3 rounded-xl border border-[#56e2c2]/30 bg-[#56e2c2]/10 p-3 text-sm leading-6 text-[var(--paper)]">
                        <p className="text-xs font-black uppercase tracking-wider text-[#56e2c2]">Potion effect</p>
                        <p className="mt-1">{modalPotionEffect}</p>
                      </div>
                    )}
                    {modal.item.type === 'pet' && (
                      <p className="mt-1 text-xs font-black uppercase tracking-wider text-[var(--brass)]">Animal: {modal.item.name}</p>
                    )}
                    {modal.item.isAccessory && (
                      <p className="mt-1 text-xs font-black uppercase tracking-wider text-[var(--brass)]">Accessory</p>
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
                        .filter((slot) => acceptsLoadoutItem(slot, modal.item!.type, modal.item!.isAccessory))
                        .map((slot) => <Button key={slot} variant="secondary" onClick={() => equipItem(modal.item!.id, slot)}>Equip {slot.replace('-', ' ')}</Button>)}
                    </div>
                  )}
                  {modal.item.loadoutSlot && <Button variant="secondary" onClick={() => equipItem(modal.item!.id, null)}>Unequip to first open slot</Button>}
                  {isPotionConsumable(modal.item) && <Button variant="teal" onClick={() => consumePotion(modal.item!)} disabled={saving}>Consume</Button>}
                  {character.ownerUserId && <Button variant="secondary" onClick={() => sendToHouse(modal.item!)}>Send to house</Button>}
                  {tradeTargets.length > 0 && !modal.item.loadoutSlot && !modal.item.isStorage && (
                    <Button variant="teal" onClick={() => setItemActionModal('transfer')} disabled={saving}>
                      <ArrowRightLeft className="mr-2 inline" size={15} />
                      Gift or trade
                    </Button>
                  )}
                  {tradeTargets.length > 0 && modal.item.loadoutSlot && (
                    <p className="rounded-xl border border-[var(--line)] bg-black/10 p-3 text-xs text-[var(--muted)]">Unequip this item before offering it to another player.</p>
                  )}
                  {tradeTargets.length > 0 && modal.item.isStorage && (
                    <p className="rounded-xl border border-[var(--line)] bg-black/10 p-3 text-xs text-[var(--muted)]">Storage containers cannot be offered through trades.</p>
                  )}
                  {modal.item.stackable && modal.item.quantity > quantityStepForItem(modal.item) && (
                    <Button variant="secondary" onClick={() => setItemActionModal('split')} disabled={saving}>
                      <Scissors className="mr-2 inline" size={15} />
                      Split stack
                    </Button>
                  )}
                  <Button variant="danger" onClick={() => setItemActionModal('drop')} disabled={saving}>
                    <Trash2 className="mr-2 inline" size={15} />
                    Drop item
                  </Button>
                </div>
              )}
              {modal.source !== 'wagon' && canAdd && (
                <form onSubmit={updateItem} className="grid gap-3 rounded-2xl border border-[var(--line)] bg-black/10 p-3 pb-[calc(5.5rem+env(safe-area-inset-bottom))] sm:pb-3">
                  {renderItemDraftControls()}
                  <Button variant="primary" className="sticky bottom-[calc(4.75rem+env(safe-area-inset-bottom))] z-20 shadow-[0_-14px_28px_rgba(10,4,1,.55)] sm:bottom-0" disabled={!draft.name.trim() || saving}>Save item</Button>
                </form>
              )}
            </div>
          ) : (
            <form onSubmit={addItem} className="grid gap-3 pb-[calc(5.5rem+env(safe-area-inset-bottom))] sm:pb-3">
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
              <Button variant="primary" className="sticky bottom-[calc(4.75rem+env(safe-area-inset-bottom))] z-20 shadow-[0_-14px_28px_rgba(10,4,1,.55)] sm:bottom-0" disabled={!draft.name.trim() || saving}>Add item</Button>
            </form>
          )}
        </Modal>
      )}
      {renderItemActionModal()}
    </Card>
  );
}
