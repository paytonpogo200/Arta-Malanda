import { Apple, Box, Coins, FlaskConical, Leaf, PackageOpen, PawPrint, Pickaxe, ScrollText, Shield, Shirt, Sparkles, Sword, Wrench } from 'lucide-react';
import type { ItemType } from '@/lib/types';

export function ItemIcon({ type, size = 18 }: { type: ItemType; size?: number }) {
  const Icon = {
    weapon: Sword,
    armor: Shield,
    shield: Shield,
    pet: PawPrint,
    accessory: Sparkles,
    storage: PackageOpen,
    ore: Pickaxe,
    potion: FlaskConical,
    food: Apple,
    plant: Leaf,
    fabric: Shirt,
    tool: Wrench,
    quest: ScrollText,
    currency: Coins,
    misc: Box
  }[type] ?? Box;

  return <Icon size={size} />;
}
