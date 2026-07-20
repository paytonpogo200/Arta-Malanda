-- Flexible bestiary categories, full stat storage, and Markdown import.

alter table public.bestiary_entities
drop constraint if exists bestiary_entities_category_check;

alter table public.bestiary_entities
add column if not exists stats jsonb not null default '{}'::jsonb;

create table if not exists public.bestiary_categories (
  category_key text primary key,
  name text not null,
  is_hidden boolean not null default false,
  display_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.bestiary_categories enable row level security;
revoke all on public.bestiary_categories from anon, authenticated;

drop trigger if exists bestiary_categories_touch_updated_at on public.bestiary_categories;
create trigger bestiary_categories_touch_updated_at
before update on public.bestiary_categories
for each row execute function public.touch_updated_at();

insert into public.bestiary_categories (category_key, name, display_order)
values
  ('animal', 'Animal', 10),
  ('beast', 'Beast', 20),
  ('being', 'Being', 30),
  ('monster', 'Monster', 40),
  ('spirit', 'Spirit', 50)
on conflict (category_key) do update
set name = excluded.name,
    display_order = excluded.display_order;

insert into public.bestiary_categories (category_key, name, display_order)
select distinct
  e.category,
  initcap(replace(e.category, '-', ' ')),
  1000
from public.bestiary_entities e
where not exists (
  select 1 from public.bestiary_categories c where c.category_key = e.category
);

create or replace function public.bestiary_category_record_to_json(p_category public.bestiary_categories)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'key', p_category.category_key,
    'name', p_category.name,
    'hidden', p_category.is_hidden,
    'order', p_category.display_order
  )
$$;

create or replace function public.bestiary_entity_record_to_json(p_entity public.bestiary_entities)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'id', p_entity.id,
    'key', p_entity.entity_key,
    'name', p_entity.name,
    'category', p_entity.category,
    'habitat', p_entity.habitat,
    'temperament', p_entity.temperament,
    'wildScore', p_entity.wild_score,
    'hp', p_entity.hp,
    'mana', p_entity.mana,
    'summary', p_entity.summary,
    'details', p_entity.details,
    'stats', p_entity.stats,
    'unlocked', p_entity.is_unlocked,
    'order', p_entity.display_order
  )
$$;

