'use client';

import { useCallback, useEffect, useMemo, useState, type FormEvent } from 'react';
import { Home, Loader2, Lock, PawPrint, Plus, RefreshCw, Unlock, Users } from 'lucide-react';
import { EMPTY_ITEM_DRAFT, ItemEditorFields, draftFromInventoryItem, itemDraftPayload, type ItemDraft } from '@/components/inventory/ItemEditorFields';
import { InventorySlot } from '@/components/inventory/InventorySlot';
import { Button } from '@/components/ui/Button';
import { Card } from '@/components/ui/Card';
import { SelectField, TextField } from '@/components/ui/Field';
import { Modal } from '@/components/ui/Modal';
import { NumberInput } from '@/components/ui/NumberInput';
import { normalizeUpdateAssetsPayload } from '@/features/assets/data';
import type { CampaignProfile } from '@/features/characters/data';
import { normalizeHousePayload, PROPERTY_LOCATIONS, PROPERTY_TYPES } from '@/features/houses/data';
import { quantityStepForItem } from '@/features/inventory/data';
import { useDragAutoScroll } from '@/hooks/useDragAutoScroll';
import { useLiveRefresh } from '@/hooks/useLiveRefresh';
import type { CampaignProperty, Character, InventoryItem, LoadoutModifierKey, PropertyLocation, PropertyType, Spell } from '@/lib/types';

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

const STABLE_SLOT_OFFSET = 45;

