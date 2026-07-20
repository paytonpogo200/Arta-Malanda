import { NextResponse, type NextRequest } from 'next/server';
import { normalizeBestiaryPayload } from '@/features/bestiary/data';
import { parseBestiaryMarkdown } from '@/features/bestiary/markdown';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

export async function POST(request: NextRequest) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in as the Dungeon Master before importing the bestiary.' }, { status: 401 });

    const body = await request.json().catch(() => ({}));
    const markdown = String(body.markdown ?? '').trim();
    if (!markdown) return NextResponse.json({ error: 'Choose a Markdown file before importing.' }, { status: 400 });

    const parsed = parseBestiaryMarkdown(markdown);
    if (!parsed.entities.length) return NextResponse.json({ error: 'No bestiary creature tables were found in that Markdown file.' }, { status: 400 });

    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('import_bestiary_markdown', {
      p_session_token: token,
      p_categories: parsed.categories,
      p_entities: parsed.entities
    });

    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    return NextResponse.json(normalizeBestiaryPayload(data));
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Bestiary import failed.' }, { status: 500 });
  }
}
