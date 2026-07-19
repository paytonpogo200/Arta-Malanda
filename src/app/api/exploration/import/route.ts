import { NextResponse, type NextRequest } from 'next/server';
import { normalizeExplorationPayload } from '@/features/exploration/data';
import { parseLootWorkbook } from '@/features/exploration/workbook';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

export async function POST(request: NextRequest) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in before importing loot.' }, { status: 401 });
    const contentType = request.headers.get('content-type') ?? '';
    let importPayload: unknown;

    if (contentType.includes('multipart/form-data')) {
      const form = await request.formData();
      const file = form.get('file');
      if (!(file instanceof File)) return NextResponse.json({ error: 'Choose a loot workbook first.' }, { status: 400 });
      const buffer = Buffer.from(await file.arrayBuffer());
      importPayload = parseLootWorkbook(buffer);
    } else {
      const body = await request.json().catch(() => ({}));
      importPayload = Array.isArray(body.rows) ? body.rows : body;
    }

    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });
    const { data, error } = await supabase.rpc('import_loot_items', {
      p_session_token: token,
      p_rows: importPayload
    });
    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    return NextResponse.json(normalizeExplorationPayload(data));
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Loot import failed.' }, { status: 500 });
  }
}
