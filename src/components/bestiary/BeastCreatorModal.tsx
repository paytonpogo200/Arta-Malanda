'use client';

import { useMemo, useState, type ReactNode } from 'react';
import { Check, Palette, PawPrint } from 'lucide-react';
import { Button } from '@/components/ui/Button';
import { ColorField, SelectField, TextAreaField, TextField } from '@/components/ui/Field';
import { Modal } from '@/components/ui/Modal';
import type { BestiaryCategoryRecord } from '@/lib/types';

const ATTRIBUTE_FIELDS = [
  ['Strength', 'Strength'],
  ['Accuracy', 'Accuracy'],
  ['Intelligence', 'Intelligence'],
  ['Vitality', 'Vitality'],
  ['Recovery', 'Recovery'],
  ['Mana Regen', 'Mana Regen'],
  ['Charisma', 'Charisma'],
  ['Wisdom / Cunning', 'Wisdom / Cunning'],
  ['Perception', 'Perception'],
  ['Alchemy', 'Alchemy'],
  ['Stealth', 'Stealth'],
  ['Agility', 'Agility']
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
  attributes: Object.fromEntries(ATTRIBUTE_FIELDS.map(([, key]) => [key, '0']))
};

function FieldLabel({ children }: { children: ReactNode }) {
  return <span className="mb-1 block text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">{children}</span>;
}

export function BeastCreatorModal({
  categories,
  saving,
  onClose,
  onCreate
}: {
  categories: BestiaryCategoryRecord[];
  saving: boolean;
  onClose: () => void;
  onCreate: (entry: Record<string, unknown>) => Promise<boolean>;
}) {
  const [draft, setDraft] = useState<BeastDraft>(() => ({ ...EMPTY_DRAFT, category: categories[0]?.key ?? '__new__' }));
  const category = categories.find((entry) => entry.key === draft.category);
  const preview = useMemo(() => draft.useGradient
    ? `linear-gradient(135deg, ${draft.tokenColor} 0%, ${draft.tokenColorSecondary} 100%)`
    : draft.tokenColor, [draft.tokenColor, draft.tokenColorSecondary, draft.useGradient]);

  async function submit() {
    if (!draft.name.trim()) return;
    const stats: Record<string, string> = {
      Damage: draft.damage || '0',
      'Armor / Hide': draft.armor || '0',
      'Magic Resistance': draft.magicResist || '0'
    };
    ATTRIBUTE_FIELDS.forEach(([, key]) => { stats[key] = draft.attributes[key] || '0'; });
    const created = await onCreate({
      name: draft.name.trim(),
      category: category?.key ?? '',
      categoryName: category?.name ?? draft.newCategoryName.trim(),
      habitat: draft.habitat.trim(),
      temperament: draft.temperament.trim(),
      hp: Number(draft.hp || 1),
      mana: Number(draft.mana || 0),
      wildScore: Number(draft.wildScore || 0),
      summary: draft.summary.trim(),
      details: draft.details.trim(),
      stats,
      tokenColor: draft.tokenColor,
      tokenColorSecondary: draft.useGradient ? draft.tokenColorSecondary : '',
      unlocked: draft.unlocked
    });
    if (created) onClose();
  }

  return (
    <Modal title="Create Bestiary Beast" size="wide" onClose={onClose}>
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
            {ATTRIBUTE_FIELDS.map(([label, key]) => <label key={key}><FieldLabel>{label}</FieldLabel><TextField type="number" value={draft.attributes[key]} onChange={(event) => setDraft({ ...draft, attributes: { ...draft.attributes, [key]: event.target.value } })} /></label>)}
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
          <Button variant="teal" disabled={saving || !draft.name.trim() || (draft.category === '__new__' && !draft.newCategoryName.trim())} onClick={() => void submit()}><Check className="mr-2 inline" size={16} /> Create beast</Button>
        </div>
      </div>
    </Modal>
  );
}
