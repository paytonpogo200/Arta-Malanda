import { NextResponse, type NextRequest } from 'next/server';
import { normalizeWorldMapPayload } from '@/features/world-map/data';
import { createAuthDatabaseClient } from '@/lib/auth/database';
import { readSessionToken } from '@/lib/auth/session';

const MAX_IMAGE_BYTES = 8 * 1024 * 1024;
const ALLOWED_IMAGE_TYPES = new Set(['image/png', 'image/jpeg', 'image/webp', 'image/gif']);

function bufferToDataUrl(buffer: ArrayBuffer, mimeType: string) {
  return `data:${mimeType};base64,${Buffer.from(buffer).toString('base64')}`;
}

export async function GET() {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in to view the world map.' }, { status: 401 });

    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('get_world_map', { p_session_token: token });
    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    return NextResponse.json(normalizeWorldMapPayload(data));
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'World map could not be loaded.' }, { status: 500 });
  }
}

export async function POST(request: NextRequest) {
  try {
    const token = await readSessionToken();
    if (!token) return NextResponse.json({ error: 'Log in before updating the world map.' }, { status: 401 });

    const form = await request.formData();
    const file = form.get('image');
    if (!(file instanceof File)) return NextResponse.json({ error: 'Choose an image to upload.' }, { status: 400 });
    if (!ALLOWED_IMAGE_TYPES.has(file.type)) return NextResponse.json({ error: 'Upload a PNG, JPEG, WEBP, or GIF image.' }, { status: 400 });
    if (file.size <= 0) return NextResponse.json({ error: 'The uploaded image was empty.' }, { status: 400 });
    if (file.size > MAX_IMAGE_BYTES) return NextResponse.json({ error: 'World map image must be 8 MB or smaller after map optimization.' }, { status: 400 });

    const supabase = createAuthDatabaseClient();
    if (!supabase) return NextResponse.json({ error: 'The campaign database is not connected yet.' }, { status: 503 });

    const { data, error } = await supabase.rpc('upload_world_map', {
      p_session_token: token,
      p_image_data_url: bufferToDataUrl(await file.arrayBuffer(), file.type),
      p_mime_type: file.type,
      p_file_name: file.name || 'world-map'
    });

    if (error) return NextResponse.json({ error: error.message, code: error.code, details: error.details, hint: error.hint }, { status: 400 });
    return NextResponse.json(normalizeWorldMapPayload(data));
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'World map could not be updated.' }, { status: 500 });
  }
}
