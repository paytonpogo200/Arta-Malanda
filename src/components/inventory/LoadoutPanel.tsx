'use client';

import { memo, type DragEvent } from 'react';
import { PawPrint, Shield, Shirt, Sparkles, Sword } from 'lucide-react';
import { ItemIcon } from '@/components/inventory/ItemIcon';
import { acceptsLoadoutItem } from '@/features/inventory/data';
import { itemHasEnhancementVisual, modifierEntries, modifierText, modifierToneClass, spellForEnchantment } from '@/features/inventory/itemDetails';
import { rarityClass } from '@/lib/utils/rarity';
import { spellManaText } from '@/lib/utils/spells';
import type { InventoryItem, LoadoutSlot, Spell } from '@/lib/types';

const slots: { key: LoadoutSlot; label: string; icon: typeof Sword }[] = [
  { key: 'weapon', label: 'Weapon', icon: Sword },
  { key: 'armor', label: 'Armor', icon: Shirt },
  { key: 'shield', label: 'Shield', icon: Shield },
  { key: 'active-pet', label: 'Active pet', icon: PawPrint },
  { key: 'accessory-1', label: 'Accessory 1', icon: Sparkles },
  { key: 'accessory-2', label: 'Accessory 2', icon: Sparkles },
  { key: 'accessory-3', label: 'Accessory 3', icon: Sparkles },
  { key: 'accessory-4', label: 'Accessory 4', icon: Sparkles }
];

export const LoadoutPanel = memo(function LoadoutPanel({
  items,
  spells = [],
  canMove,
  onOpen,
  onEquip
}: {
  items: InventoryItem[];
  spells?: Spell[];
  canMove: boolean;
  onOpen: (item: InventoryItem) => void;
  onEquip: (itemId: string, loadoutSlot: LoadoutSlot | null) => void;
}) {
  return (
    <section>
      <div className="rule-title mb-3"><h3 className="text-sm font-black uppercase tracking-wider">Loadout</h3></div>
      <div className="grid grid-cols-1 gap-2 min-[390px]:grid-cols-2 sm:grid-cols-4">
        {slots.map(({ key, label, icon: Icon }) => {
          const item = items.find((entry) => entry.loadoutSlot === key);
          const enchantmentSpell = item ? spellForEnchantment(spells, item.enchantment) : null;
          const modifiers = item ? modifierEntries(item.modifiers) : [];
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
                if (!canMove || !dragged || !acceptsLoadoutItem(key, dragged.type)) return;
                event.preventDefault();
                onEquip(itemId, key);
              }}
              className={`min-h-28 rounded-2xl border p-3 ${item ? `${rarityClass(item.rarity)} ${item.enchantment ? 'inventory-enchanted' : ''} ${itemHasEnhancementVisual(item) ? 'inventory-enhanced' : ''}` : 'surface-soft'}`}
            >
              <div className="mb-2 flex items-center justify-between gap-2">
                <p className="text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">{label}</p>
                <Icon size={15} className="text-[var(--brass)]" />
              </div>
              {item ? (
                <button
                  type="button"
                  draggable={canMove}
                  onDragStart={(event) => {
                    event.dataTransfer.setData('application/x-arta-item', item.id);
                    event.dataTransfer.effectAllowed = 'move';
                  }}
                  onDoubleClick={() => canMove && onEquip(item.id, null)}
                  onClick={() => onOpen(item)}
                  className="relative z-10 flex w-full items-start gap-2 rounded-xl bg-black/18 p-2 text-left"
                >
                  <span className="text-[var(--brass)]"><ItemIcon type={item.type} size={17} /></span>
                  <span className="min-w-0 flex-1">
                    <span className="block text-sm font-black leading-4">{item.name}</span>
                    {item.enchantment && (
                      <span className="block truncate text-[10px] font-black uppercase text-[#56e2c2]">
                        {enchantmentSpell?.name ?? item.enchantment}{enchantmentSpell ? ` · ${spellManaText(enchantmentSpell)}` : ''}
                      </span>
                    )}
                    {modifiers.length > 0 && (
                      <span className="mt-1 flex flex-wrap gap-1">
                        {modifiers.map((modifier) => (
                          <span key={modifier.key} className={`rounded-full bg-black/30 px-1.5 py-0.5 text-[9px] font-black uppercase ${modifierToneClass(modifier.value)}`}>
                            {modifierText(modifier.value)} {modifier.label}
                          </span>
                        ))}
                      </span>
                    )}
                  </span>
                </button>
              ) : (
                <p className="text-xs leading-5 text-[var(--muted)]">Drop item here.</p>
              )}
            </div>
          );
        })}
      </div>
    </section>
  );
});
