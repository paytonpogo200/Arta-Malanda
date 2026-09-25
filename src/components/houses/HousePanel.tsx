'use client';

import { useCallback, useEffect, useMemo, useState, type FormEvent } from 'react';
import { ChevronDown, ChevronUp, Home, Loader2, Lock, PawPrint, RefreshCw, Settings, Trash2, Unlock } from 'lucide-react';
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
import { normalizeHousePayload, type HousePayload } from '@/features/houses/data';
import { quantityStepForItem } from '@/features/inventory/data';
import { useDragAutoScroll } from '@/hooks/useDragAutoScroll';
import { useLiveRefresh } from '@/hooks/useLiveRefresh';
import type { Character, House, InventoryItem, LoadoutModifierKey, ShopVendor, Spell } from '@/lib/types';

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

function isPortablePropertyItem(item: InventoryItem) {
  const name = item.name.trim().toLowerCase();
  return item.isStorage && (name === 'wagon home' || name === 'caged wagon');
}

function isStableDestination(home: House, parentItemId: string | null) {
  if (home.kind === 'stable') return true;
  if (home.kind !== 'caged-wagon') return false;
  return parentItemId === (home.stableStorageItemId ?? home.id);
}

type HouseSettingsDraft = {
  kind: 'house' | 'stable';
  name: string;
  stableName: string;
  cityName: string;
  inventorySlots: number;
  stableSlots: number;
  locked: boolean;
  isMain: boolean;
};

