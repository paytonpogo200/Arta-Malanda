'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { ArrowLeftRight, Check, Clock3, Coins, Handshake, History, Inbox, Loader2, PackagePlus, Search, Send, ShieldCheck, Store, X } from 'lucide-react';
import { ItemIcon } from '@/components/inventory/ItemIcon';
import { Button } from '@/components/ui/Button';
import { Card, SoftCard } from '@/components/ui/Card';
import { TextAreaField, TextField } from '@/components/ui/Field';
import { Modal } from '@/components/ui/Modal';
import { NumberInput } from '@/components/ui/NumberInput';
import { normalizeTradingPostPayload, type TradingPostCurrency, type TradingPostItemSnapshot, type TradingPostListing, type TradingPostOffer, type TradingPostPayload } from '@/features/trading-post/data';
import { useLiveRefresh } from '@/hooks/useLiveRefresh';
import { quantityStepForItem } from '@/features/inventory/data';
import type { City, InventoryItem, ShopVendor } from '@/lib/types';
import { rarityClass } from '@/lib/utils/rarity';

type ActionConfirmation = {
  title: string;
  body: string;
  confirmLabel: string;
  variant: 'primary' | 'danger' | 'teal';
  run: () => Promise<void>;
};

const EMPTY_POST: TradingPostPayload = {
  vendor: null,
  characters: [],
  selectedCharacterId: '',
  inventory: [],
  wallet: [],
  activeListings: [],
  myListings: [],
  pendingReview: [],
  offersReceived: [],
  offersSent: []
};

function formatQuantity(value: number) {
  return Number.isInteger(value) ? String(value) : value.toFixed(1).replace(/\.0$/, '');
}

function formatTimestamp(value: string) {
  if (!value) return '';
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? '' : date.toLocaleString([], { dateStyle: 'medium', timeStyle: 'short' });
}

function statusLabel(status: string) {
  if (status === 'pending_approval') return 'Pending Shopkeeper Approval';
  return status.replaceAll('_', ' ').replace(/\b\w/g, (letter) => letter.toUpperCase());
}

function statusClass(status: string) {
  if (status === 'active' || status === 'accepted' || status === 'completed') return 'border-[var(--teal)]/50 bg-[var(--teal)]/12 text-[var(--teal)]';
  if (status === 'pending' || status === 'pending_approval') return 'border-[var(--brass)]/50 bg-[var(--brass)]/12 text-[var(--brass)]';
  if (status === 'declined' || status === 'removed') return 'border-[var(--red)]/50 bg-[var(--red)]/12 text-[var(--red)]';
  return 'border-[var(--line)] bg-black/20 text-[var(--muted)]';
}

function itemTitle(item: Pick<TradingPostItemSnapshot, 'name' | 'displayName'> | Pick<InventoryItem, 'name' | 'displayName'>) {
  return item.displayName || item.name;
}

function ItemTile({ item, quantity, selected = false, onClick, footer }: {
  item: TradingPostItemSnapshot | InventoryItem;
  quantity: number;
  selected?: boolean;
  onClick?: () => void;
  footer?: React.ReactNode;
}) {
  const content = (
    <>
      <div className="flex items-start gap-3">
        <span className="grid h-11 w-11 shrink-0 place-items-center rounded-xl border border-white/15 bg-black/20 text-[var(--brass)]">
          <ItemIcon type={item.type} size={21} />
        </span>
        <span className="min-w-0 flex-1">
          <span className="block break-words font-black leading-tight">{itemTitle(item)}</span>
          <span className="mt-1 block text-[11px] font-bold uppercase tracking-wide text-[var(--muted)]">{item.rarity} {item.type}</span>
        </span>
        <span className="rounded-lg border border-white/10 bg-black/25 px-2 py-1 text-xs font-black">x{formatQuantity(quantity)}</span>
      </div>
      {'itemDescription' in item && item.itemDescription && <p className="mt-3 line-clamp-2 text-xs leading-5 text-[var(--muted)]">{item.itemDescription}</p>}
      {'description' in item && item.description && <p className="mt-3 line-clamp-2 text-xs leading-5 text-[var(--muted)]">{item.description}</p>}
      {footer && <div className="mt-3">{footer}</div>}
    </>
  );
  const className = `min-w-0 rounded-xl border p-3 text-left ${rarityClass(item.rarity)} ${selected ? 'ring-2 ring-[var(--teal)] ring-offset-2 ring-offset-[#15110f]' : ''}`;
  return onClick ? (
    <div
      role="button"
      tabIndex={0}
      className={`${className} cursor-pointer transition hover:-translate-y-0.5`}
      onClick={onClick}
      onKeyDown={(event) => {
        if (event.key === 'Enter' || event.key === ' ') {
          event.preventDefault();
          onClick();
        }
      }}
    >{content}</div>
  ) : <div className={className}>{content}</div>;
}

