'use client';

import { useCallback, useEffect, useMemo, useState, type FormEvent } from 'react';
import { ChevronDown, ChevronUp, Home, Loader2, Lock, PawPrint, Plus, RefreshCw, Settings, Trash2, Unlock, Users } from 'lucide-react';
import { EMPTY_ITEM_DRAFT, ItemEditorFields, draftFromInventoryItem, itemDraftPayload, type ItemDraft } from '@/components/inventory/ItemEditorFields';
import { InventorySlot } from '@/components/inventory/InventorySlot';
import { Button } from '@/components/ui/Button';
import { Card } from '@/components/ui/Card';
import { SelectField, TextField } from '@/components/ui/Field';
import { Modal } from '@/components/ui/Modal';
import { NumberInput } from '@/components/ui/NumberInput';
import { normalizeUpdateAssetsPayload } from '@/features/assets/data';
import type { CampaignProfile } from '@/features/characters/data';
import { normalizeCitiesPayload } from '@/features/cities/data';
import { normalizeHousePayload, PROPERTY_LOCATIONS, PROPERTY_TYPES } from '@/features/houses/data';
import { quantityStepForItem } from '@/features/inventory/data';
import { useDragAutoScroll } from '@/hooks/useDragAutoScroll';
import { useLiveRefresh } from '@/hooks/useLiveRefresh';
import type { CampaignProperty, Character, House, InventoryItem, LoadoutModifierKey, PropertyLocation, PropertyType, ShopVendor, Spell } from '@/lib/types';

type HousePanelProps = {
  ownerUserId: string | null;
  caretakerCharacterId: string;
  viewerUserId: string;
  profiles?: CampaignProfile[];
  characters?: Character[];
  canManage: boolean;
  canAdd: boolean;
  onCharacterInventoryChanged?: () => void;
};

function sameContainer(item: InventoryItem, parentItemId: string | null) {
  return (item.parentItemId ?? null) === parentItemId && item.loadoutSlot === null;
}

type PropertyDraft = {
  name: string;
  type: PropertyType;
  location: PropertyLocation;
  isPet: boolean;
  slotIndex: number;
  storageCapacity: number;
};

const EMPTY_PROPERTY: PropertyDraft = {
  name: '',
  type: 'animal',
  location: 'at_house',
  isPet: false,
  slotIndex: 0,
  storageCapacity: 0
};

const STABLE_SLOT_OFFSET = 1000;

type HouseSettingsDraft = {
  kind: 'house' | 'stable';
  name: string;
  stableName: string;
  cityName: string;
  inventorySlots: number;
  stableSlots: number;
  propertySlots: number;
  locked: boolean;
  isMain: boolean;
};

