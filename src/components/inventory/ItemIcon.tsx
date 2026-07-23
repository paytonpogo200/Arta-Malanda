import { Box, Coins, FlaskConical, Gem, Leaf, PackageOpen, PawPrint, ScrollText, Shield, Shirt, Sparkles, Sword, Wrench } from 'lucide-react';
import type { ItemType } from '@/lib/types';

function IngotIcon({ size }: { size: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M6.5 8.5h11l3 6.5h-17l3-6.5Z" />
      <path d="M8 8.5 5 15" />
      <path d="M16 8.5 19 15" />
      <path d="M6 15h12" />
    </svg>
  );
}

function ClothIcon({ size }: { size: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M5 6.5c3.5-2 5.5 1.5 9 0s4.5-.5 5 1.5v9.5c-3.5-2-5.5 1.5-9 0s-4.5.5-5-1.5v-9.5Z" />
      <path d="M9 5.8v12.4" />
      <path d="M15 6.1v12" />
    </svg>
  );
}

function BreadIcon({ size }: { size: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M4 13c0-4.4 3.6-8 8-8s8 3.6 8 8v4.5a1.5 1.5 0 0 1-1.5 1.5h-13A1.5 1.5 0 0 1 4 17.5V13Z" />
      <path d="M8 9.5v2" />
      <path d="M12 8.5v2.5" />
      <path d="M16 9.5v2" />
    </svg>
  );
}

export function ItemIcon({ type, size = 18 }: { type: ItemType; size?: number }) {
  if (type === 'material' || type === 'ore') return <IngotIcon size={size} />;
  if (type === 'fabric') return <ClothIcon size={size} />;
  if (type === 'food') return <BreadIcon size={size} />;

  const Icon = {
    weapon: Sword,
    armor: Shirt,
    shield: Shield,
    pet: PawPrint,
    accessory: Sparkles,
    storage: PackageOpen,
    catalyst: FlaskConical,
    rune: Gem,
    potion: FlaskConical,
    plant: Leaf,
    tool: Wrench,
    quest: ScrollText,
    currency: Coins,
    misc: Box
  }[type] ?? Box;

  return <Icon size={size} />;
}
