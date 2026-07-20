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

export type ParsedBestiaryMarkdown = {
  categories: BestiaryCategoryRecord[];
  entities: ParsedBestiaryEntity[];
};

const SKIP_TABLE_HEADERS = new Set(['hp benchmark']);

function cleanCell(value: string) {
  return value
    .replace(/<br\s*\/?>/gi, ' ')
    .replace(/\*\*/g, '')
    .replace(/&nbsp;/g, ' ')
    .replace(/[—–]/g, '—')
    .replace(/\s+/g, ' ')
    .trim();
}

function slugify(value: string) {
  return cleanCell(value)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '') || 'entry';
}

function numberFrom(value: string) {
  const parsed = Number(cleanCell(value).replace(/[^\d.-]/g, ''));
  return Number.isFinite(parsed) ? Math.max(0, parsed) : 0;
}

function splitTableRow(line: string) {
  return line
    .trim()
    .replace(/^\|/, '')
    .replace(/\|$/, '')
    .split('|')
    .map(cleanCell);
}

function isSeparatorRow(line: string) {
  return /^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)+\|?\s*$/.test(line);
}

function normalizeHeader(header: string) {
  return cleanCell(header)
    .replace(/\s*\/\s*/g, ' / ')
    .replace(/\s+/g, ' ')
    .trim();
}

function isCreatureTable(headers: string[]) {
  const first = headers[0]?.toLowerCase() ?? '';
  if (!first || SKIP_TABLE_HEADERS.has(first)) return false;
  if (headers.some((header) => /^creature$/i.test(header))) return true;
  if (headers.some((header) => /^spells?$/i.test(header)) && headers.some((header) => /mana/i.test(header))) return true;
  return headers.some((header) => /^hp$/i.test(header) || /^damage$/i.test(header) || /special effects?/i.test(header));
}

function mergeDetails(current: string, addition: string) {
  const clean = cleanCell(addition);
  if (!clean || clean === '—') return current;
  if (!current) return clean;
  if (current.includes(clean)) return current;
  return `${current}\n${clean}`;
}

export function parseBestiaryMarkdown(markdown: string): ParsedBestiaryMarkdown {
  const lines = markdown.replace(/\r\n/g, '\n').split('\n');
  const categories = new Map<string, BestiaryCategoryRecord>();
  const entities = new Map<string, ParsedBestiaryEntity>();
  let currentCategoryName = 'Unsorted';
  let categoryOrder = 0;
  let entityOrder = 0;

  function ensureCategory(name: string) {
    const cleanName = cleanCell(name) || 'Unsorted';
    const key = slugify(cleanName);
    if (!categories.has(key)) {
      categories.set(key, { key, name: cleanName, hidden: false, order: categoryOrder });
      categoryOrder += 10;
    }
    return key;
  }

  ensureCategory(currentCategoryName);

  for (let index = 0; index < lines.length; index += 1) {
    const heading = lines[index].match(/^\s{0,3}#{1,3}\s+(.+?)\s*$/);
    if (heading) {
      currentCategoryName = cleanCell(heading[1]);
      ensureCategory(currentCategoryName);
      continue;
    }

    if (!lines[index].trim().startsWith('|') || !lines[index + 1] || !isSeparatorRow(lines[index + 1])) continue;

    const headers = splitTableRow(lines[index]).map(normalizeHeader);
    if (!isCreatureTable(headers)) continue;

    const categoryKey = ensureCategory(currentCategoryName);
    index += 2;

    while (index < lines.length && lines[index].trim().startsWith('|')) {
      const cells = splitTableRow(lines[index]);
      const row: Record<string, string> = {};
      headers.forEach((header, headerIndex) => {
        row[header] = cleanCell(cells[headerIndex] ?? '');
      });

      const nameHeader = headers.find((header) => /^creature$/i.test(header)) ?? headers[0];
      const name = cleanCell(row[nameHeader] ?? '');
      if (!name || name === '—') {
        index += 1;
        continue;
      }

      const key = `${categoryKey}-${slugify(name)}`;
      const stats: Record<string, string> = {};
      for (const header of headers) {
        if (header === nameHeader) continue;
        const value = cleanCell(row[header] ?? '');
        if (value && value !== '—') stats[header] = value;
      }

      const special = stats['Special Effects'] ?? stats['Special Effect'] ?? '';
      const spells = stats.Spells ? `Spells: ${stats.Spells}` : '';
      const role = stats.Role ? `Role: ${stats.Role}` : '';
      const manaText = stats['Mana Pool'] ?? stats.Mana ?? '';
      const detailAddition = [spells, role].filter(Boolean).join('\n');

      const existing = entities.get(key);
      if (existing) {
        existing.stats = { ...existing.stats, ...stats };
        existing.hp = existing.hp || numberFrom(stats.HP ?? '');
        existing.mana = existing.mana || numberFrom(manaText);
        existing.wildScore = existing.wildScore || numberFrom(stats['Wild Score'] ?? '');
        existing.summary = existing.summary || (special && special !== '—' ? special : '');
        existing.details = mergeDetails(existing.details, detailAddition);
      } else {
        entities.set(key, {
          key,
          name,
          category: categoryKey,
          hp: numberFrom(stats.HP ?? ''),
          mana: numberFrom(manaText),
          wildScore: numberFrom(stats['Wild Score'] ?? ''),
          summary: special && special !== '—' ? special : '',
          details: detailAddition,
          stats,
          order: entityOrder
        });
        entityOrder += 10;
      }

      index += 1;
    }
    index -= 1;
  }

  return {
    categories: Array.from(categories.values()),
    entities: Array.from(entities.values())
  };
}
