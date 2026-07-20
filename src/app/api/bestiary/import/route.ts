import { NextResponse, type NextRequest } from 'next/server';
import { normalizeBestiaryPayload } from '@/features/bestiary/data';
import { parseBestiaryWorkbook } from '@/features/bestiary/workbook';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

export async function POST(request: NextRequest) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in as the Dungeon Master before importing the bestiary.' }, { status: 401 });

    const form = await request.formData();
    const file = form.get('file');
    if (!(file instanceof File)) return NextResponse.json({ error: 'Choose an Excel bestiary file before importing.' }, { status: 400 });

    const parsed = parseBestiaryWorkbook(await file.arrayBuffer());
    if (!parsed.entities.length) return NextResponse.json({ error: 'No bestiary creature rows were found in that workbook.' }, { status: 400 });

    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('import_bestiary_workbook', {
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
