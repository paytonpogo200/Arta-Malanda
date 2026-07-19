'use client';

import { useCallback, useEffect, useMemo, useState, type FormEvent } from 'react';
import { Home, Loader2, PawPrint, Plus, RefreshCw } from 'lucide-react';
import { InventorySlot } from '@/components/inventory/InventorySlot';
import { Button } from '@/components/ui/Button';
import { Card } from '@/components/ui/Card';
import { SelectField, TextField } from '@/components/ui/Field';
import { Modal } from '@/components/ui/Modal';
import { NumberInput } from '@/components/ui/NumberInput';
import { normalizeHousePayload, PROPERTY_LOCATIONS, PROPERTY_TYPES } from '@/features/houses/data';
import { ITEM_TYPES } from '@/features/inventory/data';
import { rarityOptions } from '@/lib/utils/rarity';
import type { CampaignProperty, InventoryItem, ItemRarity, ItemType, PropertyLocation, PropertyType } from '@/lib/types';

type HousePanelProps = {
  ownerUserId: string | null;
  caretakerCharacterId: string;
  canManage: boolean;
  canAdd: boolean;
};

type ItemDraft = {
  name: string;
  type: ItemType;
  rarity: ItemRarity;
  quantity: number;
  storageCapacity: number;
  spellImbue: string;
};

type PropertyDraft = {
  name: string;
  type: PropertyType;
  location: PropertyLocation;
  isPet: boolean;
  slotIndex: number;
  storageCapacity: number;
};

const EMPTY_ITEM: ItemDraft = {
  name: '',
  type: 'misc',
  rarity: 'Common',
  quantity: 1,
  storageCapacity: 0,
  spellImbue: ''
};

const EMPTY_PROPERTY: PropertyDraft = {
  name: '',
  type: 'animal',
  location: 'at_house',
  isPet: false,
  slotIndex: 0,
  storageCapacity: 0
};

