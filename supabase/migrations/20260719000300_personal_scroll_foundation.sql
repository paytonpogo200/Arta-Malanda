-- Personal Scroll foundation.

create table if not exists public.personal_scrolls (
  profile_id uuid primary key references public.profiles(id) on delete cascade,
  content_html text not null default '<p><br></p>',
  drawing_data_url text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.personal_scrolls enable row level security;
revoke all on public.personal_scrolls from anon, authenticated;

drop trigger if exists personal_scrolls_touch_updated_at on public.personal_scrolls;
create trigger personal_scrolls_touch_updated_at
before update on public.personal_scrolls
for each row execute function public.touch_updated_at();

create or replace function public.personal_scroll_record_to_json(p_scroll public.personal_scrolls)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'profileId', p_scroll.profile_id,
    'contentHtml', p_scroll.content_html,
    'drawingDataUrl', p_scroll.drawing_data_url,
    'updatedAt', p_scroll.updated_at
  )
$$;

create or replace function public.get_personal_scroll(p_session_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_scroll public.personal_scrolls%rowtype;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;

  insert into public.personal_scrolls (profile_id)
  values (v_profile.id)
  on conflict (profile_id) do nothing;

  select * into v_scroll
  from public.personal_scrolls
  where profile_id = v_profile.id;

  return public.personal_scroll_record_to_json(v_scroll);
end;
$$;

create or replace function public.update_personal_scroll(
  p_session_token text,
  p_content_html text,
  p_drawing_data_url text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_scroll public.personal_scrolls%rowtype;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;

  insert into public.personal_scrolls (
    profile_id,
    content_html,
    drawing_data_url
  )
  values (
    v_profile.id,
    coalesce(nullif(p_content_html, ''), '<p><br></p>'),
    coalesce(p_drawing_data_url, '')
  )
  on conflict (profile_id) do update
  set content_html = excluded.content_html,
      drawing_data_url = excluded.drawing_data_url;

  select * into v_scroll
  from public.personal_scrolls
  where profile_id = v_profile.id;

  return public.personal_scroll_record_to_json(v_scroll);
end;
$$;

grant execute on function public.personal_scroll_record_to_json(public.personal_scrolls) to anon, authenticated;
grant execute on function public.get_personal_scroll(text) to anon, authenticated;
grant execute on function public.update_personal_scroll(text, text, text) to anon, authenticated;
