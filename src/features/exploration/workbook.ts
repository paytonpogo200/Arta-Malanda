import * as XLSX from 'xlsx';
import type { ItemRarity, ItemType } from '@/lib/types';

const RARITIES: ItemRarity[] = ['Common', 'Uncommon', 'Rare', 'Epic', 'Legendary', 'Mythical'];
const ITEM_TYPES: ItemType[] = ['weapon', 'armor', 'shield', 'pet', 'accessory', 'storage', 'ore', 'potion', 'food', 'plant', 'fabric', 'tool', 'quest', 'currency', 'misc'];

function text(value: unknown, fallback = '') {
  if (value === null || value === undefined) return fallback;
  return String(value).trim() || fallback;
}

function number(value: unknown, fallback: number) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function booleanValue(value: unknown) {
  if (typeof value === 'boolean') return value;
  return ['true', 'yes', '1'].includes(text(value).toLowerCase());
}

function slug(value: string) {
  return value.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '') || 'catalog';
}

function typeLabel(value: ItemType) {
  return value.split('-').map((part) => part.charAt(0).toUpperCase() + part.slice(1)).join(' ');
}

function splitList(value: unknown) {
  return text(value, 'Any').split(',').map((entry) => entry.trim()).filter(Boolean);
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

  if (combined.includes('coin') || combined.includes('currency') || combined.includes('callis') || combined.includes('callor')) return 'currency';
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

function valuesFromColumn(rows: unknown[][], columnIndex: number) {
  return rows.slice(1).map((row) => text(row[columnIndex])).filter(Boolean);
}

function numbersFromColumn(rows: unknown[][], columnIndex: number) {
  return valuesFromColumn(rows, columnIndex).map((entry) => number(entry, NaN)).filter(Number.isFinite);
}

function parseQuotedNumberPairs(fragment: string, allowedLabels: string[]) {
  const result: Record<string, number> = {};
  const allowed = new Set(allowedLabels);
  const pattern = /"([^"]+)"\s*,\s*([0-9]+(?:\.[0-9]+)?)/g;
  let match: RegExpExecArray | null;
  while ((match = pattern.exec(fragment))) {
    const label = match[1];
    const parsed = Number(match[2]);
    if (allowed.has(label) && Number.isFinite(parsed)) result[label] = parsed;
  }
  return result;
}

function parseBaseRolls(formula: string, poolSizes: string[]) {
  const parsed = parseQuotedNumberPairs(formula, poolSizes);
  return Object.keys(parsed).length ? parsed : {
    'Night Encounter': 5,
    'Small Cave': 10,
    'Medium Cave': 15,
    'Large Cave': 20,
    'Dragon Lair': 50,
    'Tower Floor': 25,
    Base: 50
  };
}

function parseSwitchMultipliers(formula: string, cellRef: '$B$3' | '$B$4', labels: string[]) {
  const switchStart = formula.indexOf(`SWITCH(${cellRef},`);
  if (switchStart < 0) return {};
  const nextSwitch = formula.indexOf('*SWITCH(', switchStart + 1);
  const fragment = nextSwitch > switchStart ? formula.slice(switchStart, nextSwitch) : formula.slice(switchStart);
  return parseQuotedNumberPairs(fragment, labels);
}

function parseRarityBoosts(formula: string) {
  const match = formula.match(/\{([^}]+)\}/);
  if (!match) return ['Rare', 'Epic', 'Legendary', 'Mythical'] as ItemRarity[];
  const parsed = match[1]
    .split(',')
    .map((entry) => rarity(entry.replace(/"/g, '').trim()))
    .filter((entry, index, array) => array.indexOf(entry) === index);
  return parsed.length ? parsed : ['Rare', 'Epic', 'Legendary', 'Mythical'];
}

export function parseLootWorkbook(buffer: Buffer) {
  const workbook = XLSX.read(buffer, { type: 'buffer', cellFormula: true, cellDates: false });
  const lootRows = tableRows(workbook.Sheets['Loot Table']);
  const settingsRows = tableRows(workbook.Sheets.Settings);
  const generator = workbook.Sheets.Generator;
  const helper = workbook.Sheets['Roll Helper'];

  const biomes = valuesFromColumn(settingsRows, 0);
  const difficulties = numbersFromColumn(settingsRows, 1);
  const poolSizes = valuesFromColumn(settingsRows, 2);
  const roomTypes = valuesFromColumn(settingsRows, 3);
  const rollFormula = text(generator?.B5?.f);
  const multiplierFormula = text(generator?.D2?.f);
  const eligibilityFormula = text(helper?.J2?.f);
  const adjustedWeightFormula = text(helper?.K2?.f);

  const rows = lootRows.slice(1).map((row) => {
    const name = text(row[0]);
    if (!name) return null;
    const type = categoryToItemType(row[1], name);
    const pool = `${typeLabel(type)} Catalog`;
    const minQuantity = Math.max(1, number(row[7], 1));
    return {
      pool,
      poolKey: `catalog-${slug(type)}`,
      name,
      type,
      biomes: splitList(row[2]),
      minDifficulty: Math.max(1, number(row[3], 1)),
      maxDifficulty: Math.max(1, number(row[4], 5)),
      rarity: rarity(row[5]),
      weight: Math.max(0, number(row[6], 1)),
      minQuantity,
      maxQuantity: Math.max(minQuantity, number(row[8], minQuantity)),
      towerBaseOnly: booleanValue(row[9]),
      notes: ''
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
      poolMultipliers: parseSwitchMultipliers(multiplierFormula, '$B$3', poolSizes),
      roomMultipliers: parseSwitchMultipliers(multiplierFormula, '$B$4', roomTypes),
      rareBoostRarities: parseRarityBoosts(adjustedWeightFormula),
      sourceFormulas: {
        lootRolls: rollFormula,
        multiplier: multiplierFormula,
        eligibility: eligibilityFormula,
        adjustedWeight: adjustedWeightFormula
      }
    },
    source: {
      sheets: workbook.SheetNames,
      importedRows: rows.length
    }
  };
}
