import { NextResponse, type NextRequest } from 'next/server';
import { normalizeCitiesPayload } from '@/features/cities/data';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

export async function POST(request: NextRequest) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in as the Dungeon Master before adding shop items.' }, { status: 401 });

    const body = await request.json().catch(() => ({}));
    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const isBulkCreate = Array.isArray(body.products);
    const { data, error } = await supabase.rpc(isBulkCreate ? 'create_market_products' : 'create_market_product', isBulkCreate ? {
      p_session_token: token,
      p_vendor_id: body.vendorId,
      p_patches: body.products
    } : {
      p_session_token: token,
      p_vendor_id: body.vendorId,
      p_patch: body
    });

    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    return NextResponse.json(normalizeCitiesPayload(data));
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Shop items could not be added.' }, { status: 500 });
  }
}
