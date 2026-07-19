import type { TradeOffer, TradeStatus } from '@/lib/types';

function normalizeTradeStatus(value: unknown): TradeStatus {
  if (value === 'accepted' || value === 'declined' || value === 'cancelled') return value;
  return 'pending';
}

export function normalizeTradeOffer(value: unknown): TradeOffer {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  return {
    id: String(source.id ?? ''),
    senderUserId: String(source.senderUserId ?? source.sender_user_id ?? ''),
    recipientUserId: String(source.recipientUserId ?? source.recipient_user_id ?? ''),
    senderCharacterId: String(source.senderCharacterId ?? source.sender_character_id ?? ''),
    targetCharacterId: String(source.targetCharacterId ?? source.target_character_id ?? ''),
    senderCharacterName: String(source.senderCharacterName ?? source.sender_character_name ?? 'Unknown'),
    targetCharacterName: String(source.targetCharacterName ?? source.target_character_name ?? 'Unknown'),
    status: normalizeTradeStatus(source.status),
    offerNote: String(source.offerNote ?? source.offer_note ?? ''),
    requestNote: String(source.requestNote ?? source.request_note ?? ''),
    message: String(source.message ?? ''),
    createdAt: source.createdAt || source.created_at ? String(source.createdAt ?? source.created_at) : null,
    updatedAt: source.updatedAt || source.updated_at ? String(source.updatedAt ?? source.updated_at) : null
  };
}

export function normalizeTradeList(value: unknown): TradeOffer[] {
  const source = value && typeof value === 'object' ? value as Record<string, unknown> : {};
  const trades = Array.isArray(source.trades) ? source.trades : Array.isArray(value) ? value : [];
  return trades.map(normalizeTradeOffer).filter((trade) => trade.id);
}
