-- Exploration and loot generator foundation.

create table if not exists public.loot_pools (
  id uuid primary key default gen_random_uuid(),
  pool_key text not null unique,
  name text not null,
  description text not null default '',
  display_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.loot_items (
  id uuid primary key default gen_random_uuid(),
  pool_id uuid not null references public.loot_pools(id) on delete cascade,
  item_name text not null,
  item_type public.item_type not null default 'misc',
  rarity public.item_rarity not null default 'Common',
  min_quantity int not null default 1 check (min_quantity >= 1),
  max_quantity int not null default 1 check (max_quantity >= min_quantity),
  weight int not null default 1 check (weight >= 1),
  notes text not null default '',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists loot_items_pool_idx on public.loot_items(pool_id);

alter table public.loot_pools enable row level security;
alter table public.loot_items enable row level security;

revoke all on public.loot_pools from anon, authenticated;
revoke all on public.loot_items from anon, authenticated;

drop trigger if exists loot_pools_touch_updated_at on public.loot_pools;
create trigger loot_pools_touch_updated_at
before update on public.loot_pools
for each row execute function public.touch_updated_at();

drop trigger if exists loot_items_touch_updated_at on public.loot_items;
create trigger loot_items_touch_updated_at
before update on public.loot_items
for each row execute function public.touch_updated_at();

insert into public.loot_pools (pool_key, name, description, display_order)
values
  ('forage', 'Forage', 'Plants, ingredients, food, and small natural finds.', 10),
  ('creature', 'Creature Drops', 'Common creature materials and trophies.', 20),
  ('cache', 'Hidden Cache', 'Coin, tools, and occasional equipment.', 30)
on conflict (pool_key) do update
set name = excluded.name,
    description = excluded.description,
    display_order = excluded.display_order;

insert into public.loot_items (pool_id, item_name, item_type, rarity, min_quantity, max_quantity, weight, notes)
select p.id, seed.item_name, seed.item_type::public.item_type, seed.rarity::public.item_rarity, seed.min_quantity, seed.max_quantity, seed.weight, seed.notes
from public.loot_pools p
join (
  values
    ('forage', 'Wild Herb', 'plant', 'Common', 1, 4, 12, 'Basic potion ingredient.'),
    ('forage', 'Bitter Root', 'plant', 'Common', 1, 3, 10, 'Useful in rough brews.'),
    ('forage', 'Arcane Nectar', 'plant', 'Uncommon', 1, 2, 4, 'Magical brewing catalyst.'),
    ('creature', 'Hide Scrap', 'fabric', 'Common', 1, 5, 12, 'Creature material.'),
    ('creature', 'Small Fang', 'misc', 'Common', 1, 3, 8, 'Trophy or crafting component.'),
    ('creature', 'Glowing Core', 'quest', 'Rare', 1, 1, 2, 'A strange inner organ or gem.'),
    ('cache', 'Loose Coin', 'misc', 'Common', 5, 40, 14, 'Currency found in a cache.'),
    ('cache', 'Repair Kit', 'tool', 'Common', 1, 1, 6, 'Basic tools.'),
    ('cache', 'Old Dagger', 'weapon', 'Uncommon', 1, 1, 3, 'Still sharp enough.')
) as seed(pool_key, item_name, item_type, rarity, min_quantity, max_quantity, weight, notes)
on p.pool_key = seed.pool_key
where not exists (
  select 1
  from public.loot_items i
  where i.pool_id = p.id
    and i.item_name = seed.item_name
);

create or replace function public.loot_pool_record_to_json(p_pool public.loot_pools)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'id', p_pool.id,
    'key', p_pool.pool_key,
    'name', p_pool.name,
    'description', p_pool.description,
    'order', p_pool.display_order
  )
$$;

create or replace function public.loot_item_record_to_json(p_item public.loot_items)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'id', p_item.id,
    'poolId', p_item.pool_id,
    'name', p_item.item_name,
    'type', p_item.item_type,
    'rarity', p_item.rarity,
    'minQuantity', p_item.min_quantity,
    'maxQuantity', p_item.max_quantity,
    'weight', p_item.weight,
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
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;
  if v_profile.role <> 'dm'::public.user_role then raise exception 'Only the Dungeon Master can use exploration tools.'; end if;

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
    )
  );
end;
$$;

