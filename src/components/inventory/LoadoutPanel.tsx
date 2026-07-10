'use client';

import { memo, type DragEvent } from 'react';
import { PawPrint, Shield, Shirt, Sparkles, Sword } from 'lucide-react';
import { ItemIcon } from '@/components/inventory/ItemIcon';
import { useCampaignDispatch } from '@/features/campaign/CampaignProvider';
import { rarityClass } from '@/lib/utils/rarity';
import type { InventoryItem, LoadoutSlot } from '@/lib/types';

const slots: { key: LoadoutSlot; label: string; accepts: string[]; icon: typeof Sword }[] = [
  { key: 'weapon', label: 'Weapon', accepts: ['weapon'], icon: Sword },
  { key: 'armor', label: 'Armor', accepts: ['armor'], icon: Shirt },
  { key: 'shield', label: 'Shield', accepts: ['shield'], icon: Shield },
  { key: 'active-pet', label: 'Active pet', accepts: ['pet'], icon: PawPrint },
  { key: 'accessory-1', label: 'Accessory 1', accepts: ['accessory'], icon: Sparkles },
  { key: 'accessory-2', label: 'Accessory 2', accepts: ['accessory'], icon: Sparkles },
  { key: 'accessory-3', label: 'Accessory 3', accepts: ['accessory'], icon: Sparkles },
  { key: 'accessory-4', label: 'Accessory 4', accepts: ['accessory'], icon: Sparkles }
];

export const LoadoutPanel = memo(function LoadoutPanel({ items, canEdit }: { items: InventoryItem[]; canEdit: boolean }) {
  const dispatch = useCampaignDispatch();

  return (
    <section>
      <div className="rule-title mb-3"><h3 className="text-sm font-black uppercase tracking-wider">Loadout</h3></div>
      <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
        {slots.map(({ key, label, accepts, icon: Icon }) => {
          const item = items.find((entry) => entry.loadoutSlot === key);
          const acceptsDraggedItem = (event: DragEvent<HTMLDivElement>) => Array.from(event.dataTransfer.types).includes('application/x-arta-item');
          return (
            <div
              key={key}
              onDragOver={(event) => {
                if (acceptsDraggedItem(event)) event.preventDefault();
              }}
              onDrop={(event) => {
                const itemId = event.dataTransfer.getData('application/x-arta-item');
                const dragged = items.find((entry) => entry.id === itemId);
                if (!canEdit || !dragged || !accepts.includes(dragged.type)) return;
                event.preventDefault();
                dispatch({ type: 'inventory/equip', itemId, loadoutSlot: key });
              }}
              className={`min-h-28 rounded-xl border p-3 ${item ? `${rarityClass(item.rarity)} ${item.spellImbue ? 'inventory-enchanted' : ''}` : 'surface-soft'}`}
            >
              <div className="mb-2 flex items-center justify-between gap-2">
                <p className="text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">{label}</p>
                <Icon size={15} className="text-[var(--brass)]" />
              </div>
              {item ? (
                <button
                  type="button"
                  draggable={canEdit}
                  onDragStart={(event) => {
                    event.dataTransfer.setData('application/x-arta-item', item.id);
                    event.dataTransfer.effectAllowed = 'move';
                  }}
                  onDoubleClick={() => canEdit && dispatch({ type: 'inventory/equip', itemId: item.id, loadoutSlot: null })}
                  className="relative z-10 flex w-full items-center gap-2 text-left"
                >
                  <span className="text-[var(--brass)]"><ItemIcon type={item.type} /></span>
                  <span className="min-w-0 flex-1">
                    <span className="block truncate text-sm font-black">{item.name}</span>
                    {item.spellImbue && <span className="block truncate text-[10px] font-black uppercase text-[#56e2c2]">{item.spellImbue}</span>}
                  </span>
                </button>
              ) : (
                <p className="text-xs leading-5 text-[var(--muted)]">Drop {accepts.join('/')} here.</p>
              )}
            </div>
          );
        })}
      </div>
    </section>
  );
});