function CurrencySummary({ currency }: { currency: TradingPostCurrency[] }) {
  if (!currency.length) return null;
  return (
    <div className="flex flex-wrap gap-2">
      {currency.map((entry) => (
        <span key={entry.unitId} className="inline-flex items-center gap-1 rounded-lg border border-[var(--brass)]/35 bg-[var(--brass)]/10 px-2 py-1 text-xs font-black text-[var(--brass)]">
          <Coins size={12} /> {entry.amount} {entry.name}{entry.amount === 1 ? '' : 's'}
        </span>
      ))}
    </div>
  );
}

function ListingCard({ listing, own, disabled, canRemove, onOffer, onRemove }: {
  listing: TradingPostListing;
  own: boolean;
  disabled: boolean;
  canRemove: boolean;
  onOffer: () => void;
  onRemove: () => void;
}) {
  return (
    <article className="grid gap-4 rounded-2xl border border-[var(--line)] bg-black/15 p-4 sm:grid-cols-[minmax(0,1fr)_auto] sm:items-center">
      <div className="flex min-w-0 items-start gap-3">
        <span className={`grid h-12 w-12 shrink-0 place-items-center rounded-xl border ${rarityClass(listing.item.rarity)}`}><ItemIcon type={listing.item.type} size={23} /></span>
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <h4 className="break-words text-lg font-black">{itemTitle(listing.item)}</h4>
            <span className={`rounded-lg border px-2 py-1 text-[10px] font-black uppercase tracking-wide ${statusClass(listing.status)}`}>{statusLabel(listing.status)}</span>
          </div>
          <p className="mt-1 text-sm font-bold text-[var(--muted)]">x{formatQuantity(listing.quantity)} · offered by {listing.sellerPlayerName} as {listing.sellerCharacterName}</p>
          {listing.item.description && <p className="mt-2 line-clamp-2 text-sm leading-6 text-[var(--muted)]">{listing.item.description}</p>}
          <p className="mt-2 text-xs font-black uppercase tracking-wide text-[var(--brass)]">{listing.offerCount} pending offer{listing.offerCount === 1 ? '' : 's'}</p>
        </div>
      </div>
      <div className="grid gap-2">
        <Button variant={own ? 'secondary' : 'teal'} disabled={disabled || own} onClick={onOffer}>
          <Handshake className="mr-2 inline" size={15} /> {own ? 'Your Listing' : 'Propose Trade'}
        </Button>
        {canRemove && <Button variant="danger" className="py-2 text-xs" onClick={onRemove}>Shopkeeper Remove</Button>}
      </div>
    </article>
  );
}

function OfferContents({ offer }: { offer: TradingPostOffer }) {
  return (
    <div className="grid gap-3">
      {offer.items.length > 0 && (
        <div className="grid gap-2 sm:grid-cols-2">
          {offer.items.map((item, index) => <ItemTile key={`${item.itemId ?? item.name}-${index}`} item={item} quantity={item.quantity} />)}
        </div>
      )}
      <CurrencySummary currency={offer.currency} />
      {!offer.items.length && !offer.currency.length && <p className="text-sm text-[var(--muted)]">No value remains recorded for this offer.</p>}
    </div>
  );
}

