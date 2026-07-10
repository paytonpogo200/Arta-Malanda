'use client';

import { useMemo, useState, type FormEvent } from 'react';
import { PackageOpen } from 'lucide-react';
import { InventorySlot } from '@/components/inventory/InventorySlot';
import { LoadoutPanel } from '@/components/inventory/LoadoutPanel';
import { Button } from '@/components/ui/Button';
import { Card } from '@/components/ui/Card';
import { SelectField, TextField } from '@/components/ui/Field';
import { Modal } from '@/components/ui/Modal';
import { NumberInput } from '@/components/ui/NumberInput';
import { useCampaignDispatch, useCampaignState } from '@/features/campaign/CampaignProvider';
import { rarityOptions } from '@/lib/utils/rarity';
import type { Character, InventoryItem, ItemRarity, ItemType } from '@/lib/types';

const itemTypes: ItemType[] = ['weapon', 'armor', 'shield', 'pet', 'accessory', 'storage', 'ore', 'potion', 'food', 'plant', 'fabric', 'tool', 'quest', 'misc'];

export function InventoryPanel({ character, canEdit }: { character: Character; canEdit: boolean }) {
  const state = useCampaignState();
  const dispatch = useCampaignDispatch();
  const [targetSlot, setTargetSlot] = useState<number | null>(null);
  const [modal, setModal] = useState<{ slot: number; item?: InventoryItem } | null>(null);
  const [draft, setDraft] = useState({ name: '', type: 'misc' as ItemType, rarity: 'Common' as ItemRarity, quantity: 1 });

  const characterItems = useMemo(() => state.items.filter((item) => item.characterId === character.id), [state.items, character.id]);
  const mainItems = useMemo(() => characterItems.filter((item) => item.parentItemId === null && item.loadoutSlot === null), [characterItems]);
  const itemBySlot = useMemo(() => new Map(mainItems.map((item) => [item.slotIndex, item])), [mainItems]);
  const storageItems = useMemo(() => characterItems.filter((item) => item.isStorage), [characterItems]);

  function openSlot(slot: number, item?: InventoryItem) {
    setModal({ slot, item });
    setDraft({
      name: item?.name ?? '',
      type: item?.type ?? 'misc',
      rarity: item?.rarity ?? 'Common',
      quantity: item?.quantity ?? 1
    });
  }

  function addItem(event: FormEvent) {
    event.preventDefault();
    if (!modal || modal.item || !draft.name.trim()) return;
    dispatch({
      type: 'inventory/add',
      item: {
        characterId: character.id,
        parentItemId: null,
        name: draft.name.trim(),
        type: draft.type,
        rarity: draft.rarity,
        quantity: Math.max(1, draft.quantity),
        slotIndex: modal.slot,
        loadoutSlot: null,
        isStorage: draft.type === 'storage',
        storageCapacity: draft.type === 'storage' ? 6 : 0,
        modifiers: {}
      }
    });
    setModal(null);
  }

  function moveItem(itemId: string, slot: number) {
    setTargetSlot(slot);
    dispatch({ type: 'inventory/move', itemId, slotIndex: slot, parentItemId: null });
    window.setTimeout(() => setTargetSlot(null), 120);
  }

  return (
    <Card>
      <LoadoutPanel items={characterItems} canEdit={canEdit} />

      <div className="mt-5 rule-title mb-3"><h3 className="text-sm font-black uppercase tracking-wider">Inventory</h3></div>
      <div className="grid grid-cols-3 gap-2 sm:grid-cols-5 lg:grid-cols-6">
        {Array.from({ length: character.inventorySlots }, (_, slot) => {
          const item = itemBySlot.get(slot);
          return (
            <InventorySlot
              key={slot}
              slot={slot}
              item={item}
              canEdit={canEdit}
              target={targetSlot === slot}
              onOpen={() => openSlot(slot, item)}
              onDropItem={(itemId) => moveItem(itemId, slot)}
            />
          );
        })}
      </div>

      {storageItems.length > 0 && (
        <div className="mt-5 space-y-2">
          <div className="rule-title mb-3"><h3 className="text-sm font-black uppercase tracking-wider">Additional Storage</h3></div>
          {storageItems.map((storage) => (
            <details key={storage.id} className="rounded-2xl border border-[#d1a85b2f] bg-black/15">
              <summary className="flex cursor-pointer list-none items-center justify-between gap-3 p-3">
                <span className="flex items-center gap-2 font-black"><PackageOpen size={16} className="text-[var(--brass)]" /> {storage.name}</span>
                <span className="text-xs text-[var(--muted)]">{storage.storageCapacity} slots</span>
              </summary>
              <div className="border-t border-[var(--line)] p-3 text-sm text-[var(--muted)]">Container slot rendering is reserved for the storage phase; the structure is already separate.</div>
            </details>
          ))}
        </div>
      )}

      {modal && (
        <Modal title={modal.item ? modal.item.name : 'Add item'} onClose={() => setModal(null)}>
          {modal.item ? (
            <div className="space-y-3">
              <p className="rounded-xl border border-[var(--line)] bg-black/15 p-3 text-sm text-[var(--muted)]">{modal.item.type} · {modal.item.rarity} · Quantity {modal.item.quantity}</p>
              {canEdit && <Button variant="teal" onClick={() => { dispatch({ type: 'inventory/equip', itemId: modal.item!.id, loadoutSlot: modal.item!.type === 'weapon' ? 'weapon' : modal.item!.type === 'armor' ? 'armor' : modal.item!.type === 'shield' ? 'shield' : modal.item!.type === 'pet' ? 'active-pet' : modal.item!.type === 'accessory' ? 'accessory-1' : null }); setModal(null); }}>Equip if possible</Button>}
            </div>
          ) : (
            <form onSubmit={addItem} className="grid gap-3">
              <TextField autoFocus placeholder="Item name" value={draft.name} onChange={(event) => setDraft({ ...draft, name: event.target.value })} />
              <div className="grid gap-2 sm:grid-cols-3">
                <SelectField value={draft.type} onChange={(event) => setDraft({ ...draft, type: event.target.value as ItemType })}>{itemTypes.map((type) => <option key={type} value={type}>{type}</option>)}</SelectField>
                <SelectField value={draft.rarity} onChange={(event) => setDraft({ ...draft, rarity: event.target.value as ItemRarity })}>{rarityOptions.map((rarity) => <option key={rarity} value={rarity}>{rarity}</option>)}</SelectField>
                <NumberInput min={1} value={draft.quantity} onValueChange={(quantity) => setDraft({ ...draft, quantity })} />
              </div>
              <Button variant="primary" disabled={!draft.name.trim()}>Add item</Button>
            </form>
          )}
        </Modal>
      )}
    </Card>
  );
}