export function HousePanel({ ownerUserId, caretakerCharacterId, viewerUserId, characters = [], canAdd, onCharacterInventoryChanged }: HousePanelProps) {
  const [homes, setHomes] = useState<House[]>([]);
  const [homeDetails, setHomeDetails] = useState<Record<string, HousePayload>>({});
  const [selectedHomeKey, setSelectedHomeKey] = useState('');
  const [houseAccess, setHouseAccess] = useState({ owner: false, dm: false, house: false, stable: false });
  const [inventorySlots, setInventorySlots] = useState(45);
  const [stableSlots, setStableSlots] = useState(0);
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
    stableSlots: 0,
    locked: false,
    isMain: false
  });
  const [cityOptions, setCityOptions] = useState<string[]>(['Wild']);
  const [availableStables, setAvailableStables] = useState<ShopVendor[]>([]);
  const [loading, setLoading] = useState(Boolean(ownerUserId));
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [targetSlot, setTargetSlot] = useState<string | null>(null);
  const [itemModal, setItemModal] = useState<{ home: House; slot: number; parentItemId: string | null; item?: InventoryItem } | null>(null);
  const [itemDraft, setItemDraft] = useState<ItemDraft>(EMPTY_ITEM_DRAFT);
  const [dropQuantity, setDropQuantity] = useState(1);
  const [spells, setSpells] = useState<Spell[]>([]);
  const [enhanceOpen, setEnhanceOpen] = useState(false);
  const [enhanceStat, setEnhanceStat] = useState<LoadoutModifierKey>('strength');
  const [takeTargetCharacterId, setTakeTargetCharacterId] = useState(caretakerCharacterId);
  const [homeKind, setHomeKind] = useState<'house' | 'stable' | 'wagon-home' | 'caged-wagon'>('house');
  const [homeSource, setHomeSource] = useState<'static' | 'mobile'>('static');
  const [homeIsMain, setHomeIsMain] = useState(false);
  const [homeAvailable, setHomeAvailable] = useState(false);
  useDragAutoScroll();

  const canCustomizeHouse = canAdd || houseAccess.house || houseAccess.stable;
  const selectedHome = useMemo(() => homes.find((home) => `${home.source}:${home.id}` === selectedHomeKey) ?? null, [homes, selectedHomeKey]);
  const itemHomeById = useMemo(() => {
    const result = new Map<string, House>();
    for (const detail of Object.values(homeDetails)) {
      if (!detail.house) continue;
      for (const item of detail.items) result.set(item.id, detail.house);
    }
    return result;
  }, [homeDetails]);
  const takeTargetCharacters = useMemo(() => {
    const allowedOwnerIds = canAdd
      ? null
      : new Set([ownerUserId, viewerUserId].filter((entry): entry is string => Boolean(entry)));
    const caretaker = characters.find((entry) => entry.id === caretakerCharacterId);
    const assigned = characters
      .filter((entry) => !allowedOwnerIds || (entry.ownerUserId && allowedOwnerIds.has(entry.ownerUserId)))
      .filter((entry) => canAdd || !caretaker || entry.id === caretaker.id
        || (entry.locationCityKey && entry.locationCityKey === caretaker.locationCityKey)
        || entry.locationName === caretaker.locationName)
      .sort((a, b) => a.name.localeCompare(b.name));
    if (assigned.some((entry) => entry.id === caretakerCharacterId)) return assigned;
    return caretaker ? [caretaker, ...assigned] : assigned;
  }, [canAdd, caretakerCharacterId, characters, ownerUserId, viewerUserId]);
  const caretakerCharacter = useMemo(() => characters.find((entry) => entry.id === caretakerCharacterId) ?? null, [caretakerCharacterId, characters]);
  const itemModalCanManage = useMemo(() => {
    if (!itemModal) return false;
    if (canAdd) return true;
    const detail = homeDetails[`${itemModal.home.source}:${itemModal.home.id}`];
    const stable = itemModal.home.kind === 'stable' || itemModal.home.kind === 'caged-wagon';
    return itemModal.home.accessible && Boolean(stable ? detail?.access.stable : detail?.access.house);
  }, [canAdd, homeDetails, itemModal]);

  const loadHouse = useCallback(async (showLoading = true) => {
    if (!ownerUserId) return;
    if (showLoading) setLoading(true);
    setError('');

    try {
      const [requestedSource, requestedId] = selectedHomeKey ? selectedHomeKey.split(':') : ['', ''];
      const params = new URLSearchParams();
      if (requestedId) params.set('homeId', requestedId);
      if (requestedSource) params.set('source', requestedSource);
      params.set('characterId', caretakerCharacterId);
      const response = await fetch(`/api/houses/${ownerUserId}${params.size ? `?${params.toString()}` : ''}`, { cache: 'no-store' });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.error ?? 'House could not be loaded.');
      const normalized = normalizeHousePayload(payload);
      setHomeAvailable(Boolean(normalized.house));
      setHomes(normalized.homes);
      if (normalized.house) setSelectedHomeKey(`${normalized.house.source}:${normalized.house.id}`);
      else setSelectedHomeKey('');
      setHouseName(normalized.house?.name ?? 'House');
      setStableName(normalized.house?.stableName ?? 'Stable');
      setHouseCityName(normalized.house?.cityName ?? 'Wild');
      setInventorySlots(normalized.house?.inventorySlots ?? 45);
      setStableSlots(normalized.house?.stableSlots ?? 0);
      setHouseLocked(Boolean(normalized.house?.locked));
      setHomeKind(normalized.house?.kind ?? 'house');
      setHomeSource(normalized.house?.source ?? 'static');
      setHomeIsMain(Boolean(normalized.house?.isMain));
      setHouseAccess(normalized.access);

      const selectedKey = normalized.house ? `${normalized.house.source}:${normalized.house.id}` : '';
      const details = await Promise.all(normalized.homes.map(async (home) => {
        const key = `${home.source}:${home.id}`;
        if (key === selectedKey) return [key, normalized] as const;
        const detailParams = new URLSearchParams({ homeId: home.id, source: home.source, characterId: caretakerCharacterId });
        const detailResponse = await fetch(`/api/houses/${ownerUserId}?${detailParams.toString()}`, { cache: 'no-store' });
        const detailPayload = await detailResponse.json().catch(() => ({}));
        if (!detailResponse.ok) throw new Error(detailPayload.error ?? `${home.name} could not be loaded.`);
        return [key, normalizeHousePayload(detailPayload)] as const;
      }));
      setHomeDetails(Object.fromEntries(details));
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : 'House could not be loaded.');
    } finally {
      if (showLoading) setLoading(false);
    }
  }, [caretakerCharacterId, ownerUserId, selectedHomeKey]);

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

  useEffect(() => {
    if (!selectedHome) return;
    const detail = homeDetails[`${selectedHome.source}:${selectedHome.id}`];
    setHomeAvailable(true);
    setHouseName(selectedHome.name);
    setStableName(selectedHome.stableName);
    setHouseCityName(selectedHome.cityName);
    setInventorySlots(selectedHome.inventorySlots);
    setStableSlots(selectedHome.stableSlots);
    setHouseLocked(Boolean(selectedHome.locked));
    setHomeKind(selectedHome.kind);
    setHomeSource(selectedHome.source);
    setHomeIsMain(Boolean(selectedHome.isMain));
    if (detail) setHouseAccess(detail.access);
  }, [homeDetails, selectedHome]);

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

  function openItem(home: House, slot: number, parentItemId: string | null, item?: InventoryItem) {
    if (!item && !canAdd) return;
    setSelectedHomeKey(`${home.source}:${home.id}`);
    setItemModal({ home, slot, parentItemId, item });
    setItemDraft(item ? draftFromInventoryItem(item) : EMPTY_ITEM_DRAFT);
    setDropQuantity(item?.quantity ?? 1);
    setEnhanceOpen(false);
    setEnhanceStat('strength');
  }

  async function requestHouseChange(url: string, init: RequestInit) {
    setSaving(true);
    setError('');
    try {
      const response = await fetch(url, init);
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.error ?? 'House action failed.');
      setItemModal(null);
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
      body: JSON.stringify({ homeId: selectedHome.id, source: selectedHome.source, locked: !houseLocked, actorCharacterId: caretakerCharacterId })
    });
  }

  async function addItem(event: FormEvent) {
    event.preventDefault();
    if (!ownerUserId || !itemModal || itemModal.item || !itemDraft.name.trim() || !canAdd) return;
    const addingToStable = isStableDestination(itemModal.home, itemModal.parentItemId);
    if (addingToStable && itemDraft.type !== 'pet') {
      setError('Only animals can be placed in stable slots.');
      return;
    }
    if (itemDraft.type === 'pet' && !addingToStable) {
      setError('Animals can only be placed in stable slots.');
      return;
    }
    if (itemDraft.type === 'pet' && itemModal.home.kind === 'wagon-home') {
      setError('Animals need an active pet slot or a Caged Wagon stable.');
      return;
    }
    const modalHome = itemModal.home;
    const addUrl = modalHome.source === 'mobile'
      ? `/api/houses/mobile-items/${modalHome.id}`
      : `/api/houses/${ownerUserId}/items`;
    await requestHouseChange(addUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        ...itemDraftPayload(itemDraft),
        homeId: modalHome.id,
        parentItemId: itemModal.parentItemId,
        slotIndex: itemModal.slot,
        actorCharacterId: caretakerCharacterId
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
        body: JSON.stringify({ homes: reordered.map((home) => ({ id: home.id, source: home.source })), actorCharacterId: caretakerCharacterId })
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
        source: selectedHome?.source ?? 'static',
        actorCharacterId: caretakerCharacterId
      } : {
        homeId: selectedHome?.id,
        source: selectedHome?.source ?? 'static',
        name: houseSettingsDraft.name,
        stableName: houseSettingsDraft.stableName,
        isMain: houseSettingsDraft.isMain,
        actorCharacterId: caretakerCharacterId
      })
    });
    setCreatingHome(false);
    setHouseSettingsOpen(false);
  }

  async function deleteHouse() {
    if (!ownerUserId || !canAdd || homeSource !== 'static' || !homeAvailable || !selectedHome) return;
    if (!window.confirm(`Delete ${homeKind === 'stable' ? stableName : houseName}? It must be empty first.`)) return;
    await requestHouseChange(`/api/houses/${ownerUserId}?homeId=${encodeURIComponent(selectedHome.id)}&source=static&characterId=${encodeURIComponent(caretakerCharacterId)}`, { method: 'DELETE' });
  }

  async function updateItem(event: FormEvent) {
    event.preventDefault();
    if (!itemModal?.item || !itemDraft.name.trim() || !canAdd) return;
    const editingStable = isStableDestination(itemModal.home, itemModal.parentItemId);
    if (editingStable && itemDraft.type !== 'pet') {
      setError('Only animals can be placed in stable slots.');
      return;
    }
    if (itemDraft.type === 'pet' && !editingStable) {
      setError('Animals can only be placed in stable slots.');
      return;
    }
    if (itemDraft.type === 'pet' && itemModal.home.kind === 'wagon-home') {
      setError('Animals need an active pet slot or a Caged Wagon stable.');
      return;
    }
    await requestHouseChange(itemModal.home.source === 'mobile' ? `/api/houses/mobile-items/${itemModal.item.id}` : `/api/houses/items/${itemModal.item.id}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        ...itemDraftPayload({
          ...itemDraft,
          quantity: Math.max(quantityStepForItem(itemDraft), itemDraft.quantity)
        }),
        actorCharacterId: caretakerCharacterId
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

  async function moveItem(itemId: string, slotIndex: number, parentItemId: string | null, destinationHome: House = selectedHome as House) {
    if (!destinationHome) return;
    const sourceHome = itemHomeById.get(itemId) ?? null;
    const movingHouseItem = sourceHome ? homeDetails[`${sourceHome.source}:${sourceHome.id}`]?.items.find((item) => item.id === itemId) : undefined;
    const destinationDetail = homeDetails[`${destinationHome.source}:${destinationHome.id}`];
    const movingToStable = isStableDestination(destinationHome, parentItemId);
    const canUseDestination = canAdd || Boolean(destinationHome.accessible && (movingToStable ? destinationDetail?.access.stable : destinationDetail?.access.house));
    if (!canUseDestination) return;
    if (movingHouseItem && sameContainer(movingHouseItem, parentItemId) && movingHouseItem.slotIndex === slotIndex) return;
    if (movingHouseItem?.type === 'pet' && !movingToStable) {
      setError('Animals can only be placed in stable slots.');
      return;
    }
    if (movingToStable) {
      if (movingHouseItem && movingHouseItem.type !== 'pet') {
        setError('Only animals can be placed in stable slots.');
        return;
      }
      if (slotIndex < 0 || slotIndex >= destinationHome.stableSlots) {
        setError('That stable slot does not exist.');
        return;
      }
    }

    const destinationKey = `${destinationHome.source}:${destinationHome.id}`;
    setTargetSlot(`${destinationKey}:${parentItemId ?? 'main'}:${slotIndex}`);
    if (sourceHome) {
      const sourceKey = `${sourceHome.source}:${sourceHome.id}`;
      if (sourceKey !== destinationKey) {
        await requestHouseChange('/api/houses/transfer', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            itemId,
            sourceHomeId: sourceHome.id,
            source: sourceHome.source,
            destinationHomeId: destinationHome.id,
            destination: destinationHome.source,
            slotIndex,
            parentItemId,
            actorCharacterId: caretakerCharacterId
          })
        });
      } else await requestHouseChange(sourceHome.source === 'mobile' ? `/api/houses/mobile-items/${itemId}` : `/api/houses/items/${itemId}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ slotIndex, parentItemId, actorCharacterId: caretakerCharacterId })
      });
    } else {
      await requestHouseChange(`/api/inventory/items/${itemId}/send-house`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ homeId: destinationHome.id, source: destinationHome.source, slotIndex, parentItemId, actorCharacterId: caretakerCharacterId })
      });
      onCharacterInventoryChanged?.();
    }
    window.setTimeout(() => setTargetSlot(null), 120);
  }

  async function savePetDisplayName(event: FormEvent) {
    event.preventDefault();
    if (!itemModal?.item || itemModal.item.type !== 'pet' || !itemModalCanManage) return;
    await requestHouseChange(itemModal.home.source === 'mobile' ? `/api/houses/mobile-items/${itemModal.item.id}` : `/api/houses/items/${itemModal.item.id}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ displayName: itemDraft.displayName.trim() || null, actorCharacterId: caretakerCharacterId })
    });
  }

  async function dropItem(item: InventoryItem) {
    if (!itemModalCanManage) return;
    const sourceHome = itemHomeById.get(item.id);
    const quantity = Math.max(quantityStepForItem(item), dropQuantity);
    await requestHouseChange(sourceHome?.source === 'mobile'
      ? `/api/houses/mobile-items/${item.id}?quantity=${quantity}&characterId=${encodeURIComponent(caretakerCharacterId)}`
      : `/api/houses/items/${item.id}?quantity=${quantity}&characterId=${encodeURIComponent(caretakerCharacterId)}`, { method: 'DELETE' });
  }

  async function takeItem(item: InventoryItem) {
    if (!itemModalCanManage) return;
    const characterId = takeTargetCharacterId || caretakerCharacterId;
    if (!characterId) {
      setError('Choose a character to receive this item.');
      return;
    }
    const moved = await requestHouseChange(`/api/houses/items/${item.id}/take`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ characterId, actorCharacterId: caretakerCharacterId })
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
        </div>
      </div>

      {error && <div className="mb-3 rounded-2xl border border-[var(--red)]/40 bg-[var(--red)]/10 p-3 text-sm text-[var(--red)]">{error}</div>}

      {homes.length > 0 && (
        <div className="mb-5 space-y-4">
          {homes.map((home, index) => {
            const homeKey = `${home.source}:${home.id}`;
            const active = homeKey === selectedHomeKey;
            const stable = home.kind === 'stable' || home.kind === 'caged-wagon';
            const detail = homeDetails[homeKey];
            const detailItems = detail?.items ?? [];
            const homeRootId = home.kind === 'wagon-home' ? home.storageItemId ?? null : null;
            const homeStableId = home.kind === 'caged-wagon' ? home.stableStorageItemId ?? home.id : null;
            const homeStableItems = detailItems.filter((item) => homeStableId
              ? sameContainer(item, homeStableId) && item.type === 'pet'
              : sameContainer(item, null) && item.type === 'pet' && item.slotIndex < home.stableSlots);
            const homeStableIds = new Set(homeStableItems.map((item) => item.id));
            const homeMainItems = detailItems.filter((item) => sameContainer(item, homeRootId) && !homeStableIds.has(item.id));
            const homeMainBySlot = new Map(homeMainItems.map((item) => [item.slotIndex, item]));
            const homeStableBySlot = new Map(homeStableItems.map((item) => [item.slotIndex, item]));
            const homeStorageItems = detailItems.filter((item) => item.isStorage
              && !isPortablePropertyItem(item)
              && item.id !== home.storageItemId
              && item.id !== homeStableId);
            const canUseHouse = canAdd || Boolean(detail?.access.house && home.accessible);
            const canUseStable = canAdd || Boolean(detail?.access.stable && home.accessible);
            return (
              <section
                key={homeKey}
                className={`overflow-hidden rounded-lg border transition ${active ? 'border-[var(--brass)] bg-[var(--brass)]/8 shadow-[inset_3px_0_0_var(--brass)]' : 'border-[var(--line)] bg-black/15'}`}
              >
                <div className="flex items-stretch border-b border-[var(--line)]">
                  <button type="button" className="min-w-0 flex-1 p-3 text-left" onClick={() => setSelectedHomeKey(homeKey)}>
                    <span className="flex items-center gap-2">
                      {stable ? <PawPrint size={16} className="shrink-0 text-[var(--brass)]" /> : <Home size={16} className="shrink-0 text-[var(--brass)]" />}
                      <span className="truncate text-base font-black">{stable ? home.stableName : home.name}</span>
                      {home.isMain && <span className="rounded-full border border-[var(--brass)]/45 bg-[var(--brass)]/10 px-2 py-1 text-[9px] font-black uppercase text-[var(--brass)]">Main</span>}
                    </span>
                    <span className="mt-1 block truncate text-[10px] font-black uppercase text-[var(--muted)]">{home.cityName} · {home.source === 'mobile' ? 'Mobile' : stable ? 'Stable' : 'House'}</span>
                  </button>
                  {canAdd && <div className="grid w-11 shrink-0 grid-rows-2 border-l border-[var(--line)]">
                    <button type="button" disabled={saving || index === 0} className="grid place-items-center border-b border-[var(--line)] text-[var(--muted)] hover:bg-white/5 hover:text-[var(--brass)] disabled:opacity-20" onClick={() => void reorderHome(index, -1)} aria-label={`Move ${stable ? home.stableName : home.name} earlier`}><ChevronUp size={16} /></button>
                    <button type="button" disabled={saving || index === homes.length - 1} className="grid place-items-center text-[var(--muted)] hover:bg-white/5 hover:text-[var(--brass)] disabled:opacity-20" onClick={() => void reorderHome(index, 1)} aria-label={`Move ${stable ? home.stableName : home.name} later`}><ChevronDown size={16} /></button>
                  </div>}
                </div>
                {!detail ? <div className="grid h-24 place-items-center text-[var(--muted)]"><Loader2 className="animate-spin" size={18} /></div> : <div className="space-y-4 p-3">
                  {!home.accessible && !canAdd && <div className="flex items-center gap-2 rounded-lg border border-[var(--line)] bg-black/20 p-3 text-sm text-[var(--muted)]"><Lock size={15} /> {home.accessReason || `A controlled character must be in ${home.cityName} to use this property.`}</div>}
                  {(home.accessible || canAdd) && !stable && home.inventorySlots > 0 && <div>
                    <p className="mb-2 text-[10px] font-black uppercase text-[var(--muted)]">Inventory · {homeMainItems.length}/{home.inventorySlots}</p>
                    <div className="grid grid-cols-3 gap-2 sm:grid-cols-5 lg:grid-cols-6">
                      {Array.from({ length: home.inventorySlots }, (_, slot) => {
                        const item = homeMainBySlot.get(slot);
                        return <InventorySlot key={slot} slot={slot} item={item} canEdit={canUseHouse} canAdd={canAdd}
                          target={targetSlot === `${homeKey}:${homeRootId ?? 'main'}:${slot}`}
                          onOpen={() => openItem(home, slot, homeRootId, item)}
                          onDropItem={(itemId) => moveItem(itemId, slot, homeRootId, home)} />;
                      })}
                    </div>
                  </div>}
                  {(home.accessible || canAdd) && stable && home.stableSlots > 0 && <div>
                    <p className="mb-2 flex items-center gap-2 text-[10px] font-black uppercase text-[var(--muted)]"><PawPrint size={13} className="text-[var(--brass)]" /> {home.stableName} · {homeStableItems.length}/{home.stableSlots}</p>
                    <div className="grid grid-cols-2 gap-2 min-[430px]:grid-cols-3 sm:grid-cols-5 lg:grid-cols-5">
                      {Array.from({ length: home.stableSlots }, (_, slot) => {
                        const actualSlot = slot;
                        const item = homeStableBySlot.get(actualSlot);
                        return <InventorySlot key={actualSlot} slot={slot} item={item} canEdit={canUseStable} canAdd={canAdd}
                          target={targetSlot === `${homeKey}:${homeStableId ?? 'main'}:${actualSlot}`}
                          onOpen={() => openItem(home, actualSlot, homeStableId, item)}
                          onDropItem={(itemId) => moveItem(itemId, actualSlot, homeStableId, home)} />;
                      })}
                    </div>
                  </div>}
                  {(home.accessible || canAdd) && homeStorageItems.length > 0 && <div className="space-y-2">
                    <p className="text-[10px] font-black uppercase text-[var(--muted)]">Additional Storage</p>
                    {homeStorageItems.map((storage) => {
                      const childItems = detailItems.filter((item) => sameContainer(item, storage.id));
                      const childBySlot = new Map(childItems.map((item) => [item.slotIndex, item]));
                      return <details key={storage.id} className="rounded-lg border border-[#d1a85b2f] bg-black/15">
                        <summary className="flex cursor-pointer list-none items-center justify-between gap-3 p-3">
                          <span className="flex min-w-0 items-center gap-2 font-black"><Home size={16} className="shrink-0 text-[var(--brass)]" /><span className="truncate">{storage.displayName || storage.name}</span></span>
                          <span className="shrink-0 text-xs text-[var(--muted)]">{childItems.length}/{storage.storageCapacity} slots</span>
                        </summary>
                        <div className="flex justify-end border-t border-[var(--line)] px-3 py-2">
                          <Button variant="secondary" className="px-3 py-2 text-xs" onClick={() => openItem(home, storage.slotIndex, storage.parentItemId, storage)}>Inspect storage</Button>
                        </div>
                        <div className="grid grid-cols-3 gap-2 border-t border-[var(--line)] p-3 sm:grid-cols-5 lg:grid-cols-6">
                          {Array.from({ length: storage.storageCapacity }, (_, slot) => {
                            const item = childBySlot.get(slot);
                            return <InventorySlot key={slot} slot={slot} item={item} canEdit={canUseHouse} canAdd={canAdd}
                              target={targetSlot === `${homeKey}:${storage.id}:${slot}`}
                              onOpen={() => openItem(home, slot, storage.id, item)}
                              onDropItem={(itemId) => moveItem(itemId, slot, storage.id, home)} />;
                          })}
                        </div>
                      </details>;
                    })}
                  </div>}
                </div>}
              </section>
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
              {itemModalCanManage && (
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
              {itemModalCanManage && (
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
                <div className="grid gap-2 sm:grid-cols-2">
                  {houseSettingsDraft.kind === 'house' && <label>
                    <span className="mb-1 block text-[10px] font-black uppercase text-[var(--muted)]">Home slots</span>
                    <NumberInput min={0} max={500} value={houseSettingsDraft.inventorySlots} onValueChange={(inventorySlots) => setHouseSettingsDraft({ ...houseSettingsDraft, inventorySlots })} />
                  </label>}
                  {houseSettingsDraft.kind === 'stable' && <label>
                    <span className="mb-1 block text-[10px] font-black uppercase text-[var(--muted)]">Stable slots</span>
                    <NumberInput min={0} max={200} value={houseSettingsDraft.stableSlots} onValueChange={(stableSlots) => setHouseSettingsDraft({ ...houseSettingsDraft, stableSlots })} />
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

    </Card>
  );
}
