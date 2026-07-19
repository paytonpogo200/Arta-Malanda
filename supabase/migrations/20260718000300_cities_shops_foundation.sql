-- Cities and shops foundation.

create table if not exists public.cities (
  id uuid primary key default gen_random_uuid(),
  city_key text not null unique,
  name text not null,
  is_locked boolean not null default false,
  display_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.shop_vendors (
  id uuid primary key default gen_random_uuid(),
  city_key text not null references public.cities(city_key) on delete cascade,
  vendor_key text not null unique,
  name text not null,
  facility text not null default 'Market',
  category text not null default 'General',
  is_hidden boolean not null default false,
  display_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.market_products (
  id uuid primary key default gen_random_uuid(),
  vendor_id uuid not null references public.shop_vendors(id) on delete cascade,
  product_key text not null unique,
  item_name text not null,
  description text not null default '',
  item_type public.item_type not null default 'misc',
  rarity public.item_rarity not null default 'Common',
  price_coin int not null default 0 check (price_coin >= 0),
  stock_quantity int check (stock_quantity is null or stock_quantity >= 0),
  is_available boolean not null default true,
  display_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists shop_vendors_city_idx on public.shop_vendors(city_key);
create index if not exists market_products_vendor_idx on public.market_products(vendor_id);

alter table public.cities enable row level security;
alter table public.shop_vendors enable row level security;
alter table public.market_products enable row level security;

revoke all on public.cities from anon, authenticated;
revoke all on public.shop_vendors from anon, authenticated;
revoke all on public.market_products from anon, authenticated;

drop trigger if exists cities_touch_updated_at on public.cities;
create trigger cities_touch_updated_at
before update on public.cities
for each row execute function public.touch_updated_at();

drop trigger if exists shop_vendors_touch_updated_at on public.shop_vendors;
create trigger shop_vendors_touch_updated_at
before update on public.shop_vendors
for each row execute function public.touch_updated_at();

drop trigger if exists market_products_touch_updated_at on public.market_products;
create trigger market_products_touch_updated_at
before update on public.market_products
for each row execute function public.touch_updated_at();

insert into public.cities (city_key, name, is_locked, display_order)
values ('calostrynn', 'Calostrynn', false, 10)
on conflict (city_key) do update
set name = excluded.name,
    display_order = excluded.display_order;

insert into public.shop_vendors (city_key, vendor_key, name, facility, category, display_order)
values
  ('calostrynn', 'calostrynn-market-stall', 'Market Stall', 'Market', 'General Goods', 10),
  ('calostrynn', 'calostrynn-armory', 'Armory Quartermaster', 'Armory', 'Arms & Armor', 20),
  ('calostrynn', 'calostrynn-brewery', 'Brewery Keeper', 'Brewery', 'Potions & Ingredients', 30),
  ('calostrynn', 'calostrynn-library', 'Library Scribe', 'Library', 'Spells & Scrolls', 40),
  ('calostrynn', 'calostrynn-blacksmith', 'Blacksmith', 'Blacksmith', 'Tools & Metalwork', 50)
on conflict (vendor_key) do update
set name = excluded.name,
    facility = excluded.facility,
    category = excluded.category,
    display_order = excluded.display_order;

insert into public.market_products (
  vendor_id,
  product_key,
  item_name,
  description,
  item_type,
  rarity,
  price_coin,
  stock_quantity,
  display_order
)
select v.id, product_key, item_name, description, item_type::public.item_type, rarity::public.item_rarity, price_coin, stock_quantity, display_order
from public.shop_vendors v
join (
  values
    ('calostrynn-market-stall', 'travel-rations', 'Travel Rations', 'Simple preserved food for the road.', 'food', 'Common', 8, 50, 10),
    ('calostrynn-market-stall', 'rope-bundle', 'Rope Bundle', 'Useful cordage for climbs, hauling, and quick fixes.', 'tool', 'Common', 12, 18, 20),
    ('calostrynn-market-stall', 'waist-pouch', 'Waist Pouch', 'A small one-slot storage container.', 'storage', 'Common', 80, 8, 30),
    ('calostrynn-armory', 'iron-sword', 'Iron Sword', 'A dependable blade from the city armory.', 'weapon', 'Common', 120, 8, 10),
    ('calostrynn-armory', 'round-shield', 'Round Shield', 'A sturdy shield suited for patrol or travel.', 'shield', 'Common', 90, 7, 20),
    ('calostrynn-armory', 'light-armor', 'Light Armor', 'Flexible protection that keeps a fighter moving.', 'armor', 'Common', 180, 5, 30),
    ('calostrynn-brewery', 'minor-healing-potion', 'Minor Healing Potion', 'Restores 20 health when consumed.', 'potion', 'Common', 50, 12, 10),
    ('calostrynn-brewery', 'minor-mana-potion', 'Minor Mana Potion', 'Restores 15 mana when consumed.', 'potion', 'Common', 60, 12, 20),
    ('calostrynn-brewery', 'glass-flask', 'Glass Flask', 'An empty flask for brews and careful storage.', 'tool', 'Common', 6, 40, 30),
    ('calostrynn-library', 'blank-scroll', 'Blank Scroll', 'Prepared parchment for notes, maps, or magic work.', 'quest', 'Common', 15, 30, 10),
    ('calostrynn-library', 'spark-cantrip', 'Spark Cantrip', 'A beginner spell page for controlled flame.', 'quest', 'Uncommon', 150, 3, 20),
    ('calostrynn-blacksmith', 'repair-kit', 'Repair Kit', 'Basic tools for maintaining gear at camp.', 'tool', 'Common', 75, 9, 10),
    ('calostrynn-blacksmith', 'iron-ore', 'Iron Ore', 'Raw ore ready for forge work.', 'ore', 'Common', 22, 35, 20)
) as seed(vendor_key, product_key, item_name, description, item_type, rarity, price_coin, stock_quantity, display_order)
on v.vendor_key = seed.vendor_key
on conflict (product_key) do update
set item_name = excluded.item_name,
    description = excluded.description,
    item_type = excluded.item_type,
    rarity = excluded.rarity,
    price_coin = excluded.price_coin,
    display_order = excluded.display_order;

create or replace function public.city_record_to_json(p_city public.cities)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'id', p_city.id,
    'key', p_city.city_key,
    'name', p_city.name,
    'locked', p_city.is_locked,
    'order', p_city.display_order
  )
$$;

create or replace function public.market_product_record_to_json(p_product public.market_products)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'id', p_product.id,
    'vendorId', p_product.vendor_id,
    'key', p_product.product_key,
    'name', p_product.item_name,
    'description', p_product.description,
    'type', p_product.item_type,
    'rarity', p_product.rarity,
    'priceCoin', p_product.price_coin,
    'stockQuantity', p_product.stock_quantity,
    'available', p_product.is_available
  )
$$;

create or replace function public.shop_vendor_record_to_json(p_vendor public.shop_vendors, p_is_dm boolean default false)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'id', p_vendor.id,
    'cityKey', p_vendor.city_key,
    'key', p_vendor.vendor_key,
    'name', p_vendor.name,
    'facility', p_vendor.facility,
    'category', p_vendor.category,
    'hidden', p_vendor.is_hidden,
    'order', p_vendor.display_order,
    'products', (
      select coalesce(jsonb_agg(public.market_product_record_to_json(p) order by p.display_order, p.item_name), '[]'::jsonb)
      from public.market_products p
      where p.vendor_id = p_vendor.id
        and (p_is_dm or p.is_available)
    )
  )
