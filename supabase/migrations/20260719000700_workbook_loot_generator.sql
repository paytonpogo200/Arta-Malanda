-- Workbook-backed loot generator.

create table if not exists public.loot_generator_configs (
  id text primary key default 'default',
  settings jsonb not null default '{}'::jsonb,
  source jsonb not null default '{}'::jsonb,
  imported_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.loot_generator_configs enable row level security;
revoke all on public.loot_generator_configs from anon, authenticated;

drop trigger if exists loot_generator_configs_touch_updated_at on public.loot_generator_configs;
create trigger loot_generator_configs_touch_updated_at
before update on public.loot_generator_configs
for each row execute function public.touch_updated_at();

alter table public.loot_items add column if not exists category text not null default '';
alter table public.loot_items add column if not exists biomes text[] not null default array['Any']::text[];
alter table public.loot_items add column if not exists min_difficulty int not null default 1 check (min_difficulty >= 1);
alter table public.loot_items add column if not exists max_difficulty int not null default 5 check (max_difficulty >= min_difficulty);
alter table public.loot_items add column if not exists base_weight int not null default 1 check (base_weight >= 1);

update public.loot_items
set base_weight = greatest(1, weight)
where base_weight is null or base_weight < 1;

create index if not exists loot_items_generator_filter_idx
  on public.loot_items (is_active, min_difficulty, max_difficulty, rarity);

insert into public.loot_generator_configs (id, settings)
values (
  'default',
  jsonb_build_object(
    'biomes', jsonb_build_array('Any'),
    'difficulties', jsonb_build_array(1, 2, 3, 4, 5),
    'poolSizes', jsonb_build_array('Night Encounter', 'Small Cave', 'Medium Cave', 'Large Cave', 'Dragon Lair', 'Tower Floor', 'Base'),
    'roomTypes', jsonb_build_array('Normal', 'Secret Room', 'Tower Boss Room'),
    'baseRollsByPoolSize', jsonb_build_object('Night Encounter', 5, 'Small Cave', 10, 'Medium Cave', 15, 'Large Cave', 20, 'Dragon Lair', 50, 'Tower Floor', 25, 'Base', 40),
    'rareMultiplierKeywords', jsonb_build_object('capital', 5, 'base', 2, 'camp', 1.33),
    'sourceFormulas', '{}'::jsonb
  )
)
on conflict (id) do nothing;

create or replace function public.loot_item_record_to_json(p_item public.loot_items)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'id', p_item.id,
    'poolId', p_item.pool_id,
    'name', p_item.item_name,
    'category', p_item.category,
    'biomes', to_jsonb(p_item.biomes),
    'minDifficulty', p_item.min_difficulty,
    'maxDifficulty', p_item.max_difficulty,
    'type', p_item.item_type,
    'rarity', p_item.rarity,
    'minQuantity', p_item.min_quantity,
    'maxQuantity', p_item.max_quantity,
    'weight', p_item.weight,
    'baseWeight', p_item.base_weight,
    'notes', p_item.notes
  )
$$;