export function HousePanel({ ownerUserId, caretakerCharacterId, viewerUserId, profiles = [], characters = [], canManage, canAdd, onCharacterInventoryChanged }: HousePanelProps) {
  const [items, setItems] = useState<InventoryItem[]>([]);
  const [homes, setHomes] = useState<House[]>([]);
  const [selectedHomeKey, setSelectedHomeKey] = useState('');
  const [properties, setProperties] = useState<CampaignProperty[]>([]);
  const [houseAccess, setHouseAccess] = useState({ owner: false, dm: false, house: false, stable: false });
  const [permissions, setPermissions] = useState<Record<string, { house: boolean; stable: boolean }>>({});
  const [permissionsOpen, setPermissionsOpen] = useState(false);
  const [inventorySlots, setInventorySlots] = useState(45);
  const [stableSlots, setStableSlots] = useState(5);
  const [propertySlots, setPropertySlots] = useState(10);
  const [houseName, setHouseName] = useState('House');
  const [stableName, setStableName] = useState('Stable');
  const [houseCityName, setHouseCityName] = useState('Wild');
  const [houseLocked, setHouseLocked] = useState(false);
  const [houseSettingsOpen, setHouseSettingsOpen] = useState(false);
  const [creatingHome, setCreatingHome] = useState(false);
  const [houseSettingsDraft, setHouseSettingsDraft] = useState<HouseSettingsDraft>({
    kind: 'house',
    name: 'House',
    stableName: 'Stable',
    cityName: 'Wild',
    inventorySlots: 45,
    stableSlots: 5,
    propertySlots: 10,
    locked: false,
    isMain: false
  });
  const [cityOptions, setCityOptions] = useState<string[]>(['Wild']);
  const [availableStables, setAvailableStables] = useState<ShopVendor[]>([]);
  const [loading, setLoading] = useState(Boolean(ownerUserId));
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [targetSlot, setTargetSlot] = useState<string | null>(null);
  const [itemModal, setItemModal] = useState<{ slot: number; parentItemId: string | null; item?: InventoryItem } | null>(null);
  const [propertyModal, setPropertyModal] = useState<CampaignProperty | 'new' | null>(null);
  const [itemDraft, setItemDraft] = useState<ItemDraft>(EMPTY_ITEM_DRAFT);
  const [propertyDraft, setPropertyDraft] = useState<PropertyDraft>(EMPTY_PROPERTY);
  const [dropQuantity, setDropQuantity] = useState(1);
  const [spells, setSpells] = useState<Spell[]>([]);
  const [enhanceOpen, setEnhanceOpen] = useState(false);
  const [enhanceStat, setEnhanceStat] = useState<LoadoutModifierKey>('strength');
  const [takeTargetCharacterId, setTakeTargetCharacterId] = useState(caretakerCharacterId);
  const [homeKind, setHomeKind] = useState<'house' | 'stable' | 'wagon-home' | 'caged-wagon'>('house');
  const [homeSource, setHomeSource] = useState<'static' | 'mobile'>('static');
  const [homeIsMain, setHomeIsMain] = useState(false);
  const [homeStorageItemId, setHomeStorageItemId] = useState<string | null>(null);
  const [homeStorageCharacterId, setHomeStorageCharacterId] = useState<string | null>(null);
  const [stableStorageItemId, setStableStorageItemId] = useState<string | null>(null);
  const [stableStorageCharacterId, setStableStorageCharacterId] = useState<string | null>(null);
  const [homeAvailable, setHomeAvailable] = useState(false);
  useDragAutoScroll();

  const isWagonHome = homeKind === 'wagon-home' && Boolean(homeStorageItemId);
  const isCagedWagonOnly = homeKind === 'caged-wagon' && Boolean(homeStorageItemId);
  const rootParentItemId = isWagonHome ? homeStorageItemId : null;
  const stableParentItemId = isCagedWagonOnly ? homeStorageItemId : stableStorageItemId;
  const mobileStorageCharacterIds = useMemo(() => new Set([homeStorageCharacterId, stableStorageCharacterId].filter((entry): entry is string => Boolean(entry))), [homeStorageCharacterId, stableStorageCharacterId]);
  const isMobileItem = useCallback((item: InventoryItem) => Boolean(item.characterId && mobileStorageCharacterIds.has(item.characterId)), [mobileStorageCharacterIds]);
  const stableItems = useMemo(() => items.filter((item) => (
    stableParentItemId
      ? sameContainer(item, stableParentItemId) && item.type === 'pet'
      : sameContainer(item, null)
        && item.type === 'pet'
        && item.slotIndex >= STABLE_SLOT_OFFSET
        && item.slotIndex < STABLE_SLOT_OFFSET + stableSlots
  )), [items, stableParentItemId, stableSlots]);
  const stableItemIds = useMemo(() => new Set(stableItems.map((item) => item.id)), [stableItems]);
  const mainItems = useMemo(() => items.filter((item) => sameContainer(item, rootParentItemId) && !item.isStorage && !stableItemIds.has(item.id)), [items, rootParentItemId, stableItemIds]);
  const itemBySlot = useMemo(() => new Map(mainItems.map((item) => [item.slotIndex, item])), [mainItems]);
  const stableItemBySlot = useMemo(() => new Map(stableItems.map((item) => [item.slotIndex, item])), [stableItems]);
  const storageItems = useMemo(() => items.filter((item) => item.isStorage && item.id !== homeStorageItemId && item.id !== stableParentItemId), [homeStorageItemId, items, stableParentItemId]);
  const canManageHouse = canManage || houseAccess.house;
  const canManageStable = canManage || houseAccess.stable;
  const canManageAny = canManageHouse || canManageStable;
  const canEditPermissions = canAdd || houseAccess.owner;
  const canCustomizeHouse = canAdd || houseAccess.owner;
  const selectedHome = useMemo(() => homes.find((home) => `${home.source}:${home.id}` === selectedHomeKey) ?? null, [homes, selectedHomeKey]);
  const permissionProfiles = useMemo(() => profiles
    .filter((entry) => entry.id !== ownerUserId)
    .sort((a, b) => (a.displayName || a.username || '').localeCompare(b.displayName || b.username || '')), [ownerUserId, profiles]);
  const takeTargetCharacters = useMemo(() => {
    const allowedOwnerIds = canAdd
      ? null
      : new Set([ownerUserId, viewerUserId].filter((entry): entry is string => Boolean(entry)));
    const assigned = characters
      .filter((entry) => !allowedOwnerIds || (entry.ownerUserId && allowedOwnerIds.has(entry.ownerUserId)))
      .sort((a, b) => a.name.localeCompare(b.name));
    if (assigned.some((entry) => entry.id === caretakerCharacterId)) return assigned;
    const caretaker = characters.find((entry) => entry.id === caretakerCharacterId);
    return caretaker ? [caretaker, ...assigned] : assigned;
  }, [canAdd, caretakerCharacterId, characters, ownerUserId, viewerUserId]);
  const caretakerCharacter = useMemo(() => characters.find((entry) => entry.id === caretakerCharacterId) ?? null, [caretakerCharacterId, characters]);

  const loadHouse = useCallback(async (showLoading = true) => {
    if (!ownerUserId) return;
    if (showLoading) setLoading(true);
    setError('');

    try {
      const [requestedSource, requestedId] = selectedHomeKey ? selectedHomeKey.split(':') : ['', ''];
      const params = new URLSearchParams();
      if (requestedId) params.set('homeId', requestedId);
      if (requestedSource) params.set('source', requestedSource);
      const response = await fetch(`/api/houses/${ownerUserId}${params.size ? `?${params.toString()}` : ''}`, { cache: 'no-store' });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.error ?? 'House could not be loaded.');
      const normalized = normalizeHousePayload(payload);
      setHomeAvailable(Boolean(normalized.house));
      setHomes(normalized.homes);
      if (normalized.house) setSelectedHomeKey(`${normalized.house.source}:${normalized.house.id}`);
      else setSelectedHomeKey('');
      setItems(normalized.items);
      setProperties(normalized.properties);
      setHouseName(normalized.house?.name ?? 'House');
      setStableName(normalized.house?.stableName ?? 'Stable');
      setHouseCityName(normalized.house?.cityName ?? 'Wild');
      setInventorySlots(normalized.house?.inventorySlots ?? 45);
      setStableSlots(normalized.house?.stableSlots ?? 5);
      setPropertySlots(normalized.house?.propertySlots ?? 10);
      setHouseLocked(Boolean(normalized.house?.locked));
      setHomeKind(normalized.house?.kind ?? 'house');
      setHomeSource(normalized.house?.source ?? 'static');
      setHomeIsMain(Boolean(normalized.house?.isMain));
      setHomeStorageItemId(normalized.house?.storageItemId ?? null);
      setHomeStorageCharacterId(normalized.house?.storageCharacterId ?? null);
      setStableStorageItemId(normalized.house?.stableStorageItemId ?? null);
      setStableStorageCharacterId(normalized.house?.stableStorageCharacterId ?? null);
      setHouseAccess(normalized.access);
      setPermissions(Object.fromEntries(normalized.permissions.map((entry) => [entry.granteeUserId, { house: entry.house, stable: entry.stable }])));
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : 'House could not be loaded.');
    } finally {
      if (showLoading) setLoading(false);
    }
  }, [ownerUserId, selectedHomeKey]);

  useEffect(() => {
    void loadHouse();
  }, [loadHouse]);

  useEffect(() => {
    let cancelled = false;
    fetch('/api/cities', { cache: 'no-store' })
      .then(async (response) => {
        const payload = await response.json().catch(() => ({}));
        if (!response.ok || cancelled) return;
        const normalized = normalizeCitiesPayload(payload);
        const cities = normalized
          .cities
          .slice()
          .sort((a, b) => a.order - b.order || a.name.localeCompare(b.name))
          .map((city) => city.name);
        setCityOptions([...cities, 'Wild'].filter((entry, index, list) => entry && list.indexOf(entry) === index));
        setAvailableStables(normalized.vendors.filter((vendor) => {
          if (vendor.blueprintType !== 'stable' || vendor.hidden) return false;
          const city = normalized.cities.find((entry) => entry.key === vendor.cityKey);
          if (!city || city.locked) return false;
          if (!caretakerCharacter) return true;
          return caretakerCharacter.locationCityKey
            ? caretakerCharacter.locationCityKey === city.key
            : caretakerCharacter.locationName === city.name;
        }));
      })
      .catch(() => {
        if (!cancelled) setCityOptions((current) => current.length ? current : ['Wild']);
      });
    return () => {
      cancelled = true;
    };
  }, [caretakerCharacter]);

  useEffect(() => {
    setTakeTargetCharacterId((current) => {
      if (takeTargetCharacters.some((entry) => entry.id === current)) return current;
      if (takeTargetCharacters.some((entry) => entry.id === caretakerCharacterId)) return caretakerCharacterId;
      return takeTargetCharacters[0]?.id ?? caretakerCharacterId;
    });
  }, [caretakerCharacterId, takeTargetCharacters]);

  useLiveRefresh(['house', 'inventory', 'wagon'], () => loadHouse(false), { enabled: Boolean(ownerUserId) });

  useEffect(() => {
    if (!canAdd) {
      setSpells([]);
      return;
    }

    let cancelled = false;
    fetch('/api/assets', { cache: 'no-store' })
      .then(async (response) => {
        const payload = await response.json().catch(() => ({}));
        if (!response.ok) return;
        if (!cancelled) {
          const normalized = normalizeUpdateAssetsPayload(payload);
          setSpells(normalized.spells.sort((a, b) => a.name.localeCompare(b.name)));
        }
      })
      .catch(() => {
        if (!cancelled) setSpells([]);
      });

    return () => {
      cancelled = true;
    };
  }, [canAdd]);

  if (!ownerUserId) {
    return null;
  }

  function openItem(slot: number, parentItemId: string | null, item?: InventoryItem) {
    if (!item && !canAdd) return;
    setItemModal({ slot, parentItemId, item });
    setItemDraft(item ? draftFromInventoryItem(item) : EMPTY_ITEM_DRAFT);
    setDropQuantity(item?.quantity ?? 1);
    setEnhanceOpen(false);
    setEnhanceStat('strength');
  }

  function openProperty(property: CampaignProperty | 'new') {
    if (property === 'new' && !canAdd) return;
    setPropertyModal(property);
    setPropertyDraft(property === 'new' ? {
      ...EMPTY_PROPERTY,
      slotIndex: Math.max(0, Math.min(properties.length, propertySlots - 1)),
      location: 'at_house'
    } : {
      name: property.name,
      type: property.type,
      location: property.location,
      isPet: property.isPet,
      slotIndex: property.slotIndex,
      storageCapacity: property.storageCapacity
    });
  }

  async function requestHouseChange(url: string, init: RequestInit) {
    setSaving(true);
    setError('');
    try {
      const response = await fetch(url, init);
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.error ?? 'House action failed.');
      setItemModal(null);
      setPropertyModal(null);
      await loadHouse(false);
      return true;
    } catch (actionError) {
      setError(actionError instanceof Error ? actionError.message : 'House action failed.');
      return false;
    } finally {
      setSaving(false);
    }
  }

  async function toggleHouseLock() {
    if (!ownerUserId || !canAdd || !selectedHome) return;
    await requestHouseChange(`/api/houses/${ownerUserId}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ homeId: selectedHome.id, source: selectedHome.source, locked: !houseLocked })
    });
  }

  async function addItem(event: FormEvent) {
    event.preventDefault();
    if (!ownerUserId || !itemModal || itemModal.item || !itemDraft.name.trim() || !canAdd) return;
    const addingToStable = itemModal.parentItemId === stableParentItemId || (itemModal.parentItemId === null && itemModal.slot >= STABLE_SLOT_OFFSET);
    if (addingToStable && itemDraft.type !== 'pet') {
      setError('Only animals can be placed in stable slots.');
      return;
    }
    if (itemDraft.type === 'pet' && !addingToStable) {
      setError('Animals can only be placed in stable slots.');
      return;
    }
    if (itemDraft.type === 'pet' && isWagonHome && !stableParentItemId) {
      setError('Animals need an active pet slot or a Caged Wagon stable.');
      return;
    }
    const parentItem = itemModal.parentItemId ? items.find((item) => item.id === itemModal.parentItemId) : null;
    const targetCharacterId = parentItem && isMobileItem(parentItem)
      ? parentItem.characterId
      : itemModal.parentItemId === stableParentItemId
      ? stableStorageCharacterId
      : itemModal.parentItemId === homeStorageItemId
        ? homeStorageCharacterId
        : null;
    await requestHouseChange(targetCharacterId ? `/api/characters/${targetCharacterId}/inventory` : `/api/houses/${ownerUserId}/items`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        ...itemDraftPayload(itemDraft),
        homeId: selectedHome?.id,
        parentItemId: itemModal.parentItemId,
        slotIndex: itemModal.slot
      })
    });
  }

  async function reorderHome(homeIndex: number, direction: -1 | 1) {
    if (!ownerUserId || !canAdd) return;
    const targetIndex = homeIndex + direction;
    if (targetIndex < 0 || targetIndex >= homes.length) return;
    const reordered = [...homes];
    [reordered[homeIndex], reordered[targetIndex]] = [reordered[targetIndex], reordered[homeIndex]];
    setSaving(true);
    setError('');
    try {
      const response = await fetch(`/api/houses/${ownerUserId}/order`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ homes: reordered.map((home) => ({ id: home.id, source: home.source })) })
      });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.error ?? 'Property order could not be saved.');
      const normalized = normalizeHousePayload(payload);
      setHomes(normalized.homes);
    } catch (orderError) {
      setError(orderError instanceof Error ? orderError.message : 'Property order could not be saved.');
      await loadHouse(false);
    } finally {
      setSaving(false);
    }
  }

  function openHouseSettings() {
    if (!selectedHome) return;
    setCreatingHome(false);
    setHouseSettingsDraft({
      kind: selectedHome.kind === 'stable' || selectedHome.kind === 'caged-wagon' ? 'stable' : 'house',
      name: houseName,
      stableName,
      cityName: houseCityName,
      inventorySlots,
      stableSlots,
      propertySlots,
      locked: houseLocked,
      isMain: homeIsMain
    });
    setHouseSettingsOpen(true);
  }

  function openCreateHome(kind: 'house' | 'stable') {
    if (!canAdd) return;
    const hasMainHouse = homes.some((home) => home.isMain && (home.kind === 'house' || home.kind === 'wagon-home'));
    setCreatingHome(true);
    setHouseSettingsDraft({
      kind,
      name: kind === 'stable' ? 'New Stable' : 'New House',
      stableName: kind === 'stable' ? 'New Stable' : 'Stable',
      cityName: caretakerCharacter?.locationName || cityOptions[0] || 'Wild',
      inventorySlots: kind === 'house' ? 45 : 0,
      stableSlots: kind === 'stable' ? 5 : 0,
      propertySlots: 0,
      locked: false,
      isMain: kind === 'house' && !hasMainHouse
    });
    setHouseSettingsOpen(true);
  }

  async function saveHouseSettings(event: FormEvent) {
    event.preventDefault();
    if (!ownerUserId || !canCustomizeHouse || (!creatingHome && !selectedHome)) return;
    await requestHouseChange(`/api/houses/${ownerUserId}`, {
      method: creatingHome ? 'POST' : 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(canAdd ? {
        ...houseSettingsDraft,
        homeId: selectedHome?.id,
        source: selectedHome?.source ?? 'static'
      } : {
        homeId: selectedHome?.id,
        source: selectedHome?.source ?? 'static',
        name: houseSettingsDraft.name,
        stableName: houseSettingsDraft.stableName,
        isMain: houseSettingsDraft.isMain
      })
    });
    setCreatingHome(false);
    setHouseSettingsOpen(false);
  }

  async function deleteHouse() {
    if (!ownerUserId || !canAdd || homeSource !== 'static' || !homeAvailable || !selectedHome) return;
    if (!window.confirm(`Delete ${homeKind === 'stable' ? stableName : houseName}? It must be empty first.`)) return;
    await requestHouseChange(`/api/houses/${ownerUserId}?homeId=${encodeURIComponent(selectedHome.id)}&source=static`, { method: 'DELETE' });
  }

  async function updateItem(event: FormEvent) {
    event.preventDefault();
    if (!itemModal?.item || !itemDraft.name.trim() || !canAdd) return;
    const editingStable = itemModal.parentItemId === stableParentItemId || (itemModal.parentItemId === null && itemModal.slot >= STABLE_SLOT_OFFSET);
    if (editingStable && itemDraft.type !== 'pet') {
      setError('Only animals can be placed in stable slots.');
      return;
    }
    if (itemDraft.type === 'pet' && !editingStable) {
      setError('Animals can only be placed in stable slots.');
      return;
    }
    if (itemDraft.type === 'pet' && isWagonHome && !stableParentItemId) {
      setError('Animals need an active pet slot or a Caged Wagon stable.');
      return;
    }
    await requestHouseChange(isMobileItem(itemModal.item) ? `/api/inventory/items/${itemModal.item.id}` : `/api/houses/items/${itemModal.item.id}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        ...itemDraftPayload({
          ...itemDraft,
          quantity: Math.max(quantityStepForItem(itemDraft), itemDraft.quantity)
        })
      })
    });
  }

  function renderItemEditor() {
    return (
      <ItemEditorFields
        draft={itemDraft}
        spells={spells}
        quantityStep={quantityStepForItem(itemDraft)}
        enhanceOpen={enhanceOpen}
        enhanceStat={enhanceStat}
        onDraftChange={setItemDraft}
        onEnhanceOpenChange={setEnhanceOpen}
        onEnhanceStatChange={setEnhanceStat}
      />
    );
  }

  async function moveItem(itemId: string, slotIndex: number, parentItemId: string | null) {
    if (!canManageAny) return;
    const movingHouseItem = items.find((item) => item.id === itemId);
    if (movingHouseItem && sameContainer(movingHouseItem, parentItemId) && movingHouseItem.slotIndex === slotIndex) return;
    const movingToStable = parentItemId === stableParentItemId || (parentItemId === null && slotIndex >= STABLE_SLOT_OFFSET);
    if (movingHouseItem?.type === 'pet' && !movingToStable) {
      setError('Animals can only be placed in stable slots.');
      return;
    }
    if (movingToStable) {
      if (movingHouseItem && movingHouseItem.type !== 'pet') {
        setError('Only animals can be placed in stable slots.');
        return;
      }
      const stableSlot = parentItemId === stableParentItemId ? slotIndex : slotIndex - STABLE_SLOT_OFFSET;
      if (stableSlot < 0 || stableSlot >= stableSlots) {
        setError('That stable slot does not exist.');
        return;
      }
    }

    setTargetSlot(`${parentItemId ?? 'main'}:${slotIndex}`);
    const existingHouseItem = items.some((item) => item.id === itemId);
    if (existingHouseItem) {
      const existing = items.find((item) => item.id === itemId);
      await requestHouseChange(existing && isMobileItem(existing) ? `/api/houses/mobile-items/${itemId}` : `/api/houses/items/${itemId}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ slotIndex, parentItemId })
      });
    } else {
      await requestHouseChange(`/api/inventory/items/${itemId}/send-house`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ homeId: selectedHome?.id, source: selectedHome?.source, slotIndex, parentItemId })
      });
      onCharacterInventoryChanged?.();
    }
    window.setTimeout(() => setTargetSlot(null), 120);
  }

  async function savePetDisplayName(event: FormEvent) {
    event.preventDefault();
    if (!itemModal?.item || itemModal.item.type !== 'pet' || !canManageAny) return;
    await requestHouseChange(isMobileItem(itemModal.item) ? `/api/houses/mobile-items/${itemModal.item.id}` : `/api/houses/items/${itemModal.item.id}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ displayName: itemDraft.displayName.trim() || null })
    });
  }

  async function dropItem(item: InventoryItem) {
    if (!canManageAny) return;
    await requestHouseChange(isMobileItem(item) ? `/api/houses/mobile-items/${item.id}?quantity=${Math.max(quantityStepForItem(item), dropQuantity)}` : `/api/houses/items/${item.id}?quantity=${Math.max(quantityStepForItem(item), dropQuantity)}`, { method: 'DELETE' });
  }

  async function takeItem(item: InventoryItem) {
    if (!canManageAny) return;
    const characterId = takeTargetCharacterId || caretakerCharacterId;
    if (!characterId) {
      setError('Choose a character to receive this item.');
      return;
    }
    const moved = await requestHouseChange(isMobileItem(item) ? `/api/wagons/items/${item.id}/take` : `/api/houses/items/${item.id}/take`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ characterId })
    });
    if (moved) onCharacterInventoryChanged?.();
  }

  async function boardAnimalAtStable(item: InventoryItem, vendor: ShopVendor) {
    if (!caretakerCharacterId || item.type !== 'pet') return;
    await requestHouseChange(`/api/cities/vendors/${vendor.id}/boarding`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ itemId: item.id, characterId: caretakerCharacterId })
    });
    setItemModal(null);
    onCharacterInventoryChanged?.();
  }

  async function savePermissions() {
    if (!ownerUserId || !canEditPermissions) return;
    setSaving(true);
    setError('');
    try {
      const response = await fetch(`/api/houses/${ownerUserId}/permissions`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          permissions: Object.entries(permissions).map(([granteeUserId, access]) => ({ granteeUserId, ...access })),
          homeId: selectedHome?.id,
          source: selectedHome?.source
        })
      });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.error ?? 'House permissions could not be saved.');
      const normalized = normalizeHousePayload(payload);
      setHouseAccess(normalized.access);
      setPermissions(Object.fromEntries(normalized.permissions.map((entry) => [entry.granteeUserId, { house: entry.house, stable: entry.stable }])));
      setPermissionsOpen(false);
    } catch (permissionError) {
      setError(permissionError instanceof Error ? permissionError.message : 'House permissions could not be saved.');
    } finally {
      setSaving(false);
    }
  }

  async function saveProperty(event: FormEvent) {
    event.preventDefault();
    if (!ownerUserId || !propertyModal || !propertyDraft.name.trim()) return;

    if (propertyModal === 'new') {
      if (!canAdd) return;
      await requestHouseChange(`/api/houses/${ownerUserId}/properties`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          ...propertyDraft,
          homeId: selectedHome?.id,
          caretakerCharacterId: propertyDraft.location === 'with_character' ? caretakerCharacterId : null
        })
      });
      return;
    }

    if (!canManageAny) return;
    await requestHouseChange(`/api/houses/properties/${propertyModal.id}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        ...propertyDraft,
        caretakerCharacterId: propertyDraft.location === 'with_character' ? caretakerCharacterId : null
      })
    });
  }

  return (
    <Card>
      <div className="mb-4 flex items-center justify-between gap-3">
        <div className="min-w-0 flex-1">
          <p className="eyebrow">{houseCityName}</p>
          <h3 className="mt-1 flex items-center gap-2 text-xl font-black">
            {homeKind === 'stable' || homeKind === 'caged-wagon' ? <PawPrint size={19} className="text-[var(--brass)]" /> : <Home size={19} className="text-[var(--brass)]" />}
            {homeKind === 'stable' || homeKind === 'caged-wagon' ? stableName : houseName}
            {homeIsMain && <span className="rounded-full border border-[var(--brass)]/50 bg-[var(--brass)]/10 px-2 py-1 text-[9px] font-black uppercase text-[var(--brass)]">Main House</span>}
          </h3>
          {houseLocked && <p className="mt-1 text-xs font-black uppercase tracking-wide text-[var(--red)]">Locked by DM</p>}
        </div>
        <div className="flex flex-wrap justify-end gap-2">
          {canAdd && <Button variant="primary" className="px-3 py-2 text-xs" onClick={() => openCreateHome('house')}><Home className="mr-2 inline" size={14} /> Add house</Button>}
          {canAdd && <Button variant="primary" className="px-3 py-2 text-xs" onClick={() => openCreateHome('stable')}><PawPrint className="mr-2 inline" size={14} /> Add stable</Button>}
          <Button variant="secondary" className="p-3" onClick={() => void loadHouse()} aria-label="Refresh house"><RefreshCw size={16} /></Button>
          {canCustomizeHouse && (
            <Button variant="secondary" className="p-3" onClick={openHouseSettings} aria-label="Home and stable settings">
              <Settings size={16} />
            </Button>
          )}
          {canAdd && homeSource === 'static' && (
            <Button variant={houseLocked ? 'danger' : 'teal'} className="p-3" onClick={toggleHouseLock} aria-label={houseLocked ? 'Unlock house' : 'Lock house'}>
              {houseLocked ? <Lock size={16} /> : <Unlock size={16} />}
            </Button>
          )}
          {canAdd && homeSource === 'static' && homeAvailable && (
            <Button variant="danger" className="p-3" onClick={() => void deleteHouse()} aria-label="Delete house">
              <Trash2 size={16} />
            </Button>
          )}
          {canEditPermissions && homeAvailable && (
            <Button variant="secondary" className="p-3" onClick={() => setPermissionsOpen(true)} aria-label="House permissions">
              <Users size={16} />
            </Button>
          )}
          {canAdd && homeSource === 'static' && homeKind === 'house' && propertySlots > 0 && <Button variant="primary" className="p-3" onClick={() => openProperty('new')} aria-label="Add property"><Plus size={16} /></Button>}
        </div>
      </div>

      {error && <div className="mb-3 rounded-2xl border border-[var(--red)]/40 bg-[var(--red)]/10 p-3 text-sm text-[var(--red)]">{error}</div>}

      {homes.length > 0 && (
        <div className="mb-5 grid gap-2 sm:grid-cols-2 xl:grid-cols-3">
          {homes.map((home, index) => {
            const homeKey = `${home.source}:${home.id}`;
            const active = homeKey === selectedHomeKey;
            const stable = home.kind === 'stable' || home.kind === 'caged-wagon';
            return (
              <div
                key={homeKey}
                className={`flex min-w-0 items-stretch overflow-hidden rounded-lg border transition ${active ? 'border-[var(--brass)] bg-[var(--brass)]/12 shadow-[inset_3px_0_0_var(--brass)]' : 'border-[var(--line)] bg-black/15 hover:border-[var(--brass)]/55'}`}
              >
                <button type="button" className="min-w-0 flex-1 p-3 text-left" onClick={() => setSelectedHomeKey(homeKey)}>
                  <span className="flex items-center gap-2">
                    {stable ? <PawPrint size={16} className="shrink-0 text-[var(--brass)]" /> : <Home size={16} className="shrink-0 text-[var(--brass)]" />}
                    <span className="truncate text-sm font-black">{stable ? home.stableName : home.name}</span>
                  </span>
                  <span className="mt-1 block truncate text-[10px] font-black uppercase text-[var(--muted)]">
                    {home.isMain ? 'Main House · ' : ''}{home.cityName} · {home.source === 'mobile' ? 'Mobile' : stable ? 'Stable' : 'House'}
                  </span>
                </button>
                {canAdd && (
                  <div className="grid w-10 shrink-0 grid-rows-2 border-l border-[var(--line)]">
                    <button type="button" disabled={saving || index === 0} className="grid place-items-center border-b border-[var(--line)] text-[var(--muted)] hover:bg-white/5 hover:text-[var(--brass)] disabled:opacity-20" onClick={() => void reorderHome(index, -1)} aria-label={`Move ${stable ? home.stableName : home.name} earlier`}><ChevronUp size={15} /></button>
                    <button type="button" disabled={saving || index === homes.length - 1} className="grid place-items-center text-[var(--muted)] hover:bg-white/5 hover:text-[var(--brass)] disabled:opacity-20" onClick={() => void reorderHome(index, 1)} aria-label={`Move ${stable ? home.stableName : home.name} later`}><ChevronDown size={15} /></button>
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}

      {loading ? (
        <div className="grid h-32 place-items-center rounded-2xl border border-[var(--line)] bg-black/10 text-[var(--muted)]">
          <Loader2 className="animate-spin" />
        </div>
      ) : (
        <div className="space-y-5">
          {!homeAvailable && (
            <div className="grid gap-3 rounded-2xl border border-[var(--line)] bg-black/10 p-4 text-sm text-[var(--muted)]">
              <p>No house, stable, Wagon Home, or Caged Wagon is available for this player.</p>
              {canAdd && (
                <div className="flex flex-wrap gap-2">
                  <Button variant="primary" className="w-fit px-3 py-2 text-xs" onClick={() => openCreateHome('house')}><Home className="mr-2 inline" size={14} /> Create house</Button>
                  <Button variant="secondary" className="w-fit px-3 py-2 text-xs" onClick={() => openCreateHome('stable')}><PawPrint className="mr-2 inline" size={14} /> Create stable</Button>
                </div>
              )}
            </div>
          )}
          {homeAvailable && (
          <section>
            {inventorySlots > 0 && <>
            <div className="rule-title mb-3"><h3 className="text-sm font-black uppercase tracking-wider">{houseName} inventory</h3></div>
            <div className="grid grid-cols-3 gap-2 sm:grid-cols-5 lg:grid-cols-6">
              {Array.from({ length: inventorySlots }, (_, slot) => {
                const item = itemBySlot.get(slot);
                return (
                  <InventorySlot
                    key={slot}
                    slot={slot}
                    item={item}
                    canEdit={canManageHouse}
                    canAdd={canAdd}
                    target={targetSlot === `${rootParentItemId ?? 'main'}:${slot}`}
                    onOpen={() => openItem(slot, rootParentItemId, item)}
                    onDropItem={(itemId) => moveItem(itemId, slot, rootParentItemId)}
                  />
                );
              })}
            </div>
            </>}
            {stableSlots > 0 && <div className="mt-5">
              <div className="rule-title mb-3">
                <h3 className="flex items-center gap-2 text-sm font-black uppercase tracking-wider">
                  <PawPrint size={16} className="text-[var(--brass)]" />
                  {stableName}
                </h3>
              </div>
              <p className="mb-3 text-xs font-black uppercase tracking-wide text-[var(--muted)]">{stableItems.length}/{stableSlots} animals housed</p>
              <div className="grid grid-cols-2 gap-2 min-[430px]:grid-cols-3 sm:grid-cols-5 lg:grid-cols-5">
                {Array.from({ length: stableSlots }, (_, slot) => {
                  const actualSlot = stableParentItemId ? slot : STABLE_SLOT_OFFSET + slot;
                  const item = stableItemBySlot.get(actualSlot);
                  return (
                    <InventorySlot
                      key={actualSlot}
                      slot={slot}
                      item={item}
                      canEdit={canManageStable}
                      canAdd={canAdd}
                      target={targetSlot === `${stableParentItemId ?? 'main'}:${actualSlot}`}
                      onOpen={() => openItem(actualSlot, stableParentItemId, item)}
                      onDropItem={(itemId) => moveItem(itemId, actualSlot, stableParentItemId)}
                    />
                  );
                })}
              </div>
            </div>}
            {storageItems.length > 0 && (
              <div className="mt-5 space-y-2">
                <div className="rule-title mb-3"><h3 className="text-sm font-black uppercase tracking-wider">Additional Storage</h3></div>
                {storageItems.map((storage) => {
                  const childItems = items.filter((item) => sameContainer(item, storage.id));
                  const childBySlot = new Map(childItems.map((item) => [item.slotIndex, item]));
                  return (
                    <details key={storage.id} className="rounded-2xl border border-[#d1a85b2f] bg-black/15">
                      <summary className="flex cursor-pointer list-none items-center justify-between gap-3 p-3">
                        <span className="flex items-center gap-2 font-black"><Home size={16} className="text-[var(--brass)]" /> {storage.displayName || storage.name}</span>
                        <span className="text-xs text-[var(--muted)]">{childItems.length}/{storage.storageCapacity} slots</span>
                      </summary>
                      <div className="flex justify-end border-t border-[var(--line)] px-3 py-2">
                        <Button variant="secondary" className="px-3 py-2 text-xs" onClick={() => openItem(storage.slotIndex, storage.parentItemId, storage)}>Inspect storage</Button>
                      </div>
                      <div className="grid grid-cols-3 gap-2 border-t border-[var(--line)] p-3 sm:grid-cols-5 lg:grid-cols-6">
                        {Array.from({ length: storage.storageCapacity }, (_, slot) => {
                          const item = childBySlot.get(slot);
                          return (
                            <InventorySlot
                              key={slot}
                              slot={slot}
                              item={item}
                              canEdit={canManageHouse}
                              canAdd={canAdd}
                              target={targetSlot === `${storage.id}:${slot}`}
                              onOpen={() => openItem(slot, storage.id, item)}
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
          </section>
          )}

          {homeKind === 'house' && propertySlots > 0 && <section>
            <div className="rule-title mb-3"><h3 className="text-sm font-black uppercase tracking-wider">Property</h3></div>
            <div className="grid gap-2 sm:grid-cols-2">
              {properties.map((property) => (
                <button
                  key={property.id}
                  type="button"
                  onClick={() => openProperty(property)}
                  className="rounded-2xl border border-[var(--line)] bg-black/15 p-3 text-left transition active:scale-[0.99]"
                >
                  <span className="flex items-center justify-between gap-3">
                    <span className="flex min-w-0 items-center gap-2">
                      <PawPrint size={16} className="shrink-0 text-[var(--brass)]" />
                      <span className="min-w-0">
                        <span className="block truncate font-black">{property.name}</span>
                        <span className="block text-xs text-[var(--muted)]">{property.type} · {property.location === 'at_house' ? 'At house' : 'With character'}</span>
                      </span>
                    </span>
                    {property.isPet && <span className="rounded-full bg-black/30 px-2 py-1 text-[10px] font-black uppercase text-[var(--brass)]">Pet</span>}
                  </span>
                </button>
              ))}
              {!properties.length && <div className="rounded-2xl border border-[var(--line)] bg-black/10 p-4 text-sm text-[var(--muted)]">No property yet.</div>}
            </div>
            <p className="mt-2 text-xs font-black uppercase tracking-wide text-[var(--muted)]">{properties.length}/{propertySlots} property slots</p>
          </section>}
        </div>
      )}

      {itemModal && (
        <Modal title={itemModal.item ? (itemModal.item.displayName || itemModal.item.name) : 'Add house item'} onClose={() => setItemModal(null)}>
          {itemModal.item?.type === 'pet' && (
            <div className="mb-3 space-y-3">
              <div className="rounded-xl border border-[var(--line)] bg-black/15 p-3 text-sm">
                <p className="font-black text-[var(--paper)]">{itemModal.item.displayName || itemModal.item.name}</p>
                <p className="mt-1 font-black uppercase tracking-wide text-[var(--brass)]">Animal: {itemModal.item.name}</p>
              </div>
              {canManageAny && (
                <form onSubmit={savePetDisplayName} className="grid gap-2 rounded-2xl border border-[var(--line)] bg-black/10 p-3">
                  <label>
                    <span className="mb-1 block text-[10px] font-black uppercase text-[var(--muted)]">Pet display name</span>
                    <TextField
                      placeholder={itemModal.item.name}
                      value={itemDraft.displayName}
                      onChange={(event) => setItemDraft({ ...itemDraft, displayName: event.target.value })}
                    />
                  </label>
                  <Button variant="secondary" disabled={saving}>Save pet name</Button>
                </form>
              )}
            </div>
          )}
          {itemModal.item ? (
            <div className="space-y-3">
              <div className="rounded-xl border border-[var(--line)] bg-black/15 p-3 text-sm text-[var(--muted)]">
                <p>{itemModal.item.type} · {itemModal.item.rarity} · Quantity {itemModal.item.quantity}</p>
                {itemModal.item.isAccessory && <p className="mt-1 font-black uppercase tracking-wide text-[var(--brass)]">Accessory</p>}
              </div>
              {canManageAny && (
                <div className="grid gap-2">
                  {itemModal.item.type === 'pet' && availableStables.length > 0 && (
                    <div className="grid gap-2 rounded-xl border border-[var(--line)] bg-black/10 p-3">
                      <p className="text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">Board animal</p>
                      {availableStables.map((stable) => (
                        <Button key={stable.id} variant="secondary" onClick={() => boardAnimalAtStable(itemModal.item!, stable)} disabled={saving}>
                          <PawPrint className="mr-2 inline" size={14} /> Board at {stable.name}
                        </Button>
                      ))}
                    </div>
                  )}
                  <div className="grid gap-2 rounded-xl border border-[var(--line)] bg-black/10 p-3">
                    {takeTargetCharacters.length > 1 && (
                      <label>
                        <span className="mb-1 block text-[10px] font-black uppercase text-[var(--muted)]">Take to character</span>
                        <SelectField value={takeTargetCharacterId} onChange={(event) => setTakeTargetCharacterId(event.target.value)}>
                          {takeTargetCharacters.map((entry) => <option key={entry.id} value={entry.id}>{entry.name}</option>)}
                        </SelectField>
                      </label>
                    )}
                    <Button variant="teal" onClick={() => takeItem(itemModal.item!)} disabled={saving || !takeTargetCharacterId}>
                      {itemModal.item.type === 'pet' ? 'Move to active pet' : 'Take to inventory'}
                    </Button>
                  </div>
                  <div className="grid gap-2 sm:grid-cols-[1fr_auto]">
                    <NumberInput min={quantityStepForItem(itemModal.item)} step={quantityStepForItem(itemModal.item)} max={itemModal.item.quantity} value={dropQuantity} onValueChange={setDropQuantity} />
                    <Button variant="danger" onClick={() => dropItem(itemModal.item!)} disabled={saving}>Drop</Button>
                  </div>
                </div>
              )}
              {canAdd && (
                <form onSubmit={updateItem} className="grid gap-3 rounded-2xl border border-[var(--line)] bg-black/10 p-3">
                  {renderItemEditor()}
                  <Button variant="primary" disabled={!itemDraft.name.trim() || saving}>Save item</Button>
                </form>
              )}
            </div>
          ) : (
            <form onSubmit={addItem} className="grid gap-3">
              {renderItemEditor()}
              <Button variant="primary" disabled={!itemDraft.name.trim() || saving}>Add item</Button>
            </form>
          )}
        </Modal>
      )}

      {permissionsOpen && (
        <Modal title="Permissions" onClose={() => setPermissionsOpen(false)}>
          <div className="grid gap-3">
            {permissionProfiles.map((entry) => {
              const access = permissions[entry.id] ?? { house: false, stable: false };
              return (
                <div key={entry.id} className="grid gap-2 rounded-2xl border border-[var(--line)] bg-black/15 p-3 sm:grid-cols-[1fr_auto_auto] sm:items-center">
                  <div>
                    <p className="font-black">{entry.displayName || entry.username || 'Player'}</p>
                    {entry.username && <p className="text-xs text-[var(--muted)]">{entry.username}</p>}
                  </div>
                  {homeAvailable && inventorySlots > 0 && <label className="flex items-center gap-2 text-sm font-black">
                    <input
                      type="checkbox"
                      checked={access.house}
                      onChange={(event) => setPermissions((current) => ({ ...current, [entry.id]: { ...(current[entry.id] ?? access), house: event.target.checked } }))}
                    />
                    {houseName}
                  </label>}
                  {homeAvailable && stableSlots > 0 && <label className="flex items-center gap-2 text-sm font-black">
                    <input
                      type="checkbox"
                      checked={access.stable}
                      onChange={(event) => setPermissions((current) => ({ ...current, [entry.id]: { ...(current[entry.id] ?? access), stable: event.target.checked } }))}
                    />
                    {stableName}
                  </label>}
                </div>
              );
            })}
            {!permissionProfiles.length && (
              <div className="rounded-2xl border border-[var(--line)] bg-black/10 p-4 text-sm text-[var(--muted)]">No other players are available yet.</div>
            )}
            <div className="flex justify-end gap-2">
              <Button variant="ghost" onClick={() => setPermissionsOpen(false)}>Cancel</Button>
              <Button variant="primary" disabled={saving} onClick={savePermissions}>
                {saving && <Loader2 className="mr-2 inline animate-spin" size={15} />}
                Save permissions
              </Button>
            </div>
          </div>
        </Modal>
      )}

      {houseSettingsOpen && (
        <Modal title={creatingHome ? `Create ${houseSettingsDraft.kind}` : 'Property settings'} onClose={() => { setHouseSettingsOpen(false); setCreatingHome(false); }}>
          <form onSubmit={saveHouseSettings} className="grid gap-3">
            {creatingHome && (
              <label>
                <span className="mb-1 block text-[10px] font-black uppercase text-[var(--muted)]">Property type</span>
                <SelectField value={houseSettingsDraft.kind} onChange={(event) => {
                  const kind = event.target.value === 'stable' ? 'stable' : 'house';
                  setHouseSettingsDraft((current) => ({
                    ...current,
                    kind,
                    name: kind === 'stable' ? 'New Stable' : 'New House',
                    inventorySlots: kind === 'house' ? Math.max(1, current.inventorySlots || 45) : 0,
                    stableSlots: kind === 'stable' ? Math.max(1, current.stableSlots || 5) : 0,
                    isMain: kind === 'house' && current.isMain
                  }));
                }}>
                  <option value="house">House</option>
                  <option value="stable">Stable</option>
                </SelectField>
              </label>
            )}
            <label>
              <span className="mb-1 block text-[10px] font-black uppercase text-[var(--muted)]">{houseSettingsDraft.kind === 'stable' ? 'Stable name' : 'House name'}</span>
              <TextField value={houseSettingsDraft.name} onChange={(event) => setHouseSettingsDraft({ ...houseSettingsDraft, name: event.target.value })} />
            </label>
            {houseSettingsDraft.kind === 'house' && stableSlots > 0 && !creatingHome && <label>
              <span className="mb-1 block text-[10px] font-black uppercase text-[var(--muted)]">Stable name</span>
              <TextField value={houseSettingsDraft.stableName} onChange={(event) => setHouseSettingsDraft({ ...houseSettingsDraft, stableName: event.target.value })} />
            </label>}
            {houseSettingsDraft.kind === 'house' && homeKind !== 'caged-wagon' && (
              <label className="flex items-center gap-2 rounded-xl border border-[var(--brass)]/35 bg-[var(--brass)]/10 p-3 text-sm font-black">
                <input type="checkbox" checked={houseSettingsDraft.isMain} onChange={(event) => setHouseSettingsDraft({ ...houseSettingsDraft, isMain: event.target.checked })} />
                Main House
              </label>
            )}
            {canAdd && (
              <>
                <label>
                  <span className="mb-1 block text-[10px] font-black uppercase text-[var(--muted)]">Location</span>
                  <SelectField value={houseSettingsDraft.cityName} onChange={(event) => setHouseSettingsDraft({ ...houseSettingsDraft, cityName: event.target.value })}>
                    {cityOptions.map((city) => <option key={city} value={city}>{city}</option>)}
                  </SelectField>
                </label>
                <div className="grid gap-2 sm:grid-cols-3">
                  {houseSettingsDraft.kind === 'house' && <label>
                    <span className="mb-1 block text-[10px] font-black uppercase text-[var(--muted)]">Home slots</span>
                    <NumberInput min={0} max={500} value={houseSettingsDraft.inventorySlots} onValueChange={(inventorySlots) => setHouseSettingsDraft({ ...houseSettingsDraft, inventorySlots })} />
                  </label>}
                  {(houseSettingsDraft.kind === 'stable' || (!creatingHome && stableSlots > 0)) && <label>
                    <span className="mb-1 block text-[10px] font-black uppercase text-[var(--muted)]">Stable slots</span>
                    <NumberInput min={0} max={200} value={houseSettingsDraft.stableSlots} onValueChange={(stableSlots) => setHouseSettingsDraft({ ...houseSettingsDraft, stableSlots })} />
                  </label>}
                  {houseSettingsDraft.kind === 'house' && (creatingHome || homeSource === 'static') && <label>
                    <span className="mb-1 block text-[10px] font-black uppercase text-[var(--muted)]">Property slots</span>
                    <NumberInput min={0} max={200} value={houseSettingsDraft.propertySlots} onValueChange={(propertySlots) => setHouseSettingsDraft({ ...houseSettingsDraft, propertySlots })} />
                  </label>}
                </div>
                <label className="flex items-center gap-2 rounded-xl border border-[var(--line)] bg-black/15 p-3 text-sm font-black">
                  <input type="checkbox" checked={houseSettingsDraft.locked} onChange={(event) => setHouseSettingsDraft({ ...houseSettingsDraft, locked: event.target.checked })} />
                  Locked by DM
                </label>
              </>
            )}
            <div className="flex justify-end gap-2">
              <Button variant="ghost" type="button" onClick={() => { setHouseSettingsOpen(false); setCreatingHome(false); }}>Cancel</Button>
              <Button variant="primary" disabled={!houseSettingsDraft.name.trim() || saving}>
                {saving && <Loader2 className="mr-2 inline animate-spin" size={15} />}
                Save settings
              </Button>
            </div>
          </form>
        </Modal>
      )}

      {propertyModal && (
        <Modal title={propertyModal === 'new' ? 'Add property' : propertyModal.name} onClose={() => setPropertyModal(null)}>
          <form onSubmit={saveProperty} className="grid gap-3">
            <TextField autoFocus placeholder="Property name" value={propertyDraft.name} onChange={(event) => setPropertyDraft({ ...propertyDraft, name: event.target.value })} />
            <div className="grid gap-2 sm:grid-cols-3">
              <SelectField value={propertyDraft.type} onChange={(event) => setPropertyDraft({ ...propertyDraft, type: event.target.value as PropertyType })}>{PROPERTY_TYPES.map((type) => <option key={type} value={type}>{type}</option>)}</SelectField>
              <SelectField value={propertyDraft.location} onChange={(event) => setPropertyDraft({ ...propertyDraft, location: event.target.value as PropertyLocation })}>{PROPERTY_LOCATIONS.map((location) => <option key={location} value={location}>{location === 'at_house' ? 'At house' : 'With character'}</option>)}</SelectField>
              <NumberInput min={0} value={propertyDraft.slotIndex} onValueChange={(slotIndex) => setPropertyDraft({ ...propertyDraft, slotIndex })} />
            </div>
            <label className="flex items-center gap-2 rounded-xl border border-[var(--line)] bg-black/15 p-3 text-sm font-black">
              <input type="checkbox" checked={propertyDraft.isPet} onChange={(event) => setPropertyDraft({ ...propertyDraft, isPet: event.target.checked })} />
              Can occupy active pet slot
            </label>
            {propertyDraft.type === 'wagon' && (
              <label>
                <span className="mb-1 block text-[10px] font-black uppercase text-[var(--muted)]">Wagon storage slots</span>
                <NumberInput min={0} value={propertyDraft.storageCapacity} onValueChange={(storageCapacity) => setPropertyDraft({ ...propertyDraft, storageCapacity })} />
              </label>
            )}
            <Button variant="primary" disabled={!propertyDraft.name.trim() || saving}>Save property</Button>
          </form>
        </Modal>
      )}
    </Card>
  );
}