export function HousePanel({ ownerUserId, caretakerCharacterId, canManage, canAdd }: HousePanelProps) {
  const [items, setItems] = useState<InventoryItem[]>([]);
  const [properties, setProperties] = useState<CampaignProperty[]>([]);
  const [inventorySlots, setInventorySlots] = useState(50);
  const [propertySlots, setPropertySlots] = useState(10);
  const [loading, setLoading] = useState(Boolean(ownerUserId));
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [targetSlot, setTargetSlot] = useState<number | null>(null);
  const [itemModal, setItemModal] = useState<{ slot: number; item?: InventoryItem } | null>(null);
  const [propertyModal, setPropertyModal] = useState<CampaignProperty | 'new' | null>(null);
  const [itemDraft, setItemDraft] = useState<ItemDraft>(EMPTY_ITEM);
  const [propertyDraft, setPropertyDraft] = useState<PropertyDraft>(EMPTY_PROPERTY);
  const [dropQuantity, setDropQuantity] = useState(1);

  const itemBySlot = useMemo(() => new Map(items.map((item) => [item.slotIndex, item])), [items]);

  const loadHouse = useCallback(async () => {
    if (!ownerUserId) return;
    setLoading(true);
    setError('');

    try {
      const response = await fetch(`/api/houses/${ownerUserId}`, { cache: 'no-store' });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.error ?? 'House could not be loaded.');
      const normalized = normalizeHousePayload(payload);
      setItems(normalized.items);
      setProperties(normalized.properties);
      setInventorySlots(normalized.house?.inventorySlots ?? 50);
      setPropertySlots(normalized.house?.propertySlots ?? 10);
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : 'House could not be loaded.');
    } finally {
      setLoading(false);
    }
  }, [ownerUserId]);

  useEffect(() => {
    void loadHouse();
  }, [loadHouse]);

  if (!ownerUserId) {
    return null;
  }

  function openItem(slot: number, item?: InventoryItem) {
    if (!item && !canAdd) return;
    setItemModal({ slot, item });
    setItemDraft(item ? {
      name: item.name,
      type: item.type,
      rarity: item.rarity,
      quantity: item.quantity,
      storageCapacity: item.storageCapacity,
      spellImbue: item.spellImbue ?? ''
    } : EMPTY_ITEM);
    setDropQuantity(item?.quantity ?? 1);
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
      await loadHouse();
    } catch (actionError) {
      setError(actionError instanceof Error ? actionError.message : 'House action failed.');
    } finally {
      setSaving(false);
    }
  }

  async function addItem(event: FormEvent) {
    event.preventDefault();
    if (!ownerUserId || !itemModal || itemModal.item || !itemDraft.name.trim() || !canAdd) return;
    await requestHouseChange(`/api/houses/${ownerUserId}/items`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        ...itemDraft,
        slotIndex: itemModal.slot,
        isStorage: itemDraft.type === 'storage',
        storageCapacity: itemDraft.type === 'storage' ? Math.max(1, itemDraft.storageCapacity || 6) : 0,
        spellImbue: itemDraft.spellImbue.trim() || null
      })
    });
  }

  async function updateItem(event: FormEvent) {
    event.preventDefault();
    if (!itemModal?.item || !itemDraft.name.trim() || !canAdd) return;
    await requestHouseChange(`/api/houses/items/${itemModal.item.id}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        ...itemDraft,
        name: itemDraft.name.trim(),
        isStorage: itemDraft.type === 'storage',
        storageCapacity: itemDraft.type === 'storage' ? Math.max(1, itemDraft.storageCapacity || 6) : 0,
        spellImbue: itemDraft.spellImbue.trim() || null
      })
    });
  }

  async function moveItem(itemId: string, slotIndex: number) {
    if (!canManage) return;
    setTargetSlot(slotIndex);
    await requestHouseChange(`/api/houses/items/${itemId}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ slotIndex })
    });
    window.setTimeout(() => setTargetSlot(null), 120);
  }

  async function dropItem(item: InventoryItem) {
    if (!canManage) return;
    await requestHouseChange(`/api/houses/items/${item.id}?quantity=${Math.max(1, dropQuantity)}`, { method: 'DELETE' });
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

    if (!canManage) return;
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
        </div>
        <div className="flex gap-2">
          <Button variant="secondary" className="p-3" onClick={loadHouse} aria-label="Refresh house"><RefreshCw size={16} /></Button>
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
                    canEdit={canManage}
                    canAdd={canAdd}
                    target={targetSlot === slot}
                    onOpen={() => openItem(slot, item)}
                    onDropItem={(itemId) => moveItem(itemId, slot)}
                  />
                );
              })}
            </div>
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
        <Modal title={itemModal.item ? itemModal.item.name : 'Add house item'} onClose={() => setItemModal(null)}>
          {itemModal.item ? (
            <div className="space-y-3">
              <p className="rounded-xl border border-[var(--line)] bg-black/15 p-3 text-sm text-[var(--muted)]">{itemModal.item.type} · {itemModal.item.rarity} · Quantity {itemModal.item.quantity}</p>
              {canManage && (
                <div className="grid gap-2 sm:grid-cols-[1fr_auto]">
                  <NumberInput min={1} max={itemModal.item.quantity} value={dropQuantity} onValueChange={setDropQuantity} />
                  <Button variant="danger" onClick={() => dropItem(itemModal.item!)} disabled={saving}>Drop</Button>
                </div>
              )}
              {canAdd && (
                <form onSubmit={updateItem} className="grid gap-3 rounded-2xl border border-[var(--line)] bg-black/10 p-3">
                  <TextField value={itemDraft.name} onChange={(event) => setItemDraft({ ...itemDraft, name: event.target.value })} />
                  <div className="grid gap-2 sm:grid-cols-3">
                    <SelectField value={itemDraft.type} onChange={(event) => setItemDraft({ ...itemDraft, type: event.target.value as ItemType })}>{ITEM_TYPES.map((type) => <option key={type} value={type}>{type}</option>)}</SelectField>
                    <SelectField value={itemDraft.rarity} onChange={(event) => setItemDraft({ ...itemDraft, rarity: event.target.value as ItemRarity })}>{rarityOptions.map((rarity) => <option key={rarity} value={rarity}>{rarity}</option>)}</SelectField>
                    <NumberInput min={1} value={itemDraft.quantity} onValueChange={(quantity) => setItemDraft({ ...itemDraft, quantity })} />
                  </div>
                  <Button variant="primary" disabled={!itemDraft.name.trim() || saving}>Save item</Button>
                </form>
              )}
            </div>
          ) : (
            <form onSubmit={addItem} className="grid gap-3">
              <TextField autoFocus placeholder="Item name" value={itemDraft.name} onChange={(event) => setItemDraft({ ...itemDraft, name: event.target.value })} />
              <div className="grid gap-2 sm:grid-cols-3">
                <SelectField value={itemDraft.type} onChange={(event) => setItemDraft({ ...itemDraft, type: event.target.value as ItemType })}>{ITEM_TYPES.map((type) => <option key={type} value={type}>{type}</option>)}</SelectField>
                <SelectField value={itemDraft.rarity} onChange={(event) => setItemDraft({ ...itemDraft, rarity: event.target.value as ItemRarity })}>{rarityOptions.map((rarity) => <option key={rarity} value={rarity}>{rarity}</option>)}</SelectField>
                <NumberInput min={1} value={itemDraft.quantity} onValueChange={(quantity) => setItemDraft({ ...itemDraft, quantity })} />
              </div>
              <Button variant="primary" disabled={!itemDraft.name.trim() || saving}>Add item</Button>
            </form>
          )}
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
