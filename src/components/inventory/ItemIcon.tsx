import { Box, BrickWall, Coins, FlaskConical, Leaf, PackageOpen, PawPrint, ScrollText, Shield, Shirt, Sparkles, SwatchBook, Sword, Wheat, Wrench } from 'lucide-react';
import type { ItemType } from '@/lib/types';

export function ItemIcon({ type, size = 18 }: { type: ItemType; size?: number }) {
  const Icon = {
    weapon: Sword,
    armor: Shirt,
    shield: Shield,
    pet: PawPrint,
    accessory: Sparkles,
    storage: PackageOpen,
    ore: BrickWall,
    potion: FlaskConical,
    food: Wheat,
    plant: Leaf,
    fabric: SwatchBook,
    tool: Wrench,
    quest: ScrollText,
    currency: Coins,
    misc: Box
  }[type] ?? Box;

  return <Icon size={size} />;
}
