'use client';

import { useMemo } from 'react';
import { SelectField, TextAreaField, TextField } from '@/components/ui/Field';
import { NumberInput } from '@/components/ui/NumberInput';
import { ITEM_TYPES } from '@/features/inventory/data';
import {
  EDITABLE_MODIFIER_FIELDS,
  canManuallyEnchant,
  canManuallyEnhance,
  cleanModifiers,
  modifierEntries
} from '@/features/inventory/itemDetails';
import { rarityOptions } from '@/lib/utils/rarity';
import type { InventoryItem, ItemRarity, ItemType, LoadoutModifierKey, LoadoutModifiers, Spell } from '@/lib/types';

export type ItemDraft = {
  name: string;
  displayName: string;
  itemDescription: string;
  type: ItemType;
  rarity: ItemRarity;
  quantity: number;
  storageCapacity: number;
  enchantment: string;
  material: string;
  enhancementCount: number;
  isTwoHanded: boolean;
  isAccessory: boolean;
  modifiers: LoadoutModifiers;
  potionStrength: string;
  potionProperty: string;
  potionQuality: string;
};

export const EMPTY_ITEM_DRAFT: ItemDraft = {
  name: '',
  displayName: '',
  itemDescription: '',
  type: 'misc',
  rarity: 'Common',
  quantity: 1,
  storageCapacity: 0,
  enchantment: '',
  material: '',
  enhancementCount: 0,
  isTwoHanded: false,
  isAccessory: false,
  modifiers: {},
  potionStrength: '',
  potionProperty: '',
  potionQuality: ''
};

const POTION_STRENGTHS = ['Lesser', 'Greater', 'Greatest'];
const POTION_QUALITIES = ['Shoddy', 'Basic', 'Fine', 'Strong', 'Enriched'];
const POTION_PROPERTIES = [
  { key: 'Healing', label: 'Healing' },
  { key: 'Speed', label: 'Swiftness' },
  { key: 'Agility', label: 'Agility' },
  { key: 'Strength', label: 'Strength' },
  { key: 'Sorcery', label: 'Sorcery' },
  { key: 'Mana Regen', label: 'Mana' },
  { key: 'Luck', label: 'Luck' },
  { key: 'Antidote', label: 'Antidote' },
  { key: 'Warming', label: 'Warming' },
  { key: 'Cooling', label: 'Cooling' },
  { key: 'Night-Eye', label: 'Night-Eye' },
  { key: 'Thickskin', label: 'Thickskin' },
  { key: 'Clear-Mind', label: 'Clear-Mind' },
  { key: 'Wake-Up', label: 'Wake-Up' },
  { key: 'Clotting', label: 'Clotting' }
];

function normalizedItemName(name: string) {
  const clean = name.trim().toLowerCase();
  if (clean === 'glass flask' || clean === 'glass flasks' || clean === 'empty flasks') return 'empty flask';
  if (clean === 'mana recovery potion') return 'mana potion';
  return clean;
}

function isEmptyFlask(item: Pick<ItemDraft, 'name'> | Pick<InventoryItem, 'name'>) {
  return normalizedItemName(item.name) === 'empty flask';
}

function isArcaneNector(item: Pick<ItemDraft, 'name'> | Pick<InventoryItem, 'name'>) {
  return normalizedItemName(item.name) === 'arcane nector';
}

function itemSupportsLoadoutDetails(type: ItemType) {
  return type === 'weapon' || type === 'armor' || type === 'shield' || type === 'accessory' || type === 'pet';
}

function itemSupportsAccessoryModifiers(item: Pick<ItemDraft, 'type' | 'isAccessory'>) {
  return item.type === 'accessory' || item.isAccessory;
}

export function potionQualityCanApply(item: Pick<ItemDraft, 'name' | 'type' | 'potionProperty'>) {
  if (item.type !== 'potion' || isEmptyFlask(item) || isArcaneNector(item)) return false;
  const property = item.potionProperty || '';
  if (property === 'Healing' || property === 'Mana Regen') return false;
  const name = normalizedItemName(item.name);
  return !name.includes('healing potion') && !name.includes('mana potion');
}

