import * as XLSX from 'xlsx';
import type { ItemRarity, ItemType } from '@/lib/types';

const RARITIES: ItemRarity[] = ['Common', 'Uncommon', 'Rare', 'Epic', 'Legendary', 'Mythical'];
const ITEM_TYPES: ItemType[] = ['weapon', 'armor', 'shield', 'pet', 'accessory', 'storage', 'ore', 'potion', 'food', 'plant', 'fabric', 'tool', 'quest', 'misc'];

function text(value: unknown, fallback = '') {
  if (value === null || value === undefined) return fallback;
  return String(value).trim() || fallback;
}

function number(value: unknown, fallback: number) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function slug(value: string) {
  return value.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '') || 'catalog';
}

function typeLabel(value: ItemType) {
  return value.split('-').map((part) => part.charAt(0).toUpperCase() + part.slice(1)).join(' ');
}

function rarity(value: unknown): ItemRarity {
  const normalized = text(value, 'Common');
  return RARITIES.includes(normalized as ItemRarity) ? normalized as ItemRarity : 'Common';
}

export function categoryToItemType(typeValue: unknown, itemNameValue: unknown): ItemType {
  const explicitType = text(typeValue).toLowerCase();
  if (ITEM_TYPES.includes(explicitType as ItemType)) return explicitType as ItemType;

  const name = text(itemNameValue).toLowerCase();
  const combined = `${explicitType} ${name}`;

  if (combined.includes('shield')) return 'shield';
  if (combined.includes('armor') || combined.includes('armour')) return 'armor';
  if (combined.includes('weapon') || combined.includes('sword') || combined.includes('axe') || combined.includes('bow') || combined.includes('dagger') || combined.includes('spear') || combined.includes('mace') || combined.includes('staff') || combined.includes('wand') || combined.includes('arrows')) return 'weapon';
  if (combined.includes('animal') || combined.includes('horse') || combined.includes('dog') || combined.includes('pet')) return 'pet';
  if (combined.includes('storage') || combined.includes('bag') || combined.includes('duffle') || combined.includes('pouch') || combined.includes('satchel')) return 'storage';
  if (combined.includes('potion') || combined.includes('elixir') || combined.includes('nectar')) return 'potion';
  if (combined.includes('ore') || combined.includes('ingot') || combined.includes('metal')) return 'ore';
  if (combined.includes('food') || combined.includes('ration')) return 'food';
  if (combined.includes('plant') || combined.includes('herb') || combined.includes('flower') || combined.includes('root')) return 'plant';
  if (combined.includes('fabric') || combined.includes('cloth') || combined.includes('leather') || combined.includes('clothing') || combined.includes('cloak')) return 'fabric';
  if (combined.includes('scroll') || combined.includes('map') || combined.includes('lore') || combined.includes('tome')) return 'quest';
  if (combined.includes('belt') || combined.includes('ring') || combined.includes('jewel') || combined.includes('jewlery') || combined.includes('jewelry') || combined.includes('gem') || combined.includes('rune') || combined.includes('upgrade')) return 'accessory';
  if (combined.includes('tool') || combined.includes('gear') || combined.includes('rope') || combined.includes('torch')) return 'tool';
  return 'misc';
}

function tableRows(sheet: XLSX.WorkSheet | undefined) {
  if (!sheet) return [];
  return XLSX.utils.sheet_to_json<unknown[]>(sheet, { header: 1, defval: '', blankrows: false });
}

export function parseLootWorkbook(buffer: Buffer) {
  const workbook = XLSX.read(buffer, { type: 'buffer', cellFormula: false, cellDates: false });
  const lootRows = tableRows(workbook.Sheets['Loot Table']);
  const rows = lootRows.slice(1).map((row) => {
    const name = text(row[0]);
    if (!name) return null;
    const type = categoryToItemType(row[1], name);
    const pool = `${typeLabel(type)} Catalog`;
    return {
      pool,
      poolKey: `catalog-${slug(type)}`,
      name,
      type,
      rarity: rarity(row[5]),
      minQuantity: Math.max(1, number(row[7], 1)),
      maxQuantity: Math.max(Math.max(1, number(row[7], 1)), number(row[8], 1)),
      notes: ''
    };
  }).filter(Boolean);

  return {
    replace: true,
    rows,
    source: {
      sheets: workbook.SheetNames,
      importedRows: rows.length
    }
  };
}
