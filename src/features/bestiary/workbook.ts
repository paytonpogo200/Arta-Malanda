import * as XLSX from 'xlsx';
import type { BestiaryCategoryRecord } from '@/lib/types';

export type ParsedBestiaryEntity = {
  key: string;
  name: string;
  category: string;
  hp: number;
  mana: number;
  wildScore: number;
  summary: string;
  details: string;
  stats: Record<string, string>;
  order: number;
};

export type ParsedBestiaryWorkbook = {
  categories: BestiaryCategoryRecord[];
  entities: ParsedBestiaryEntity[];
};

function clean(value: unknown) {
  return String(value ?? '').replace(/\s+/g, ' ').trim();
}

function slugify(value: string) {
  return clean(value)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '') || 'entry';
}

function entityKey(categoryKey: string, name: string) {
  const nameKey = slugify(name);
  return categoryKey === 'bosses' ? `boss-${nameKey}` : `${categoryKey}-${nameKey}`;
}

function numberFrom(value: unknown) {
  const parsed = Number(clean(value).replace(/[^\d.-]/g, ''));
  return Number.isFinite(parsed) ? Math.max(0, parsed) : 0;
}

function filledCells(row: unknown[]) {
  return row.map(clean).filter(Boolean);
}

function rowWidth(row: unknown[]) {
  let width = 0;
  row.forEach((value, index) => {
    if (clean(value)) width = index + 1;
  });
  return width;
}

function isHeaderRow(row: unknown[]) {
  const first = clean(row[0]).toLowerCase();
  const cells = filledCells(row).map((cell) => cell.toLowerCase());
  return ['beast', 'creature', 'monster', 'animal', 'entity'].includes(first)
    && (cells.includes('hp') || cells.includes('damage') || cells.includes('wild score'));
}

function statValue(value: unknown) {
  const text = clean(value);
  return text && text !== '—' ? text : '';
}

const CATEGORY_FILL = '244062';
const HEADER_FILL = 'D9EAF7';

function cellFill(sheet: XLSX.WorkSheet, row: number, column: number) {
  const cell = sheet[XLSX.utils.encode_cell({ r: row, c: column })] as XLSX.CellObject & { s?: { fgColor?: { rgb?: string } } } | undefined;
  return cell?.s?.fgColor?.rgb?.toUpperCase() ?? '';
}

function rowHasFill(sheet: XLSX.WorkSheet, row: number, fill: string) {
  const range = XLSX.utils.decode_range(sheet['!ref'] ?? 'A1:A1');
  for (let column = range.s.c; column <= range.e.c; column += 1) {
    if (cellFill(sheet, row, column) === fill) return true;
  }
  return false;
}

export function parseBestiaryWorkbook(buffer: ArrayBuffer): ParsedBestiaryWorkbook {
  const workbook = XLSX.read(buffer, { type: 'array', cellFormula: true, cellDates: false, cellStyles: true });
  const sheetName = workbook.SheetNames.includes('Bestiary') ? 'Bestiary' : workbook.SheetNames[0];
  const sheet = workbook.Sheets[sheetName];
  if (!sheet) return { categories: [], entities: [] };

  const rows = XLSX.utils.sheet_to_json<unknown[]>(sheet, { header: 1, defval: '', blankrows: true });
  const categories = new Map<string, BestiaryCategoryRecord>();
  const entities = new Map<string, ParsedBestiaryEntity>();
  let currentCategoryKey = '';
  let headers: string[] = [];
  let categoryOrder = 0;
  let entityOrder = 0;

  function ensureCategory(name: string) {
    const categoryName = clean(name) || 'Unsorted';
    const key = slugify(categoryName);
    if (!categories.has(key)) {
      categories.set(key, { key, name: categoryName, hidden: false, order: categoryOrder });
      categoryOrder += 10;
    }
    return key;
  }

  for (let rowIndex = 0; rowIndex < rows.length; rowIndex += 1) {
    const row = rows[rowIndex];
    const values = filledCells(row);
    if (!values.length) continue;

    if (rowHasFill(sheet, rowIndex, CATEGORY_FILL)) {
      currentCategoryKey = ensureCategory(values[0]);
      headers = [];
      continue;
    }

    if (currentCategoryKey && (rowHasFill(sheet, rowIndex, HEADER_FILL) || isHeaderRow(row))) {
      const width = rowWidth(row);
      headers = row.slice(0, width).map((value) => clean(value));
      continue;
    }

    if (!currentCategoryKey || !headers.length) continue;

    const name = clean(row[0]);
    if (!name) continue;

    const stats: Record<string, string> = {};
    headers.forEach((header, index) => {
      if (index === 0 || !header) return;
      const value = statValue(row[index]);
      if (value) stats[header] = value;
    });

    const special = stats['Special Effects'] ?? stats['Special Effect'] ?? '';
    const key = entityKey(currentCategoryKey, name);
    entities.set(key, {
      key,
      name,
      category: currentCategoryKey,
      hp: numberFrom(stats.HP),
      mana: numberFrom(stats['Mana Pool'] ?? stats.Mana),
      wildScore: numberFrom(stats['Wild Score']),
      summary: special,
      details: '',
      stats,
      order: entityOrder
    });
    entityOrder += 10;
  }

  return {
    categories: Array.from(categories.values()),
    entities: Array.from(entities.values())
  };
}
