'use client';

import { memo } from 'react';
import { Plus } from 'lucide-react';
import { ItemIcon } from '@/components/inventory/ItemIcon';
import { rarityClass } from '@/lib/utils/rarity';
import type { InventoryItem } from '@/lib/types';

export const InventorySlot = memo(function InventorySlot({
  slot,
  item,
  canEdit,
  canAdd,
  target,
  onOpen,
  onDropItem
}: {
  slot: number;
  item?: InventoryItem;
  canEdit: boolean;
  canAdd: boolean;
  target?: boolean;
  onOpen: () => void;
  onDropItem: (itemId: string) => void;
}) {
  return (
    <button
      type="button"
      draggable={Boolean(item && canEdit)}
      onDragStart={(event) => {
        if (!item) return;
        event.dataTransfer.setData('application/x-arta-item', item.id);
        event.dataTransfer.effectAllowed = 'move';
      }}
      onDragOver={(event) => {
        if (canEdit && Array.from(event.dataTransfer.types).includes('application/x-arta-item')) {
          event.preventDefault();
          event.dataTransfer.dropEffect = 'move';
        }
      }}
      onDrop={(event) => {
        if (!canEdit) return;
        const itemId = event.dataTransfer.getData('application/x-arta-item');
        if (itemId) {
          event.preventDefault();
          onDropItem(itemId);
        }
      }}
      onClick={() => {
        if (item || canAdd) onOpen();
      }}
      className={`inventory-slot relative flex min-h-[7.6rem] flex-col items-center justify-between rounded-2xl border p-2.5 text-center transition active:scale-95 sm:min-h-[7rem] ${
        item ? `${rarityClass(item.rarity)} ${item.spellImbue ? 'inventory-enchanted' : ''}` : 'border-dashed border-[var(--line)] bg-black/10'
      } ${target ? 'inventory-slot-target' : ''}`}
    >
      <span className="pointer-events-none absolute left-2 top-1.5 text-[9px] font-black text-[var(--muted)]">{slot + 1}</span>
      {item ? (
        <>
          <span className="inventory-slot-icon mt-2 text-[var(--brass)]"><ItemIcon type={item.type} size={17} /></span>
          <span className="inventory-item-name line-clamp-3 w-full rounded-xl bg-black/24 px-1.5 py-1 text-[11px] font-black leading-[0.9rem] shadow-inner">{item.name}</span>
          <span className="min-h-[1.25rem]">
            {item.quantity > 1 && <span className="rounded-full bg-black/45 px-2 py-0.5 text-[10px] font-black">x{item.quantity}</span>}
          </span>
        </>
      ) : canAdd ? <Plus className="text-[var(--muted)]" size={16} /> : null}
    </button>
  );
});
