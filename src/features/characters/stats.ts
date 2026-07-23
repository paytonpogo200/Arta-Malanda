export function armorDefenseBase(armor?: string) {
  const normalized = (armor ?? '').toLowerCase();
  if (normalized.includes('heavy')) return 13;
  if (normalized.includes('medium')) return 10;
  if (normalized.includes('light')) return 7;
  return 0;
}