export function TradingPostPanel({ vendor, city, selectedCharacterId, canUseService }: {
  vendor: ShopVendor;
  city: City;
  selectedCharacterId: string;
  canUseService: boolean;
}) {
  const [post, setPost] = useState<TradingPostPayload>(EMPTY_POST);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState('');
  const [error, setError] = useState('');
  const [inventorySearch, setInventorySearch] = useState('');
  const [listingStep, setListingStep] = useState<'closed' | 'choose' | 'review'>('closed');
  const [listingItemId, setListingItemId] = useState('');
  const [listingQuantity, setListingQuantity] = useState(1);
  const [offerListing, setOfferListing] = useState<TradingPostListing | null>(null);
  const [offerStep, setOfferStep] = useState<'build' | 'confirm'>('build');
  const [offerItems, setOfferItems] = useState<Record<string, number>>({});
  const [offerCurrency, setOfferCurrency] = useState<Record<string, number>>({});
  const [offerMessage, setOfferMessage] = useState('');
  const [reviewNote, setReviewNote] = useState<Record<string, string>>({});
  const [confirmation, setConfirmation] = useState<ActionConfirmation | null>(null);

  const loadPost = useCallback(async (quiet = false) => {
    if (!vendor.id) return;
    if (!quiet) setLoading(true);
    try {
      const params = new URLSearchParams({ vendorId: vendor.id });
      if (selectedCharacterId) params.set('characterId', selectedCharacterId);
      const response = await fetch(`/api/cities/trading-post?${params}`, { cache: 'no-store' });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.error ?? 'The Trading Post could not be loaded.');
      setPost(normalizeTradingPostPayload(payload));
      setError('');
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'The Trading Post could not be loaded.');
    } finally {
      if (!quiet) setLoading(false);
    }
  }, [selectedCharacterId, vendor.id]);

  useEffect(() => { void loadPost(); }, [loadPost]);
  useLiveRefresh(['trading-post', 'inventory', 'wallet'], () => loadPost(true), { enabled: Boolean(vendor.id), debounceMs: 180 });

  const selectedCharacter = post.characters.find((character) => character.id === (selectedCharacterId || post.selectedCharacterId));
  const ownListingIds = useMemo(() => new Set(post.activeListings
    .filter((listing) => listing.sellerUserId === selectedCharacter?.ownerUserId)
    .map((listing) => listing.id)), [post.activeListings, selectedCharacter?.ownerUserId]);
  const filteredInventory = useMemo(() => {
    const terms = inventorySearch.toLowerCase().trim().split(/\s+/).filter(Boolean);
    return post.inventory.filter((item) => {
      const label = `${item.displayName ?? ''} ${item.name}`.toLowerCase();
      return terms.every((term) => label.includes(term));
    });
  }, [inventorySearch, post.inventory]);
  const listingItem = post.inventory.find((item) => item.id === listingItemId) ?? null;
  const selectedOfferItems = post.inventory.filter((item) => offerItems[item.id] > 0);
  const selectedCurrency = post.wallet.flatMap((balance) => {
    const amount = Math.max(0, Math.floor(offerCurrency[balance.unit.id] ?? 0));
    return amount > 0 ? [{ ...balance.unit, unitId: balance.unit.id, amount } as TradingPostCurrency] : [];
  });
  const offerHasValue = selectedOfferItems.length > 0 || selectedCurrency.length > 0;

  function resetOffer() {
    setOfferListing(null);
    setOfferStep('build');
    setOfferItems({});
    setOfferCurrency({});
    setOfferMessage('');
    setInventorySearch('');
  }

  async function request(path: string, method: 'POST' | 'PATCH', body: Record<string, unknown>, busyKey: string) {
    setBusy(busyKey);
    setError('');
    try {
      const response = await fetch(path, { method, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.error ?? 'The Trading Post could not complete that action.');
      setPost(normalizeTradingPostPayload(payload));
      await loadPost(true);
      return true;
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'The Trading Post could not complete that action.');
      return false;
    } finally {
      setBusy('');
    }
  }

  async function submitListing() {
    if (!listingItem || !selectedCharacter) return;
    const succeeded = await request('/api/cities/trading-post', 'POST', {
      vendorId: vendor.id,
      characterId: selectedCharacter.id,
      itemId: listingItem.id,
      quantity: listingQuantity
    }, 'listing-submit');
    if (!succeeded) return;
    setListingStep('closed');
    setListingItemId('');
    setListingQuantity(1);
    setInventorySearch('');
  }

  async function submitOffer() {
    if (!offerListing || !selectedCharacter) return;
    const succeeded = await request('/api/cities/trading-post/offers', 'POST', {
      listingId: offerListing.id,
      characterId: selectedCharacter.id,
      items: selectedOfferItems.map((item) => ({ itemId: item.id, quantity: offerItems[item.id] })),
      currency: selectedCurrency.map((entry) => ({ unitId: entry.unitId, amount: entry.amount })),
      message: offerMessage
    }, 'offer-submit');
    if (!succeeded) return;
    resetOffer();
  }

  async function listingAction(listing: TradingPostListing, action: string) {
    await request(`/api/cities/trading-post/listings/${listing.id}`, 'PATCH', {
      action,
      reviewNote: reviewNote[listing.id] ?? ''
    }, `listing-${listing.id}-${action}`);
  }

  async function offerAction(offer: TradingPostOffer, action: string) {
    await request(`/api/cities/trading-post/offers/${offer.id}`, 'PATCH', { action }, `offer-${offer.id}-${action}`);
  }

  if (loading) return <Card><div className="h-52 animate-pulse rounded-2xl bg-black/20" /></Card>;

  return (
    <div className="space-y-5" style={{ '--post-primary': city.primaryColor, '--post-secondary': city.secondaryColor } as React.CSSProperties}>
      <Card className="overflow-hidden">
        <div className="relative -m-4 overflow-hidden p-5 sm:-m-5 sm:p-7" style={{ background: `linear-gradient(135deg, ${city.primaryColor}35, rgba(0,0,0,.08) 52%, ${city.secondaryColor}2e)` }}>
          <div className="flex flex-wrap items-center justify-between gap-4">
            <div className="flex items-center gap-3">
              <span className="grid h-14 w-14 place-items-center rounded-2xl border border-[var(--brass)]/50 bg-black/20 text-[var(--brass)]"><Handshake size={27} /></span>
              <div><p className="eyebrow">Velmora City Service</p><h2 className="text-3xl font-black">{vendor.name}</h2><p className="mt-1 text-sm font-bold text-[var(--muted)]">Reviewed by {post.vendor?.shopkeeperName ?? vendor.npcName}</p></div>
            </div>
            <span className="rounded-xl border border-[var(--line)] bg-black/25 px-3 py-2 text-xs font-black text-[var(--muted)]">Trading as {selectedCharacter?.name ?? 'No character selected'}</span>
          </div>
        </div>
      </Card>

      {error && <div className="rounded-2xl border border-[var(--red)]/45 bg-[var(--red)]/10 p-4 text-sm font-bold text-[var(--red)]">{error}</div>}

      <section className="space-y-3">
        <div className="rule-title"><div><p className="eyebrow">Approved Listings</p><h3 className="text-2xl font-black">Trading Block</h3></div></div>
        {post.activeListings.length ? <div className="grid gap-3">{post.activeListings.map((listing) => (
          <ListingCard
            key={listing.id}
            listing={listing}
            own={ownListingIds.has(listing.id)}
            disabled={!canUseService || !selectedCharacter}
            canRemove={Boolean(post.vendor?.canManage)}
            onOffer={() => { setError(''); setOfferListing(listing); setOfferStep('build'); }}
            onRemove={() => setConfirmation({ title: 'Remove listing?', body: 'The shopkeeper will remove this listing and close every pending offer.', confirmLabel: 'Remove Listing', variant: 'danger', run: () => listingAction(listing, 'remove') })}
          />
        ))}</div> : <Card><div className="grid min-h-32 place-items-center text-center"><Store className="text-[var(--brass)]" size={28} /><p className="mt-2 font-black">The Trading Block is empty.</p><p className="mt-1 text-sm text-[var(--muted)]">Approved player goods will appear here.</p></div></Card>}
      </section>

      <section className="space-y-3">
        <div className="rule-title"><div><p className="eyebrow">List An Item</p><h3 className="text-2xl font-black">Enter Trade Goods</h3></div></div>
        <Card>
          <div className="flex flex-wrap items-center justify-between gap-4">
            <div><h4 className="text-lg font-black">Submit goods for shopkeeper review</h4><p className="mt-1 max-w-2xl text-sm leading-6 text-[var(--muted)]">Choose one inventory stack and any valid quantity. Your item stays usable until an offer is accepted, so ownership and quantity are checked again at completion.</p></div>
            <Button variant="primary" disabled={!canUseService || !selectedCharacter || post.inventory.length === 0} onClick={() => { setError(''); setListingStep('choose'); }}><PackagePlus className="mr-2 inline" size={16} /> Choose Item</Button>
          </div>
          {!canUseService && <p className="mt-3 rounded-xl border border-[var(--red)]/30 bg-[var(--red)]/8 p-3 text-sm font-bold text-[var(--red)]">Choose a character currently able to use this city service.</p>}
        </Card>
      </section>

      {post.vendor?.canManage && (
        <section className="space-y-3">
          <div className="rule-title"><div><p className="eyebrow">Shopkeeper Controls</p><h3 className="text-xl font-black">Approval Desk</h3></div></div>
          {post.pendingReview.length ? <div className="grid gap-3">{post.pendingReview.map((listing) => (
            <Card key={listing.id}>
              <div className="grid gap-4 lg:grid-cols-[minmax(0,1fr)_minmax(16rem,24rem)]">
                <div><ItemTile item={listing.item} quantity={listing.quantity} /><p className="mt-2 text-sm font-bold text-[var(--muted)]">Submitted by {listing.sellerPlayerName} as {listing.sellerCharacterName}</p></div>
                <div className="grid content-start gap-2"><TextAreaField rows={3} placeholder="Optional review note" value={reviewNote[listing.id] ?? ''} onChange={(event) => setReviewNote((current) => ({ ...current, [listing.id]: event.target.value }))} /><div className="grid grid-cols-2 gap-2"><Button variant="teal" disabled={busy.startsWith(`listing-${listing.id}`)} onClick={() => void listingAction(listing, 'approve')}><Check className="mr-2 inline" size={14} /> Approve</Button><Button variant="danger" disabled={busy.startsWith(`listing-${listing.id}`)} onClick={() => void listingAction(listing, 'decline')}><X className="mr-2 inline" size={14} /> Decline</Button></div></div>
              </div>
            </Card>
          ))}</div> : <SoftCard><p className="text-sm font-bold text-[var(--muted)]">No submissions are awaiting approval.</p></SoftCard>}
        </section>
      )}

      <section className="grid gap-4 xl:grid-cols-3">
        <ActivityColumn title="My Listings" icon={<History size={17} />} empty="You have not submitted any listings.">
          {post.myListings.map((listing) => (
            <SoftCard key={listing.id}>
              <div className="flex items-start justify-between gap-2"><div className="min-w-0"><p className="break-words font-black">{itemTitle(listing.item)} ×{formatQuantity(listing.quantity)}</p><p className="mt-1 text-xs text-[var(--muted)]">{listing.offerCount} pending offer{listing.offerCount === 1 ? '' : 's'}</p></div><span className={`shrink-0 rounded-lg border px-2 py-1 text-[9px] font-black uppercase ${statusClass(listing.status)}`}>{statusLabel(listing.status)}</span></div>
              {listing.reviewNote && <p className="mt-2 text-xs leading-5 text-[var(--muted)]">Shopkeeper: {listing.reviewNote}</p>}
              <p className="mt-2 text-[10px] font-bold uppercase tracking-wide text-[var(--muted)]">{formatTimestamp(listing.completedAt || listing.closedAt || listing.createdAt)}</p>
              {(listing.status === 'pending_approval' || listing.status === 'active') && <Button variant="danger" className="mt-3 w-full py-2 text-xs" disabled={busy.startsWith(`listing-${listing.id}`)} onClick={() => setConfirmation({ title: 'Withdraw listing?', body: 'This closes the listing and makes every pending offer unavailable. No items or currency will move.', confirmLabel: 'Withdraw Listing', variant: 'danger', run: () => listingAction(listing, 'withdraw') })}>Withdraw</Button>}
              {post.vendor?.canManage && listing.status === 'active' && <Button variant="danger" className="mt-2 w-full py-2 text-xs" disabled={busy.startsWith(`listing-${listing.id}`)} onClick={() => setConfirmation({ title: 'Remove listing?', body: 'The shopkeeper will remove this listing and close every pending offer.', confirmLabel: 'Remove Listing', variant: 'danger', run: () => listingAction(listing, 'remove') })}>Shopkeeper Remove</Button>}
            </SoftCard>
          ))}
        </ActivityColumn>

        <ActivityColumn title="Offers Received" icon={<Inbox size={17} />} empty="No one has offered on your listings yet.">
          {post.offersReceived.map((offer) => (
            <SoftCard key={offer.id}>
              <div className="flex items-start justify-between gap-2"><div><p className="font-black">For {itemTitle(offer.listing.item)} ×{formatQuantity(offer.listing.quantity)}</p><p className="mt-1 text-xs font-bold text-[var(--muted)]">From {offer.offererPlayerName} as {offer.offererCharacterName}</p></div><span className={`rounded-lg border px-2 py-1 text-[9px] font-black uppercase ${statusClass(offer.status)}`}>{statusLabel(offer.status)}</span></div>
              <div className="mt-3"><OfferContents offer={offer} /></div>
              {offer.message && <p className="mt-3 rounded-lg border border-[var(--line)] bg-black/15 p-2 text-xs italic text-[var(--muted)]">“{offer.message}”</p>}
              <p className="mt-2 text-[10px] font-bold uppercase tracking-wide text-[var(--muted)]">{formatTimestamp(offer.resolvedAt || offer.createdAt)}</p>
              {offer.status === 'pending' && <div className="mt-3 grid grid-cols-2 gap-2"><Button variant="teal" className="py-2 text-xs" disabled={busy.startsWith(`offer-${offer.id}`)} onClick={() => setConfirmation({ title: 'Accept this trade?', body: 'The Trading Post will recheck every item, inventory destination, and currency balance, then exchange everything as one transaction.', confirmLabel: 'Accept And Exchange', variant: 'teal', run: () => offerAction(offer, 'accept') })}>Accept</Button><Button variant="danger" className="py-2 text-xs" disabled={busy.startsWith(`offer-${offer.id}`)} onClick={() => void offerAction(offer, 'decline')}>Decline</Button></div>}
            </SoftCard>
          ))}
        </ActivityColumn>

        <ActivityColumn title="Offers Sent" icon={<Send size={17} />} empty="You have not proposed any trades.">
          {post.offersSent.map((offer) => (
            <SoftCard key={offer.id}>
              <div className="flex items-start justify-between gap-2"><div><p className="font-black">For {itemTitle(offer.listing.item)} ×{formatQuantity(offer.listing.quantity)}</p><p className="mt-1 text-xs text-[var(--muted)]">Offered by {offer.offererCharacterName}</p></div><span className={`rounded-lg border px-2 py-1 text-[9px] font-black uppercase ${statusClass(offer.status)}`}>{statusLabel(offer.status)}</span></div>
              <div className="mt-3"><OfferContents offer={offer} /></div>
              <p className="mt-2 text-[10px] font-bold uppercase tracking-wide text-[var(--muted)]">{formatTimestamp(offer.resolvedAt || offer.createdAt)}</p>
              {offer.status === 'pending' && <Button variant="danger" className="mt-3 w-full py-2 text-xs" disabled={busy.startsWith(`offer-${offer.id}`)} onClick={() => setConfirmation({ title: 'Cancel this offer?', body: 'The offer will close without moving any items or currency.', confirmLabel: 'Cancel Offer', variant: 'danger', run: () => offerAction(offer, 'cancel') })}>Cancel Offer</Button>}
            </SoftCard>
          ))}
        </ActivityColumn>
      </section>

      {listingStep !== 'closed' && (
        <Modal size="wide" title={listingStep === 'choose' ? 'Choose Trade Goods' : 'Review Listing'} onClose={() => setListingStep('closed')}>
          {error && <div className="mb-4 rounded-xl border border-[var(--red)]/40 bg-[var(--red)]/10 p-3 text-sm font-bold text-[var(--red)]">{error}</div>}
          {listingStep === 'choose' ? <div className="grid gap-4">
            <div className="relative"><Search className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-[var(--muted)]" size={16} /><TextField className="pl-10" autoFocus value={inventorySearch} onChange={(event) => setInventorySearch(event.target.value)} placeholder="Search this character's inventory" /></div>
            <div className="grid max-h-[52dvh] gap-3 overflow-y-auto pr-1 sm:grid-cols-2 lg:grid-cols-3">{filteredInventory.map((item) => <ItemTile key={item.id} item={item} quantity={item.quantity} selected={listingItemId === item.id} onClick={() => { setListingItemId(item.id); setListingQuantity(Math.min(item.quantity, 1)); }} />)}</div>
            {!filteredInventory.length && <SoftCard><p className="text-sm text-[var(--muted)]">No inventory items match that search.</p></SoftCard>}
            {listingItem && <div className="sticky bottom-0 grid gap-3 rounded-2xl border border-[var(--line)] bg-[#171210]/95 p-3 backdrop-blur sm:grid-cols-[1fr_12rem_auto] sm:items-end"><div><p className="text-xs font-black uppercase text-[var(--muted)]">Selected</p><p className="font-black">{itemTitle(listingItem)}</p></div><label><span className="mb-1 block text-[10px] font-black uppercase text-[var(--muted)]">Quantity</span><NumberInput min={quantityStepForItem(listingItem)} max={listingItem.quantity} step={quantityStepForItem(listingItem)} value={listingQuantity} onValueChange={(value) => setListingQuantity(Math.max(quantityStepForItem(listingItem), Math.min(itemCanListQuantity(listingItem), value)))} /></label><Button variant="primary" onClick={() => setListingStep('review')}>Review Listing</Button></div>}
          </div> : listingItem ? <div className="grid gap-5"><p className="text-sm leading-6 text-[var(--muted)]">Confirm what the shopkeeper will review. The item remains in your inventory until a later offer is accepted.</p><div className="mx-auto w-full max-w-md"><ItemTile item={listingItem} quantity={listingQuantity} /></div><div className="flex flex-wrap justify-end gap-2"><Button variant="secondary" onClick={() => setListingStep('choose')}>Back</Button><Button variant="primary" disabled={busy === 'listing-submit'} onClick={() => void submitListing()}>{busy === 'listing-submit' ? <Loader2 className="mr-2 inline animate-spin" size={15} /> : <ShieldCheck className="mr-2 inline" size={15} />} Submit For Approval</Button></div></div> : null}
        </Modal>
      )}

      {offerListing && (
        <Modal size="wide" title={offerStep === 'build' ? 'Build Trade Offer' : 'Confirm Trade Offer'} onClose={resetOffer}>
          {error && <div className="mb-4 rounded-xl border border-[var(--red)]/40 bg-[var(--red)]/10 p-3 text-sm font-bold text-[var(--red)]">{error}</div>}
          {offerStep === 'build' ? <div className="grid gap-5">
            <div><p className="eyebrow">You Receive</p><div className="mt-2 max-w-md"><ItemTile item={offerListing.item} quantity={offerListing.quantity} /></div></div>
            <div><p className="eyebrow">Choose Items To Offer</p><div className="relative mt-2"><Search className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-[var(--muted)]" size={16} /><TextField className="pl-10" value={inventorySearch} onChange={(event) => setInventorySearch(event.target.value)} placeholder="Search inventory" /></div><div className="mt-3 grid max-h-[36dvh] gap-3 overflow-y-auto pr-1 sm:grid-cols-2 lg:grid-cols-3">{filteredInventory.map((item) => {
              const selected = offerItems[item.id] > 0;
              const step = quantityStepForItem(item);
              return <ItemTile key={item.id} item={item} quantity={item.quantity} selected={selected} onClick={() => setOfferItems((current) => selected ? withoutKey(current, item.id) : { ...current, [item.id]: Math.min(item.quantity, 1) })} footer={selected ? <div onClick={(event) => event.stopPropagation()} onKeyDown={(event) => event.stopPropagation()}><span className="mb-1 block text-[10px] font-black uppercase text-[var(--muted)]">Offer quantity</span><NumberInput min={step} max={item.quantity} step={step} value={offerItems[item.id]} onValueChange={(value) => setOfferItems((current) => ({ ...current, [item.id]: Math.max(step, Math.min(itemCanListQuantity(item), value)) }))} /></div> : undefined} />;
            })}</div></div>
            <div><p className="eyebrow">Global Currency</p><div className="mt-2 grid gap-2 sm:grid-cols-2 lg:grid-cols-5">{post.wallet.map((balance) => <label key={balance.unit.id} className="rounded-xl border border-[var(--line)] bg-black/15 p-3"><span className="block text-xs font-black">{balance.unit.name}</span><span className="mb-2 block text-[10px] font-bold text-[var(--muted)]">Available: {balance.amount}</span><NumberInput min={0} max={balance.amount} step={1} value={offerCurrency[balance.unit.id] ?? 0} onValueChange={(value) => setOfferCurrency((current) => ({ ...current, [balance.unit.id]: Math.max(0, Math.min(balance.amount, Math.floor(value))) }))} /></label>)}</div></div>
            <label><span className="mb-1 block text-[10px] font-black uppercase text-[var(--muted)]">Message (optional)</span><TextAreaField rows={3} maxLength={1000} value={offerMessage} onChange={(event) => setOfferMessage(event.target.value)} placeholder="Add a short note to the listing owner" /></label>
            <div className="flex justify-end"><Button variant="primary" disabled={!offerHasValue} onClick={() => setOfferStep('confirm')}>Review Offer</Button></div>
          </div> : <div className="grid gap-5">
            <div className="grid gap-4 lg:grid-cols-[1fr_auto_1fr] lg:items-center"><div><p className="eyebrow">You Offer</p><div className="mt-2 grid gap-2">{selectedOfferItems.map((item) => <ItemTile key={item.id} item={item} quantity={offerItems[item.id]} />)}<CurrencySummary currency={selectedCurrency} /></div></div><ArrowLeftRight className="mx-auto rotate-90 text-[var(--brass)] lg:rotate-0" size={30} /><div><p className="eyebrow">You Receive</p><div className="mt-2"><ItemTile item={offerListing.item} quantity={offerListing.quantity} /></div></div></div>
            <div className="rounded-xl border border-[var(--brass)]/35 bg-[var(--brass)]/8 p-3 text-sm leading-6 text-[var(--muted)]"><Clock3 className="mr-2 inline text-[var(--brass)]" size={15} />Nothing moves now. Every offered item and balance is checked again only if the listing owner accepts.</div>
            <div className="flex flex-wrap justify-end gap-2"><Button variant="secondary" onClick={() => setOfferStep('build')}>Back</Button><Button variant="teal" disabled={busy === 'offer-submit'} onClick={() => void submitOffer()}>{busy === 'offer-submit' ? <Loader2 className="mr-2 inline animate-spin" size={15} /> : <Send className="mr-2 inline" size={15} />} Send Offer</Button></div>
          </div>}
        </Modal>
      )}

      {confirmation && <Modal title={confirmation.title} onClose={() => setConfirmation(null)}><div className="grid gap-4"><p className="text-sm leading-6 text-[var(--muted)]">{confirmation.body}</p><div className="flex justify-end gap-2"><Button variant="secondary" onClick={() => setConfirmation(null)}>Cancel</Button><Button variant={confirmation.variant} disabled={Boolean(busy)} onClick={() => { const action = confirmation.run; setConfirmation(null); void action(); }}>{confirmation.confirmLabel}</Button></div></div></Modal>}
    </div>
  );
}

function ActivityColumn({ title, icon, empty, children }: { title: string; icon: React.ReactNode; empty: string; children: React.ReactNode[] }) {
  return <Card><div className="mb-3 flex items-center gap-2 text-[var(--brass)]">{icon}<h3 className="font-black text-[var(--paper)]">{title}</h3></div><div className="grid max-h-[42rem] gap-3 overflow-y-auto pr-1">{children.length ? children : <p className="rounded-xl border border-dashed border-[var(--line)] p-4 text-sm text-[var(--muted)]">{empty}</p>}</div></Card>;
}

function withoutKey(source: Record<string, number>, key: string) {
  const next = { ...source };
  delete next[key];
  return next;
}

function itemCanListQuantity(item: InventoryItem) {
  return item.isStorage ? 1 : item.quantity;
}