$$;

create or replace function public.currency_coin_value(p_unit_key text)
returns int
language sql
immutable
as $$
  select case p_unit_key
    when 'coin' then 1
    when 'callis' then 10
    when 'callor' then 100
    when 'cal' then 10000
    else 0
  end
$$;

create or replace function public.wallet_total_coin(p_character_id uuid)
returns int
language sql
stable
set search_path = public
as $$
  select coalesce(sum(b.amount * public.currency_coin_value(u.unit_key)), 0)::int
  from public.character_wallet_balances b
  join public.currency_units u on u.id = b.currency_unit_id
  where b.character_id = p_character_id
$$;

create or replace function public.set_wallet_from_coin_value(p_character_id uuid, p_coin_value int)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_remaining int := greatest(0, coalesce(p_coin_value, 0));
  v_cal int;
  v_callor int;
  v_callis int;
  v_coin int;
begin
  v_cal := floor(v_remaining / 10000);
  v_remaining := v_remaining - v_cal * 10000;
  v_callor := floor(v_remaining / 100);
  v_remaining := v_remaining - v_callor * 100;
  v_callis := floor(v_remaining / 10);
  v_remaining := v_remaining - v_callis * 10;
  v_coin := v_remaining;

  insert into public.character_wallet_balances (character_id, currency_unit_id, amount)
  select p_character_id, u.id,
    case u.unit_key
      when 'cal' then v_cal
      when 'callor' then v_callor
      when 'callis' then v_callis
      when 'coin' then v_coin
      else 0
    end
  from public.currency_units u
  where u.unit_key in ('coin', 'callis', 'callor', 'cal')
  on conflict (character_id, currency_unit_id) do update
  set amount = excluded.amount;
