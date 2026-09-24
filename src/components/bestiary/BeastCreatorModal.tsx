'use client';

import { useMemo, useState, type ReactNode } from 'react';
import { Check, Palette, PawPrint } from 'lucide-react';
import { Button } from '@/components/ui/Button';
import { ColorField, SelectField, TextAreaField, TextField } from '@/components/ui/Field';
import { Modal } from '@/components/ui/Modal';
import type { BestiaryCategoryRecord, BestiaryEntity } from '@/lib/types';

const ATTRIBUTE_FIELDS = [
  ['Strength', 'Strength', true],
  ['Accuracy', 'Accuracy', true],
  ['Intelligence', 'Intelligence', true],
  ['Vitality', 'Vitality', true],
  ['Recovery', 'Recovery', false],
  ['Mana Regen', 'Mana Regen', false],
  ['Charisma', 'Charisma', false],
  ['Wisdom / Cunning', 'Wisdom / Cunning', false],
  ['Perception', 'Perception', false],
  ['Alchemy', 'Alchemy', false],
  ['Stealth', 'Stealth', false],
  ['Agility', 'Agility', false]
] as const;

type BeastDraft = {
  name: string;
  category: string;
  newCategoryName: string;
  habitat: string;
  temperament: string;
  hp: string;
  mana: string;
  wildScore: string;
  damage: string;
  armor: string;
  magicResist: string;
  summary: string;
  details: string;
  tokenColor: string;
  tokenColorSecondary: string;
  useGradient: boolean;
  unlocked: boolean;
  attributes: Record<string, string>;
};

const EMPTY_DRAFT: BeastDraft = {
  name: '', category: '', newCategoryName: '', habitat: '', temperament: '', hp: '1', mana: '0', wildScore: '0',
  damage: '0', armor: '0', magicResist: '0', summary: '', details: '', tokenColor: '#7f514d',
  tokenColorSecondary: '#315f65', useGradient: false, unlocked: true,
  attributes: Object.fromEntries(ATTRIBUTE_FIELDS.map(([, key, important]) => [key, important ? '0' : '']))
};

function draftFromEntity(entity: BestiaryEntity | null | undefined, categories: BestiaryCategoryRecord[]): BeastDraft {
  if (!entity) return { ...EMPTY_DRAFT, attributes: { ...EMPTY_DRAFT.attributes }, category: categories[0]?.key ?? '__new__' };
  return {
    name: entity.name,
    category: entity.category,
    newCategoryName: '',
    habitat: entity.habitat,
    temperament: entity.temperament,
    hp: String(entity.hp),
    mana: String(entity.mana),
    wildScore: String(entity.wildScore),
    damage: entity.stats.Damage ?? '0',
    armor: entity.stats['Armor / Hide'] ?? entity.stats.Armor ?? '0',
    magicResist: entity.stats['Magic Resistance'] ?? entity.stats['Magic Resist'] ?? '0',
    summary: entity.summary,
    details: entity.details,
    tokenColor: entity.tokenColor || '#7f514d',
    tokenColorSecondary: entity.tokenColorSecondary || '#315f65',
    useGradient: Boolean(entity.tokenColorSecondary),
    unlocked: entity.unlocked,
    attributes: Object.fromEntries(ATTRIBUTE_FIELDS.map(([, key, important]) => {
      const value = entity.stats[key] ?? (key === 'Wisdom / Cunning' ? entity.stats['Wisdom/Cunning'] : undefined);
      return [key, value && (important || Number(value) !== 0) ? value : important ? '0' : ''];
    }))
  };
}

function FieldLabel({ children }: { children: ReactNode }) {
  return <span className="mb-1 block text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">{children}</span>;
}