create or replace function public.roll_loot_pool(
  p_session_token text,
  p_pool_id uuid,
  p_rolls int default 1
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_rolls int := greatest(1, least(200, coalesce(p_rolls, 1)));
  v_index int;
  v_total_weight int;
  v_pick int;
  v_running int;
  v_item public.loot_items%rowtype;
  v_drops jsonb := '[]'::jsonb;
  v_quantity int;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;
  if v_profile.role <> 'dm'::public.user_role then raise exception 'Only the Dungeon Master can roll loot.'; end if;

  select coalesce(sum(weight), 0) into v_total_weight
  from public.loot_items
  where pool_id = p_pool_id
    and is_active;

  if v_total_weight <= 0 then
    raise exception 'That loot pool has no active items.';
  end if;

  for v_index in 1..v_rolls loop
    v_pick := floor(random() * v_total_weight)::int + 1;
    v_running := 0;

    for v_item in
      select *
      from public.loot_items
      where pool_id = p_pool_id
        and is_active
      order by item_name
    loop
      v_running := v_running + v_item.weight;
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

  return jsonb_build_object('drops', v_drops);
end;
$$;

create or replace function public.award_loot_item(
  p_session_token text,
  p_character_id uuid,
  p_loot_item_id uuid,
  p_quantity int default 1
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_character public.characters%rowtype;
  v_loot public.loot_items%rowtype;
  v_slot int;
  v_target public.inventory_items%rowtype;
  v_item public.inventory_items%rowtype;
  v_quantity int := greatest(1, coalesce(p_quantity, 1));
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;
  v_character := public.assert_inventory_access(v_profile, p_character_id, true);

  select * into v_loot from public.loot_items where id = p_loot_item_id and is_active;
  if v_loot.id is null then raise exception 'Loot item not found.'; end if;

  select * into v_target
  from public.inventory_items i
  where i.character_id = v_character.id
    and i.parent_item_id is null
    and i.loadout_slot is null
    and i.item_name = v_loot.item_name
    and i.item_type = v_loot.item_type
    and i.rarity = v_loot.rarity
    and i.is_storage = false
    and coalesce(i.spell_imbue, '') = ''
  order by i.slot_index
  limit 1;

  if v_target.id is not null then
    update public.inventory_items
    set quantity = quantity + v_quantity
    where id = v_target.id
    returning * into v_item;
  else
    v_slot := public.find_first_free_inventory_slot(v_character.id, null, v_character.inventory_slots);
    if v_slot is null then raise exception 'Inventory full.'; end if;

    insert into public.inventory_items (character_id, parent_item_id, slot_index, item_name, item_type, rarity, quantity, is_storage, storage_capacity, modifiers, spell_imbue)
    values (v_character.id, null, v_slot, v_loot.item_name, v_loot.item_type, v_loot.rarity, v_quantity, v_loot.item_type = 'storage'::public.item_type, case when v_loot.item_type = 'storage'::public.item_type then 1 else 0 end, '{}'::jsonb, null)
    returning * into v_item;
  end if;

  return jsonb_build_object('item', public.inventory_item_record_to_json(v_item));
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
  v_row jsonb;
  v_pool_key text;
  v_pool public.loot_pools%rowtype;
  v_name text;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;
  if v_profile.role <> 'dm'::public.user_role then raise exception 'Only the Dungeon Master can import loot.'; end if;

  for v_row in select * from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) loop
    v_pool_key := lower(regexp_replace(coalesce(v_row->>'pool', v_row->>'pool_key', 'custom'), '[^a-z0-9]+', '-', 'g'));
    v_name := nullif(trim(coalesce(v_row->>'name', v_row->>'item', v_row->>'item_name', '')), '');
    if v_name is null then
      continue;
    end if;

    insert into public.loot_pools (pool_key, name, description, display_order)
    values (v_pool_key, initcap(replace(v_pool_key, '-', ' ')), 'Imported loot pool.', 100)
    on conflict (pool_key) do update set name = excluded.name
    returning * into v_pool;

    insert into public.loot_items (pool_id, item_name, item_type, rarity, min_quantity, max_quantity, weight, notes, is_active)
    values (
      v_pool.id,
      v_name,
      coalesce(nullif(lower(v_row->>'type'), ''), 'misc')::public.item_type,
      coalesce(nullif(v_row->>'rarity', ''), 'Common')::public.item_rarity,
      greatest(1, coalesce(nullif(v_row->>'min', '')::int, nullif(v_row->>'min_quantity', '')::int, 1)),
      greatest(greatest(1, coalesce(nullif(v_row->>'min', '')::int, nullif(v_row->>'min_quantity', '')::int, 1)), coalesce(nullif(v_row->>'max', '')::int, nullif(v_row->>'max_quantity', '')::int, 1)),
      greatest(1, coalesce(nullif(v_row->>'weight', '')::int, 1)),
      coalesce(v_row->>'notes', ''),
      true
    );
  end loop;

  return public.get_exploration_state(p_session_token);
end;
$$;

grant execute on function public.loot_pool_record_to_json(public.loot_pools) to anon, authenticated;
grant execute on function public.loot_item_record_to_json(public.loot_items) to anon, authenticated;
grant execute on function public.get_exploration_state(text) to anon, authenticated;
grant execute on function public.roll_loot_pool(text, uuid, int) to anon, authenticated;
grant execute on function public.award_loot_item(text, uuid, uuid, int) to anon, authenticated;
grant execute on function public.import_loot_items(text, jsonb) to anon, authenticated;
