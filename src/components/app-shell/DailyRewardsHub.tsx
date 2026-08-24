'use client';

import { useEffect, useMemo, useState } from 'react';
import { CalendarDays, CheckCircle2, Coins, Loader2, PackageCheck, Save, Search, Settings, X } from 'lucide-react';
import { createPortal } from 'react-dom';
import { ItemIcon } from '@/components/inventory/ItemIcon';
import { Button } from '@/components/ui/Button';
import { SelectField, TextField } from '@/components/ui/Field';
import { NumberInput } from '@/components/ui/NumberInput';
import { matchesCatalogNameSearch } from '@/features/catalog/search';
import { CURRENCY_SYSTEMS, normalizeCurrencySystemKey } from '@/features/cities/data';
import { normalizeDailyRewardsPayload, type DailyRewardEntry, type DailyRewardKind, type DailyRewardsPayload } from '@/features/daily-rewards/data';
import type { Character, ItemCatalogEntry, Profile } from '@/lib/types';
import { rarityClass } from '@/lib/utils/rarity';

type DailyRewardsHubProps = {
  profile: Profile;
  available: boolean;
  onRefresh: () => void;
};

type RewardDraft = {
  date: string;
  rewardKind: DailyRewardKind;
  itemCatalogId: string;
  currencyUnitId: string;
  quantity: number;
};

const EMPTY_PAYLOAD: DailyRewardsPayload = {
  today: '',
  currentWeekStart: '',
  nextWeekStart: '',
  available: false,
  rewards: [],
  characters: [],
  catalog: [],
  currencyUnits: []
};

function rewardDraftFromEntry(entry: DailyRewardEntry): RewardDraft {
  return {
    date: entry.date,
    rewardKind: entry.rewardKind,
    itemCatalogId: entry.item?.id ?? '',
    currencyUnitId: entry.currency?.id ?? '',
    quantity: entry.quantity || 1
  };
}

function rewardLabel(entry: Pick<DailyRewardEntry, 'rewardKind' | 'item' | 'currency' | 'quantity'>) {
  if (entry.rewardKind === 'item' && entry.item) return `${entry.item.name}${entry.quantity > 1 ? ` x${entry.quantity}` : ''}`;
  if (entry.rewardKind === 'currency' && entry.currency) {
    const amount = Math.max(0, Math.floor(entry.quantity));
    return `${amount} ${amount === 1 ? entry.currency.name : `${entry.currency.name}s`}`;
  }
  return 'No item scheduled';
}

function draftPreview(draft: RewardDraft, catalog: ItemCatalogEntry[], payload: DailyRewardsPayload): DailyRewardEntry {
  const item = catalog.find((entry) => entry.id === draft.itemCatalogId) ?? null;
  const currency = payload.currencyUnits.find((entry) => entry.id === draft.currencyUnitId) ?? null;
  return {
    date: draft.date,
    dayOfWeek: 0,
    dayName: '',
    weekOffset: 0,
    scheduleId: null,
    rewardKind: draft.rewardKind,
    quantity: draft.quantity,
    item,
    currency,
    status: 'upcoming',
    available: false
  };
}

function RewardVisual({ entry, compact = false }: { entry: Pick<DailyRewardEntry, 'rewardKind' | 'item' | 'currency' | 'quantity'>; compact?: boolean }) {
  if (entry.rewardKind === 'currency' && entry.currency) {
    return (
      <div className={`relative grid ${compact ? 'min-h-[4.6rem]' : 'min-h-[6.5rem]'} place-items-center rounded-2xl border border-[var(--brass)]/55 bg-[radial-gradient(circle_at_30%_10%,rgba(245,180,76,0.25),rgba(0,0,0,0.22))] p-3 text-center`}>
        <Coins className="text-[var(--brass)]" size={compact ? 20 : 28} />
        <div className="mt-2 text-xs font-black leading-5 text-[var(--paper)]">{rewardLabel(entry)}</div>
      </div>
    );
  }

  if (entry.rewardKind === 'item' && entry.item) {
    return (
      <div className={`relative grid ${compact ? 'min-h-[4.6rem]' : 'min-h-[6.5rem]'} rounded-2xl border bg-black/20 p-3 ${rarityClass(entry.item.rarity)}`}>
        <div className="flex items-start gap-3">
          <span className="grid h-10 w-10 shrink-0 place-items-center rounded-xl border border-white/15 bg-black/25"><ItemIcon type={entry.item.type} size={20} /></span>
          <span className="min-w-0">
            <span className="block break-words text-sm font-black">{entry.item.name}</span>
            <span className="mt-1 block text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">{entry.item.rarity} - {entry.item.type}</span>
            {entry.quantity > 1 && <span className="mt-2 inline-block rounded-full border border-white/15 bg-black/25 px-2 py-1 text-xs font-black">x{entry.quantity}</span>}
          </span>
        </div>
      </div>
    );
  }

  return (
    <div className={`grid ${compact ? 'min-h-[4.6rem]' : 'min-h-[6.5rem]'} place-items-center rounded-2xl border border-dashed border-[var(--line)] bg-black/10 p-3 text-center text-xs font-black uppercase tracking-wider text-[var(--muted)]`}>
      No item scheduled
    </div>
  );
}