create or replace function public.get_bestiary(p_session_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_is_dm boolean;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;
  v_is_dm := v_profile.role = 'dm'::public.user_role;

  return jsonb_build_object(
    'categories', (
      select coalesce(jsonb_agg(public.bestiary_category_record_to_json(c) order by c.display_order, c.name), '[]'::jsonb)
      from public.bestiary_categories c
      where v_is_dm or not c.is_hidden
    ),
    'entities', (
      select coalesce(jsonb_agg(public.bestiary_entity_record_to_json(e) order by coalesce(c.display_order, 999999), e.display_order, e.name), '[]'::jsonb)
      from public.bestiary_entities e
      left join public.bestiary_categories c on c.category_key = e.category
      where (v_is_dm or e.is_unlocked)
        and (v_is_dm or coalesce(c.is_hidden, false) = false)
    ),
    'unlockedCount', (
      select count(*)
      from public.bestiary_entities e
      left join public.bestiary_categories c on c.category_key = e.category
      where e.is_unlocked
        and (v_is_dm or coalesce(c.is_hidden, false) = false)
    ),
    'totalCount', (
      select count(*)
      from public.bestiary_entities e
      left join public.bestiary_categories c on c.category_key = e.category
      where v_is_dm or (e.is_unlocked and coalesce(c.is_hidden, false) = false)
    )
  );
end;
$$;

create or replace function public.update_bestiary_category(
  p_session_token text,
  p_category_key text,
  p_patch jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_patch jsonb := coalesce(p_patch, '{}'::jsonb);
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;
  if v_profile.role <> 'dm'::public.user_role then raise exception 'Only the Dungeon Master can update bestiary categories.'; end if;

  insert into public.bestiary_categories (category_key, name, display_order)
  values (p_category_key, initcap(replace(p_category_key, '-', ' ')), 1000)
  on conflict (category_key) do nothing;

  update public.bestiary_categories
  set
    name = case when v_patch ? 'name' then coalesce(nullif(trim(v_patch->>'name'), ''), name) else name end,
    is_hidden = case when v_patch ? 'hidden' then (v_patch->>'hidden')::boolean else is_hidden end,
    display_order = case when v_patch ? 'order' then (v_patch->>'order')::int else display_order end
  where category_key = p_category_key;

  return public.get_bestiary(p_session_token);
end;
$$;

create or replace function public.update_bestiary_entity(
  p_session_token text,
  p_entity_id uuid,
  p_patch jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_patch jsonb := coalesce(p_patch, '{}'::jsonb);
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;
  if v_profile.role <> 'dm'::public.user_role then raise exception 'Only the Dungeon Master can update the bestiary.'; end if;

  if v_patch ? 'category' then
    insert into public.bestiary_categories (category_key, name, display_order)
    values (coalesce(nullif(v_patch->>'category', ''), 'beast'), initcap(replace(coalesce(nullif(v_patch->>'category', ''), 'beast'), '-', ' ')), 1000)
    on conflict (category_key) do nothing;
  end if;

  update public.bestiary_entities
  set
    is_unlocked = case when v_patch ? 'unlocked' then (v_patch->>'unlocked')::boolean else is_unlocked end,
    name = case when v_patch ? 'name' then coalesce(nullif(trim(v_patch->>'name'), ''), name) else name end,
    category = case when v_patch ? 'category' then coalesce(nullif(v_patch->>'category', ''), category) else category end,
    habitat = case when v_patch ? 'habitat' then coalesce(v_patch->>'habitat', '') else habitat end,
    temperament = case when v_patch ? 'temperament' then coalesce(v_patch->>'temperament', '') else temperament end,
    wild_score = case when v_patch ? 'wildScore' then greatest(0, (v_patch->>'wildScore')::int) else wild_score end,
    hp = case when v_patch ? 'hp' then greatest(0, (v_patch->>'hp')::int) else hp end,
    mana = case when v_patch ? 'mana' then greatest(0, (v_patch->>'mana')::int) else mana end,
    summary = case when v_patch ? 'summary' then coalesce(v_patch->>'summary', '') else summary end,
    details = case when v_patch ? 'details' then coalesce(v_patch->>'details', '') else details end,
    stats = case when v_patch ? 'stats' then coalesce(v_patch->'stats', '{}'::jsonb) else stats end,
    display_order = case when v_patch ? 'order' then (v_patch->>'order')::int else display_order end
  where id = p_entity_id;

  return public.get_bestiary(p_session_token);
end;
$$;

create or replace function public.import_bestiary_markdown(
  p_session_token text,
  p_categories jsonb,
  p_entities jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_category jsonb;
  v_entity jsonb;
  v_category_key text;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;
  if v_profile.role <> 'dm'::public.user_role then raise exception 'Only the Dungeon Master can import the bestiary.'; end if;

  for v_category in select value from jsonb_array_elements(coalesce(p_categories, '[]'::jsonb))
  loop
    v_category_key := coalesce(nullif(v_category->>'key', ''), 'unsorted');
    insert into public.bestiary_categories (category_key, name, display_order)
    values (
      v_category_key,
      coalesce(nullif(v_category->>'name', ''), initcap(replace(v_category_key, '-', ' '))),
      coalesce((v_category->>'order')::int, 1000)
    )
    on conflict (category_key) do update
    set name = excluded.name,
        display_order = excluded.display_order;
  end loop;

  for v_entity in select value from jsonb_array_elements(coalesce(p_entities, '[]'::jsonb))
  loop
    v_category_key := coalesce(nullif(v_entity->>'category', ''), 'unsorted');
    insert into public.bestiary_categories (category_key, name, display_order)
    values (v_category_key, initcap(replace(v_category_key, '-', ' ')), 1000)
    on conflict (category_key) do nothing;

    insert into public.bestiary_entities (
      entity_key,
      name,
      category,
      hp,
      mana,
      wild_score,
      summary,
      details,
      stats,
      display_order
    )
    values (
      coalesce(nullif(v_entity->>'key', ''), gen_random_uuid()::text),
      coalesce(nullif(v_entity->>'name', ''), 'Unknown Entity'),
      v_category_key,
      greatest(0, coalesce((v_entity->>'hp')::int, 0)),
      greatest(0, coalesce((v_entity->>'mana')::int, 0)),
      greatest(0, coalesce((v_entity->>'wildScore')::int, 0)),
      coalesce(v_entity->>'summary', ''),
      coalesce(v_entity->>'details', ''),
      coalesce(v_entity->'stats', '{}'::jsonb),
      coalesce((v_entity->>'order')::int, 0)
    )
    on conflict (entity_key) do update
    set name = excluded.name,
        category = excluded.category,
        hp = excluded.hp,
        mana = excluded.mana,
        wild_score = excluded.wild_score,
        summary = excluded.summary,
        details = excluded.details,
        stats = excluded.stats,
        display_order = excluded.display_order;
  end loop;

  return public.get_bestiary(p_session_token);
end;
$$;

create or replace function public.update_shop_vendor(
  p_session_token text,
  p_vendor_id uuid,
  p_patch jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_patch jsonb := coalesce(p_patch, '{}'::jsonb);
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then
    raise exception 'Invalid or expired session.';
  end if;

  if v_profile.role <> 'dm'::public.user_role then
    raise exception 'Only the Dungeon Master can change shop details.';
  end if;

  update public.shop_vendors
  set
    name = case when v_patch ? 'name' then coalesce(nullif(trim(v_patch->>'name'), ''), name) else name end,
    npc_name = case when v_patch ? 'npcName' then coalesce(nullif(trim(v_patch->>'npcName'), ''), npc_name) else npc_name end,
    facility = case when v_patch ? 'facility' then coalesce(nullif(trim(v_patch->>'facility'), ''), facility) else facility end,
    category = case when v_patch ? 'category' then coalesce(nullif(trim(v_patch->>'category'), ''), category) else category end,
    is_hidden = case when v_patch ? 'hidden' then (v_patch->>'hidden')::boolean else is_hidden end,
    display_order = case when v_patch ? 'order' then (v_patch->>'order')::int else display_order end
  where id = p_vendor_id;

  return public.get_discovered_cities(p_session_token);
end;
$$;

grant execute on function public.bestiary_category_record_to_json(public.bestiary_categories) to anon, authenticated;
grant execute on function public.bestiary_entity_record_to_json(public.bestiary_entities) to anon, authenticated;
grant execute on function public.get_bestiary(text) to anon, authenticated;
grant execute on function public.update_bestiary_category(text, text, jsonb) to anon, authenticated;
grant execute on function public.update_bestiary_entity(text, uuid, jsonb) to anon, authenticated;
grant execute on function public.import_bestiary_markdown(text, jsonb, jsonb) to anon, authenticated;
grant execute on function public.update_shop_vendor(text, uuid, jsonb) to anon, authenticated;