export function draftFromInventoryItem(item: InventoryItem): ItemDraft {
  return {
    name: item.name,
    displayName: item.displayName ?? '',
    itemDescription: item.itemDescription ?? '',
    type: item.type,
    rarity: item.rarity,
    quantity: item.quantity,
    storageCapacity: item.storageCapacity,
    enchantment: item.enchantment ?? '',
    material: item.material ?? '',
    enhancementCount: item.enhancementCount,
    isTwoHanded: item.isTwoHanded,
    isAccessory: item.isAccessory,
    modifiers: cleanModifiers(item.modifiers),
    potionStrength: item.potionStrength ?? '',
    potionProperty: item.potionProperty ?? '',
    potionQuality: item.potionQuality ?? ''
  };
}

export function itemDraftPayload(draft: ItemDraft) {
  return {
    name: draft.name.trim(),
    type: draft.type,
    rarity: draft.rarity,
    quantity: draft.quantity,
    isStorage: draft.type === 'storage',
    storageCapacity: draft.type === 'storage' ? Math.max(1, draft.storageCapacity || 6) : 0,
    enchantment: draft.enchantment.trim() || null,
    material: draft.material.trim(),
    enhancementCount: draft.enhancementCount,
    isTwoHanded: draft.isTwoHanded,
    isAccessory: draft.isAccessory,
    modifiers: cleanModifiers(draft.modifiers),
    itemDescription: draft.itemDescription.trim(),
    potionStrength: draft.potionStrength,
    potionProperty: draft.potionProperty,
    potionQuality: potionQualityCanApply(draft) ? draft.potionQuality : ''
  };
}

