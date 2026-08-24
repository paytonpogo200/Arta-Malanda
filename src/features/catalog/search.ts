import type { ItemCatalogEntry } from '@/lib/types';

function normalizeSearchText(value: string) {
  return value.toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
}

function searchWords(value: string) {
  return normalizeSearchText(value).split(/\s+/).filter(Boolean);
}

export function matchesCatalogNameSearch(item: Pick<ItemCatalogEntry, 'name' | 'key'>, query: string) {
  const needle = normalizeSearchText(query);
  if (!needle) return true;

  const name = normalizeSearchText(item.name);
  const key = normalizeSearchText(item.key);
  if (name.includes(needle) || key.includes(needle)) return true;

  const nameWords = searchWords(item.name);
  const keyWords = searchWords(item.key);
  return searchWords(query).every((part) => (
    nameWords.some((word) => word.startsWith(part))
    || keyWords.some((word) => word.startsWith(part))
  ));
}
