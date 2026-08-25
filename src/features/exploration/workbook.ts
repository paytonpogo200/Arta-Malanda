import * as XLSX from 'xlsx';
import type { ItemRarity, ItemType } from '@/lib/types';

const RARITIES: ItemRarity[] = ['Common', 'Uncommon', 'Rare', 'Epic', 'Legendary', 'Mythical'];
const ITEM_TYPES: ItemType[] = ['weapon', 'armor', 'shield', 'pet', 'accessory', 'storage', 'material', 'catalyst', 'rune', 'ore', 'potion', 'food', 'plant', 'fabric', 'tool', 'book', 'quest', 'spell book', 'currency', 'misc'];

function text(value: unknown, fallback = '') {
  if (value === null || value === undefined) return fallback;
  return String(value).trim() || fallback;
}

function number(value: unknown, fallback: number) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function optionalNumber(value: unknown, fallback: number) {
  const cleaned = text(value);
  if (!cleaned) return fallback;
  const parsed = Number(cleaned);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function booleanValue(value: unknown) {
  if (typeof value === 'boolean') return value;
  return ['true', 'yes', '1'].includes(text(value).toLowerCase());
}

function booleanValueDefault(value: unknown, fallback: boolean) {
  const cleaned = text(value).toLowerCase();
  if (!cleaned) return fallback;
  if (['true', 'yes', '1'].includes(cleaned)) return true;
  if (['false', 'no', '0'].includes(cleaned)) return false;
  return fallback;
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

function headerMap(headers: unknown[]) {
  const map = new Map<string, number>();
  headers.forEach((header, index) => {
    const key = text(header)
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, '');
    if (key) map.set(key, index);
  });
  return map;
}

function getColumn(row: unknown[], headers: Map<string, number>, aliases: string[], fallbackIndex: number) {
  for (const alias of aliases) {
    const index = headers.get(alias.toLowerCase().replace(/[^a-z0-9]+/g, ''));
    if (index !== undefined) return row[index];
  }
  return row[fallbackIndex];
}

function rarity(value: unknown): ItemRarity {
  const normalized = text(value, 'Common');
  return RARITIES.includes(normalized as ItemRarity) ? normalized as ItemRarity : 'Common';
}

function inferredConversion(name: string) {
  const normalized = name.toLowerCase();
  const material = ['dragonscale', 'vaylium', 'mythril', 'steel'].find((entry) => normalized.startsWith(entry));
  if (!material) return { scaleItem: '', scaleQuantity: 0 };
  const scaleItem = `${material.charAt(0).toUpperCase()}${material.slice(1)} Scale`;
  const scaleQuantity = normalized.includes('dagger')
    ? 0.5
    : normalized.includes('battleaxe') || normalized.includes('mace')
      ? 2
      : normalized.includes('armor')
        ? 3
        : 1;
  return { scaleItem, scaleQuantity };
}

export function categoryToItemType(typeValue: unknown, itemNameValue: unknown): ItemType {
  const explicitType = text(typeValue).toLowerCase();
  const name = text(itemNameValue).toLowerCase();
  const combined = `${explicitType} ${name}`;

  if (combined.includes('spell book')) return 'spell book';
  if (combined.includes('book') || combined.includes('tome') || combined.includes('volume')) return 'book';
  if (combined.includes('coin') || combined.includes('currency') || combined.includes('callis') || combined.includes('callor')) return 'currency';
  if (combined.includes('rune')) return 'rune';
  if (ITEM_TYPES.includes(explicitType as ItemType)) return explicitType as ItemType;
  if (combined.includes('catalyst') || combined.includes('fang') || combined.includes('feather') || combined.includes('venom') || combined.includes('slime') || combined.includes('gland') || combined.includes('residue')) return 'catalyst';
  if (combined.includes('scale') || combined.includes('material')) return 'material';
  if (combined.includes('shield')) return 'shield';
  if (combined.includes('armor') || combined.includes('armour')) return 'armor';
  if (combined.includes('animal') || combined.includes('horse') || combined.includes('dog') || combined.includes('pet')) return 'pet';
  if (combined.includes('storage') || combined.includes('bag') || combined.includes('duffle') || combined.includes('pouch') || combined.includes('satchel') || combined.includes('wagon')) return 'storage';
  if (combined.includes('potion') || combined.includes('elixir') || combined.includes('nectar')) return 'potion';
  if (combined.includes('ore') || combined.includes('ingot') || combined.includes('metal')) return 'ore';
  if (combined.includes('food') || combined.includes('ration') || combined.includes('meal')) return 'food';
  if (combined.includes('plant') || combined.includes('herb') || combined.includes('flower') || combined.includes('root')) return 'plant';
  if (combined.includes('fabric') || combined.includes('cloth') || combined.includes('leather') || combined.includes('clothing') || combined.includes('cloak')) return 'fabric';
  if (combined.includes('scroll') || combined.includes('map') || combined.includes('lore')) return 'quest';
  if (combined.includes('belt') || combined.includes('ring') || combined.includes('jewel') || combined.includes('jewlery') || combined.includes('jewelry') || combined.includes('gem') || combined.includes('rune') || combined.includes('upgrade')) return 'accessory';
  if (combined.includes('tool') || combined.includes('gear') || combined.includes('rope') || combined.includes('torch') || combined.includes('blanket') || combined.includes('cooking pot') || combined.includes('ink and paper') || combined.includes('lock') || combined.includes('hammer') || combined.includes('axe')) return 'tool';
  if (combined.includes('weapon') || combined.includes('sword') || combined.includes('bow') || combined.includes('dagger') || combined.includes('spear') || combined.includes('mace') || combined.includes('staff') || combined.includes('wand') || combined.includes('arrows')) return 'weapon';
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
  const luckPotionOptions = valuesFromColumn(settingsRows, 4);
  const rollFormula = text(generator?.B5?.f);
  const multiplierFormula = text(generator?.D2?.f);
  const legendaryLuckFormula = text(generator?.F2?.f);
  const mythicalLuckFormula = text(generator?.F3?.f);
  const eligibilityFormula = text(helper?.J2?.f);
  const adjustedWeightFormula = text(helper?.K2?.f);
  const lootHeaders = headerMap(lootRows[0] ?? []);

  const rows = lootRows.slice(1).map((row) => {
    const name = text(getColumn(row, lootHeaders, ['Item', 'Name', 'Item Name'], 0))
      .replace(/\bMountian Rune\b/gi, 'Mountain Rune')
      .replace(/\bFine Clothe\b/gi, 'Fine Cloth')
      .replace(/\bCooking pots\b/gi, 'Cooking Pots')
      .replace(/\bInk and paper\b/gi, 'Ink and Paper')
      .replace(/\bStandard hammer\b/gi, 'Standard Hammer')
      .replace(/\bStandard axe\b/gi, 'Standard Axe')
      .replace(/\bWinter wear\b/gi, 'Winter Wear')
      .replace(/\bHeat wear\b/gi, 'Heat Wear')
      .replace(/\bRainproof wear\b/gi, 'Rainproof Wear')
      .replace(/\bBasic meal\b/gi, 'Basic Meal')
      .replace(/\bTavern meal\b/gi, 'Tavern Meal')
      .replace(/\bFine inn\b/gi, 'Fine Inn');
    if (!name) return null;
    const typeValue = getColumn(row, lootHeaders, ['Type', 'Category', 'Item Type'], 1);
    const type = categoryToItemType(typeValue, name);
    const pool = `${typeLabel(type)} Catalog`;
    const minQuantity = Math.max(0.5, number(getColumn(row, lootHeaders, ['Min Qty', 'Min Quantity', 'Minimum Quantity'], 7), 1));
    const inferred = inferredConversion(name);
    const convertScaleItem = text(getColumn(row, lootHeaders, ['Convert Material', 'Convert Scale Item', 'Convert Scale', 'Scale Item'], 12), inferred.scaleItem);
    const convertScaleNumber = optionalNumber(getColumn(row, lootHeaders, ['Convert Scale Number', 'Convert Scale Quantity', 'Scale Quantity'], 13), inferred.scaleQuantity);
    const isConvertible = booleanValue(getColumn(row, lootHeaders, ['Convertible'], 11));
    const canForgeDragonscaleScale = booleanValue(getColumn(row, lootHeaders, ['Can be crafted into Dragonscale Scales', 'Dragon Scale Fragment', 'Dragonscale Fragment'], 14));
    const canBeEnhanced = booleanValue(getColumn(row, lootHeaders, ['Can Be Enhanced', 'Can be enhanced', 'Enhanceable'], 15));
    const canBeEnchanted = booleanValue(getColumn(row, lootHeaders, ['Can Be Enchanted', 'Can be enchanted', 'Enchantable'], 16));
    return {
      pool,
      poolKey: `catalog-${slug(type)}`,
      name,
      type,
      biomes: splitList(getColumn(row, lootHeaders, ['Biomes', 'Biome'], 2)),
      minDifficulty: Math.max(1, number(getColumn(row, lootHeaders, ['Min Difficulty', 'Minimum Difficulty'], 3), 1)),
      maxDifficulty: Math.max(1, number(getColumn(row, lootHeaders, ['Max Difficulty', 'Maximum Difficulty'], 4), 5)),
      rarity: rarity(getColumn(row, lootHeaders, ['Rarity'], 5)),
      weight: Math.max(0, number(getColumn(row, lootHeaders, ['Loot Pool Weight', 'Weight', 'Base Weight'], 6), 1)),
      minQuantity,
      maxQuantity: Math.max(minQuantity, number(getColumn(row, lootHeaders, ['Max Qty', 'Max Quantity', 'Maximum Quantity'], 8), minQuantity)),
      towerBaseOnly: booleanValue(getColumn(row, lootHeaders, ['Tower and Base Only', 'Tower Base Only'], 9)),
      stackable: booleanValueDefault(getColumn(row, lootHeaders, ['Stackable', 'Is Stackable'], 10), true),
      convertible: isConvertible,
      convertScaleItem,
      convertScaleNumber,
      canForgeDragonscaleScale,
      canBeEnhanced,
      canBeEnchanted,
      notes: text(getColumn(row, lootHeaders, ['Notes', 'Description'], -1))
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
      luckPotionOptions: luckPotionOptions.length ? luckPotionOptions : ['None', 'Lesser', 'Greater', 'Greatest'],
      baseRollsByPoolSize: parseBaseRolls(rollFormula, poolSizes),
      poolMultipliers: parseSwitchMultipliers(multiplierFormula, '$B$3', poolSizes),
      roomMultipliers: parseSwitchMultipliers(multiplierFormula, '$B$4', roomTypes),
      luckPotionMultipliers: {
        None: { legendary: 1, mythical: 1 },
        Lesser: { legendary: 2, mythical: 2 },
        Greater: { legendary: 3, mythical: 3 },
        Greatest: { legendary: 3, mythical: 5 }
      },
      rareBoostRarities: parseRarityBoosts(adjustedWeightFormula),
      sourceFormulas: {
        lootRolls: rollFormula,
        multiplier: multiplierFormula,
        legendaryLuck: legendaryLuckFormula,
        mythicalLuck: mythicalLuckFormula,
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
