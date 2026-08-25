'use client';

import { BookOpen } from 'lucide-react';
import type { ReactNode } from 'react';
import { Button } from '@/components/ui/Button';

export const BOOK_PAGE_MAX_CHARS = 950;

function splitLongPage(page: string) {
  const normalized = page.trim();
  if (normalized.length <= BOOK_PAGE_MAX_CHARS) return [normalized];

  const pages: string[] = [];
  let remaining = normalized;
  while (remaining.length > BOOK_PAGE_MAX_CHARS) {
    const slice = remaining.slice(0, BOOK_PAGE_MAX_CHARS);
    const breakAt = Math.max(slice.lastIndexOf('\n\n'), slice.lastIndexOf('. '), slice.lastIndexOf(' '));
    const index = breakAt > BOOK_PAGE_MAX_CHARS * 0.58 ? breakAt + (slice[breakAt] === '.' ? 1 : 0) : BOOK_PAGE_MAX_CHARS;
    pages.push(remaining.slice(0, index).trim());
    remaining = remaining.slice(index).trim();
  }
  if (remaining) pages.push(remaining);
  return pages;
}

export function pagesFromBookContent(content: string) {
  const rawPages = content
    .split(/\n\s*---+\s*page\s*---+\s*\n|\f/gi)
    .map((page) => page.trim())
    .filter(Boolean);
  const pages = (rawPages.length ? rawPages : [content.trim()])
    .flatMap(splitLongPage)
    .filter(Boolean);
  return pages.length ? pages : [''];
}

export function bookContentFromPages(pages: string[]) {
  return pages.map((page) => page.trim()).filter(Boolean).join('\n\n--- page ---\n\n');
}

function totalSpreads(pageCount: number) {
  if (pageCount <= 1) return 1;
  return 1 + Math.ceil(Math.max(0, pageCount - 1) / 2);
}

function spreadStartForIndex(spreadIndex: number) {
  return spreadIndex <= 0 ? 0 : 1 + (spreadIndex - 1) * 2;
}

function titleSizeClass(title: string) {
  if (title.length > 46) return 'text-2xl sm:text-3xl';
  if (title.length > 28) return 'text-3xl sm:text-4xl';
  return 'text-4xl sm:text-5xl';
}

function BookCover({ title, author }: { title: string; author?: string; label?: string }) {
  const displayTitle = title || 'Untitled Book';

  return (
    <div className="book-cover-page">
      <div className="book-cover-spine" />
      <div className="book-cover-corner book-cover-corner-top" />
      <div className="book-cover-corner book-cover-corner-bottom" />
      <div className="book-cover-ornament">
        <BookOpen size={32} />
      </div>
      <div className="book-cover-title-panel">
        <p className="book-cover-kicker">Bound Volume</p>
        <h4 className={`book-cover-title ${titleSizeClass(displayTitle)}`}>{displayTitle}</h4>
        {author && <p className="book-cover-author">By {author}</p>}
      </div>
    </div>
  );
}

function BookPage({ pageNumber, text }: { pageNumber: number; text: string }) {
  const readableText = text.replace(/\S{28,}/g, (word) => word.match(/.{1,18}/g)?.join('\u00ad') ?? word);

  return (
    <article className="book-page">
      <div className="book-page-content">
        <p className="book-page-number">Page {pageNumber}</p>
        <p className="book-page-text" lang="en">{readableText || 'Blank page.'}</p>
      </div>
    </article>
  );
}

export function BookReader({
  title,
  author,
  pages,
  label,
  spreadIndex,
  onSpreadChange,
  editableAction
}: {
  title: string;
  author?: string;
  pages: string[];
  label?: string;
  spreadIndex: number;
  onSpreadChange: (index: number) => void;
  editableAction?: ReactNode;
}) {
  const normalizedPages = (pages.length ? pages : ['']).flatMap(splitLongPage);
  const spreadCount = totalSpreads(normalizedPages.length);
  const safeSpread = Math.min(Math.max(0, spreadIndex), spreadCount - 1);
  const start = spreadStartForIndex(safeSpread);
  const leftPage = safeSpread === 0 ? '' : normalizedPages[start] ?? '';
  const rightPage = safeSpread === 0 ? normalizedPages[0] ?? '' : normalizedPages[start + 1] ?? '';
  const leftPageNumber = start + 1;
  const rightPageNumber = safeSpread === 0 ? 1 : start + 2;

  return (
    <div className="book-reader">
      <div className="book-spread-shell">
        <div className="book-spread">
          {safeSpread === 0 ? (
            <BookCover title={title} author={author} label={label} />
          ) : (
            <BookPage pageNumber={leftPageNumber} text={leftPage} />
          )}
          <BookPage pageNumber={rightPageNumber} text={rightPage} />
        </div>
      </div>
      <div className="mt-3 grid gap-2 sm:grid-cols-[1fr_auto_1fr] sm:items-center">
        <Button variant="secondary" disabled={safeSpread <= 0} onClick={() => onSpreadChange(safeSpread - 1)}>Previous spread</Button>
        <span className="text-center text-xs font-black uppercase tracking-wider text-[var(--muted)]">
          Spread {safeSpread + 1} / {spreadCount}
        </span>
        <Button variant="secondary" disabled={safeSpread >= spreadCount - 1} onClick={() => onSpreadChange(safeSpread + 1)}>Next spread</Button>
      </div>
      {editableAction && <div className="mt-3">{editableAction}</div>}
    </div>
  );
}