end;
$$;

create or replace function public.get_discovered_cities(p_session_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then
    raise exception 'Invalid or expired session.';
  end if;

  return jsonb_build_object(
    'characters', (
      select coalesce(jsonb_agg(public.character_record_to_json(c) order by c.name), '[]'::jsonb)
      from public.characters c
      where c.kind = 'player'
        and (v_profile.role = 'dm'::public.user_role or c.owner_user_id = v_profile.id)
    ),
    'cities', (
      select coalesce(jsonb_agg(public.city_record_to_json(c) order by c.display_order, c.name), '[]'::jsonb)
      from public.cities c
    ),
    'vendors', (
      select coalesce(jsonb_agg(public.shop_vendor_record_to_json(v, v_profile.role = 'dm'::public.user_role) order by v.display_order, v.name), '[]'::jsonb)
      from public.shop_vendors v
      where v_profile.role = 'dm'::public.user_role or not v.is_hidden
    )
  );
end;
$$;

create or replace function public.purchase_market_product(
  p_session_token text,
  p_character_id uuid,
  p_product_id uuid,
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
  v_city public.cities%rowtype;
  v_product public.market_products%rowtype;
  v_vendor public.shop_vendors%rowtype;
  v_quantity int := greatest(1, coalesce(p_quantity, 1));
  v_cost int;
  v_wallet int;
  v_slot int;
  v_target public.inventory_items%rowtype;
  v_item public.inventory_items%rowtype;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then
    raise exception 'Invalid or expired session.';
  end if;

  v_character := public.assert_inventory_access(v_profile, p_character_id, false);

  select * into v_product from public.market_products where id = p_product_id;
  if v_product.id is null or not v_product.is_available then
    raise exception 'That item is not available.';
  end if;

  select * into v_vendor from public.shop_vendors where id = v_product.vendor_id;
  select * into v_city from public.cities where city_key = v_vendor.city_key;
  if v_city.id is null then
    raise exception 'City not found.';
  end if;

  if v_city.is_locked then
    raise exception 'That city is currently locked.';
  end if;

  if v_character.location_name <> v_city.name then
    raise exception 'That character is not in %.', v_city.name;
  end if;

  if v_product.stock_quantity is not null and v_quantity > v_product.stock_quantity then
    raise exception 'Not enough stock.';
  end if;

  v_cost := v_product.price_coin * v_quantity;
  v_wallet := public.wallet_total_coin(v_character.id);
  if v_wallet < v_cost then
    raise exception 'Not enough currency.';
  end if;

  select * into v_target
  from public.inventory_items i
  where i.character_id = v_character.id
    and i.parent_item_id is null
    and i.loadout_slot is null
    and i.item_name = v_product.item_name
    and i.item_type = v_product.item_type
    and i.rarity = v_product.rarity
    and coalesce(i.spell_imbue, '') = ''
    and i.is_storage = false
  order by i.slot_index
  limit 1;

  if v_target.id is not null then
    update public.inventory_items
    set quantity = quantity + v_quantity
    where id = v_target.id
    returning * into v_item;
  else
    v_slot := public.find_first_free_inventory_slot(v_character.id, null, v_character.inventory_slots);
    if v_slot is null then
      raise exception 'Inventory full.';
    end if;

    insert into public.inventory_items (
      character_id,
      parent_item_id,
      slot_index,
      item_name,
      item_type,
      rarity,
      quantity,
      is_storage,
      storage_capacity,
      modifiers,
      spell_imbue
    )
    values (
      v_character.id,
      null,
      v_slot,
      v_product.item_name,
      v_product.item_type,
      v_product.rarity,
      v_quantity,
      v_product.item_type = 'storage'::public.item_type,
      case when v_product.item_type = 'storage'::public.item_type then 1 else 0 end,
      '{}'::jsonb,
      null
    )
    returning * into v_item;
  end if;

  perform public.set_wallet_from_coin_value(v_character.id, v_wallet - v_cost);

  if v_product.stock_quantity is not null then
    update public.market_products
    set stock_quantity = greatest(0, stock_quantity - v_quantity)
    where id = v_product.id;
  end if;

  return public.get_discovered_cities(p_session_token);
end;
$$;

create or replace function public.update_city_access(
  p_session_token text,
  p_city_key text,
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
    raise exception 'Only the Dungeon Master can change city access.';
  end if;

  update public.cities
  set is_locked = case when v_patch ? 'locked' then (v_patch->>'locked')::boolean else is_locked end
  where city_key = p_city_key;

  return public.get_discovered_cities(p_session_token);
end;
$$;

create or replace function public.update_market_product(
  p_session_token text,
  p_product_id uuid,
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
    raise exception 'Only the Dungeon Master can change shop stock.';
  end if;

  update public.market_products
  set
    item_name = case when v_patch ? 'name' then coalesce(nullif(trim(v_patch->>'name'), ''), item_name) else item_name end,
    description = case when v_patch ? 'description' then coalesce(v_patch->>'description', '') else description end,
    item_type = case when v_patch ? 'type' then (v_patch->>'type')::public.item_type else item_type end,
    rarity = case when v_patch ? 'rarity' then (v_patch->>'rarity')::public.item_rarity else rarity end,
    price_coin = case when v_patch ? 'priceCoin' then greatest(0, (v_patch->>'priceCoin')::int) else price_coin end,
    stock_quantity = case when v_patch ? 'stockQuantity' then greatest(0, (v_patch->>'stockQuantity')::int) else stock_quantity end,
    is_available = case when v_patch ? 'available' then (v_patch->>'available')::boolean else is_available end
  where id = p_product_id;

  return public.get_discovered_cities(p_session_token);
end;
$$;

grant execute on function public.city_record_to_json(public.cities) to anon, authenticated;
grant execute on function public.market_product_record_to_json(public.market_products) to anon, authenticated;
grant execute on function public.shop_vendor_record_to_json(public.shop_vendors, boolean) to anon, authenticated;
grant execute on function public.currency_coin_value(text) to anon, authenticated;
grant execute on function public.wallet_total_coin(uuid) to anon, authenticated;
grant execute on function public.set_wallet_from_coin_value(uuid, int) to anon, authenticated;
grant execute on function public.get_discovered_cities(text) to anon, authenticated;
grant execute on function public.purchase_market_product(text, uuid, uuid, int) to anon, authenticated;
grant execute on function public.update_city_access(text, text, jsonb) to anon, authenticated;
grant execute on function public.update_market_product(text, uuid, jsonb) to anon, authenticated;