export function BeastCreatorModal({
  categories,
  initialEntity,
  saving,
  onClose,
  onSave
}: {
  categories: BestiaryCategoryRecord[];
  initialEntity?: BestiaryEntity | null;
  saving: boolean;
  onClose: () => void;
  onSave: (entry: Record<string, unknown>) => Promise<boolean>;
}) {
  const [draft, setDraft] = useState<BeastDraft>(() => draftFromEntity(initialEntity, categories));
  const category = categories.find((entry) => entry.key === draft.category);
  const preview = useMemo(() => draft.useGradient
    ? `linear-gradient(135deg, ${draft.tokenColor} 0%, ${draft.tokenColorSecondary} 100%)`
    : draft.tokenColor, [draft.tokenColor, draft.tokenColorSecondary, draft.useGradient]);

  async function submit() {
    if (!draft.name.trim()) return;
    const controlledKeys = new Set(['HP', 'Mana', 'Mana Pool', 'Wild Score', 'Damage', 'Armor / Hide', 'Armor', 'Magic Resistance', 'Magic Resist', 'Magic Res', ...ATTRIBUTE_FIELDS.flatMap(([, key]) => key === 'Wisdom / Cunning' ? [key, 'Wisdom/Cunning'] : [key])]);
    const stats: Record<string, string> = Object.fromEntries(Object.entries(initialEntity?.stats ?? {}).filter(([key]) => !controlledKeys.has(key)));
    Object.assign(stats, {
      Damage: draft.damage || '0',
      'Armor / Hide': draft.armor || '0',
      'Magic Resistance': draft.magicResist || '0'
    });
    ATTRIBUTE_FIELDS.forEach(([, key, important]) => {
      const value = draft.attributes[key]?.trim();
      if (important || (value && Number(value) !== 0)) stats[key] = value || '0';
    });
    const saved = await onSave({
      name: draft.name.trim(),
      category: category?.key ?? draft.newCategoryName.trim().toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, ''),
      categoryName: category?.name ?? draft.newCategoryName.trim(),
      habitat: draft.habitat.trim(),
      temperament: draft.temperament.trim(),
      hp: Number(draft.hp || 1),
      mana: Number(draft.mana || 0),
      wildScore: Number(draft.wildScore || 0),
      summary: draft.summary.trim(),
      details: draft.details.trim(),
      stats,
      tokenColor: initialEntity && !initialEntity.tokenColor && !draft.useGradient && draft.tokenColor === '#7f514d' ? '' : draft.tokenColor,
      tokenColorSecondary: draft.useGradient ? draft.tokenColorSecondary : '',
      unlocked: draft.unlocked
    });
    if (saved) onClose();
  }

  return (
    <Modal title={initialEntity ? `Edit ${initialEntity.name}` : 'Create Bestiary Beast'} size="wide" onClose={onClose}>
      <div className="space-y-5 pb-2">
        <section className="rounded-2xl border border-[var(--line)] bg-black/15 p-4">
          <div className="mb-3 flex items-center gap-2"><PawPrint size={17} className="text-[var(--brass)]" /><h4 className="font-black">Identity and category</h4></div>
          <div className="grid gap-3 md:grid-cols-2">
            <label><FieldLabel>Beast name</FieldLabel><TextField value={draft.name} onChange={(event) => setDraft({ ...draft, name: event.target.value })} placeholder="Example: Ashfang Stalker" autoFocus /></label>
            <label><FieldLabel>Bestiary category</FieldLabel><SelectField value={draft.category} onChange={(event) => setDraft({ ...draft, category: event.target.value })}>{categories.map((entry) => <option key={entry.key} value={entry.key}>{entry.name}</option>)}<option value="__new__">Create a new category</option></SelectField></label>
            {draft.category === '__new__' && <label className="md:col-span-2"><FieldLabel>New category name</FieldLabel><TextField value={draft.newCategoryName} onChange={(event) => setDraft({ ...draft, newCategoryName: event.target.value })} placeholder="Example: Expedition Threats" /></label>}
            <label><FieldLabel>Habitat</FieldLabel><TextField value={draft.habitat} onChange={(event) => setDraft({ ...draft, habitat: event.target.value })} placeholder="Forest, ruins, mountains..." /></label>
            <label><FieldLabel>Temperament</FieldLabel><TextField value={draft.temperament} onChange={(event) => setDraft({ ...draft, temperament: event.target.value })} placeholder="Docile, territorial, hostile..." /></label>
          </div>
        </section>

        <section className="rounded-2xl border border-[var(--line)] bg-black/15 p-4">
          <h4 className="mb-3 font-black">Combat profile</h4>
          <div className="grid grid-cols-2 gap-3 md:grid-cols-3 lg:grid-cols-6">
            {([['HP', 'hp'], ['Mana', 'mana'], ['Wild score', 'wildScore'], ['Armor / Hide', 'armor'], ['Magic resist', 'magicResist']] as const).map(([label, key]) => (
              <label key={key}><FieldLabel>{label}</FieldLabel><TextField type="number" min={0} value={draft[key]} onChange={(event) => setDraft({ ...draft, [key]: event.target.value })} /></label>
            ))}
            <label><FieldLabel>Damage</FieldLabel><TextField value={draft.damage} onChange={(event) => setDraft({ ...draft, damage: event.target.value })} placeholder="12 or 2d6" /></label>
          </div>
        </section>

        <section className="rounded-2xl border border-[var(--line)] bg-black/15 p-4">
          <h4 className="mb-1 font-black">Attributes and skills</h4>
          <p className="mb-3 text-xs text-[var(--muted)]">Use positive or negative numbers exactly as they should appear on the battlefield sheet.</p>
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
            {ATTRIBUTE_FIELDS.map(([label, key, important]) => <label key={key}><FieldLabel>{label}{!important ? ' (optional)' : ''}</FieldLabel><TextField type="number" value={draft.attributes[key]} placeholder={!important ? 'Omitted if 0' : undefined} onChange={(event) => setDraft({ ...draft, attributes: { ...draft.attributes, [key]: event.target.value } })} /></label>)}
          </div>
        </section>

        <section className="rounded-2xl border border-[var(--line)] bg-black/15 p-4">
          <div className="mb-3 flex items-center gap-2"><Palette size={17} className="text-[var(--teal)]" /><h4 className="font-black">Battle token appearance</h4></div>
          <div className="grid gap-3 lg:grid-cols-[1fr_1fr_10rem]">
            <label><FieldLabel>Primary color</FieldLabel><ColorField value={draft.tokenColor} onChange={(event) => setDraft({ ...draft, tokenColor: event.target.value })} /></label>
            <div>
              <label className="mb-2 flex items-center gap-2 text-sm font-black"><input type="checkbox" checked={draft.useGradient} onChange={(event) => setDraft({ ...draft, useGradient: event.target.checked })} /> Add second color</label>
              {draft.useGradient && <ColorField value={draft.tokenColorSecondary} onChange={(event) => setDraft({ ...draft, tokenColorSecondary: event.target.value })} />}
            </div>
            <div className="grid min-h-24 place-items-center rounded-2xl border border-[var(--line)] bg-black/20"><span className="grid h-16 w-16 place-items-center rounded-[20px] border-2 border-white/30 text-2xl font-black text-white shadow-xl" style={{ background: preview }}>{draft.name.trim()[0]?.toUpperCase() ?? '?'}</span></div>
          </div>
        </section>

        <section className="rounded-2xl border border-[var(--line)] bg-black/15 p-4">
          <h4 className="mb-3 font-black">Bestiary description</h4>
          <div className="grid gap-3 md:grid-cols-2">
            <label><FieldLabel>Summary</FieldLabel><TextAreaField rows={5} value={draft.summary} onChange={(event) => setDraft({ ...draft, summary: event.target.value })} placeholder="Short overview shown near the top of its card." /></label>
            <label><FieldLabel>Details, abilities, and notes</FieldLabel><TextAreaField rows={5} value={draft.details} onChange={(event) => setDraft({ ...draft, details: event.target.value })} placeholder="Attacks, passives, behavior, or encounter notes." /></label>
          </div>
          <label className="mt-3 flex items-center gap-2 rounded-xl border border-[var(--line)] bg-black/15 p-3 text-sm font-black"><input type="checkbox" checked={draft.unlocked} onChange={(event) => setDraft({ ...draft, unlocked: event.target.checked })} /> Visible to players immediately</label>
        </section>

        <div className="sticky bottom-0 flex justify-end gap-2 border-t border-[var(--line)] bg-[var(--surface)] py-3">
          <Button variant="secondary" onClick={onClose}>Cancel</Button>
          <Button variant="teal" disabled={saving || !draft.name.trim() || (draft.category === '__new__' && !draft.newCategoryName.trim())} onClick={() => void submit()}><Check className="mr-2 inline" size={16} /> {initialEntity ? 'Save changes' : 'Create beast'}</Button>
        </div>
      </div>
    </Modal>
  );
}
