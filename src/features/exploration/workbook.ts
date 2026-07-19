import * as XLSX from 'xlsx';
import type { ItemRarity, ItemType } from '@/lib/types';

const RARITIES: ItemRarity[] = ['Common', 'Uncommon', 'Rare', 'Epic', 'Legendary', 'Mythical'];

function text(value: unknown, fallback = '') {
  if (value === null || value === undefined) return fallback;
  return String(value).trim() || fallback;
}

function number(value: unknown, fallback: number) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function slug(value: string) {
  return value.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '') || 'loot';
}

function splitList(value: unknown) {
  const raw = text(value, 'Any');
  return raw.split(',').map((entry) => entry.trim()).filter(Boolean);
}

function rarity(value: unknown): ItemRarity {
  const normalized = text(value, 'Common');
  return RARITIES.includes(normalized as ItemRarity) ? normalized as ItemRarity : 'Common';
}

export function categoryToItemType(categoryValue: unknown, itemNameValue: unknown): ItemType {
  const category = text(categoryValue).toLowerCase();
  const name = text(itemNameValue).toLowerCase();
  const combined = `${category} ${name}`;

  if (combined.includes('weapon') || combined.includes('sword') || combined.includes('axe') || combined.includes('bow') || combined.includes('dagger') || combined.includes('spear')) return 'weapon';
  if (combined.includes('shield')) return 'shield';
  if (combined.includes('armor') || combined.includes('armour')) return 'armor';
  if (combined.includes('animal') || combined.includes('horse') || combined.includes('dog') || combined.includes('pet')) return 'pet';
  if (combined.includes('storage') || combined.includes('bag') || combined.includes('duffle') || combined.includes('pouch')) return 'storage';
  if (combined.includes('potion') || combined.includes('elixir') || combined.includes('nectar')) return 'potion';
  if (combined.includes('ore') || combined.includes('ingot') || combined.includes('metal')) return 'ore';
  if (combined.includes('food') || combined.includes('ration')) return 'food';
  if (combined.includes('plant') || combined.includes('herb') || combined.includes('flower') || combined.includes('root')) return 'plant';
  if (combined.includes('fabric') || combined.includes('cloth') || combined.includes('leather') || combined.includes('clothing') || combined.includes('cloak')) return 'fabric';
  if (combined.includes('scroll') || combined.includes('map') || combined.includes('lore') || combined.includes('tome')) return 'quest';
  if (combined.includes('ring') || combined.includes('jewel') || combined.includes('gem') || combined.includes('rune') || combined.includes('upgrade')) return 'accessory';
  if (combined.includes('tool') || combined.includes('gear') || combined.includes('rope') || combined.includes('torch') || combined.includes('arrows')) return 'tool';
  return 'misc';
}

function tableRows(sheet: XLSX.WorkSheet | undefined) {
  if (!sheet) return [];
  return XLSX.utils.sheet_to_json<unknown[]>(sheet, { header: 1, defval: '' });
}

function valuesFromColumn(rows: unknown[][], columnIndex: number) {
  return rows.slice(1).map((row) => text(row[columnIndex])).filter(Boolean);
}

function parseBaseRolls(formula: string, fallbackPoolSizes: string[]) {
  const result: Record<string, number> = {};
  const pattern = /"([^"]+)"\s*,\s*([0-9]+(?:\.[0-9]+)?)/g;
  let match: RegExpExecArray | null;
  while ((match = pattern.exec(formula))) {
    const key = match[1];
    const value = Number(match[2]);
    if (fallbackPoolSizes.includes(key) && Number.isFinite(value)) result[key] = value;
  }
  return Object.keys(result).length ? result : {
    'Night Encounter': 5,
    'Small Cave': 10,
    'Medium Cave': 15,
    'Large Cave': 20,
    'Dragon Lair': 50,
    'Tower Floor': 25,
    Base: 40
  };
}

function parseRareMultipliers(formula: string) {
  const result: Record<string, number> = {};
  const pattern = /SEARCH\("([^"]+)"[\s\S]*?\)\s*,\s*([0-9]+(?:\.[0-9]+)?)/g;
  let match: RegExpExecArray | null;
  while ((match = pattern.exec(formula))) {
    const keyword = match[1].toLowerCase();
    const value = Number(match[2]);
    if (Number.isFinite(value)) result[keyword] = value;
  }
  return Object.keys(result).length ? result : { capital: 5, base: 2, camp: 1.33 };
}

export function parseLootWorkbook(buffer: Buffer) {
  const workbook = XLSX.read(buffer, { type: 'buffer', cellFormula: true, cellDates: false });
  const lootRows = tableRows(workbook.Sheets['Loot Table']);
  const settingsRows = tableRows(workbook.Sheets.Settings);
  const generator = workbook.Sheets.Generator;

  const biomes = valuesFromColumn(settingsRows, 0);
  const difficulties = valuesFromColumn(settingsRows, 1).map((entry) => number(entry, NaN)).filter(Number.isFinite);
  const poolSizes = valuesFromColumn(settingsRows, 2);
  const roomTypes = valuesFromColumn(settingsRows, 3);
  const rollFormula = text(generator?.B5?.f);
  const rareFormula = text(generator?.D2?.f);

  const rows = lootRows.slice(1).map((row) => {
    const name = text(row[0]);
    if (!name) return null;
    const category = text(row[1], 'Item');
    return {
      pool: 'Workbook Loot',
      poolKey: 'workbook-loot',
      name,
      category,
      type: categoryToItemType(category, name),
      biomes: splitList(row[2]),
      minDifficulty: Math.max(1, number(row[3], 1)),
      maxDifficulty: Math.max(1, number(row[4], 5)),
      rarity: rarity(row[5]),
      weight: Math.max(1, number(row[6], 1)),
      baseWeight: Math.max(1, number(row[6], 1)),
      minQuantity: Math.max(1, number(row[7], 1)),
      maxQuantity: Math.max(Math.max(1, number(row[7], 1)), number(row[8], 1)),
      notes: text(row[9])
    };
  }).filter(Boolean);

  return {
    replace: true,
    rows,
    settings: {
      biomes: biomes.length ? biomes : ['Any'],
      difficulties: difficulties.length ? difficulties : [1, 2, 3, 4, 5],
      poolSizes: poolSizes.length ? poolSizes : ['Night Encounter', 'Small Cave', 'Medium Cave', 'Large Cave', 'Dragon Lair', 'Tower Floor', 'Base'],
      roomTypes: roomTypes.length ? roomTypes : ['Normal', 'Secret Room', 'Tower Boss Room'],
      baseRollsByPoolSize: parseBaseRolls(rollFormula, poolSizes),
      rareMultiplierKeywords: parseRareMultipliers(rareFormula),
      sourceFormulas: {
        rareMultiplier: rareFormula,
        lootRolls: rollFormula
      }
    },
    source: {
      sheets: workbook.SheetNames,
      importedRows: rows.length
    }
  };
}
