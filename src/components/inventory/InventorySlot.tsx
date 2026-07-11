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
      className={`inventory-slot relative flex aspect-square min-h-24 flex-col items-center justify-center rounded-xl border p-2 text-center transition active:scale-95 sm:min-h-20 ${
        item ? `${rarityClass(item.rarity)} ${item.spellImbue ? 'inventory-enchanted' : ''}` : 'border-dashed border-[var(--line)] bg-black/10'
      } ${target ? 'inventory-slot-target' : ''}`}
    >
      <span className="pointer-events-none absolute left-2 top-1.5 text-[9px] font-black text-[var(--muted)]">{slot + 1}</span>
      {item ? (
        <>
          <span className="mb-1 text-[var(--brass)]"><ItemIcon type={item.type} /></span>
          <span className="inventory-item-name line-clamp-2 text-xs font-black leading-4">{item.name}</span>
          {item.quantity > 1 && <span className="mt-1 rounded-full bg-black/40 px-1.5 text-[10px] font-black">x{item.quantity}</span>}
        </>
      ) : canAdd ? <Plus className="text-[var(--muted)]" size={16} /> : null}
    </button>
  );
});