function statusStamp(status: DailyRewardEntry['status']) {
  if (status === 'received') return { label: 'Received', className: 'border-[var(--teal)] bg-[var(--teal)] text-black shadow-[0_0_24px_rgba(43,214,196,0.45)]' };
  if (status === 'missed') return { label: 'Missed', className: 'border-[var(--red)] bg-[var(--red)] text-white shadow-[0_0_24px_rgba(255,106,92,0.45)]' };
  return null;
}

export function DailyRewardsHub({ profile, available, onRefresh }: DailyRewardsHubProps) {
  const [open, setOpen] = useState(false);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [payload, setPayload] = useState<DailyRewardsPayload>(EMPTY_PAYLOAD);
  const [drafts, setDrafts] = useState<Record<string, RewardDraft>>({});
  const [claimEntry, setClaimEntry] = useState<DailyRewardEntry | null>(null);
  const [claimCharacterId, setClaimCharacterId] = useState('');
  const [catalogSearch, setCatalogSearch] = useState('');
  const [choosingItemDate, setChoosingItemDate] = useState('');
  const [busy, setBusy] = useState('');
  const [error, setError] = useState('');
  const isDm = profile.role === 'dm';

  const currentWeekRewards = useMemo(() => payload.rewards.filter((entry) => entry.weekOffset === 0), [payload.rewards]);
  const settingsRewards = useMemo(() => payload.rewards, [payload.rewards]);
  const filteredCatalog = useMemo(() => {
    const query = catalogSearch.trim();
    const source = query ? payload.catalog.filter((item) => matchesCatalogNameSearch(item, query)) : payload.catalog;
    return source.slice().sort((a, b) => a.name.localeCompare(b.name)).slice(0, 100);
  }, [catalogSearch, payload.catalog]);

  async function loadRewards() {
    setError('');
    try {
      const response = await fetch('/api/daily-rewards', { cache: 'no-store' });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(body.error ?? 'Daily rewards could not be loaded.');
      const normalized = normalizeDailyRewardsPayload(body);
      setPayload(normalized);
      setDrafts(Object.fromEntries(normalized.rewards.map((entry) => [entry.date, rewardDraftFromEntry(entry)])));
      const availableEntry = normalized.rewards.find((entry) => entry.available);
      setClaimCharacterId(normalized.characters[0]?.id ?? '');
      if (claimEntry && !availableEntry) setClaimEntry(null);
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : 'Daily rewards could not be loaded.');
    }
  }

  useEffect(() => {
    if (!open) return;
    void loadRewards();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open]);

  async function saveSettings() {
    setBusy('settings');
    setError('');
    try {
      const response = await fetch('/api/daily-rewards', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          rewards: settingsRewards.map((entry) => drafts[entry.date] ?? rewardDraftFromEntry(entry))
        })
      });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(body.error ?? 'Daily rewards could not be saved.');
      const normalized = normalizeDailyRewardsPayload(body);
      setPayload(normalized);
      setDrafts(Object.fromEntries(normalized.rewards.map((entry) => [entry.date, rewardDraftFromEntry(entry)])));
      setSettingsOpen(false);
      onRefresh();
    } catch (saveError) {
      setError(saveError instanceof Error ? saveError.message : 'Daily rewards could not be saved.');
    } finally {
      setBusy('');
    }
  }

  async function claimReward() {
    if (!claimEntry || !claimCharacterId) return;
    setBusy('claim');
    setError('');
    try {
      const response = await fetch('/api/daily-rewards/claim', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ date: claimEntry.date, characterId: claimCharacterId })
      });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(body.error ?? 'Daily reward could not be claimed.');
      const normalized = normalizeDailyRewardsPayload(body);
      setPayload(normalized);
      setDrafts(Object.fromEntries(normalized.rewards.map((entry) => [entry.date, rewardDraftFromEntry(entry)])));
      setClaimEntry(null);
      onRefresh();
    } catch (claimError) {
      setError(claimError instanceof Error ? claimError.message : 'Daily reward could not be claimed.');
    } finally {
      setBusy('');
    }
  }

  function updateDraft(date: string, patch: Partial<RewardDraft>) {
    setDrafts((current) => {
      const base = current[date] ?? {
        date,
        rewardKind: 'none' as DailyRewardKind,
        itemCatalogId: '',
        currencyUnitId: '',
        quantity: 1
      };
      return { ...current, [date]: { ...base, ...patch } };
    });
  }

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="relative rounded-xl border border-[var(--line)] bg-black/20 p-3 text-[var(--muted)] transition active:scale-95"
        aria-label="Open daily rewards"
      >
        <CalendarDays size={18} />
        {available && (
          <span className="absolute -right-1 -top-1 h-3.5 w-3.5 rounded-full border-2 border-[#141915] bg-[var(--brass)] shadow-[0_0_12px_rgba(245,180,76,0.8)]" />
        )}
      </button>

      {open && typeof document !== 'undefined' && createPortal(
        <div className="modal-backdrop" role="dialog" aria-modal="true" aria-label="Daily Efforts">
          <section className="modal-panel surface flex max-h-[calc(100dvh-var(--bottom-nav-space)-1rem)] w-[min(96vw,52rem)] flex-col overflow-hidden rounded-2xl p-4 sm:p-5">
            <div className="mb-4 flex items-start justify-between gap-3">
              <div>
                <p className="eyebrow">Rewards</p>
                <h2 className="mt-1 text-2xl font-black">Daily Efforts</h2>
              </div>
              <div className="flex gap-2">
                {isDm && (
                  <button
                    type="button"
                    onClick={() => setSettingsOpen((value) => !value)}
                    className="rounded-xl border border-[var(--line)] bg-black/20 p-3 text-[var(--muted)]"
                    aria-label="Daily reward settings"
                  >
                    <Settings size={18} />
                  </button>
                )}
                <button
                  type="button"
                  onClick={() => setOpen(false)}
                  className="rounded-xl border border-[var(--line)] bg-black/20 p-3 text-[var(--muted)]"
                  aria-label="Close daily rewards"
                >
                  <X size={18} />
                </button>
              </div>
            </div>

            {error && <div className="mb-3 rounded-xl border border-[var(--red)]/40 bg-[var(--red)]/10 p-3 text-sm text-[var(--red)]">{error}</div>}

            <div className="modal-body thin-scrollbar min-h-0 flex-1 overflow-y-auto pr-1">
              {!settingsOpen ? (
                <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
                  {currentWeekRewards.map((entry) => {
                    const stamp = statusStamp(entry.status);
                    const dimmed = entry.status === 'upcoming' || entry.status === 'empty' || entry.status === 'received' || entry.status === 'missed';
                    return (
                      <button
                        key={entry.date}
                        type="button"
                        disabled={!entry.available}
                        onClick={() => {
                          setClaimEntry(entry);
                          setClaimCharacterId(payload.characters[0]?.id ?? '');
                        }}
                        className={`relative rounded-2xl border p-3 text-left transition ${entry.available ? 'border-[var(--brass)] bg-[var(--brass)]/12 shadow-[0_0_24px_rgba(245,180,76,0.18)] hover:border-[var(--brass)]' : 'border-[var(--line)] bg-black/10'} ${dimmed ? 'opacity-55' : ''}`}
                      >
                        <div className="mb-2 flex items-center justify-between gap-2">
                          <div>
                            <p className="text-[10px] font-black uppercase tracking-[0.18em] text-[var(--brass)]">{entry.dayName}</p>
                            <p className="text-xs font-bold text-[var(--muted)]">{entry.date}</p>
                          </div>
                          {entry.available && <span className="rounded-full bg-[var(--brass)] px-2 py-1 text-[10px] font-black uppercase tracking-wide text-black">Claim</span>}
                        </div>
                        <div className={entry.available ? '' : 'opacity-55 grayscale-[0.25]'}>
                          <RewardVisual entry={entry} />
                        </div>
                        {stamp && (
                          <span className={`absolute left-1/2 top-1/2 z-10 -translate-x-1/2 -translate-y-1/2 rotate-[-10deg] rounded-xl border-2 px-4 py-2 text-base font-black uppercase tracking-[0.18em] ${stamp.className}`}>
                            {stamp.label}
                          </span>
                        )}
                      </button>
                    );
                  })}
                </div>
              ) : (
                <div className="grid gap-4">
                  <div className="rounded-2xl border border-[var(--line)] bg-black/15 p-3">
                    <p className="eyebrow">Dungeon Master</p>
                    <h3 className="mt-1 text-xl font-black">Reward Schedule</h3>
                    <p className="mt-1 text-sm font-bold leading-6 text-[var(--muted)]">Set this week and next week now, so Sunday rolls over cleanly.</p>
                  </div>
                  {[0, 1].map((weekOffset) => (
                    <div key={weekOffset} className="grid gap-2">
                      <div className="rule-title"><h3 className="text-sm font-black uppercase tracking-wider">{weekOffset === 0 ? 'This Week' : 'Next Week'}</h3></div>
                      <div className="grid gap-3">
                        {settingsRewards.filter((entry) => entry.weekOffset === weekOffset).map((entry) => {
                          const draft = drafts[entry.date] ?? rewardDraftFromEntry(entry);
                          const preview = draftPreview(draft, payload.catalog, payload);
                          return (
                            <div key={entry.date} className="grid gap-3 rounded-2xl border border-[var(--line)] bg-black/15 p-3 lg:grid-cols-[11rem_1fr]">
                              <div>
                                <p className="text-[10px] font-black uppercase tracking-[0.18em] text-[var(--brass)]">{entry.dayName}</p>
                                <p className="mt-1 text-sm font-black">{entry.date}</p>
                                <div className="mt-3"><RewardVisual entry={preview} compact /></div>
                              </div>
                              <div className="grid gap-2 sm:grid-cols-[10rem_1fr_9rem]">
                                <SelectField value={draft.rewardKind} onChange={(event) => updateDraft(entry.date, { rewardKind: event.target.value as DailyRewardKind })}>
                                  <option value="none">No reward</option>
                                  <option value="item">Item</option>
                                  <option value="currency">Currency</option>
                                </SelectField>
                                {draft.rewardKind === 'item' ? (
                                  <button
                                    type="button"
                                    onClick={() => {
                                      setChoosingItemDate(entry.date);
                                      setCatalogSearch('');
                                    }}
                                    className="rounded-xl border border-[var(--line)] bg-black/20 px-3 py-2 text-left font-black transition hover:border-[var(--brass)]/60"
                                  >
                                    {preview.item ? preview.item.name : 'Choose item'}
                                  </button>
                                ) : draft.rewardKind === 'currency' ? (
                                  <SelectField value={draft.currencyUnitId} onChange={(event) => updateDraft(entry.date, { currencyUnitId: event.target.value })}>
                                    <option value="">Choose currency</option>
                                    {payload.currencyUnits.map((unit) => (
                                      <option key={unit.id} value={unit.id}>{CURRENCY_SYSTEMS[normalizeCurrencySystemKey(unit.systemKey)].label} - {unit.name}</option>
                                    ))}
                                  </SelectField>
                                ) : (
                                  <div className="rounded-xl border border-dashed border-[var(--line)] bg-black/10 px-3 py-2 text-sm font-bold text-[var(--muted)]">No item scheduled</div>
                                )}
                                <NumberInput min={draft.rewardKind === 'none' ? 0 : 1} step={draft.rewardKind === 'item' && preview.item?.quantityStep === 0.5 ? 0.5 : 1} value={draft.rewardKind === 'none' ? 0 : draft.quantity} onValueChange={(quantity) => updateDraft(entry.date, { quantity })} disabled={draft.rewardKind === 'none'} />
                              </div>
                            </div>
                          );
                        })}
                      </div>
                    </div>
                  ))}
                  <Button variant="primary" onClick={saveSettings} disabled={busy === 'settings'}>
                    {busy === 'settings' ? <Loader2 className="mr-2 inline animate-spin" size={15} /> : <Save className="mr-2 inline" size={15} />} Save rewards
                  </Button>
                </div>
              )}
            </div>

            {claimEntry && (
              <div className="mt-4 rounded-2xl border border-[var(--brass)]/45 bg-black/25 p-3">
                <p className="eyebrow">Claim Reward</p>
                <div className="mt-3 grid gap-3 sm:grid-cols-[1fr_1fr_auto] sm:items-end">
                  <RewardVisual entry={claimEntry} compact />
                  <label>
                    <span className="mb-1 block text-[10px] font-black uppercase tracking-wider text-[var(--muted)]">Receive with</span>
                    <SelectField value={claimCharacterId} onChange={(event) => setClaimCharacterId(event.target.value)}>
                      {payload.characters.map((character: Character) => (
                        <option key={character.id} value={character.id}>{character.name} - {character.className}</option>
                      ))}
                    </SelectField>
                  </label>
                  <Button variant="teal" onClick={claimReward} disabled={!claimCharacterId || busy === 'claim'}>
                    {busy === 'claim' ? <Loader2 className="mr-2 inline animate-spin" size={15} /> : <PackageCheck className="mr-2 inline" size={15} />} Claim
                  </Button>
                </div>
              </div>
            )}
          </section>

          {choosingItemDate && (
            <div className="modal-backdrop z-[80]" role="dialog" aria-modal="true" aria-label="Choose reward item">
              <section className="modal-panel surface flex max-h-[calc(100dvh-var(--bottom-nav-space)-1rem)] w-[min(94vw,42rem)] flex-col overflow-hidden rounded-2xl p-4 sm:p-5">
                <div className="mb-4 flex items-center justify-between gap-3">
                  <div>
                    <p className="eyebrow">Reward Item</p>
                    <h3 className="mt-1 text-xl font-black">Choose Item</h3>
                  </div>
                  <button type="button" onClick={() => setChoosingItemDate('')} className="rounded-xl border border-[var(--line)] bg-black/20 p-3 text-[var(--muted)]" aria-label="Close item picker"><X size={18} /></button>
                </div>
                <label className="relative mb-3 block">
                  <span className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-[var(--muted)]"><Search size={17} /></span>
                  <TextField className="pl-10" value={catalogSearch} onChange={(event) => setCatalogSearch(event.target.value)} placeholder="Search item names" autoFocus />
                </label>
                <div className="thin-scrollbar grid min-h-0 flex-1 gap-2 overflow-y-auto pr-1 sm:grid-cols-2">
                  {filteredCatalog.map((item) => (
                    <button
                      key={item.id}
                      type="button"
                      onClick={() => {
                        updateDraft(choosingItemDate, { rewardKind: 'item', itemCatalogId: item.id, quantity: Math.max(1, item.quantityStep) });
                        setChoosingItemDate('');
                      }}
                      className="flex min-h-[4.75rem] items-center gap-3 rounded-xl border border-[var(--line)] bg-black/20 p-3 text-left transition hover:border-[var(--brass)]/60"
                    >
                      <span className={`grid h-11 w-11 shrink-0 place-items-center rounded-xl border bg-black/25 ${rarityClass(item.rarity)}`}><ItemIcon type={item.type} size={21} /></span>
                      <span className="min-w-0 flex-1">
                        <span className="block break-words font-black">{item.name}</span>
                        <span className="mt-1 block text-xs font-bold text-[var(--muted)]">{item.rarity} - {item.type}</span>
                      </span>
                      <CheckCircle2 size={17} className="shrink-0 text-[var(--brass)]" />
                    </button>
                  ))}
                  {!filteredCatalog.length && <div className="rounded-xl border border-[var(--line)] bg-black/20 p-4 text-sm font-bold text-[var(--muted)] sm:col-span-2">No catalog items match that search.</div>}
                </div>
              </section>
            </div>
          )}
        </div>,
        document.body
      )}
    </>
  );
}
