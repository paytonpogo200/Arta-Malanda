'use client';

import { memo } from 'react';
import { Plus } from 'lucide-react';
import { ItemIcon } from '@/components/inventory/ItemIcon';
import { itemHasEnhancementVisual, spellBookVisualClass } from '@/features/inventory/itemDetails';
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
  const itemLabel = item?.displayName || item?.name || '';
  const nameClass = item && itemLabel.length > 28
    ? 'line-clamp-5 text-[9px] leading-[0.72rem]'
    : item && itemLabel.length > 18
      ? 'line-clamp-4 text-[10px] leading-[0.8rem]'
      : 'line-clamp-3 text-[11px] leading-[0.9rem]';

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
        item ? `${rarityClass(item.rarity)} ${spellBookVisualClass(item)} ${item.enchantment || item.runeName ? 'inventory-enchanted' : ''} ${itemHasEnhancementVisual(item) ? 'inventory-enhanced' : ''}` : 'border-dashed border-[var(--line)] bg-black/10'
      } ${target ? 'inventory-slot-target' : ''}`}
    >
      <span className="inventory-slot-number pointer-events-none absolute top-1.5 text-[9px] font-black text-[var(--muted)]">{slot + 1}</span>
      {item ? (
        <>
          <span className="inventory-slot-icon mt-2 text-[var(--brass)]"><ItemIcon type={item.type} size={17} /></span>
          <span className={`inventory-item-name w-full rounded-xl bg-black/24 px-1.5 py-1 font-black shadow-inner ${nameClass}`}>{itemLabel}</span>
          {item.type === 'pet' && item.displayName && (
            <span className="w-full truncate text-[9px] font-black uppercase tracking-wide text-[var(--muted)]">{item.name}</span>
          )}
          {item.type === 'spell book' && (
            <span className="w-full truncate text-[9px] font-black uppercase tracking-wide text-[var(--paper)]">Form {item.spellBookForm ?? 1}</span>
          )}
          {item.runeName && <span className="w-full truncate text-[9px] font-black uppercase tracking-wide text-[#56e2c2]">{item.runeName}</span>}
          <span className="min-h-[1.25rem]">
            {item.quantity > 1 && <span className="rounded-full bg-black/45 px-2 py-0.5 text-[10px] font-black">x{item.quantity}</span>}
          </span>
        </>
      ) : canAdd ? (
        <span className="inventory-empty-plus">
          <Plus size={18} />
        </span>
      ) : null}
    </button>
  );
});