export function HousePanel({ ownerUserId, caretakerCharacterId, viewerUserId, profiles = [], characters = [], canManage, canAdd, onCharacterInventoryChanged }: HousePanelProps) {
  const [items, setItems] = useState<InventoryItem[]>([]);
  const [properties, setProperties] = useState<CampaignProperty[]>([]);
  const [houseAccess, setHouseAccess] = useState({ owner: false, dm: false, house: false, stable: false });
  const [permissions, setPermissions] = useState<Record<string, { house: boolean; stable: boolean }>>({});
  const [permissionsOpen, setPermissionsOpen] = useState(false);
  const [inventorySlots, setInventorySlots] = useState(45);
  const [stableSlots, setStableSlots] = useState(5);
  const [propertySlots, setPropertySlots] = useState(10);
  const [houseLocked, setHouseLocked] = useState(false);
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
  useDragAutoScroll();

  const stableItems = useMemo(() => items.filter((item) => (
    sameContainer(item, null)
    && item.type === 'pet'
    && item.slotIndex >= STABLE_SLOT_OFFSET
    && item.slotIndex < STABLE_SLOT_OFFSET + stableSlots
  )), [items, stableSlots]);
  const stableItemIds = useMemo(() => new Set(stableItems.map((item) => item.id)), [stableItems]);
  const mainItems = useMemo(() => items.filter((item) => sameContainer(item, null) && !item.isStorage && !stableItemIds.has(item.id)), [items, stableItemIds]);
  const itemBySlot = useMemo(() => new Map(mainItems.map((item) => [item.slotIndex, item])), [mainItems]);
  const stableItemBySlot = useMemo(() => new Map(stableItems.map((item) => [item.slotIndex, item])), [stableItems]);
  const storageItems = useMemo(() => items.filter((item) => item.isStorage), [items]);
  const canManageHouse = canManage || houseAccess.house;
  const canManageStable = canManage || houseAccess.stable;
  const canManageAny = canManageHouse || canManageStable;
  const canEditPermissions = canAdd || houseAccess.owner;
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

  const loadHouse = useCallback(async (showLoading = true) => {
    if (!ownerUserId) return;
    if (showLoading) setLoading(true);
    setError('');

    try {
      const response = await fetch(`/api/houses/${ownerUserId}`, { cache: 'no-store' });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.error ?? 'House could not be loaded.');
      const normalized = normalizeHousePayload(payload);
      setItems(normalized.items);
      setProperties(normalized.properties);
      setInventorySlots(normalized.house?.inventorySlots ?? 45);
      setStableSlots(normalized.house?.stableSlots ?? 5);
      setPropertySlots(normalized.house?.propertySlots ?? 10);
      setHouseLocked(Boolean(normalized.house?.locked));
      setHouseAccess(normalized.access);
      setPermissions(Object.fromEntries(normalized.permissions.map((entry) => [entry.granteeUserId, { house: entry.house, stable: entry.stable }])));
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : 'House could not be loaded.');
    } finally {
      if (showLoading) setLoading(false);
    }
  }, [ownerUserId]);

  useEffect(() => {
    void loadHouse();
  }, [loadHouse]);

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
    if (!ownerUserId || !canAdd) return;
    await requestHouseChange(`/api/houses/${ownerUserId}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ locked: !houseLocked })
    });
  }

  async function addItem(event: FormEvent) {
    event.preventDefault();
    if (!ownerUserId || !itemModal || itemModal.item || !itemDraft.name.trim() || !canAdd) return;
    if (itemModal.parentItemId === null && itemModal.slot >= STABLE_SLOT_OFFSET && itemDraft.type !== 'pet') {
      setError('Only animals can be placed in stable slots.');
      return;
    }
    if (itemDraft.type === 'pet' && (itemModal.parentItemId !== null || itemModal.slot < STABLE_SLOT_OFFSET)) {
      setError('Animals can only be placed in stable slots.');
      return;
    }
    await requestHouseChange(`/api/houses/${ownerUserId}/items`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        ...itemDraftPayload(itemDraft),
        parentItemId: itemModal.parentItemId,
        slotIndex: itemModal.slot
      })
    });
  }

  async function updateItem(event: FormEvent) {
    event.preventDefault();
    if (!itemModal?.item || !itemDraft.name.trim() || !canAdd) return;
    if (itemModal.parentItemId === null && itemModal.slot >= STABLE_SLOT_OFFSET && itemDraft.type !== 'pet') {
      setError('Only animals can be placed in stable slots.');
      return;
    }
    if (itemDraft.type === 'pet' && (itemModal.parentItemId !== null || itemModal.slot < STABLE_SLOT_OFFSET)) {
      setError('Animals can only be placed in stable slots.');
      return;
    }
    await requestHouseChange(`/api/houses/items/${itemModal.item.id}`, {
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
    if (!canManage) return;
    const movingHouseItem = items.find((item) => item.id === itemId);
    if (movingHouseItem && sameContainer(movingHouseItem, parentItemId) && movingHouseItem.slotIndex === slotIndex) return;
    if (movingHouseItem?.type === 'pet' && (parentItemId !== null || slotIndex < STABLE_SLOT_OFFSET)) {
      setError('Animals can only be placed in stable slots.');
      return;
    }
    if (parentItemId === null && slotIndex >= STABLE_SLOT_OFFSET) {
      if (movingHouseItem && movingHouseItem.type !== 'pet') {
        setError('Only animals can be placed in stable slots.');
        return;
      }
      if (slotIndex >= STABLE_SLOT_OFFSET + stableSlots) {
        setError('That stable slot does not exist.');
        return;
      }
    }

    setTargetSlot(`${parentItemId ?? 'main'}:${slotIndex}`);
    const existingHouseItem = items.some((item) => item.id === itemId);
    if (existingHouseItem) {
      await requestHouseChange(`/api/houses/items/${itemId}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ slotIndex, parentItemId })
      });
    } else {
      await requestHouseChange(`/api/inventory/items/${itemId}/send-house`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ slotIndex, parentItemId })
      });
      onCharacterInventoryChanged?.();
    }
    window.setTimeout(() => setTargetSlot(null), 120);
  }

  async function savePetDisplayName(event: FormEvent) {
    event.preventDefault();
    if (!itemModal?.item || itemModal.item.type !== 'pet' || !canManageAny) return;
    await requestHouseChange(`/api/houses/items/${itemModal.item.id}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ displayName: itemDraft.displayName.trim() || null })
    });
  }

  async function dropItem(item: InventoryItem) {
    if (!canManageAny) return;
    await requestHouseChange(`/api/houses/items/${item.id}?quantity=${Math.max(quantityStepForItem(item), dropQuantity)}`, { method: 'DELETE' });
  }

  async function takeItem(item: InventoryItem) {
    if (!canManageAny) return;
    const characterId = takeTargetCharacterId || caretakerCharacterId;
    if (!characterId) {
      setError('Choose a character to receive this item.');
      return;
    }
    const moved = await requestHouseChange(`/api/houses/items/${item.id}/take`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ characterId })
    });
    if (moved) onCharacterInventoryChanged?.();
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
          permissions: Object.entries(permissions).map(([granteeUserId, access]) => ({ granteeUserId, ...access }))
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
        <div>
          <p className="eyebrow">Calostrynn</p>
          <h3 className="mt-1 flex items-center gap-2 text-xl font-black"><Home size={19} className="text-[var(--brass)]" /> House</h3>
          {houseLocked && <p className="mt-1 text-xs font-black uppercase tracking-wide text-[var(--red)]">Locked by DM</p>}
        </div>
        <div className="flex gap-2">
          <Button variant="secondary" className="p-3" onClick={() => void loadHouse()} aria-label="Refresh house"><RefreshCw size={16} /></Button>
          {canAdd && (
            <Button variant={houseLocked ? 'danger' : 'teal'} className="p-3" onClick={toggleHouseLock} aria-label={houseLocked ? 'Unlock house' : 'Lock house'}>
              {houseLocked ? <Lock size={16} /> : <Unlock size={16} />}
            </Button>
          )}
          {canEditPermissions && (
            <Button variant="secondary" className="p-3" onClick={() => setPermissionsOpen(true)} aria-label="House permissions">
              <Users size={16} />
            </Button>
          )}
          {canAdd && <Button variant="primary" className="p-3" onClick={() => openProperty('new')} aria-label="Add property"><Plus size={16} /></Button>}
        </div>
      </div>

      {error && <div className="mb-3 rounded-2xl border border-[var(--red)]/40 bg-[var(--red)]/10 p-3 text-sm text-[var(--red)]">{error}</div>}

      {loading ? (
        <div className="grid h-32 place-items-center rounded-2xl border border-[var(--line)] bg-black/10 text-[var(--muted)]">
          <Loader2 className="animate-spin" />
        </div>
      ) : (
        <div className="space-y-5">
          <section>
            <div className="rule-title mb-3"><h3 className="text-sm font-black uppercase tracking-wider">House inventory</h3></div>
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
                    target={targetSlot === `main:${slot}`}
                    onOpen={() => openItem(slot, null, item)}
                    onDropItem={(itemId) => moveItem(itemId, slot, null)}
                  />
                );
              })}
            </div>
            <div className="mt-5">
              <div className="rule-title mb-3">
                <h3 className="flex items-center gap-2 text-sm font-black uppercase tracking-wider">
                  <PawPrint size={16} className="text-[var(--brass)]" />
                  Stable
                </h3>
              </div>
              <p className="mb-3 text-xs font-black uppercase tracking-wide text-[var(--muted)]">{stableItems.length}/{stableSlots} animals housed</p>
              <div className="grid grid-cols-2 gap-2 min-[430px]:grid-cols-3 sm:grid-cols-5 lg:grid-cols-5">
                {Array.from({ length: stableSlots }, (_, slot) => {
                  const actualSlot = STABLE_SLOT_OFFSET + slot;
                  const item = stableItemBySlot.get(actualSlot);
                  return (
                    <InventorySlot
                      key={actualSlot}
                      slot={slot}
                      item={item}
                      canEdit={canManageStable}
                      canAdd={canAdd}
                      target={targetSlot === `main:${actualSlot}`}
                      onOpen={() => openItem(actualSlot, null, item)}
                      onDropItem={(itemId) => moveItem(itemId, actualSlot, null)}
                    />
                  );
                })}
              </div>
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

          <section>
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
          </section>
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
                  <label className="flex items-center gap-2 text-sm font-black">
                    <input
                      type="checkbox"
                      checked={access.house}
                      onChange={(event) => setPermissions((current) => ({ ...current, [entry.id]: { ...(current[entry.id] ?? access), house: event.target.checked } }))}
                    />
                    House
                  </label>
                  <label className="flex items-center gap-2 text-sm font-black">
                    <input
                      type="checkbox"
                      checked={access.stable}
                      onChange={(event) => setPermissions((current) => ({ ...current, [entry.id]: { ...(current[entry.id] ?? access), stable: event.target.checked } }))}
                    />
                    Stable
                  </label>
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
