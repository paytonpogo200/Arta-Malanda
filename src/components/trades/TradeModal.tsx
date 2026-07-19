'use client';

import { useMemo, useState, type FormEvent } from 'react';
import { Loader2, Send } from 'lucide-react';
import { Button } from '@/components/ui/Button';
import { Modal } from '@/components/ui/Modal';
import { SelectField, TextAreaField } from '@/components/ui/Field';
import type { Character } from '@/lib/types';

type TradeModalProps = {
  target: Character;
  characters: Character[];
  profileId: string;
  onClose: () => void;
};

export function TradeModal({ target, characters, profileId, onClose }: TradeModalProps) {
  const ownedCharacters = useMemo(() => characters.filter((character) => character.ownerUserId === profileId && character.id !== target.id), [characters, profileId, target.id]);
  const [senderCharacterId, setSenderCharacterId] = useState(ownedCharacters[0]?.id ?? '');
  const [offerNote, setOfferNote] = useState('');
  const [requestNote, setRequestNote] = useState('');
  const [message, setMessage] = useState('');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  async function submit(event: FormEvent) {
    event.preventDefault();
    if (!senderCharacterId || saving) return;
    setSaving(true);
    setError('');

    try {
      const response = await fetch('/api/trades', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          senderCharacterId,
          targetCharacterId: target.id,
          offerNote,
          requestNote,
          message
        })
      });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.error ?? 'Trade could not be sent.');
      onClose();
    } catch (tradeError) {
      setError(tradeError instanceof Error ? tradeError.message : 'Trade could not be sent.');
    } finally {
      setSaving(false);
    }
  }

  return (
    <Modal title={`Trade with ${target.name}`} onClose={onClose}>
      <form onSubmit={submit} className="grid gap-3">
        {error && <div className="rounded-xl border border-[var(--red)]/40 bg-[var(--red)]/10 p-3 text-sm text-[var(--red)]">{error}</div>}

        <label>
          <span className="mb-1 block text-[10px] font-black uppercase tracking-wide text-[var(--muted)]">Offering as</span>
          <SelectField value={senderCharacterId} onChange={(event) => setSenderCharacterId(event.target.value)}>
            {ownedCharacters.map((character) => <option key={character.id} value={character.id}>{character.name}</option>)}
          </SelectField>
        </label>

        <label>
          <span className="mb-1 block text-[10px] font-black uppercase tracking-wide text-[var(--muted)]">You offer</span>
          <TextAreaField rows={4} value={offerNote} onChange={(event) => setOfferNote(event.target.value)} placeholder="Items, coin, favors, or terms offered." />
        </label>

        <label>
          <span className="mb-1 block text-[10px] font-black uppercase tracking-wide text-[var(--muted)]">You request</span>
          <TextAreaField rows={4} value={requestNote} onChange={(event) => setRequestNote(event.target.value)} placeholder="What you want in return." />
        </label>

        <label>
          <span className="mb-1 block text-[10px] font-black uppercase tracking-wide text-[var(--muted)]">Message</span>
          <TextAreaField rows={3} value={message} onChange={(event) => setMessage(event.target.value)} placeholder="Optional note to the player." />
        </label>

        <Button variant="primary" disabled={!senderCharacterId || saving} className="flex items-center justify-center gap-2">
          {saving ? <Loader2 size={16} className="animate-spin" /> : <Send size={16} />} Send offer
        </Button>
      </form>
    </Modal>
  );
}