create or replace function public.get_exploration_state(p_session_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_settings jsonb;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;
  if v_profile.role <> 'dm'::public.user_role then raise exception 'Only the Dungeon Master can use exploration tools.'; end if;

  select settings into v_settings
  from public.loot_generator_configs
  where id = 'default';

  return jsonb_build_object(
    'characters', (
      select coalesce(jsonb_agg(public.character_record_to_json(c) order by c.name), '[]'::jsonb)
      from public.characters c
      where c.kind = 'player'
    ),
    'pools', (
      select coalesce(jsonb_agg(public.loot_pool_record_to_json(p) order by p.display_order, p.name), '[]'::jsonb)
      from public.loot_pools p
    ),
    'items', (
      select coalesce(jsonb_agg(public.loot_item_record_to_json(i) order by i.item_name), '[]'::jsonb)
      from public.loot_items i
      where i.is_active
    ),
    'settings', coalesce(v_settings, '{}'::jsonb)
  );
end;
$$;

create or replace function public.import_loot_items(
  p_session_token text,
  p_rows jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_payload jsonb := coalesce(p_rows, '[]'::jsonb);
  v_rows jsonb;
  v_settings jsonb;
  v_source jsonb;
  v_replace boolean := false;
  v_row jsonb;
  v_pool_key text;
  v_pool_name text;
  v_pool public.loot_pools%rowtype;
  v_name text;
  v_type_text text;
  v_rarity_text text;
  v_biomes text[];
  v_min_quantity int;
  v_max_quantity int;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;
  if v_profile.role <> 'dm'::public.user_role then raise exception 'Only the Dungeon Master can import loot.'; end if;

  if jsonb_typeof(v_payload) = 'object' then
    v_rows := coalesce(v_payload->'rows', '[]'::jsonb);
    v_settings := v_payload->'settings';
    v_source := coalesce(v_payload->'source', '{}'::jsonb);
    v_replace := coalesce((v_payload->>'replace')::boolean, false);
  else
    v_rows := v_payload;
    v_settings := null;
    v_source := '{}'::jsonb;
  end if;

  if v_settings is not null then
    insert into public.loot_generator_configs (id, settings, source, imported_at)
    values ('default', v_settings, v_source, now())
    on conflict (id) do update
    set settings = excluded.settings,
        source = excluded.source,
        imported_at = excluded.imported_at;
  end if;

  if v_replace then
    delete from public.loot_items;
  end if;

  for v_row in select * from jsonb_array_elements(coalesce(v_rows, '[]'::jsonb)) loop
    v_pool_key := lower(regexp_replace(coalesce(v_row->>'poolKey', v_row->>'pool_key', v_row->>'pool', 'workbook-loot'), '[^a-z0-9]+', '-', 'g'));
    v_pool_name := coalesce(nullif(trim(v_row->>'pool'), ''), initcap(replace(v_pool_key, '-', ' ')));
    v_name := nullif(trim(coalesce(v_row->>'name', v_row->>'item', v_row->>'item_name', '')), '');
    if v_name is null then
      continue;
    end if;

    v_type_text := lower(coalesce(nullif(v_row->>'type', ''), nullif(v_row->>'item_type', ''), 'misc'));
    if v_type_text not in ('weapon', 'armor', 'shield', 'pet', 'accessory', 'storage', 'ore', 'potion', 'food', 'plant', 'fabric', 'tool', 'quest', 'misc') then
      v_type_text := 'misc';
    end if;

    v_rarity_text := coalesce(nullif(v_row->>'rarity', ''), 'Common');
    if v_rarity_text not in ('Common', 'Uncommon', 'Rare', 'Epic', 'Legendary', 'Mythical') then
      v_rarity_text := 'Common';
    end if;

    if jsonb_typeof(v_row->'biomes') = 'array' then
      select coalesce(array_agg(nullif(trim(value), '')), array['Any']::text[]) into v_biomes
      from jsonb_array_elements_text(v_row->'biomes') as value;
    else
      select coalesce(array_agg(nullif(trim(value), '')), array['Any']::text[]) into v_biomes
      from regexp_split_to_table(coalesce(v_row->>'biomes', 'Any'), ',') as value;
    end if;
    v_biomes := array(select entry from unnest(v_biomes) as entry where entry is not null);
    if coalesce(array_length(v_biomes, 1), 0) = 0 then v_biomes := array['Any']::text[]; end if;

    v_min_quantity := greatest(1, coalesce(nullif(v_row->>'minQuantity', '')::int, nullif(v_row->>'min_quantity', '')::int, nullif(v_row->>'min', '')::int, 1));
    v_max_quantity := greatest(v_min_quantity, coalesce(nullif(v_row->>'maxQuantity', '')::int, nullif(v_row->>'max_quantity', '')::int, nullif(v_row->>'max', '')::int, v_min_quantity));

    insert into public.loot_pools (pool_key, name, description, display_order)
    values (v_pool_key, v_pool_name, 'Imported loot pool.', 100)
    on conflict (pool_key) do update set name = excluded.name
    returning * into v_pool;

    insert into public.loot_items (
      pool_id,
      item_name,
      category,
      biomes,
      min_difficulty,
      max_difficulty,
      item_type,
      rarity,
      min_quantity,
      max_quantity,
      weight,
      base_weight,
      notes,
      is_active
    )
    values (
      v_pool.id,
      v_name,
      coalesce(v_row->>'category', ''),
      v_biomes,
      greatest(1, coalesce(nullif(v_row->>'minDifficulty', '')::int, nullif(v_row->>'min_difficulty', '')::int, 1)),
      greatest(greatest(1, coalesce(nullif(v_row->>'minDifficulty', '')::int, nullif(v_row->>'min_difficulty', '')::int, 1)), coalesce(nullif(v_row->>'maxDifficulty', '')::int, nullif(v_row->>'max_difficulty', '')::int, 5)),
      v_type_text::public.item_type,
      v_rarity_text::public.item_rarity,
      v_min_quantity,
      v_max_quantity,
      greatest(1, coalesce(nullif(v_row->>'weight', '')::int, nullif(v_row->>'baseWeight', '')::int, nullif(v_row->>'base_weight', '')::int, 1)),
      greatest(1, coalesce(nullif(v_row->>'baseWeight', '')::int, nullif(v_row->>'base_weight', '')::int, nullif(v_row->>'weight', '')::int, 1)),
      coalesce(v_row->>'notes', ''),
      true
    );
  end loop;

  return public.get_exploration_state(p_session_token);
end;
$$;

create or replace function public.roll_loot_generator(
  p_session_token text,
  p_biome text default 'Any',
  p_difficulty int default 1,
  p_pool_size text default 'Medium Cave',
  p_room_type text default 'Normal'
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_settings jsonb;
  v_rolls int;
  v_base_rolls numeric;
  v_index int;
  v_total_weight numeric;
  v_pick numeric;
  v_running numeric;
  v_item record;
  v_drops jsonb := '[]'::jsonb;
  v_quantity int;
  v_rare_multiplier numeric := 1;
  v_keyword text;
  v_value numeric;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;
  if v_profile.role <> 'dm'::public.user_role then raise exception 'Only the Dungeon Master can roll loot.'; end if;

  select settings into v_settings
  from public.loot_generator_configs
  where id = 'default';

  v_base_rolls := coalesce(nullif(v_settings #>> array['baseRollsByPoolSize', p_pool_size], '')::numeric, 1);
  v_rolls := greatest(1, least(200, round(v_base_rolls)::int));
  if p_room_type = 'Secret Room' then
    v_rolls := greatest(1, ceil(v_base_rolls / 2)::int);
  elsif p_room_type = 'Tower Boss Room' then
    v_rolls := greatest(1, least(200, round(v_base_rolls * 2)::int));
  end if;

  for v_keyword, v_value in
    select key, value::text::numeric
    from jsonb_each(coalesce(v_settings->'rareMultiplierKeywords', '{}'::jsonb))
    where value::text ~ '^-?[0-9]+(\.[0-9]+)?$'
  loop
    if position(v_keyword in lower(coalesce(p_biome, ''))) > 0 then
      v_rare_multiplier := greatest(v_rare_multiplier, v_value);
    end if;
  end loop;

  select coalesce(sum(adjusted_weight), 0) into v_total_weight
  from (
    select
      greatest(1, i.base_weight)::numeric
      * case when i.rarity in ('Rare', 'Epic', 'Legendary', 'Mythical') then v_rare_multiplier else 1 end
      * case when position('tower' in lower(coalesce(p_biome, ''))) > 0 and i.rarity in ('Epic', 'Legendary', 'Mythical') then 2 else 1 end
      * case when p_room_type in ('Secret Room', 'Tower Boss Room') and i.rarity in ('Epic', 'Legendary', 'Mythical') then 2 else 1 end as adjusted_weight
    from public.loot_items i
    where i.is_active
      and greatest(1, p_difficulty) between i.min_difficulty and i.max_difficulty
      and (
        coalesce(p_biome, 'Any') = 'Any'
        or 'Any' = any(i.biomes)
        or exists (
          select 1
          from unnest(i.biomes) as biome
          where position(lower(coalesce(p_biome, '')) in lower(biome)) > 0
             or (position('tower' in lower(coalesce(p_biome, ''))) > 0 and position('tower' in lower(biome)) > 0)
             or (position('base' in lower(coalesce(p_biome, ''))) > 0 and position('base' in lower(biome)) > 0)
        )
      )
  ) eligible;

  if v_total_weight <= 0 then
    raise exception 'No matching loot for those settings.';
  end if;

  for v_index in 1..v_rolls loop
    v_pick := random() * v_total_weight;
    v_running := 0;

    for v_item in
      select
        i.*,
        greatest(1, i.base_weight)::numeric
        * case when i.rarity in ('Rare', 'Epic', 'Legendary', 'Mythical') then v_rare_multiplier else 1 end
        * case when position('tower' in lower(coalesce(p_biome, ''))) > 0 and i.rarity in ('Epic', 'Legendary', 'Mythical') then 2 else 1 end
        * case when p_room_type in ('Secret Room', 'Tower Boss Room') and i.rarity in ('Epic', 'Legendary', 'Mythical') then 2 else 1 end as adjusted_weight
      from public.loot_items i
      where i.is_active
        and greatest(1, p_difficulty) between i.min_difficulty and i.max_difficulty
        and (
          coalesce(p_biome, 'Any') = 'Any'
          or 'Any' = any(i.biomes)
          or exists (
            select 1
            from unnest(i.biomes) as biome
            where position(lower(coalesce(p_biome, '')) in lower(biome)) > 0
               or (position('tower' in lower(coalesce(p_biome, ''))) > 0 and position('tower' in lower(biome)) > 0)
               or (position('base' in lower(coalesce(p_biome, ''))) > 0 and position('base' in lower(biome)) > 0)
          )
        )
      order by i.item_name
    loop
      v_running := v_running + v_item.adjusted_weight;
      if v_running >= v_pick then
        v_quantity := v_item.min_quantity + floor(random() * (v_item.max_quantity - v_item.min_quantity + 1))::int;
        v_drops := v_drops || jsonb_build_array(jsonb_build_object(
          'id', gen_random_uuid(),
          'itemId', v_item.id,
          'name', v_item.item_name,
          'type', v_item.item_type,
          'rarity', v_item.rarity,
          'quantity', v_quantity
        ));
        exit;
      end if;
    end loop;
  end loop;

  return jsonb_build_object('drops', v_drops, 'rolls', v_rolls);
end;
$$;

grant execute on function public.roll_loot_generator(text, text, int, text, text) to anon, authenticated;