export function ItemEditorFields({
  draft,
  spells,
  quantityStep,
  enhanceOpen,
  enhanceStat,
  onDraftChange,
  onEnhanceOpenChange,
  onEnhanceStatChange
}: {
  draft: ItemDraft;
  spells: Spell[];
  quantityStep: number;
  enhanceOpen: boolean;
  enhanceStat: LoadoutModifierKey;
  onDraftChange: (draft: ItemDraft) => void;
  onEnhanceOpenChange: (open: boolean) => void;
  onEnhanceStatChange: (stat: LoadoutModifierKey) => void;
}) {
  const sortedSpells = useMemo(() => [...spells].sort((a, b) => a.name.localeCompare(b.name)), [spells]);
  const modifierList = modifierEntries(draft.modifiers);
  const showForgeDetails = itemSupportsLoadoutDetails(draft.type) || Boolean(draft.enchantment.trim()) || draft.enhancementCount > 0 || modifierList.length > 0;
  const enchantable = canManuallyEnchant(draft) || Boolean(draft.enchantment.trim());
  const enhanceable = canManuallyEnhance(draft);
  const accessoryModifiers = itemSupportsAccessoryModifiers(draft);
  const legendaryWeapon = draft.type === 'weapon' && draft.rarity === 'Legendary';
  const hasCurrentCustomSpell = Boolean(draft.enchantment.trim()) && !sortedSpells.some((spell) => spell.name === draft.enchantment);

  function updateDraftModifier(key: LoadoutModifierKey, value: number) {
    onDraftChange({
      ...draft,
      modifiers: cleanModifiers({ ...draft.modifiers, [key]: value })
    });
  }

  function updateDraftEnchantment(enchantment: string) {
    onDraftChange({
      ...draft,
      enchantment,
      enhancementCount: enchantment.trim() ? 0 : draft.enhancementCount
    });
  }

  function confirmDraftEnhancement() {
    if (!canManuallyEnhance(draft) || draft.enhancementCount >= 3) return;
    const currentValue = Number(draft.modifiers[enhanceStat] ?? 0);
    onDraftChange({
      ...draft,
      modifiers: cleanModifiers({ ...draft.modifiers, [enhanceStat]: currentValue + 1 }),
      enhancementCount: Math.min(3, draft.enhancementCount + 1),
      enchantment: ''
    });
    onEnhanceOpenChange(false);
  }

  return (
    <>
      <TextField placeholder="Item name" value={draft.name} onChange={(event) => onDraftChange({ ...draft, name: event.target.value })} />
      <TextAreaField
        rows={10}
        className="min-h-56 resize-y leading-6"
        value={draft.itemDescription}
        onChange={(event) => onDraftChange({ ...draft, itemDescription: event.target.value })}
        placeholder="Inspection description"
      />
      <div className="grid gap-2 sm:grid-cols-3">
        <SelectField value={draft.type} onChange={(event) => onDraftChange({ ...draft, type: event.target.value as ItemType })}>{ITEM_TYPES.map((type) => <option key={type} value={type}>{type}</option>)}</SelectField>
        <SelectField value={draft.rarity} onChange={(event) => onDraftChange({ ...draft, rarity: event.target.value as ItemRarity })}>{rarityOptions.map((rarity) => <option key={rarity} value={rarity}>{rarity}</option>)}</SelectField>
        <NumberInput min={quantityStep} step={quantityStep} value={draft.quantity} onValueChange={(quantity) => onDraftChange({ ...draft, quantity })} />
      </div>
      {draft.type === 'storage' && <NumberInput aria-label="Storage capacity" min={1} value={draft.storageCapacity || 6} onValueChange={(storageCapacity) => onDraftChange({ ...draft, storageCapacity })} />}

      <label className="flex min-h-12 items-center gap-2 rounded-xl border border-[var(--line)] bg-black/15 px-3 text-sm font-black">
        <input type="checkbox" checked={draft.isAccessory} onChange={(event) => onDraftChange({ ...draft, isAccessory: event.target.checked })} />
        Mark as accessory
      </label>

      {legendaryWeapon && (
        <details className="rounded-2xl border border-[var(--brass)]/40 bg-[var(--brass)]/10">
          <summary className="cursor-pointer list-none p-3 font-black text-[var(--brass)]">Legendary weapon details</summary>
          <div className="grid gap-3 border-t border-[var(--line)] p-3">
            <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
              {EDITABLE_MODIFIER_FIELDS.map((field) => (
                <label key={field.key}>
                  <span className="mb-1 block text-[10px] font-black uppercase text-[var(--muted)]">{field.label}</span>
                  <NumberInput value={Number(draft.modifiers[field.key] ?? 0)} onValueChange={(value) => updateDraftModifier(field.key, value)} />
                </label>
              ))}
            </div>
          </div>
        </details>
      )}

      {accessoryModifiers && (
        <details open className="rounded-2xl border border-[var(--brass)]/40 bg-[var(--brass)]/10">
          <summary className="cursor-pointer list-none p-3 font-black text-[var(--brass)]">Accessory stat bonuses</summary>
          <div className="grid gap-3 border-t border-[var(--line)] p-3">
            <p className="text-xs font-bold leading-5 text-[var(--muted)]">
              These bonuses apply while the item is equipped in an accessory slot.
            </p>
            <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
              {EDITABLE_MODIFIER_FIELDS.map((field) => (
                <label key={field.key}>
                  <span className="mb-1 block text-[10px] font-black uppercase text-[var(--muted)]">{field.label}</span>
                  <NumberInput value={Number(draft.modifiers[field.key] ?? 0)} onValueChange={(value) => updateDraftModifier(field.key, value)} />
                </label>
              ))}
            </div>
          </div>
        </details>
      )}

      {draft.type === 'potion' && !isEmptyFlask(draft) && !isArcaneNector(draft) && (
        <div className="grid gap-2 rounded-2xl border border-[#56e2c2]/30 bg-[#56e2c2]/10 p-3">
          <p className="eyebrow text-[#56e2c2]">Potion details</p>
          <div className="grid gap-2 sm:grid-cols-3">
            <SelectField value={draft.potionStrength} onChange={(event) => onDraftChange({ ...draft, potionStrength: event.target.value })}>
              <option value="">Infer strength</option>
              {POTION_STRENGTHS.map((strength) => <option key={strength} value={strength}>{strength}</option>)}
            </SelectField>
            <SelectField value={draft.potionProperty} onChange={(event) => onDraftChange({ ...draft, potionProperty: event.target.value, potionQuality: event.target.value === 'Healing' || event.target.value === 'Mana Regen' ? '' : draft.potionQuality })}>
              <option value="">Infer property</option>
              {POTION_PROPERTIES.map((property) => <option key={property.key} value={property.key}>{property.label}</option>)}
            </SelectField>
            {potionQualityCanApply(draft) ? (
              <SelectField value={draft.potionQuality} onChange={(event) => onDraftChange({ ...draft, potionQuality: event.target.value })}>
                <option value="">No quality</option>
                {POTION_QUALITIES.map((quality) => <option key={quality} value={quality}>{quality}</option>)}
              </SelectField>
            ) : (
              <div className="rounded-xl border border-[var(--line)] bg-black/15 px-3 py-3 text-sm font-black text-[var(--muted)]">
                No quality
              </div>
            )}
          </div>
        </div>
      )}

      {draft.type === 'weapon' && (
        <label className="flex min-h-12 items-center gap-2 rounded-xl border border-[var(--line)] bg-black/15 px-3 text-sm font-black">
          <input type="checkbox" checked={draft.isTwoHanded} onChange={(event) => onDraftChange({ ...draft, isTwoHanded: event.target.checked })} />
          Two-handed weapon
        </label>
      )}

      {showForgeDetails && (
        <div className="grid gap-2 rounded-2xl border border-[var(--line)] bg-black/10 p-3">
          <p className="eyebrow">Arcane forge</p>
          {enchantable && (
            <label>
              <span className="mb-1 block text-[10px] font-black uppercase text-[var(--muted)]">Weapon enchantment</span>
              <SelectField
                value={hasCurrentCustomSpell ? '__custom__' : draft.enchantment}
                disabled={draft.enhancementCount > 0}
                onChange={(event) => updateDraftEnchantment(event.target.value === '__custom__' ? draft.enchantment : event.target.value)}
              >
                <option value="">No enchantment</option>
                {hasCurrentCustomSpell && <option value="__custom__">{draft.enchantment}</option>}
                {sortedSpells.map((spell) => <option key={spell.id} value={spell.name}>{spell.name}</option>)}
              </SelectField>
              {draft.enhancementCount > 0 && <span className="mt-1 block text-xs font-black text-[var(--red)]">Remove enhancements before adding an enchantment.</span>}
            </label>
          )}
          {enhanceable && (
            <details open={enhanceOpen} onToggle={(event) => onEnhanceOpenChange(event.currentTarget.open)} className="rounded-2xl border border-[var(--line)] bg-black/10">
              <summary className="cursor-pointer list-none p-3 font-black text-[var(--brass)]">Enhancement forge; {draft.enhancementCount}/3</summary>
              <div className="grid gap-2 border-t border-[var(--line)] p-3 sm:grid-cols-[1fr_auto]">
                <SelectField value={enhanceStat} onChange={(event) => onEnhanceStatChange(event.target.value as LoadoutModifierKey)}>
                  {EDITABLE_MODIFIER_FIELDS.map((field) => <option key={field.key} value={field.key}>{field.label}</option>)}
                </SelectField>
                <button
                  type="button"
                  className="rounded-xl border border-[var(--brass)] bg-[var(--brass)]/15 px-4 py-3 text-sm font-black text-[var(--brass)] disabled:opacity-45"
                  disabled={draft.enhancementCount >= 3}
                  onClick={confirmDraftEnhancement}
                >
                  Add +1
                </button>
              </div>
            </details>
          )}
          {modifierList.length > 0 && (
            <div className="flex flex-wrap gap-1.5">
              {modifierList.map((modifier) => (
                <span key={modifier.key} className="rounded-full bg-black/30 px-2 py-1 text-[10px] font-black uppercase text-[var(--teal)]">
                  {modifier.value > 0 ? '+' : ''}{modifier.value} {modifier.label}
                </span>
              ))}
            </div>
          )}
        </div>
      )}
    </>
  );
}
