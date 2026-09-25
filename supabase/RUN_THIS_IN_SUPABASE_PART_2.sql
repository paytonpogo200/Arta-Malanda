-- Arta Malanda Supabase runner - PART 2 OF 2
-- Run only after PART 1 succeeds. This applies shops and later game systems.

-- ============================================================
-- ============================================================

-- Shop vendor controls for Discovered Cities.



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
  v_vendor public.shop_vendors%rowtype;
  v_patch jsonb := coalesce(p_patch, '{}'::jsonb);
  v_can_manage boolean := false;
  v_can_rename_stable boolean := false;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then
    raise exception 'Invalid or expired session.';
  end if;

  select * into v_vendor
  from public.shop_vendors
  where id = p_vendor_id;

  if v_vendor.id is null then
    raise exception 'Shop not found.';
  end if;

  v_can_manage := public.profile_can_manage_shop_vendor(v_profile, v_vendor);
  v_can_rename_stable := public.profile_runs_shop_vendor(v_profile, v_vendor) and v_vendor.blueprint_type = 'stable';

  if not v_can_manage and not v_can_rename_stable then
    raise exception 'You do not have permission to change this shop.';
  end if;

  if v_can_rename_stable and not v_can_manage then
    v_patch := jsonb_strip_nulls(jsonb_build_object(
      'name', v_patch->'name',
      'boardingFeeCoin', v_patch->'boardingFeeCoin'
    ));
  end if;

  update public.shop_vendors
  set
    name = case when v_patch ? 'name' then coalesce(nullif(trim(v_patch->>'name'), ''), name) else name end,
    npc_name = case when v_patch ? 'npcName' then coalesce(nullif(trim(v_patch->>'npcName'), ''), npc_name) else npc_name end,
    facility = case when v_patch ? 'facility' then coalesce(nullif(trim(v_patch->>'facility'), ''), facility) else facility end,
    category = case when v_patch ? 'category' then coalesce(nullif(trim(v_patch->>'category'), ''), category) else category end,
    blueprint_type = case
      when v_patch ? 'blueprintType' and v_patch->>'blueprintType' in ('market', 'blacksmith', 'armory', 'brewery', 'spell_registrar', 'library', 'stable') then v_patch->>'blueprintType'
      else blueprint_type
    end,
    payout_character_id = case
      when v_patch ? 'payoutCharacterId' then nullif(v_patch->>'payoutCharacterId', '')::uuid
      else payout_character_id
    end,
    boarding_fee_coin = case
      when v_patch ? 'boardingFeeCoin' then greatest(0, (v_patch->>'boardingFeeCoin')::int)
      else boarding_fee_coin
    end,
    display_order = case when v_patch ? 'order' then greatest(0, (v_patch->>'order')::int) else display_order end,
    is_hidden = case when v_patch ? 'hidden' then (v_patch->>'hidden')::boolean else is_hidden end
  where id = p_vendor_id;

  return public.get_discovered_cities(p_session_token);
end;
$$;



-- ============================================================
-- ============================================================

-- Spell catalog, character spell slots, and mana use foundation.

create table if not exists public.spell_catalog (
  id uuid primary key default gen_random_uuid(),
  spell_key text not null unique,
  name text not null,
  school text not null default 'arcane' check (school in ('arcane', 'restoration', 'nature', 'alchemy', 'rune', 'shadow', 'martial')),
  mana_cost int not null default 0 check (mana_cost >= 0),
  summary text not null default '',
  details text not null default '',
  rarity public.item_rarity not null default 'Common',
  is_available boolean not null default true,
  display_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.character_spells (
  id uuid primary key default gen_random_uuid(),
  character_id uuid not null references public.characters(id) on delete cascade,
  spell_id uuid not null references public.spell_catalog(id) on delete cascade,
  is_active boolean not null default false,
  slot_index int check (slot_index is null or slot_index >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists character_spells_active_slot_unique
  on public.character_spells (character_id, slot_index)
  where is_active and slot_index is not null;

create index if not exists character_spells_character_idx on public.character_spells(character_id);
create index if not exists character_spells_spell_idx on public.character_spells(spell_id);

alter table public.spell_catalog enable row level security;
alter table public.character_spells enable row level security;

revoke all on public.spell_catalog from anon, authenticated;
revoke all on public.character_spells from anon, authenticated;

drop trigger if exists spell_catalog_touch_updated_at on public.spell_catalog;
create trigger spell_catalog_touch_updated_at
before update on public.spell_catalog
for each row execute function public.touch_updated_at();

drop trigger if exists character_spells_touch_updated_at on public.character_spells;
create trigger character_spells_touch_updated_at
before update on public.character_spells
for each row execute function public.touch_updated_at();

alter table public.spell_catalog
  add column if not exists spell_type text not null default 'Utility',
  add column if not exists mana_label text not null default '',
  add column if not exists price_coin int not null default 0 check (price_coin >= 0);

alter table public.spell_catalog
  drop constraint if exists spell_catalog_spell_type_valid,
  add constraint spell_catalog_spell_type_valid check (spell_type in ('Ember', 'Frost', 'Lightning', 'Earth', 'Wind', 'Energy', 'Defensive Support', 'Offensive Support', 'Enhancement', 'Utility'));

alter table public.character_spells
  drop constraint if exists character_spells_character_id_spell_id_key,
  add column if not exists custom_name text,
  add column if not exists custom_summary text,
  add column if not exists custom_details text,
  add column if not exists custom_mana_cost int check (custom_mana_cost is null or custom_mana_cost >= 0);

drop table if exists public.app_checkpoints;

do $$
begin
  if exists (select 1 from public.spell_catalog where spell_key = 'defibulate')
    and not exists (select 1 from public.spell_catalog where spell_key = 'defibrillate')
  then
    update public.spell_catalog
    set spell_key = 'defibrillate',
        name = 'Defibrillate'
    where spell_key = 'defibulate';
  elsif exists (select 1 from public.spell_catalog where spell_key = 'defibulate') then
    delete from public.spell_catalog where spell_key = 'defibulate';
  end if;

end;
$$;

insert into public.spell_catalog (spell_key, name, school, spell_type, mana_cost, mana_label, summary, details, rarity, is_available, display_order, price_coin)
values
  ('emberbolt', 'Emberbolt', 'arcane', 'Ember', 8, '8 mana', '', '', 'Common', true, 1000, 600),
  ('scorch', 'Scorch', 'arcane', 'Ember', 12, '12 mana', '', '', 'Common', true, 1001, 800),
  ('flame-ring', 'Flame Ring', 'arcane', 'Ember', 18, '18 mana', '', '', 'Common', true, 1002, 2500),
  ('solar-flare', 'Solar Flare', 'arcane', 'Ember', 18, '18 mana', '', '', 'Common', true, 1003, 3000),
  ('radiance', 'Radiance', 'arcane', 'Ember', 45, '45 mana', '', '', 'Common', true, 1004, 10000),
  ('fireball', 'Fireball', 'arcane', 'Ember', 30, '30 mana', '', '', 'Common', true, 1005, 6500),
  ('sear', 'Sear', 'arcane', 'Ember', 35, '35 mana', '', '', 'Common', true, 1006, 9000),
  ('frostbite', 'Frostbite', 'arcane', 'Frost', 10, '10 mana', '', '', 'Common', true, 2007, 1000),
  ('ice-shard', 'Ice Shard', 'arcane', 'Frost', 11, '11 mana', '', '', 'Common', true, 2008, 1100),
  ('hypothermia', 'Hypothermia', 'arcane', 'Frost', 18, '18 mana', '', '', 'Common', true, 2009, 2400),
  ('ice-wall', 'Ice Wall', 'arcane', 'Frost', 25, '25 mana', '', '', 'Common', true, 2010, 4500),
  ('ice-cube', 'Ice Cube', 'arcane', 'Frost', 22, '22 mana', '', '', 'Common', true, 2011, 4800),
  ('christmas-tree', 'Christmas Tree', 'arcane', 'Frost', 25, '25 mana', '', '', 'Common', true, 2012, 7500),
  ('absolute-zero', 'Absolute Zero', 'arcane', 'Frost', 45, '45 mana', '', '', 'Common', true, 2013, 10000),
  ('sparkshot', 'Sparkshot', 'arcane', 'Lightning', 9, '9 mana', '', '', 'Common', true, 3014, 600),
  ('static-charge', 'Static Charge', 'arcane', 'Lightning', 20, '20 mana', '', '', 'Common', true, 3015, 2800),
  ('arc-shot', 'Arc Shot', 'arcane', 'Lightning', 32, '32 mana', '', '', 'Common', true, 3016, 6000),
  ('defibrillate', 'Defibrillate', 'arcane', 'Lightning', 10, '10 mana', '', '', 'Common', true, 3017, 5000),
  ('electric-explosion', 'Electric Explosion', 'arcane', 'Lightning', 20, '20 mana', '', '', 'Common', true, 3018, 1800),
  ('thunder-crash', 'Thunder Crash', 'arcane', 'Lightning', 38, '38 mana', '', '', 'Common', true, 3019, 8500),
  ('lightning-chain', 'Lightning Chain', 'arcane', 'Lightning', 38, '38 mana', '', '', 'Common', true, 3020, 10000),
  ('stone-fist', 'Stone Fist', 'nature', 'Earth', 12, '12 mana', '', '', 'Common', true, 4021, 900),
  ('quicksand', 'Quicksand', 'nature', 'Earth', 15, '15 mana', '', '', 'Common', true, 4022, 3000),
  ('earthen-spikes', 'Earthen Spikes', 'nature', 'Earth', 26, '26 mana', '', '', 'Common', true, 4023, 4000),
  ('earthquake', 'Earthquake', 'nature', 'Earth', 30, '30 mana', '', '', 'Common', true, 4024, 5000),
  ('wind-cutter', 'Wind Cutter', 'nature', 'Wind', 10, '10 mana', '', '', 'Common', true, 5025, 800),
  ('mighty-gust', 'Mighty Gust', 'nature', 'Wind', 15, '15 mana', '', '', 'Common', true, 5026, 2000),
  ('wind-be-with-me', 'Wind Be With Me', 'nature', 'Wind', 25, '25 mana', '', '', 'Common', true, 5027, 2500),
  ('gale-burst', 'Gale Burst', 'nature', 'Wind', 24, '24 mana', '', '', 'Common', true, 5028, 3500),
  ('pulse', 'Pulse', 'arcane', 'Energy', 15, '15 mana', '', '', 'Common', true, 6029, 1600),
  ('energy-shield', 'Energy Shield', 'arcane', 'Energy', 15, '15 mana', '', '', 'Common', true, 6030, 2400),
  ('mend-wounds', 'Mend Wounds', 'restoration', 'Defensive Support', 12, '12 mana', '', '', 'Common', true, 7031, 2000),
  ('greater-mend', 'Greater Mend', 'restoration', 'Defensive Support', 28, '28 mana', '', '', 'Common', true, 7032, 5500),
  ('antivenom', 'Antivenom', 'restoration', 'Defensive Support', 10, '10 mana', '', '', 'Common', true, 7033, 1200),
  ('fortify', 'Fortify', 'restoration', 'Defensive Support', 16, '16 mana', '', '', 'Common', true, 7034, 3000),
  ('iron-skin', 'Iron Skin', 'restoration', 'Defensive Support', 25, '25 mana', '', '', 'Common', true, 7035, 6000),
  ('shield', 'Shield', 'restoration', 'Defensive Support', 10, '10 mana', '', '', 'Common', true, 7036, 8000),
  ('cleanse', 'Cleanse', 'restoration', 'Defensive Support', 50, '50 mana', '', '', 'Common', true, 7037, 12000),
  ('revitalize', 'Revitalize', 'restoration', 'Defensive Support', 10, '10 mana', '', '', 'Common', true, 7038, 2500),
  ('golden-boy', 'Golden Boy', 'restoration', 'Defensive Support', 40, '40 mana', '', '', 'Common', true, 7039, 7500),
  ('insurance', 'Insurance', 'restoration', 'Defensive Support', 45, '45 mana', '', '', 'Common', true, 7040, 10000),
  ('counter-attack', 'Counter Attack', 'restoration', 'Defensive Support', 30, '30 mana', '', '', 'Common', true, 7041, 5000),
  ('retaliation', 'Retaliation', 'restoration', 'Defensive Support', 45, '45 mana', '', '', 'Common', true, 7042, 7500),
  ('internal-bleeding', 'Internal Bleeding', 'shadow', 'Offensive Support', 25, '25 mana', '', '', 'Common', true, 8043, 4500),
  ('strip', 'Strip', 'shadow', 'Offensive Support', 30, '30 mana', '', '', 'Common', true, 8044, 5500),
  ('demoralize', 'Demoralize', 'shadow', 'Offensive Support', 55, '55 mana', '', '', 'Common', true, 8045, 10000),
  ('weaken', 'Weaken', 'shadow', 'Offensive Support', 28, '28 mana', '', '', 'Common', true, 8046, 5000),
  ('cripple', 'Cripple', 'shadow', 'Offensive Support', 50, '50 mana', '', '', 'Common', true, 8047, 9000),
  ('enfeeblement', 'Enfeeblement', 'shadow', 'Offensive Support', 60, '60 mana', '', '', 'Common', true, 8048, 11000),
  ('dreadfall', 'Dreadfall', 'shadow', 'Offensive Support', 90, '90 mana', '', '', 'Common', true, 8049, 15000),
  ('whats-mine-is-yours', 'What''s Mine Is Yours', 'shadow', 'Offensive Support', 30, '30 mana', '', '', 'Common', true, 8050, 10000),
  ('judas', 'Judas', 'shadow', 'Offensive Support', 65, '65 mana', '', '', 'Common', true, 8051, 11000),
  ('jump-him', 'Jump Him', 'shadow', 'Offensive Support', 70, '70 mana', '', '', 'Common', true, 8052, 12500),
  ('follow-the-leader', 'Follow the Leader', 'shadow', 'Offensive Support', 45, '45 mana', '', '', 'Common', true, 8053, 8000),
  ('bloodthirsty', 'Bloodthirsty', 'shadow', 'Offensive Support', 30, '30 mana', '', '', 'Common', true, 8054, 6000),
  ('swiftness', 'Swiftness', 'rune', 'Enhancement', 14, '14 mana', '', '', 'Common', true, 9055, 2200),
  ('clarity', 'Clarity', 'rune', 'Enhancement', 10, '10 mana', '', '', 'Common', true, 9056, 1400),
  ('mana-surge', 'Mana Surge', 'rune', 'Enhancement', 18, '18 mana', '', '', 'Common', true, 9057, 4500),
  ('guided-strike', 'Guided Strike', 'rune', 'Enhancement', 10, '10 mana', '', '', 'Common', true, 9058, 1200),
  ('stabilize', 'Stabilize', 'rune', 'Enhancement', 10, '10 mana', '', '', 'Common', true, 9059, 9000),
  ('light-orb', 'Light Orb', 'arcane', 'Utility', 3, '3 mana', '', '', 'Common', true, 10060, 200),
  ('warmth', 'Warmth', 'arcane', 'Utility', 5, '5 mana', '', '', 'Common', true, 10061, 500),
  ('cooling', 'Cooling', 'arcane', 'Utility', 5, '5 mana', '', '', 'Common', true, 10062, 500),
  ('levitation', 'Levitation', 'arcane', 'Utility', 15, '15 mana', '', '', 'Common', true, 10063, 3500),
  ('seal', 'Seal', 'arcane', 'Utility', 12, '12 mana', '', '', 'Common', true, 10064, 1800),
  ('magecraft-detection', 'Magecraft Detection', 'arcane', 'Utility', 6, '6 mana', '', '', 'Common', true, 10065, 2500),
  ('purify-water', 'Purify Water', 'arcane', 'Utility', 5, '5 mana', '', '', 'Common', true, 10066, 400),
  ('silent-step', 'Silent Step', 'arcane', 'Utility', 14, '14 mana', '', '', 'Common', true, 10067, 3500),
  ('taunt', 'Taunt', 'arcane', 'Utility', 20, '20 mana', '', '', 'Common', true, 10068, 4500),
  ('entangle', 'Entangle', 'arcane', 'Utility', 35, '35 mana', '', '', 'Common', true, 10069, 10000),
  ('pure-chaos', 'Pure Chaos', 'arcane', 'Utility', 0, 'Mana decided by 3d20', 'Mana decided by 3d20. The next attack will be a random spell.', 'Mana decided by 3d20. The next attack will be a random spell.', 'Common', true, 10070, 10000),
  ('equilibrium', 'Equilibrium', 'arcane', 'Utility', 0, 'Free', 'Freely trade health and mana one-for-one, within table limits.', 'Freely trade health and mana one-for-one, within table limits.', 'Common', true, 10071, 10000),
  ('preparation', 'Preparation', 'arcane', 'Utility', 0, 'Free', '', '', 'Common', true, 10072, 10000)
on conflict (spell_key) do update
set name = excluded.name,
    school = excluded.school,
    spell_type = excluded.spell_type,
    mana_cost = excluded.mana_cost,
    mana_label = excluded.mana_label,
    summary = case when excluded.summary <> '' then excluded.summary else public.spell_catalog.summary end,
    details = case when excluded.details <> '' then excluded.details else public.spell_catalog.details end,
    rarity = public.spell_catalog.rarity,
    is_available = excluded.is_available,
    display_order = excluded.display_order,
    price_coin = excluded.price_coin;

update public.spell_catalog
set summary = replace(replace(replace(replace(replace(replace(summary, 'Sheild', 'Shield'), 'Intellegence', 'Intelligence'), 'recieve', 'receive'), 'begining', 'beginning'), 'resuraction', 'resurrection'), 'Chose', 'Choose'),
    details = replace(replace(replace(replace(replace(replace(details, 'Sheild', 'Shield'), 'Intellegence', 'Intelligence'), 'recieve', 'receive'), 'begining', 'beginning'), 'resuraction', 'resurrection'), 'Chose', 'Choose')
where spell_key in ('emberbolt', 'scorch', 'flame-ring', 'solar-flare', 'radiance', 'fireball', 'sear', 'frostbite', 'ice-shard', 'hypothermia', 'ice-wall', 'ice-cube', 'christmas-tree', 'absolute-zero', 'sparkshot', 'static-charge', 'arc-shot', 'defibrillate', 'electric-explosion', 'thunder-crash', 'lightning-chain', 'stone-fist', 'quicksand', 'earthen-spikes', 'earthquake', 'wind-cutter', 'mighty-gust', 'wind-be-with-me', 'gale-burst', 'pulse', 'energy-shield', 'mend-wounds', 'greater-mend', 'antivenom', 'fortify', 'iron-skin', 'shield', 'cleanse', 'revitalize', 'golden-boy', 'insurance', 'counter-attack', 'retaliation', 'internal-bleeding', 'strip', 'demoralize', 'weaken', 'cripple', 'enfeeblement', 'dreadfall', 'whats-mine-is-yours', 'judas', 'jump-him', 'follow-the-leader', 'bloodthirsty', 'swiftness', 'clarity', 'mana-surge', 'guided-strike', 'stabilize', 'light-orb', 'warmth', 'cooling', 'levitation', 'seal', 'magecraft-detection', 'purify-water', 'silent-step', 'taunt', 'entangle', 'pure-chaos', 'equilibrium', 'preparation');

insert into public.market_products (vendor_id, product_key, item_name, description, item_type, rarity, price_coin, stock_quantity, shop_section, quantity_step, catalog_item_key, product_kind, mana_cost, mana_label, is_available, display_order)
select
  v.id,
  'spell-' || s.spell_key,
  s.name,
  trim(concat_ws(' - ', nullif(s.mana_label, ''), nullif(coalesce(nullif(s.details, ''), nullif(s.summary, '')), ''))),
  'quest',
  s.rarity,
  s.price_coin,
  null,
  s.spell_type || ' Spells',
  1,
  s.spell_key,
  'spell',
  s.mana_cost,
  s.mana_label,
  s.is_available,
  s.display_order
from public.shop_vendors v
join public.spell_catalog s on s.spell_key in ('emberbolt', 'scorch', 'flame-ring', 'solar-flare', 'radiance', 'fireball', 'sear', 'frostbite', 'ice-shard', 'hypothermia', 'ice-wall', 'ice-cube', 'christmas-tree', 'absolute-zero', 'sparkshot', 'static-charge', 'arc-shot', 'defibrillate', 'electric-explosion', 'thunder-crash', 'lightning-chain', 'stone-fist', 'quicksand', 'earthen-spikes', 'earthquake', 'wind-cutter', 'mighty-gust', 'wind-be-with-me', 'gale-burst', 'pulse', 'energy-shield', 'mend-wounds', 'greater-mend', 'antivenom', 'fortify', 'iron-skin', 'shield', 'cleanse', 'revitalize', 'golden-boy', 'insurance', 'counter-attack', 'retaliation', 'internal-bleeding', 'strip', 'demoralize', 'weaken', 'cripple', 'enfeeblement', 'dreadfall', 'whats-mine-is-yours', 'judas', 'jump-him', 'follow-the-leader', 'bloodthirsty', 'swiftness', 'clarity', 'mana-surge', 'guided-strike', 'stabilize', 'light-orb', 'warmth', 'cooling', 'levitation', 'seal', 'magecraft-detection', 'purify-water', 'silent-step', 'taunt', 'entangle', 'pure-chaos', 'equilibrium', 'preparation')
where v.vendor_key = 'calostrynn-spells'
  and not exists (
    select 1 from public.market_products existing
    where existing.vendor_id = v.id
  )
  and not exists (select 1 from public.app_data_repairs where repair_key = 'calostrynn-shop-defaults-preexisting-2026-08-24')
on conflict (product_key) do nothing;

create or replace function public.spell_record_to_json(p_spell public.spell_catalog)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'id', p_spell.id,
    'key', p_spell.spell_key,
    'name', p_spell.name,
    'school', p_spell.school,
    'type', p_spell.spell_type,
    'manaCost', p_spell.mana_cost,
    'manaLabel', p_spell.mana_label,
    'summary', p_spell.summary,
    'details', p_spell.details,
    'rarity', p_spell.rarity
  )
$$;

create or replace function public.safe_slug(p_value text)
returns text
language sql
immutable
as $$
  select coalesce(nullif(regexp_replace(lower(trim(coalesce(p_value, ''))), '[^a-z0-9]+', '-', 'g'), ''), 'entry')
$$;

create or replace function public.create_shop_vendor(
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
  v_city public.cities%rowtype;
  v_patch jsonb := coalesce(p_patch, '{}'::jsonb);
  v_blueprint text := coalesce(nullif(v_patch->>'blueprintType', ''), 'market');
  v_name text := coalesce(nullif(trim(v_patch->>'name'), ''), 'New Shop');
  v_vendor public.shop_vendors%rowtype;
  v_source public.shop_vendors%rowtype;
  v_currency text;
begin
  v_profile := public.require_dm_profile(p_session_token);

  if v_blueprint not in ('market', 'blacksmith', 'armory', 'brewery', 'spell_registrar', 'library', 'stable') then
    raise exception 'Unsupported shop blueprint.';
  end if;

  select * into v_city from public.cities where city_key = p_city_key;
  if v_city.id is null then raise exception 'City not found.'; end if;
  v_currency := case when p_city_key = 'calostrynn' then 'calostrynn' else 'common' end;

  insert into public.shop_vendors (
    city_key,
    vendor_key,
    name,
    npc_name,
    facility,
    category,
    blueprint_type,
    payout_character_id,
    is_custom,
    is_hidden,
    display_order
  )
  values (
    p_city_key,
    public.safe_slug(p_city_key || '-' || v_name || '-' || substring(gen_random_uuid()::text from 1 for 8)),
    v_name,
    coalesce(nullif(trim(v_patch->>'npcName'), ''), 'Shopkeeper'),
    coalesce(nullif(trim(v_patch->>'facility'), ''), initcap(replace(v_blueprint, '_', ' '))),
    coalesce(nullif(trim(v_patch->>'category'), ''), initcap(replace(v_blueprint, '_', ' '))),
    v_blueprint,
    nullif(v_patch->>'payoutCharacterId', '')::uuid,
    true,
    coalesce((v_patch->>'hidden')::boolean, false),
    coalesce((select max(display_order) + 10 from public.shop_vendors where city_key = p_city_key), 10)
  )
  returning * into v_vendor;

  if v_blueprint in ('blacksmith', 'armory', 'brewery') then
    select * into v_source
    from public.shop_vendors
    where vendor_key = case
      when v_blueprint = 'blacksmith' then 'calostrynn-blacksmith'
      when v_blueprint = 'armory' then 'calostrynn-armory'
      else 'calostrynn-brewery'
    end;

    insert into public.market_products (
      vendor_id,
      product_key,
      item_name,
      description,
      item_type,
      rarity,
      price_coin,
      currency_system_key,
      stock_quantity,
      catalog_item_key,
      shop_section,
      quantity_step,
      product_kind,
      document_author,
      document_content,
      document_pages,
      document_visibility,
      document_editor_user_id,
      is_available,
      display_order
    )
    select
      v_vendor.id,
      public.safe_slug(v_vendor.vendor_key || '-' || p.product_key),
      p.item_name,
      p.description,
      p.item_type,
      p.rarity,
      case when p_city_key = 'calostrynn' then p.price_coin else 0 end,
      v_currency,
      p.stock_quantity,
      p.catalog_item_key,
      p.shop_section,
      p.quantity_step,
      p.product_kind,
      p.document_author,
      p.document_content,
      p.document_pages,
      p.document_visibility,
      p.document_editor_user_id,
      p.is_available,
      p.display_order
    from public.market_products p
    where p.vendor_id = v_source.id;
  end if;

  update public.market_products
  set currency_system_key = 'common',
      price_coin = 0
  where vendor_id = v_vendor.id
    and v_vendor.city_key <> 'calostrynn';

  insert into public.shop_sections (vendor_id, section_key, section_name, display_order)
  select v_vendor.id, public.safe_slug(coalesce(nullif(trim(p.shop_section), ''), 'Wares')), coalesce(nullif(trim(p.shop_section), ''), 'Wares'), coalesce(min(p.display_order), 0)
  from public.market_products p
  where p.vendor_id = v_vendor.id
  group by coalesce(nullif(trim(p.shop_section), ''), 'Wares')
  on conflict (vendor_id, section_key) do update
  set section_name = excluded.section_name,
      display_order = least(public.shop_sections.display_order, excluded.display_order);

  insert into public.shop_sections (vendor_id, section_key, section_name, section_type, display_order, slot_count)
  select v_vendor.id, public.safe_slug(seed.section_name), seed.section_name, seed.section_type, seed.display_order, seed.slot_count
  from (values
    ('market', 'Wares', 'standard', 10, 0),
    ('blacksmith', 'Material Scales', 'standard', 10, 0),
    ('blacksmith', 'Runes', 'standard', 20, 0),
    ('blacksmith', 'Light Weapons', 'standard', 100, 0),
    ('blacksmith', 'Medium Weapons', 'standard', 110, 0),
    ('blacksmith', 'Heavy Weapons', 'standard', 120, 0),
    ('blacksmith', 'Magecraft Commissions', 'standard', 130, 0),
    ('blacksmith', 'Shield Creation', 'standard', 140, 0),
    ('blacksmith', 'Mythril Services', 'standard', 200, 0),
    ('blacksmith', 'Dragon Scale Refining', 'standard', 210, 0),
    ('armory', 'Material Scales', 'standard', 10, 0),
    ('armory', 'Armor Creation', 'standard', 100, 0),
    ('armory', 'Mythril Services', 'standard', 200, 0),
    ('armory', 'Dragon Scale Refining', 'standard', 210, 0),
    ('brewery', 'Brewing Supplies', 'standard', 10, 0),
    ('brewery', 'Finished Potions', 'standard', 20, 0),
    ('brewery', 'Brew Potion', 'standard', 100, 0),
    ('spell_registrar', 'Ember Spells', 'standard', 10, 0),
    ('spell_registrar', 'Frost Spells', 'standard', 20, 0),
    ('spell_registrar', 'Lightning Spells', 'standard', 30, 0),
    ('spell_registrar', 'Earth Spells', 'standard', 40, 0),
    ('spell_registrar', 'Wind Spells', 'standard', 50, 0),
    ('spell_registrar', 'Energy Spells', 'standard', 60, 0),
    ('spell_registrar', 'Defensive Support Spells', 'standard', 70, 0),
    ('spell_registrar', 'Offensive Support Spells', 'standard', 80, 0),
    ('spell_registrar', 'Enhancement Spells', 'standard', 90, 0),
    ('spell_registrar', 'Utility Spells', 'standard', 100, 0),
    ('stable', 'Sale Stalls', 'sale', 10, 6),
    ('stable', 'Rental Stalls', 'rent', 20, 6),
    ('stable', 'Holding Pens', 'holding', 30, 6)
  ) as seed(blueprint_type, section_name, section_type, display_order, slot_count)
  where seed.blueprint_type = v_blueprint
  on conflict (vendor_id, section_key) do nothing;

  return public.get_discovered_cities(p_session_token);
end;
$$;

create or replace function public.create_market_product(
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
  v_vendor public.shop_vendors%rowtype;
  v_patch jsonb := coalesce(p_patch, '{}'::jsonb);
  v_name text := coalesce(nullif(trim(v_patch->>'name'), ''), 'New Item');
  v_section text := coalesce(nullif(trim(v_patch->>'section'), ''), 'Wares');
  v_kind text;
  v_currency text;
  v_spell_type text;
  v_spell_key text;
  v_section_record public.shop_sections%rowtype;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then
    raise exception 'Invalid or expired session.';
  end if;

  select * into v_vendor from public.shop_vendors where id = p_vendor_id;
  if v_vendor.id is null then raise exception 'Shop not found.'; end if;
  if not public.profile_can_manage_shop_vendor(v_profile, v_vendor) then
    raise exception 'You do not have permission to add products to this shop.';
  end if;

  if v_profile.role <> 'dm'::public.user_role
    and (not (v_patch ? 'stockQuantity') or jsonb_typeof(v_patch->'stockQuantity') = 'null')
  then
    raise exception 'Only the Dungeon Master can create infinite stock.';
  end if;

  v_kind := case
    when v_patch ? 'kind' and v_patch->>'kind' in ('item', 'spell', 'document', 'service') then v_patch->>'kind'
    when v_vendor.blueprint_type = 'spell_registrar' then 'spell'
    when v_vendor.blueprint_type = 'library' then 'document'
    else 'item'
  end;
  v_currency := case when v_vendor.city_key = 'calostrynn' then 'calostrynn' else 'common' end;

  if v_vendor.blueprint_type = 'stable' then
    v_kind := 'item';
    v_section := coalesce(nullif(trim(v_patch->>'section'), ''), 'Sale Stalls');

    if public.normalize_item_type(coalesce(v_patch->>'type', 'pet')) <> 'pet' then
      raise exception 'Stable listings can only sell or rent pets.';
    end if;

    select * into v_section_record
    from public.shop_sections
    where vendor_id = p_vendor_id
      and section_name = v_section;

    if v_section_record.id is null then
      raise exception 'Create that stable section before listing animals in it.';
    end if;

    if v_section_record.id is not null
      and v_section_record.slot_count > 0
      and (
        select count(*)::int
        from public.market_products p
        where p.vendor_id = p_vendor_id
          and coalesce(nullif(trim(p.shop_section), ''), 'Wares') = v_section
      ) >= v_section_record.slot_count
    then
      raise exception 'That stable section has no open listing slots.';
    end if;
  end if;

  if v_kind = 'spell' then
    v_spell_type := case
      when v_section in ('Ember', 'Frost', 'Lightning', 'Earth', 'Wind', 'Energy', 'Defensive Support', 'Offensive Support', 'Enhancement', 'Utility') then v_section
      when regexp_replace(v_section, '\s+Spells$', '', 'i') in ('Ember', 'Frost', 'Lightning', 'Earth', 'Wind', 'Energy', 'Defensive Support', 'Offensive Support', 'Enhancement', 'Utility') then regexp_replace(v_section, '\s+Spells$', '', 'i')
      else 'Utility'
    end;
    v_section := v_spell_type || ' Spells';
    v_spell_key := public.catalog_key_for_name(v_name);

    insert into public.spell_catalog (spell_key, name, school, spell_type, mana_cost, mana_label, summary, details, rarity, is_available, display_order, price_coin)
    values (
      v_spell_key,
      v_name,
      'arcane',
      v_spell_type,
      greatest(0, coalesce(nullif(v_patch->>'manaCost', '')::int, 0)),
      greatest(0, coalesce(nullif(v_patch->>'manaCost', '')::int, 0))::text || ' mana',
      coalesce(v_patch->>'description', ''),
      coalesce(v_patch->>'description', ''),
      coalesce(nullif(v_patch->>'rarity', ''), 'Common')::public.item_rarity,
      true,
      coalesce((select max(display_order) + 10 from public.spell_catalog), 10),
      greatest(0, coalesce(nullif(v_patch->>'priceCoin', '')::int, 0))
    )
    on conflict (spell_key) do update
    set name = excluded.name,
        spell_type = excluded.spell_type,
        mana_cost = excluded.mana_cost,
        mana_label = excluded.mana_label,
        summary = excluded.summary,
        details = excluded.details,
        rarity = excluded.rarity,
        is_available = true;
  end if;

  insert into public.market_products (
    vendor_id,
    product_key,
    item_name,
    description,
    item_type,
    rarity,
    price_coin,
    currency_system_key,
    stock_quantity,
    catalog_item_key,
    shop_section,
    quantity_step,
    product_kind,
    mana_cost,
    mana_label,
    document_author,
    document_content,
    document_pages,
    document_visibility,
    document_editor_user_id,
    is_available,
    display_order
  )
  values (
    p_vendor_id,
    public.safe_slug(v_vendor.vendor_key || '-' || v_name || '-' || substring(gen_random_uuid()::text from 1 for 8)),
    v_name,
    coalesce(v_patch->>'description', ''),
    case
      when v_kind = 'spell' then 'misc'
      when v_kind = 'document' then 'book'
      when v_vendor.blueprint_type = 'stable' then 'pet'
      else public.normalize_item_type(coalesce(v_patch->>'type', 'misc'))
    end,
    coalesce(nullif(v_patch->>'rarity', ''), 'Common')::public.item_rarity,
    greatest(0, coalesce(nullif(v_patch->>'priceCoin', '')::int, 0)),
    case when v_currency = 'calostrynn' and v_patch ? 'currencySystemKey' and v_patch->>'currencySystemKey' = 'calostrynn' then 'calostrynn' else v_currency end,
    case
      when v_patch ? 'stockQuantity' and jsonb_typeof(v_patch->'stockQuantity') = 'null' then null
      when v_vendor.blueprint_type = 'stable' then greatest(0, coalesce(nullif(v_patch->>'stockQuantity', '')::numeric, 1))
      when v_patch ? 'stockQuantity' then greatest(0, (v_patch->>'stockQuantity')::numeric)
      else null
    end,
    coalesce(nullif(v_patch->>'catalogItemKey', ''), case when v_kind = 'spell' then v_spell_key else public.catalog_key_for_name(v_name) end),
    v_section,
    case when v_vendor.blueprint_type = 'stable' then 1 when v_patch ? 'quantityStep' and (v_patch->>'quantityStep')::numeric = 0.5 then 0.5 else 1 end,
    v_kind,
    case when v_kind = 'spell' then greatest(0, coalesce(nullif(v_patch->>'manaCost', '')::int, 0)) else 0 end,
    case when v_kind = 'spell' then greatest(0, coalesce(nullif(v_patch->>'manaCost', '')::int, 0))::text || ' mana' else '' end,
    left(trim(coalesce(v_patch->>'documentAuthor', '')), 160),
    left(coalesce(v_patch->>'documentContent', ''), 12000),
    case
      when v_patch ? 'documentPages' and jsonb_typeof(v_patch->'documentPages') = 'array'
        then (
          select coalesce(jsonb_agg(left(page.value #>> '{}', 950)), '[]'::jsonb)
          from jsonb_array_elements(v_patch->'documentPages') as page(value)
        )
      when length(trim(coalesce(v_patch->>'documentContent', ''))) > 0 then to_jsonb(array[left(coalesce(v_patch->>'documentContent', ''), 950)])
      else '[]'::jsonb
    end,
    case when v_patch ? 'documentVisibility' and v_patch->>'documentVisibility' = 'government' then 'government' else 'for_sale' end,
    nullif(v_patch->>'documentEditorUserId', '')::uuid,
    coalesce((v_patch->>'available')::boolean, true),
    coalesce((select max(display_order) + 10 from public.market_products where vendor_id = p_vendor_id), 10)
  );

  insert into public.shop_sections (vendor_id, section_key, section_name, section_type, display_order)
  values (
    p_vendor_id,
    public.safe_slug(v_section),
    v_section,
    case when v_vendor.blueprint_type = 'stable' then v_section_record.section_type else 'standard' end,
    coalesce((select max(display_order) + 10 from public.shop_sections where vendor_id = p_vendor_id), 10)
  )
  on conflict (vendor_id, section_key) do update
  set section_name = excluded.section_name,
      section_type = excluded.section_type;

  return public.get_discovered_cities(p_session_token);
end;
$$;

create or replace function public.delete_market_product(
  p_session_token text,
  p_product_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_product public.market_products%rowtype;
  v_vendor public.shop_vendors%rowtype;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then
    raise exception 'Invalid or expired session.';
  end if;

  select * into v_product
  from public.market_products
  where id = p_product_id;

  if v_product.id is null then
    raise exception 'Shop product not found.';
  end if;

  select * into v_vendor from public.shop_vendors where id = v_product.vendor_id;
  if not public.profile_can_manage_shop_vendor(v_profile, v_vendor) then
    raise exception 'You do not have permission to delete products from this shop.';
  end if;

  delete from public.market_products
  where id = p_product_id;

  return public.get_discovered_cities(p_session_token);
end;
$$;

create or replace function public.create_shop_section(
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
  v_vendor public.shop_vendors%rowtype;
  v_patch jsonb := coalesce(p_patch, '{}'::jsonb);
  v_name text := coalesce(nullif(trim(v_patch->>'name'), ''), 'Wares');
  v_section_type text := case when v_patch->>'sectionType' in ('sale', 'rent', 'holding') then v_patch->>'sectionType' else 'standard' end;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then
    raise exception 'Invalid or expired session.';
  end if;

  select * into v_vendor from public.shop_vendors where id = p_vendor_id;
  if v_vendor.id is null then raise exception 'Shop not found.'; end if;
  if not public.profile_can_manage_shop_vendor(v_profile, v_vendor) then
    raise exception 'You do not have permission to create sections in this shop.';
  end if;
  if v_vendor.blueprint_type <> 'stable' then
    v_section_type := 'standard';
  end if;

  insert into public.shop_sections (
    vendor_id,
    section_key,
    section_name,
    npc_name,
    role_label,
    section_type,
    slot_count,
    is_hidden,
    display_order
  )
  values (
    p_vendor_id,
    public.safe_slug(v_name),
    v_name,
    left(trim(coalesce(v_patch->>'npcName', '')), 120),
    left(trim(coalesce(v_patch->>'roleLabel', '')), 120),
    v_section_type,
    greatest(0, least(200, coalesce(nullif(v_patch->>'slotCount', '')::int, 0))),
    coalesce((v_patch->>'hidden')::boolean, false),
    coalesce(nullif(v_patch->>'order', '')::int, coalesce((select max(display_order) + 10 from public.shop_sections where vendor_id = p_vendor_id), 10))
  )
  on conflict (vendor_id, section_key) do update
  set section_name = excluded.section_name,
      npc_name = excluded.npc_name,
      role_label = excluded.role_label,
      section_type = excluded.section_type,
      slot_count = excluded.slot_count,
      is_hidden = excluded.is_hidden,
      display_order = excluded.display_order;

  return public.get_discovered_cities(p_session_token);
end;
$$;

create or replace function public.update_shop_section(
  p_session_token text,
  p_vendor_id uuid,
  p_section_id uuid,
  p_patch jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_vendor public.shop_vendors%rowtype;
  v_section public.shop_sections%rowtype;
  v_patch jsonb := coalesce(p_patch, '{}'::jsonb);
  v_name text;
  v_section_type text;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then
    raise exception 'Invalid or expired session.';
  end if;

  select * into v_vendor from public.shop_vendors where id = p_vendor_id;
  if v_vendor.id is null then raise exception 'Shop not found.'; end if;
  if not public.profile_can_manage_shop_vendor(v_profile, v_vendor) then
    raise exception 'You do not have permission to update sections in this shop.';
  end if;

  select * into v_section
  from public.shop_sections
  where id = p_section_id
    and vendor_id = p_vendor_id;

  if v_section.id is null then raise exception 'Shop section not found.'; end if;

  v_name := case when v_patch ? 'name' then coalesce(nullif(trim(v_patch->>'name'), ''), v_section.section_name) else v_section.section_name end;
  v_section_type := case
    when v_vendor.blueprint_type <> 'stable' then 'standard'
    when v_patch->>'sectionType' in ('sale', 'rent', 'holding') then v_patch->>'sectionType'
    else v_section.section_type
  end;

  update public.shop_sections
  set section_key = public.safe_slug(v_name),
      section_name = v_name,
      npc_name = case when v_patch ? 'npcName' then left(trim(coalesce(v_patch->>'npcName', '')), 120) else npc_name end,
      role_label = case when v_patch ? 'roleLabel' then left(trim(coalesce(v_patch->>'roleLabel', '')), 120) else role_label end,
      section_type = v_section_type,
      slot_count = case when v_patch ? 'slotCount' then greatest(0, least(200, (v_patch->>'slotCount')::int)) else slot_count end,
      is_hidden = case when v_patch ? 'hidden' then coalesce((v_patch->>'hidden')::boolean, false) else is_hidden end,
      display_order = case when v_patch ? 'order' then greatest(0, (v_patch->>'order')::int) else display_order end
  where id = v_section.id;

  if v_name <> v_section.section_name then
    update public.market_products
    set shop_section = v_name
    where vendor_id = p_vendor_id
      and coalesce(nullif(trim(shop_section), ''), 'Wares') = v_section.section_name;
  end if;

  return public.get_discovered_cities(p_session_token);
end;
$$;

create or replace function public.delete_market_section(
  p_session_token text,
  p_vendor_id uuid,
  p_section text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_vendor public.shop_vendors%rowtype;
  v_section text := coalesce(nullif(trim(p_section), ''), 'Wares');
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then
    raise exception 'Invalid or expired session.';
  end if;

  select * into v_vendor
  from public.shop_vendors
  where id = p_vendor_id;

  if v_vendor.id is null then
    raise exception 'Shop not found.';
  end if;
  if not public.profile_can_manage_shop_vendor(v_profile, v_vendor) then
    raise exception 'You do not have permission to delete sections from this shop.';
  end if;

  delete from public.market_products
  where vendor_id = p_vendor_id
    and coalesce(nullif(trim(shop_section), ''), 'Wares') = v_section;

  delete from public.shop_sections
  where vendor_id = p_vendor_id
    and section_name = v_section;

  return public.get_discovered_cities(p_session_token);
end;
$$;

create or replace function public.delete_shop_vendor(
  p_session_token text,
  p_vendor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_vendor public.shop_vendors%rowtype;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then
    raise exception 'Invalid or expired session.';
  end if;

  select * into v_vendor
  from public.shop_vendors
  where id = p_vendor_id;

  if v_vendor.id is null then
    raise exception 'Shop not found.';
  end if;
  if not public.profile_can_manage_shop_vendor(v_profile, v_vendor) then
    raise exception 'You do not have permission to delete this shop.';
  end if;

  delete from public.shop_vendors
  where id = p_vendor_id;

  return public.get_discovered_cities(p_session_token);
end;
$$;

create or replace function public.stock_shop_from_inventory(
  p_session_token text,
  p_vendor_id uuid,
  p_item_id uuid,
  p_quantity numeric,
  p_price_coin int,
  p_section text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_vendor public.shop_vendors%rowtype;
  v_item public.inventory_items%rowtype;
  v_catalog public.item_catalog%rowtype;
  v_section public.shop_sections%rowtype;
  v_quantity numeric := coalesce(p_quantity, 0);
  v_section_name text := coalesce(nullif(trim(p_section), ''), 'Wares');
  v_section_type text := 'standard';
  v_product_kind text := 'item';
  v_can_manage boolean := false;
  v_can_price_stable boolean := false;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then
    raise exception 'Invalid or expired session.';
  end if;

  select * into v_vendor from public.shop_vendors where id = p_vendor_id;
  if v_vendor.id is null then
    raise exception 'Shop not found.';
  end if;
  v_can_manage := public.profile_can_manage_shop_vendor(v_profile, v_vendor);
  v_can_price_stable := public.profile_can_price_stable_vendor(v_profile, v_vendor);
  if not v_can_manage and not v_can_price_stable then
    raise exception 'You do not have permission to stock this shop.';
  end if;
  if v_vendor.payout_character_id is null then
    raise exception 'Choose a payout character before stocking inventory.';
  end if;

  select * into v_item
  from public.inventory_items
  where id = p_item_id
    and character_id = v_vendor.payout_character_id
  for update;

  if v_item.id is null then
    raise exception 'Inventory item not found for this shopkeeper.';
  end if;
  if v_item.loadout_slot is not null then
    raise exception 'Equipped items cannot be stocked.';
  end if;
  if public.normalize_item_type(v_item.item_type) = 'currency' then
    raise exception 'Currency cannot be stocked as a shop product.';
  end if;
  if exists (select 1 from public.inventory_items child where child.parent_item_id = v_item.id) then
    raise exception 'Empty that storage item before listing it in a shop.';
  end if;
  if v_vendor.blueprint_type = 'stable' and public.normalize_item_type(v_item.item_type) <> 'pet' then
    raise exception 'Stable inventory can only stock pets.';
  end if;
  if v_vendor.blueprint_type <> 'stable' and public.normalize_item_type(v_item.item_type) = 'pet' then
    raise exception 'Pets belong in stable shops.';
  end if;

  select * into v_section
  from public.shop_sections
  where vendor_id = p_vendor_id
    and section_name = v_section_name;

  if v_section.id is null then
    raise exception 'Create that shop section before adding inventory to it.';
  end if;
  v_section_type := v_section.section_type;

  if v_vendor.blueprint_type = 'stable' then
    if v_section_type <> 'holding' then
      raise exception 'Animals must be added to Holding Pens first. Move them to sale or rent after pricing.';
    end if;
    if v_section.slot_count > 0
      and (
        select count(*)::int
        from public.market_products p
        where p.vendor_id = p_vendor_id
          and coalesce(nullif(trim(p.shop_section), ''), 'Wares') = v_section_name
      ) >= v_section.slot_count
    then
      raise exception 'That stable section has no open listing slots.';
    end if;
  else
    if not exists (
      select 1
      from public.market_products p
      where p.vendor_id = p_vendor_id
        and p.is_available
        and public.normalize_item_type(p.item_type) = public.normalize_item_type(v_item.item_type)
        and (
          coalesce(nullif(p.catalog_item_key, ''), public.catalog_key_for_name(p.item_name)) = public.catalog_key_for_name(v_item.item_name)
          or lower(public.normalize_item_name(p.item_name)) = lower(public.normalize_item_name(v_item.item_name))
        )
    ) then
      raise exception 'That item is not actively listed by this shop.';
    end if;
  end if;

  v_quantity := public.assert_valid_item_quantity(v_item.item_name, v_item.item_type, greatest(0.5, v_quantity));
  if v_item.is_storage or public.normalize_item_type(v_item.item_type) in ('pet', 'weapon', 'armor', 'shield', 'accessory', 'tool', 'book', 'spell book') then
    v_quantity := 1;
  end if;
  if v_quantity > v_item.quantity then
    raise exception 'Not enough quantity to stock.';
  end if;

  select * into v_catalog
  from public.item_catalog
  where item_key = public.catalog_key_for_name(v_item.item_name)
  limit 1;

  insert into public.market_products (
    vendor_id,
    product_key,
    item_name,
    description,
    item_type,
    rarity,
    price_coin,
    currency_system_key,
    stock_quantity,
    catalog_item_key,
    shop_section,
    quantity_step,
    product_kind,
    item_is_accessory,
    item_is_storage,
    item_storage_capacity,
    item_modifiers,
    item_enchantment,
    item_rune_name,
    item_material,
    item_enhancement_count,
    item_is_two_handed,
    item_potion_strength,
    item_potion_property,
    item_potion_quality,
    item_spell_book_form,
    is_available,
    display_order
  )
  values (
    p_vendor_id,
    public.safe_slug(v_vendor.vendor_key || '-' || v_item.item_name || '-' || substring(gen_random_uuid()::text from 1 for 8)),
    v_item.item_name,
    left(trim(coalesce(v_item.item_description, '')), 1500),
    public.normalize_item_type(v_item.item_type),
    v_item.rarity,
    case when v_section_type = 'holding' then 0 else greatest(0, coalesce(p_price_coin, 0)) end,
    'common',
    v_quantity,
    coalesce(v_catalog.item_key, public.catalog_key_for_name(v_item.item_name)),
    v_section_name,
    public.assert_valid_item_quantity(v_item.item_name, v_item.item_type, 1),
    v_product_kind,
    v_item.is_accessory,
    v_item.is_storage,
    v_item.storage_capacity,
    coalesce(v_item.modifiers, '{}'::jsonb),
    v_item.enchantment,
    v_item.rune_name,
    v_item.material,
    v_item.enhancement_count,
    v_item.is_two_handed,
    v_item.potion_strength,
    v_item.potion_property,
    v_item.potion_quality,
    v_item.spell_book_form,
    true,
    coalesce((select max(display_order) + 10 from public.market_products where vendor_id = p_vendor_id), 10)
  );

  if v_quantity >= v_item.quantity then
    delete from public.inventory_items where id = v_item.id;
  else
    update public.inventory_items
    set quantity = quantity - v_quantity
    where id = v_item.id;
  end if;

  return public.get_discovered_cities(p_session_token);
end;
$$;









grant execute on function public.safe_slug(text) to anon, authenticated;
grant execute on function public.shop_section_record_to_json(public.shop_sections) to anon, authenticated;
grant execute on function public.market_product_record_to_json(public.market_products, boolean) to anon, authenticated;
grant execute on function public.profile_runs_shop_vendor(public.profiles, public.shop_vendors) to anon, authenticated;
grant execute on function public.profile_can_manage_shop_vendor(public.profiles, public.shop_vendors) to anon, authenticated;
grant execute on function public.profile_can_price_stable_vendor(public.profiles, public.shop_vendors) to anon, authenticated;
grant execute on function public.stable_section_type_for_product(public.market_products) to anon, authenticated;
grant execute on function public.create_shop_vendor(text, text, jsonb) to anon, authenticated;
grant execute on function public.create_shop_section(text, uuid, jsonb) to anon, authenticated;
grant execute on function public.update_shop_section(text, uuid, uuid, jsonb) to anon, authenticated;
grant execute on function public.create_market_product(text, uuid, jsonb) to anon, authenticated;
grant execute on function public.delete_market_product(text, uuid) to anon, authenticated;
grant execute on function public.delete_market_section(text, uuid, text) to anon, authenticated;
grant execute on function public.delete_shop_vendor(text, uuid) to anon, authenticated;
grant execute on function public.stock_shop_from_inventory(text, uuid, uuid, numeric, int, text) to anon, authenticated;

create or replace function public.character_spell_record_to_json(p_entry public.character_spells)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'id', p_entry.id,
    'characterId', p_entry.character_id,
    'spellId', p_entry.spell_id,
    'active', p_entry.is_active,
    'slotIndex', p_entry.slot_index,
    'spell', jsonb_build_object(
      'id', s.id,
      'key', s.spell_key,
      'name', coalesce(nullif(p_entry.custom_name, ''), s.name),
      'school', s.school,
      'type', s.spell_type,
      'manaCost', coalesce(p_entry.custom_mana_cost, s.mana_cost),
      'manaLabel', case
        when p_entry.custom_mana_cost is not null then p_entry.custom_mana_cost::text || ' mana'
        else s.mana_label
      end,
      'summary', coalesce(nullif(p_entry.custom_summary, ''), s.summary),
      'details', coalesce(nullif(p_entry.custom_details, ''), s.details),
      'rarity', s.rarity
    )
  )
  from public.spell_catalog s
  where s.id = p_entry.spell_id
$$;

create or replace function public.character_has_active_battle(p_character_id uuid)
returns boolean
language sql
stable
set search_path = public
as $$
  select exists (
    select 1
    from public.combatants cb
    join public.battles b on b.id = cb.battle_id
    where cb.character_id = p_character_id
      and b.status = 'active'::public.battle_status
  )
$$;

create or replace function public.find_first_free_spell_slot(p_character_id uuid, p_spell_slots int)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_slot int;
begin
  if p_spell_slots <= 0 then
    return null;
  end if;

  for v_slot in 0..greatest(p_spell_slots - 1, 0) loop
    if not exists (
      select 1
      from public.character_spells s
      where s.character_id = p_character_id
        and s.is_active
        and s.slot_index = v_slot
    ) then
      return v_slot;
    end if;
  end loop;

  return null;
end;
$$;

create or replace function public.get_character_spells(
  p_session_token text,
  p_character_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_character public.characters%rowtype;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;

  select * into v_character
  from public.characters
  where id = p_character_id;

  if v_character.id is null then
    raise exception 'Character not found.';
  end if;

  if v_profile.role <> 'dm'::public.user_role
     and v_character.kind <> 'player'::public.character_kind then
    raise exception 'You do not have access to this character''s spells.';
  end if;

  return jsonb_build_object(
    'catalog', (
      select coalesce(jsonb_agg(public.spell_record_to_json(s) order by s.display_order, s.name), '[]'::jsonb)
      from public.spell_catalog s
      where s.is_available or v_profile.role = 'dm'::public.user_role
    ),
    'spells', (
      select coalesce(jsonb_agg(public.character_spell_record_to_json(cs) order by cs.is_active desc, cs.slot_index, (public.character_spell_record_to_json(cs)->'spell'->>'name')), '[]'::jsonb)
      from public.character_spells cs
      where cs.character_id = p_character_id
    ),
    'activeBattle', public.character_has_active_battle(p_character_id)
  );
end;
$$;

create or replace function public.grant_character_spell(
  p_session_token text,
  p_character_id uuid,
  p_spell_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_character public.characters%rowtype;
  v_slot int;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;

  v_character := public.assert_inventory_access(v_profile, p_character_id, true);

  if not exists (select 1 from public.spell_catalog where id = p_spell_id) then
    raise exception 'Spell not found.';
  end if;

  v_slot := public.find_first_free_spell_slot(p_character_id, v_character.spell_slots);

  insert into public.character_spells (character_id, spell_id, is_active, slot_index)
  values (p_character_id, p_spell_id, v_slot is not null, v_slot);

  return public.get_character_spells(p_session_token, p_character_id);
end;
$$;

create or replace function public.update_character_spell_details(
  p_session_token text,
  p_character_spell_id uuid,
  p_patch jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_entry public.character_spells%rowtype;
  v_patch jsonb := coalesce(p_patch, '{}'::jsonb);
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;

  select * into v_entry from public.character_spells where id = p_character_spell_id;
  if v_entry.id is null then raise exception 'Character spell not found.'; end if;

  perform public.assert_inventory_access(v_profile, v_entry.character_id, false);

  update public.character_spells
  set custom_name = case
        when v_patch ? 'name' then nullif(left(trim(coalesce(v_patch->>'name', '')), 120), '')
        else custom_name
      end,
      custom_summary = case
        when v_patch ? 'summary' then nullif(left(trim(coalesce(v_patch->>'summary', '')), 500), '')
        when v_patch ? 'details' then nullif(left(trim(coalesce(v_patch->>'details', '')), 500), '')
        else custom_summary
      end,
      custom_details = case
        when v_patch ? 'details' then nullif(left(trim(coalesce(v_patch->>'details', '')), 4000), '')
        else custom_details
      end,
      custom_mana_cost = case
        when v_patch ? 'manaCost' and nullif(trim(coalesce(v_patch->>'manaCost', '')), '') is not null then greatest(0, (v_patch->>'manaCost')::int)
        else custom_mana_cost
      end
  where id = p_character_spell_id
  returning * into v_entry;

  return public.get_character_spells(p_session_token, v_entry.character_id);
end;
$$;

create or replace function public.update_character_spell_state(
  p_session_token text,
  p_character_spell_id uuid,
  p_patch jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_entry public.character_spells%rowtype;
  v_character public.characters%rowtype;
  v_patch jsonb := coalesce(p_patch, '{}'::jsonb);
  v_active boolean;
  v_slot int;
  v_conflict public.character_spells%rowtype;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;

  select * into v_entry from public.character_spells where id = p_character_spell_id;
  if v_entry.id is null then raise exception 'Character spell not found.'; end if;

  v_character := public.assert_inventory_access(v_profile, v_entry.character_id, false);

  if public.character_has_active_battle(v_entry.character_id) then
    raise exception 'Spell swapping is locked during combat.';
  end if;

  v_active := case when v_patch ? 'active' then (v_patch->>'active')::boolean else v_entry.is_active end;

  if not v_active then
    update public.character_spells
    set is_active = false,
        slot_index = null
    where id = p_character_spell_id;
    return public.get_character_spells(p_session_token, v_entry.character_id);
  end if;

  v_slot := case when v_patch ? 'slotIndex' and nullif(v_patch->>'slotIndex', '') is not null then (v_patch->>'slotIndex')::int else public.find_first_free_spell_slot(v_entry.character_id, v_character.spell_slots) end;

  if v_slot is null or v_slot < 0 or v_slot >= v_character.spell_slots then
    raise exception 'No active spell slot is available.';
  end if;

  select * into v_conflict
  from public.character_spells cs
  where cs.character_id = v_entry.character_id
    and cs.is_active
    and cs.slot_index = v_slot
    and cs.id <> v_entry.id
  limit 1;

  if v_conflict.id is not null then
    if v_entry.is_active and v_entry.slot_index is not null then
      update public.character_spells
      set slot_index = null
      where id = v_entry.id;

      update public.character_spells
      set slot_index = v_entry.slot_index
      where id = v_conflict.id;
    else
      update public.character_spells
      set is_active = false,
          slot_index = null
      where id = v_conflict.id;
    end if;
  end if;

  update public.character_spells
  set is_active = true,
      slot_index = v_slot
  where id = p_character_spell_id;

  return public.get_character_spells(p_session_token, v_entry.character_id);
end;
$$;

create or replace function public.delete_character_spell(
  p_session_token text,
  p_character_spell_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_entry public.character_spells%rowtype;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;

  select * into v_entry from public.character_spells where id = p_character_spell_id;
  if v_entry.id is null then raise exception 'Character spell not found.'; end if;

  perform public.assert_inventory_access(v_profile, v_entry.character_id, false);

  delete from public.character_spells
  where id = p_character_spell_id;

  return public.get_character_spells(p_session_token, v_entry.character_id);
end;
$$;

create or replace function public.use_character_spell(
  p_session_token text,
  p_character_spell_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_entry public.character_spells%rowtype;
  v_spell public.spell_catalog%rowtype;
  v_character public.characters%rowtype;
  v_combatant public.combatants%rowtype;
  v_current_mana int;
  v_mana_cost int;
  v_remaining_mana int;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;

  select * into v_entry from public.character_spells where id = p_character_spell_id;
  if v_entry.id is null then raise exception 'Character spell not found.'; end if;

  if not v_entry.is_active then
    raise exception 'Only active spells can be used.';
  end if;

  v_character := public.assert_inventory_access(v_profile, v_entry.character_id, false);
  select * into v_spell from public.spell_catalog where id = v_entry.spell_id;
  v_mana_cost := coalesce(v_entry.custom_mana_cost, v_spell.mana_cost);

  select cb.* into v_combatant
  from public.combatants cb
  join public.battles b on b.id = cb.battle_id
  where cb.character_id = v_entry.character_id
    and b.status = 'active'::public.battle_status
  order by cb.created_at desc
  limit 1;

  v_current_mana := coalesce(v_combatant.current_mana, v_character.current_mana);

  if v_current_mana < v_mana_cost then
    raise exception 'Not enough mana.';
  end if;

  v_remaining_mana := v_current_mana - v_mana_cost;

  if v_combatant.id is not null then
    update public.combatants
    set current_mana = v_remaining_mana
    where id = v_combatant.id;
  end if;

  update public.characters
  set current_mana = v_remaining_mana
  where id = v_character.id;

  return jsonb_build_object(
    'characterId', v_character.id,
    'currentMana', v_remaining_mana,
    'manaSpent', v_mana_cost,
    'spellName', coalesce(nullif(v_entry.custom_name, ''), v_spell.name)
  );
end;
$$;

create or replace function public.use_inventory_enchantment_spell(
  p_session_token text,
  p_character_id uuid,
  p_item_id uuid,
  p_spell_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_character public.characters%rowtype;
  v_item public.inventory_items%rowtype;
  v_spell public.spell_catalog%rowtype;
  v_combatant public.combatants%rowtype;
  v_current_mana int;
  v_remaining_mana int;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;

  v_character := public.assert_inventory_access(v_profile, p_character_id, false);

  select * into v_item
  from public.inventory_items
  where id = p_item_id
    and character_id = v_character.id;

  if v_item.id is null then raise exception 'Enchanted item not found.'; end if;
  if nullif(trim(coalesce(v_item.enchantment, '')), '') is null then raise exception 'That item has no spell enchantment.'; end if;

  select * into v_spell from public.spell_catalog where id = p_spell_id;
  if v_spell.id is null then raise exception 'Spell not found.'; end if;

  if lower(regexp_replace(v_item.enchantment, '[^a-z0-9]+', ' ', 'g')) <> lower(regexp_replace(v_spell.name, '[^a-z0-9]+', ' ', 'g'))
     and lower(regexp_replace(v_item.enchantment, '[^a-z0-9]+', ' ', 'g')) <> lower(regexp_replace(v_spell.spell_key, '[^a-z0-9]+', ' ', 'g')) then
    raise exception 'That spell does not match this item enchantment.';
  end if;

  select cb.* into v_combatant
  from public.combatants cb
  join public.battles b on b.id = cb.battle_id
  where cb.character_id = v_character.id
    and b.status = 'active'::public.battle_status
  order by cb.created_at desc
  limit 1;

  v_current_mana := coalesce(v_combatant.current_mana, v_character.current_mana);
  if v_current_mana < v_spell.mana_cost then raise exception 'Not enough mana.'; end if;

  v_remaining_mana := v_current_mana - v_spell.mana_cost;

  if v_combatant.id is not null then
    update public.combatants set current_mana = v_remaining_mana where id = v_combatant.id;
  end if;

  update public.characters set current_mana = v_remaining_mana where id = v_character.id;

  return jsonb_build_object(
    'characterId', v_character.id,
    'currentMana', v_remaining_mana,
    'manaSpent', v_spell.mana_cost,
    'spellName', v_spell.name,
    'itemName', coalesce(v_item.display_name, v_item.item_name)
  );
end;
$$;

create or replace function public.use_spell_book_item(
  p_session_token text,
  p_character_id uuid,
  p_item_id uuid,
  p_target_character_id uuid,
  p_form int,
  p_caster_on_fire boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_character public.characters%rowtype;
  v_target public.characters%rowtype;
  v_item public.inventory_items%rowtype;
  v_caster_combatant public.combatants%rowtype;
  v_target_combatant public.combatants%rowtype;
  v_mana_cost int := 40;
  v_current_mana int;
  v_remaining_mana int;
  v_heal_amount int;
  v_restore_mana int;
  v_target_hp int;
  v_target_mana int;
  v_form int;
  v_caster_is_burning boolean := false;
  v_target_is_burning boolean := false;
  v_target_healing_blocked boolean := false;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;

  v_character := public.assert_inventory_access(v_profile, p_character_id, false);
  perform public.ensure_dm_testing_wallet(v_character.id);

  select * into v_item
  from public.inventory_items
  where id = p_item_id
    and character_id = v_character.id
    and public.normalize_item_type(item_type) = 'spell book'
    and lower(public.normalize_item_name(item_name)) = lower(public.normalize_item_name('Peaceful Restoration Spell Book'));

  if v_item.id is null then raise exception 'Peaceful Restoration spell book not found.'; end if;
  v_form := coalesce(v_item.spell_book_form, 1);

  select * into v_target
  from public.characters
  where id = p_target_character_id
    and kind = 'player'::public.character_kind;

  if v_target.id is null then raise exception 'Target ally not found.'; end if;
  if v_target.id = v_character.id then raise exception 'Peaceful Restoration must target an ally, not the caster.'; end if;
  if v_form not in (1, 2) then raise exception 'Choose Peaceful Restoration form 1 or form 2.'; end if;

  select cb.* into v_caster_combatant
  from public.combatants cb
  join public.battles b on b.id = cb.battle_id
  where cb.character_id = v_character.id
    and b.status = 'active'::public.battle_status
  order by cb.created_at desc
  limit 1;

  if v_caster_combatant.id is not null then
    v_caster_is_burning := exists (
      select 1 from jsonb_array_elements(v_caster_combatant.statuses) effect
      where effect->>'key' = 'burning' and coalesce((effect->>'duration')::int, 0) > 0
    );
    select cb.* into v_target_combatant
    from public.combatants cb
    where cb.battle_id = v_caster_combatant.battle_id
      and cb.character_id = v_target.id
    limit 1;

    if v_target_combatant.id is null then
      raise exception 'Peaceful Restoration can only target an ally in the same active battle.';
    end if;
    v_target_is_burning := exists (
      select 1 from jsonb_array_elements(v_target_combatant.statuses) effect
      where effect->>'key' = 'burning' and coalesce((effect->>'duration')::int, 0) > 0
    );
    v_target_healing_blocked := exists (
      select 1 from jsonb_array_elements(v_target_combatant.statuses) effect
      where effect->>'key' in ('burning', 'bleeding') and coalesce((effect->>'duration')::int, 0) > 0
    );
  end if;

  if v_form = 2 and v_caster_is_burning then raise exception 'Form 2 cannot be used while the caster is burning.'; end if;

  v_current_mana := coalesce(v_caster_combatant.current_mana, v_character.current_mana);
  if v_current_mana < v_mana_cost then raise exception 'Not enough mana.'; end if;

  if v_form = 1 then
    if v_caster_is_burning then
      v_heal_amount := 20;
      v_restore_mana := 10;
    else
      v_heal_amount := 75;
      v_restore_mana := 25;
    end if;
  else
    v_heal_amount := 25;
    v_restore_mana := 75;
  end if;

  if v_target_healing_blocked then v_heal_amount := 0; end if;

  v_remaining_mana := v_current_mana - v_mana_cost;
  v_target_hp := least(v_target.max_hp, coalesce(v_target_combatant.current_hp, v_target.current_hp) + v_heal_amount);
  v_target_mana := least(v_target.max_mana, coalesce(v_target_combatant.current_mana, v_target.current_mana) + v_restore_mana);

  if v_caster_combatant.id is not null then
    update public.combatants
    set current_mana = v_remaining_mana
    where id = v_caster_combatant.id;

    update public.combatants
    set current_hp = v_target_hp,
        current_mana = v_target_mana
    where id = v_target_combatant.id;
  end if;

  update public.characters
  set current_mana = v_remaining_mana
  where id = v_character.id;

  update public.characters
  set current_hp = v_target_hp,
      current_mana = v_target_mana
  where id = v_target.id;

  return jsonb_build_object(
    'characterId', v_character.id,
    'targetCharacterId', v_target.id,
    'currentMana', v_remaining_mana,
    'targetCurrentHp', v_target_hp,
    'targetCurrentMana', v_target_mana,
    'manaSpent', v_mana_cost,
    'spellName', 'Peaceful Restoration',
    'form', v_form,
    'healedHp', v_heal_amount,
    'restoredMana', v_restore_mana,
    'casterOnFire', v_caster_is_burning,
    'targetWasBurning', v_target_is_burning,
    'targetHealingBlocked', v_target_healing_blocked
  );
end;
$$;

grant execute on function public.spell_record_to_json(public.spell_catalog) to anon, authenticated;
grant execute on function public.character_spell_record_to_json(public.character_spells) to anon, authenticated;
grant execute on function public.character_has_active_battle(uuid) to anon, authenticated;
grant execute on function public.find_first_free_spell_slot(uuid, int) to anon, authenticated;
grant execute on function public.get_character_spells(text, uuid) to anon, authenticated;
grant execute on function public.grant_character_spell(text, uuid, uuid) to anon, authenticated;
grant execute on function public.update_character_spell_details(text, uuid, jsonb) to anon, authenticated;
grant execute on function public.update_character_spell_state(text, uuid, jsonb) to anon, authenticated;
grant execute on function public.delete_character_spell(text, uuid) to anon, authenticated;
grant execute on function public.use_character_spell(text, uuid) to anon, authenticated;
grant execute on function public.use_inventory_enchantment_spell(text, uuid, uuid, uuid) to anon, authenticated;
grant execute on function public.use_spell_book_item(text, uuid, uuid, uuid, int, boolean) to anon, authenticated;


-- ============================================================
-- ============================================================

-- Item catalog foundation.

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
  item_type text not null default 'misc',
  rarity public.item_rarity not null default 'Common',
  generator_biomes text[] not null default array['Any']::text[],
  difficulty_min int not null default 1 check (difficulty_min >= 1),
  difficulty_max int not null default 5 check (difficulty_max >= difficulty_min),
  loot_weight numeric not null default 1 check (loot_weight >= 0),
  tower_base_only boolean not null default false,
  is_stackable boolean not null default true,
  min_quantity numeric(12,1) not null default 1 check (min_quantity > 0),
  max_quantity numeric(12,1) not null default 1 check (max_quantity >= min_quantity),
  notes text not null default '',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists loot_items_pool_idx on public.loot_items(pool_id);

create table if not exists public.loot_workbook_settings (
  id text primary key default 'default',
  settings jsonb not null default '{}'::jsonb,
  source jsonb not null default '{}'::jsonb,
  imported_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.loot_pools enable row level security;
alter table public.loot_items enable row level security;
alter table public.loot_workbook_settings enable row level security;

revoke all on public.loot_pools from anon, authenticated;
revoke all on public.loot_items from anon, authenticated;
revoke all on public.loot_workbook_settings from anon, authenticated;

drop trigger if exists loot_pools_touch_updated_at on public.loot_pools;
create trigger loot_pools_touch_updated_at
before update on public.loot_pools
for each row execute function public.touch_updated_at();

drop trigger if exists loot_items_touch_updated_at on public.loot_items;
create trigger loot_items_touch_updated_at
before update on public.loot_items
for each row execute function public.touch_updated_at();

drop trigger if exists loot_workbook_settings_touch_updated_at on public.loot_workbook_settings;
create trigger loot_workbook_settings_touch_updated_at
before update on public.loot_workbook_settings
for each row execute function public.touch_updated_at();

drop function if exists public.roll_loot_pool(text, uuid, int);
drop function if exists public.award_loot_item(text, uuid, uuid, int);
drop function if exists public.roll_loot_generator(text, text, int, text, text);
drop table if exists public.loot_generator_configs;
drop index if exists public.loot_items_generator_filter_idx;

alter table public.loot_items add column if not exists generator_biomes text[] not null default array['Any']::text[];
alter table public.loot_items add column if not exists difficulty_min int not null default 1 check (difficulty_min >= 1);
alter table public.loot_items add column if not exists difficulty_max int not null default 5 check (difficulty_max >= difficulty_min);
alter table public.loot_items add column if not exists loot_weight numeric not null default 1 check (loot_weight >= 0);
alter table public.loot_items add column if not exists tower_base_only boolean not null default false;
alter table public.loot_items add column if not exists is_stackable boolean not null default true;

alter table public.loot_items drop constraint if exists loot_item_type_valid;
alter table public.loot_items drop constraint if exists loot_items_item_type_valid;

do $$
begin
  if exists (
    select 1
    from pg_attribute
    where attrelid = 'public.loot_items'::regclass
      and attname = 'item_type'
      and not attisdropped
      and format_type(atttypid, atttypmod) <> 'text'
  ) then
    alter table public.loot_items
      alter column item_type type text using item_type::text;
  end if;

  if exists (
    select 1
    from pg_attribute
    where attrelid = 'public.loot_items'::regclass
      and attname = 'min_quantity'
      and not attisdropped
      and format_type(atttypid, atttypmod) <> 'numeric(12,1)'
  ) then
    alter table public.loot_items
      alter column min_quantity type numeric(12,1) using min_quantity::numeric;
  end if;

  if exists (
    select 1
    from pg_attribute
    where attrelid = 'public.loot_items'::regclass
      and attname = 'max_quantity'
      and not attisdropped
      and format_type(atttypid, atttypmod) <> 'numeric(12,1)'
  ) then
    alter table public.loot_items
      alter column max_quantity type numeric(12,1) using max_quantity::numeric;
  end if;
end;
$$;

alter table public.loot_items drop constraint if exists loot_items_min_quantity_check;
alter table public.loot_items drop constraint if exists loot_items_max_quantity_check;
alter table public.loot_items add constraint loot_items_min_quantity_check check (min_quantity > 0);
alter table public.loot_items add constraint loot_items_max_quantity_check check (max_quantity >= min_quantity);

update public.loot_items
set item_type = public.normalize_item_type(item_type);

update public.loot_items
set item_name = public.normalize_item_name(item_name),
    item_type = case
      when lower(public.normalize_item_name(item_name)) in ('empty flask', 'arcane nector') then 'potion'
      else public.normalize_item_type(item_type)
    end,
    rarity = case
      when lower(public.normalize_item_name(item_name)) = 'arcane nector' then 'Uncommon'::public.item_rarity
      when lower(public.normalize_item_name(item_name)) = 'empty flask' then 'Common'::public.item_rarity
      when public.potion_strength_from_name(item_name) is not null then public.potion_rarity_for(public.potion_strength_from_name(item_name), public.potion_property_from_name(item_name))
      else rarity
    end
where public.normalize_item_name(item_name) <> item_name
   or lower(public.normalize_item_name(item_name)) in ('empty flask', 'arcane nector')
   or public.potion_strength_from_name(item_name) is not null;

create index if not exists loot_items_workbook_filter_idx on public.loot_items(is_active, difficulty_min, difficulty_max, rarity);

alter table public.loot_items drop column if exists category;
alter table public.loot_items drop column if exists biomes;
alter table public.loot_items drop column if exists min_difficulty;
alter table public.loot_items drop column if exists max_difficulty;
alter table public.loot_items drop column if exists base_weight;
alter table public.loot_items drop column if exists weight;

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


create or replace function public.is_currency_loot_item(p_item public.loot_items)
returns boolean
language sql
stable
as $$
  select exists (
    select 1
    from public.loot_pools p
    where p.id = p_item.pool_id
      and p.pool_key = 'catalog-currency'
  )
  or lower(p_item.item_name) in ('coin', 'callis', 'callor', 'cal')
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
    'category', case when public.is_currency_loot_item(p_item) then 'currency' else p_item.item_type::text end,
    'biomes', to_jsonb(p_item.generator_biomes),
    'minDifficulty', p_item.difficulty_min,
    'maxDifficulty', p_item.difficulty_max,
    'type', case when public.is_currency_loot_item(p_item) then 'currency' else p_item.item_type::text end,
    'rarity', p_item.rarity,
    'minQuantity', p_item.min_quantity,
    'maxQuantity', p_item.max_quantity,
    'weight', p_item.loot_weight,
    'towerBaseOnly', p_item.tower_base_only,
    'stackable', p_item.is_stackable,
    'notes', p_item.notes
  )
$$;


grant execute on function public.loot_pool_record_to_json(public.loot_pools) to anon, authenticated;
grant execute on function public.is_currency_loot_item(public.loot_items) to anon, authenticated;
grant execute on function public.loot_item_record_to_json(public.loot_items) to anon, authenticated;

-- Seed/refresh loot rows from the checked workbook. This is intentionally authoritative: when the Loot Drops workbook changes, catalog items, conversion rules, dragon fragments, and generator odds update together.
do $$
declare
  v_row jsonb;
  v_pool_id uuid;
  v_name text;
  v_type text;
  v_rarity text;
  v_biomes text[];
  v_min_difficulty int;
  v_max_difficulty int;
  v_min_quantity numeric;
  v_max_quantity numeric;
  v_stackable boolean;
  v_convertible boolean;
  v_scale_item text;
  v_scale_quantity numeric;
  v_material text;
  v_dragon_fragment boolean;
  v_can_be_enhanced boolean;
  v_can_be_enchanted boolean;
  v_notes text;
begin
  delete from public.loot_items where true;
  delete from public.loot_pools where true;
  delete from public.material_conversion_recipes where true;

  insert into public.loot_workbook_settings (id, settings, source, imported_at)
  values ('default', $settings${"biomes":["Any","Caves","Goblins","Elven","Volcano","Mountains","Snow","Voidlands"],"difficulties":[1,2,3,4,5],"poolSizes":["Night Encounter","Small Cave","Medium Cave","Large Cave","Dragon Lair","Tower Floor","Base"],"roomTypes":["Normal","Secret Room","Tower Boss Room"],"luckPotionOptions":["None","Lesser","Greater","Greatest"],"baseRollsByPoolSize":{"Night Encounter":5,"Small Cave":10,"Medium Cave":15,"Large Cave":20,"Dragon Lair":50,"Tower Floor":25,"Base":50},"poolMultipliers":{"Large Cave":1.33,"Dragon Lair":5,"Tower Floor":2,"Base":2},"roomMultipliers":{"Secret Room":2,"Tower Boss Room":2},"luckPotionMultipliers":{"None":{"legendary":1,"mythical":1},"Lesser":{"legendary":2,"mythical":2},"Greater":{"legendary":3,"mythical":3},"Greatest":{"legendary":3,"mythical":5}},"rareBoostRarities":["Rare","Epic","Legendary","Mythical"],"sourceFormulas":{}}$settings$::jsonb, jsonb_build_object('sheets', jsonb_build_array('Loot Table', 'Generator', 'Roll Helper', 'Settings'), 'importedRows', 165, 'source', 'RUN_THIS_IN_SUPABASE.sql workbook seed'), now())
  on conflict (id) do update
  set settings = excluded.settings,
      source = excluded.source,
      imported_at = excluded.imported_at;

  for v_row in select * from jsonb_array_elements($loot$[{"name":"Torch","type":"tool","pool":"Tool Catalog","poolKey":"catalog-tool","biomes":["Any"],"minDifficulty":1,"maxDifficulty":3,"rarity":"Common","weight":100.0,"minQuantity":1.0,"maxQuantity":3.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Rope","type":"tool","pool":"Tool Catalog","poolKey":"catalog-tool","biomes":["Any"],"minDifficulty":1,"maxDifficulty":3,"rarity":"Common","weight":90.0,"minQuantity":1.0,"maxQuantity":5.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Waist Pouch","type":"storage","pool":"Storage Catalog","poolKey":"catalog-storage","biomes":["Any"],"minDifficulty":1,"maxDifficulty":2,"rarity":"Common","weight":70.0,"minQuantity":1.0,"maxQuantity":3.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Back Bag","type":"storage","pool":"Storage Catalog","poolKey":"catalog-storage","biomes":["Any"],"minDifficulty":1,"maxDifficulty":3,"rarity":"Common","weight":60.0,"minQuantity":1.0,"maxQuantity":2.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Leather","type":"fabric","pool":"Fabric Catalog","poolKey":"catalog-fabric","biomes":["Any","Goblins"],"minDifficulty":1,"maxDifficulty":5,"rarity":"Common","weight":100.0,"minQuantity":1.0,"maxQuantity":10.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Jewlery","type":"accessory","pool":"Accessory Catalog","poolKey":"catalog-accessory","biomes":["Any","Goblins"],"minDifficulty":1,"maxDifficulty":5,"rarity":"Common","weight":80.0,"minQuantity":1.0,"maxQuantity":3.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Loose Arrows","type":"weapon","pool":"Weapon Catalog","poolKey":"catalog-weapon","biomes":["Any"],"minDifficulty":1,"maxDifficulty":5,"rarity":"Common","weight":80.0,"minQuantity":3.0,"maxQuantity":25.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Cloth","type":"fabric","pool":"Fabric Catalog","poolKey":"catalog-fabric","biomes":["Any"],"minDifficulty":1,"maxDifficulty":2,"rarity":"Common","weight":80.0,"minQuantity":1.0,"maxQuantity":3.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Fine Cloth","type":"fabric","pool":"Fabric Catalog","poolKey":"catalog-fabric","biomes":["Any"],"minDifficulty":3,"maxDifficulty":5,"rarity":"Common","weight":75.0,"minQuantity":1.0,"maxQuantity":5.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Coin","type":"currency","pool":"Currency Catalog","poolKey":"catalog-currency","biomes":["Any"],"minDifficulty":1,"maxDifficulty":2,"rarity":"Common","weight":80.0,"minQuantity":1.0,"maxQuantity":50.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Fishing Rod","type":"tool","pool":"Tool Catalog","poolKey":"catalog-tool","biomes":["Caves"],"minDifficulty":1,"maxDifficulty":5,"rarity":"Common","weight":60.0,"minQuantity":1.0,"maxQuantity":1.0,"towerBaseOnly":false,"stackable":false,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Hunting Trap","type":"tool","pool":"Tool Catalog","poolKey":"catalog-tool","biomes":["Caves"],"minDifficulty":1,"maxDifficulty":5,"rarity":"Common","weight":60.0,"minQuantity":1.0,"maxQuantity":2.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Dried Rations","type":"food","pool":"Food Catalog","poolKey":"catalog-food","biomes":["Caves"],"minDifficulty":1,"maxDifficulty":5,"rarity":"Common","weight":60.0,"minQuantity":1.0,"maxQuantity":3.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Tattered Cloak","type":"fabric","pool":"Fabric Catalog","poolKey":"catalog-fabric","biomes":["Any"],"minDifficulty":1,"maxDifficulty":5,"rarity":"Common","weight":60.0,"minQuantity":1.0,"maxQuantity":1.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Leather Belt","type":"misc","pool":"Misc Catalog","poolKey":"catalog-misc","biomes":["Caves"],"minDifficulty":1,"maxDifficulty":5,"rarity":"Common","weight":60.0,"minQuantity":1.0,"maxQuantity":2.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Glass Flasks","type":"potion","pool":"Potion Catalog","poolKey":"catalog-potion","biomes":["Any"],"minDifficulty":1,"maxDifficulty":5,"rarity":"Common","weight":60.0,"minQuantity":1.0,"maxQuantity":5.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Small Net","type":"tool","pool":"Tool Catalog","poolKey":"catalog-tool","biomes":["Caves"],"minDifficulty":1,"maxDifficulty":3,"rarity":"Common","weight":60.0,"minQuantity":1.0,"maxQuantity":3.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Looks like a good walking stick","type":"misc","pool":"Misc Catalog","poolKey":"catalog-misc","biomes":["Caves"],"minDifficulty":1,"maxDifficulty":3,"rarity":"Common","weight":60.0,"minQuantity":1.0,"maxQuantity":50.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Iron Scale","type":"ore","pool":"Ore Catalog","poolKey":"catalog-ore","biomes":["Any"],"minDifficulty":1,"maxDifficulty":4,"rarity":"Uncommon","weight":75.0,"minQuantity":1.0,"maxQuantity":5.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"Iron Scale","convertScaleNumber":1,"material":"Iron","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Iron Sword","type":"weapon","pool":"Weapon Catalog","poolKey":"catalog-weapon","biomes":["Any"],"minDifficulty":1,"maxDifficulty":4,"rarity":"Uncommon","weight":0,"minQuantity":1.0,"maxQuantity":2.0,"towerBaseOnly":false,"stackable":false,"convertible":true,"convertScaleItem":"Iron Scale","convertScaleNumber":1.0,"material":"Iron","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Iron Armor","type":"armor","pool":"Armor Catalog","poolKey":"catalog-armor","biomes":["Any"],"minDifficulty":1,"maxDifficulty":4,"rarity":"Uncommon","weight":0,"minQuantity":1.0,"maxQuantity":1.0,"towerBaseOnly":false,"stackable":false,"convertible":true,"convertScaleItem":"Iron Scale","convertScaleNumber":3.0,"material":"Iron","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Callis","type":"currency","pool":"Currency Catalog","poolKey":"catalog-currency","biomes":["Any"],"minDifficulty":2,"maxDifficulty":4,"rarity":"Uncommon","weight":60.0,"minQuantity":1.0,"maxQuantity":50.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Longbow","type":"weapon","pool":"Weapon Catalog","poolKey":"catalog-weapon","biomes":["Any"],"minDifficulty":1,"maxDifficulty":3,"rarity":"Uncommon","weight":50.0,"minQuantity":1.0,"maxQuantity":3.0,"towerBaseOnly":false,"stackable":false,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Fur Skin","type":"fabric","pool":"Fabric Catalog","poolKey":"catalog-fabric","biomes":["Any","Goblins"],"minDifficulty":1,"maxDifficulty":5,"rarity":"Uncommon","weight":60.0,"minQuantity":1.0,"maxQuantity":5.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Light Duffle","type":"storage","pool":"Storage Catalog","poolKey":"catalog-storage","biomes":["Any"],"minDifficulty":2,"maxDifficulty":4,"rarity":"Uncommon","weight":50.0,"minQuantity":1.0,"maxQuantity":2.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Steel Shovel","type":"tool","pool":"Tool Catalog","poolKey":"catalog-tool","biomes":["Any"],"minDifficulty":1,"maxDifficulty":3,"rarity":"Uncommon","weight":50.0,"minQuantity":1.0,"maxQuantity":2.0,"towerBaseOnly":false,"stackable":false,"convertible":true,"convertScaleItem":"Steel Scale","convertScaleNumber":1.0,"material":"Steel","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Steel Pickaxe","type":"tool","pool":"Tool Catalog","poolKey":"catalog-tool","biomes":["Any"],"minDifficulty":1,"maxDifficulty":3,"rarity":"Uncommon","weight":50.0,"minQuantity":1.0,"maxQuantity":2.0,"towerBaseOnly":false,"stackable":false,"convertible":true,"convertScaleItem":"Steel Scale","convertScaleNumber":1.0,"material":"Steel","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Steel Sword","type":"weapon","pool":"Weapon Catalog","poolKey":"catalog-weapon","biomes":["Any"],"minDifficulty":1,"maxDifficulty":3,"rarity":"Uncommon","weight":50.0,"minQuantity":1.0,"maxQuantity":2.0,"towerBaseOnly":false,"stackable":false,"convertible":true,"convertScaleItem":"Steel Scale","convertScaleNumber":1.0,"material":"Steel","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Steel Axe","type":"tool","pool":"Tool Catalog","poolKey":"catalog-tool","biomes":["Any"],"minDifficulty":1,"maxDifficulty":3,"rarity":"Uncommon","weight":50.0,"minQuantity":1.0,"maxQuantity":2.0,"towerBaseOnly":false,"stackable":false,"convertible":true,"convertScaleItem":"Steel Scale","convertScaleNumber":1.0,"material":"Steel","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Spyglass","type":"tool","pool":"Tool Catalog","poolKey":"catalog-tool","biomes":["Caves"],"minDifficulty":1,"maxDifficulty":5,"rarity":"Uncommon","weight":50.0,"minQuantity":1.0,"maxQuantity":1.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Smoke Bomb","type":"tool","pool":"Tool Catalog","poolKey":"catalog-tool","biomes":["Caves"],"minDifficulty":1,"maxDifficulty":5,"rarity":"Uncommon","weight":50.0,"minQuantity":1.0,"maxQuantity":1.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Steel ring","type":"accessory","pool":"Accessory Catalog","poolKey":"catalog-accessory","biomes":["Caves"],"minDifficulty":1,"maxDifficulty":5,"rarity":"Uncommon","weight":50.0,"minQuantity":1.0,"maxQuantity":1.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"Steel Scale","convertScaleNumber":1,"material":"Steel","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Large Net","type":"tool","pool":"Tool Catalog","poolKey":"catalog-tool","biomes":["Caves"],"minDifficulty":1,"maxDifficulty":5,"rarity":"Uncommon","weight":50.0,"minQuantity":1.0,"maxQuantity":2.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"An actual walking stick","type":"misc","pool":"Misc Catalog","poolKey":"catalog-misc","biomes":["Caves"],"minDifficulty":1,"maxDifficulty":5,"rarity":"Uncommon","weight":50.0,"minQuantity":1.0,"maxQuantity":2.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Steel Battleaxe","type":"weapon","pool":"Weapon Catalog","poolKey":"catalog-weapon","biomes":["Any"],"minDifficulty":1,"maxDifficulty":3,"rarity":"Uncommon","weight":55.0,"minQuantity":1.0,"maxQuantity":1.0,"towerBaseOnly":false,"stackable":false,"convertible":true,"convertScaleItem":"Steel Scale","convertScaleNumber":2.0,"material":"Steel","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Steel Mace","type":"weapon","pool":"Weapon Catalog","poolKey":"catalog-weapon","biomes":["Any"],"minDifficulty":1,"maxDifficulty":3,"rarity":"Uncommon","weight":55.0,"minQuantity":1.0,"maxQuantity":1.0,"towerBaseOnly":false,"stackable":false,"convertible":true,"convertScaleItem":"Steel Scale","convertScaleNumber":2.0,"material":"Steel","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Arcane Nector","type":"potion","pool":"Potion Catalog","poolKey":"catalog-potion","biomes":["Any"],"minDifficulty":1,"maxDifficulty":5,"rarity":"Uncommon","weight":50.0,"minQuantity":1.0,"maxQuantity":10.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Lesser Healing Potion","type":"potion","pool":"Potion Catalog","poolKey":"catalog-potion","biomes":["Any"],"minDifficulty":1,"maxDifficulty":3,"rarity":"Uncommon","weight":45.0,"minQuantity":1.0,"maxQuantity":5.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Lesser Swiftness Potion","type":"potion","pool":"Potion Catalog","poolKey":"catalog-potion","biomes":["Any"],"minDifficulty":1,"maxDifficulty":3,"rarity":"Uncommon","weight":36.0,"minQuantity":1.0,"maxQuantity":5.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Lesser Agility Potion","type":"potion","pool":"Potion Catalog","poolKey":"catalog-potion","biomes":["Any"],"minDifficulty":1,"maxDifficulty":3,"rarity":"Uncommon","weight":36.0,"minQuantity":1.0,"maxQuantity":5.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Lesser Strength Potion","type":"potion","pool":"Potion Catalog","poolKey":"catalog-potion","biomes":["Any"],"minDifficulty":1,"maxDifficulty":3,"rarity":"Uncommon","weight":36.0,"minQuantity":1.0,"maxQuantity":5.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Lesser Sorcery Potion","type":"potion","pool":"Potion Catalog","poolKey":"catalog-potion","biomes":["Any"],"minDifficulty":1,"maxDifficulty":3,"rarity":"Uncommon","weight":36.0,"minQuantity":1.0,"maxQuantity":5.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Lesser Mana Potion","type":"potion","pool":"Potion Catalog","poolKey":"catalog-potion","biomes":["Any"],"minDifficulty":1,"maxDifficulty":3,"rarity":"Uncommon","weight":36.0,"minQuantity":1.0,"maxQuantity":5.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Lesser Antidote Potion","type":"potion","pool":"Potion Catalog","poolKey":"catalog-potion","biomes":["Any"],"minDifficulty":1,"maxDifficulty":3,"rarity":"Uncommon","weight":36.0,"minQuantity":1.0,"maxQuantity":5.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Lesser Warming Potion","type":"potion","pool":"Potion Catalog","poolKey":"catalog-potion","biomes":["Any"],"minDifficulty":1,"maxDifficulty":3,"rarity":"Uncommon","weight":36.0,"minQuantity":1.0,"maxQuantity":5.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Lesser Cooling Potion","type":"potion","pool":"Potion Catalog","poolKey":"catalog-potion","biomes":["Any"],"minDifficulty":1,"maxDifficulty":3,"rarity":"Uncommon","weight":36.0,"minQuantity":1.0,"maxQuantity":5.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Lesser Night-Eye Potion","type":"potion","pool":"Potion Catalog","poolKey":"catalog-potion","biomes":["Any"],"minDifficulty":1,"maxDifficulty":3,"rarity":"Uncommon","weight":36.0,"minQuantity":1.0,"maxQuantity":5.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Lesser Thickskin Potion","type":"potion","pool":"Potion Catalog","poolKey":"catalog-potion","biomes":["Any"],"minDifficulty":1,"maxDifficulty":3,"rarity":"Uncommon","weight":36.0,"minQuantity":1.0,"maxQuantity":5.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Lesser Clear-Mind Potion","type":"potion","pool":"Potion Catalog","poolKey":"catalog-potion","biomes":["Any"],"minDifficulty":1,"maxDifficulty":3,"rarity":"Uncommon","weight":36.0,"minQuantity":1.0,"maxQuantity":5.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Lesser Wake-Up Potion","type":"potion","pool":"Potion Catalog","poolKey":"catalog-potion","biomes":["Any"],"minDifficulty":1,"maxDifficulty":3,"rarity":"Uncommon","weight":30.0,"minQuantity":1.0,"maxQuantity":5.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Lesser Clotting Potion","type":"potion","pool":"Potion Catalog","poolKey":"catalog-potion","biomes":["Any"],"minDifficulty":1,"maxDifficulty":3,"rarity":"Uncommon","weight":36.0,"minQuantity":1.0,"maxQuantity":5.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Callor","type":"currency","pool":"Currency Catalog","poolKey":"catalog-currency","biomes":["Any"],"minDifficulty":3,"maxDifficulty":5,"rarity":"Rare","weight":35.0,"minQuantity":1.0,"maxQuantity":50.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Horse","type":"pet","pool":"Pet Catalog","poolKey":"catalog-pet","biomes":["Any"],"minDifficulty":1,"maxDifficulty":3,"rarity":"Rare","weight":35.0,"minQuantity":1.0,"maxQuantity":5.0,"towerBaseOnly":true,"stackable":false,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"War Horse","type":"pet","pool":"Pet Catalog","poolKey":"catalog-pet","biomes":["Any"],"minDifficulty":3,"maxDifficulty":5,"rarity":"Rare","weight":35.0,"minQuantity":1.0,"maxQuantity":5.0,"towerBaseOnly":true,"stackable":false,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Quartz","type":"ore","pool":"Ore Catalog","poolKey":"catalog-ore","biomes":["Any","Goblins"],"minDifficulty":1,"maxDifficulty":5,"rarity":"Rare","weight":40.0,"minQuantity":1.0,"maxQuantity":5.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Heavy Duffle","type":"storage","pool":"Storage Catalog","poolKey":"catalog-storage","biomes":["Any"],"minDifficulty":2,"maxDifficulty":5,"rarity":"Rare","weight":35.0,"minQuantity":1.0,"maxQuantity":2.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Steel Shield","type":"shield","pool":"Shield Catalog","poolKey":"catalog-shield","biomes":["Any"],"minDifficulty":3,"maxDifficulty":5,"rarity":"Rare","weight":30.0,"minQuantity":1.0,"maxQuantity":2.0,"towerBaseOnly":false,"stackable":false,"convertible":true,"convertScaleItem":"Steel Scale","convertScaleNumber":1.0,"material":"Steel","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Mythril Pickaxe","type":"tool","pool":"Tool Catalog","poolKey":"catalog-tool","biomes":["Any"],"minDifficulty":2,"maxDifficulty":4,"rarity":"Rare","weight":35.0,"minQuantity":1.0,"maxQuantity":2.0,"towerBaseOnly":false,"stackable":false,"convertible":true,"convertScaleItem":"Mythril Scale","convertScaleNumber":1.0,"material":"Mythril","canForgeDragonscaleScale":false,"canBeEnhanced":true,"canBeEnchanted":false,"notes":""},{"name":"Mythril Sword","type":"weapon","pool":"Weapon Catalog","poolKey":"catalog-weapon","biomes":["Any"],"minDifficulty":2,"maxDifficulty":4,"rarity":"Rare","weight":35.0,"minQuantity":1.0,"maxQuantity":2.0,"towerBaseOnly":false,"stackable":false,"convertible":true,"convertScaleItem":"Mythril Scale","convertScaleNumber":1.0,"material":"Mythril","canForgeDragonscaleScale":false,"canBeEnhanced":true,"canBeEnchanted":true,"notes":""},{"name":"Mythril Dagger","type":"weapon","pool":"Weapon Catalog","poolKey":"catalog-weapon","biomes":["Any"],"minDifficulty":2,"maxDifficulty":4,"rarity":"Rare","weight":35.0,"minQuantity":1.0,"maxQuantity":2.0,"towerBaseOnly":false,"stackable":false,"convertible":true,"convertScaleItem":"Mythril Scale","convertScaleNumber":0.5,"material":"Mythril","canForgeDragonscaleScale":false,"canBeEnhanced":true,"canBeEnchanted":true,"notes":""},{"name":"Mythril Axe","type":"tool","pool":"Tool Catalog","poolKey":"catalog-tool","biomes":["Any"],"minDifficulty":2,"maxDifficulty":4,"rarity":"Rare","weight":35.0,"minQuantity":1.0,"maxQuantity":2.0,"towerBaseOnly":false,"stackable":false,"convertible":true,"convertScaleItem":"Mythril Scale","convertScaleNumber":1.0,"material":"Mythril","canForgeDragonscaleScale":false,"canBeEnhanced":true,"canBeEnchanted":true,"notes":""},{"name":"Mythril Battleaxe","type":"weapon","pool":"Weapon Catalog","poolKey":"catalog-weapon","biomes":["Any"],"minDifficulty":2,"maxDifficulty":4,"rarity":"Rare","weight":30.0,"minQuantity":1.0,"maxQuantity":1.0,"towerBaseOnly":false,"stackable":false,"convertible":true,"convertScaleItem":"Mythril Scale","convertScaleNumber":2.0,"material":"Mythril","canForgeDragonscaleScale":false,"canBeEnhanced":true,"canBeEnchanted":true,"notes":""},{"name":"Mythril Mace","type":"weapon","pool":"Weapon Catalog","poolKey":"catalog-weapon","biomes":["Any"],"minDifficulty":2,"maxDifficulty":4,"rarity":"Rare","weight":30.0,"minQuantity":1.0,"maxQuantity":1.0,"towerBaseOnly":false,"stackable":false,"convertible":true,"convertScaleItem":"Mythril Scale","convertScaleNumber":2.0,"material":"Mythril","canForgeDragonscaleScale":false,"canBeEnhanced":true,"canBeEnchanted":true,"notes":""},{"name":"Greater Wake-Up Potion","type":"potion","pool":"Potion Catalog","poolKey":"catalog-potion","biomes":["Any"],"minDifficulty":1,"maxDifficulty":5,"rarity":"Rare","weight":18.0,"minQuantity":1.0,"maxQuantity":4.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Greater Clotting Potion","type":"potion","pool":"Potion Catalog","poolKey":"catalog-potion","biomes":["Any"],"minDifficulty":1,"maxDifficulty":5,"rarity":"Rare","weight":22.0,"minQuantity":1.0,"maxQuantity":4.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Greater Clear-Mind Potion","type":"potion","pool":"Potion Catalog","poolKey":"catalog-potion","biomes":["Any"],"minDifficulty":1,"maxDifficulty":5,"rarity":"Rare","weight":22.0,"minQuantity":1.0,"maxQuantity":4.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Greater Thickskin Potion","type":"potion","pool":"Potion Catalog","poolKey":"catalog-potion","biomes":["Any"],"minDifficulty":1,"maxDifficulty":5,"rarity":"Rare","weight":22.0,"minQuantity":1.0,"maxQuantity":4.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Greater Night-Eye Potion","type":"potion","pool":"Potion Catalog","poolKey":"catalog-potion","biomes":["Any"],"minDifficulty":1,"maxDifficulty":5,"rarity":"Rare","weight":22.0,"minQuantity":1.0,"maxQuantity":4.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Greater Cooling Potion","type":"potion","pool":"Potion Catalog","poolKey":"catalog-potion","biomes":["Any"],"minDifficulty":1,"maxDifficulty":5,"rarity":"Rare","weight":22.0,"minQuantity":1.0,"maxQuantity":4.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Greater Warming Potion","type":"potion","pool":"Potion Catalog","poolKey":"catalog-potion","biomes":["Any"],"minDifficulty":1,"maxDifficulty":5,"rarity":"Rare","weight":22.0,"minQuantity":1.0,"maxQuantity":4.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Greater Antidote Potion","type":"potion","pool":"Potion Catalog","poolKey":"catalog-potion","biomes":["Any"],"minDifficulty":1,"maxDifficulty":5,"rarity":"Rare","weight":22.0,"minQuantity":1.0,"maxQuantity":4.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Greater Mana Potion","type":"potion","pool":"Potion Catalog","poolKey":"catalog-potion","biomes":["Any"],"minDifficulty":1,"maxDifficulty":5,"rarity":"Rare","weight":22.0,"minQuantity":1.0,"maxQuantity":4.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Greater Sorcery Potion","type":"potion","pool":"Potion Catalog","poolKey":"catalog-potion","biomes":["Any"],"minDifficulty":1,"maxDifficulty":5,"rarity":"Rare","weight":22.0,"minQuantity":1.0,"maxQuantity":4.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Greater Strength Potion","type":"potion","pool":"Potion Catalog","poolKey":"catalog-potion","biomes":["Any"],"minDifficulty":1,"maxDifficulty":5,"rarity":"Rare","weight":22.0,"minQuantity":1.0,"maxQuantity":4.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Greater Agility Potion","type":"potion","pool":"Potion Catalog","poolKey":"catalog-potion","biomes":["Any"],"minDifficulty":1,"maxDifficulty":5,"rarity":"Rare","weight":22.0,"minQuantity":1.0,"maxQuantity":4.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Greater Swiftness Potion","type":"potion","pool":"Potion Catalog","poolKey":"catalog-potion","biomes":["Any"],"minDifficulty":1,"maxDifficulty":5,"rarity":"Rare","weight":22.0,"minQuantity":1.0,"maxQuantity":4.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Greater Healing Potion","type":"potion","pool":"Potion Catalog","poolKey":"catalog-potion","biomes":["Any"],"minDifficulty":1,"maxDifficulty":5,"rarity":"Rare","weight":28.0,"minQuantity":1.0,"maxQuantity":4.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Mythril Shield","type":"shield","pool":"Shield Catalog","poolKey":"catalog-shield","biomes":["Any"],"minDifficulty":3,"maxDifficulty":5,"rarity":"Rare","weight":40.0,"minQuantity":1.0,"maxQuantity":1.0,"towerBaseOnly":false,"stackable":false,"convertible":true,"convertScaleItem":"Mythril Scale","convertScaleNumber":1.0,"material":"Mythril","canForgeDragonscaleScale":false,"canBeEnhanced":true,"canBeEnchanted":true,"notes":""},{"name":"Mythril Armor","type":"armor","pool":"Armor Catalog","poolKey":"catalog-armor","biomes":["Any"],"minDifficulty":3,"maxDifficulty":5,"rarity":"Rare","weight":0,"minQuantity":1,"maxQuantity":1,"towerBaseOnly":false,"stackable":false,"convertible":true,"convertScaleItem":"Mythril Scale","convertScaleNumber":3.0,"material":"Mythril","canForgeDragonscaleScale":false,"canBeEnhanced":true,"canBeEnchanted":false,"notes":""},{"name":"Vaylium Armor","type":"armor","pool":"Armor Catalog","poolKey":"catalog-armor","biomes":["Any"],"minDifficulty":3,"maxDifficulty":5,"rarity":"Epic","weight":0,"minQuantity":1,"maxQuantity":1,"towerBaseOnly":false,"stackable":false,"convertible":true,"convertScaleItem":"Vaylium Scale","convertScaleNumber":3.0,"material":"Vaylium","canForgeDragonscaleScale":false,"canBeEnhanced":true,"canBeEnchanted":false,"notes":""},{"name":"Vaylium Shield","type":"shield","pool":"Shield Catalog","poolKey":"catalog-shield","biomes":["Any"],"minDifficulty":4,"maxDifficulty":5,"rarity":"Epic","weight":25.0,"minQuantity":1.0,"maxQuantity":1.0,"towerBaseOnly":false,"stackable":false,"convertible":true,"convertScaleItem":"Vaylium Scale","convertScaleNumber":1.0,"material":"Vaylium","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Vaylium Battleaxe","type":"weapon","pool":"Weapon Catalog","poolKey":"catalog-weapon","biomes":["Any"],"minDifficulty":3,"maxDifficulty":5,"rarity":"Epic","weight":15.0,"minQuantity":1.0,"maxQuantity":1.0,"towerBaseOnly":false,"stackable":false,"convertible":true,"convertScaleItem":"Vaylium Scale","convertScaleNumber":2.0,"material":"Vaylium","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Vaylium Mace","type":"weapon","pool":"Weapon Catalog","poolKey":"catalog-weapon","biomes":["Any"],"minDifficulty":3,"maxDifficulty":5,"rarity":"Epic","weight":15.0,"minQuantity":1.0,"maxQuantity":1.0,"towerBaseOnly":false,"stackable":false,"convertible":true,"convertScaleItem":"Vaylium Scale","convertScaleNumber":2.0,"material":"Vaylium","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Vaylium Pickaxe","type":"tool","pool":"Tool Catalog","poolKey":"catalog-tool","biomes":["Any"],"minDifficulty":3,"maxDifficulty":5,"rarity":"Epic","weight":20.0,"minQuantity":1.0,"maxQuantity":2.0,"towerBaseOnly":false,"stackable":false,"convertible":true,"convertScaleItem":"Vaylium Scale","convertScaleNumber":1.0,"material":"Vaylium","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Vaylium Sword","type":"weapon","pool":"Weapon Catalog","poolKey":"catalog-weapon","biomes":["Any"],"minDifficulty":3,"maxDifficulty":5,"rarity":"Epic","weight":20.0,"minQuantity":1.0,"maxQuantity":2.0,"towerBaseOnly":false,"stackable":false,"convertible":true,"convertScaleItem":"Vaylium Scale","convertScaleNumber":1.0,"material":"Vaylium","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Vaylium Dagger","type":"weapon","pool":"Weapon Catalog","poolKey":"catalog-weapon","biomes":["Any"],"minDifficulty":3,"maxDifficulty":5,"rarity":"Epic","weight":20.0,"minQuantity":1.0,"maxQuantity":2.0,"towerBaseOnly":false,"stackable":false,"convertible":true,"convertScaleItem":"Vaylium Scale","convertScaleNumber":0.5,"material":"Vaylium","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Vaylium Axe","type":"tool","pool":"Tool Catalog","poolKey":"catalog-tool","biomes":["Any"],"minDifficulty":3,"maxDifficulty":5,"rarity":"Epic","weight":20.0,"minQuantity":1.0,"maxQuantity":2.0,"towerBaseOnly":false,"stackable":false,"convertible":true,"convertScaleItem":"Vaylium Scale","convertScaleNumber":1.0,"material":"Vaylium","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Magic Bow","type":"weapon","pool":"Weapon Catalog","poolKey":"catalog-weapon","biomes":["Any"],"minDifficulty":3,"maxDifficulty":5,"rarity":"Epic","weight":25.0,"minQuantity":1.0,"maxQuantity":2.0,"towerBaseOnly":false,"stackable":false,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Fire Scroll","type":"quest","pool":"Quest Catalog","poolKey":"catalog-quest","biomes":["Any"],"minDifficulty":3,"maxDifficulty":5,"rarity":"Epic","weight":20.0,"minQuantity":1.0,"maxQuantity":2.0,"towerBaseOnly":true,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Frost Scroll","type":"quest","pool":"Quest Catalog","poolKey":"catalog-quest","biomes":["Any"],"minDifficulty":3,"maxDifficulty":5,"rarity":"Epic","weight":20.0,"minQuantity":1.0,"maxQuantity":2.0,"towerBaseOnly":true,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Lightning Scroll","type":"quest","pool":"Quest Catalog","poolKey":"catalog-quest","biomes":["Any"],"minDifficulty":3,"maxDifficulty":5,"rarity":"Epic","weight":20.0,"minQuantity":1.0,"maxQuantity":2.0,"towerBaseOnly":true,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Earth Scroll","type":"quest","pool":"Quest Catalog","poolKey":"catalog-quest","biomes":["Any"],"minDifficulty":3,"maxDifficulty":5,"rarity":"Epic","weight":20.0,"minQuantity":1.0,"maxQuantity":2.0,"towerBaseOnly":true,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Wind Scroll","type":"quest","pool":"Quest Catalog","poolKey":"catalog-quest","biomes":["Any"],"minDifficulty":3,"maxDifficulty":5,"rarity":"Epic","weight":20.0,"minQuantity":1.0,"maxQuantity":2.0,"towerBaseOnly":true,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Energy Scroll","type":"quest","pool":"Quest Catalog","poolKey":"catalog-quest","biomes":["Any"],"minDifficulty":3,"maxDifficulty":5,"rarity":"Epic","weight":20.0,"minQuantity":1.0,"maxQuantity":2.0,"towerBaseOnly":true,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Healing Scroll","type":"quest","pool":"Quest Catalog","poolKey":"catalog-quest","biomes":["Any"],"minDifficulty":3,"maxDifficulty":5,"rarity":"Epic","weight":20.0,"minQuantity":1.0,"maxQuantity":2.0,"towerBaseOnly":true,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Enhancment Scroll","type":"quest","pool":"Quest Catalog","poolKey":"catalog-quest","biomes":["Any"],"minDifficulty":3,"maxDifficulty":5,"rarity":"Epic","weight":20.0,"minQuantity":1.0,"maxQuantity":2.0,"towerBaseOnly":true,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Utility Scroll","type":"quest","pool":"Quest Catalog","poolKey":"catalog-quest","biomes":["Any"],"minDifficulty":3,"maxDifficulty":5,"rarity":"Epic","weight":25.0,"minQuantity":1.0,"maxQuantity":1.0,"towerBaseOnly":true,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Mystery Tome","type":"book","pool":"Book Catalog","poolKey":"catalog-book","biomes":["Any"],"minDifficulty":1,"maxDifficulty":5,"rarity":"Epic","weight":20.0,"minQuantity":1.0,"maxQuantity":1.0,"towerBaseOnly":true,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"World Map Fragment","type":"quest","pool":"Quest Catalog","poolKey":"catalog-quest","biomes":["Any"],"minDifficulty":1,"maxDifficulty":5,"rarity":"Epic","weight":20.0,"minQuantity":1.0,"maxQuantity":1.0,"towerBaseOnly":true,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"World History","type":"quest","pool":"Quest Catalog","poolKey":"catalog-quest","biomes":["Any"],"minDifficulty":1,"maxDifficulty":5,"rarity":"Epic","weight":20.0,"minQuantity":1.0,"maxQuantity":1.0,"towerBaseOnly":true,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Emerald","type":"ore","pool":"Ore Catalog","poolKey":"catalog-ore","biomes":["Goblins","Caves"],"minDifficulty":2,"maxDifficulty":5,"rarity":"Epic","weight":30.0,"minQuantity":1.0,"maxQuantity":4.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Ruby","type":"ore","pool":"Ore Catalog","poolKey":"catalog-ore","biomes":["Goblins","Caves"],"minDifficulty":3,"maxDifficulty":5,"rarity":"Epic","weight":20.0,"minQuantity":1.0,"maxQuantity":3.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Ember Rune","type":"rune","pool":"Rune Catalog","poolKey":"catalog-rune","biomes":["Any"],"minDifficulty":1,"maxDifficulty":5,"rarity":"Epic","weight":15.0,"minQuantity":1.0,"maxQuantity":3.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Frost Rune","type":"rune","pool":"Rune Catalog","poolKey":"catalog-rune","biomes":["Any"],"minDifficulty":1,"maxDifficulty":5,"rarity":"Epic","weight":15.0,"minQuantity":1.0,"maxQuantity":3.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Lightning Rune","type":"rune","pool":"Rune Catalog","poolKey":"catalog-rune","biomes":["Any"],"minDifficulty":1,"maxDifficulty":5,"rarity":"Epic","weight":15.0,"minQuantity":1.0,"maxQuantity":3.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Earth Rune","type":"rune","pool":"Rune Catalog","poolKey":"catalog-rune","biomes":["Any"],"minDifficulty":1,"maxDifficulty":5,"rarity":"Epic","weight":15.0,"minQuantity":1.0,"maxQuantity":3.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Wind Rune","type":"rune","pool":"Rune Catalog","poolKey":"catalog-rune","biomes":["Any"],"minDifficulty":1,"maxDifficulty":5,"rarity":"Epic","weight":15.0,"minQuantity":1.0,"maxQuantity":3.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Mountain Rune","type":"rune","pool":"Rune Catalog","poolKey":"catalog-rune","biomes":["Any"],"minDifficulty":1,"maxDifficulty":5,"rarity":"Epic","weight":11.0,"minQuantity":1.0,"maxQuantity":3.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Random Accessory","type":"accessory","pool":"Accessory Catalog","poolKey":"catalog-accessory","biomes":["Any"],"minDifficulty":1,"maxDifficulty":5,"rarity":"Epic","weight":30.0,"minQuantity":1.0,"maxQuantity":3.0,"towerBaseOnly":false,"stackable":false,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Dragonscale Sword","type":"weapon","pool":"Weapon Catalog","poolKey":"catalog-weapon","biomes":["Any"],"minDifficulty":4,"maxDifficulty":5,"rarity":"Legendary","weight":5.0,"minQuantity":1.0,"maxQuantity":2.0,"towerBaseOnly":false,"stackable":false,"convertible":true,"convertScaleItem":"Dragonscale Scale","convertScaleNumber":1.0,"material":"Dragonscale","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Dragonscale Dagger","type":"weapon","pool":"Weapon Catalog","poolKey":"catalog-weapon","biomes":["Any"],"minDifficulty":4,"maxDifficulty":5,"rarity":"Legendary","weight":5.0,"minQuantity":1.0,"maxQuantity":2.0,"towerBaseOnly":false,"stackable":false,"convertible":true,"convertScaleItem":"Dragonscale Scale","convertScaleNumber":0.5,"material":"Dragonscale","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Dragonscale Pickaxe","type":"tool","pool":"Tool Catalog","poolKey":"catalog-tool","biomes":["Any"],"minDifficulty":4,"maxDifficulty":5,"rarity":"Legendary","weight":5.0,"minQuantity":1.0,"maxQuantity":2.0,"towerBaseOnly":false,"stackable":false,"convertible":true,"convertScaleItem":"Dragonscale Scale","convertScaleNumber":1.0,"material":"Dragonscale","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Dragonscale Axe","type":"tool","pool":"Tool Catalog","poolKey":"catalog-tool","biomes":["Any"],"minDifficulty":4,"maxDifficulty":5,"rarity":"Legendary","weight":5.0,"minQuantity":1.0,"maxQuantity":2.0,"towerBaseOnly":false,"stackable":false,"convertible":true,"convertScaleItem":"Dragonscale Scale","convertScaleNumber":1.0,"material":"Dragonscale","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Dragonscale Shield","type":"shield","pool":"Shield Catalog","poolKey":"catalog-shield","biomes":["Any"],"minDifficulty":5,"maxDifficulty":5,"rarity":"Legendary","weight":3.0,"minQuantity":1.0,"maxQuantity":1.0,"towerBaseOnly":false,"stackable":false,"convertible":true,"convertScaleItem":"Dragonscale Scale","convertScaleNumber":1.0,"material":"Dragonscale","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Dragonscale Battleaxe","type":"weapon","pool":"Weapon Catalog","poolKey":"catalog-weapon","biomes":["Any"],"minDifficulty":4,"maxDifficulty":5,"rarity":"Legendary","weight":5.0,"minQuantity":1.0,"maxQuantity":2.0,"towerBaseOnly":false,"stackable":false,"convertible":true,"convertScaleItem":"Dragonscale Scale","convertScaleNumber":2.0,"material":"Dragonscale","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Dragonscale Mace","type":"weapon","pool":"Weapon Catalog","poolKey":"catalog-weapon","biomes":["Any"],"minDifficulty":4,"maxDifficulty":5,"rarity":"Legendary","weight":5.0,"minQuantity":1.0,"maxQuantity":2.0,"towerBaseOnly":false,"stackable":false,"convertible":true,"convertScaleItem":"Dragonscale Scale","convertScaleNumber":2.0,"material":"Dragonscale","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Mythril Scale","type":"ore","pool":"Ore Catalog","poolKey":"catalog-ore","biomes":["Any"],"minDifficulty":2,"maxDifficulty":4,"rarity":"Legendary","weight":5.0,"minQuantity":1.0,"maxQuantity":3.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"Mythril Scale","convertScaleNumber":1,"material":"Mythril","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Vaylium Scale","type":"ore","pool":"Ore Catalog","poolKey":"catalog-ore","biomes":["Any"],"minDifficulty":3,"maxDifficulty":5,"rarity":"Legendary","weight":5.0,"minQuantity":1.0,"maxQuantity":3.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"Vaylium Scale","convertScaleNumber":1,"material":"Vaylium","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Young Dragons Scales","type":"misc","pool":"Misc Catalog","poolKey":"catalog-misc","biomes":["Any"],"minDifficulty":4,"maxDifficulty":5,"rarity":"Legendary","weight":5.0,"minQuantity":19.0,"maxQuantity":80.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":true,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Ember Dragons Scales","type":"misc","pool":"Misc Catalog","poolKey":"catalog-misc","biomes":["Volcano","Caves"],"minDifficulty":4,"maxDifficulty":5,"rarity":"Legendary","weight":5.0,"minQuantity":19.0,"maxQuantity":80.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":true,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Frost Dragons Scales","type":"misc","pool":"Misc Catalog","poolKey":"catalog-misc","biomes":["Mountains","Snow"],"minDifficulty":4,"maxDifficulty":5,"rarity":"Legendary","weight":5.0,"minQuantity":19.0,"maxQuantity":80.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":true,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Storm Dragons Scales","type":"misc","pool":"Misc Catalog","poolKey":"catalog-misc","biomes":["Caves"],"minDifficulty":4,"maxDifficulty":5,"rarity":"Legendary","weight":5.0,"minQuantity":19.0,"maxQuantity":80.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":true,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Mountian Dragons Scales","type":"misc","pool":"Misc Catalog","poolKey":"catalog-misc","biomes":["Mountains","Caves"],"minDifficulty":4,"maxDifficulty":5,"rarity":"Legendary","weight":5.0,"minQuantity":19.0,"maxQuantity":80.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":true,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Cal","type":"currency","pool":"Currency Catalog","poolKey":"catalog-currency","biomes":["Any"],"minDifficulty":5,"maxDifficulty":5,"rarity":"Legendary","weight":5.0,"minQuantity":1.0,"maxQuantity":50.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Dragonscale Bow","type":"weapon","pool":"Weapon Catalog","poolKey":"catalog-weapon","biomes":["Any"],"minDifficulty":4,"maxDifficulty":5,"rarity":"Legendary","weight":5.0,"minQuantity":1.0,"maxQuantity":1.0,"towerBaseOnly":false,"stackable":false,"convertible":true,"convertScaleItem":"Dragonscale Scale","convertScaleNumber":2,"material":"Dragonscale","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Fire Spell Upgrade","type":"quest","pool":"Quest Catalog","poolKey":"catalog-quest","biomes":["Elven"],"minDifficulty":3,"maxDifficulty":5,"rarity":"Legendary","weight":9.0,"minQuantity":1.0,"maxQuantity":1.0,"towerBaseOnly":true,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Frost Spell Upgrade","type":"quest","pool":"Quest Catalog","poolKey":"catalog-quest","biomes":["Elven"],"minDifficulty":3,"maxDifficulty":5,"rarity":"Legendary","weight":9.0,"minQuantity":1.0,"maxQuantity":1.0,"towerBaseOnly":true,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Lightning Spell Upgrade","type":"quest","pool":"Quest Catalog","poolKey":"catalog-quest","biomes":["Elven"],"minDifficulty":3,"maxDifficulty":5,"rarity":"Legendary","weight":9.0,"minQuantity":1.0,"maxQuantity":1.0,"towerBaseOnly":true,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Earth Spell Upgrade","type":"quest","pool":"Quest Catalog","poolKey":"catalog-quest","biomes":["Elven"],"minDifficulty":3,"maxDifficulty":5,"rarity":"Legendary","weight":9.0,"minQuantity":1.0,"maxQuantity":1.0,"towerBaseOnly":true,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Wind Spell Upgrade","type":"quest","pool":"Quest Catalog","poolKey":"catalog-quest","biomes":["Elven"],"minDifficulty":3,"maxDifficulty":5,"rarity":"Legendary","weight":9.0,"minQuantity":1.0,"maxQuantity":1.0,"towerBaseOnly":true,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Energy Spell Upgrade","type":"quest","pool":"Quest Catalog","poolKey":"catalog-quest","biomes":["Elven"],"minDifficulty":3,"maxDifficulty":5,"rarity":"Legendary","weight":9.0,"minQuantity":1.0,"maxQuantity":1.0,"towerBaseOnly":true,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Healing Spell Upgrade","type":"quest","pool":"Quest Catalog","poolKey":"catalog-quest","biomes":["Elven"],"minDifficulty":3,"maxDifficulty":5,"rarity":"Legendary","weight":9.0,"minQuantity":1.0,"maxQuantity":1.0,"towerBaseOnly":true,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Enhancement Spell Upgrade","type":"quest","pool":"Quest Catalog","poolKey":"catalog-quest","biomes":["Elven"],"minDifficulty":3,"maxDifficulty":5,"rarity":"Legendary","weight":9.0,"minQuantity":1.0,"maxQuantity":1.0,"towerBaseOnly":true,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Utility Spell Upgrade","type":"quest","pool":"Quest Catalog","poolKey":"catalog-quest","biomes":["Elven"],"minDifficulty":3,"maxDifficulty":5,"rarity":"Legendary","weight":9.0,"minQuantity":1.0,"maxQuantity":1.0,"towerBaseOnly":true,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Sapphire","type":"ore","pool":"Ore Catalog","poolKey":"catalog-ore","biomes":["Goblins","Caves"],"minDifficulty":4,"maxDifficulty":5,"rarity":"Legendary","weight":10.0,"minQuantity":1.0,"maxQuantity":2.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Legendary Weapon","type":"weapon","pool":"Weapon Catalog","poolKey":"catalog-weapon","biomes":["Any"],"minDifficulty":1,"maxDifficulty":5,"rarity":"Legendary","weight":10.0,"minQuantity":1.0,"maxQuantity":1.0,"towerBaseOnly":false,"stackable":false,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Greatest Healing Potion","type":"potion","pool":"Potion Catalog","poolKey":"catalog-potion","biomes":["Any"],"minDifficulty":3,"maxDifficulty":5,"rarity":"Legendary","weight":4.0,"minQuantity":1.0,"maxQuantity":3.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Greatest Swiftness Potion","type":"potion","pool":"Potion Catalog","poolKey":"catalog-potion","biomes":["Any"],"minDifficulty":3,"maxDifficulty":5,"rarity":"Legendary","weight":3.0,"minQuantity":1.0,"maxQuantity":3.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Greatest Agility Potion","type":"potion","pool":"Potion Catalog","poolKey":"catalog-potion","biomes":["Any"],"minDifficulty":3,"maxDifficulty":5,"rarity":"Legendary","weight":3.0,"minQuantity":1.0,"maxQuantity":3.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Greatest Strength Potion","type":"potion","pool":"Potion Catalog","poolKey":"catalog-potion","biomes":["Any"],"minDifficulty":3,"maxDifficulty":5,"rarity":"Legendary","weight":3.0,"minQuantity":1.0,"maxQuantity":3.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Greatest Sorcery Potion","type":"potion","pool":"Potion Catalog","poolKey":"catalog-potion","biomes":["Any"],"minDifficulty":3,"maxDifficulty":5,"rarity":"Legendary","weight":3.0,"minQuantity":1.0,"maxQuantity":3.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Greatest Mana Potion","type":"potion","pool":"Potion Catalog","poolKey":"catalog-potion","biomes":["Any"],"minDifficulty":3,"maxDifficulty":5,"rarity":"Legendary","weight":3.0,"minQuantity":1.0,"maxQuantity":3.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Greatest Antidote Potion","type":"potion","pool":"Potion Catalog","poolKey":"catalog-potion","biomes":["Any"],"minDifficulty":3,"maxDifficulty":5,"rarity":"Legendary","weight":3.0,"minQuantity":1.0,"maxQuantity":3.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Greatest Warming Potion","type":"potion","pool":"Potion Catalog","poolKey":"catalog-potion","biomes":["Any"],"minDifficulty":3,"maxDifficulty":5,"rarity":"Legendary","weight":3.0,"minQuantity":1.0,"maxQuantity":3.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Greatest Cooling Potion","type":"potion","pool":"Potion Catalog","poolKey":"catalog-potion","biomes":["Any"],"minDifficulty":3,"maxDifficulty":5,"rarity":"Legendary","weight":3.0,"minQuantity":1.0,"maxQuantity":3.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Greatest Night-Eye Potion","type":"potion","pool":"Potion Catalog","poolKey":"catalog-potion","biomes":["Any"],"minDifficulty":3,"maxDifficulty":5,"rarity":"Legendary","weight":3.0,"minQuantity":1.0,"maxQuantity":3.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Greatest Thinkskin Potion","type":"potion","pool":"Potion Catalog","poolKey":"catalog-potion","biomes":["Any"],"minDifficulty":3,"maxDifficulty":5,"rarity":"Legendary","weight":3.0,"minQuantity":1.0,"maxQuantity":3.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Greatest Clear-Mind Potion","type":"potion","pool":"Potion Catalog","poolKey":"catalog-potion","biomes":["Any"],"minDifficulty":3,"maxDifficulty":5,"rarity":"Legendary","weight":3.0,"minQuantity":1.0,"maxQuantity":3.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Greatest Wake-Up Potion","type":"potion","pool":"Potion Catalog","poolKey":"catalog-potion","biomes":["Any"],"minDifficulty":3,"maxDifficulty":5,"rarity":"Legendary","weight":2.0,"minQuantity":1.0,"maxQuantity":3.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Greatest Clotting Potion","type":"potion","pool":"Potion Catalog","poolKey":"catalog-potion","biomes":["Any"],"minDifficulty":3,"maxDifficulty":5,"rarity":"Legendary","weight":3.0,"minQuantity":1.0,"maxQuantity":3.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Bag of Holding","type":"storage","pool":"Storage Catalog","poolKey":"catalog-storage","biomes":["Any"],"minDifficulty":3,"maxDifficulty":5,"rarity":"Mythical","weight":2.0,"minQuantity":1.0,"maxQuantity":1.0,"towerBaseOnly":false,"stackable":false,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Void Rune","type":"rune","pool":"Rune Catalog","poolKey":"catalog-rune","biomes":["Any"],"minDifficulty":1,"maxDifficulty":5,"rarity":"Mythical","weight":2.0,"minQuantity":1.0,"maxQuantity":5.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Elder Dragons Scales","type":"misc","pool":"Misc Catalog","poolKey":"catalog-misc","biomes":["Elven"],"minDifficulty":5,"maxDifficulty":5,"rarity":"Mythical","weight":2.0,"minQuantity":19.0,"maxQuantity":100.0,"towerBaseOnly":true,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":true,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Void Dragon Scales","type":"misc","pool":"Misc Catalog","poolKey":"catalog-misc","biomes":["Voidlands"],"minDifficulty":5,"maxDifficulty":5,"rarity":"Mythical","weight":2.0,"minQuantity":19.0,"maxQuantity":100.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":true,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Father's Belt","type":"weapon","pool":"Weapon Catalog","poolKey":"catalog-weapon","biomes":["Any"],"minDifficulty":1,"maxDifficulty":5,"rarity":"Mythical","weight":2.0,"minQuantity":1.0,"maxQuantity":1.0,"towerBaseOnly":false,"stackable":false,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Blanket","type":"fabric","pool":"Fabric Catalog","poolKey":"catalog-fabric","biomes":["Any"],"minDifficulty":1,"maxDifficulty":5,"rarity":"Common","weight":10.0,"minQuantity":1.0,"maxQuantity":5.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Cooking Pots","type":"tool","pool":"Tool Catalog","poolKey":"catalog-tool","biomes":["Any"],"minDifficulty":1,"maxDifficulty":5,"rarity":"Common","weight":10.0,"minQuantity":1.0,"maxQuantity":5.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Ink and Paper","type":"tool","pool":"Tool Catalog","poolKey":"catalog-tool","biomes":["Any"],"minDifficulty":1,"maxDifficulty":5,"rarity":"Common","weight":10.0,"minQuantity":1.0,"maxQuantity":1.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Lock","type":"tool","pool":"Tool Catalog","poolKey":"catalog-tool","biomes":["Any"],"minDifficulty":1,"maxDifficulty":5,"rarity":"Common","weight":10.0,"minQuantity":1.0,"maxQuantity":1.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Standard Hammer","type":"tool","pool":"Tool Catalog","poolKey":"catalog-tool","biomes":["Any"],"minDifficulty":1,"maxDifficulty":5,"rarity":"Common","weight":10.0,"minQuantity":1.0,"maxQuantity":1.0,"towerBaseOnly":false,"stackable":false,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Standard Axe","type":"tool","pool":"Tool Catalog","poolKey":"catalog-tool","biomes":["Any"],"minDifficulty":1,"maxDifficulty":5,"rarity":"Common","weight":10.0,"minQuantity":1.0,"maxQuantity":1.0,"towerBaseOnly":false,"stackable":false,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Winter Wear","type":"fabric","pool":"Fabric Catalog","poolKey":"catalog-fabric","biomes":["Any"],"minDifficulty":1,"maxDifficulty":5,"rarity":"Uncommon","weight":10.0,"minQuantity":1.0,"maxQuantity":1.0,"towerBaseOnly":false,"stackable":false,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Heat Wear","type":"fabric","pool":"Fabric Catalog","poolKey":"catalog-fabric","biomes":["Any"],"minDifficulty":1,"maxDifficulty":5,"rarity":"Uncommon","weight":10.0,"minQuantity":1.0,"maxQuantity":1.0,"towerBaseOnly":false,"stackable":false,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Rainproof Wear","type":"fabric","pool":"Fabric Catalog","poolKey":"catalog-fabric","biomes":["Any"],"minDifficulty":1,"maxDifficulty":5,"rarity":"Uncommon","weight":5.0,"minQuantity":1.0,"maxQuantity":1.0,"towerBaseOnly":false,"stackable":false,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""},{"name":"Dog","type":"pet","pool":"Pet Catalog","poolKey":"catalog-pet","biomes":["Any"],"minDifficulty":1,"maxDifficulty":5,"rarity":"Epic","weight":5.0,"minQuantity":1.0,"maxQuantity":5.0,"towerBaseOnly":false,"stackable":true,"convertible":false,"convertScaleItem":"","convertScaleNumber":0,"material":"","canForgeDragonscaleScale":false,"canBeEnhanced":false,"canBeEnchanted":false,"notes":""}]$loot$::jsonb) loop
    v_name := public.normalize_item_name(v_row->>'name');
    v_type := public.normalize_item_type(v_row->>'type');
    v_rarity := coalesce(nullif(v_row->>'rarity', ''), 'Common');
    v_min_difficulty := greatest(1, coalesce((v_row->>'minDifficulty')::int, 1));
    v_max_difficulty := greatest(v_min_difficulty, coalesce((v_row->>'maxDifficulty')::int, v_min_difficulty));
    v_stackable := coalesce((v_row->>'stackable')::boolean, true);
    v_convertible := coalesce((v_row->>'convertible')::boolean, false);
    v_scale_item := public.normalize_item_name(coalesce(v_row->>'convertScaleItem', ''));
    v_scale_quantity := coalesce((v_row->>'convertScaleNumber')::numeric, 0);
    v_material := coalesce(nullif(trim(v_row->>'material'), ''), regexp_replace(v_scale_item, '\s+Scale$', '', 'i'));
    v_dragon_fragment := coalesce((v_row->>'canForgeDragonscaleScale')::boolean, false);
    v_can_be_enhanced := coalesce((v_row->>'canBeEnhanced')::boolean, false);
    v_can_be_enchanted := coalesce((v_row->>'canBeEnchanted')::boolean, false);
    v_notes := coalesce(v_row->>'notes', '');
    v_min_quantity := greatest(case when v_type in ('material', 'ore') then 0.5 else 1 end, coalesce((v_row->>'minQuantity')::numeric, 1));
    v_max_quantity := greatest(v_min_quantity, case when v_type in ('material', 'ore') then 0.5 else 1 end, coalesce((v_row->>'maxQuantity')::numeric, v_min_quantity));

    select coalesce(array_agg(value), array['Any']::text[]) into v_biomes
    from jsonb_array_elements_text(coalesce(v_row->'biomes', '["Any"]'::jsonb)) as value;
    if coalesce(array_length(v_biomes, 1), 0) = 0 then
      v_biomes := array['Any']::text[];
    end if;

    insert into public.loot_pools (pool_key, name, description, display_order)
    values (coalesce(nullif(v_row->>'poolKey', ''), 'catalog-' || v_type), coalesce(nullif(v_row->>'pool', ''), initcap(replace(v_type, '-', ' ')) || ' Catalog'), 'Imported item catalog group.', 100)
    on conflict (pool_key) do update
    set name = excluded.name,
        description = excluded.description
    returning id into v_pool_id;

    insert into public.loot_items (pool_id, item_name, item_type, rarity, generator_biomes, difficulty_min, difficulty_max, loot_weight, tower_base_only, is_stackable, min_quantity, max_quantity, notes, is_active)
    values (v_pool_id, v_name, v_type, v_rarity::public.item_rarity, v_biomes, v_min_difficulty, v_max_difficulty, greatest(0, coalesce((v_row->>'weight')::numeric, 0)), coalesce((v_row->>'towerBaseOnly')::boolean, false), v_stackable, v_min_quantity, v_max_quantity, v_notes, true);

    perform public.upsert_item_catalog_entry(v_name, v_type, v_rarity, coalesce(nullif(v_row->>'pool', ''), 'Loot Catalog'), array[]::text[], public.item_quantity_step(v_name, v_type), v_stackable, '{}'::jsonb, v_material, false, case when v_type = 'storage' then public.catalog_storage_capacity(v_name) else 0 end, v_notes, true, 100, v_can_be_enhanced, v_can_be_enchanted);

    update public.item_catalog
    set can_be_enhanced = v_can_be_enhanced,
        can_be_enchanted = v_can_be_enchanted,
        material = case when v_material <> '' then v_material else material end,
        is_stackable = v_stackable,
        quantity_step = public.item_quantity_step(v_name, v_type)
    where item_key = public.catalog_key_for_name(v_name);

    if v_convertible and v_scale_item <> '' and v_scale_quantity > 0 then
      perform public.upsert_material_conversion_recipe(v_name, v_name, v_type, v_rarity, coalesce(nullif(v_material, ''), regexp_replace(v_scale_item, '\s+Scale$', '', 'i')), v_scale_item, v_scale_quantity, 100);
    end if;

    if v_dragon_fragment then
      perform public.upsert_dragon_scale_fragment(v_name, v_type, v_rarity, 100);
    end if;
  end loop;
end $$;

-- ============================================================
-- ============================================================

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


-- ============================================================
-- ============================================================

-- Trades and notifications foundation.

create table if not exists public.campaign_notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_user_id uuid references public.profiles(id) on delete cascade,
  title text not null,
  body text not null default '',
  notice_kind text not null default 'notice' check (notice_kind in ('notice', 'trade', 'announcement', 'system')),
  source_type text,
  source_id uuid,
  location_name text not null default '',
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists campaign_notifications_recipient_idx on public.campaign_notifications(recipient_user_id, read_at, created_at desc);
create index if not exists campaign_notifications_source_idx on public.campaign_notifications(source_type, source_id);

create table if not exists public.trade_offers (
  id uuid primary key default gen_random_uuid(),
  sender_user_id uuid not null references public.profiles(id) on delete cascade,
  recipient_user_id uuid not null references public.profiles(id) on delete cascade,
  sender_character_id uuid not null references public.characters(id) on delete cascade,
  target_character_id uuid not null references public.characters(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'declined', 'cancelled')),
  offer_note text not null default '',
  request_note text not null default '',
  offered_item_id uuid references public.inventory_items(id) on delete set null,
  offered_item_name text not null default '',
  offered_quantity numeric(12,1) not null default 1 check (offered_quantity > 0),
  requested_item_id uuid references public.inventory_items(id) on delete set null,
  requested_item_name text not null default '',
  requested_quantity numeric(12,1) not null default 1 check (requested_quantity > 0),
  offered_items jsonb not null default '[]'::jsonb check (jsonb_typeof(offered_items) = 'array'),
  requested_items jsonb not null default '[]'::jsonb check (jsonb_typeof(requested_items) = 'array'),
  offered_currency jsonb not null default '[]'::jsonb check (jsonb_typeof(offered_currency) = 'array'),
  requested_currency jsonb not null default '[]'::jsonb check (jsonb_typeof(requested_currency) = 'array'),
  message text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists trade_offers_sender_idx on public.trade_offers(sender_user_id, status, created_at desc);
create index if not exists trade_offers_recipient_idx on public.trade_offers(recipient_user_id, status, created_at desc);

alter table public.trade_offers
  add column if not exists offered_item_id uuid references public.inventory_items(id) on delete set null,
  add column if not exists offered_item_name text not null default '',
  add column if not exists offered_quantity numeric(12,1) not null default 1 check (offered_quantity > 0),
  add column if not exists requested_item_id uuid references public.inventory_items(id) on delete set null,
  add column if not exists requested_item_name text not null default '',
  add column if not exists requested_quantity numeric(12,1) not null default 1 check (requested_quantity > 0),
  add column if not exists offered_items jsonb not null default '[]'::jsonb check (jsonb_typeof(offered_items) = 'array'),
  add column if not exists requested_items jsonb not null default '[]'::jsonb check (jsonb_typeof(requested_items) = 'array'),
  add column if not exists offered_currency jsonb not null default '[]'::jsonb check (jsonb_typeof(offered_currency) = 'array'),
  add column if not exists requested_currency jsonb not null default '[]'::jsonb check (jsonb_typeof(requested_currency) = 'array');

alter table public.campaign_notifications enable row level security;
alter table public.trade_offers enable row level security;
revoke all on public.campaign_notifications from anon, authenticated;
revoke all on public.trade_offers from anon, authenticated;

drop trigger if exists trade_offers_touch_updated_at on public.trade_offers;
create trigger trade_offers_touch_updated_at
before update on public.trade_offers
for each row execute function public.touch_updated_at();

create or replace function public.notification_record_to_json(p_notice public.campaign_notifications)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'id', p_notice.id,
    'title', p_notice.title,
    'body', p_notice.body,
    'kind', p_notice.notice_kind,
    'sourceType', p_notice.source_type,
    'sourceId', p_notice.source_id,
    'readAt', p_notice.read_at,
    'createdAt', p_notice.created_at
  )
$$;

create or replace function public.trade_offer_record_to_json(p_trade public.trade_offers)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'id', p_trade.id,
    'senderUserId', p_trade.sender_user_id,
    'recipientUserId', p_trade.recipient_user_id,
    'senderCharacterId', p_trade.sender_character_id,
    'targetCharacterId', p_trade.target_character_id,
    'senderCharacterName', coalesce((select c.name from public.characters c where c.id = p_trade.sender_character_id), 'Unknown'),
    'targetCharacterName', coalesce((select c.name from public.characters c where c.id = p_trade.target_character_id), 'Unknown'),
    'status', p_trade.status,
    'offerNote', p_trade.offer_note,
    'requestNote', p_trade.request_note,
    'offeredItemId', p_trade.offered_item_id,
    'offeredItemName', p_trade.offered_item_name,
    'offeredQuantity', p_trade.offered_quantity,
    'requestedItemId', p_trade.requested_item_id,
    'requestedItemName', p_trade.requested_item_name,
    'requestedQuantity', p_trade.requested_quantity,
    'offeredItems', case
      when jsonb_array_length(coalesce(p_trade.offered_items, '[]'::jsonb)) > 0 then p_trade.offered_items
      when p_trade.offered_item_id is not null then jsonb_build_array(jsonb_build_object(
        'itemId', p_trade.offered_item_id,
        'name', p_trade.offered_item_name,
        'quantity', p_trade.offered_quantity
      ))
      else '[]'::jsonb
    end,
    'requestedItems', case
      when jsonb_array_length(coalesce(p_trade.requested_items, '[]'::jsonb)) > 0 then p_trade.requested_items
      when p_trade.requested_item_id is not null then jsonb_build_array(jsonb_build_object(
        'itemId', p_trade.requested_item_id,
        'name', p_trade.requested_item_name,
        'quantity', p_trade.requested_quantity
      ))
      else '[]'::jsonb
    end,
    'offeredCurrency', p_trade.offered_currency,
    'requestedCurrency', p_trade.requested_currency,
    'message', p_trade.message,
    'createdAt', p_trade.created_at,
    'updatedAt', p_trade.updated_at
  )
$$;

-- Daily Efforts rewards.
create table if not exists public.daily_reward_schedule (
  id uuid primary key default gen_random_uuid(),
  reward_date date not null unique,
  reward_kind text not null default 'none' check (reward_kind in ('none', 'item', 'currency')),
  item_catalog_id uuid references public.item_catalog(id) on delete set null,
  currency_unit_id uuid references public.currency_units(id) on delete set null,
  quantity numeric(12,1) not null default 0 check (quantity >= 0),
  updated_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.daily_reward_claims (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  reward_date date not null,
  schedule_id uuid references public.daily_reward_schedule(id) on delete set null,
  character_id uuid references public.characters(id) on delete set null,
  reward_kind text not null check (reward_kind in ('item', 'currency')),
  item_catalog_id uuid references public.item_catalog(id) on delete set null,
  currency_unit_id uuid references public.currency_units(id) on delete set null,
  quantity numeric(12,1) not null default 1,
  claimed_at timestamptz not null default now(),
  unique (user_id, reward_date)
);

alter table public.daily_reward_schedule enable row level security;
alter table public.daily_reward_claims enable row level security;
revoke all on public.daily_reward_schedule from anon, authenticated;
revoke all on public.daily_reward_claims from anon, authenticated;

drop trigger if exists daily_reward_schedule_touch_updated_at on public.daily_reward_schedule;
create trigger daily_reward_schedule_touch_updated_at
before update on public.daily_reward_schedule
for each row execute function public.touch_updated_at();

create or replace function public.daily_reward_today()
returns date
language sql
stable
as $$
  select (now() at time zone 'America/New_York')::date
$$;

create or replace function public.daily_reward_week_start(p_date date)
returns date
language sql
immutable
as $$
  select p_date - extract(dow from p_date)::int
$$;

create or replace function public.currency_unit_record_to_json(p_unit public.currency_units)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'id', p_unit.id,
    'systemKey', p_unit.currency_system_key,
    'key', p_unit.unit_key,
    'name', p_unit.name,
    'symbol', p_unit.symbol,
    'order', p_unit.unit_order
  )
$$;

create or replace function public.daily_reward_entry_to_json(
  p_reward_date date,
  p_profile public.profiles
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_today date := public.daily_reward_today();
  v_week_start date := public.daily_reward_week_start(public.daily_reward_today());
  v_schedule public.daily_reward_schedule%rowtype;
  v_claim public.daily_reward_claims%rowtype;
  v_item public.item_catalog%rowtype;
  v_currency public.currency_units%rowtype;
  v_has_reward boolean := false;
  v_status text := 'empty';
begin
  select * into v_schedule
  from public.daily_reward_schedule
  where reward_date = p_reward_date;

  if v_schedule.id is not null and v_schedule.reward_kind in ('item', 'currency') then
    v_has_reward := true;
  end if;

  select * into v_claim
  from public.daily_reward_claims
  where user_id = p_profile.id
    and reward_date = p_reward_date;

  if v_schedule.item_catalog_id is not null then
    select * into v_item from public.item_catalog where id = v_schedule.item_catalog_id;
  end if;

  if v_schedule.currency_unit_id is not null then
    select * into v_currency from public.currency_units where id = v_schedule.currency_unit_id;
  end if;

  v_status := case
    when v_claim.id is not null then 'received'
    when not v_has_reward then 'empty'
    when p_reward_date < v_today then 'missed'
    when p_reward_date = v_today then 'available'
    else 'upcoming'
  end;

  return jsonb_build_object(
    'date', p_reward_date,
    'dayOfWeek', extract(dow from p_reward_date)::int,
    'dayName', trim(to_char(p_reward_date, 'Day')),
    'weekOffset', case when p_reward_date >= v_week_start + 7 then 1 else 0 end,
    'scheduleId', v_schedule.id,
    'rewardKind', coalesce(v_schedule.reward_kind, 'none'),
    'quantity', coalesce(v_schedule.quantity, 0),
    'item', case when v_item.id is not null then public.catalog_record_to_json(v_item) else null end,
    'currency', case when v_currency.id is not null then public.currency_unit_record_to_json(v_currency) else null end,
    'status', v_status,
    'available', v_status = 'available'
  );
end;
$$;

create or replace function public.get_daily_rewards(p_session_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_today date := public.daily_reward_today();
  v_week_start date := public.daily_reward_week_start(public.daily_reward_today());
begin
  select * into v_profile
  from public.profile_from_campaign_session(p_session_token);

  if v_profile.id is null then
    raise exception 'Invalid or expired session.';
  end if;

  return jsonb_build_object(
    'today', v_today,
    'currentWeekStart', v_week_start,
    'nextWeekStart', v_week_start + 7,
    'available', exists (
      select 1
      from public.daily_reward_schedule s
      where s.reward_date = v_today
        and s.reward_kind in ('item', 'currency')
        and not exists (
          select 1 from public.daily_reward_claims c
          where c.user_id = v_profile.id
            and c.reward_date = v_today
        )
    ),
    'rewards', (
      select coalesce(jsonb_agg(public.daily_reward_entry_to_json(day_value::date, v_profile) order by day_value), '[]'::jsonb)
      from generate_series(v_week_start, v_week_start + 13, interval '1 day') as days(day_value)
    ),
    'characters', (
      select coalesce(jsonb_agg(public.character_record_to_json(c) order by c.name), '[]'::jsonb)
      from public.characters c
      where c.kind = 'player'::public.character_kind
        and (v_profile.role = 'dm'::public.user_role or c.owner_user_id = v_profile.id)
    ),
    'catalog', (
      select coalesce(jsonb_agg(public.catalog_record_to_json(i) order by i.category, i.display_order, i.item_name), '[]'::jsonb)
      from public.item_catalog i
      where i.is_active
    ),
    'currencyUnits', (
      select coalesce(jsonb_agg(public.currency_unit_record_to_json(u) order by u.currency_system_key, u.unit_order), '[]'::jsonb)
      from public.currency_units u
    )
  );
end;
$$;

create or replace function public.update_daily_reward_schedule(
  p_session_token text,
  p_rewards jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_today date := public.daily_reward_today();
  v_week_start date := public.daily_reward_week_start(public.daily_reward_today());
  v_rewards jsonb := case when jsonb_typeof(coalesce(p_rewards, '[]'::jsonb)) = 'array' then coalesce(p_rewards, '[]'::jsonb) else '[]'::jsonb end;
  v_entry jsonb;
  v_reward_date date;
  v_kind text;
  v_item_catalog_id uuid;
  v_currency_unit_id uuid;
  v_quantity numeric;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;
  if v_profile.role <> 'dm'::public.user_role then raise exception 'Only the Dungeon Master can edit daily rewards.'; end if;

  for v_entry in select * from jsonb_array_elements(v_rewards) loop
    v_reward_date := nullif(coalesce(v_entry->>'date', v_entry->>'rewardDate', ''), '')::date;
    if v_reward_date is null then
      continue;
    end if;
    if v_reward_date < v_week_start or v_reward_date > v_week_start + 13 then
      raise exception 'Daily rewards can only be scheduled for this week or next week.';
    end if;

    v_kind := lower(trim(coalesce(v_entry->>'rewardKind', v_entry->>'reward_kind', 'none')));
    if v_kind not in ('none', 'item', 'currency') then
      v_kind := 'none';
    end if;

    v_item_catalog_id := null;
    v_currency_unit_id := null;
    v_quantity := case when v_kind = 'none' then 0 else greatest(1, coalesce(nullif(v_entry->>'quantity', '')::numeric, 1)) end;

    if v_kind = 'item' then
      v_item_catalog_id := nullif(coalesce(v_entry->>'itemCatalogId', v_entry->>'item_catalog_id', ''), '')::uuid;
      if v_item_catalog_id is null or not exists (select 1 from public.item_catalog where id = v_item_catalog_id and is_active) then
        raise exception 'Choose a valid item for each item reward.';
      end if;
      v_quantity := public.assert_valid_item_quantity(
        (select item_name from public.item_catalog where id = v_item_catalog_id),
        (select item_type from public.item_catalog where id = v_item_catalog_id),
        v_quantity
      );
    elsif v_kind = 'currency' then
      v_currency_unit_id := nullif(coalesce(v_entry->>'currencyUnitId', v_entry->>'currency_unit_id', ''), '')::uuid;
      if v_currency_unit_id is null or not exists (select 1 from public.currency_units where id = v_currency_unit_id) then
        raise exception 'Choose a valid currency for each currency reward.';
      end if;
      v_quantity := floor(v_quantity)::int;
    end if;

    insert into public.daily_reward_schedule (
      reward_date,
      reward_kind,
      item_catalog_id,
      currency_unit_id,
      quantity,
      updated_by
    )
    values (
      v_reward_date,
      v_kind,
      v_item_catalog_id,
      v_currency_unit_id,
      v_quantity,
      v_profile.id
    )
    on conflict (reward_date) do update
    set reward_kind = excluded.reward_kind,
        item_catalog_id = excluded.item_catalog_id,
        currency_unit_id = excluded.currency_unit_id,
        quantity = excluded.quantity,
        updated_by = excluded.updated_by,
        updated_at = now();
  end loop;

  perform public.touch_app_live_update('dashboard', null);
  return public.get_daily_rewards(p_session_token);
end;
$$;

create or replace function public.claim_daily_reward(
  p_session_token text,
  p_reward_date date,
  p_character_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_character public.characters%rowtype;
  v_schedule public.daily_reward_schedule%rowtype;
  v_catalog public.item_catalog%rowtype;
  v_currency public.currency_units%rowtype;
  v_slot int;
  v_quantity numeric;
  v_item public.inventory_items%rowtype;
  v_target public.inventory_items%rowtype;
  v_storage_kind text;
  v_storage_active boolean;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;

  if p_reward_date <> public.daily_reward_today() then
    raise exception 'Only today''s daily reward can be claimed.';
  end if;

  select * into v_schedule
  from public.daily_reward_schedule
  where reward_date = p_reward_date
  for update;

  if v_schedule.id is null or v_schedule.reward_kind not in ('item', 'currency') then
    raise exception 'No daily reward is scheduled today.';
  end if;

  if exists (
    select 1 from public.daily_reward_claims
    where user_id = v_profile.id
      and reward_date = p_reward_date
  ) then
    raise exception 'You already claimed today''s daily reward.';
  end if;

  select * into v_character
  from public.characters
  where id = p_character_id
    and kind = 'player'::public.character_kind;

  if v_character.id is null then raise exception 'Choose a valid character for this reward.'; end if;
  if v_profile.role <> 'dm'::public.user_role and v_character.owner_user_id is distinct from v_profile.id then
    raise exception 'Choose one of your assigned characters for this reward.';
  end if;

  v_quantity := greatest(1, coalesce(v_schedule.quantity, 1));

  if v_schedule.reward_kind = 'currency' then
    select * into v_currency
    from public.currency_units
    where id = v_schedule.currency_unit_id;

    if v_currency.id is null then raise exception 'Daily reward currency was not found.'; end if;

    insert into public.character_wallet_balances (character_id, currency_unit_id, amount)
    values (v_character.id, v_currency.id, floor(v_quantity)::int)
    on conflict (character_id, currency_unit_id) do update
    set amount = public.character_wallet_balances.amount + excluded.amount;
  else
    select * into v_catalog
    from public.item_catalog
    where id = v_schedule.item_catalog_id
      and is_active;

    if v_catalog.id is null then raise exception 'Daily reward item was not found.'; end if;

    v_quantity := public.assert_valid_item_quantity(v_catalog.item_name, v_catalog.item_type, v_quantity);

    if public.normalize_item_type(v_catalog.item_type) = 'pet' then
      perform public.place_pet_item_for_character(
        v_character.id,
        v_catalog.item_name,
        null,
        v_catalog.notes,
        v_catalog.rarity,
        v_quantity,
        false,
        v_catalog.default_modifiers,
        null,
        null,
        v_catalog.material,
        0,
        v_catalog.is_two_handed
      );
    elsif public.normalize_item_type(v_catalog.item_type) = 'storage' then
      v_storage_kind := public.additional_storage_kind(v_catalog.item_name, v_catalog.item_type);
      v_storage_active := v_storage_kind is not null
        and not public.character_storage_container_exists(v_character.id, v_catalog.item_name);
      v_slot := case
        when v_storage_active then public.next_storage_container_slot(v_character.id)
        else public.find_first_free_inventory_slot(v_character.id, null, v_character.inventory_slots)
      end;
      if v_slot is null then raise exception 'Inventory full.'; end if;

      insert into public.inventory_items (
        character_id, parent_item_id, slot_index, item_name, item_type, rarity, quantity,
        item_description, is_storage, storage_active, storage_capacity, modifiers, material, is_two_handed
      )
      values (
        v_character.id, null, v_slot, v_catalog.item_name, public.normalize_item_type(v_catalog.item_type), v_catalog.rarity, 1,
        v_catalog.notes, true, v_storage_active, greatest(1, coalesce(nullif(v_catalog.storage_capacity, 0), public.catalog_storage_capacity(v_catalog.item_name))),
        v_catalog.default_modifiers, v_catalog.material, v_catalog.is_two_handed
      );
    else
      select * into v_target
      from public.inventory_items i
      where i.character_id = v_character.id
        and i.parent_item_id is null
        and i.loadout_slot is null
        and lower(public.normalize_item_name(i.item_name)) = lower(public.normalize_item_name(v_catalog.item_name))
        and public.normalize_item_type(i.item_type) = public.normalize_item_type(v_catalog.item_type)
        and i.rarity = v_catalog.rarity
        and i.is_storage = false
        and coalesce(i.enchantment, '') = ''
        and coalesce(i.rune_name, '') = ''
        and coalesce(i.material, '') = coalesce(v_catalog.material, '')
        and i.enhancement_count = 0
        and i.is_two_handed = v_catalog.is_two_handed
        and i.modifiers = v_catalog.default_modifiers
        and public.item_catalog_stackable(v_catalog.item_name, v_catalog.item_type)
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

        insert into public.inventory_items (
          character_id, parent_item_id, slot_index, item_name, item_type, rarity, quantity,
          item_description, is_storage, storage_capacity, modifiers, material, is_two_handed
        )
        values (
          v_character.id, null, v_slot, v_catalog.item_name, public.normalize_item_type(v_catalog.item_type), v_catalog.rarity, v_quantity,
          v_catalog.notes, false, 0, v_catalog.default_modifiers, v_catalog.material, v_catalog.is_two_handed
        )
        returning * into v_item;
      end if;
    end if;
  end if;

  insert into public.daily_reward_claims (
    user_id,
    reward_date,
    schedule_id,
    character_id,
    reward_kind,
    item_catalog_id,
    currency_unit_id,
    quantity
  )
  values (
    v_profile.id,
    p_reward_date,
    v_schedule.id,
    v_character.id,
    v_schedule.reward_kind,
    v_schedule.item_catalog_id,
    v_schedule.currency_unit_id,
    v_quantity
  );

  perform public.touch_app_live_update('dashboard', null);
  perform public.touch_app_live_update('inventory', v_character.id::text);
  return public.get_daily_rewards(p_session_token);
end;
$$;

create or replace function public.get_dashboard_state(p_session_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_active_battle_id uuid;
begin
  select * into v_profile
  from public.profile_from_campaign_session(p_session_token);

  if v_profile.id is null then
    raise exception 'Invalid or expired session.';
  end if;

  select b.id into v_active_battle_id
  from public.battles b
  where b.status = 'active'::public.battle_status
  order by b.created_at desc
  limit 1;

  return jsonb_build_object(
    'activeBattle', v_active_battle_id is not null,
    'activeBattleId', v_active_battle_id,
    'notifications', (
      select coalesce(jsonb_agg(public.notification_record_to_json(n) order by n.created_at desc), '[]'::jsonb)
      from public.campaign_notifications n
      where n.read_at is null
        and (n.recipient_user_id = v_profile.id or n.recipient_user_id is null)
    ),
    'dailyRewards', (
      select jsonb_build_object(
        'today', public.daily_reward_today(),
        'available', exists (
          select 1
          from public.daily_reward_schedule s
          where s.reward_date = public.daily_reward_today()
            and s.reward_kind in ('item', 'currency')
            and not exists (
              select 1
              from public.daily_reward_claims c
              where c.user_id = v_profile.id
                and c.reward_date = public.daily_reward_today()
            )
        )
      )
    )
  );
end;
$$;

create or replace function public.mark_notification_read(
  p_session_token text,
  p_notification_id uuid
)
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

  update public.campaign_notifications
  set read_at = now()
  where id = p_notification_id
    and read_at is null
    and (recipient_user_id = v_profile.id or recipient_user_id is null);

  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.create_campaign_announcement(
  p_session_token text,
  p_title text,
  p_body text,
  p_location_name text default '',
  p_in_world boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_title text := nullif(trim(coalesce(p_title, '')), '');
  v_body text := coalesce(p_body, '');
  v_location text := nullif(trim(coalesce(p_location_name, '')), '');
  v_inserted int := 0;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;
  if v_profile.role <> 'dm'::public.user_role then raise exception 'Only the Dungeon Master can send announcements.'; end if;
  if v_title is null then raise exception 'Announcement title is required.'; end if;

  insert into public.campaign_notifications (
    recipient_user_id,
    title,
    body,
    notice_kind,
    source_type,
    location_name
  )
  select
    p.id,
    v_title,
    case when p_in_world then '[In-world] ' || v_body else v_body end,
    'announcement',
    'announcement',
    coalesce(v_location, '')
  from public.profiles p
  where v_location is null
     or exists (
       select 1
       from public.characters c
       where c.owner_user_id = p.id
         and c.location_name = v_location
     );

  get diagnostics v_inserted = row_count;

  if v_inserted = 0 then
    insert into public.campaign_notifications (recipient_user_id, title, body, notice_kind, source_type, location_name)
    select p.id, v_title, case when p_in_world then '[In-world] ' || v_body else v_body end, 'announcement', 'announcement', coalesce(v_location, '')
    from public.profiles p;
  end if;

  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.get_trade_offers(p_session_token text)
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

  return jsonb_build_object(
    'trades', (
      select coalesce(jsonb_agg(public.trade_offer_record_to_json(t) order by t.created_at desc), '[]'::jsonb)
      from public.trade_offers t
      where t.sender_user_id = v_profile.id
         or t.recipient_user_id = v_profile.id
         or v_profile.role = 'dm'::public.user_role
    )
  );
end;
$$;

create or replace function public.assert_trade_currency_available(
  p_character_id uuid,
  p_currency jsonb
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_entry jsonb;
  v_unit_id uuid;
  v_amount int;
  v_available int;
begin
  for v_entry in select * from jsonb_array_elements(case when jsonb_typeof(coalesce(p_currency, '[]'::jsonb)) = 'array' then coalesce(p_currency, '[]'::jsonb) else '[]'::jsonb end) loop
    v_unit_id := nullif(coalesce(v_entry->>'unitId', v_entry->>'unit_id'), '')::uuid;
    v_amount := greatest(0, floor(coalesce(nullif(v_entry->>'amount', '')::numeric, 0))::int);
    if v_unit_id is null or v_amount <= 0 then
      continue;
    end if;

    if not exists (select 1 from public.currency_units where id = v_unit_id) then
      raise exception 'A trade currency unit was not found.';
    end if;

    select coalesce(amount, 0) into v_available
    from public.character_wallet_balances
    where character_id = p_character_id
      and currency_unit_id = v_unit_id;

    if coalesce(v_available, 0) < v_amount then
      raise exception 'A character does not have enough offered money for this trade.';
    end if;
  end loop;
end;
$$;

create or replace function public.transfer_trade_currency(
  p_from_character_id uuid,
  p_to_character_id uuid,
  p_currency jsonb
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_entry jsonb;
  v_unit_id uuid;
  v_amount int;
  v_available int;
begin
  for v_entry in select * from jsonb_array_elements(case when jsonb_typeof(coalesce(p_currency, '[]'::jsonb)) = 'array' then coalesce(p_currency, '[]'::jsonb) else '[]'::jsonb end) loop
    v_unit_id := nullif(coalesce(v_entry->>'unitId', v_entry->>'unit_id'), '')::uuid;
    v_amount := greatest(0, floor(coalesce(nullif(v_entry->>'amount', '')::numeric, 0))::int);
    if v_unit_id is null or v_amount <= 0 then
      continue;
    end if;

    select coalesce(amount, 0) into v_available
    from public.character_wallet_balances
    where character_id = p_from_character_id
      and currency_unit_id = v_unit_id
    for update;

    if coalesce(v_available, 0) < v_amount then
      raise exception 'A character no longer has enough money for this trade.';
    end if;

    update public.character_wallet_balances
    set amount = amount - v_amount
    where character_id = p_from_character_id
      and currency_unit_id = v_unit_id;

    insert into public.character_wallet_balances (character_id, currency_unit_id, amount)
    values (p_to_character_id, v_unit_id, v_amount)
    on conflict (character_id, currency_unit_id) do update
    set amount = public.character_wallet_balances.amount + excluded.amount;
  end loop;
end;
$$;

create or replace function public.move_inventory_storage_tree_to_character(
  p_storage_item_id uuid,
  p_to_character_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_storage public.inventory_items%rowtype;
  v_target_character public.characters%rowtype;
  v_slot_index int;
  v_storage_kind text;
  v_activate boolean := true;
  v_has_children boolean := false;
begin
  select * into v_storage
  from public.inventory_items
  where id = p_storage_item_id
  for update;

  if v_storage.id is null then raise exception 'Storage container is no longer available.'; end if;
  if not v_storage.is_storage then raise exception 'That item is not a storage container.'; end if;
  if v_storage.loadout_slot is not null then raise exception 'Unequip that storage container before moving it.'; end if;

  select * into v_target_character from public.characters where id = p_to_character_id;
  if v_target_character.id is null then raise exception 'Receiving character was not found.'; end if;

  v_storage_kind := public.additional_storage_kind(v_storage.item_name, v_storage.item_type);
  v_has_children := exists (select 1 from public.inventory_items child where child.parent_item_id = v_storage.id);
  v_activate := v_storage_kind is not null
    and not exists (
      select 1
      from public.inventory_items i
      where i.character_id = p_to_character_id
        and i.id <> v_storage.id
        and i.parent_item_id is null
        and i.loadout_slot is null
        and i.is_storage = true
        and i.storage_active = true
        and public.additional_storage_kind(i.item_name, i.item_type) = v_storage_kind
    );

  if not v_activate and v_has_children then
    raise exception 'That character already has active % storage. Empty this container before gifting or trading it.', v_storage.item_name;
  end if;

  v_slot_index := case
    when v_activate then public.next_storage_container_slot(p_to_character_id)
    else public.find_first_free_inventory_slot(p_to_character_id, null, v_target_character.inventory_slots)
  end;
  if v_slot_index is null then raise exception 'Target inventory is full.'; end if;

  update public.inventory_items
  set character_id = p_to_character_id,
      parent_item_id = null,
      loadout_slot = null,
      slot_index = v_slot_index,
      storage_active = v_activate
  where id = p_storage_item_id;

  with recursive descendants as (
    select child.id
    from public.inventory_items child
    where child.parent_item_id = p_storage_item_id

    union all

    select child.id
    from public.inventory_items child
    join descendants parent on parent.id = child.parent_item_id
  )
  update public.inventory_items moved
  set character_id = p_to_character_id,
      loadout_slot = null
  where moved.id in (select id from descendants);
end;
$$;

create or replace function public.transfer_trade_inventory_item(
  p_item_id uuid,
  p_from_character_id uuid,
  p_to_character_id uuid,
  p_quantity numeric
)
returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_source_item public.inventory_items%rowtype;
  v_target_item public.inventory_items%rowtype;
  v_target_character public.characters%rowtype;
  v_quantity numeric;
  v_slot_index int;
  v_item_label text;
begin
  select * into v_source_item
  from public.inventory_items
  where id = p_item_id
  for update;

  if v_source_item.id is null then raise exception 'A trade item is no longer available.'; end if;
  if v_source_item.character_id <> p_from_character_id then raise exception 'A trade item is no longer held by the expected character.'; end if;
  if v_source_item.loadout_slot is not null and public.normalize_item_type(v_source_item.item_type) <> 'pet' then raise exception 'A trade item is currently equipped.'; end if;

  select * into v_target_character from public.characters where id = p_to_character_id;
  if v_target_character.id is null then raise exception 'Receiving character was not found.'; end if;

  v_quantity := public.assert_valid_item_quantity(v_source_item.item_name, v_source_item.item_type, greatest(0.5, coalesce(p_quantity, 1)));
  if v_source_item.quantity < v_quantity then raise exception 'A trade item quantity is no longer available.'; end if;
  v_item_label := public.format_item_quantity(v_quantity) || ' ' || coalesce(v_source_item.display_name, v_source_item.item_name);

  if v_source_item.is_storage then
    if v_quantity <> 1 then raise exception 'Storage containers must be traded one at a time.'; end if;
    perform public.move_inventory_storage_tree_to_character(v_source_item.id, v_target_character.id);
    return '1 ' || coalesce(v_source_item.display_name, v_source_item.item_name);
  end if;

  if public.normalize_item_type(v_source_item.item_type) = 'pet' then
    perform public.place_pet_item_for_character(
      v_target_character.id,
      v_source_item.item_name,
      v_source_item.display_name,
      v_source_item.item_description,
      v_source_item.rarity,
      v_quantity,
      v_source_item.is_accessory,
      v_source_item.modifiers,
      v_source_item.enchantment,
      v_source_item.rune_name,
      v_source_item.material,
      v_source_item.enhancement_count,
      v_source_item.is_two_handed
    );

    if v_quantity >= v_source_item.quantity then
      delete from public.inventory_items where id = v_source_item.id;
    else
      update public.inventory_items
      set quantity = quantity - v_quantity
      where id = v_source_item.id;
    end if;

    return v_item_label;
  end if;

  select * into v_target_item
  from public.inventory_items i
  where i.character_id = v_target_character.id
    and i.parent_item_id is null
    and i.loadout_slot is null
    and lower(public.normalize_item_name(i.item_name)) = lower(public.normalize_item_name(v_source_item.item_name))
    and public.normalize_item_type(i.item_type) = public.normalize_item_type(v_source_item.item_type)
    and i.rarity = v_source_item.rarity
    and coalesce(i.enchantment, '') = coalesce(v_source_item.enchantment, '')
    and coalesce(i.rune_name, '') = coalesce(v_source_item.rune_name, '')
    and coalesce(i.material, '') = coalesce(v_source_item.material, '')
    and coalesce(i.potion_strength, '') = coalesce(v_source_item.potion_strength, '')
    and coalesce(i.potion_property, '') = coalesce(v_source_item.potion_property, '')
    and coalesce(i.potion_quality, '') = coalesce(v_source_item.potion_quality, '')
    and i.enhancement_count = v_source_item.enhancement_count
    and i.is_two_handed = v_source_item.is_two_handed
    and i.is_accessory = v_source_item.is_accessory
    and i.modifiers = v_source_item.modifiers
    and i.is_storage = false
    and v_source_item.is_storage = false
    and public.item_catalog_stackable(v_source_item.item_name, v_source_item.item_type)
  order by i.slot_index
  limit 1;

  if v_target_item.id is not null then
    update public.inventory_items
    set quantity = quantity + v_quantity
    where id = v_target_item.id;
  else
    v_slot_index := public.find_first_free_inventory_slot(v_target_character.id, null::uuid, v_target_character.inventory_slots);
    if v_slot_index is null then raise exception 'Receiving character inventory is full.'; end if;

    insert into public.inventory_items (
      character_id,
      parent_item_id,
      slot_index,
      item_name,
      display_name,
      item_description,
      item_type,
      rarity,
      quantity,
      is_accessory,
      is_storage,
      storage_capacity,
      modifiers,
      enchantment,
      rune_name,
      material,
      enhancement_count,
      is_two_handed,
      potion_strength,
      potion_property,
      potion_quality
    )
    values (
      v_target_character.id,
      null,
      v_slot_index,
      v_source_item.item_name,
      v_source_item.display_name,
      v_source_item.item_description,
      v_source_item.item_type,
      v_source_item.rarity,
      v_quantity,
      v_source_item.is_accessory,
      false,
      0,
      v_source_item.modifiers,
      v_source_item.enchantment,
      v_source_item.rune_name,
      v_source_item.material,
      v_source_item.enhancement_count,
      v_source_item.is_two_handed,
      v_source_item.potion_strength,
      v_source_item.potion_property,
      v_source_item.potion_quality
    );
  end if;

  if v_quantity >= v_source_item.quantity then
    delete from public.inventory_items where id = v_source_item.id;
  else
    update public.inventory_items
    set quantity = quantity - v_quantity
    where id = v_source_item.id;
  end if;

  return v_item_label;
end;
$$;

drop function if exists public.create_trade_offer(text, uuid, uuid, text, text, text);
drop function if exists public.create_trade_offer(text, uuid, uuid, text, text, text, uuid, numeric);
drop function if exists public.create_trade_offer(text, uuid, uuid, text, text, text, uuid, numeric, uuid, numeric, jsonb, jsonb);
drop function if exists public.create_trade_offer(text, uuid, uuid, text, text, text, uuid, numeric, uuid, numeric, jsonb, jsonb, jsonb, jsonb);

create or replace function public.create_trade_offer(
  p_session_token text,
  p_sender_character_id uuid,
  p_target_character_id uuid,
  p_offer_note text default '',
  p_request_note text default '',
  p_message text default '',
  p_offered_item_id uuid default null,
  p_offered_quantity numeric default 1,
  p_requested_item_id uuid default null,
  p_requested_quantity numeric default 1,
  p_offered_currency jsonb default '[]'::jsonb,
  p_requested_currency jsonb default '[]'::jsonb,
  p_offered_items jsonb default '[]'::jsonb,
  p_requested_items jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_sender public.characters%rowtype;
  v_target public.characters%rowtype;
  v_offered_item public.inventory_items%rowtype;
  v_requested_item public.inventory_items%rowtype;
  v_trade public.trade_offers%rowtype;
  v_entry jsonb;
  v_item_id uuid;
  v_quantity numeric;
  v_offered_quantity numeric := greatest(0.5, coalesce(p_offered_quantity, 1));
  v_requested_quantity numeric := greatest(0.5, coalesce(p_requested_quantity, 1));
  v_offered_currency jsonb := case when jsonb_typeof(coalesce(p_offered_currency, '[]'::jsonb)) = 'array' then coalesce(p_offered_currency, '[]'::jsonb) else '[]'::jsonb end;
  v_requested_currency jsonb := case when jsonb_typeof(coalesce(p_requested_currency, '[]'::jsonb)) = 'array' then coalesce(p_requested_currency, '[]'::jsonb) else '[]'::jsonb end;
  v_offered_items_source jsonb := case when jsonb_typeof(coalesce(p_offered_items, '[]'::jsonb)) = 'array' then coalesce(p_offered_items, '[]'::jsonb) else '[]'::jsonb end;
  v_requested_items_source jsonb := case when jsonb_typeof(coalesce(p_requested_items, '[]'::jsonb)) = 'array' then coalesce(p_requested_items, '[]'::jsonb) else '[]'::jsonb end;
  v_offered_items jsonb := '[]'::jsonb;
  v_requested_items jsonb := '[]'::jsonb;
  v_offer_labels text[] := array[]::text[];
  v_request_labels text[] := array[]::text[];
  v_first_offered_item_id uuid := null;
  v_first_requested_item_id uuid := null;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;

  select * into v_sender from public.characters where id = p_sender_character_id;
  select * into v_target from public.characters where id = p_target_character_id;

  if v_sender.id is null then raise exception 'Offering character was not found.'; end if;
  if v_target.id is null then raise exception 'Target character was not found.'; end if;
  if v_sender.owner_user_id <> v_profile.id and v_profile.role <> 'dm'::public.user_role then
    raise exception 'You can only offer trades from your own characters.';
  end if;
  if v_target.owner_user_id is null then raise exception 'That character is not assigned to a player.'; end if;

  if jsonb_array_length(v_offered_items_source) = 0 and p_offered_item_id is not null then
    v_offered_items_source := jsonb_build_array(jsonb_build_object('itemId', p_offered_item_id, 'quantity', v_offered_quantity));
  end if;

  if jsonb_array_length(v_requested_items_source) = 0 and p_requested_item_id is not null then
    v_requested_items_source := jsonb_build_array(jsonb_build_object('itemId', p_requested_item_id, 'quantity', v_requested_quantity));
  end if;

  for v_entry in select * from jsonb_array_elements(v_offered_items_source) loop
    v_item_id := nullif(coalesce(v_entry->>'itemId', v_entry->>'item_id', v_entry->>'id'), '')::uuid;
    v_quantity := greatest(0.5, coalesce(nullif(v_entry->>'quantity', '')::numeric, 1));
    if v_item_id is null then continue; end if;

    select * into v_offered_item
    from public.inventory_items
    where id = v_item_id
      and character_id = v_sender.id;

    if v_offered_item.id is null then raise exception 'Offered item was not found in that inventory.'; end if;
    if v_offered_item.loadout_slot is not null and public.normalize_item_type(v_offered_item.item_type) <> 'pet' then raise exception 'Unequip that item before offering it.'; end if;
    v_quantity := public.assert_valid_item_quantity(v_offered_item.item_name, v_offered_item.item_type, v_quantity);
    if v_offered_item.is_storage then v_quantity := 1; end if;
    if v_offered_item.quantity < v_quantity then raise exception 'Not enough quantity to offer.'; end if;

    if v_offered_items = '[]'::jsonb then
      v_first_offered_item_id := v_offered_item.id;
      v_offered_quantity := v_quantity;
    end if;
    v_offered_items := v_offered_items || jsonb_build_array(jsonb_build_object(
      'itemId', v_offered_item.id,
      'name', coalesce(v_offered_item.display_name, v_offered_item.item_name),
      'quantity', v_quantity,
      'type', v_offered_item.item_type,
      'rarity', v_offered_item.rarity
    ));
    v_offer_labels := array_append(v_offer_labels, public.format_item_quantity(v_quantity) || ' ' || coalesce(v_offered_item.display_name, v_offered_item.item_name));
  end loop;

  for v_entry in select * from jsonb_array_elements(v_requested_items_source) loop
    v_item_id := nullif(coalesce(v_entry->>'itemId', v_entry->>'item_id', v_entry->>'id'), '')::uuid;
    v_quantity := greatest(0.5, coalesce(nullif(v_entry->>'quantity', '')::numeric, 1));
    if v_item_id is null then continue; end if;

    select * into v_requested_item
    from public.inventory_items
    where id = v_item_id
      and character_id = v_target.id;

    if v_requested_item.id is null then raise exception 'Requested item was not found in that inventory.'; end if;
    if v_requested_item.loadout_slot is not null and public.normalize_item_type(v_requested_item.item_type) <> 'pet' then raise exception 'The requested item is currently equipped.'; end if;
    v_quantity := public.assert_valid_item_quantity(v_requested_item.item_name, v_requested_item.item_type, v_quantity);
    if v_requested_item.is_storage then v_quantity := 1; end if;
    if v_requested_item.quantity < v_quantity then raise exception 'Not enough quantity to request.'; end if;

    if v_requested_items = '[]'::jsonb then
      v_first_requested_item_id := v_requested_item.id;
      v_requested_quantity := v_quantity;
    end if;
    v_requested_items := v_requested_items || jsonb_build_array(jsonb_build_object(
      'itemId', v_requested_item.id,
      'name', coalesce(v_requested_item.display_name, v_requested_item.item_name),
      'quantity', v_quantity,
      'type', v_requested_item.item_type,
      'rarity', v_requested_item.rarity
    ));
    v_request_labels := array_append(v_request_labels, public.format_item_quantity(v_quantity) || ' ' || coalesce(v_requested_item.display_name, v_requested_item.item_name));
  end loop;

  if jsonb_array_length(v_offered_items) = 0 and jsonb_array_length(v_offered_currency) = 0 then
    raise exception 'Offer at least one item or some money.';
  end if;

  if jsonb_array_length(v_requested_items) = 0 and jsonb_array_length(v_requested_currency) = 0 then
    raise exception 'Request at least one item or some money.';
  end if;

  perform public.assert_trade_currency_available(v_sender.id, v_offered_currency);
  perform public.assert_trade_currency_available(v_target.id, v_requested_currency);

  insert into public.trade_offers (
    sender_user_id,
    recipient_user_id,
    sender_character_id,
    target_character_id,
    offer_note,
    request_note,
    offered_item_id,
    offered_item_name,
    offered_quantity,
    offered_items,
    requested_item_id,
    requested_item_name,
    requested_quantity,
    requested_items,
    offered_currency,
    requested_currency,
    message
  )
  values (
    coalesce(v_sender.owner_user_id, v_profile.id),
    v_target.owner_user_id,
    v_sender.id,
    v_target.id,
    coalesce(nullif(p_offer_note, ''), array_to_string(v_offer_labels, ', '), ''),
    coalesce(nullif(p_request_note, ''), array_to_string(v_request_labels, ', '), ''),
    v_first_offered_item_id,
    coalesce(v_offered_items->0->>'name', ''),
    v_offered_quantity,
    v_offered_items,
    v_first_requested_item_id,
    coalesce(v_requested_items->0->>'name', ''),
    v_requested_quantity,
    v_requested_items,
    v_offered_currency,
    v_requested_currency,
    coalesce(p_message, '')
  )
  returning * into v_trade;

  insert into public.campaign_notifications (
    recipient_user_id,
    title,
    body,
    notice_kind,
    source_type,
    source_id,
    location_name
  )
  values (
    v_target.owner_user_id,
    v_sender.name || ' offered a trade to ' || v_target.name,
    trim(both from concat_ws(E'\n\n', nullif(coalesce(p_message, ''), ''), 'Offers: ' || nullif(coalesce(nullif(p_offer_note, ''), array_to_string(v_offer_labels, ', '), 'money'), ''), 'Requests: ' || nullif(coalesce(nullif(p_request_note, ''), array_to_string(v_request_labels, ', '), 'money'), ''))),
    'trade',
    'trade',
    v_trade.id,
    v_target.location_name
  );

  return public.trade_offer_record_to_json(v_trade);
end;
$$;

drop function if exists public.gift_inventory_item(text, uuid, uuid, numeric);

create or replace function public.gift_inventory_item(
  p_session_token text,
  p_item_id uuid,
  p_target_character_id uuid,
  p_quantity numeric default 1
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_source_item public.inventory_items%rowtype;
  v_sender public.characters%rowtype;
  v_target_character public.characters%rowtype;
  v_target_item public.inventory_items%rowtype;
  v_quantity numeric;
  v_slot_index int;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;

  select * into v_source_item
  from public.inventory_items
  where id = p_item_id
  for update;

  if v_source_item.id is null then raise exception 'Item was not found.'; end if;

  v_sender := public.assert_inventory_access(v_profile, v_source_item.character_id, false);

  select * into v_target_character
  from public.characters
  where id = p_target_character_id;

  if v_target_character.id is null then raise exception 'Target character was not found.'; end if;
  if v_target_character.id = v_sender.id then raise exception 'Choose another character to gift this to.'; end if;
  if v_target_character.owner_user_id is null then raise exception 'That character is not assigned to a player.'; end if;
  if v_source_item.loadout_slot is not null and public.normalize_item_type(v_source_item.item_type) <> 'pet' then raise exception 'Unequip that item before gifting it.'; end if;

  if v_sender.owner_user_id is distinct from v_target_character.owner_user_id
    and v_profile.role <> 'dm'::public.user_role
    and not coalesce(v_target_character.gift_inventory_open, true)
  then
    raise exception 'This persons inventory is closed from gifting efforts and grows tired of your pranks';
  end if;

  v_quantity := public.assert_valid_item_quantity(v_source_item.item_name, v_source_item.item_type, greatest(0.5, coalesce(p_quantity, 1)));
  if v_source_item.is_storage then v_quantity := 1; end if;
  if v_quantity > v_source_item.quantity then raise exception 'Not enough quantity to gift.'; end if;

  if v_source_item.is_storage then
    perform public.move_inventory_storage_tree_to_character(v_source_item.id, v_target_character.id);

    if v_sender.owner_user_id is distinct from v_target_character.owner_user_id then
      insert into public.campaign_notifications (
        recipient_user_id,
        title,
        body,
        notice_kind,
        source_type,
        location_name
      )
      values (
        v_target_character.owner_user_id,
        v_sender.name || ' gave storage to ' || v_target_character.name,
        coalesce(v_source_item.display_name, v_source_item.item_name) || ' and its contents were transferred to ' || v_target_character.name || '.',
        'notice',
        'gift',
        v_target_character.location_name
      );
    end if;

    return public.get_character_inventory(p_session_token, v_sender.id);
  end if;

  if public.normalize_item_type(v_source_item.item_type) = 'pet' then
    perform public.place_pet_item_for_character(
      v_target_character.id,
      v_source_item.item_name,
      v_source_item.display_name,
      v_source_item.item_description,
      v_source_item.rarity,
      v_quantity,
      v_source_item.is_accessory,
      v_source_item.modifiers,
      v_source_item.enchantment,
      v_source_item.rune_name,
      v_source_item.material,
      v_source_item.enhancement_count,
      v_source_item.is_two_handed
    );

    if v_quantity >= v_source_item.quantity then
      delete from public.inventory_items where id = v_source_item.id;
    else
      update public.inventory_items
      set quantity = quantity - v_quantity
      where id = v_source_item.id;
    end if;

    if v_sender.owner_user_id is distinct from v_target_character.owner_user_id then
      insert into public.campaign_notifications (
        recipient_user_id,
        title,
        body,
        notice_kind,
        source_type,
        location_name
      )
      values (
        v_target_character.owner_user_id,
        v_sender.name || ' gave an animal to ' || v_target_character.name,
        coalesce(v_source_item.display_name, v_source_item.item_name) || ' was placed into ' || v_target_character.name || '''s active pet slot or stable.',
        'notice',
        'gift',
        v_target_character.location_name
      );
    end if;

    return public.get_character_inventory(p_session_token, v_sender.id);
  end if;

  select * into v_target_item
  from public.inventory_items i
  where i.character_id = v_target_character.id
    and i.parent_item_id is null
    and i.loadout_slot is null
    and lower(public.normalize_item_name(i.item_name)) = lower(public.normalize_item_name(v_source_item.item_name))
    and public.normalize_item_type(i.item_type) = public.normalize_item_type(v_source_item.item_type)
    and i.rarity = v_source_item.rarity
    and coalesce(i.enchantment, '') = coalesce(v_source_item.enchantment, '')
    and coalesce(i.rune_name, '') = coalesce(v_source_item.rune_name, '')
    and coalesce(i.material, '') = coalesce(v_source_item.material, '')
    and coalesce(i.potion_strength, '') = coalesce(v_source_item.potion_strength, '')
    and coalesce(i.potion_property, '') = coalesce(v_source_item.potion_property, '')
    and coalesce(i.potion_quality, '') = coalesce(v_source_item.potion_quality, '')
    and i.enhancement_count = v_source_item.enhancement_count
    and i.is_two_handed = v_source_item.is_two_handed
    and i.is_accessory = v_source_item.is_accessory
    and i.modifiers = v_source_item.modifiers
    and i.item_type <> 'pet'
    and i.is_storage = false
    and v_source_item.is_storage = false
    and public.item_catalog_stackable(v_source_item.item_name, v_source_item.item_type)
  order by i.slot_index
  limit 1;

  if v_target_item.id is not null then
    update public.inventory_items
    set quantity = quantity + v_quantity
    where id = v_target_item.id;
  else
    v_slot_index := public.find_first_free_inventory_slot(v_target_character.id, null::uuid, v_target_character.inventory_slots);
    if v_slot_index is null then raise exception 'Target inventory is full.'; end if;

    insert into public.inventory_items (
      character_id,
      parent_item_id,
      slot_index,
      item_name,
      display_name,
      item_description,
      item_type,
      rarity,
      quantity,
      is_accessory,
      is_storage,
      storage_capacity,
      modifiers,
      enchantment,
      rune_name,
      material,
      enhancement_count,
      is_two_handed,
      potion_strength,
      potion_property,
      potion_quality
    )
    values (
      v_target_character.id,
      null,
      v_slot_index,
      v_source_item.item_name,
      v_source_item.display_name,
      v_source_item.item_description,
      v_source_item.item_type,
      v_source_item.rarity,
      v_quantity,
      v_source_item.is_accessory,
      false,
      0,
      v_source_item.modifiers,
      v_source_item.enchantment,
      v_source_item.rune_name,
      v_source_item.material,
      v_source_item.enhancement_count,
      v_source_item.is_two_handed,
      v_source_item.potion_strength,
      v_source_item.potion_property,
      v_source_item.potion_quality
    );
  end if;

  if v_quantity >= v_source_item.quantity then
    delete from public.inventory_items where id = v_source_item.id;
  else
    update public.inventory_items
    set quantity = quantity - v_quantity
    where id = v_source_item.id;
  end if;

  if v_sender.owner_user_id is distinct from v_target_character.owner_user_id then
    insert into public.campaign_notifications (
      recipient_user_id,
      title,
      body,
      notice_kind,
      source_type,
      location_name
    )
    values (
      v_target_character.owner_user_id,
      v_sender.name || ' gave something to ' || v_target_character.name,
      public.format_item_quantity(v_quantity) || ' ' || coalesce(v_source_item.display_name, v_source_item.item_name) || ' was placed into ' || v_target_character.name || '''s inventory.',
      'notice',
      'gift',
      v_target_character.location_name
    );
  end if;

  return public.get_character_inventory(p_session_token, v_sender.id);
end;
$$;

create or replace function public.update_trade_offer_status(
  p_session_token text,
  p_trade_id uuid,
  p_status text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_trade public.trade_offers%rowtype;
  v_source_item public.inventory_items%rowtype;
  v_requested_item public.inventory_items%rowtype;
  v_target_character public.characters%rowtype;
  v_sender_character public.characters%rowtype;
  v_target_item public.inventory_items%rowtype;
  v_sender_target_item public.inventory_items%rowtype;
  v_slot_index int;
  v_sender_slot_index int;
  v_next_status text := lower(trim(coalesce(p_status, '')));
  v_notify_user uuid;
  v_title text;
  v_entry jsonb;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;
  if v_next_status not in ('accepted', 'declined', 'cancelled') then raise exception 'Unsupported trade status.'; end if;

  select * into v_trade from public.trade_offers where id = p_trade_id;
  if v_trade.id is null then raise exception 'Trade was not found.'; end if;
  if v_trade.status <> 'pending' then raise exception 'That trade has already been resolved.'; end if;

  if v_next_status in ('accepted', 'declined') and v_trade.recipient_user_id <> v_profile.id and v_profile.role <> 'dm'::public.user_role then
    raise exception 'Only the receiving player can accept or decline this trade.';
  end if;
  if v_next_status = 'cancelled' and v_trade.sender_user_id <> v_profile.id and v_profile.role <> 'dm'::public.user_role then
    raise exception 'Only the offering player can cancel this trade.';
  end if;

  if v_next_status = 'accepted' then
    select * into v_sender_character from public.characters where id = v_trade.sender_character_id;
    select * into v_target_character from public.characters where id = v_trade.target_character_id;
    if v_sender_character.id is null then raise exception 'Offering character was not found.'; end if;
    if v_target_character.id is null then raise exception 'Target character was not found.'; end if;
    perform public.assert_trade_currency_available(v_sender_character.id, v_trade.offered_currency);
    perform public.assert_trade_currency_available(v_target_character.id, v_trade.requested_currency);
  end if;

  if v_next_status = 'accepted' then
    for v_entry in select * from jsonb_array_elements(coalesce(v_trade.offered_items, '[]'::jsonb)) loop
      perform public.transfer_trade_inventory_item(
        nullif(coalesce(v_entry->>'itemId', v_entry->>'item_id', v_entry->>'id'), '')::uuid,
        v_trade.sender_character_id,
        v_trade.target_character_id,
        greatest(0.5, coalesce(nullif(v_entry->>'quantity', '')::numeric, 1))
      );
    end loop;

    for v_entry in select * from jsonb_array_elements(coalesce(v_trade.requested_items, '[]'::jsonb)) loop
      perform public.transfer_trade_inventory_item(
        nullif(coalesce(v_entry->>'itemId', v_entry->>'item_id', v_entry->>'id'), '')::uuid,
        v_trade.target_character_id,
        v_trade.sender_character_id,
        greatest(0.5, coalesce(nullif(v_entry->>'quantity', '')::numeric, 1))
      );
    end loop;
  end if;

  if v_next_status = 'accepted' and v_trade.offered_item_id is not null and jsonb_array_length(coalesce(v_trade.offered_items, '[]'::jsonb)) = 0 then
    select * into v_source_item
    from public.inventory_items
    where id = v_trade.offered_item_id
    for update;

    if v_source_item.id is null then raise exception 'The offered item is no longer available.'; end if;
    if v_source_item.character_id <> v_trade.sender_character_id then raise exception 'The offered item is no longer held by the offering character.'; end if;
    if v_source_item.loadout_slot is not null and public.normalize_item_type(v_source_item.item_type) <> 'pet' then raise exception 'The offered item is currently equipped.'; end if;
    if v_source_item.quantity < v_trade.offered_quantity then raise exception 'The offered item quantity is no longer available.'; end if;

    if public.normalize_item_type(v_source_item.item_type) = 'pet' then
      perform public.transfer_trade_inventory_item(v_source_item.id, v_trade.sender_character_id, v_trade.target_character_id, v_trade.offered_quantity);
    else

    select * into v_target_item
    from public.inventory_items i
    where i.character_id = v_target_character.id
      and i.parent_item_id is null
      and i.loadout_slot is null
      and lower(public.normalize_item_name(i.item_name)) = lower(public.normalize_item_name(v_source_item.item_name))
      and public.normalize_item_type(i.item_type) = public.normalize_item_type(v_source_item.item_type)
      and i.rarity = v_source_item.rarity
      and coalesce(i.enchantment, '') = coalesce(v_source_item.enchantment, '')
      and coalesce(i.rune_name, '') = coalesce(v_source_item.rune_name, '')
      and coalesce(i.material, '') = coalesce(v_source_item.material, '')
      and coalesce(i.potion_strength, '') = coalesce(v_source_item.potion_strength, '')
      and coalesce(i.potion_property, '') = coalesce(v_source_item.potion_property, '')
      and coalesce(i.potion_quality, '') = coalesce(v_source_item.potion_quality, '')
      and i.enhancement_count = v_source_item.enhancement_count
      and i.is_two_handed = v_source_item.is_two_handed
      and i.is_accessory = v_source_item.is_accessory
      and i.modifiers = v_source_item.modifiers
      and i.is_storage = false
      and v_source_item.is_storage = false
      and public.item_catalog_stackable(v_source_item.item_name, v_source_item.item_type)
    order by i.slot_index
    limit 1;

    if v_target_item.id is not null then
      update public.inventory_items
      set quantity = quantity + v_trade.offered_quantity
      where id = v_target_item.id;
    else
      v_slot_index := public.find_first_free_inventory_slot(v_target_character.id, null::uuid, v_target_character.inventory_slots);
      if v_slot_index is null then raise exception 'Target inventory is full.'; end if;

      insert into public.inventory_items (
        character_id,
        parent_item_id,
        slot_index,
        item_name,
        display_name,
        item_description,
        item_type,
        rarity,
        quantity,
        is_accessory,
        is_storage,
        storage_capacity,
        modifiers,
        enchantment,
        rune_name,
        material,
        enhancement_count,
        is_two_handed,
        potion_strength,
        potion_property,
        potion_quality
      )
      values (
        v_target_character.id,
        null,
        v_slot_index,
        v_source_item.item_name,
        v_source_item.display_name,
        v_source_item.item_description,
        v_source_item.item_type,
        v_source_item.rarity,
        v_trade.offered_quantity,
        v_source_item.is_accessory,
        false,
        0,
        v_source_item.modifiers,
        v_source_item.enchantment,
        v_source_item.rune_name,
        v_source_item.material,
        v_source_item.enhancement_count,
        v_source_item.is_two_handed,
        v_source_item.potion_strength,
        v_source_item.potion_property,
        v_source_item.potion_quality
      );
    end if;

    if v_trade.offered_quantity >= v_source_item.quantity then
      delete from public.inventory_items where id = v_source_item.id;
    else
      update public.inventory_items
      set quantity = quantity - v_trade.offered_quantity
      where id = v_source_item.id;
    end if;
    end if;
  end if;

  if v_next_status = 'accepted' and v_trade.requested_item_id is not null and jsonb_array_length(coalesce(v_trade.requested_items, '[]'::jsonb)) = 0 then
    select * into v_requested_item
    from public.inventory_items
    where id = v_trade.requested_item_id
    for update;

    if v_requested_item.id is null then raise exception 'The requested item is no longer available.'; end if;
    if v_requested_item.character_id <> v_trade.target_character_id then raise exception 'The requested item is no longer held by the target character.'; end if;
    if v_requested_item.loadout_slot is not null and public.normalize_item_type(v_requested_item.item_type) <> 'pet' then raise exception 'The requested item is currently equipped.'; end if;
    if v_requested_item.quantity < v_trade.requested_quantity then raise exception 'The requested item quantity is no longer available.'; end if;

    if public.normalize_item_type(v_requested_item.item_type) = 'pet' then
      perform public.transfer_trade_inventory_item(v_requested_item.id, v_trade.target_character_id, v_trade.sender_character_id, v_trade.requested_quantity);
    else

    select * into v_sender_target_item
    from public.inventory_items i
      where i.character_id = v_sender_character.id
        and i.parent_item_id is null
        and i.loadout_slot is null
        and lower(public.normalize_item_name(i.item_name)) = lower(public.normalize_item_name(v_requested_item.item_name))
        and public.normalize_item_type(i.item_type) = public.normalize_item_type(v_requested_item.item_type)
      and i.rarity = v_requested_item.rarity
      and coalesce(i.enchantment, '') = coalesce(v_requested_item.enchantment, '')
      and coalesce(i.rune_name, '') = coalesce(v_requested_item.rune_name, '')
      and coalesce(i.material, '') = coalesce(v_requested_item.material, '')
      and coalesce(i.potion_strength, '') = coalesce(v_requested_item.potion_strength, '')
      and coalesce(i.potion_property, '') = coalesce(v_requested_item.potion_property, '')
      and coalesce(i.potion_quality, '') = coalesce(v_requested_item.potion_quality, '')
      and i.enhancement_count = v_requested_item.enhancement_count
      and i.is_two_handed = v_requested_item.is_two_handed
      and i.is_accessory = v_requested_item.is_accessory
      and i.modifiers = v_requested_item.modifiers
      and i.is_storage = false
      and v_requested_item.is_storage = false
      and public.item_catalog_stackable(v_requested_item.item_name, v_requested_item.item_type)
    order by i.slot_index
    limit 1;

    if v_sender_target_item.id is not null then
      update public.inventory_items
      set quantity = quantity + v_trade.requested_quantity
      where id = v_sender_target_item.id;
    else
      v_sender_slot_index := public.find_first_free_inventory_slot(v_sender_character.id, null::uuid, v_sender_character.inventory_slots);
      if v_sender_slot_index is null then raise exception 'Offering character inventory is full.'; end if;

      insert into public.inventory_items (
        character_id,
        parent_item_id,
        slot_index,
        item_name,
        display_name,
        item_description,
        item_type,
        rarity,
        quantity,
        is_accessory,
        is_storage,
        storage_capacity,
        modifiers,
        enchantment,
        rune_name,
        material,
        enhancement_count,
        is_two_handed,
        potion_strength,
        potion_property,
        potion_quality
      )
      values (
        v_sender_character.id,
        null,
        v_sender_slot_index,
        v_requested_item.item_name,
        v_requested_item.display_name,
        v_requested_item.item_description,
        v_requested_item.item_type,
        v_requested_item.rarity,
        v_trade.requested_quantity,
        v_requested_item.is_accessory,
        false,
        0,
        v_requested_item.modifiers,
        v_requested_item.enchantment,
        v_requested_item.rune_name,
        v_requested_item.material,
        v_requested_item.enhancement_count,
        v_requested_item.is_two_handed,
        v_requested_item.potion_strength,
        v_requested_item.potion_property,
        v_requested_item.potion_quality
      );
    end if;

    if v_trade.requested_quantity >= v_requested_item.quantity then
      delete from public.inventory_items where id = v_requested_item.id;
    else
      update public.inventory_items
      set quantity = quantity - v_trade.requested_quantity
      where id = v_requested_item.id;
    end if;
    end if;
  end if;

  if v_next_status = 'accepted' then
    perform public.transfer_trade_currency(v_sender_character.id, v_target_character.id, v_trade.offered_currency);
    perform public.transfer_trade_currency(v_target_character.id, v_sender_character.id, v_trade.requested_currency);
  end if;

  update public.trade_offers
  set status = v_next_status
  where id = v_trade.id
  returning * into v_trade;

  update public.campaign_notifications
  set read_at = now()
  where source_type = 'trade'
    and source_id = v_trade.id
    and recipient_user_id = v_profile.id
    and read_at is null;

  v_notify_user := case when v_profile.id = v_trade.sender_user_id then v_trade.recipient_user_id else v_trade.sender_user_id end;
  v_title := case
    when v_next_status = 'accepted' then 'Trade accepted'
    when v_next_status = 'declined' then 'Trade declined'
    else 'Trade cancelled'
  end;

  insert into public.campaign_notifications (
    recipient_user_id,
    title,
    body,
    notice_kind,
    source_type,
    source_id
  )
  values (
    v_notify_user,
    v_title,
    coalesce((select c.name from public.characters c where c.id = v_trade.sender_character_id), 'A character') ||
      ' and ' ||
      coalesce((select c.name from public.characters c where c.id = v_trade.target_character_id), 'another character') ||
      ' now have a trade marked ' || v_next_status || '.',
    'trade',
    'trade',
    v_trade.id
  );

  return public.trade_offer_record_to_json(v_trade);
end;
$$;

grant execute on function public.notification_record_to_json(public.campaign_notifications) to anon, authenticated;
grant execute on function public.trade_offer_record_to_json(public.trade_offers) to anon, authenticated;
grant execute on function public.daily_reward_today() to anon, authenticated;
grant execute on function public.daily_reward_week_start(date) to anon, authenticated;
grant execute on function public.currency_unit_record_to_json(public.currency_units) to anon, authenticated;
grant execute on function public.daily_reward_entry_to_json(date, public.profiles) to anon, authenticated;
grant execute on function public.get_daily_rewards(text) to anon, authenticated;
grant execute on function public.update_daily_reward_schedule(text, jsonb) to anon, authenticated;
grant execute on function public.claim_daily_reward(text, date, uuid) to anon, authenticated;
grant execute on function public.mark_notification_read(text, uuid) to anon, authenticated;
grant execute on function public.create_campaign_announcement(text, text, text, text, boolean) to anon, authenticated;
grant execute on function public.get_trade_offers(text) to anon, authenticated;
grant execute on function public.assert_trade_currency_available(uuid, jsonb) to anon, authenticated;
grant execute on function public.transfer_trade_currency(uuid, uuid, jsonb) to anon, authenticated;
grant execute on function public.move_inventory_storage_tree_to_character(uuid, uuid) to anon, authenticated;
grant execute on function public.transfer_trade_inventory_item(uuid, uuid, uuid, numeric) to anon, authenticated;
grant execute on function public.create_trade_offer(text, uuid, uuid, text, text, text, uuid, numeric, uuid, numeric, jsonb, jsonb, jsonb, jsonb) to anon, authenticated;
grant execute on function public.gift_inventory_item(text, uuid, uuid, numeric) to anon, authenticated;
grant execute on function public.update_trade_offer_status(text, uuid, text) to anon, authenticated;


-- ============================================================
-- ============================================================

-- DM update assets foundation.

create or replace function public.require_dm_profile(p_session_token text)
returns public.profiles
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;
  if v_profile.role <> 'dm'::public.user_role then raise exception 'Only the Dungeon Master can update campaign assets.'; end if;
  return v_profile;
end;
$$;

create or replace function public.get_update_assets(p_session_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
begin
  v_profile := public.require_dm_profile(p_session_token);

  return jsonb_build_object(
    'classes', (
      select coalesce(jsonb_agg(public.class_template_record_to_json(t) order by t.name), '[]'::jsonb)
      from public.class_templates t
    ),
    'cities', (
      select coalesce(jsonb_agg(public.city_record_to_json(c) order by c.display_order, c.name), '[]'::jsonb)
      from public.cities c
    ),
    'vendors', (
      select coalesce(jsonb_agg(public.shop_vendor_record_to_json(v, true) order by v.city_key, v.display_order, v.name), '[]'::jsonb)
      from public.shop_vendors v
    ),
    'itemCatalog', (
      select coalesce(jsonb_agg(public.catalog_record_to_json(i) order by i.category, i.display_order, i.item_name), '[]'::jsonb)
      from public.item_catalog i
    ),
    'spells', (
      select coalesce(jsonb_agg(public.spell_record_to_json(s) order by s.display_order, s.name), '[]'::jsonb)
      from public.spell_catalog s
    ),
    'lootPools', (
      select coalesce(jsonb_agg(public.loot_pool_record_to_json(p) order by p.display_order, p.name), '[]'::jsonb)
      from public.loot_pools p
    ),
    'lootItems', (
      select coalesce(jsonb_agg(public.loot_item_record_to_json(i) order by i.item_name), '[]'::jsonb)
      from public.loot_items i
    ),
    'bestiary', (
      select coalesce(jsonb_agg(public.bestiary_entity_record_to_json(e) order by e.category, e.display_order, e.name), '[]'::jsonb)
      from public.bestiary_entities e
    )
  );
end;
$$;

create or replace function public.update_class_template_asset(
  p_session_token text,
  p_class_id uuid,
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
  v_template public.class_templates%rowtype;
  v_apply boolean := coalesce((v_patch->>'applyToCharacters')::boolean, false);
begin
  v_profile := public.require_dm_profile(p_session_token);

  update public.class_templates
  set
    name = case when v_patch ? 'name' then coalesce(nullif(trim(v_patch->>'name'), ''), name) else name end,
    role = case when v_patch ? 'role' then coalesce(v_patch->>'role', '') else role end,
    armor = case when v_patch ? 'armor' then coalesce(v_patch->>'armor', '') else armor end,
    identity = case when v_patch ? 'identity' then coalesce(v_patch->>'identity', '') else identity end,
    base_hp = case when v_patch ? 'baseHp' then greatest(0, (v_patch->>'baseHp')::int) else base_hp end,
    base_mana = case when v_patch ? 'baseMana' then greatest(0, (v_patch->>'baseMana')::int) else base_mana end,
    base_magic_resist = case when v_patch ? 'baseMagicResist' then greatest(0, (v_patch->>'baseMagicResist')::int) else base_magic_resist end,
    inventory_slots = case when v_patch ? 'inventorySlots' then least(120, greatest(0, (v_patch->>'inventorySlots')::int)) else inventory_slots end,
    spell_slots = case when v_patch ? 'spellSlots' then greatest(0, (v_patch->>'spellSlots')::int) else spell_slots end,
    attributes = case when v_patch ? 'attributes' and jsonb_typeof(v_patch->'attributes') = 'object' then v_patch->'attributes' else attributes end,
    passives = case when v_patch ? 'passives' and jsonb_typeof(v_patch->'passives') = 'array' then v_patch->'passives' else passives end,
    token_color = case when v_patch ? 'tokenColor' then coalesce(nullif(trim(v_patch->>'tokenColor'), ''), token_color) else token_color end
  where id = p_class_id
  returning * into v_template;

  if v_template.id is null then raise exception 'Class template was not found.'; end if;

  if v_apply then
    update public.characters
    set class_name = v_template.name,
        max_hp = v_template.base_hp,
        current_hp = least(current_hp, v_template.base_hp),
        max_mana = v_template.base_mana,
        current_mana = least(current_mana, v_template.base_mana),
        magic_resist = v_template.base_magic_resist,
        inventory_slots = v_template.inventory_slots,
        spell_slots = v_template.spell_slots,
        attributes = v_template.attributes,
        class_passives = v_template.passives,
        token_color = v_template.token_color
    where class_template_id = v_template.id;
  end if;

  return public.get_update_assets(p_session_token);
end;
$$;

create or replace function public.update_spell_asset(
  p_session_token text,
  p_spell_id uuid,
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
  v_profile := public.require_dm_profile(p_session_token);

  update public.spell_catalog
  set
    name = case when v_patch ? 'name' then coalesce(nullif(trim(v_patch->>'name'), ''), name) else name end,
    school = case when v_patch ? 'school' then coalesce(nullif(v_patch->>'school', ''), school) else school end,
    spell_type = case
      when v_patch ? 'type' and v_patch->>'type' in ('Ember', 'Frost', 'Lightning', 'Earth', 'Wind', 'Energy', 'Defensive Support', 'Offensive Support', 'Enhancement', 'Utility') then v_patch->>'type'
      else spell_type
    end,
    mana_cost = case when v_patch ? 'manaCost' then greatest(0, (v_patch->>'manaCost')::int) else mana_cost end,
    mana_label = case
      when v_patch ? 'manaLabel' then coalesce(
        nullif(trim(v_patch->>'manaLabel'), ''),
        (case when v_patch ? 'manaCost' then greatest(0, (v_patch->>'manaCost')::int) else mana_cost end)::text || ' mana'
      )
      else mana_label
    end,
    summary = case when v_patch ? 'summary' then coalesce(v_patch->>'summary', '') else summary end,
    details = case when v_patch ? 'details' then coalesce(v_patch->>'details', '') else details end,
    rarity = case when v_patch ? 'rarity' then (v_patch->>'rarity')::public.item_rarity else rarity end,
    is_available = case when v_patch ? 'available' then (v_patch->>'available')::boolean else is_available end
  where id = p_spell_id;

  if not found then raise exception 'Spell was not found.'; end if;

  return public.get_update_assets(p_session_token);
end;
$$;

create or replace function public.update_item_catalog_asset(
  p_session_token text,
  p_item_id uuid,
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
  v_profile := public.require_dm_profile(p_session_token);

  update public.item_catalog
  set
    item_name = case when v_patch ? 'name' then coalesce(nullif(trim(v_patch->>'name'), ''), item_name) else item_name end,
    item_key = case when v_patch ? 'name' then public.catalog_key_for_name(coalesce(nullif(trim(v_patch->>'name'), ''), item_name)) else item_key end,
    item_type = case when v_patch ? 'type' then public.normalize_item_type(v_patch->>'type') else item_type end,
    rarity = case when v_patch ? 'rarity' then (v_patch->>'rarity')::public.item_rarity else rarity end,
    category = case when v_patch ? 'category' then coalesce(nullif(trim(v_patch->>'category'), ''), 'General') else category end,
    properties = case when v_patch ? 'properties' and jsonb_typeof(v_patch->'properties') = 'array' then (
      select coalesce(array_agg(nullif(trim(value), '')), array[]::text[])
      from jsonb_array_elements_text(v_patch->'properties') as value
      where nullif(trim(value), '') is not null
    ) else properties end,
    quantity_step = case when v_patch ? 'quantityStep' and (v_patch->>'quantityStep')::numeric = 0.5 then 0.5 when v_patch ? 'quantityStep' then 1 else quantity_step end,
    is_stackable = case when v_patch ? 'stackable' then (v_patch->>'stackable')::boolean else is_stackable end,
    default_modifiers = case when v_patch ? 'defaultModifiers' and jsonb_typeof(v_patch->'defaultModifiers') = 'object' then v_patch->'defaultModifiers' else default_modifiers end,
    material = case when v_patch ? 'material' then trim(coalesce(v_patch->>'material', '')) else material end,
    is_two_handed = case when v_patch ? 'isTwoHanded' then (v_patch->>'isTwoHanded')::boolean else is_two_handed end,
    storage_capacity = case when v_patch ? 'storageCapacity' then greatest(0, (v_patch->>'storageCapacity')::int) else storage_capacity end,
    notes = case when v_patch ? 'notes' then coalesce(v_patch->>'notes', '') else notes end,
    is_active = case when v_patch ? 'active' then (v_patch->>'active')::boolean else is_active end
  where id = p_item_id;

  if not found then raise exception 'Catalog item was not found.'; end if;

  return public.get_update_assets(p_session_token);
end;
$$;

create or replace function public.update_loot_item_asset(
  p_session_token text,
  p_loot_item_id uuid,
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
  v_min numeric;
  v_max numeric;
begin
  v_profile := public.require_dm_profile(p_session_token);

  select
    case when v_patch ? 'minQuantity' then greatest(0.5, (v_patch->>'minQuantity')::numeric) else min_quantity end,
    case when v_patch ? 'maxQuantity' then greatest(0.5, (v_patch->>'maxQuantity')::numeric) else max_quantity end
  into v_min, v_max
  from public.loot_items
  where id = p_loot_item_id;

  if v_min is null then raise exception 'Loot item was not found.'; end if;
  if v_max < v_min then v_max := v_min; end if;

  update public.loot_items
  set
    item_name = case when v_patch ? 'name' then coalesce(nullif(trim(v_patch->>'name'), ''), item_name) else item_name end,
    item_type = case when v_patch ? 'type' then public.normalize_item_type(v_patch->>'type') else item_type end,
    rarity = case when v_patch ? 'rarity' then (v_patch->>'rarity')::public.item_rarity else rarity end,
    generator_biomes = case
      when v_patch ? 'biomes' and jsonb_typeof(v_patch->'biomes') = 'array' then (
        select coalesce(array_agg(nullif(trim(value), '')), array['Any']::text[])
        from jsonb_array_elements_text(v_patch->'biomes') as value
      )
      when v_patch ? 'biomesText' then (
        select coalesce(array_agg(nullif(trim(value), '')), array['Any']::text[])
        from regexp_split_to_table(coalesce(v_patch->>'biomesText', 'Any'), ',') as value
      )
      else generator_biomes
    end,
    difficulty_min = case when v_patch ? 'minDifficulty' then greatest(1, (v_patch->>'minDifficulty')::int) else difficulty_min end,
    difficulty_max = case
      when v_patch ? 'maxDifficulty' then greatest(greatest(1, (v_patch->>'maxDifficulty')::int), case when v_patch ? 'minDifficulty' then greatest(1, (v_patch->>'minDifficulty')::int) else difficulty_min end)
      when v_patch ? 'minDifficulty' then greatest(difficulty_max, greatest(1, (v_patch->>'minDifficulty')::int))
      else difficulty_max
    end,
    loot_weight = case when v_patch ? 'weight' then greatest(0, (v_patch->>'weight')::numeric) else loot_weight end,
    tower_base_only = case when v_patch ? 'towerBaseOnly' then (v_patch->>'towerBaseOnly')::boolean else tower_base_only end,
    is_stackable = case when v_patch ? 'stackable' then (v_patch->>'stackable')::boolean else is_stackable end,
    min_quantity = v_min,
    max_quantity = v_max,
    notes = case when v_patch ? 'notes' then coalesce(v_patch->>'notes', '') else notes end,
    is_active = case when v_patch ? 'active' then (v_patch->>'active')::boolean else is_active end
  where id = p_loot_item_id;

  return public.get_update_assets(p_session_token);
end;
$$;

grant execute on function public.require_dm_profile(text) to anon, authenticated;
grant execute on function public.get_update_assets(text) to anon, authenticated;
grant execute on function public.update_class_template_asset(text, uuid, jsonb) to anon, authenticated;
grant execute on function public.update_item_catalog_asset(text, uuid, jsonb) to anon, authenticated;
grant execute on function public.update_spell_asset(text, uuid, jsonb) to anon, authenticated;
grant execute on function public.update_loot_item_asset(text, uuid, jsonb) to anon, authenticated;


-- Workbook-backed loot generator.

create table if not exists public.exploration_cave_nicknames (
  cave_number int primary key check (cave_number between 1 and 999),
  nickname text not null default '',
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now()
);

alter table public.exploration_cave_nicknames enable row level security;
revoke all on public.exploration_cave_nicknames from anon, authenticated;

drop trigger if exists exploration_cave_nicknames_touch_updated_at on public.exploration_cave_nicknames;
create trigger exploration_cave_nicknames_touch_updated_at
before update on public.exploration_cave_nicknames
for each row execute function public.touch_updated_at();

create or replace function public.get_exploration_cave_nicknames(p_session_token text)
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
  if v_profile.role <> 'dm'::public.user_role then raise exception 'Only the Dungeon Master can use cave tools.'; end if;

  return jsonb_build_object(
    'nicknames', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'caveNumber', cave_number,
        'nickname', nickname,
        'updatedAt', updated_at
      ) order by cave_number), '[]'::jsonb)
      from public.exploration_cave_nicknames
      where length(trim(nickname)) > 0
    )
  );
end;
$$;

create or replace function public.set_exploration_cave_nickname(
  p_session_token text,
  p_cave_number int,
  p_nickname text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_nickname text := left(trim(coalesce(p_nickname, '')), 80);
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;
  if v_profile.role <> 'dm'::public.user_role then raise exception 'Only the Dungeon Master can rename caves.'; end if;
  if p_cave_number < 1 or p_cave_number > 999 then raise exception 'Cave number is invalid.'; end if;

  if length(v_nickname) = 0 then
    delete from public.exploration_cave_nicknames where cave_number = p_cave_number;
  else
    insert into public.exploration_cave_nicknames (cave_number, nickname, updated_by)
    values (p_cave_number, v_nickname, v_profile.id)
    on conflict (cave_number) do update
      set nickname = excluded.nickname,
          updated_by = excluded.updated_by,
          updated_at = now();
  end if;

  return jsonb_build_object(
    'caveNumber', p_cave_number,
    'nickname', v_nickname
  );
end;
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
  from public.loot_workbook_settings
  where id = 'default';

  return jsonb_build_object(
    'characters', (
      select coalesce(jsonb_agg(
        public.character_record_to_json(c)
        || jsonb_build_object(
          'inventoryOpenSlots',
          greatest(
            c.inventory_slots - (
              select count(*)::int
              from public.inventory_items i
              where i.character_id = c.id
                and i.parent_item_id is null
                and i.loadout_slot is null
                and i.slot_index >= 0
                and i.slot_index < c.inventory_slots
            ),
            0
          )
        )
        order by c.name
      ), '[]'::jsonb)
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
    'settings', coalesce(v_settings, jsonb_build_object(
      'biomes', jsonb_build_array('Any', 'Caves', 'Goblins', 'Elven', 'Volcano', 'Mountains', 'Snow', 'Voidlands'),
      'difficulties', jsonb_build_array(1, 2, 3, 4, 5),
      'poolSizes', jsonb_build_array('Night Encounter', 'Small Cave', 'Medium Cave', 'Large Cave', 'Dragon Lair', 'Tower Floor', 'Base'),
      'roomTypes', jsonb_build_array('Normal', 'Secret Room', 'Tower Boss Room'),
      'luckPotionOptions', jsonb_build_array('None', 'Lesser', 'Greater', 'Greatest'),
      'baseRollsByPoolSize', jsonb_build_object('Night Encounter', 5, 'Small Cave', 10, 'Medium Cave', 15, 'Large Cave', 20, 'Dragon Lair', 50, 'Tower Floor', 25, 'Base', 50),
      'poolMultipliers', jsonb_build_object('Large Cave', 1.33, 'Dragon Lair', 5, 'Tower Floor', 2, 'Base', 2),
      'roomMultipliers', jsonb_build_object('Secret Room', 2, 'Tower Boss Room', 2),
      'luckPotionMultipliers', jsonb_build_object(
        'None', jsonb_build_object('legendary', 1, 'mythical', 1),
        'Lesser', jsonb_build_object('legendary', 2, 'mythical', 2),
        'Greater', jsonb_build_object('legendary', 3, 'mythical', 3),
        'Greatest', jsonb_build_object('legendary', 3, 'mythical', 5)
      ),
      'rareBoostRarities', jsonb_build_array('Rare', 'Epic', 'Legendary', 'Mythical'),
      'sourceFormulas', '{}'::jsonb
    ))
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
  v_replace boolean := true;
  v_row jsonb;
  v_pool_key text;
  v_pool_name text;
  v_pool public.loot_pools%rowtype;
  v_name text;
  v_type_text text;
  v_rarity_text text;
  v_biomes text[];
  v_min_quantity numeric;
  v_max_quantity numeric;
  v_stackable boolean;
  v_convertible boolean;
  v_convert_scale_item_name text;
  v_convert_scale_quantity numeric;
  v_conversion_material text;
  v_dragon_scale_fragment boolean;
  v_can_be_enhanced boolean;
  v_can_be_enchanted boolean;
  v_notes text;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;
  if v_profile.role <> 'dm'::public.user_role then raise exception 'Only the Dungeon Master can import the item catalog.'; end if;

  if jsonb_typeof(v_payload) = 'object' then
    v_rows := coalesce(v_payload->'rows', '[]'::jsonb);
    v_settings := v_payload->'settings';
    v_source := coalesce(v_payload->'source', '{}'::jsonb);
    v_replace := coalesce((v_payload->>'replace')::boolean, true);
  else
    v_rows := v_payload;
    v_settings := null;
    v_source := '{}'::jsonb;
  end if;

  if v_settings is not null then
    insert into public.loot_workbook_settings (id, settings, source, imported_at)
    values ('default', v_settings, v_source, now())
    on conflict (id) do update
    set settings = excluded.settings,
        source = excluded.source,
        imported_at = excluded.imported_at;
  end if;

  if v_replace then
    delete from public.loot_items where true;
    delete from public.loot_pools where true;
  end if;

  for v_row in select * from jsonb_array_elements(coalesce(v_rows, '[]'::jsonb)) loop
    v_name := nullif(trim(coalesce(v_row->>'name', v_row->>'item', v_row->>'item_name', '')), '');
    if v_name is null then
      continue;
    end if;
    if lower(v_name) = 'mountian rune' then
      v_name := 'Mountain Rune';
    end if;

    v_type_text := public.normalize_item_type(coalesce(nullif(v_row->>'type', ''), nullif(v_row->>'item_type', ''), 'misc'));
    if lower(v_name) like '% rune' then
      v_type_text := 'rune';
    end if;

    v_pool_key := lower(regexp_replace(coalesce(v_row->>'poolKey', v_row->>'pool_key', v_row->>'pool', 'catalog-' || v_type_text), '[^a-z0-9]+', '-', 'g'));
    v_pool_name := coalesce(nullif(trim(v_row->>'pool'), ''), initcap(replace(v_pool_key, '-', ' ')));

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

    v_min_quantity := greatest(case when v_type_text in ('material', 'ore') then 0.5 else 1 end, coalesce(nullif(v_row->>'minQuantity', '')::numeric, nullif(v_row->>'min_quantity', '')::numeric, nullif(v_row->>'min', '')::numeric, 1));
    v_max_quantity := greatest(v_min_quantity, case when v_type_text in ('material', 'ore') then 0.5 else 1 end, coalesce(nullif(v_row->>'maxQuantity', '')::numeric, nullif(v_row->>'max_quantity', '')::numeric, nullif(v_row->>'max', '')::numeric, v_min_quantity));
    v_stackable := case lower(trim(coalesce(v_row->>'stackable', v_row->>'isStackable', v_row->>'is_stackable', '')))
      when 'false' then false
      when 'no' then false
      when '0' then false
      when 'true' then true
      when 'yes' then true
      when '1' then true
      else true
    end;
    v_convertible := case lower(trim(coalesce(v_row->>'convertible', v_row->>'isConvertible', v_row->>'is_convertible', '')))
      when 'true' then true
      when 'yes' then true
      when '1' then true
      else false
    end;
    v_convert_scale_item_name := public.normalize_item_name(coalesce(nullif(v_row->>'convertScaleItem', ''), nullif(v_row->>'convert_scale_item', ''), nullif(v_row->>'convertMaterial', ''), nullif(v_row->>'convert_material', ''), ''));
    v_convert_scale_quantity := coalesce(nullif(v_row->>'convertScaleNumber', '')::numeric, nullif(v_row->>'convert_scale_number', '')::numeric, nullif(v_row->>'convertScaleQuantity', '')::numeric, nullif(v_row->>'convert_scale_quantity', '')::numeric, 0);
    if v_convertible and (v_convert_scale_item_name = '' or v_convert_scale_quantity <= 0) then
      v_conversion_material := case
        when lower(v_name) like 'dragonscale %' then 'Dragonscale'
        when lower(v_name) like 'vaylium %' then 'Vaylium'
        when lower(v_name) like 'mythril %' then 'Mythril'
        when lower(v_name) like 'steel %' then 'Steel'
        when lower(v_name) like 'iron %' then 'Iron'
        else ''
      end;
      if v_convert_scale_item_name = '' and v_conversion_material <> '' then
        v_convert_scale_item_name := v_conversion_material || ' Scale';
      end if;
      if v_convert_scale_quantity <= 0 then
        v_convert_scale_quantity := case
          when lower(v_name) like '%dagger%' then 0.5
          when lower(v_name) like '%battleaxe%' or lower(v_name) like '%mace%' then 2
          when lower(v_name) like '%armor%' then 3
          else 1
        end;
      end if;
    end if;
    v_dragon_scale_fragment := case lower(trim(coalesce(v_row->>'canForgeDragonscaleScale', v_row->>'can_forge_dragonscale_scale', v_row->>'dragonScaleFragment', v_row->>'dragon_scale_fragment', '')))
      when 'true' then true
      when 'yes' then true
      when '1' then true
      else false
    end;
    v_can_be_enhanced := case lower(trim(coalesce(v_row->>'canBeEnhanced', v_row->>'can_be_enhanced', v_row->>'enhanceable', '')))
      when 'true' then true
      when 'yes' then true
      when '1' then true
      else false
    end;
    v_can_be_enchanted := case lower(trim(coalesce(v_row->>'canBeEnchanted', v_row->>'can_be_enchanted', v_row->>'enchantable', '')))
      when 'true' then true
      when 'yes' then true
      when '1' then true
      else false
    end;
    v_notes := coalesce(v_row->>'notes', '');

    insert into public.loot_pools (pool_key, name, description, display_order)
    values (v_pool_key, v_pool_name, 'Imported item catalog group.', 100)
    on conflict (pool_key) do update
    set name = excluded.name,
        description = excluded.description
    returning * into v_pool;

    insert into public.loot_items (
      pool_id,
      item_name,
      item_type,
      rarity,
      generator_biomes,
      difficulty_min,
      difficulty_max,
      loot_weight,
      tower_base_only,
      is_stackable,
      min_quantity,
      max_quantity,
      notes,
      is_active
    )
    values (
      v_pool.id,
      v_name,
      v_type_text,
      v_rarity_text::public.item_rarity,
      v_biomes,
      greatest(1, coalesce(nullif(v_row->>'minDifficulty', '')::int, nullif(v_row->>'min_difficulty', '')::int, 1)),
      greatest(greatest(1, coalesce(nullif(v_row->>'minDifficulty', '')::int, nullif(v_row->>'min_difficulty', '')::int, 1)), coalesce(nullif(v_row->>'maxDifficulty', '')::int, nullif(v_row->>'max_difficulty', '')::int, 5)),
      greatest(0, coalesce(nullif(v_row->>'weight', '')::numeric, nullif(v_row->>'lootWeight', '')::numeric, nullif(v_row->>'loot_weight', '')::numeric, 1)),
      coalesce((v_row->>'towerBaseOnly')::boolean, false),
      v_stackable,
      v_min_quantity,
      v_max_quantity,
      v_notes,
      true
    );

    perform public.upsert_item_catalog_entry(
      v_name,
      v_type_text,
      v_rarity_text,
      v_pool_name,
      array[]::text[],
      public.item_quantity_step(v_name, v_type_text),
      v_stackable,
      '{}'::jsonb,
      case
        when v_convert_scale_item_name <> '' then regexp_replace(v_convert_scale_item_name, '\s+Scale$', '', 'i')
        when lower(v_name) like 'dragonscale %' then 'Dragonscale'
        when lower(v_name) like 'vaylium %' then 'Vaylium'
        when lower(v_name) like 'mythril %' then 'Mythril'
        when lower(v_name) like 'steel %' then 'Steel'
        when lower(v_name) like 'iron %' then 'Iron'
        else ''
      end,
      false,
      case when v_type_text = 'storage' then public.catalog_storage_capacity(v_name) else 0 end,
      v_notes,
      true,
      100,
      v_can_be_enhanced,
      v_can_be_enchanted
    );

    update public.item_catalog
    set can_be_enhanced = v_can_be_enhanced,
        can_be_enchanted = v_can_be_enchanted,
        material = case
          when v_convert_scale_item_name <> '' then regexp_replace(v_convert_scale_item_name, '\s+Scale$', '', 'i')
          when lower(v_name) like 'dragonscale %' then 'Dragonscale'
          when lower(v_name) like 'vaylium %' then 'Vaylium'
          when lower(v_name) like 'mythril %' then 'Mythril'
          when lower(v_name) like 'steel %' then 'Steel'
          when lower(v_name) like 'iron %' then 'Iron'
          else material
        end,
        is_stackable = v_stackable,
        quantity_step = public.item_quantity_step(v_name, v_type_text)
    where item_key = public.catalog_key_for_name(v_name);

    if v_convertible and v_convert_scale_item_name <> '' and v_convert_scale_quantity > 0 then
      v_conversion_material := regexp_replace(v_convert_scale_item_name, '\s+Scale$', '', 'i');
      perform public.upsert_material_conversion_recipe(
        v_name,
        v_name,
        v_type_text,
        v_rarity_text,
        v_conversion_material,
        v_convert_scale_item_name,
        v_convert_scale_quantity,
        100
      );
    end if;

    if v_dragon_scale_fragment then
      perform public.upsert_dragon_scale_fragment(v_name, v_type_text, v_rarity_text, 100);
    end if;
  end loop;

  return public.get_exploration_state(p_session_token);
end;
$$;



do $$
declare
  v_loot public.loot_items%rowtype;
  v_pool_name text;
begin
  for v_loot in select * from public.loot_items where is_active loop
    select name into v_pool_name from public.loot_pools where id = v_loot.pool_id;
    perform public.upsert_item_catalog_entry(
      v_loot.item_name,
      v_loot.item_type,
      v_loot.rarity::text,
      coalesce(v_pool_name, 'Loot Catalog'),
      array[]::text[],
      public.item_quantity_step(v_loot.item_name, v_loot.item_type),
      v_loot.is_stackable,
      '{}'::jsonb,
      '',
      false,
      case when v_loot.item_type = 'storage' then public.catalog_storage_capacity(v_loot.item_name) else 0 end,
      v_loot.notes,
      true,
      100
    );
  end loop;
end $$;

drop function if exists public.cleanup_existing_unstackable_item_stacks();

drop function if exists public.award_exploration_loot_item(text, uuid, uuid, int);
drop function if exists public.award_exploration_loot_item(text, uuid, uuid, integer);

create or replace function public.award_exploration_loot_item(
  p_session_token text,
  p_character_id uuid,
  p_loot_item_id uuid,
  p_quantity numeric default 1
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
  v_catalog public.item_catalog%rowtype;
  v_currency_unit public.currency_units%rowtype;
  v_currency_key text;
  v_slot int;
  v_inventory_quantity numeric;
  v_modifiers jsonb := '{}'::jsonb;
  v_material text := '';
  v_is_two_handed boolean := false;
  v_storage_capacity int := 0;
  v_storage_item public.inventory_items%rowtype;
  v_target public.inventory_items%rowtype;
  v_item public.inventory_items%rowtype;
  v_quantity numeric := greatest(0.5, coalesce(p_quantity, 1));
  v_item_name text;
  v_item_type text;
  v_rarity public.item_rarity;
  v_potion_strength text;
  v_potion_property text;
  v_potion_quality text;
  v_has_open_inventory_slot boolean := false;
  v_storage_kind text;
  v_storage_active boolean := false;
  v_storage_slot int;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;
  if v_profile.role <> 'dm'::public.user_role then raise exception 'Only the Dungeon Master can give generated loot.'; end if;

  v_character := public.assert_inventory_access(v_profile, p_character_id, true);

  select * into v_loot from public.loot_items where id = p_loot_item_id and is_active;
  if v_loot.id is null then raise exception 'Loot item not found.'; end if;

  v_item_name := public.normalize_item_name(v_loot.item_name);
  v_item_type := public.normalize_item_type(v_loot.item_type);
  v_rarity := v_loot.rarity;

  if v_item_type = 'potion' then
    v_potion_strength := public.potion_strength_from_name(v_item_name);
    v_potion_property := public.potion_property_from_name(v_item_name);
    v_potion_quality := case
      when v_potion_property in ('Healing', 'Mana Regen') then null
      when lower(v_item_name) = 'empty flask' then null
      else public.potion_quality_from_name(v_item_name)
    end;
    if v_potion_strength is not null and v_potion_property is not null then
      v_item_name := public.format_potion_item_name(v_potion_strength, v_potion_property, v_potion_quality);
      v_rarity := public.potion_rarity_for(v_potion_strength, v_potion_property);
    elsif lower(v_item_name) = 'arcane nector' then
      v_rarity := 'Uncommon'::public.item_rarity;
    elsif lower(v_item_name) = 'empty flask' then
      v_rarity := 'Common'::public.item_rarity;
    end if;
  end if;

  select * into v_catalog
  from public.item_catalog
  where item_key = public.catalog_key_for_name(v_item_name)
  limit 1;

  v_quantity := public.assert_valid_item_quantity(v_item_name, v_item_type, v_quantity);
  if v_item_type = 'storage'::text then
    v_quantity := 1;
  end if;
  if v_catalog.id is not null then
    v_modifiers := v_catalog.default_modifiers;
    v_material := v_catalog.material;
    v_is_two_handed := v_catalog.is_two_handed;
    v_storage_capacity := v_catalog.storage_capacity;
  end if;

  if public.is_currency_loot_item(v_loot) then
    v_currency_key := case lower(v_item_name)
      when 'coin' then 'coin'
      when 'callis' then 'callis'
      when 'callor' then 'callor'
      when 'cal' then 'cal'
      else null
    end;

    if v_currency_key is null then
      raise exception 'Currency loot item is missing a matching wallet unit.';
    end if;

    select * into v_currency_unit
    from public.currency_units
    where unit_key = v_currency_key;

    if v_currency_unit.id is null then
      raise exception 'Currency unit % was not found.', v_currency_key;
    end if;

    insert into public.character_wallet_balances (character_id, currency_unit_id, amount)
    values (v_character.id, v_currency_unit.id, v_quantity::int)
    on conflict (character_id, currency_unit_id) do update
    set amount = public.character_wallet_balances.amount + excluded.amount;

    return jsonb_build_object(
      'currency', true,
      'characterId', v_character.id,
      'unitKey', v_currency_unit.unit_key,
      'unitName', v_currency_unit.name,
      'amount', v_quantity
    );
  end if;

  if v_item_type = 'pet' then
    return coalesce(
      public.place_pet_item_for_character(
        v_character.id,
        v_item_name,
        null,
        coalesce(v_loot.notes, ''),
        v_rarity,
        v_quantity,
        false,
        v_modifiers,
        null,
        null,
        v_material,
        0,
        v_is_two_handed
      ),
      jsonb_build_object(
        'petPlaced', 'stable',
        'characterId', v_character.id,
        'name', v_item_name,
        'quantity', 1
      )
    );
  end if;

  v_inventory_quantity := v_quantity;

  if v_item_type = 'storage'::text then
    v_storage_kind := public.additional_storage_kind(v_item_name, v_item_type);
    v_storage_active := v_storage_kind is not null
      and not public.character_storage_container_exists(v_character.id, v_item_name);
    v_storage_slot := case
      when v_storage_active then public.next_storage_container_slot(v_character.id)
      else public.find_first_free_inventory_slot(v_character.id, null, v_character.inventory_slots)
    end;
    if v_storage_slot is null then raise exception 'Inventory full.'; end if;

    insert into public.inventory_items (
      character_id,
      parent_item_id,
      slot_index,
      item_name,
      item_type,
      rarity,
      quantity,
      is_storage,
      storage_active,
      storage_capacity,
      modifiers,
      enchantment,
      material,
      enhancement_count,
      is_two_handed
    )
    values (
      v_character.id,
      null,
      v_storage_slot,
      v_item_name,
      v_item_type,
      v_rarity,
      1,
      true,
      v_storage_active,
      greatest(1, coalesce(nullif(v_storage_capacity, 0), public.catalog_storage_capacity(v_item_name))),
      v_modifiers,
      null,
      v_material,
      0,
      v_is_two_handed
    )
    returning * into v_storage_item;

    v_inventory_quantity := v_inventory_quantity - 1;
  end if;

  if v_inventory_quantity <= 0 then
    return public.inventory_item_record_to_json(v_storage_item);
  end if;

  select * into v_target
  from public.inventory_items i
  where i.character_id = v_character.id
    and i.parent_item_id is null
    and i.loadout_slot is null
    and lower(public.normalize_item_name(i.item_name)) = lower(public.normalize_item_name(v_item_name))
    and public.normalize_item_type(i.item_type) = public.normalize_item_type(v_item_type)
    and i.rarity = v_rarity
    and i.is_storage = false
    and coalesce(i.enchantment, '') = ''
    and coalesce(i.material, '') = coalesce(v_material, '')
    and coalesce(i.potion_strength, '') = coalesce(v_potion_strength, '')
    and coalesce(i.potion_property, '') = coalesce(v_potion_property, '')
    and coalesce(i.potion_quality, '') = coalesce(v_potion_quality, '')
    and i.enhancement_count = 0
    and i.is_two_handed = v_is_two_handed
    and public.item_catalog_stackable(v_item_name, v_item_type)
  order by i.slot_index
  limit 1;

  if v_target.id is not null then
    update public.inventory_items
    set quantity = quantity + v_inventory_quantity
    where id = v_target.id
    returning * into v_item;
  else
    v_has_open_inventory_slot := public.find_first_free_inventory_slot(v_character.id, null, v_character.inventory_slots) is not null;
    if not v_has_open_inventory_slot then
      raise exception 'Inventory full.';
    end if;

    v_slot := public.find_first_free_inventory_slot(v_character.id, null, v_character.inventory_slots);
    if v_slot is null then raise exception 'Inventory full.'; end if;

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
      enchantment,
      material,
      enhancement_count,
      is_two_handed,
      potion_strength,
      potion_property,
      potion_quality
    )
    values (
      v_character.id,
      null,
      v_slot,
      v_item_name,
      v_item_type,
      v_rarity,
      v_inventory_quantity,
      false,
      0,
      v_modifiers,
      null,
      v_material,
      0,
      v_is_two_handed,
      v_potion_strength,
      v_potion_property,
      v_potion_quality
    )
    returning * into v_item;
  end if;

  return public.inventory_item_record_to_json(v_item);
end;
$$;

create table if not exists public.world_map_uploads (
  id uuid primary key default gen_random_uuid(),
  uploaded_by uuid references public.profiles(id) on delete set null,
  file_name text not null default 'world-map',
  mime_type text not null default 'image/png',
  image_data_url text not null,
  created_at timestamptz not null default now(),
  constraint world_map_uploads_image_only check (mime_type like 'image/%'),
  constraint world_map_uploads_data_url_image check (image_data_url like 'data:image/%')
);

alter table public.world_map_uploads enable row level security;
revoke all on public.world_map_uploads from anon, authenticated;

create table if not exists public.world_map_pins (
  id uuid primary key default gen_random_uuid(),
  map_upload_id uuid not null references public.world_map_uploads(id) on delete cascade,
  created_by uuid references public.profiles(id) on delete set null,
  pin_type text not null,
  x numeric(8,6) not null,
  y numeric(8,6) not null,
  description text not null,
  created_at timestamptz not null default now(),
  constraint world_map_pins_type_valid check (pin_type in ('sword', 'puzzle', 'skull', 'flag', 'plant', 'chest')),
  constraint world_map_pins_x_unit check (x >= 0 and x <= 1),
  constraint world_map_pins_y_unit check (y >= 0 and y <= 1),
  constraint world_map_pins_description_present check (length(trim(description)) > 0)
);

create index if not exists world_map_pins_map_created_idx on public.world_map_pins(map_upload_id, created_at, id);
create index if not exists world_map_pins_created_by_idx on public.world_map_pins(created_by);

alter table public.world_map_pins enable row level security;
revoke all on public.world_map_pins from anon, authenticated;

create or replace function public.world_map_record_to_json(p_map public.world_map_uploads)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'id', p_map.id,
    'fileName', p_map.file_name,
    'mimeType', p_map.mime_type,
    'imageDataUrl', p_map.image_data_url,
    'createdAt', p_map.created_at
  )
$$;

create or replace function public.world_map_pin_record_to_json(p_pin public.world_map_pins)
returns jsonb
language sql
stable
set search_path = public, extensions
as $$
  select jsonb_build_object(
    'id', p_pin.id,
    'mapId', p_pin.map_upload_id,
    'type', p_pin.pin_type,
    'x', p_pin.x,
    'y', p_pin.y,
    'description', p_pin.description,
    'createdBy', p_pin.created_by,
    'createdByName', coalesce((select display_name from public.profiles where id = p_pin.created_by), 'Unknown'),
    'createdAt', p_pin.created_at
  )
$$;

create or replace function public.current_world_map_payload()
returns jsonb
language plpgsql
stable
set search_path = public, extensions
as $$
declare
  v_map public.world_map_uploads%rowtype;
  v_pins jsonb := '[]'::jsonb;
begin
  select * into v_map
  from public.world_map_uploads
  order by created_at desc, id desc
  limit 1;

  if v_map.id is null then
    return jsonb_build_object('map', null, 'pins', '[]'::jsonb);
  end if;

  select coalesce(jsonb_agg(public.world_map_pin_record_to_json(p) order by p.created_at, p.id), '[]'::jsonb)
    into v_pins
  from public.world_map_pins p
  where p.map_upload_id = v_map.id;

  return jsonb_build_object(
    'map', public.world_map_record_to_json(v_map),
    'pins', v_pins
  );
end;
$$;

create or replace function public.get_world_map(p_session_token text)
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

  return public.current_world_map_payload();
end;
$$;

create or replace function public.upload_world_map(
  p_session_token text,
  p_image_data_url text,
  p_mime_type text,
  p_file_name text default 'world-map'
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_map public.world_map_uploads%rowtype;
  v_mime_type text := lower(trim(coalesce(p_mime_type, '')));
  v_file_name text := left(coalesce(nullif(trim(p_file_name), ''), 'world-map'), 160);
  v_image_data_url text := trim(coalesce(p_image_data_url, ''));
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then
    raise exception 'Invalid or expired session.';
  end if;
  if v_profile.role <> 'dm'::public.user_role then
    raise exception 'Only the Dungeon Master can update the world map.';
  end if;
  if v_mime_type not in ('image/png', 'image/jpeg', 'image/webp', 'image/gif') then
    raise exception 'Upload a PNG, JPEG, WEBP, or GIF image.';
  end if;
  if v_image_data_url not like 'data:image/%;base64,%' then
    raise exception 'World map image data was invalid.';
  end if;
  if length(v_image_data_url) > 12000000 then
    raise exception 'World map image is too large.';
  end if;

  insert into public.world_map_uploads (uploaded_by, file_name, mime_type, image_data_url)
  values (v_profile.id, v_file_name, v_mime_type, v_image_data_url)
  returning * into v_map;

  delete from public.world_map_uploads
  where id <> v_map.id;

  return public.current_world_map_payload();
end;
$$;

create or replace function public.add_world_map_pin(
  p_session_token text,
  p_pin_type text,
  p_x numeric,
  p_y numeric,
  p_description text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_map public.world_map_uploads%rowtype;
  v_pin_type text := lower(trim(coalesce(p_pin_type, '')));
  v_description text := left(trim(coalesce(p_description, '')), 3000);
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then
    raise exception 'Invalid or expired session.';
  end if;

  select * into v_map
  from public.world_map_uploads
  order by created_at desc, id desc
  limit 1;

  if v_map.id is null then
    raise exception 'Upload a world map before placing pins.';
  end if;
  if v_pin_type not in ('sword', 'puzzle', 'skull', 'flag', 'plant', 'chest') then
    raise exception 'Choose a valid pin type.';
  end if;
  if p_x is null or p_y is null or p_x < 0 or p_x > 1 or p_y < 0 or p_y > 1 then
    raise exception 'Place the pin inside the map.';
  end if;
  if length(v_description) = 0 then
    raise exception 'Describe the map pin before placing it.';
  end if;

  insert into public.world_map_pins (map_upload_id, created_by, pin_type, x, y, description)
  values (v_map.id, v_profile.id, v_pin_type, p_x, p_y, v_description);

  return public.current_world_map_payload();
end;
$$;

create or replace function public.delete_world_map_pin(
  p_session_token text,
  p_pin_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_pin public.world_map_pins%rowtype;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then
    raise exception 'Invalid or expired session.';
  end if;

  select * into v_pin
  from public.world_map_pins
  where id = p_pin_id;

  if v_pin.id is null then
    raise exception 'Map pin was not found.';
  end if;
  if v_profile.role <> 'dm'::public.user_role and v_pin.created_by is distinct from v_profile.id then
    raise exception 'Only the Dungeon Master or the player who placed this pin can delete it.';
  end if;

  delete from public.world_map_pins where id = v_pin.id;
  return public.current_world_map_payload();
end;
$$;

-- Consolidated final grants
grant execute on function public.get_character_ledger(text) to anon, authenticated;
grant execute on function public.create_campaign_character(text, text, uuid, text, text, text) to anon, authenticated;
grant execute on function public.ensure_character_starter_armor(uuid) to anon, authenticated;
grant execute on function public.update_campaign_character(text, uuid, jsonb) to anon, authenticated;
grant execute on function public.delete_campaign_character(text, uuid) to anon, authenticated;
grant execute on function public.set_character_gift_inventory_open(text, uuid, boolean) to anon, authenticated;
grant execute on function public.get_dashboard_state(text) to anon, authenticated;
grant execute on function public.get_daily_rewards(text) to anon, authenticated;
grant execute on function public.update_daily_reward_schedule(text, jsonb) to anon, authenticated;
grant execute on function public.claim_daily_reward(text, date, uuid) to anon, authenticated;
grant execute on function public.shop_vendor_record_to_json(public.shop_vendors, boolean) to anon, authenticated;
grant execute on function public.shop_section_record_to_json(public.shop_sections) to anon, authenticated;
grant execute on function public.create_shop_section(text, uuid, jsonb) to anon, authenticated;
grant execute on function public.update_shop_section(text, uuid, uuid, jsonb) to anon, authenticated;
grant execute on function public.is_currency_loot_item(public.loot_items) to anon, authenticated;
grant execute on function public.loot_item_record_to_json(public.loot_items) to anon, authenticated;
grant execute on function public.get_exploration_state(text) to anon, authenticated;
grant execute on function public.get_exploration_cave_nicknames(text) to anon, authenticated;
grant execute on function public.set_exploration_cave_nickname(text, int, text) to anon, authenticated;
grant execute on function public.import_loot_items(text, jsonb) to anon, authenticated;
grant execute on function public.update_shop_vendor(text, uuid, jsonb) to anon, authenticated;
grant execute on function public.item_catalog_stackable(text, text) to anon, authenticated;
grant execute on function public.catalog_storage_capacity(text) to anon, authenticated;
grant execute on function public.additional_storage_kind(text, text) to anon, authenticated;
grant execute on function public.inventory_item_can_hold_children(public.inventory_items) to anon, authenticated;
grant execute on function public.split_inventory_item_stack(text, uuid, numeric, boolean) to anon, authenticated;
grant execute on function public.award_exploration_loot_item(text, uuid, uuid, numeric) to anon, authenticated;
grant execute on function public.world_map_record_to_json(public.world_map_uploads) to anon, authenticated;
grant execute on function public.world_map_pin_record_to_json(public.world_map_pins) to anon, authenticated;
grant execute on function public.get_world_map(text) to anon, authenticated;
grant execute on function public.upload_world_map(text, text, text, text) to anon, authenticated;
grant execute on function public.add_world_map_pin(text, text, numeric, numeric, text) to anon, authenticated;
grant execute on function public.delete_world_map_pin(text, uuid) to anon, authenticated;


-- ============================================================
-- ============================================================

-- Live app refresh signals.
-- Realtime clients listen to this single table and quietly reload the affected panels.

create table if not exists public.app_live_updates (
  scope text primary key,
  version bigint not null default 0,
  entity_id text,
  updated_at timestamptz not null default now(),
  constraint app_live_updates_scope_not_blank check (length(trim(scope)) > 0)
);

alter table public.app_live_updates enable row level security;
revoke all on table public.app_live_updates from anon, authenticated;
grant select on table public.app_live_updates to anon, authenticated;

drop policy if exists app_live_updates_read_all on public.app_live_updates;
create policy app_live_updates_read_all
on public.app_live_updates
for select
to anon, authenticated
using (true);

insert into public.app_live_updates (scope)
values
  ('dashboard'),
  ('notifications'),
  ('battle'),
  ('characters'),
  ('inventory'),
  ('house'),
  ('wagon'),
  ('spells'),
  ('cities'),
  ('bestiary'),
  ('world-map'),
  ('assets'),
  ('exploration'),
  ('caves'),
  ('trades')
on conflict (scope) do nothing;

create or replace function public.touch_app_live_update(
  p_scope text,
  p_entity_id text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_scope is null or length(trim(p_scope)) = 0 then
    return;
  end if;

  insert into public.app_live_updates (scope, version, entity_id, updated_at)
  values (trim(p_scope), 1, p_entity_id, now())
  on conflict (scope) do update
  set version = public.app_live_updates.version + 1,
      entity_id = excluded.entity_id,
      updated_at = excluded.updated_at;
end;
$$;

create or replace function public.touch_app_live_update_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_scope text;
  v_entity_id text;
begin
  v_entity_id := coalesce(to_jsonb(new)->>'id', to_jsonb(old)->>'id');
  foreach v_scope in array string_to_array(coalesce(tg_argv[0], ''), ',')
  loop
    perform public.touch_app_live_update(trim(v_scope), v_entity_id);
  end loop;
  return coalesce(new, old);
end;
$$;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
    and not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'app_live_updates'
    )
  then
    alter publication supabase_realtime add table public.app_live_updates;
  end if;
end $$;

drop trigger if exists app_live_profiles on public.profiles;
create trigger app_live_profiles
after insert or update or delete on public.profiles
for each row execute function public.touch_app_live_update_trigger('dashboard,characters,notifications');

drop trigger if exists app_live_class_templates on public.class_templates;
create trigger app_live_class_templates
after insert or update or delete on public.class_templates
for each row execute function public.touch_app_live_update_trigger('battle,characters,assets');

drop trigger if exists app_live_characters on public.characters;
create trigger app_live_characters
after insert or update or delete on public.characters
for each row execute function public.touch_app_live_update_trigger('dashboard,battle,characters,cities,inventory');

drop trigger if exists app_live_currency_units on public.currency_units;
create trigger app_live_currency_units
after insert or update or delete on public.currency_units
for each row execute function public.touch_app_live_update_trigger('assets,cities,inventory');

drop trigger if exists app_live_character_wallet_balances on public.character_wallet_balances;
create trigger app_live_character_wallet_balances
after insert or update or delete on public.character_wallet_balances
for each row execute function public.touch_app_live_update_trigger('battle,characters,cities,inventory');

drop trigger if exists app_live_item_catalog on public.item_catalog;
create trigger app_live_item_catalog
after insert or update or delete on public.item_catalog
for each row execute function public.touch_app_live_update_trigger('assets,cities,inventory,exploration');

drop trigger if exists app_live_inventory_items on public.inventory_items;
create trigger app_live_inventory_items
after insert or update or delete on public.inventory_items
for each row execute function public.touch_app_live_update_trigger('battle,inventory,cities,wagon');

drop trigger if exists app_live_battles on public.battles;
create trigger app_live_battles
after insert or update or delete on public.battles
for each row execute function public.touch_app_live_update_trigger('dashboard,battle');

drop trigger if exists app_live_combatants on public.combatants;
create trigger app_live_combatants
after insert or update or delete on public.combatants
for each row execute function public.touch_app_live_update_trigger('dashboard,battle,characters');

drop trigger if exists app_live_battle_terrain on public.battle_terrain;
create trigger app_live_battle_terrain
after insert or update or delete on public.battle_terrain
for each row execute function public.touch_app_live_update_trigger('battle');

drop trigger if exists app_live_bestiary_entities on public.bestiary_entities;
create trigger app_live_bestiary_entities
after insert or update or delete on public.bestiary_entities
for each row execute function public.touch_app_live_update_trigger('battle,bestiary,assets');

drop trigger if exists app_live_bestiary_categories on public.bestiary_categories;
create trigger app_live_bestiary_categories
after insert or update or delete on public.bestiary_categories
for each row execute function public.touch_app_live_update_trigger('bestiary,assets');

drop trigger if exists app_live_world_map_uploads on public.world_map_uploads;
create trigger app_live_world_map_uploads
after insert or update or delete on public.world_map_uploads
for each row execute function public.touch_app_live_update_trigger('world-map');

drop trigger if exists app_live_world_map_pins on public.world_map_pins;
create trigger app_live_world_map_pins
after insert or update or delete on public.world_map_pins
for each row execute function public.touch_app_live_update_trigger('world-map');

drop trigger if exists app_live_cities on public.cities;
create trigger app_live_cities
after insert or update or delete on public.cities
for each row execute function public.touch_app_live_update_trigger('dashboard,cities,assets');

drop trigger if exists app_live_shop_vendors on public.shop_vendors;
create trigger app_live_shop_vendors
after insert or update or delete on public.shop_vendors
for each row execute function public.touch_app_live_update_trigger('cities,assets');

drop trigger if exists app_live_shop_sections on public.shop_sections;
create trigger app_live_shop_sections
after insert or update or delete on public.shop_sections
for each row execute function public.touch_app_live_update_trigger('cities,assets');

drop trigger if exists app_live_market_products on public.market_products;
create trigger app_live_market_products
after insert or update or delete on public.market_products
for each row execute function public.touch_app_live_update_trigger('cities,assets');

drop trigger if exists app_live_material_conversion_recipes on public.material_conversion_recipes;
create trigger app_live_material_conversion_recipes
after insert or update or delete on public.material_conversion_recipes
for each row execute function public.touch_app_live_update_trigger('cities,inventory,assets');

drop trigger if exists app_live_dragon_scale_fragment_catalog on public.dragon_scale_fragment_catalog;
create trigger app_live_dragon_scale_fragment_catalog
after insert or update or delete on public.dragon_scale_fragment_catalog
for each row execute function public.touch_app_live_update_trigger('cities,inventory,assets');




























drop trigger if exists app_live_wagon_activity_log on public.wagon_activity_log;
create trigger app_live_wagon_activity_log
after insert or update or delete on public.wagon_activity_log
for each row execute function public.touch_app_live_update_trigger('wagon,inventory');

drop trigger if exists app_live_spell_catalog on public.spell_catalog;
create trigger app_live_spell_catalog
after insert or update or delete on public.spell_catalog
for each row execute function public.touch_app_live_update_trigger('spells,cities,assets');

drop trigger if exists app_live_character_spells on public.character_spells;
create trigger app_live_character_spells
after insert or update or delete on public.character_spells
for each row execute function public.touch_app_live_update_trigger('battle,characters,spells');

drop trigger if exists app_live_loot_pools on public.loot_pools;
create trigger app_live_loot_pools
after insert or update or delete on public.loot_pools
for each row execute function public.touch_app_live_update_trigger('exploration,assets');

drop trigger if exists app_live_loot_items on public.loot_items;
create trigger app_live_loot_items
after insert or update or delete on public.loot_items
for each row execute function public.touch_app_live_update_trigger('exploration,assets');

drop trigger if exists app_live_loot_workbook_settings on public.loot_workbook_settings;
create trigger app_live_loot_workbook_settings
after insert or update or delete on public.loot_workbook_settings
for each row execute function public.touch_app_live_update_trigger('exploration,assets');

drop trigger if exists app_live_campaign_notifications on public.campaign_notifications;
create trigger app_live_campaign_notifications
after insert or update or delete on public.campaign_notifications
for each row execute function public.touch_app_live_update_trigger('dashboard,notifications,trades');

drop trigger if exists app_live_daily_reward_schedule on public.daily_reward_schedule;
create trigger app_live_daily_reward_schedule
after insert or update or delete on public.daily_reward_schedule
for each row execute function public.touch_app_live_update_trigger('dashboard');

drop trigger if exists app_live_daily_reward_claims on public.daily_reward_claims;
create trigger app_live_daily_reward_claims
after insert or update or delete on public.daily_reward_claims
for each row execute function public.touch_app_live_update_trigger('dashboard,inventory');

drop trigger if exists app_live_trade_offers on public.trade_offers;
create trigger app_live_trade_offers
after insert or update or delete on public.trade_offers
for each row execute function public.touch_app_live_update_trigger('dashboard,notifications,trades,inventory');

drop trigger if exists app_live_exploration_cave_nicknames on public.exploration_cave_nicknames;
create trigger app_live_exploration_cave_nicknames
after insert or update or delete on public.exploration_cave_nicknames
for each row execute function public.touch_app_live_update_trigger('caves,exploration');

grant execute on function public.touch_app_live_update(text, text) to anon, authenticated;
grant execute on function public.touch_app_live_update_trigger() to anon, authenticated;


-- ============================================================
-- Ruined City hub and construction projects.

alter table public.cities
  add column if not exists description text not null default '',
  add column if not exists primary_color text not null default '#d1a85b',
  add column if not exists secondary_color text not null default '#1f7875',
  add column if not exists accent_color text not null default '#f5b44c',
  add column if not exists is_player_visible boolean not null default true,
  add column if not exists is_current_residence boolean not null default false,
  add column if not exists show_under_construction boolean not null default false;

insert into public.cities (city_key, name, description, is_locked, is_current_residence, show_under_construction, display_order)
values ('the-ruined-city', 'The Ruined City*', '', false, false, false, 5)
on conflict (city_key) do nothing;

update public.cities
set is_current_residence = true,
    updated_at = now()
where city_key = 'the-ruined-city'
  and not exists (
    select 1
    from public.cities existing
    where existing.is_current_residence
  );

update public.characters c
set location_city_key = city.city_key,
    location_name = city.name
from public.cities city
where c.location_city_key is null
  and public.city_names_match(city.name, c.location_name);

update public.characters c
set location_name = city.name
from public.cities city
where c.location_city_key = city.city_key
  and c.location_name is distinct from city.name;

update public.characters c
set location_city_key = null,
    location_name = 'Wild'
where c.location_city_key is not null
  and not exists (
    select 1
    from public.cities city
    where city.city_key = c.location_city_key
  );

update public.characters c
set location_city_key = null,
    location_name = 'Wild'
where not public.city_names_match(c.location_name, 'Wild')
  and c.location_city_key is null
  and not exists (
    select 1
    from public.cities city
    where public.city_names_match(city.name, c.location_name)
  );

alter table public.characters
  drop constraint if exists characters_location_city_key_fkey;

alter table public.characters
  add constraint characters_location_city_key_fkey
  foreign key (location_city_key)
  references public.cities(city_key)
  on update cascade
  on delete set null;

drop index if exists cities_one_current_residence_idx;
create unique index cities_one_current_residence_idx
on public.cities ((is_current_residence))
where is_current_residence;

do $$
begin
  perform public.upsert_item_catalog_entry('Wood Logs', 'material', 'Common', 'Construction Materials', array['Construction material']::text[], 1, true, '{}'::jsonb, 'Wood', false, 0, 'Construction-ready logs for city projects.', true, 4000);
  perform public.upsert_item_catalog_entry('Stone Scale', 'ore', 'Common', 'Construction Materials', array['Construction material']::text[], 1, true, '{}'::jsonb, 'Stone', false, 0, 'Measured stone for city projects.', true, 4010);
  perform public.upsert_item_catalog_entry('Coal', 'ore', 'Uncommon', 'Construction Materials', array['Construction material']::text[], 1, true, '{}'::jsonb, 'Coal', false, 0, 'Usable coal for city projects and crafting.', true, 4020);
end $$;

create table if not exists public.city_construction_projects (
  id uuid primary key default gen_random_uuid(),
  city_key text not null references public.cities(city_key) on delete cascade,
  project_name text not null,
  status text not null default 'active' check (status in ('active', 'ended')),
  display_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.city_construction_requirements (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.city_construction_projects(id) on delete cascade,
  item_catalog_id uuid not null references public.item_catalog(id),
  required_quantity numeric(12,1) not null check (required_quantity > 0),
  contributed_quantity numeric(12,1) not null default 0 check (contributed_quantity >= 0),
  display_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(project_id, item_catalog_id)
);

create table if not exists public.city_construction_contributions (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.city_construction_projects(id) on delete cascade,
  requirement_id uuid not null references public.city_construction_requirements(id) on delete cascade,
  character_id uuid not null references public.characters(id) on delete cascade,
  source_item_id uuid,
  item_catalog_id uuid not null references public.item_catalog(id),
  quantity numeric(12,1) not null check (quantity > 0),
  created_at timestamptz not null default now()
);

create index if not exists city_construction_projects_city_idx on public.city_construction_projects(city_key, status, display_order);
create index if not exists city_construction_requirements_project_idx on public.city_construction_requirements(project_id, display_order);
create index if not exists city_construction_contributions_project_idx on public.city_construction_contributions(project_id, created_at desc);

alter table public.city_construction_projects enable row level security;
alter table public.city_construction_requirements enable row level security;
alter table public.city_construction_contributions enable row level security;

revoke all on public.city_construction_projects from anon, authenticated;
revoke all on public.city_construction_requirements from anon, authenticated;
revoke all on public.city_construction_contributions from anon, authenticated;

drop trigger if exists city_construction_projects_touch_updated_at on public.city_construction_projects;
create trigger city_construction_projects_touch_updated_at
before update on public.city_construction_projects
for each row execute function public.touch_updated_at();

drop trigger if exists city_construction_requirements_touch_updated_at on public.city_construction_requirements;
create trigger city_construction_requirements_touch_updated_at
before update on public.city_construction_requirements
for each row execute function public.touch_updated_at();

drop trigger if exists app_live_city_construction_projects on public.city_construction_projects;
create trigger app_live_city_construction_projects
after insert or update or delete on public.city_construction_projects
for each row execute function public.touch_app_live_update_trigger('cities,inventory,assets');

drop trigger if exists app_live_city_construction_requirements on public.city_construction_requirements;
create trigger app_live_city_construction_requirements
after insert or update or delete on public.city_construction_requirements
for each row execute function public.touch_app_live_update_trigger('cities,inventory,assets');

drop trigger if exists app_live_city_construction_contributions on public.city_construction_contributions;
create trigger app_live_city_construction_contributions
after insert or update or delete on public.city_construction_contributions
for each row execute function public.touch_app_live_update_trigger('cities,inventory');

create or replace function public.city_record_to_json(p_city public.cities)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'id', p_city.id,
    'key', p_city.city_key,
    'name', p_city.name,
    'description', p_city.description,
    'primaryColor', p_city.primary_color,
    'secondaryColor', p_city.secondary_color,
    'accentColor', p_city.accent_color,
    'locked', p_city.is_locked,
    'visibleToPlayers', p_city.is_player_visible,
    'currentResidence', p_city.is_current_residence,
    'showUnderConstruction', p_city.show_under_construction,
    'order', p_city.display_order
  )
$$;

create or replace function public.city_construction_requirement_to_json(p_requirement public.city_construction_requirements)
returns jsonb
language sql
stable
set search_path = public
as $$
  select jsonb_build_object(
    'id', p_requirement.id,
    'projectId', p_requirement.project_id,
    'item', public.catalog_record_to_json(c),
    'requiredQuantity', p_requirement.required_quantity,
    'contributedQuantity', p_requirement.contributed_quantity,
    'complete', p_requirement.contributed_quantity >= p_requirement.required_quantity,
    'order', p_requirement.display_order
  )
  from public.item_catalog c
  where c.id = p_requirement.item_catalog_id
$$;

create or replace function public.city_construction_project_to_json(p_project public.city_construction_projects)
returns jsonb
language sql
stable
set search_path = public
as $$
  with requirement_totals as (
    select
      coalesce(sum(r.required_quantity), 0) as required_total,
      coalesce(sum(least(r.contributed_quantity, r.required_quantity)), 0) as contributed_total,
      bool_and(r.contributed_quantity >= r.required_quantity) as all_complete
    from public.city_construction_requirements r
    where r.project_id = p_project.id
  )
  select jsonb_build_object(
    'id', p_project.id,
    'cityKey', p_project.city_key,
    'name', p_project.project_name,
    'status', p_project.status,
    'order', p_project.display_order,
    'complete', coalesce(t.all_complete, false) and t.required_total > 0,
    'progress', case when t.required_total > 0 then least(1, t.contributed_total / t.required_total) else 0 end,
    'requirements', (
      select coalesce(jsonb_agg(public.city_construction_requirement_to_json(r) order by r.display_order, r.created_at), '[]'::jsonb)
      from public.city_construction_requirements r
      where r.project_id = p_project.id
    )
  )
  from requirement_totals t
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
    'profiles', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', p.id,
        'username', p.username::text,
        'displayName', p.display_name,
        'role', p.role
      ) order by p.display_name), '[]'::jsonb)
      from public.profiles p
    ),
    'characters', (
      select coalesce(jsonb_agg(public.character_record_to_json(c) order by c.name), '[]'::jsonb)
      from public.characters c
      where c.kind = 'player'
        and (v_profile.role = 'dm'::public.user_role or c.owner_user_id = v_profile.id)
    ),
    'cities', (
      select coalesce(jsonb_agg(public.city_record_to_json(c) order by c.is_current_residence desc, c.display_order, c.name), '[]'::jsonb)
      from public.cities c
      where v_profile.role = 'dm'::public.user_role or c.is_player_visible
    ),
    'vendors', (
      select coalesce(jsonb_agg(public.shop_vendor_record_to_json(v, v_profile.role = 'dm'::public.user_role) order by v.city_key, v.display_order, v.name), '[]'::jsonb)
      from public.shop_vendors v
      join public.cities c on c.city_key = v.city_key
      where v_profile.role = 'dm'::public.user_role or (c.is_player_visible and not v.is_hidden)
    ),
    'constructionProjects', (
      select coalesce(jsonb_agg(public.city_construction_project_to_json(p) order by p.city_key, p.display_order, p.project_name), '[]'::jsonb)
      from public.city_construction_projects p
      join public.cities c on c.city_key = p.city_key
      where p.status = 'active'
        and (v_profile.role = 'dm'::public.user_role or c.is_player_visible)
    )
  );
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
  v_city public.cities%rowtype;
  v_new_name text;
begin
  v_profile := public.require_dm_profile(p_session_token);

  select *
  into v_city
  from public.cities
  where city_key = p_city_key;

  if v_city.id is null then
    raise exception 'City not found.';
  end if;

  if coalesce((v_patch->>'currentResidence')::boolean, false) then
    update public.cities set is_current_residence = false where is_current_residence;
  end if;

  update public.cities
  set
    name = case when v_patch ? 'name' then coalesce(nullif(trim(v_patch->>'name'), ''), name) else name end,
    description = case when v_patch ? 'description' then coalesce(v_patch->>'description', '') else description end,
    primary_color = case when v_patch ? 'primaryColor' then coalesce(nullif(trim(v_patch->>'primaryColor'), ''), primary_color) else primary_color end,
    secondary_color = case when v_patch ? 'secondaryColor' then coalesce(nullif(trim(v_patch->>'secondaryColor'), ''), secondary_color) else secondary_color end,
    accent_color = case when v_patch ? 'accentColor' then coalesce(nullif(trim(v_patch->>'accentColor'), ''), accent_color) else accent_color end,
    is_locked = case when v_patch ? 'locked' then coalesce((v_patch->>'locked')::boolean, false) else is_locked end,
    is_player_visible = case when v_patch ? 'visibleToPlayers' then coalesce((v_patch->>'visibleToPlayers')::boolean, false) else is_player_visible end,
    show_under_construction = case when v_patch ? 'showUnderConstruction' then coalesce((v_patch->>'showUnderConstruction')::boolean, false) else show_under_construction end,
    is_current_residence = case when v_patch ? 'currentResidence' then coalesce((v_patch->>'currentResidence')::boolean, false) else is_current_residence end,
    display_order = case when v_patch ? 'order' then greatest(0, (v_patch->>'order')::int) else display_order end
  where city_key = p_city_key
  returning name into v_new_name;

  update public.characters
  set location_city_key = p_city_key,
      location_name = v_new_name
  where location_city_key = p_city_key
     or (
       location_city_key is null
       and public.city_names_match(location_name, v_city.name)
     );

  if not exists (select 1 from public.cities where is_current_residence) then
    update public.cities
    set is_current_residence = true
    where city_key = p_city_key;
  end if;

  return public.get_discovered_cities(p_session_token);
end;
$$;

create or replace function public.create_discovered_city(
  p_session_token text,
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
  v_name text := coalesce(nullif(trim(v_patch->>'name'), ''), 'New City');
  v_city_key text;
begin
  v_profile := public.require_dm_profile(p_session_token);
  v_city_key := public.safe_slug(v_name);

  if v_city_key = '' then
    v_city_key := 'city';
  end if;

  if exists (select 1 from public.cities where city_key = v_city_key) then
    v_city_key := v_city_key || '-' || substring(gen_random_uuid()::text from 1 for 8);
  end if;

  if coalesce((v_patch->>'currentResidence')::boolean, false) then
    update public.cities set is_current_residence = false where is_current_residence;
  end if;

  insert into public.cities (
    city_key,
    name,
    description,
    primary_color,
    secondary_color,
    accent_color,
    is_locked,
    is_player_visible,
    is_current_residence,
    show_under_construction,
    display_order
  )
  values (
    v_city_key,
    v_name,
    coalesce(v_patch->>'description', ''),
    coalesce(nullif(trim(v_patch->>'primaryColor'), ''), '#8f6a46'),
    coalesce(nullif(trim(v_patch->>'secondaryColor'), ''), '#345c52'),
    coalesce(nullif(trim(v_patch->>'accentColor'), ''), '#c99f65'),
    coalesce((v_patch->>'locked')::boolean, true),
    coalesce((v_patch->>'visibleToPlayers')::boolean, false),
    coalesce((v_patch->>'currentResidence')::boolean, false),
    coalesce((v_patch->>'showUnderConstruction')::boolean, false),
    greatest(0, coalesce((v_patch->>'order')::int, (select coalesce(max(display_order), 0) + 10 from public.cities)))
  );

  return public.get_discovered_cities(p_session_token);
end;
$$;

create or replace function public.construction_source_item_accessible(
  p_profile public.profiles,
  p_actor public.characters,
  p_item public.inventory_items
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_root public.inventory_items%rowtype;
  v_owner public.characters%rowtype;
begin
  if p_item.character_id = p_actor.id then
    return true;
  end if;

  with recursive ancestry as (
    select i.*
    from public.inventory_items i
    where i.id = p_item.id
    union all
    select parent.*
    from public.inventory_items parent
    join ancestry child on child.parent_item_id = parent.id
  )
  select * into v_root
  from ancestry
  where parent_item_id is null
  order by id
  limit 1;

  if v_root.id is null then
    return false;
  end if;

  select * into v_owner
  from public.characters
  where id = v_root.character_id;

  return public.inventory_storage_visible_to_profile(p_profile, v_root, v_owner)
    and public.characters_share_location(v_owner, p_actor);
end;
$$;

create or replace function public.create_city_construction_project(
  p_session_token text,
  p_city_key text,
  p_project_name text,
  p_requirements jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_project public.city_construction_projects%rowtype;
  v_entry jsonb;
  v_catalog public.item_catalog%rowtype;
  v_quantity numeric;
  v_order int := 0;
begin
  v_profile := public.require_dm_profile(p_session_token);

  if not exists (select 1 from public.cities where city_key = p_city_key) then
    raise exception 'City not found.';
  end if;
  if length(trim(coalesce(p_project_name, ''))) = 0 then
    raise exception 'Project name is required.';
  end if;
  if jsonb_typeof(coalesce(p_requirements, '[]'::jsonb)) <> 'array' or jsonb_array_length(coalesce(p_requirements, '[]'::jsonb)) = 0 then
    raise exception 'Add at least one required material.';
  end if;

  insert into public.city_construction_projects (city_key, project_name, display_order)
  values (
    p_city_key,
    trim(p_project_name),
    coalesce((select max(display_order) + 10 from public.city_construction_projects where city_key = p_city_key), 10)
  )
  returning * into v_project;

  for v_entry in select * from jsonb_array_elements(coalesce(p_requirements, '[]'::jsonb))
  loop
    select * into v_catalog from public.item_catalog where id = (v_entry->>'itemCatalogId')::uuid and is_active;
    if v_catalog.id is null then raise exception 'Required item was not found in the item catalog.'; end if;
    v_quantity := public.assert_valid_item_quantity(v_catalog.item_name, v_catalog.item_type, coalesce((v_entry->>'quantity')::numeric, 0));
    v_order := v_order + 10;

    insert into public.city_construction_requirements (project_id, item_catalog_id, required_quantity, display_order)
    values (v_project.id, v_catalog.id, v_quantity, v_order)
    on conflict (project_id, item_catalog_id) do update
    set required_quantity = public.city_construction_requirements.required_quantity + excluded.required_quantity;
  end loop;

  return public.get_discovered_cities(p_session_token);
end;
$$;

create or replace function public.update_city_construction_project(
  p_session_token text,
  p_project_id uuid,
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
  v_project public.city_construction_projects%rowtype;
  v_entry jsonb;
  v_catalog public.item_catalog%rowtype;
  v_quantity numeric;
  v_seen uuid[] := '{}';
  v_order int := 0;
begin
  v_profile := public.require_dm_profile(p_session_token);

  select * into v_project from public.city_construction_projects where id = p_project_id;
  if v_project.id is null then raise exception 'Project not found.'; end if;

  update public.city_construction_projects
  set project_name = case when v_patch ? 'name' then coalesce(nullif(trim(v_patch->>'name'), ''), project_name) else project_name end,
      status = case when v_patch ? 'status' and v_patch->>'status' = 'ended' then 'ended' else status end,
      display_order = case when v_patch ? 'order' then greatest(0, (v_patch->>'order')::int) else display_order end
  where id = p_project_id;

  if v_patch ? 'requirements' then
    if jsonb_typeof(v_patch->'requirements') <> 'array' or jsonb_array_length(v_patch->'requirements') = 0 then
      raise exception 'A project needs at least one required material.';
    end if;

    for v_entry in select * from jsonb_array_elements(v_patch->'requirements')
    loop
      select * into v_catalog from public.item_catalog where id = (v_entry->>'itemCatalogId')::uuid and is_active;
      if v_catalog.id is null then raise exception 'Required item was not found in the item catalog.'; end if;
      v_quantity := public.assert_valid_item_quantity(v_catalog.item_name, v_catalog.item_type, coalesce((v_entry->>'quantity')::numeric, 0));
      v_order := v_order + 10;
      v_seen := array_append(v_seen, v_catalog.id);

      insert into public.city_construction_requirements (project_id, item_catalog_id, required_quantity, display_order)
      values (p_project_id, v_catalog.id, v_quantity, v_order)
      on conflict (project_id, item_catalog_id) do update
      set required_quantity = greatest(excluded.required_quantity, public.city_construction_requirements.contributed_quantity),
          display_order = excluded.display_order;
    end loop;

    delete from public.city_construction_requirements
    where project_id = p_project_id
      and not (item_catalog_id = any(v_seen))
      and contributed_quantity = 0;
  end if;

  return public.get_discovered_cities(p_session_token);
end;
$$;

create or replace function public.contribute_city_construction_project(
  p_session_token text,
  p_character_id uuid,
  p_project_id uuid,
  p_contributions jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_actor public.characters%rowtype;
  v_project public.city_construction_projects%rowtype;
  v_city public.cities%rowtype;
  v_entry jsonb;
  v_requirement public.city_construction_requirements%rowtype;
  v_catalog public.item_catalog%rowtype;
  v_item public.inventory_items%rowtype;
  v_quantity numeric;
  v_remaining numeric;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;

  v_actor := public.assert_inventory_access(v_profile, p_character_id, false);

  select * into v_project from public.city_construction_projects where id = p_project_id and status = 'active';
  if v_project.id is null then raise exception 'Active project not found.'; end if;

  select * into v_city from public.cities where city_key = v_project.city_key;
  if v_city.id is null then raise exception 'Project city not found.'; end if;
  if v_city.is_locked then raise exception 'This city is locked by the Dungeon Master.'; end if;
  if not v_city.show_under_construction then raise exception 'Construction is not open in this city.'; end if;
  if not public.character_is_in_city(v_actor, v_city.city_key) then
    raise exception '% is in %, not %.', v_actor.name, v_actor.location_name, v_city.name;
  end if;
  if jsonb_typeof(coalesce(p_contributions, '[]'::jsonb)) <> 'array' or jsonb_array_length(coalesce(p_contributions, '[]'::jsonb)) = 0 then
    raise exception 'Choose at least one item to contribute.';
  end if;

  for v_entry in select * from jsonb_array_elements(coalesce(p_contributions, '[]'::jsonb))
  loop
    select * into v_requirement
    from public.city_construction_requirements
    where id = (v_entry->>'requirementId')::uuid
      and project_id = p_project_id
    for update;
    if v_requirement.id is null then raise exception 'Project material requirement not found.'; end if;

    select * into v_catalog from public.item_catalog where id = v_requirement.item_catalog_id;
    if v_catalog.id is null then raise exception 'Catalog item not found.'; end if;

    select * into v_item from public.inventory_items where id = (v_entry->>'itemId')::uuid for update;
    if v_item.id is null then raise exception 'Contribution item not found.'; end if;
    if v_item.is_storage or v_item.item_type = 'pet' then raise exception 'Storage containers and pets cannot be consumed for construction.'; end if;
    if v_item.loadout_slot is not null then raise exception 'Remove % from the active loadout before contributing it.', v_item.item_name; end if;
    if public.catalog_key_for_name(public.normalize_item_name(v_item.item_name)) <> v_catalog.item_key then
      raise exception '% does not match the required material %.', v_item.item_name, v_catalog.item_name;
    end if;
    if not public.construction_source_item_accessible(v_profile, v_actor, v_item) then
      raise exception 'That item is not in accessible storage for this city.';
    end if;

    v_remaining := greatest(0, v_requirement.required_quantity - v_requirement.contributed_quantity);
    if v_remaining <= 0 then raise exception '% is already complete.', v_catalog.item_name; end if;
    v_quantity := public.assert_valid_item_quantity(v_item.item_name, v_item.item_type, coalesce((v_entry->>'quantity')::numeric, 0));
    if v_quantity > v_item.quantity then raise exception 'Not enough % in that stack.', v_item.item_name; end if;
    if v_quantity > v_remaining then raise exception 'That contribution exceeds the remaining % needed.', v_catalog.item_name; end if;

    update public.city_construction_requirements
    set contributed_quantity = contributed_quantity + v_quantity
    where id = v_requirement.id;

    insert into public.city_construction_contributions (project_id, requirement_id, character_id, source_item_id, item_catalog_id, quantity)
    values (p_project_id, v_requirement.id, v_actor.id, v_item.id, v_catalog.id, v_quantity);

    if v_item.quantity = v_quantity then
      delete from public.inventory_items where id = v_item.id;
    else
      update public.inventory_items set quantity = quantity - v_quantity where id = v_item.id;
    end if;
  end loop;

  return public.get_discovered_cities(p_session_token);
end;
$$;

grant execute on function public.city_construction_requirement_to_json(public.city_construction_requirements) to anon, authenticated;
grant execute on function public.city_construction_project_to_json(public.city_construction_projects) to anon, authenticated;
grant execute on function public.update_city_access(text, text, jsonb) to anon, authenticated;
grant execute on function public.create_discovered_city(text, jsonb) to anon, authenticated;
grant execute on function public.construction_source_item_accessible(public.profiles, public.characters, public.inventory_items) to anon, authenticated;
grant execute on function public.create_city_construction_project(text, text, text, jsonb) to anon, authenticated;
grant execute on function public.update_city_construction_project(text, uuid, jsonb) to anon, authenticated;
grant execute on function public.contribute_city_construction_project(text, uuid, uuid, jsonb) to anon, authenticated;

grant execute on function public.city_names_match(text, text) to anon, authenticated;

-- ============================================================

-- Canonical property storage cutover.
-- Existing legacy tables are read only by the preservation transaction below.
begin;

create table if not exists public.storage_properties (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references public.profiles(id) on delete cascade,
  property_kind text not null check (property_kind in ('house', 'stable')),
  city_key text not null default 'wild',
  property_name text not null,
  capacity integer not null check (capacity between 0 and 500),
  display_order integer not null default 0 check (display_order >= 0),
  is_main boolean not null default false,
  is_locked boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint storage_properties_name_not_blank check (length(trim(property_name)) > 0),
  constraint storage_properties_city_key_not_blank check (length(trim(city_key)) > 0)
);

create unique index if not exists storage_properties_one_main_house
  on public.storage_properties(owner_user_id)
  where property_kind = 'house' and is_main;
create index if not exists storage_properties_owner_order
  on public.storage_properties(owner_user_id, display_order, created_at, id);
create index if not exists storage_properties_city
  on public.storage_properties(city_key);

alter table public.storage_properties enable row level security;
revoke all on public.storage_properties from anon, authenticated;

drop trigger if exists normalize_additional_storage_inventory_item_trigger on public.inventory_items;
drop trigger if exists validate_inventory_item_placement_trigger on public.inventory_items;

alter table public.inventory_items
  add column if not exists property_id uuid references public.storage_properties(id) on delete cascade,
  add column if not exists storage_is_main boolean not null default false,
  add column if not exists storage_display_order integer not null default 0;

alter table public.market_products add column if not exists boarded_item_id uuid;
create unique index if not exists market_products_boarded_item_unique
  on public.market_products(boarded_item_id) where boarded_item_id is not null;

alter table public.inventory_items alter column character_id drop not null;

-- Old indexes assume every item belongs to a character. They are replaced after migration.
drop index if exists public.inventory_container_slot_unique;
drop index if exists public.inventory_loadout_slot_unique;
drop index if exists public.inventory_root_slot_unique;
drop index if exists public.inventory_parent_slot_unique;
drop index if exists public.inventory_character_slot_unique;
drop index if exists public.inventory_property_slot_unique;
drop index if exists public.inventory_character_root_slot_unique;
drop index if exists public.inventory_character_active_storage_kind_unique;
drop index if exists public.inventory_property_root_slot_unique;
drop index if exists public.inventory_child_slot_unique;
drop index if exists public.inventory_character_loadout_slot_unique;
drop index if exists public.inventory_items_property_idx;

do $$
declare
  v_legacy_house_items bigint := 0;
  v_legacy_properties bigint := 0;
  v_collision_count bigint := 0;
  v_mismatch_count bigint := 0;
  v_property record;
  v_target_property public.storage_properties%rowtype;
  v_slot integer;
  v_kind text;
  v_city_key text;
begin
  if to_regclass('public.player_houses') is null
    and to_regclass('public.house_inventory_items') is null
    and to_regclass('public.campaign_properties') is null
  then
    if to_regclass('public.storage_properties') is null
      or to_regprocedure('public.get_player_homes(text,uuid,uuid,text,uuid)') is null
      or not exists (
        select 1
        from pg_constraint
        where conrelid = 'public.inventory_items'::regclass
          and conname = 'inventory_items_canonical_location_check'
      )
    then
      raise exception 'Legacy storage sources are absent, but a completed canonical storage installation could not be verified.';
    end if;

    -- A successful earlier run already preserved and migrated the legacy rows.
    -- Skip only the one-time copy; the idempotent runtime installation below
    -- still refreshes functions, triggers, grants, and integrity checks.
    return;
  end if;

  if to_regclass('public.player_houses') is null
    or to_regclass('public.house_inventory_items') is null
    or to_regclass('public.campaign_properties') is null
  then
    raise exception 'Canonical storage migration found an unsafe mixed state: some legacy source tables exist and others are missing.';
  end if;

  if to_regclass('public.player_main_homes') is null
    or to_regclass('public.player_home_display_orders') is null
  then
    raise exception 'Canonical storage migration is missing required legacy home ordering tables.';
  end if;

  select count(*) into v_legacy_house_items from public.house_inventory_items;
  select count(*) into v_legacy_properties from public.campaign_properties;

  select count(*) into v_collision_count
  from public.house_inventory_items legacy
  join public.inventory_items item on item.id = legacy.id;
  if v_collision_count > 0 then
    raise exception 'Storage migration aborted: % legacy house item IDs already exist in inventory_items.', v_collision_count;
  end if;

  select count(*) into v_collision_count
  from public.campaign_properties legacy
  join public.inventory_items item on item.id = legacy.id;
  if v_collision_count > 0 then
    raise exception 'Storage migration aborted: % legacy property IDs already exist in inventory_items.', v_collision_count;
  end if;

  insert into public.storage_properties (
    id, owner_user_id, property_kind, city_key, property_name, capacity,
    display_order, is_main, is_locked, created_at, updated_at
  )
  select
    house.id,
    house.owner_user_id,
    case when house.house_kind = 'stable' then 'stable' else 'house' end,
    coalesce(
      (select city.city_key from public.cities city
        where lower(trim(city.name)) = lower(trim(house.city_name))
          or city.city_key = public.safe_slug(house.city_name)
        order by (lower(trim(city.name)) = lower(trim(house.city_name))) desc
        limit 1),
      nullif(public.safe_slug(house.city_name), ''),
      'wild'
    ),
    case when house.house_kind = 'stable'
      then coalesce(nullif(trim(house.stable_name), ''), 'Stable')
      else coalesce(nullif(trim(house.house_name), ''), 'House')
    end,
    case when house.house_kind = 'stable' then house.stable_slots else house.inventory_slots end,
    coalesce((select ordering.display_order from public.player_home_display_orders ordering
      where ordering.owner_user_id = house.owner_user_id and ordering.home_source = 'static' and ordering.home_id = house.id),
      greatest(0, house.created_order)),
    exists (select 1 from public.player_main_homes main
      where main.owner_user_id = house.owner_user_id and main.home_source = 'static' and main.home_id = house.id)
      and house.house_kind = 'house',
    house.is_locked,
    house.created_at,
    house.updated_at
  from public.player_houses house
  on conflict (id) do nothing;

  select count(*) into v_mismatch_count
  from public.player_houses legacy
  left join public.storage_properties storage on storage.id = legacy.id
  where storage.id is null
    or storage.owner_user_id is distinct from legacy.owner_user_id
    or storage.property_kind is distinct from case when legacy.house_kind = 'stable' then 'stable' else 'house' end
    or storage.property_name is distinct from case when legacy.house_kind = 'stable'
      then coalesce(nullif(trim(legacy.stable_name), ''), 'Stable')
      else coalesce(nullif(trim(legacy.house_name), ''), 'House') end
    or storage.capacity is distinct from case when legacy.house_kind = 'stable' then legacy.stable_slots else legacy.inventory_slots end
    or storage.is_locked is distinct from legacy.is_locked
    or storage.created_at is distinct from legacy.created_at;
  if v_mismatch_count > 0 then
    raise exception 'Storage migration aborted: % house or stable records did not preserve their identity and metadata.', v_mismatch_count;
  end if;

  update public.inventory_items item
  set storage_is_main = exists (
        select 1 from public.player_main_homes main
        where main.home_source = 'mobile' and main.home_id = item.id
      ),
      storage_display_order = coalesce((
        select ordering.display_order from public.player_home_display_orders ordering
        where ordering.home_source = 'mobile' and ordering.home_id = item.id
      ), greatest(0, item.slot_index))
  where item.is_storage
    and (public.inventory_item_is_mobile_home_storage(item.item_name, item.item_type)
      or public.inventory_item_is_caged_wagon_storage(item.item_name, item.item_type));

  insert into public.inventory_items (
    id, character_id, property_id, parent_item_id, item_name, display_name,
    item_description, item_type, rarity, quantity, slot_index, loadout_slot,
    is_accessory, is_storage, storage_active, storage_capacity, modifiers,
    enchantment, rune_name, material, enhancement_count, is_two_handed,
    potion_strength, potion_property, potion_quality, spell_book_form,
    created_at, updated_at
  )
  select
    legacy.id, null, legacy.house_id, legacy.parent_item_id, legacy.item_name, legacy.display_name,
    legacy.item_description, legacy.item_type, legacy.rarity, legacy.quantity,
    case
      when home.house_kind = 'stable' and legacy.parent_item_id is null and legacy.slot_index >= 1000
        then legacy.slot_index - 1000
      else greatest(0, legacy.slot_index)
    end,
    null, legacy.is_accessory, legacy.is_storage, legacy.is_storage,
    legacy.storage_capacity, legacy.modifiers, legacy.enchantment, legacy.rune_name,
    legacy.material, legacy.enhancement_count, legacy.is_two_handed,
    legacy.potion_strength, legacy.potion_property, legacy.potion_quality,
    1, legacy.created_at, legacy.updated_at
  from public.house_inventory_items legacy
  join public.player_houses home on home.id = legacy.house_id;

  select count(*) into v_mismatch_count
  from public.house_inventory_items legacy
  left join public.inventory_items item on item.id = legacy.id
  where item.id is null
    or item.property_id is distinct from legacy.house_id
    or item.parent_item_id is distinct from legacy.parent_item_id
    or item.item_name is distinct from legacy.item_name
    or item.display_name is distinct from legacy.display_name
    or item.item_description is distinct from legacy.item_description
    or item.item_type is distinct from legacy.item_type
    or item.rarity is distinct from legacy.rarity
    or item.quantity is distinct from legacy.quantity
    or item.is_accessory is distinct from legacy.is_accessory
    or item.is_storage is distinct from legacy.is_storage
    or item.storage_capacity is distinct from legacy.storage_capacity
    or item.modifiers is distinct from legacy.modifiers
    or item.enchantment is distinct from legacy.enchantment
    or item.rune_name is distinct from legacy.rune_name
    or item.material is distinct from legacy.material
    or item.enhancement_count is distinct from legacy.enhancement_count
    or item.is_two_handed is distinct from legacy.is_two_handed
    or item.potion_strength is distinct from legacy.potion_strength
    or item.potion_property is distinct from legacy.potion_property
    or item.potion_quality is distinct from legacy.potion_quality;
  if v_mismatch_count > 0 then
    raise exception 'Storage migration aborted: % house item metadata fingerprints did not match.', v_mismatch_count;
  end if;

  -- Legacy Property rows become real item instances in a compatible fixed property.
  for v_property in
    select property.*,
      caretaker.location_city_key,
      caretaker.location_name,
      legacy_house.city_name as house_city_name
    from public.campaign_properties property
    left join public.characters caretaker on caretaker.id = property.caretaker_character_id
    left join public.player_houses legacy_house on legacy_house.id = property.house_id
    order by property.created_at, property.id
  loop
    v_kind := case when v_property.is_pet or v_property.property_type in ('animal', 'pet', 'mount') then 'stable' else 'house' end;
    v_city_key := coalesce(
      case when v_property.property_location = 'at_house' then (
        select city.city_key from public.cities city
        where lower(trim(city.name)) = lower(trim(v_property.house_city_name))
          or city.city_key = public.safe_slug(v_property.house_city_name)
        order by (lower(trim(city.name)) = lower(trim(v_property.house_city_name))) desc
        limit 1
      ) else v_property.location_city_key end,
      (select city.city_key from public.cities city
        where lower(trim(city.name)) = lower(trim(v_property.location_name))
          or city.city_key = public.safe_slug(v_property.location_name)
        order by (lower(trim(city.name)) = lower(trim(v_property.location_name))) desc
        limit 1),
      nullif(public.safe_slug(case when v_property.property_location = 'at_house' then v_property.house_city_name else v_property.location_name end), ''),
      'wild'
    );
    v_target_property.id := null;
    select storage.* into v_target_property
    from public.storage_properties storage
    where storage.owner_user_id = v_property.owner_user_id
      and storage.property_kind = v_kind
      and storage.city_key = v_city_key
    order by storage.is_main desc, storage.display_order, storage.created_at, storage.id
    limit 1;

    if v_target_property.id is null then
      insert into public.storage_properties (
        owner_user_id, property_kind, city_key, property_name, capacity, display_order, is_main
      ) values (
        v_property.owner_user_id,
        v_kind,
        v_city_key,
        case when v_kind = 'stable' then 'Recovered Stable' else 'Recovered House' end,
        1,
        coalesce((select max(storage.display_order) + 10 from public.storage_properties storage where storage.owner_user_id = v_property.owner_user_id), 0),
        v_kind = 'house' and not exists (select 1 from public.storage_properties storage where storage.owner_user_id = v_property.owner_user_id and storage.property_kind = 'house' and storage.is_main)
      ) returning * into v_target_property;
    end if;

    select candidate.slot into v_slot
    from generate_series(0, greatest(0, v_target_property.capacity - 1)) candidate(slot)
    where not exists (
      select 1 from public.inventory_items occupied
      where occupied.property_id = v_target_property.id and occupied.parent_item_id is null
        and occupied.loadout_slot is null and occupied.slot_index = candidate.slot
    )
    order by candidate.slot limit 1;
    if v_slot is null then
      v_slot := v_target_property.capacity;
      update public.storage_properties set capacity = capacity + 1 where id = v_target_property.id returning * into v_target_property;
    end if;

    insert into public.inventory_items (
      id, character_id, property_id, parent_item_id, item_name, display_name,
      item_description, item_type, rarity, quantity, slot_index, loadout_slot,
      is_accessory, is_storage, storage_active, storage_capacity, modifiers,
      created_at, updated_at
    ) values (
      v_property.id, null, v_target_property.id, null, v_property.property_name, null,
      '', case when v_kind = 'stable' then 'pet' else case when v_property.property_type = 'wagon' then 'storage' else 'misc' end end,
      'Common', 1, v_slot, null, false,
      v_property.property_type = 'wagon' and v_property.storage_capacity > 0,
      v_property.property_type = 'wagon' and v_property.storage_capacity > 0,
      greatest(0, v_property.storage_capacity), '{}'::jsonb,
      v_property.created_at, v_property.updated_at
    );
  end loop;

  if (select count(*) from public.inventory_items item join public.house_inventory_items legacy on legacy.id = item.id) <> v_legacy_house_items then
    raise exception 'Storage migration aborted: expected % house items to survive.', v_legacy_house_items;
  end if;
  if (select count(*) from public.inventory_items item join public.campaign_properties legacy on legacy.id = item.id) <> v_legacy_properties then
    raise exception 'Storage migration aborted: expected % legacy properties to survive.', v_legacy_properties;
  end if;
  select count(*) into v_mismatch_count
  from public.campaign_properties legacy
  left join public.inventory_items item on item.id = legacy.id
  where item.id is null
    or item.item_name is distinct from legacy.property_name
    or item.item_type is distinct from case
      when legacy.is_pet or legacy.property_type in ('animal', 'pet', 'mount') then 'pet'
      when legacy.property_type = 'wagon' then 'storage'
      else 'misc' end
    or item.quantity is distinct from 1::numeric
    or item.is_storage is distinct from (legacy.property_type = 'wagon' and legacy.storage_capacity > 0)
    or item.storage_capacity is distinct from greatest(0, legacy.storage_capacity)
    or item.created_at is distinct from legacy.created_at;
  if v_mismatch_count > 0 then
    raise exception 'Storage migration aborted: % legacy property item fingerprints did not match.', v_mismatch_count;
  end if;
end;
$$;

do $$
declare
  v_item public.inventory_items%rowtype;
  v_slot integer;
  v_capacity integer;
begin
  for v_item in
    select * from public.inventory_items item
    where item.slot_index < 0
      and not (
        item.character_id is not null
        and item.parent_item_id is null
        and item.loadout_slot is null
        and item.is_storage
        and item.storage_active
      )
    order by item.created_at, item.id
  loop
    if v_item.loadout_slot is not null then
      update public.inventory_items set slot_index = 0 where id = v_item.id;
    elsif v_item.parent_item_id is not null then
      select parent.storage_capacity into v_capacity from public.inventory_items parent where parent.id = v_item.parent_item_id;
      select candidate.slot into v_slot
      from generate_series(0, greatest(0, v_capacity - 1)) candidate(slot)
      where not exists (
        select 1 from public.inventory_items occupied
        where occupied.parent_item_id = v_item.parent_item_id
          and occupied.loadout_slot is null
          and occupied.slot_index = candidate.slot
          and occupied.id <> v_item.id
      ) order by candidate.slot limit 1;
      if v_slot is null then
        v_slot := v_capacity;
        update public.inventory_items set storage_capacity = storage_capacity + 1 where id = v_item.parent_item_id;
      end if;
      update public.inventory_items set slot_index = v_slot where id = v_item.id;
    elsif v_item.property_id is not null then
      select storage.capacity into v_capacity from public.storage_properties storage where storage.id = v_item.property_id;
      select candidate.slot into v_slot
      from generate_series(0, greatest(0, v_capacity - 1)) candidate(slot)
      where not exists (
        select 1 from public.inventory_items occupied
        where occupied.property_id = v_item.property_id
          and occupied.parent_item_id is null
          and occupied.loadout_slot is null
          and occupied.slot_index = candidate.slot
          and occupied.id <> v_item.id
      ) order by candidate.slot limit 1;
      if v_slot is null then
        v_slot := v_capacity;
        update public.storage_properties set capacity = capacity + 1 where id = v_item.property_id;
      end if;
      update public.inventory_items set slot_index = v_slot where id = v_item.id;
    else
      select character.inventory_slots into v_capacity from public.characters character where character.id = v_item.character_id;
      select candidate.slot into v_slot
      from generate_series(0, greatest(0, v_capacity - 1)) candidate(slot)
      where not exists (
        select 1 from public.inventory_items occupied
        where occupied.character_id = v_item.character_id
          and occupied.parent_item_id is null
          and occupied.loadout_slot is null
          and occupied.slot_index = candidate.slot
          and occupied.id <> v_item.id
          and not (occupied.is_storage and occupied.storage_active)
      ) order by candidate.slot limit 1;
      if v_slot is null then
        v_slot := v_capacity;
        update public.characters set inventory_slots = inventory_slots + 1 where id = v_item.character_id;
      end if;
      update public.inventory_items set slot_index = v_slot where id = v_item.id;
    end if;
  end loop;
end;
$$;

-- ============================================================
-- CANONICAL STORAGE INSTALL START
-- The migration is complete; invariants and the canonical runtime follow.
-- ============================================================

create or replace function public.portable_property_kind(p_item_name text, p_item_type text)
returns text
language sql
immutable
as $$
  select case
    when public.inventory_item_is_caged_wagon_storage(p_item_name, p_item_type) then 'stable'
    when public.inventory_item_is_mobile_home_storage(p_item_name, p_item_type) then 'house'
    else null
  end
$$;

create or replace function public.inventory_container_property_kind(p_parent_item_id uuid)
returns text
language sql
stable
set search_path = public
as $$
  with recursive ancestry as (
    select item.id, item.parent_item_id, item.item_name, item.item_type
    from public.inventory_items item where item.id = p_parent_item_id
    union all
    select parent.id, parent.parent_item_id, parent.item_name, parent.item_type
    from public.inventory_items parent
    join ancestry child on child.parent_item_id = parent.id
  )
  select public.portable_property_kind(item_name, item_type)
  from ancestry
  where public.portable_property_kind(item_name, item_type) is not null
  order by case when parent_item_id is null then 0 else 1 end, id
  limit 1
$$;

-- Repair historical placements before enabling strict invariants.
do $$
declare
  v_item public.inventory_items%rowtype;
  v_source public.storage_properties%rowtype;
  v_destination public.storage_properties%rowtype;
  v_character public.characters%rowtype;
  v_slot integer;
  v_city_key text;
  v_owner_user_id uuid;
  v_needed_kind text;
begin
  -- Fixed properties: move every incompatible item tree to a compatible local property.
  for v_item in
    select item.*
    from public.inventory_items item
    join public.storage_properties storage on storage.id = item.property_id
    where item.parent_item_id is null
      and item.loadout_slot is null
      and (
        (storage.property_kind = 'house' and public.normalize_item_type(item.item_type) = 'pet')
        or (storage.property_kind = 'stable' and public.normalize_item_type(item.item_type) <> 'pet')
      )
    order by item.created_at, item.id
  loop
    select * into v_source from public.storage_properties where id = v_item.property_id;
    v_needed_kind := case when public.normalize_item_type(v_item.item_type) = 'pet' then 'stable' else 'house' end;
    v_destination.id := null;
    select storage.* into v_destination
    from public.storage_properties storage
    where storage.owner_user_id = v_source.owner_user_id
      and storage.city_key = v_source.city_key
      and storage.property_kind = v_needed_kind
    order by storage.is_main desc, storage.display_order, storage.created_at, storage.id
    limit 1;
    if v_destination.id is null then
      insert into public.storage_properties (
        owner_user_id, property_kind, city_key, property_name, capacity, display_order, is_main
      ) values (
        v_source.owner_user_id, v_needed_kind, v_source.city_key,
        case when v_needed_kind = 'stable' then 'Recovered Stable' else 'Recovered House' end,
        1,
        coalesce((select max(storage.display_order) + 10 from public.storage_properties storage where storage.owner_user_id = v_source.owner_user_id), 0),
        v_needed_kind = 'house' and not exists (select 1 from public.storage_properties storage where storage.owner_user_id = v_source.owner_user_id and storage.property_kind = 'house' and storage.is_main)
      ) returning * into v_destination;
    end if;
    select candidate.slot into v_slot
    from generate_series(0, greatest(0, v_destination.capacity - 1)) candidate(slot)
    where not exists (
      select 1 from public.inventory_items occupied
      where occupied.property_id = v_destination.id and occupied.parent_item_id is null
        and occupied.loadout_slot is null and occupied.slot_index = candidate.slot
    ) order by candidate.slot limit 1;
    if v_slot is null then
      v_slot := v_destination.capacity;
      update public.storage_properties set capacity = capacity + 1 where id = v_destination.id returning * into v_destination;
    end if;
    with recursive tree as (
      select item.id from public.inventory_items item where item.id = v_item.id
      union all
      select child.id from public.inventory_items child join tree parent on child.parent_item_id = parent.id
    )
    update public.inventory_items set character_id = null, property_id = v_destination.id
    where id in (select id from tree);
    update public.inventory_items set parent_item_id = null, slot_index = v_slot, loadout_slot = null where id = v_item.id;
  end loop;

  -- Direct inventory animals are recovered into a stable in their character's city.
  for v_item in
    select item.*
    from public.inventory_items item
    where item.character_id is not null
      and item.property_id is null
      and item.parent_item_id is null
      and item.loadout_slot is null
      and public.normalize_item_type(item.item_type) = 'pet'
    order by item.created_at, item.id
  loop
    select * into v_character from public.characters where id = v_item.character_id;
    if v_character.owner_user_id is null then
      raise exception 'Storage migration cannot preserve unowned animal %.', v_item.id;
    end if;
    v_owner_user_id := v_character.owner_user_id;
    v_city_key := coalesce(v_character.location_city_key,
      (select city.city_key from public.cities city where lower(trim(city.name)) = lower(trim(v_character.location_name)) limit 1),
      nullif(public.safe_slug(v_character.location_name), ''), 'wild');
    v_destination.id := null;
    select storage.* into v_destination
    from public.storage_properties storage
    where storage.owner_user_id = v_owner_user_id
      and storage.city_key = v_city_key
      and storage.property_kind = 'stable'
    order by storage.display_order, storage.created_at, storage.id limit 1;
    if v_destination.id is null then
      insert into public.storage_properties (
        owner_user_id, property_kind, city_key, property_name, capacity, display_order
      ) values (
        v_owner_user_id, 'stable', v_city_key, 'Recovered Stable', 1,
        coalesce((select max(storage.display_order) + 10 from public.storage_properties storage where storage.owner_user_id = v_owner_user_id), 0)
      ) returning * into v_destination;
    end if;
    select candidate.slot into v_slot
    from generate_series(0, greatest(0, v_destination.capacity - 1)) candidate(slot)
    where not exists (
      select 1 from public.inventory_items occupied
      where occupied.property_id = v_destination.id and occupied.parent_item_id is null
        and occupied.loadout_slot is null and occupied.slot_index = candidate.slot
    ) order by candidate.slot limit 1;
    if v_slot is null then
      v_slot := v_destination.capacity;
      update public.storage_properties set capacity = capacity + 1 where id = v_destination.id;
    end if;
    with recursive tree as (
      select item.id from public.inventory_items item where item.id = v_item.id
      union all select child.id from public.inventory_items child join tree parent on child.parent_item_id = parent.id
    )
    update public.inventory_items set character_id = null, property_id = v_destination.id
    where id in (select id from tree);
    update public.inventory_items set parent_item_id = null, slot_index = v_slot where id = v_item.id;
  end loop;

  -- Preserve over-capacity historical roots by expanding only as far as needed.
  update public.storage_properties storage
  set capacity = greatest(storage.capacity, occupied.required_capacity)
  from (
    select item.property_id, max(item.slot_index) + 1 as required_capacity
    from public.inventory_items item
    where item.property_id is not null and item.parent_item_id is null and item.loadout_slot is null
    group by item.property_id
  ) occupied
  where storage.id = occupied.property_id and storage.capacity < occupied.required_capacity;
end;
$$;

-- Active additional storage is deployed beside the base inventory. It uses a
-- zero-based sentinel position and never occupies a visible base slot.
update public.inventory_items
set storage_active = false
where storage_active
  and (
    character_id is null
    or property_id is not null
    or parent_item_id is not null
    or loadout_slot is not null
    or not is_storage
    or public.additional_storage_kind(item_name, item_type) is null
  );

update public.inventory_items candidate
set storage_active = true,
    slot_index = 0
where candidate.id in (
  select distinct on (item.character_id, public.additional_storage_kind(item.item_name, item.item_type)) item.id
  from public.inventory_items item
  where item.character_id is not null
    and item.parent_item_id is null
    and item.loadout_slot is null
    and item.is_storage
    and public.additional_storage_kind(item.item_name, item.item_type) is not null
    and not exists (
      select 1
      from public.inventory_items active
      where active.character_id = item.character_id
        and active.parent_item_id is null
        and active.loadout_slot is null
        and active.is_storage
        and active.storage_active
        and public.additional_storage_kind(active.item_name, active.item_type)
          = public.additional_storage_kind(item.item_name, item.item_type)
    )
  order by item.character_id, public.additional_storage_kind(item.item_name, item.item_type), item.created_at, item.id
);

update public.inventory_items
set slot_index = 0
where character_id is not null
  and parent_item_id is null
  and loadout_slot is null
  and is_storage
  and storage_active;

do $$
declare
  v_duplicate record;
  v_child public.inventory_items%rowtype;
  v_slot integer;
  v_capacity integer;
begin
  for v_duplicate in
    with ranked as (
      select item.id, item.character_id, item.slot_index,
        first_value(item.id) over (
          partition by item.character_id, public.additional_storage_kind(item.item_name, item.item_type)
          order by item.storage_active desc, item.created_at, item.id
        ) as primary_id,
        row_number() over (
          partition by item.character_id, public.additional_storage_kind(item.item_name, item.item_type)
          order by item.storage_active desc, item.created_at, item.id
        ) as storage_rank
      from public.inventory_items item
      where item.character_id is not null
        and item.parent_item_id is null
        and item.loadout_slot is null
        and item.is_storage
        and public.additional_storage_kind(item.item_name, item.item_type) is not null
    )
    select * from ranked where storage_rank > 1
  loop
    for v_child in
      select * from public.inventory_items child
      where child.parent_item_id = v_duplicate.id
      order by child.slot_index, child.created_at, child.id
    loop
      select parent.storage_capacity into v_capacity
      from public.inventory_items parent where parent.id = v_duplicate.primary_id;
      select candidate.slot into v_slot
      from generate_series(0, greatest(0, v_capacity - 1)) candidate(slot)
      where not exists (
        select 1 from public.inventory_items occupied
        where occupied.parent_item_id = v_duplicate.primary_id
          and occupied.loadout_slot is null
          and occupied.slot_index = candidate.slot
      )
      order by candidate.slot limit 1;
      if v_slot is null then
        v_slot := v_capacity;
        update public.inventory_items
        set storage_capacity = storage_capacity + 1
        where id = v_duplicate.primary_id;
      end if;
      update public.inventory_items
      set parent_item_id = v_duplicate.primary_id,
          slot_index = v_slot
      where id = v_child.id;
    end loop;

    v_slot := null;
    select v_duplicate.slot_index into v_slot
    from public.characters character
    where character.id = v_duplicate.character_id
      and v_duplicate.slot_index between 0 and character.inventory_slots - 1
      and not exists (
        select 1 from public.inventory_items occupied
        where occupied.character_id = character.id
          and occupied.id <> v_duplicate.id
          and occupied.parent_item_id is null
          and occupied.loadout_slot is null
          and occupied.slot_index = v_duplicate.slot_index
          and not (occupied.is_storage and occupied.storage_active)
      );
    if v_slot is null then
      select candidate.slot into v_slot
      from public.characters character
      cross join lateral generate_series(0, greatest(0, character.inventory_slots - 1)) candidate(slot)
      where character.id = v_duplicate.character_id
        and not exists (
          select 1 from public.inventory_items occupied
          where occupied.character_id = character.id
            and occupied.id <> v_duplicate.id
            and occupied.parent_item_id is null
            and occupied.loadout_slot is null
            and occupied.slot_index = candidate.slot
            and not (occupied.is_storage and occupied.storage_active)
        )
      order by candidate.slot limit 1;
    end if;
    if v_slot is null then
      update public.characters
      set inventory_slots = inventory_slots + 1
      where id = v_duplicate.character_id
      returning inventory_slots - 1 into v_slot;
    end if;
    update public.inventory_items
    set storage_active = false,
        slot_index = v_slot
    where id = v_duplicate.id;
  end loop;
end;
$$;

-- Wagon Homes and Caged Wagons are portable properties, not deployed bonus
-- inventory. Give each carried property a normal visible inventory slot.
do $$
declare
  v_property_item public.inventory_items%rowtype;
  v_slot integer;
begin
  for v_property_item in
    select item.* from public.inventory_items item
    where item.parent_item_id is null
      and item.loadout_slot is null
      and public.portable_property_kind(item.item_name, item.item_type) is not null
    order by item.created_at, item.id
  loop
    if v_property_item.character_id is not null then
      select candidate.slot into v_slot
      from public.characters character
      cross join lateral generate_series(0, greatest(0, character.inventory_slots - 1)) candidate(slot)
      where character.id = v_property_item.character_id
        and not exists (
          select 1 from public.inventory_items occupied
          where occupied.character_id = character.id
            and occupied.id <> v_property_item.id
            and occupied.parent_item_id is null
            and occupied.loadout_slot is null
            and occupied.slot_index = candidate.slot
            and not (occupied.is_storage and occupied.storage_active)
        )
      order by candidate.slot limit 1;
      if v_slot is null then
        update public.characters
        set inventory_slots = inventory_slots + 1
        where id = v_property_item.character_id
        returning inventory_slots - 1 into v_slot;
      end if;
      update public.inventory_items
      set storage_active = false, slot_index = v_slot
      where id = v_property_item.id;
    else
      update public.inventory_items set storage_active = false where id = v_property_item.id;
    end if;
  end loop;
end;
$$;

alter table public.inventory_items drop constraint if exists inventory_items_visible_or_storage_slot_check;
alter table public.inventory_items drop constraint if exists inventory_items_canonical_location_check;
alter table public.inventory_items add constraint inventory_items_canonical_location_check check (
  ((character_id is not null)::integer + (property_id is not null)::integer) = 1
  and slot_index >= 0
  and (property_id is null or loadout_slot is null)
);

create unique index inventory_character_root_slot_unique
  on public.inventory_items(character_id, slot_index)
  where character_id is not null and parent_item_id is null and loadout_slot is null
    and not (is_storage and storage_active);
create unique index inventory_character_active_storage_kind_unique
  on public.inventory_items(character_id, public.additional_storage_kind(item_name, item_type))
  where character_id is not null and parent_item_id is null and loadout_slot is null
    and is_storage and storage_active
    and public.additional_storage_kind(item_name, item_type) is not null;
create unique index inventory_property_root_slot_unique
  on public.inventory_items(property_id, slot_index)
  where property_id is not null and parent_item_id is null and loadout_slot is null;
create unique index inventory_child_slot_unique
  on public.inventory_items(parent_item_id, slot_index)
  where parent_item_id is not null and loadout_slot is null;
create unique index inventory_character_loadout_slot_unique
  on public.inventory_items(character_id, loadout_slot)
  where character_id is not null and loadout_slot is not null;
create index inventory_items_property_idx on public.inventory_items(property_id);

create or replace function public.assert_inventory_item_placement(
  p_item_id uuid,
  p_item_name text,
  p_item_type text,
  p_character_id uuid,
  p_property_id uuid,
  p_parent_item_id uuid,
  p_slot_index integer,
  p_loadout_slot text
)
returns void
language plpgsql
set search_path = public
as $$
declare
  v_property public.storage_properties%rowtype;
  v_character public.characters%rowtype;
  v_parent public.inventory_items%rowtype;
  v_effective_kind text;
  v_is_pet boolean := public.normalize_item_type(p_item_type) = 'pet';
  v_portable_kind text := public.portable_property_kind(p_item_name, p_item_type);
begin
  if ((p_character_id is not null)::integer + (p_property_id is not null)::integer) <> 1 then
    raise exception 'An item must belong to exactly one character or property.';
  end if;
  if p_slot_index < 0 then raise exception 'Storage slots use zero-based non-negative indices.'; end if;
  if p_property_id is not null and p_loadout_slot is not null then raise exception 'Property items cannot occupy loadout slots.'; end if;

  if p_parent_item_id is not null then
    if p_parent_item_id = p_item_id then raise exception 'An item cannot contain itself.'; end if;
    select * into v_parent from public.inventory_items where id = p_parent_item_id;
    if v_parent.id is null or not v_parent.is_storage then raise exception 'Destination container was not found.'; end if;
    if v_parent.character_id is distinct from p_character_id or v_parent.property_id is distinct from p_property_id then
      raise exception 'Container trees must remain in one location.';
    end if;
    if p_slot_index >= v_parent.storage_capacity then raise exception 'That container slot does not exist.'; end if;
    if v_portable_kind is not null then raise exception 'Portable properties cannot be nested inside another container.'; end if;
    if exists (
      with recursive descendants as (
        select item.id from public.inventory_items item where item.parent_item_id = p_item_id
        union all select child.id from public.inventory_items child join descendants parent on child.parent_item_id = parent.id
      ) select 1 from descendants where id = p_parent_item_id
    ) then raise exception 'An item cannot be moved inside its own contents.'; end if;
    v_effective_kind := public.inventory_container_property_kind(p_parent_item_id);
  elsif p_property_id is not null then
    select * into v_property from public.storage_properties where id = p_property_id;
    if v_property.id is null then raise exception 'Storage property not found.'; end if;
    if p_slot_index >= v_property.capacity then raise exception 'That property slot does not exist.'; end if;
    v_effective_kind := v_property.property_kind;
  elsif p_loadout_slot is null then
    select * into v_character from public.characters where id = p_character_id;
    if v_character.id is null then raise exception 'Character not found.'; end if;
    if p_slot_index >= v_character.inventory_slots then raise exception 'That inventory slot does not exist.'; end if;
  end if;

  if p_loadout_slot = 'active-pet' and not v_is_pet then raise exception 'Only animals can occupy active pet slots.'; end if;
  if p_loadout_slot is not null and p_loadout_slot <> 'active-pet' and v_is_pet then raise exception 'Animals can only occupy active pet slots.'; end if;
  if v_effective_kind = 'stable' and not v_is_pet then raise exception 'Stables and Caged Wagons only accept animals.'; end if;
  if v_effective_kind = 'house' and v_is_pet then raise exception 'Animals require a stable or Caged Wagon.'; end if;
  if v_effective_kind is null and p_loadout_slot is null and v_is_pet then raise exception 'Animals require a stable, Caged Wagon, or active pet slot.'; end if;
end;
$$;

create or replace function public.validate_inventory_item_placement()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_setting('app.canonical_storage_move', true) = 'on' then return new; end if;
  if new.storage_active and (
    new.character_id is null
    or new.property_id is not null
    or new.parent_item_id is not null
    or new.loadout_slot is not null
    or not new.is_storage
    or public.additional_storage_kind(new.item_name, new.item_type) is null
  ) then
    raise exception 'Only a carried root additional-storage item can be active.';
  end if;
  perform public.assert_inventory_item_placement(
    new.id, new.item_name, new.item_type, new.character_id, new.property_id,
    new.parent_item_id, new.slot_index, new.loadout_slot
  );
  return new;
end;
$$;

drop trigger if exists validate_inventory_item_placement_trigger on public.inventory_items;
create trigger validate_inventory_item_placement_trigger
before insert or update of character_id, property_id, parent_item_id, slot_index, loadout_slot, item_name, item_type, is_storage, storage_active
on public.inventory_items for each row execute function public.validate_inventory_item_placement();

create or replace function public.storage_property_accessible(
  p_profile public.profiles,
  p_property public.storage_properties,
  p_actor_character_id uuid
)
returns boolean
language plpgsql
stable
set search_path = public
as $$
declare
  v_actor public.characters%rowtype;
  v_actor_city_key text;
begin
  if p_profile.role = 'dm'::public.user_role then return true; end if;
  if p_profile.id is distinct from p_property.owner_user_id or p_property.is_locked then return false; end if;
  if p_actor_character_id is null then return false; end if;
  select * into v_actor from public.characters where id = p_actor_character_id;
  if v_actor.id is null or v_actor.owner_user_id is distinct from p_property.owner_user_id then return false; end if;
  v_actor_city_key := coalesce(v_actor.location_city_key,
    (select city.city_key from public.cities city where lower(trim(city.name)) = lower(trim(v_actor.location_name)) limit 1),
    nullif(public.safe_slug(v_actor.location_name), ''), 'wild');
  return v_actor_city_key is not distinct from p_property.city_key;
end;
$$;

create or replace function public.assert_storage_property_access(
  p_profile public.profiles,
  p_property_id uuid,
  p_actor_character_id uuid
)
returns public.storage_properties
language plpgsql
stable
set search_path = public
as $$
declare
  v_property public.storage_properties%rowtype;
begin
  select * into v_property from public.storage_properties where id = p_property_id;
  if v_property.id is null then raise exception 'Storage property not found.'; end if;
  if not public.storage_property_accessible(p_profile, v_property, p_actor_character_id) then
    if v_property.is_locked then raise exception 'That property is locked by the Dungeon Master.'; end if;
    raise exception 'A controlled character must be in the property''s city to use it.';
  end if;
  return v_property;
end;
$$;

create or replace function public.inventory_item_owner_user_id(p_item public.inventory_items)
returns uuid
language sql
stable
set search_path = public
as $$
  select case
    when p_item.character_id is not null then (select character.owner_user_id from public.characters character where character.id = p_item.character_id)
    else (select storage.owner_user_id from public.storage_properties storage where storage.id = p_item.property_id)
  end
$$;

create or replace function public.assert_inventory_item_control(
  p_profile public.profiles,
  p_item public.inventory_items,
  p_actor_character_id uuid
)
returns void
language plpgsql
stable
set search_path = public
as $$
declare
  v_owner_user_id uuid;
  v_property public.storage_properties%rowtype;
  v_actor public.characters%rowtype;
  v_carrier public.characters%rowtype;
begin
  v_owner_user_id := public.inventory_item_owner_user_id(p_item);
  if p_profile.role = 'dm'::public.user_role then return; end if;
  if v_owner_user_id is null or v_owner_user_id is distinct from p_profile.id then
    raise exception 'You do not control that item.';
  end if;
  if p_item.property_id is not null then
    perform public.assert_storage_property_access(p_profile, p_item.property_id, p_actor_character_id);
    return;
  end if;
  if p_actor_character_id is null then raise exception 'Choose the acting character for this move.'; end if;
  select * into v_actor from public.characters where id = p_actor_character_id;
  select * into v_carrier from public.characters where id = p_item.character_id;
  if v_actor.owner_user_id is distinct from p_profile.id then raise exception 'You do not control the acting character.'; end if;
  if v_carrier.owner_user_id is distinct from p_profile.id then raise exception 'You do not control the item carrier.'; end if;
  if coalesce(v_actor.location_city_key, nullif(public.safe_slug(v_actor.location_name), ''), 'wild')
    is distinct from coalesce(v_carrier.location_city_key, nullif(public.safe_slug(v_carrier.location_name), ''), 'wild')
  then raise exception 'The acting character is not with that mobile property.'; end if;
end;
$$;

create or replace function public.ensure_character_additional_storage_activation(p_character_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_kind text;
  v_candidate_id uuid;
begin
  if p_character_id is null then return; end if;

  update public.inventory_items item
  set storage_active = false,
      updated_at = now()
  where item.character_id = p_character_id
    and item.storage_active
    and (
      item.property_id is not null
      or item.parent_item_id is not null
      or item.loadout_slot is not null
      or not item.is_storage
      or public.additional_storage_kind(item.item_name, item.item_type) is null
    );

  for v_kind in
    select distinct public.additional_storage_kind(item.item_name, item.item_type)
    from public.inventory_items item
    where item.character_id = p_character_id
      and item.property_id is null
      and item.parent_item_id is null
      and item.loadout_slot is null
      and item.is_storage
      and public.additional_storage_kind(item.item_name, item.item_type) is not null
  loop
    if not exists (
      select 1 from public.inventory_items active
      where active.character_id = p_character_id
        and active.property_id is null
        and active.parent_item_id is null
        and active.loadout_slot is null
        and active.is_storage
        and active.storage_active
        and public.additional_storage_kind(active.item_name, active.item_type) = v_kind
    ) then
      select item.id into v_candidate_id
      from public.inventory_items item
      where item.character_id = p_character_id
        and item.property_id is null
        and item.parent_item_id is null
        and item.loadout_slot is null
        and item.is_storage
        and not item.storage_active
        and public.additional_storage_kind(item.item_name, item.item_type) = v_kind
      order by item.created_at, item.id
      limit 1;
      if v_candidate_id is not null then
        update public.inventory_items
        set storage_active = true, slot_index = 0, updated_at = now()
        where id = v_candidate_id;
      end if;
    end if;
    v_candidate_id := null;
  end loop;
end;
$$;

create or replace function public.move_inventory_item_instance(
  p_profile public.profiles,
  p_actor_character_id uuid,
  p_item_id uuid,
  p_destination_character_id uuid,
  p_destination_property_id uuid,
  p_destination_parent_item_id uuid,
  p_destination_slot_index integer,
  p_destination_loadout_slot text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_item public.inventory_items%rowtype;
  v_target public.inventory_items%rowtype;
  v_destination_parent public.inventory_items%rowtype;
  v_source_character_id uuid;
  v_source_property_id uuid;
  v_source_parent_item_id uuid;
  v_source_slot_index integer;
  v_source_loadout_slot text;
  v_destination_character public.characters%rowtype;
begin
  select * into v_item from public.inventory_items where id = p_item_id for update;
  if v_item.id is null then raise exception 'Item not found.'; end if;
  perform public.assert_inventory_item_control(p_profile, v_item, p_actor_character_id);

  if p_destination_parent_item_id is not null then
    select * into v_destination_parent from public.inventory_items where id = p_destination_parent_item_id for update;
    if v_destination_parent.id is null then raise exception 'Destination container not found.'; end if;
    p_destination_character_id := v_destination_parent.character_id;
    p_destination_property_id := v_destination_parent.property_id;
    p_destination_loadout_slot := null;
  end if;

  if ((p_destination_character_id is not null)::integer + (p_destination_property_id is not null)::integer) <> 1 then
    raise exception 'Choose exactly one destination location.';
  end if;
  if p_destination_property_id is not null then
    perform public.assert_storage_property_access(p_profile, p_destination_property_id, p_actor_character_id);
  else
    select * into v_destination_character from public.characters where id = p_destination_character_id;
    if v_destination_character.id is null then raise exception 'Destination character not found.'; end if;
    perform public.assert_inventory_access(p_profile, p_destination_character_id, false);
  end if;

  perform public.assert_inventory_item_placement(
    v_item.id, v_item.item_name, v_item.item_type,
    p_destination_character_id, p_destination_property_id, p_destination_parent_item_id,
    p_destination_slot_index, p_destination_loadout_slot
  );

  if p_destination_parent_item_id is not null then
    select * into v_target from public.inventory_items target
    where target.parent_item_id = p_destination_parent_item_id
      and target.slot_index = p_destination_slot_index and target.loadout_slot is null
    for update;
  elsif p_destination_property_id is not null then
    select * into v_target from public.inventory_items target
    where target.property_id = p_destination_property_id and target.parent_item_id is null
      and target.slot_index = p_destination_slot_index and target.loadout_slot is null
    for update;
  elsif p_destination_loadout_slot is not null then
    select * into v_target from public.inventory_items target
    where target.character_id = p_destination_character_id and target.loadout_slot = p_destination_loadout_slot
    for update;
  else
    select * into v_target from public.inventory_items target
    where target.character_id = p_destination_character_id and target.parent_item_id is null
      and target.slot_index = p_destination_slot_index and target.loadout_slot is null
      and not (target.is_storage and target.storage_active)
    for update;
  end if;

  if v_target.id = v_item.id then return v_item.id; end if;
  if v_target.id is not null and public.inventory_items_stackable(v_target, v_item) then
    update public.inventory_items set quantity = quantity + v_item.quantity, updated_at = now() where id = v_target.id;
    delete from public.inventory_items where id = v_item.id;
    return v_target.id;
  end if;

  v_source_character_id := v_item.character_id;
  v_source_property_id := v_item.property_id;
  v_source_parent_item_id := v_item.parent_item_id;
  v_source_slot_index := v_item.slot_index;
  v_source_loadout_slot := v_item.loadout_slot;

  if v_target.id is not null and v_item.storage_active then
    raise exception 'Move active additional storage into an empty destination slot.';
  end if;

  if v_target.id is not null then
    perform public.assert_inventory_item_control(p_profile, v_target, p_actor_character_id);
    perform public.assert_inventory_item_placement(
      v_target.id, v_target.item_name, v_target.item_type,
      v_source_character_id, v_source_property_id, v_source_parent_item_id,
      v_source_slot_index, v_source_loadout_slot
    );
  end if;

  perform set_config('app.canonical_storage_move', 'on', true);
  if v_target.id is not null then
    update public.inventory_items set slot_index = 2147483647 where id = v_target.id;
  end if;
  update public.inventory_items set slot_index = 2147483646 where id = v_item.id;

  with recursive moving as (
    select item.id from public.inventory_items item where item.id = v_item.id
    union all select child.id from public.inventory_items child join moving parent on child.parent_item_id = parent.id
  )
  update public.inventory_items
  set character_id = p_destination_character_id, property_id = p_destination_property_id
  where id in (select id from moving);
  update public.inventory_items
  set parent_item_id = p_destination_parent_item_id,
      slot_index = p_destination_slot_index,
      loadout_slot = p_destination_loadout_slot,
      storage_active = case
        when public.additional_storage_kind(item_name, item_type) is not null
          and (p_destination_property_id is not null or p_destination_parent_item_id is not null or p_destination_loadout_slot is not null)
        then false
        else storage_active
      end,
      updated_at = now()
  where id = v_item.id;

  if v_target.id is not null then
    with recursive swapping as (
      select item.id from public.inventory_items item where item.id = v_target.id
      union all select child.id from public.inventory_items child join swapping parent on child.parent_item_id = parent.id
    )
    update public.inventory_items
    set character_id = v_source_character_id, property_id = v_source_property_id
    where id in (select id from swapping);
    update public.inventory_items
    set parent_item_id = v_source_parent_item_id,
        slot_index = v_source_slot_index,
        loadout_slot = v_source_loadout_slot,
        storage_active = case
          when public.additional_storage_kind(item_name, item_type) is not null
            and (v_source_property_id is not null or v_source_parent_item_id is not null or v_source_loadout_slot is not null)
          then false
          else storage_active
        end,
        updated_at = now()
    where id = v_target.id;
  end if;
  perform set_config('app.canonical_storage_move', 'off', true);

  perform public.ensure_character_additional_storage_activation(v_source_character_id);
  if p_destination_character_id is distinct from v_source_character_id then
    perform public.ensure_character_additional_storage_activation(p_destination_character_id);
  end if;

  select * into v_item from public.inventory_items where id = v_item.id;
  perform public.assert_inventory_item_placement(v_item.id, v_item.item_name, v_item.item_type, v_item.character_id, v_item.property_id, v_item.parent_item_id, v_item.slot_index, v_item.loadout_slot);
  if v_target.id is not null then
    select * into v_target from public.inventory_items where id = v_target.id;
    perform public.assert_inventory_item_placement(v_target.id, v_target.item_name, v_target.item_type, v_target.character_id, v_target.property_id, v_target.parent_item_id, v_target.slot_index, v_target.loadout_slot);
  end if;
  return v_item.id;
end;
$$;

-- The inventory editor uses the same atomic movement service as houses. This
-- replaces the former negative temporary-slot swap implementation.
create or replace function public.update_inventory_item_state_impl(
  p_session_token text,
  p_item_id uuid,
  p_patch jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_character public.characters%rowtype;
  v_item public.inventory_items%rowtype;
  v_target public.inventory_items%rowtype;
  v_patch jsonb := coalesce(p_patch, '{}'::jsonb);
  v_parent_item_id uuid;
  v_slot_index integer;
  v_loadout_slot text;
  v_storage_kind text;
  v_free_slot integer;
  v_child_max_slot integer;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;
  select * into v_item from public.inventory_items where id = p_item_id for update;
  if v_item.id is null or v_item.character_id is null then raise exception 'Inventory item not found.'; end if;
  v_character := public.assert_inventory_access(v_profile, v_item.character_id, false);

  if (v_patch ? 'name' or v_patch ? 'type' or v_patch ? 'rarity' or v_patch ? 'quantity'
      or v_patch ? 'isStorage' or v_patch ? 'isAccessory' or v_patch ? 'storageCapacity'
      or v_patch ? 'modifiers' or v_patch ? 'enchantment' or v_patch ? 'material'
      or v_patch ? 'enhancementCount' or v_patch ? 'isTwoHanded' or v_patch ? 'potionStrength'
      or v_patch ? 'potionProperty' or v_patch ? 'potionQuality' or v_patch ? 'itemDescription')
    and v_profile.role <> 'dm'::public.user_role
  then
    raise exception 'Only the Dungeon Master can edit item details.';
  end if;

  if v_patch ? 'spellBookForm' and (
    public.normalize_item_type(v_item.item_type) <> 'spell book'
    or lower(public.normalize_item_name(v_item.item_name)) <> lower(public.normalize_item_name('Peaceful Restoration Spell Book'))
  ) then
    raise exception 'Only Peaceful Restoration spell books can change form.';
  end if;
  if v_patch ? 'displayName' and public.normalize_item_type(v_item.item_type) <> 'pet' then
    raise exception 'Only pet items can be named.';
  end if;

  if v_profile.role = 'dm'::public.user_role then
    if v_patch ? 'storageCapacity' then
      select max(child.slot_index) into v_child_max_slot
      from public.inventory_items child where child.parent_item_id = v_item.id and child.loadout_slot is null;
      if greatest(0, (v_patch->>'storageCapacity')::integer) <= coalesce(v_child_max_slot, -1) then
        raise exception 'Empty every slot beyond the new capacity before reducing it.';
      end if;
    end if;
    if v_patch ? 'isStorage' and not (v_patch->>'isStorage')::boolean
      and exists (select 1 from public.inventory_items child where child.parent_item_id = v_item.id)
    then
      raise exception 'Empty this storage item before removing its storage capacity.';
    end if;

    update public.inventory_items
    set item_name = case when v_patch ? 'name' then public.normalize_item_name(coalesce(nullif(trim(v_patch->>'name'), ''), item_name)) else item_name end,
        item_type = case when v_patch ? 'type' then public.normalize_item_type(v_patch->>'type') else item_type end,
        rarity = case when v_patch ? 'rarity' then (v_patch->>'rarity')::public.item_rarity else rarity end,
        quantity = case when v_patch ? 'quantity' then public.assert_valid_item_quantity(
          coalesce(nullif(trim(v_patch->>'name'), ''), item_name),
          case when v_patch ? 'type' then public.normalize_item_type(v_patch->>'type') else item_type end,
          (v_patch->>'quantity')::numeric
        ) else quantity end,
        item_description = case when v_patch ? 'itemDescription' then left(trim(coalesce(v_patch->>'itemDescription', '')), 1500) else item_description end,
        is_accessory = case when v_patch ? 'isAccessory' then (v_patch->>'isAccessory')::boolean else is_accessory end,
        is_storage = case when v_patch ? 'isStorage' then (v_patch->>'isStorage')::boolean else is_storage end,
        storage_capacity = case when v_patch ? 'storageCapacity' then greatest(0, least(500, (v_patch->>'storageCapacity')::integer)) else storage_capacity end,
        modifiers = case when v_patch ? 'modifiers' and jsonb_typeof(v_patch->'modifiers') = 'object' then v_patch->'modifiers' else modifiers end,
        enchantment = case
          when v_patch ? 'enhancementCount' and (v_patch->>'enhancementCount')::integer > 0 then null
          when v_patch ? 'enchantment' then nullif(trim(coalesce(v_patch->>'enchantment', '')), '')
          else enchantment end,
        material = case when v_patch ? 'material' then trim(coalesce(v_patch->>'material', '')) else material end,
        enhancement_count = case
          when v_patch ? 'enchantment' and length(trim(coalesce(v_patch->>'enchantment', ''))) > 0 then 0
          when v_patch ? 'enhancementCount' then least(3, greatest(0, (v_patch->>'enhancementCount')::integer))
          else enhancement_count end,
        is_two_handed = case when v_patch ? 'isTwoHanded' then (v_patch->>'isTwoHanded')::boolean else is_two_handed end,
        potion_strength = case
          when case when v_patch ? 'type' then public.normalize_item_type(v_patch->>'type') else item_type end <> 'potion' then null
          when v_patch ? 'potionStrength' then nullif(trim(coalesce(v_patch->>'potionStrength', '')), '')
          when v_patch ? 'name' then public.potion_strength_from_name(v_patch->>'name')
          else potion_strength end,
        potion_property = case
          when case when v_patch ? 'type' then public.normalize_item_type(v_patch->>'type') else item_type end <> 'potion' then null
          when v_patch ? 'potionProperty' then nullif(trim(coalesce(v_patch->>'potionProperty', '')), '')
          when v_patch ? 'name' then public.potion_property_from_name(v_patch->>'name')
          else potion_property end,
        potion_quality = case
          when case when v_patch ? 'type' then public.normalize_item_type(v_patch->>'type') else item_type end <> 'potion' then null
          when coalesce(nullif(trim(coalesce(v_patch->>'potionProperty', '')), ''), potion_property,
            public.potion_property_from_name(coalesce(v_patch->>'name', item_name))) in ('Healing', 'Mana Regen') then null
          when lower(public.normalize_item_name(coalesce(v_patch->>'name', item_name))) = 'empty flask' then null
          when v_patch ? 'potionQuality' then nullif(trim(coalesce(v_patch->>'potionQuality', '')), '')
          when v_patch ? 'name' then public.potion_quality_from_name(v_patch->>'name')
          else potion_quality end,
        updated_at = now()
    where id = v_item.id
    returning * into v_item;

    if public.normalize_item_type(v_item.item_type) = 'potion'
      and v_item.potion_strength is not null and v_item.potion_property is not null
    then
      update public.inventory_items
      set item_name = public.format_potion_item_name(v_item.potion_strength, v_item.potion_property, v_item.potion_quality),
          rarity = public.potion_rarity_for(v_item.potion_strength, v_item.potion_property), updated_at = now()
      where id = v_item.id returning * into v_item;
    end if;
    if not public.inventory_item_is_mythril(v_item.item_name, v_item.material) and v_item.rune_name is not null then
      update public.inventory_items set rune_name = null, updated_at = now() where id = v_item.id returning * into v_item;
    end if;
  end if;

  if v_patch ? 'displayName' then
    update public.inventory_items
    set display_name = nullif(left(trim(coalesce(v_patch->>'displayName', '')), 80), ''), updated_at = now()
    where id = v_item.id returning * into v_item;
  elsif public.normalize_item_type(v_item.item_type) <> 'pet' and v_item.display_name is not null then
    update public.inventory_items set display_name = null, updated_at = now() where id = v_item.id returning * into v_item;
  end if;

  if v_patch ? 'spellBookForm' then
    update public.inventory_items
    set spell_book_form = least(2, greatest(1, (v_patch->>'spellBookForm')::integer)), updated_at = now()
    where id = v_item.id returning * into v_item;
  end if;

  if v_patch ? 'storageActive' then
    v_storage_kind := public.additional_storage_kind(v_item.item_name, v_item.item_type);
    if not v_item.is_storage or v_storage_kind is null then
      raise exception 'Only carried additional storage can be activated or packed up.';
    end if;
    if coalesce((v_patch->>'storageActive')::boolean, false) then
      if exists (
        select 1 from public.inventory_items active
        where active.character_id = v_item.character_id and active.id <> v_item.id
          and active.parent_item_id is null and active.loadout_slot is null
          and active.is_storage and active.storage_active
          and public.additional_storage_kind(active.item_name, active.item_type) = v_storage_kind
      ) then raise exception 'Only one % can be active additional storage.', v_item.item_name; end if;
      update public.inventory_items
      set storage_active = true, parent_item_id = null, loadout_slot = null, slot_index = 0, updated_at = now()
      where id = v_item.id returning * into v_item;
    else
      if exists (select 1 from public.inventory_items child where child.parent_item_id = v_item.id) then
        raise exception 'Empty this storage before packing it up.';
      end if;
      v_free_slot := public.first_free_character_slot(v_item.character_id);
      if v_free_slot is null then raise exception 'No open inventory slot.'; end if;
      update public.inventory_items
      set storage_active = false, parent_item_id = null, loadout_slot = null,
          slot_index = v_free_slot, updated_at = now()
      where id = v_item.id returning * into v_item;
    end if;
    return public.inventory_item_record_to_json(v_item);
  end if;

  if v_patch ? 'loadoutSlot' and not (v_patch ? 'slotIndex' or v_patch ? 'parentItemId') then
    v_loadout_slot := nullif(v_patch->>'loadoutSlot', '');
    if v_loadout_slot is null then
      if public.normalize_item_type(v_item.item_type) = 'pet' then
        raise exception 'Use Send to stable to remove an active animal.';
      end if;
      v_slot_index := public.first_free_character_slot(v_item.character_id);
      if v_slot_index is null then raise exception 'No open inventory slot.'; end if;
      perform public.move_inventory_item_instance(v_profile, v_item.character_id, v_item.id,
        v_item.character_id, null, null, v_slot_index, null);
    else
      if not public.loadout_slot_accepts_item(v_loadout_slot, v_item.item_type, v_item.is_accessory) then
        raise exception 'That item cannot go in that loadout slot.';
      end if;
      if v_loadout_slot = 'shield' and exists (
        select 1 from public.inventory_items equipped
        where equipped.character_id = v_item.character_id and equipped.loadout_slot = 'weapon' and equipped.is_two_handed
      ) then raise exception 'A shield cannot be active with a heavy two-handed weapon.'; end if;
      if v_loadout_slot = 'weapon' and v_item.is_two_handed and exists (
        select 1 from public.inventory_items equipped
        where equipped.character_id = v_item.character_id and equipped.loadout_slot = 'shield'
      ) then raise exception 'A heavy two-handed weapon cannot be active with a shield.'; end if;
      if exists (
        select 1 from public.inventory_items equipped
        where equipped.character_id = v_item.character_id and equipped.loadout_slot = v_loadout_slot and equipped.id <> v_item.id
      ) then raise exception 'That loadout slot is already occupied.'; end if;
      perform public.move_inventory_item_instance(v_profile, v_item.character_id, v_item.id,
        v_item.character_id, null, null, 0, v_loadout_slot);
    end if;
    select * into v_item from public.inventory_items where id = v_item.id;
    return public.inventory_item_record_to_json(v_item);
  end if;

  if v_patch ? 'slotIndex' or v_patch ? 'parentItemId' then
    if v_item.is_storage and v_item.storage_active then
      raise exception 'Pack up active additional storage before placing it in an inventory slot.';
    end if;
    v_parent_item_id := case when v_patch ? 'parentItemId' then nullif(v_patch->>'parentItemId', '')::uuid else v_item.parent_item_id end;
    v_slot_index := case when v_patch ? 'slotIndex' then (v_patch->>'slotIndex')::integer else v_item.slot_index end;
    if v_item.loadout_slot is not null then
      select * into v_target from public.inventory_items target
      where target.character_id = v_item.character_id
        and target.parent_item_id is not distinct from v_parent_item_id
        and target.loadout_slot is null and target.slot_index = v_slot_index and target.id <> v_item.id
        and not (v_parent_item_id is null and target.is_storage and target.storage_active)
      for update;
      if v_target.id is not null and not public.inventory_items_stackable(v_target, v_item) then
        v_free_slot := public.find_first_free_inventory_slot(
          v_item.character_id, v_parent_item_id,
          case when v_parent_item_id is null then v_character.inventory_slots
            else (select storage_capacity from public.inventory_items where id = v_parent_item_id) end
        );
        if v_free_slot is null then raise exception 'No open slot for the item already there.'; end if;
        perform public.move_inventory_item_instance(v_profile, v_item.character_id, v_target.id,
          v_target.character_id, null, v_parent_item_id, v_free_slot, null);
      end if;
    end if;
    perform public.move_inventory_item_instance(v_profile, v_item.character_id, v_item.id,
      v_item.character_id, null, v_parent_item_id, v_slot_index, null);
    select * into v_item from public.inventory_items where id = v_item.id;
    if v_item.id is null then
      select * into v_item from public.inventory_items target
      where target.character_id = v_character.id and target.parent_item_id is not distinct from v_parent_item_id
        and target.slot_index = v_slot_index and target.loadout_slot is null;
    end if;
  end if;

  return public.inventory_item_record_to_json(v_item);
end;
$$;

create or replace function public.inventory_item_record_to_json(p_item public.inventory_items)
returns jsonb
language sql
stable
set search_path = public
as $$
  select jsonb_build_object(
    'id', p_item.id,
    'characterId', p_item.character_id,
    'propertyId', p_item.property_id,
    'parentItemId', p_item.parent_item_id,
    'name', p_item.item_name,
    'displayName', p_item.display_name,
    'itemDescription', p_item.item_description,
    'type', p_item.item_type,
    'rarity', p_item.rarity,
    'quantity', p_item.quantity,
    'slotIndex', p_item.slot_index,
    'loadoutSlot', p_item.loadout_slot,
    'stackable', public.item_catalog_stackable(p_item.item_name, p_item.item_type),
    'isAccessory', p_item.is_accessory,
    'isStorage', p_item.is_storage,
    'storageActive', p_item.storage_active,
    'storageCapacity', p_item.storage_capacity,
    'modifiers', p_item.modifiers,
    'enchantment', p_item.enchantment,
    'runeName', p_item.rune_name,
    'material', p_item.material,
    'enhancementCount', p_item.enhancement_count,
    'isTwoHanded', p_item.is_two_handed,
    'potionStrength', p_item.potion_strength,
    'potionProperty', p_item.potion_property,
    'potionQuality', p_item.potion_quality,
    'spellBookForm', p_item.spell_book_form,
    'canBeEnhanced', public.item_catalog_can_be_enhanced(p_item.item_name, p_item.item_type, p_item.material),
    'canBeEnchanted', public.item_catalog_can_be_enchanted(p_item.item_name, p_item.item_type, p_item.material)
  )
$$;

-- Retire the parallel storage model only after every item has been preserved.
do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'house_unit_access_permissions',
    'house_access_permissions',
    'mobile_storage_access_permissions',
    'player_main_homes',
    'player_home_display_orders',
    'house_inventory_items',
    'campaign_properties',
    'player_houses'
  ]
  loop
    if to_regclass(format('public.%I', v_table)) is not null then
      execute format('drop table public.%I cascade', v_table);
    end if;
  end loop;
end;
$$;

-- CANONICAL STORAGE RUNTIME START
-- No runtime definition below this boundary may reference a retired storage model.

create or replace function public.update_inventory_item_state(
  p_session_token text,
  p_item_id uuid,
  p_patch jsonb
)
returns jsonb
language sql
security definer
set search_path = public, extensions
as $$
  select public.update_inventory_item_state_impl(p_session_token, p_item_id, p_patch)
$$;

-- Remove every superseded RPC signature before installing the actor-aware API.
drop function if exists public.get_player_homes(text, uuid, uuid, text);
drop function if exists public.reorder_player_homes(text, uuid, jsonb);
drop function if exists public.save_player_home(text, uuid, uuid, text, jsonb);
drop function if exists public.delete_player_home(text, uuid, uuid, text);
drop function if exists public.add_home_inventory_item(text, uuid, uuid, uuid, integer, text, text, text, numeric, boolean, integer, jsonb, text, text, integer, boolean, text, text, text, text, boolean);
drop function if exists public.move_inventory_item_to_home(text, uuid, uuid, text, integer, uuid);
drop function if exists public.move_home_item_to_inventory(text, uuid, uuid);
drop function if exists public.move_item_between_homes(text, uuid, uuid, text, uuid, text, integer, uuid);
drop function if exists public.update_house_inventory_item_state(text, uuid, jsonb);
drop function if exists public.drop_house_inventory_item_quantity(text, uuid, numeric);
drop function if exists public.update_mobile_home_item_state(text, uuid, jsonb);
drop function if exists public.drop_mobile_home_item_quantity(text, uuid, numeric);

create or replace function public.mobile_property_accessible(
  p_profile public.profiles,
  p_storage public.inventory_items,
  p_actor_character_id uuid
)
returns boolean
language plpgsql
stable
set search_path = public
as $$
declare
  v_actor public.characters%rowtype;
  v_carrier public.characters%rowtype;
  v_property public.storage_properties%rowtype;
begin
  if p_profile.role = 'dm'::public.user_role then return true; end if;
  if p_storage.property_id is not null then
    select * into v_property from public.storage_properties where id = p_storage.property_id;
    return public.storage_property_accessible(p_profile, v_property, p_actor_character_id);
  end if;
  select * into v_carrier from public.characters where id = p_storage.character_id;
  select * into v_actor from public.characters where id = p_actor_character_id;
  return v_carrier.owner_user_id = p_profile.id
    and v_actor.owner_user_id = p_profile.id
    and coalesce(v_carrier.location_city_key, nullif(public.safe_slug(v_carrier.location_name), ''), 'wild')
      = coalesce(v_actor.location_city_key, nullif(public.safe_slug(v_actor.location_name), ''), 'wild');
end;
$$;

create or replace function public.inventory_portable_property_root(p_item_id uuid)
returns uuid
language sql
stable
set search_path = public
as $$
  with recursive ancestry as (
    select item.id, item.parent_item_id, item.item_name, item.item_type
    from public.inventory_items item where item.id = p_item_id
    union all
    select parent.id, parent.parent_item_id, parent.item_name, parent.item_type
    from public.inventory_items parent
    join ancestry child on child.parent_item_id = parent.id
  )
  select ancestry.id
  from ancestry
  where public.portable_property_kind(ancestry.item_name, ancestry.item_type) is not null
  limit 1
$$;

create or replace function public.get_character_inventory(
  p_session_token text,
  p_character_id uuid
)
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
  if not exists (select 1 from public.characters where id = p_character_id) then
    raise exception 'Character not found.';
  end if;
  perform public.ensure_dm_testing_wallet(p_character_id);
  perform public.ensure_character_additional_storage_activation(p_character_id);

  return jsonb_build_object(
    'items', (
      select coalesce(jsonb_agg(public.inventory_item_record_to_json(item)
        order by coalesce(item.loadout_slot, ''), coalesce(item.parent_item_id, '00000000-0000-0000-0000-000000000000'::uuid),
          item.slot_index, item.item_name), '[]'::jsonb)
      from public.inventory_items item
      where item.character_id = p_character_id
        and (
          item.parent_item_id is null
          or public.inventory_portable_property_root(item.id) is null
        )
    ),
    'wallet', public.wallet_balances_for_character(p_character_id)
  );
end;
$$;

create or replace function public.storage_property_record_to_json(
  p_property public.storage_properties,
  p_profile public.profiles,
  p_actor_character_id uuid
)
returns jsonb
language sql
stable
set search_path = public
as $$
  select jsonb_build_object(
    'id', p_property.id,
    'ownerUserId', p_property.owner_user_id,
    'source', 'static',
    'name', p_property.property_name,
    'stableName', p_property.property_name,
    'cityName', coalesce((select city.name from public.cities city where city.city_key = p_property.city_key), case when p_property.city_key = 'wild' then 'Wild' else p_property.city_key end),
    'cityKey', p_property.city_key,
    'inventorySlots', case when p_property.property_kind = 'house' then p_property.capacity else 0 end,
    'stableSlots', case when p_property.property_kind = 'stable' then p_property.capacity else 0 end,
    'locked', p_property.is_locked,
    'isMain', p_property.is_main,
    'displayOrder', p_property.display_order,
    'accessible', public.storage_property_accessible(p_profile, p_property, p_actor_character_id),
    'accessReason', case
      when p_profile.role = 'dm'::public.user_role then ''
      when p_property.is_locked then 'Locked by the Dungeon Master.'
      when public.storage_property_accessible(p_profile, p_property, p_actor_character_id) then ''
      else 'A controlled character must be in ' || coalesce((select city.name from public.cities city where city.city_key = p_property.city_key), 'Wild') || ' to use this property.'
    end,
    'kind', p_property.property_kind,
    'storageItemId', null,
    'storageCharacterId', null,
    'stableStorageItemId', null,
    'stableStorageCharacterId', null
  )
$$;

create or replace function public.mobile_property_record_to_json(
  p_storage public.inventory_items,
  p_owner_user_id uuid,
  p_profile public.profiles,
  p_actor_character_id uuid
)
returns jsonb
language sql
stable
set search_path = public
as $$
  select jsonb_build_object(
    'id', p_storage.id,
    'ownerUserId', p_owner_user_id,
    'source', 'mobile',
    'name', coalesce(nullif(p_storage.display_name, ''), p_storage.item_name),
    'stableName', coalesce(nullif(p_storage.display_name, ''), p_storage.item_name),
    'cityName', case
      when p_storage.character_id is not null then (select character.location_name from public.characters character where character.id = p_storage.character_id)
      else coalesce((select city.name from public.storage_properties storage left join public.cities city on city.city_key = storage.city_key where storage.id = p_storage.property_id), 'Wild')
    end,
    'inventorySlots', case when public.portable_property_kind(p_storage.item_name, p_storage.item_type) = 'house' then p_storage.storage_capacity else 0 end,
    'stableSlots', case when public.portable_property_kind(p_storage.item_name, p_storage.item_type) = 'stable' then p_storage.storage_capacity else 0 end,
    'locked', false,
    'isMain', p_storage.storage_is_main,
    'displayOrder', p_storage.storage_display_order,
    'accessible', public.mobile_property_accessible(p_profile, p_storage, p_actor_character_id),
    'accessReason', case when public.mobile_property_accessible(p_profile, p_storage, p_actor_character_id) then '' else 'The acting character is not with this mobile property.' end,
    'kind', case when public.portable_property_kind(p_storage.item_name, p_storage.item_type) = 'stable' then 'caged-wagon' else 'wagon-home' end,
    'storageItemId', case when public.portable_property_kind(p_storage.item_name, p_storage.item_type) = 'house' then p_storage.id else null end,
    'storageCharacterId', p_storage.character_id,
    'stableStorageItemId', case when public.portable_property_kind(p_storage.item_name, p_storage.item_type) = 'stable' then p_storage.id else null end,
    'stableStorageCharacterId', p_storage.character_id
  )
$$;

drop function if exists public.get_player_homes(text, uuid, uuid, text);
drop function if exists public.get_player_homes(text, uuid, uuid, text, uuid);
create function public.get_player_homes(
  p_session_token text,
  p_owner_user_id uuid,
  p_selected_home_id uuid default null,
  p_selected_source text default null,
  p_actor_character_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_selected_property public.storage_properties%rowtype;
  v_selected_mobile public.inventory_items%rowtype;
  v_selected_source text;
  v_selected_id uuid;
  v_accessible boolean := false;
  v_kind text;
  v_homes jsonb := '[]'::jsonb;
  v_items jsonb := '[]'::jsonb;
  v_house jsonb := null;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;
  if v_profile.role <> 'dm'::public.user_role and p_owner_user_id is distinct from v_profile.id then
    raise exception 'Only the owner or Dungeon Master can view these properties.';
  end if;

  with homes as (
    select storage.display_order, storage.created_at, storage.id,
      public.storage_property_record_to_json(storage, v_profile, p_actor_character_id) as payload
    from public.storage_properties storage where storage.owner_user_id = p_owner_user_id
    union all
    select item.storage_display_order, item.created_at, item.id,
      public.mobile_property_record_to_json(item, p_owner_user_id, v_profile, p_actor_character_id)
    from public.inventory_items item
    left join public.characters carrier on carrier.id = item.character_id
    left join public.storage_properties fixed on fixed.id = item.property_id
    where item.parent_item_id is null and item.loadout_slot is null and item.is_storage
      and public.portable_property_kind(item.item_name, item.item_type) is not null
      and coalesce(carrier.owner_user_id, fixed.owner_user_id) = p_owner_user_id
  )
  select coalesce(jsonb_agg(payload order by display_order, created_at, id), '[]'::jsonb) into v_homes from homes;

  if p_selected_home_id is not null and p_selected_source = 'mobile' then
    select item.* into v_selected_mobile
    from public.inventory_items item
    left join public.characters carrier on carrier.id = item.character_id
    left join public.storage_properties fixed on fixed.id = item.property_id
    where item.id = p_selected_home_id and item.parent_item_id is null and item.loadout_slot is null
      and public.portable_property_kind(item.item_name, item.item_type) is not null
      and coalesce(carrier.owner_user_id, fixed.owner_user_id) = p_owner_user_id;
    if v_selected_mobile.id is not null then v_selected_source := 'mobile'; v_selected_id := v_selected_mobile.id; end if;
  elsif p_selected_home_id is not null then
    select * into v_selected_property from public.storage_properties
    where id = p_selected_home_id and owner_user_id = p_owner_user_id;
    if v_selected_property.id is not null then v_selected_source := 'static'; v_selected_id := v_selected_property.id; end if;
  end if;

  if v_selected_id is null then
    select candidate.source, candidate.id into v_selected_source, v_selected_id
    from (
      select 'static'::text as source, storage.id,
        public.storage_property_accessible(v_profile, storage, p_actor_character_id) as accessible,
        storage.property_kind = 'house' and storage.is_main as is_main,
        storage.display_order, storage.created_at, 0 as source_order
      from public.storage_properties storage
      where storage.owner_user_id = p_owner_user_id
      union all
      select 'mobile'::text, item.id,
        public.mobile_property_accessible(v_profile, item, p_actor_character_id),
        public.portable_property_kind(item.item_name, item.item_type) = 'house' and item.storage_is_main,
        item.storage_display_order, item.created_at, 1
      from public.inventory_items item
      left join public.characters carrier on carrier.id = item.character_id
      left join public.storage_properties fixed on fixed.id = item.property_id
      where item.parent_item_id is null and item.loadout_slot is null
        and public.portable_property_kind(item.item_name, item.item_type) is not null
        and coalesce(carrier.owner_user_id, fixed.owner_user_id) = p_owner_user_id
    ) candidate
    order by candidate.accessible desc, candidate.is_main desc,
      candidate.display_order, candidate.source_order, candidate.created_at, candidate.id
    limit 1;
    if v_selected_source = 'static' then
      select * into v_selected_property from public.storage_properties where id = v_selected_id;
    elsif v_selected_source = 'mobile' then
      select * into v_selected_mobile from public.inventory_items where id = v_selected_id;
    end if;
  end if;

  if v_selected_source = 'static' then
    v_accessible := public.storage_property_accessible(v_profile, v_selected_property, p_actor_character_id);
    v_kind := v_selected_property.property_kind;
    v_house := public.storage_property_record_to_json(v_selected_property, v_profile, p_actor_character_id);
    if v_accessible then
      select coalesce(jsonb_agg(public.inventory_item_record_to_json(item) order by item.parent_item_id nulls first, item.slot_index, item.created_at), '[]'::jsonb)
      into v_items
      from public.inventory_items item
      where item.property_id = v_selected_property.id
        and (
          item.parent_item_id is null
          or public.inventory_portable_property_root(item.id) is null
        );
    end if;
  elsif v_selected_source = 'mobile' then
    v_accessible := public.mobile_property_accessible(v_profile, v_selected_mobile, p_actor_character_id);
    v_kind := public.portable_property_kind(v_selected_mobile.item_name, v_selected_mobile.item_type);
    v_house := public.mobile_property_record_to_json(v_selected_mobile, p_owner_user_id, v_profile, p_actor_character_id);
    if v_accessible then
      with recursive content_ids as (
        select item.id from public.inventory_items item where item.parent_item_id = v_selected_mobile.id
        union all select child.id from public.inventory_items child join content_ids parent on child.parent_item_id = parent.id
      )
      select coalesce(jsonb_agg(public.inventory_item_record_to_json(item) order by item.parent_item_id nulls first, item.slot_index, item.created_at), '[]'::jsonb)
      into v_items from public.inventory_items item join content_ids content on content.id = item.id;
    end if;
  end if;

  return jsonb_build_object(
    'house', v_house,
    'homes', v_homes,
    'items', v_items,
    'access', jsonb_build_object(
      'owner', v_profile.id = p_owner_user_id,
      'dm', v_profile.role = 'dm'::public.user_role,
      'house', v_accessible and v_kind = 'house',
      'stable', v_accessible and v_kind = 'stable'
    )
  );
end;
$$;

drop function if exists public.reorder_player_homes(text, uuid, jsonb);
drop function if exists public.reorder_player_homes(text, uuid, uuid, jsonb);
create function public.reorder_player_homes(
  p_session_token text,
  p_owner_user_id uuid,
  p_actor_character_id uuid,
  p_homes jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_entry jsonb;
  v_order integer := 0;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;
  if v_profile.role <> 'dm'::public.user_role and v_profile.id is distinct from p_owner_user_id then raise exception 'Only the owner or Dungeon Master can reorder properties.'; end if;
  for v_entry in select value from jsonb_array_elements(coalesce(p_homes, '[]'::jsonb)) loop
    if v_entry->>'source' = 'mobile' then
      update public.inventory_items item set storage_display_order = v_order
      where item.id = (v_entry->>'id')::uuid
        and public.inventory_item_owner_user_id(item) = p_owner_user_id;
    else
      update public.storage_properties set display_order = v_order
      where id = (v_entry->>'id')::uuid and owner_user_id = p_owner_user_id;
    end if;
    v_order := v_order + 10;
  end loop;
  return public.get_player_homes(p_session_token, p_owner_user_id, null, null, p_actor_character_id);
end;
$$;

drop function if exists public.save_player_home(text, uuid, uuid, text, jsonb);
drop function if exists public.save_player_home(text, uuid, uuid, text, uuid, jsonb);
create function public.save_player_home(
  p_session_token text,
  p_owner_user_id uuid,
  p_home_id uuid,
  p_home_source text,
  p_actor_character_id uuid,
  p_patch jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_property public.storage_properties%rowtype;
  v_mobile public.inventory_items%rowtype;
  v_kind text;
  v_name text;
  v_capacity integer;
  v_city_key text;
  v_is_main boolean;
  v_max_slot integer;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;
  if v_profile.role <> 'dm'::public.user_role and v_profile.id is distinct from p_owner_user_id then raise exception 'Only the owner or Dungeon Master can edit this property.'; end if;

  if p_home_source = 'mobile' then
    select item.* into v_mobile from public.inventory_items item
    where item.id = p_home_id and public.inventory_item_owner_user_id(item) = p_owner_user_id
      and public.portable_property_kind(item.item_name, item.item_type) is not null for update;
    if v_mobile.id is null then raise exception 'Mobile property not found.'; end if;
    if not public.mobile_property_accessible(v_profile, v_mobile, p_actor_character_id) then raise exception 'The acting character is not with this mobile property.'; end if;
    v_kind := public.portable_property_kind(v_mobile.item_name, v_mobile.item_type);
    v_name := coalesce(nullif(left(trim(p_patch->>'name'), 100), ''), v_mobile.display_name, v_mobile.item_name);
    v_capacity := case when v_kind = 'stable' then coalesce((p_patch->>'stableSlots')::integer, v_mobile.storage_capacity) else coalesce((p_patch->>'inventorySlots')::integer, v_mobile.storage_capacity) end;
    select max(slot_index) into v_max_slot from public.inventory_items where parent_item_id = v_mobile.id;
    if v_capacity <= coalesce(v_max_slot, -1) then raise exception 'Empty every slot beyond the new capacity before reducing it.'; end if;
    v_is_main := coalesce((p_patch->>'isMain')::boolean, v_mobile.storage_is_main) and v_kind = 'house';
    if v_is_main then
      update public.storage_properties set is_main = false where owner_user_id = p_owner_user_id and property_kind = 'house';
      update public.inventory_items item set storage_is_main = false
      where item.storage_is_main and public.inventory_item_owner_user_id(item) = p_owner_user_id;
    end if;
    update public.inventory_items set display_name = v_name, storage_capacity = greatest(0, least(500, v_capacity)), storage_is_main = v_is_main, updated_at = now() where id = v_mobile.id;
    return public.get_player_homes(p_session_token, p_owner_user_id, v_mobile.id, 'mobile', p_actor_character_id);
  end if;

  if p_home_id is null then
    if v_profile.role <> 'dm'::public.user_role then raise exception 'Only the Dungeon Master can create fixed properties.'; end if;
    v_kind := case when p_patch->>'kind' = 'stable' then 'stable' else 'house' end;
    v_name := coalesce(nullif(left(trim(p_patch->>'name'), 100), ''), case when v_kind = 'stable' then 'Stable' else 'House' end);
    v_capacity := case when v_kind = 'stable' then coalesce((p_patch->>'stableSlots')::integer, 5) else coalesce((p_patch->>'inventorySlots')::integer, 45) end;
    select city.city_key into v_city_key from public.cities city where lower(trim(city.name)) = lower(trim(p_patch->>'cityName')) limit 1;
    v_city_key := coalesce(v_city_key, case when lower(trim(p_patch->>'cityName')) = 'wild' then 'wild' else null end);
    if v_city_key is null then raise exception 'Choose a valid city or Wild location.'; end if;
    v_is_main := coalesce((p_patch->>'isMain')::boolean, false) and v_kind = 'house';
    if v_is_main then
      update public.storage_properties set is_main = false where owner_user_id = p_owner_user_id and property_kind = 'house';
      update public.inventory_items item set storage_is_main = false where item.storage_is_main and public.inventory_item_owner_user_id(item) = p_owner_user_id;
    end if;
    insert into public.storage_properties(owner_user_id, property_kind, city_key, property_name, capacity, display_order, is_main, is_locked)
    values (p_owner_user_id, v_kind, v_city_key, v_name, greatest(0, least(500, v_capacity)),
      coalesce((
        select max(ordered.display_order) + 10
        from (
          select storage.display_order from public.storage_properties storage where storage.owner_user_id = p_owner_user_id
          union all
          select item.storage_display_order from public.inventory_items item
          where item.parent_item_id is null and item.loadout_slot is null
            and public.portable_property_kind(item.item_name, item.item_type) is not null
            and public.inventory_item_owner_user_id(item) = p_owner_user_id
        ) ordered
      ), 0),
      v_is_main, coalesce((p_patch->>'locked')::boolean, false)) returning * into v_property;
    return public.get_player_homes(p_session_token, p_owner_user_id, v_property.id, 'static', p_actor_character_id);
  end if;

  select * into v_property from public.storage_properties where id = p_home_id and owner_user_id = p_owner_user_id for update;
  if v_property.id is null then raise exception 'Property not found.'; end if;
  if v_profile.role <> 'dm'::public.user_role and not public.storage_property_accessible(v_profile, v_property, p_actor_character_id) then raise exception 'A controlled character must be in the property''s city to edit it.'; end if;
  v_name := coalesce(nullif(left(trim(p_patch->>'name'), 100), ''), v_property.property_name);
  v_capacity := case when v_property.property_kind = 'stable' then coalesce((p_patch->>'stableSlots')::integer, v_property.capacity) else coalesce((p_patch->>'inventorySlots')::integer, v_property.capacity) end;
  select max(slot_index) into v_max_slot from public.inventory_items where property_id = v_property.id and parent_item_id is null and loadout_slot is null;
  if v_capacity <= coalesce(v_max_slot, -1) then raise exception 'Empty every slot beyond the new capacity before reducing it.'; end if;
  v_city_key := v_property.city_key;
  if v_profile.role = 'dm'::public.user_role and p_patch ? 'cityName' then
    select city.city_key into v_city_key from public.cities city where lower(trim(city.name)) = lower(trim(p_patch->>'cityName')) limit 1;
    v_city_key := coalesce(v_city_key, case when lower(trim(p_patch->>'cityName')) = 'wild' then 'wild' else null end);
    if v_city_key is null then raise exception 'Choose a valid city or Wild location.'; end if;
  end if;
  v_is_main := coalesce((p_patch->>'isMain')::boolean, v_property.is_main) and v_property.property_kind = 'house';
  if v_is_main then
    update public.storage_properties set is_main = false where owner_user_id = p_owner_user_id and property_kind = 'house';
    update public.inventory_items item set storage_is_main = false where item.storage_is_main and public.inventory_item_owner_user_id(item) = p_owner_user_id;
  end if;
  update public.storage_properties set property_name = v_name, capacity = greatest(0, least(500, v_capacity)), city_key = v_city_key,
    is_main = v_is_main, is_locked = case when v_profile.role = 'dm'::public.user_role and p_patch ? 'locked' then (p_patch->>'locked')::boolean else is_locked end,
    updated_at = now() where id = v_property.id returning * into v_property;
  return public.get_player_homes(p_session_token, p_owner_user_id, v_property.id, 'static', p_actor_character_id);
end;
$$;

drop function if exists public.delete_player_home(text, uuid, uuid, text);
drop function if exists public.delete_player_home(text, uuid, uuid, text, uuid);
create function public.delete_player_home(p_session_token text, p_owner_user_id uuid, p_home_id uuid, p_home_source text, p_actor_character_id uuid)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_profile public.profiles%rowtype; v_property public.storage_properties%rowtype;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.role <> 'dm'::public.user_role then raise exception 'Only the Dungeon Master can delete fixed properties.'; end if;
  if p_home_source <> 'static' then raise exception 'Portable properties are items and must be moved or dropped as items.'; end if;
  select * into v_property from public.storage_properties where id = p_home_id and owner_user_id = p_owner_user_id for update;
  if v_property.id is null then raise exception 'Property not found.'; end if;
  if exists (select 1 from public.inventory_items where property_id = v_property.id) then raise exception 'A fixed property must be empty before it can be deleted.'; end if;
  delete from public.storage_properties where id = v_property.id;
  return public.get_player_homes(p_session_token, p_owner_user_id, null, null, p_actor_character_id);
end;
$$;

create or replace function public.first_free_property_slot(p_property_id uuid)
returns integer language sql stable set search_path = public as $$
  select candidate.slot from public.storage_properties storage
  cross join lateral generate_series(0, greatest(0, storage.capacity - 1)) candidate(slot)
  where storage.id = p_property_id and not exists (
    select 1 from public.inventory_items item where item.property_id = storage.id and item.parent_item_id is null and item.loadout_slot is null and item.slot_index = candidate.slot
  ) order by candidate.slot limit 1
$$;

create or replace function public.first_free_container_slot(p_parent_item_id uuid)
returns integer language sql stable set search_path = public as $$
  select candidate.slot from public.inventory_items parent
  cross join lateral generate_series(0, greatest(0, parent.storage_capacity - 1)) candidate(slot)
  where parent.id = p_parent_item_id and not exists (
    select 1 from public.inventory_items item where item.parent_item_id = parent.id and item.loadout_slot is null and item.slot_index = candidate.slot
  ) order by candidate.slot limit 1
$$;

create or replace function public.first_free_character_slot(p_character_id uuid)
returns integer language sql stable set search_path = public as $$
  select candidate.slot from public.characters character
  cross join lateral generate_series(0, greatest(0, character.inventory_slots - 1)) candidate(slot)
  where character.id = p_character_id and not exists (
    select 1 from public.inventory_items item where item.character_id = character.id and item.parent_item_id is null and item.loadout_slot is null and item.slot_index = candidate.slot
      and not (item.is_storage and item.storage_active)
  ) order by candidate.slot limit 1
$$;

create or replace function public.find_first_free_inventory_slot(
  p_character_id uuid,
  p_parent_item_id uuid,
  p_capacity integer
)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select candidate.slot
  from generate_series(0, greatest(0, p_capacity - 1)) candidate(slot)
  where p_capacity > 0
    and not exists (
      select 1
      from public.inventory_items item
      where item.character_id = p_character_id
        and item.parent_item_id is not distinct from p_parent_item_id
        and item.loadout_slot is null
        and item.slot_index = candidate.slot
        and (p_parent_item_id is not null or not (item.is_storage and item.storage_active))
    )
  order by candidate.slot
  limit 1
$$;

create or replace function public.next_storage_container_slot(p_character_id uuid)
returns integer
language sql
stable
as $$
  select 0
$$;

drop function if exists public.add_home_inventory_item(text, uuid, uuid, uuid, integer, text, text, text, numeric, boolean, integer, jsonb, text, text, integer, boolean, text, text, text, text, boolean);
drop function if exists public.add_home_inventory_item(text, uuid, uuid, uuid, uuid, integer, text, text, text, numeric, boolean, integer, jsonb, text, text, integer, boolean, text, text, text, text, boolean);
create function public.add_home_inventory_item(
  p_session_token text, p_owner_user_id uuid, p_home_id uuid, p_actor_character_id uuid,
  p_parent_item_id uuid, p_slot_index integer, p_item_name text, p_item_type text,
  p_rarity text, p_quantity numeric, p_is_storage boolean, p_storage_capacity integer,
  p_modifiers jsonb, p_enchantment text, p_material text, p_enhancement_count integer,
  p_is_two_handed boolean, p_potion_strength text, p_potion_property text,
  p_potion_quality text, p_item_description text, p_is_accessory boolean
)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_profile public.profiles%rowtype; v_property public.storage_properties%rowtype; v_item public.inventory_items%rowtype;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.role <> 'dm'::public.user_role then raise exception 'Only the Dungeon Master can create property items.'; end if;
  v_property := public.assert_storage_property_access(v_profile, p_home_id, p_actor_character_id);
  if v_property.owner_user_id is distinct from p_owner_user_id then raise exception 'That property does not belong to the selected player.'; end if;
  insert into public.inventory_items(character_id, property_id, parent_item_id, item_name, item_description, item_type, rarity, quantity, slot_index,
    is_accessory, is_storage, storage_active, storage_capacity, modifiers, enchantment, material, enhancement_count, is_two_handed,
    potion_strength, potion_property, potion_quality)
  values(null, v_property.id, p_parent_item_id, public.normalize_item_name(p_item_name), coalesce(p_item_description, ''), public.normalize_item_type(p_item_type),
    p_rarity::public.item_rarity, public.assert_valid_item_quantity(p_item_name, p_item_type, p_quantity), p_slot_index,
    coalesce(p_is_accessory, false), coalesce(p_is_storage, false), false, greatest(0, coalesce(p_storage_capacity, 0)),
    coalesce(p_modifiers, '{}'::jsonb), p_enchantment, p_material, greatest(0, least(3, coalesce(p_enhancement_count, 0))),
    coalesce(p_is_two_handed, false), p_potion_strength, p_potion_property, p_potion_quality)
  returning * into v_item;
  return public.inventory_item_record_to_json(v_item);
end;
$$;

drop function if exists public.add_mobile_home_inventory_item(text, uuid, uuid, uuid, integer, text, text, text, numeric, boolean, integer, jsonb, text, text, integer, boolean, text, text, text, text, boolean);
create function public.add_mobile_home_inventory_item(
  p_session_token text, p_mobile_home_id uuid, p_actor_character_id uuid,
  p_parent_item_id uuid, p_slot_index integer, p_item_name text, p_item_type text,
  p_rarity text, p_quantity numeric, p_is_storage boolean, p_storage_capacity integer,
  p_modifiers jsonb, p_enchantment text, p_material text, p_enhancement_count integer,
  p_is_two_handed boolean, p_potion_strength text, p_potion_property text,
  p_potion_quality text, p_item_description text, p_is_accessory boolean
)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_profile public.profiles%rowtype;
  v_mobile public.inventory_items%rowtype;
  v_parent_item_id uuid;
  v_item public.inventory_items%rowtype;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;
  if v_profile.role <> 'dm'::public.user_role then raise exception 'Only the Dungeon Master can create property items.'; end if;
  select item.* into v_mobile
  from public.inventory_items item
  where item.id = p_mobile_home_id
    and item.parent_item_id is null
    and public.portable_property_kind(item.item_name, item.item_type) is not null;
  if v_mobile.id is null then raise exception 'Mobile property not found.'; end if;
  if not public.mobile_property_accessible(v_profile, v_mobile, p_actor_character_id) then raise exception 'Mobile property is not accessible.'; end if;
  v_parent_item_id := coalesce(p_parent_item_id, v_mobile.id);
  if public.inventory_portable_property_root(v_parent_item_id) is distinct from v_mobile.id then
    raise exception 'The selected slot does not belong to that mobile property.';
  end if;
  insert into public.inventory_items(
    character_id, property_id, parent_item_id, item_name, item_description, item_type,
    rarity, quantity, slot_index, is_accessory, is_storage, storage_active,
    storage_capacity, modifiers, enchantment, material, enhancement_count,
    is_two_handed, potion_strength, potion_property, potion_quality
  ) values (
    v_mobile.character_id, v_mobile.property_id, v_parent_item_id,
    public.normalize_item_name(p_item_name), coalesce(p_item_description, ''),
    public.normalize_item_type(p_item_type), p_rarity::public.item_rarity,
    public.assert_valid_item_quantity(p_item_name, p_item_type, p_quantity), p_slot_index,
    coalesce(p_is_accessory, false), coalesce(p_is_storage, false), false,
    greatest(0, coalesce(p_storage_capacity, 0)), coalesce(p_modifiers, '{}'::jsonb),
    p_enchantment, p_material, greatest(0, least(3, coalesce(p_enhancement_count, 0))),
    coalesce(p_is_two_handed, false), p_potion_strength, p_potion_property, p_potion_quality
  ) returning * into v_item;
  return public.inventory_item_record_to_json(v_item);
end;
$$;

create or replace function public.find_local_animal_destination(p_character_id uuid)
returns table(destination_property_id uuid, destination_parent_item_id uuid, destination_slot integer)
language sql
stable
set search_path = public
as $$
  with actor as (
    select character.*, coalesce(character.location_city_key,
      (select city.city_key from public.cities city where lower(trim(city.name)) = lower(trim(character.location_name)) limit 1),
      nullif(public.safe_slug(character.location_name), ''), 'wild') as city_key
    from public.characters character where character.id = p_character_id and character.owner_user_id is not null
  ), destinations as (
    select 0 as source_order, storage.display_order, storage.created_at, storage.id,
      storage.id as property_id, null::uuid as parent_id, public.first_free_property_slot(storage.id) as free_slot
    from actor join public.storage_properties storage on storage.owner_user_id = actor.owner_user_id
    where storage.property_kind = 'stable' and storage.city_key = actor.city_key and not storage.is_locked
    union all
    select 1, item.storage_display_order, item.created_at, item.id,
      item.property_id, item.id, public.first_free_container_slot(item.id)
    from actor
    join public.inventory_items item on item.parent_item_id is null and item.loadout_slot is null
      and public.portable_property_kind(item.item_name, item.item_type) = 'stable'
    left join public.characters carrier on carrier.id = item.character_id
    left join public.storage_properties fixed on fixed.id = item.property_id
    where coalesce(carrier.owner_user_id, fixed.owner_user_id) = actor.owner_user_id
      and (
        (carrier.id is not null and coalesce(carrier.location_city_key, nullif(public.safe_slug(carrier.location_name), ''), 'wild') = actor.city_key)
        or (fixed.id is not null and fixed.city_key = actor.city_key and fixed.property_kind = 'house' and not fixed.is_locked)
      )
  )
  select property_id, parent_id, free_slot from destinations
  where free_slot is not null
  order by display_order, source_order, created_at, id
  limit 1
$$;

create or replace function public.place_pet_item_in_stable_for_character(
  p_character_id uuid,
  p_item_name text,
  p_display_name text,
  p_item_description text,
  p_rarity public.item_rarity,
  p_quantity numeric default 1,
  p_is_accessory boolean default false,
  p_modifiers jsonb default '{}'::jsonb,
  p_enchantment text default null,
  p_rune_name text default null,
  p_material text default null,
  p_enhancement_count integer default 0,
  p_is_two_handed boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_destination record;
  v_item public.inventory_items%rowtype;
  v_location_character_id uuid;
  v_location_property_id uuid;
begin
  select * into v_destination from public.find_local_animal_destination(p_character_id);
  if v_destination.destination_slot is null then
    raise exception 'No local stable or Caged Wagon has room for this animal.';
  end if;
  v_location_property_id := v_destination.destination_property_id;
  if v_location_property_id is null then v_location_character_id := p_character_id; end if;
  if v_destination.destination_parent_item_id is not null then
    select character_id, property_id into v_location_character_id, v_location_property_id
    from public.inventory_items where id = v_destination.destination_parent_item_id;
  end if;
  insert into public.inventory_items(
    character_id, property_id, parent_item_id, item_name, display_name, item_description,
    item_type, rarity, quantity, slot_index, loadout_slot, is_accessory, is_storage,
    storage_active, storage_capacity, modifiers, enchantment, rune_name, material,
    enhancement_count, is_two_handed
  ) values (
    v_location_character_id, v_location_property_id, v_destination.destination_parent_item_id,
    public.normalize_item_name(p_item_name), nullif(left(trim(coalesce(p_display_name, '')), 80), ''), coalesce(p_item_description, ''),
    'pet', p_rarity, public.assert_valid_item_quantity(p_item_name, 'pet', p_quantity),
    v_destination.destination_slot, null, coalesce(p_is_accessory, false), false, false, 0,
    coalesce(p_modifiers, '{}'::jsonb), p_enchantment, p_rune_name, p_material,
    greatest(0, least(3, coalesce(p_enhancement_count, 0))), coalesce(p_is_two_handed, false)
  ) returning * into v_item;
  return public.inventory_item_record_to_json(v_item);
end;
$$;

create or replace function public.place_pet_item_for_character(
  p_character_id uuid,
  p_item_name text,
  p_display_name text,
  p_item_description text,
  p_rarity public.item_rarity,
  p_quantity numeric default 1,
  p_is_accessory boolean default false,
  p_modifiers jsonb default '{}'::jsonb,
  p_enchantment text default null,
  p_rune_name text default null,
  p_material text default null,
  p_enhancement_count integer default 0,
  p_is_two_handed boolean default false
)
returns jsonb language sql security definer set search_path = public, extensions as $$
  select public.place_pet_item_in_stable_for_character(p_character_id, p_item_name, p_display_name, p_item_description,
    p_rarity, p_quantity, p_is_accessory, p_modifiers, p_enchantment, p_rune_name, p_material, p_enhancement_count, p_is_two_handed)
$$;

drop function if exists public.move_inventory_item_to_home(text, uuid, uuid, text, integer, uuid);
drop function if exists public.move_inventory_item_to_home(text, uuid, uuid, uuid, text, integer, uuid);
create function public.move_inventory_item_to_home(
  p_session_token text, p_item_id uuid, p_actor_character_id uuid,
  p_home_id uuid default null, p_home_source text default null,
  p_slot_index integer default null, p_parent_item_id uuid default null
)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_profile public.profiles%rowtype;
  v_item public.inventory_items%rowtype;
  v_character public.characters%rowtype;
  v_property public.storage_properties%rowtype;
  v_mobile public.inventory_items%rowtype;
  v_parent public.inventory_items%rowtype;
  v_animal_destination record;
  v_home_candidate record;
  v_destination_character_id uuid;
  v_destination_property_id uuid;
  v_destination_parent_id uuid;
  v_slot integer;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;
  select * into v_item from public.inventory_items where id = p_item_id;
  if v_item.id is null then raise exception 'Item not found.'; end if;
  select * into v_character from public.characters where id = p_actor_character_id;
  if v_character.id is null then raise exception 'Choose the acting character.'; end if;
  perform public.assert_inventory_item_control(v_profile, v_item, p_actor_character_id);
  if p_home_id is not null and coalesce(p_home_source, '') not in ('static', 'mobile') then
    raise exception 'Choose a valid fixed or mobile property destination.';
  end if;

  if public.normalize_item_type(v_item.item_type) = 'pet' then
    if p_home_id is not null and p_home_source = 'mobile' then
      select * into v_mobile from public.inventory_items item
      where item.id = p_home_id and public.portable_property_kind(item.item_name, item.item_type) = 'stable';
      if v_mobile.id is null or not public.mobile_property_accessible(v_profile, v_mobile, p_actor_character_id) then
        raise exception 'Caged Wagon is not accessible.';
      end if;
      if public.inventory_item_owner_user_id(v_mobile) is distinct from public.inventory_item_owner_user_id(v_item) then
        raise exception 'The animal and Caged Wagon must have the same owner.';
      end if;
      v_destination_character_id := v_mobile.character_id;
      v_destination_property_id := v_mobile.property_id;
      v_destination_parent_id := coalesce(p_parent_item_id, v_mobile.id);
      if public.inventory_portable_property_root(v_destination_parent_id) is distinct from v_mobile.id then
        raise exception 'The selected stable slot does not belong to that Caged Wagon.';
      end if;
      v_slot := coalesce(p_slot_index, public.first_free_container_slot(v_destination_parent_id));
    elsif p_home_id is not null then
      v_property := public.assert_storage_property_access(v_profile, p_home_id, p_actor_character_id);
      if v_property.property_kind <> 'stable' then raise exception 'Animals require a stable or Caged Wagon.'; end if;
      if v_property.owner_user_id is distinct from public.inventory_item_owner_user_id(v_item) then
        raise exception 'The animal and stable must have the same owner.';
      end if;
      if p_parent_item_id is not null then
        select * into v_parent from public.inventory_items where id = p_parent_item_id;
        if v_parent.id is null or v_parent.property_id is distinct from v_property.id
          or public.inventory_portable_property_root(v_parent.id) is not null
        then raise exception 'The selected stable slot does not belong to that fixed stable.';
        end if;
      end if;
      v_destination_property_id := v_property.id;
      v_destination_parent_id := p_parent_item_id;
      v_slot := coalesce(p_slot_index, case when p_parent_item_id is null
        then public.first_free_property_slot(v_property.id)
        else public.first_free_container_slot(p_parent_item_id) end);
    else
      select * into v_animal_destination from public.find_local_animal_destination(v_character.id);
      if v_animal_destination.destination_slot is null then
        raise exception 'No local stable or Caged Wagon has room for this animal.';
      end if;
      v_destination_property_id := v_animal_destination.destination_property_id;
      v_destination_parent_id := v_animal_destination.destination_parent_item_id;
      v_slot := v_animal_destination.destination_slot;
      if v_destination_parent_id is not null then
        select parent.character_id, parent.property_id
        into v_destination_character_id, v_destination_property_id
        from public.inventory_items parent where parent.id = v_destination_parent_id;
      end if;
    end if;
    if v_slot is null then raise exception 'That stable is full.'; end if;
    perform public.move_inventory_item_instance(v_profile, p_actor_character_id, v_item.id,
      v_destination_character_id, v_destination_property_id, v_destination_parent_id, v_slot, null);
    return public.get_player_homes(p_session_token, v_character.owner_user_id,
      coalesce(p_home_id, v_destination_property_id, v_destination_parent_id),
      case when v_destination_parent_id is not null then 'mobile' else 'static' end,
      p_actor_character_id);
  end if;

  if p_home_id is not null and p_home_source = 'mobile' then
    select * into v_mobile from public.inventory_items item where item.id = p_home_id
      and public.portable_property_kind(item.item_name, item.item_type) = 'house';
    if v_mobile.id is null or not public.mobile_property_accessible(v_profile, v_mobile, p_actor_character_id) then raise exception 'Wagon Home is not accessible.'; end if;
    if public.inventory_item_owner_user_id(v_mobile) is distinct from public.inventory_item_owner_user_id(v_item) then
      raise exception 'The item and Wagon Home must have the same owner.';
    end if;
    v_destination_property_id := v_mobile.property_id;
    v_destination_parent_id := coalesce(p_parent_item_id, v_mobile.id);
    if public.inventory_portable_property_root(v_destination_parent_id) is distinct from v_mobile.id then
      raise exception 'The selected house slot does not belong to that Wagon Home.';
    end if;
    v_slot := coalesce(p_slot_index, public.first_free_container_slot(v_destination_parent_id));
  elsif p_home_id is not null then
    v_property := public.assert_storage_property_access(v_profile, p_home_id, p_actor_character_id);
    if v_property.property_kind <> 'house' then raise exception 'Non-animal items require a house or Wagon Home.'; end if;
    if v_property.owner_user_id is distinct from public.inventory_item_owner_user_id(v_item) then
      raise exception 'The item and house must have the same owner.';
    end if;
    if p_parent_item_id is not null then
      select * into v_parent from public.inventory_items where id = p_parent_item_id;
      if v_parent.id is null or v_parent.property_id is distinct from v_property.id
        or public.inventory_portable_property_root(v_parent.id) is not null
      then raise exception 'The selected house slot does not belong to that fixed house.';
      end if;
    end if;
    v_destination_property_id := v_property.id;
    v_destination_parent_id := p_parent_item_id;
    v_slot := coalesce(p_slot_index, case when p_parent_item_id is null then public.first_free_property_slot(v_property.id) else public.first_free_container_slot(p_parent_item_id) end);
  else
    select * into v_home_candidate
    from (
      select 'static'::text as source, storage.id, storage.is_main,
        storage.display_order, storage.created_at, 0 as source_order
      from public.storage_properties storage
      where storage.owner_user_id = v_character.owner_user_id
        and storage.property_kind = 'house'
        and storage.city_key = coalesce(v_character.location_city_key,
          (select city.city_key from public.cities city where lower(trim(city.name)) = lower(trim(v_character.location_name)) limit 1),
          nullif(public.safe_slug(v_character.location_name), ''), 'wild')
        and not storage.is_locked
        and public.first_free_property_slot(storage.id) is not null
      union all
      select 'mobile'::text, item.id, item.storage_is_main,
        item.storage_display_order, item.created_at, 1
      from public.inventory_items item
      left join public.characters carrier on carrier.id = item.character_id
      left join public.storage_properties fixed on fixed.id = item.property_id
      where item.parent_item_id is null
        and public.portable_property_kind(item.item_name, item.item_type) = 'house'
        and coalesce(carrier.owner_user_id, fixed.owner_user_id) = v_character.owner_user_id
        and public.mobile_property_accessible(v_profile, item, p_actor_character_id)
        and public.first_free_container_slot(item.id) is not null
    ) candidate
    order by candidate.is_main desc, candidate.display_order, candidate.source_order,
      candidate.created_at, candidate.id
    limit 1;
    if v_home_candidate.id is null then raise exception 'No accessible local house or Wagon Home has room.'; end if;
    if v_home_candidate.source = 'static' then
      select * into v_property from public.storage_properties where id = v_home_candidate.id;
      v_destination_property_id := v_property.id;
      v_slot := public.first_free_property_slot(v_property.id);
    else
      select * into v_mobile from public.inventory_items where id = v_home_candidate.id;
      v_destination_property_id := v_mobile.property_id;
      v_destination_parent_id := v_mobile.id;
      v_slot := public.first_free_container_slot(v_mobile.id);
    end if;
  end if;
  if v_slot is null then raise exception 'That destination is full.'; end if;
  perform public.move_inventory_item_instance(v_profile, p_actor_character_id, v_item.id,
    case when v_destination_property_id is null then v_mobile.character_id else null end,
    v_destination_property_id, v_destination_parent_id, v_slot, null);
  return public.get_player_homes(p_session_token, v_character.owner_user_id, coalesce(p_home_id, v_mobile.id, v_destination_property_id),
    case when v_destination_parent_id is not null and v_mobile.id is not null then 'mobile' else 'static' end, p_actor_character_id);
end;
$$;

drop function if exists public.move_home_item_to_inventory(text, uuid, uuid);
drop function if exists public.move_home_item_to_inventory(text, uuid, uuid, uuid);
create function public.move_home_item_to_inventory(p_session_token text, p_house_item_id uuid, p_character_id uuid, p_actor_character_id uuid default null)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_profile public.profiles%rowtype;
  v_item public.inventory_items%rowtype;
  v_actor public.characters%rowtype;
  v_target_character public.characters%rowtype;
  v_slot integer;
  v_loadout text;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  select * into v_item from public.inventory_items where id = p_house_item_id;
  if v_item.id is null then raise exception 'Property item not found.'; end if;
  p_actor_character_id := coalesce(p_actor_character_id, p_character_id);
  perform public.assert_inventory_item_control(v_profile, v_item, p_actor_character_id);
  select * into v_actor from public.characters where id = p_actor_character_id;
  v_target_character := public.assert_inventory_access(v_profile, p_character_id, false);
  if public.inventory_item_owner_user_id(v_item) is distinct from v_target_character.owner_user_id
    and v_profile.role <> 'dm'::public.user_role
  then
    raise exception 'Items can only move from a property to one of its owner''s characters.';
  end if;
  if v_profile.role <> 'dm'::public.user_role and not public.characters_share_location(v_actor, v_target_character) then
    raise exception 'The receiving character must be in the same location as the property.';
  end if;
  if v_item.is_storage then
    perform public.move_inventory_storage_tree_to_character(v_item.id, p_character_id);
    return public.get_character_inventory(p_session_token, p_character_id);
  end if;
  if public.normalize_item_type(v_item.item_type) = 'pet' then
    if exists (select 1 from public.inventory_items where character_id = p_character_id and loadout_slot = 'active-pet') then raise exception 'That character already has an active pet.'; end if;
    v_slot := 0; v_loadout := 'active-pet';
  else
    v_slot := public.first_free_character_slot(p_character_id);
    if v_slot is null then raise exception 'That character inventory is full.'; end if;
  end if;
  perform public.move_inventory_item_instance(v_profile, p_actor_character_id, v_item.id, p_character_id, null, null, v_slot, v_loadout);
  return public.get_character_inventory(p_session_token, p_character_id);
end;
$$;

drop function if exists public.move_item_between_homes(text, uuid, uuid, text, uuid, text, integer, uuid);
drop function if exists public.move_item_between_homes(text, uuid, uuid, uuid, text, uuid, text, integer, uuid);
create function public.move_item_between_homes(
  p_session_token text, p_actor_character_id uuid, p_item_id uuid,
  p_source_home_id uuid, p_source text, p_destination_home_id uuid,
  p_destination text, p_slot_index integer, p_parent_item_id uuid default null
)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_profile public.profiles%rowtype;
  v_item public.inventory_items%rowtype;
  v_destination_property public.storage_properties%rowtype;
  v_destination_mobile public.inventory_items%rowtype;
  v_destination_parent public.inventory_items%rowtype;
  v_owner_user_id uuid;
  v_destination_character_id uuid;
  v_destination_property_id uuid;
  v_destination_parent_id uuid;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;
  if p_source not in ('static', 'mobile') or p_destination not in ('static', 'mobile') then
    raise exception 'Choose valid fixed or mobile property locations.';
  end if;
  select * into v_item from public.inventory_items where id = p_item_id;
  if v_item.id is null then raise exception 'Item not found.'; end if;
  v_owner_user_id := public.inventory_item_owner_user_id(v_item);

  if p_source = 'static' and (
    v_item.property_id is distinct from p_source_home_id
    or (
      public.inventory_portable_property_root(v_item.id) is not null
      and public.inventory_portable_property_root(v_item.id) is distinct from v_item.id
    )
  ) then raise exception 'Item is not in the selected source property.'; end if;
  if p_source = 'mobile' and not exists (
    with recursive ancestry as (
      select item.id, item.parent_item_id from public.inventory_items item where item.id = v_item.id
      union all select parent.id, parent.parent_item_id from public.inventory_items parent join ancestry child on child.parent_item_id = parent.id
    ) select 1 from ancestry where id = p_source_home_id
  ) then raise exception 'Item is not in the selected source mobile property.'; end if;

  if p_destination = 'mobile' then
    select * into v_destination_mobile from public.inventory_items item
    where item.id = p_destination_home_id and public.portable_property_kind(item.item_name, item.item_type) is not null;
    if v_destination_mobile.id is null or public.inventory_item_owner_user_id(v_destination_mobile) is distinct from v_owner_user_id then raise exception 'Destination mobile property not found.'; end if;
    if not public.mobile_property_accessible(v_profile, v_destination_mobile, p_actor_character_id) then raise exception 'Destination mobile property is not accessible.'; end if;
    v_destination_character_id := v_destination_mobile.character_id;
    v_destination_property_id := v_destination_mobile.property_id;
    v_destination_parent_id := coalesce(p_parent_item_id, v_destination_mobile.id);
    if public.inventory_portable_property_root(v_destination_parent_id) is distinct from v_destination_mobile.id then
      raise exception 'The selected destination slot does not belong to that Wagon Home or Caged Wagon.';
    end if;
  else
    v_destination_property := public.assert_storage_property_access(v_profile, p_destination_home_id, p_actor_character_id);
    if v_destination_property.owner_user_id is distinct from v_owner_user_id then raise exception 'Properties must have the same owner for a direct transfer.'; end if;
    if p_parent_item_id is not null then
      select * into v_destination_parent from public.inventory_items where id = p_parent_item_id;
      if v_destination_parent.id is null
        or v_destination_parent.property_id is distinct from v_destination_property.id
        or public.inventory_portable_property_root(v_destination_parent.id) is not null
      then
        raise exception 'The selected destination slot does not belong to that fixed property.';
      end if;
    end if;
    v_destination_property_id := v_destination_property.id;
    v_destination_parent_id := p_parent_item_id;
  end if;
  perform public.move_inventory_item_instance(v_profile, p_actor_character_id, v_item.id,
    v_destination_character_id, v_destination_property_id, v_destination_parent_id, p_slot_index, null);
  return public.get_player_homes(p_session_token, v_owner_user_id, p_destination_home_id, p_destination, p_actor_character_id);
end;
$$;

drop function if exists public.update_house_inventory_item_state(text, uuid, jsonb);
drop function if exists public.update_house_inventory_item_state(text, uuid, uuid, jsonb);
create function public.update_house_inventory_item_state(p_session_token text, p_item_id uuid, p_actor_character_id uuid, p_patch jsonb)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_profile public.profiles%rowtype;
  v_item public.inventory_items%rowtype;
  v_slot integer;
  v_parent uuid;
  v_source_mobile_root uuid;
  v_destination_mobile_root uuid;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  select * into v_item from public.inventory_items where id = p_item_id;
  if v_item.id is null then raise exception 'Property item not found.'; end if;
  perform public.assert_inventory_item_control(v_profile, v_item, p_actor_character_id);
  v_slot := coalesce((p_patch->>'slotIndex')::integer, v_item.slot_index);
  v_parent := case when p_patch ? 'parentItemId' then nullif(p_patch->>'parentItemId', '')::uuid else v_item.parent_item_id end;
  if v_slot <> v_item.slot_index or v_parent is distinct from v_item.parent_item_id then
    v_source_mobile_root := public.inventory_portable_property_root(v_item.id);
    if v_source_mobile_root = v_item.id then v_source_mobile_root := null; end if;
    v_destination_mobile_root := case when v_parent is null then null else public.inventory_portable_property_root(v_parent) end;
    if v_source_mobile_root is distinct from v_destination_mobile_root then
      raise exception 'Use the property transfer control to move an item between properties.';
    end if;
    perform public.move_inventory_item_instance(v_profile, p_actor_character_id, v_item.id, v_item.character_id, v_item.property_id, v_parent, v_slot, null);
  end if;
  if v_profile.role = 'dm'::public.user_role then
    update public.inventory_items set
      item_name = case when p_patch ? 'name' then public.normalize_item_name(p_patch->>'name') else item_name end,
      item_description = case when p_patch ? 'itemDescription' then coalesce(p_patch->>'itemDescription', '') else item_description end,
      item_type = case when p_patch ? 'type' then public.normalize_item_type(p_patch->>'type') else item_type end,
      rarity = case when p_patch ? 'rarity' then (p_patch->>'rarity')::public.item_rarity else rarity end,
      quantity = case when p_patch ? 'quantity' then public.assert_valid_item_quantity(item_name, item_type, (p_patch->>'quantity')::numeric) else quantity end,
      display_name = case when p_patch ? 'displayName' then nullif(left(trim(p_patch->>'displayName'), 80), '') else display_name end,
      modifiers = case when p_patch ? 'modifiers' then p_patch->'modifiers' else modifiers end,
      updated_at = now()
    where id = p_item_id;
  elsif p_patch ? 'displayName' and public.normalize_item_type(v_item.item_type) = 'pet' then
    update public.inventory_items set display_name = nullif(left(trim(p_patch->>'displayName'), 80), ''), updated_at = now() where id = p_item_id;
  end if;
  select * into v_item from public.inventory_items where id = p_item_id;
  return public.inventory_item_record_to_json(v_item);
end;
$$;

drop function if exists public.drop_house_inventory_item_quantity(text, uuid, numeric);
drop function if exists public.drop_house_inventory_item_quantity(text, uuid, uuid, numeric);
create function public.drop_house_inventory_item_quantity(p_session_token text, p_item_id uuid, p_actor_character_id uuid, p_quantity numeric)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_profile public.profiles%rowtype; v_item public.inventory_items%rowtype; v_quantity numeric;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  select * into v_item from public.inventory_items where id = p_item_id for update;
  if v_item.id is null then raise exception 'Property item not found.'; end if;
  perform public.assert_inventory_item_control(v_profile, v_item, p_actor_character_id);
  v_quantity := public.assert_valid_item_quantity(v_item.item_name, v_item.item_type, p_quantity);
  if v_quantity >= v_item.quantity then
    if exists (select 1 from public.inventory_items where parent_item_id = v_item.id) then raise exception 'Move every contained item before dropping this storage item.'; end if;
    delete from public.inventory_items where id = v_item.id;
    return null;
  end if;
  update public.inventory_items set quantity = quantity - v_quantity, updated_at = now() where id = v_item.id returning * into v_item;
  return public.inventory_item_record_to_json(v_item);
end;
$$;

drop function if exists public.update_mobile_home_item_state(text, uuid, jsonb);
drop function if exists public.update_mobile_home_item_state(text, uuid, uuid, jsonb);
create function public.update_mobile_home_item_state(p_session_token text, p_item_id uuid, p_actor_character_id uuid, p_patch jsonb)
returns jsonb language sql security definer set search_path = public, extensions as $$
  select public.update_house_inventory_item_state(p_session_token, p_item_id, p_actor_character_id, p_patch)
$$;
drop function if exists public.drop_mobile_home_item_quantity(text, uuid, numeric);
drop function if exists public.drop_mobile_home_item_quantity(text, uuid, uuid, numeric);
create function public.drop_mobile_home_item_quantity(p_session_token text, p_item_id uuid, p_actor_character_id uuid, p_quantity numeric)
returns jsonb language sql security definer set search_path = public, extensions as $$
  select public.drop_house_inventory_item_quantity(p_session_token, p_item_id, p_actor_character_id, p_quantity)
$$;

create or replace function public.construction_source_item_accessible(
  p_profile public.profiles,
  p_actor public.characters,
  p_item public.inventory_items
)
returns boolean
language plpgsql
stable
set search_path = public
as $$
declare
  v_property public.storage_properties%rowtype;
  v_root public.inventory_items%rowtype;
  v_carrier public.characters%rowtype;
  v_actor_city_key text;
begin
  if p_item.character_id = p_actor.id then return true; end if;
  v_actor_city_key := coalesce(p_actor.location_city_key,
    (select city.city_key from public.cities city where lower(trim(city.name)) = lower(trim(p_actor.location_name)) limit 1),
    nullif(public.safe_slug(p_actor.location_name), ''), 'wild');

  if p_item.property_id is not null then
    select * into v_property from public.storage_properties where id = p_item.property_id;
    return v_property.owner_user_id is not distinct from p_actor.owner_user_id
      and v_property.property_kind = 'house'
      and not v_property.is_locked
      and v_property.city_key is not distinct from v_actor_city_key;
  end if;

  with recursive ancestry as (
    select item.* from public.inventory_items item where item.id = p_item.id
    union all
    select parent.* from public.inventory_items parent join ancestry child on child.parent_item_id = parent.id
  )
  select * into v_root from ancestry where parent_item_id is null order by id limit 1;
  if v_root.id is null or v_root.character_id is null then return false; end if;
  select * into v_carrier from public.characters where id = v_root.character_id;
  if v_carrier.owner_user_id is distinct from p_actor.owner_user_id
    or not public.characters_share_location(v_carrier, p_actor)
  then return false; end if;
  return (
    public.portable_property_kind(v_root.item_name, v_root.item_type) = 'house'
    or public.inventory_item_is_wagon(v_root.item_name, v_root.item_type)
  ) and public.inventory_storage_visible_to_profile(p_profile, v_root, v_carrier);
end;
$$;

create or replace function public.accessible_crafting_items(p_character_id uuid, p_station_city_name text)
returns table(
  source_order integer, source text, id uuid, item_name text, item_type text,
  rarity public.item_rarity, quantity numeric, properties text[]
)
language sql
stable
set search_path = public
as $$
  with actor as (
    select character.*, coalesce(character.location_city_key,
      (select city.city_key from public.cities city where lower(trim(city.name)) = lower(trim(character.location_name)) limit 1),
      nullif(public.safe_slug(character.location_name), ''), 'wild') as city_key,
      coalesce((select city.city_key from public.cities city where lower(trim(city.name)) = lower(trim(p_station_city_name)) limit 1),
        nullif(public.safe_slug(p_station_city_name), ''), 'wild') as station_city_key
    from public.characters character where character.id = p_character_id
  ), available as (
    select 0 as source_order, 'inventory'::text as source, item.*
    from actor join public.inventory_items item on item.character_id = actor.id
    where item.loadout_slot is null
      and not exists (
        with recursive ancestry as (
          select candidate.id, candidate.parent_item_id, candidate.item_name, candidate.item_type
          from public.inventory_items candidate where candidate.id = item.id
          union all
          select parent.id, parent.parent_item_id, parent.item_name, parent.item_type
          from public.inventory_items parent join ancestry child on child.parent_item_id = parent.id
        )
        select 1 from ancestry root
        where root.parent_item_id is null
          and public.portable_property_kind(root.item_name, root.item_type) = 'house'
      )
    union all
    select case when storage.is_main then 100 else 200 + greatest(0, storage.display_order) end,
      'house'::text, item.*
    from actor
    join public.storage_properties storage on storage.owner_user_id = actor.owner_user_id
      and storage.property_kind = 'house' and not storage.is_locked
      and storage.city_key = actor.city_key and storage.city_key = actor.station_city_key
    join public.inventory_items item on item.property_id = storage.id
    union all
    select case when mobile.storage_is_main then 100 else 200 + greatest(0, mobile.storage_display_order) end,
      'house'::text, item.*
    from actor
    join public.inventory_items mobile on mobile.parent_item_id is null
      and public.portable_property_kind(mobile.item_name, mobile.item_type) = 'house'
    join public.characters carrier on carrier.id = mobile.character_id and carrier.owner_user_id = actor.owner_user_id
      and coalesce(carrier.location_city_key, nullif(public.safe_slug(carrier.location_name), ''), 'wild') = actor.city_key
      and actor.city_key = actor.station_city_key
    join lateral (
      with recursive contents as (
        select child.* from public.inventory_items child where child.parent_item_id = mobile.id
        union all select child.* from public.inventory_items child join contents parent on child.parent_item_id = parent.id
      ) select * from contents
    ) item on true
  )
  select available.source_order, available.source, available.id,
    public.normalize_item_name(available.item_name), available.item_type, available.rarity,
    available.quantity, coalesce(catalog.properties, array[]::text[])
  from available
  left join public.item_catalog catalog on catalog.item_key = public.catalog_key_for_name(public.normalize_item_name(available.item_name))
  where available.is_storage = false and public.normalize_item_type(available.item_type) <> 'pet'
$$;

create or replace function public.crafting_house_is_accessible(p_character_id uuid, p_station_city_name text)
returns boolean language sql stable set search_path = public as $$
  select exists(select 1 from public.accessible_crafting_items(p_character_id, p_station_city_name) item where item.source = 'house')
$$;

create or replace function public.house_item_quantity_by_name(p_character_id uuid, p_item_name text, p_station_city_name text)
returns numeric language sql stable set search_path = public as $$
  select coalesce(sum(item.quantity), 0)
  from public.accessible_crafting_items(p_character_id, p_station_city_name) item
  where item.source = 'house' and lower(item.item_name) = lower(public.normalize_item_name(p_item_name))
$$;

create or replace function public.consume_house_item_by_name(p_character_id uuid, p_item_name text, p_quantity numeric, p_station_city_name text)
returns void language plpgsql security definer set search_path = public as $$
declare v_needed numeric := coalesce(p_quantity, 0); v_item record; v_take numeric;
begin
  if v_needed <= 0 then return; end if;
  for v_item in
    select available.id, available.item_name, available.quantity
    from public.accessible_crafting_items(p_character_id, p_station_city_name) available
    where available.source = 'house' and lower(available.item_name) = lower(public.normalize_item_name(p_item_name))
    order by available.source_order, available.id
  loop
    exit when v_needed <= 0;
    v_take := least(v_needed, v_item.quantity);
    if v_take >= v_item.quantity then delete from public.inventory_items where id = v_item.id;
    else update public.inventory_items set quantity = quantity - v_take, updated_at = now() where id = v_item.id;
    end if;
    v_needed := v_needed - v_take;
  end loop;
  if v_needed > 0 then raise exception 'Not enough % in accessible local houses.', p_item_name; end if;
end;
$$;

create or replace function public.crafting_selection_item(p_character_id uuid, p_source text, p_item_id uuid, p_station_city_name text)
returns table(item_name text, item_type text, rarity public.item_rarity, quantity numeric, properties text[])
language sql stable set search_path = public as $$
  select item.item_name, item.item_type, item.rarity, item.quantity, item.properties
  from public.accessible_crafting_items(p_character_id, p_station_city_name) item
  where item.id = p_item_id and item.source = lower(trim(coalesce(p_source, '')))
    and public.normalize_item_type(item.item_type) <> 'potion'
$$;

create or replace function public.consume_crafting_selection(p_character_id uuid, p_source text, p_item_id uuid, p_quantity numeric, p_station_city_name text)
returns void language plpgsql security definer set search_path = public as $$
declare v_item public.inventory_items%rowtype; v_needed numeric := coalesce(p_quantity, 0);
begin
  if v_needed <= 0 then raise exception 'Quantity must be positive.'; end if;
  if not exists (
    select 1 from public.accessible_crafting_items(p_character_id, p_station_city_name) available
    where available.id = p_item_id and available.source = lower(trim(coalesce(p_source, '')))
  ) then raise exception 'Selected crafting item is not accessible.'; end if;
  select * into v_item from public.inventory_items where id = p_item_id for update;
  if v_item.id is null then raise exception 'Selected crafting item is not accessible.'; end if;
  if v_item.quantity < v_needed then raise exception 'Not enough %.', v_item.item_name; end if;
  if v_item.quantity = v_needed then delete from public.inventory_items where id = v_item.id;
  else update public.inventory_items set quantity = quantity - v_needed, updated_at = now() where id = v_item.id;
  end if;
end;
$$;

create or replace function public.brewery_available_items(p_character_id uuid, p_station_city_name text)
returns jsonb language sql stable set search_path = public as $$
  with useful as (
    select * from public.accessible_crafting_items(p_character_id, p_station_city_name) available
    where (public.normalize_item_type(available.item_type) <> 'potion' or lower(available.item_name) = 'arcane nector')
      and (lower(available.item_name) = 'arcane nector' or exists (
        select 1 from unnest(available.properties) property(name)
        where property.name in ('Catalyst', 'Stabilizer')
          or exists (select 1 from public.alchemy_potion_definitions definition where definition.property_key = property.name)
      ))
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'source', source, 'id', id, 'name', item_name, 'type', item_type,
    'rarity', rarity, 'quantity', quantity, 'properties', to_jsonb(properties),
    'catalystBonus', case when 'Catalyst' = any(properties) then public.catalyst_bonus_for_rarity(rarity) else 0 end
  ) order by source_order, item_name, id), '[]'::jsonb) from useful
$$;

create or replace function public.board_pet_at_stable(p_session_token text, p_vendor_id uuid, p_item_id uuid, p_character_id uuid)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_profile public.profiles%rowtype;
  v_vendor public.shop_vendors%rowtype;
  v_section public.shop_sections%rowtype;
  v_character public.characters%rowtype;
  v_item public.inventory_items%rowtype;
  v_used_slots integer;
  v_wallet integer;
  v_free boolean;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;
  select * into v_vendor from public.shop_vendors where id = p_vendor_id;
  if v_vendor.id is null or v_vendor.blueprint_type <> 'stable' then raise exception 'Stable not found.'; end if;
  select * into v_character from public.characters where id = p_character_id;
  if v_character.id is null then raise exception 'Choose a character to board the animal.'; end if;
  perform public.assert_inventory_access(v_profile, v_character.id, false);
  if v_profile.role <> 'dm'::public.user_role and not public.character_is_in_city(v_character, v_vendor.city_key) then raise exception 'That character is not at this stable.'; end if;
  select * into v_section from public.shop_sections
  where vendor_id = v_vendor.id and section_type = 'holding' and not is_hidden
  order by display_order, section_name limit 1;
  if v_section.id is null then raise exception 'This stable needs a Holding section before animals can board.'; end if;
  select count(*)::integer into v_used_slots from public.market_products product
  where product.vendor_id = v_vendor.id and product.shop_section = v_section.section_name;
  if v_section.slot_count > 0 and v_used_slots >= v_section.slot_count then raise exception 'That stable has no open boarding slots.'; end if;

  select * into v_item from public.inventory_items where id = p_item_id for update;
  if v_item.id is null or public.normalize_item_type(v_item.item_type) <> 'pet' then raise exception 'Animal not found.'; end if;
  perform public.assert_inventory_item_control(v_profile, v_item, p_character_id);
  if public.inventory_item_owner_user_id(v_item) is distinct from v_character.owner_user_id and v_profile.role <> 'dm'::public.user_role then
    raise exception 'The boarding character must belong to the animal owner.';
  end if;

  v_free := v_profile.role = 'dm'::public.user_role or public.profile_runs_shop_vendor(v_profile, v_vendor);
  if v_vendor.boarding_fee_coin > 0 and not v_free then
    v_wallet := public.wallet_total_currency(v_character.id, 'common');
    if v_wallet < v_vendor.boarding_fee_coin then raise exception 'Not enough global currency to board this animal.'; end if;
    perform public.set_wallet_from_currency_value(v_character.id, 'common', v_wallet - v_vendor.boarding_fee_coin);
    perform public.credit_character_wallet_value(v_vendor.payout_character_id, 'common', v_vendor.boarding_fee_coin);
  end if;

  insert into public.market_products(
    vendor_id, product_key, item_name, item_display_name, description, item_type, rarity,
    price_coin, currency_system_key, stock_quantity, catalog_item_key, shop_section,
    quantity_step, product_kind, item_is_accessory, item_is_storage, item_storage_capacity,
    item_modifiers, item_enchantment, item_rune_name, item_material, item_enhancement_count,
    item_is_two_handed, item_potion_strength, item_potion_property, item_potion_quality,
    item_spell_book_form, boarded_item_id, boarded_owner_user_id, boarded_source_character_id, boarded_at,
    is_available, display_order
  ) values (
    v_vendor.id, public.safe_slug(v_vendor.vendor_key || '-boarded-' || v_item.item_name || '-' || substring(v_item.id::text from 1 for 8)),
    v_item.item_name, v_item.display_name, v_item.item_description, 'pet', v_item.rarity,
    0, 'common', 1, public.catalog_key_for_name(v_item.item_name), v_section.section_name,
    1, 'item', v_item.is_accessory, v_item.is_storage, v_item.storage_capacity,
    v_item.modifiers, v_item.enchantment, v_item.rune_name, v_item.material,
    v_item.enhancement_count, v_item.is_two_handed, v_item.potion_strength,
    v_item.potion_property, v_item.potion_quality, v_item.spell_book_form, v_item.id,
    public.inventory_item_owner_user_id(v_item), v_character.id, now(), true,
    coalesce((select max(display_order) + 10 from public.market_products where vendor_id = v_vendor.id), 10)
  );
  delete from public.inventory_items where id = v_item.id;
  return public.get_discovered_cities(p_session_token);
end;
$$;

create or replace function public.get_stable_boarding_options(p_session_token text, p_vendor_id uuid, p_character_id uuid)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_profile public.profiles%rowtype;
  v_vendor public.shop_vendors%rowtype;
  v_character public.characters%rowtype;
  v_section public.shop_sections%rowtype;
  v_used integer;
  v_animals jsonb;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;
  select * into v_vendor from public.shop_vendors where id = p_vendor_id;
  select * into v_character from public.characters where id = p_character_id;
  if v_vendor.id is null or v_vendor.blueprint_type <> 'stable' then raise exception 'Stable not found.'; end if;
  if v_character.id is null then raise exception 'Choose a character before boarding an animal.'; end if;
  perform public.assert_inventory_access(v_profile, v_character.id, false);
  if v_profile.role <> 'dm'::public.user_role and not public.character_is_in_city(v_character, v_vendor.city_key) then raise exception 'That character is not at this stable.'; end if;
  select * into v_section from public.shop_sections where vendor_id = v_vendor.id and section_type = 'holding' and not is_hidden order by display_order limit 1;
  if v_section.id is null then raise exception 'This stable needs a visible Holding section before animals can board.'; end if;
  select count(*)::integer into v_used from public.market_products where vendor_id = v_vendor.id and shop_section = v_section.section_name;
  select coalesce(jsonb_agg(jsonb_build_object(
    'itemId', item.id, 'itemName', item.item_name,
    'displayName', coalesce(nullif(item.display_name, ''), item.item_name),
    'rarity', item.rarity,
    'source', case
      when item.loadout_slot = 'active-pet' then 'active-pet'
      when public.inventory_portable_property_root(item.id) is not null then 'caged-wagon'
      else 'stable'
    end,
    'sourceLabel', case
      when item.loadout_slot = 'active-pet' then (select character.name || ' - Active Pet' from public.characters character where character.id = item.character_id)
      when public.inventory_portable_property_root(item.id) is not null then (
        select coalesce(nullif(root.display_name, ''), root.item_name)
        from public.inventory_items root where root.id = public.inventory_portable_property_root(item.id)
      )
      else property.property_name
    end
  ) order by coalesce(item.display_name, item.item_name), item.item_name), '[]'::jsonb) into v_animals
  from public.inventory_items item
  left join public.storage_properties property on property.id = item.property_id
  left join public.characters carrier on carrier.id = item.character_id
  where public.normalize_item_type(item.item_type) = 'pet'
    and coalesce(property.owner_user_id, carrier.owner_user_id) = v_character.owner_user_id
    and (
      (property.id is not null and property.property_kind = 'stable' and property.city_key = v_vendor.city_key and not property.is_locked)
      or (property.id is not null and property.property_kind = 'house' and property.city_key = v_vendor.city_key
        and not property.is_locked and public.inventory_container_property_kind(item.parent_item_id) = 'stable')
      or (carrier.id is not null and coalesce(carrier.location_city_key, nullif(public.safe_slug(carrier.location_name), ''), 'wild') = v_vendor.city_key)
    );
  return jsonb_build_object(
    'vendorId', v_vendor.id, 'vendorName', v_vendor.name,
    'boardingFeeCoin', v_vendor.boarding_fee_coin,
    'freeBoarding', v_profile.role = 'dm'::public.user_role or public.profile_runs_shop_vendor(v_profile, v_vendor),
    'holdingSection', v_section.section_name, 'slotCount', v_section.slot_count,
    'usedSlots', v_used, 'hasRoom', v_section.slot_count = 0 or v_used < v_section.slot_count,
    'animals', v_animals
  );
end;
$$;

create or replace function public.retrieve_boarded_stable_pet(p_session_token text, p_product_id uuid, p_character_id uuid default null)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_profile public.profiles%rowtype;
  v_product public.market_products%rowtype;
  v_vendor public.shop_vendors%rowtype;
  v_character public.characters%rowtype;
  v_destination record;
  v_location_character_id uuid;
  v_location_property_id uuid;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  select * into v_product from public.market_products where id = p_product_id for update;
  if v_product.id is null or v_product.boarded_owner_user_id is null or public.normalize_item_type(v_product.item_type) <> 'pet' then raise exception 'Boarded animal not found.'; end if;
  select * into v_vendor from public.shop_vendors where id = v_product.vendor_id;
  if v_profile.role <> 'dm'::public.user_role and not public.profile_runs_shop_vendor(v_profile, v_vendor) and v_profile.id is distinct from v_product.boarded_owner_user_id then
    raise exception 'Only the animal owner, stable keeper, or Dungeon Master can return this animal.';
  end if;
  select * into v_character from public.characters character
  where character.id = coalesce(p_character_id, v_product.boarded_source_character_id)
    and character.owner_user_id = v_product.boarded_owner_user_id;
  if v_character.id is null then
    select * into v_character from public.characters character
    where character.owner_user_id = v_product.boarded_owner_user_id and public.character_is_in_city(character, v_vendor.city_key)
    order by character.created_at, character.id limit 1;
  end if;
  if v_character.id is null then raise exception 'Choose one of the owner''s characters at this stable.'; end if;
  if not public.character_is_in_city(v_character, v_vendor.city_key) then
    raise exception 'Choose one of the owner''s characters at this stable.';
  end if;
  select * into v_destination from public.find_local_animal_destination(v_character.id);
  if v_destination.destination_slot is null then raise exception 'No local stable or Caged Wagon has room for this animal.'; end if;
  v_location_property_id := v_destination.destination_property_id;
  if v_destination.destination_parent_item_id is not null then
    select character_id, property_id into v_location_character_id, v_location_property_id
    from public.inventory_items where id = v_destination.destination_parent_item_id;
  end if;
  insert into public.inventory_items(
    id, character_id, property_id, parent_item_id, item_name, display_name, item_description,
    item_type, rarity, quantity, slot_index, is_accessory, is_storage, storage_active,
    storage_capacity, modifiers, enchantment, rune_name, material, enhancement_count,
    is_two_handed, potion_strength, potion_property, potion_quality, spell_book_form
  ) values (
    coalesce(v_product.boarded_item_id, gen_random_uuid()), v_location_character_id, v_location_property_id,
    v_destination.destination_parent_item_id, v_product.item_name, v_product.item_display_name,
    v_product.description, 'pet', v_product.rarity, 1, v_destination.destination_slot,
    v_product.item_is_accessory, false, false, 0, v_product.item_modifiers,
    v_product.item_enchantment, v_product.item_rune_name, v_product.item_material,
    v_product.item_enhancement_count, v_product.item_is_two_handed, v_product.item_potion_strength,
    v_product.item_potion_property, v_product.item_potion_quality, v_product.item_spell_book_form
  );
  delete from public.market_products where id = v_product.id;
  return public.get_discovered_cities(p_session_token);
end;
$$;

create or replace function public.apply_inventory_item_rune(p_session_token text, p_target_item_id uuid, p_rune_item_id uuid, p_source text default 'inventory')
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_profile public.profiles%rowtype;
  v_target public.inventory_items%rowtype;
  v_rune public.inventory_items%rowtype;
  v_rune_name text;
  v_owner_user_id uuid;
  v_actor_character_id uuid;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  select * into v_target from public.inventory_items where id = p_target_item_id for update;
  select * into v_rune from public.inventory_items where id = p_rune_item_id for update;
  if v_target.id is null or v_rune.id is null then raise exception 'The item or rune was not found.'; end if;
  v_owner_user_id := public.inventory_item_owner_user_id(v_target);
  if v_owner_user_id is distinct from public.inventory_item_owner_user_id(v_rune) then raise exception 'The item and rune must have the same owner.'; end if;
  v_actor_character_id := coalesce(v_target.character_id, v_rune.character_id,
    (select character.id from public.characters character
      left join public.storage_properties property on property.id = coalesce(v_target.property_id, v_rune.property_id)
      where character.owner_user_id = v_owner_user_id
        and (v_profile.role = 'dm'::public.user_role
          or coalesce(character.location_city_key, nullif(public.safe_slug(character.location_name), ''), 'wild') = property.city_key)
      order by character.created_at, character.id limit 1));
  perform public.assert_inventory_item_control(v_profile, v_target, v_actor_character_id);
  perform public.assert_inventory_item_control(v_profile, v_rune, v_actor_character_id);
  if not public.inventory_item_is_mythril(v_target.item_name, v_target.material) then raise exception 'Runes can only be applied to Mythril items.'; end if;
  if public.normalize_item_type(v_rune.item_type) <> 'rune' then raise exception 'Choose a rune item.'; end if;
  v_rune_name := regexp_replace(public.normalize_item_name(v_rune.item_name), '\s+Rune$', '', 'i');
  update public.inventory_items set rune_name = v_rune_name, updated_at = now() where id = v_target.id returning * into v_target;
  if v_rune.quantity <= 1 then delete from public.inventory_items where id = v_rune.id;
  else update public.inventory_items set quantity = quantity - 1, updated_at = now() where id = v_rune.id;
  end if;
  return public.inventory_item_record_to_json(v_target);
end;
$$;

create or replace function public.move_inventory_storage_tree_to_character(
  p_storage_item_id uuid,
  p_to_character_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_storage public.inventory_items%rowtype;
  v_target public.characters%rowtype;
  v_storage_kind text;
  v_portable_kind text;
  v_source_owner_user_id uuid;
  v_source_character_id uuid;
  v_activate boolean;
  v_slot integer;
begin
  select * into v_storage from public.inventory_items where id = p_storage_item_id for update;
  select * into v_target from public.characters where id = p_to_character_id;
  if v_storage.id is null or not v_storage.is_storage then raise exception 'Storage container is no longer available.'; end if;
  if v_target.id is null then raise exception 'Receiving character was not found.'; end if;
  if v_storage.loadout_slot is not null then raise exception 'Unequip that storage container before moving it.'; end if;

  v_source_owner_user_id := public.inventory_item_owner_user_id(v_storage);
  v_source_character_id := v_storage.character_id;
  v_storage_kind := public.additional_storage_kind(v_storage.item_name, v_storage.item_type);
  v_portable_kind := public.portable_property_kind(v_storage.item_name, v_storage.item_type);
  v_activate := v_portable_kind is null
    and v_storage_kind is not null
    and not exists (
    select 1 from public.inventory_items active
    where active.character_id = v_target.id
      and active.id <> v_storage.id
      and active.parent_item_id is null
      and active.loadout_slot is null
      and active.is_storage
      and active.storage_active
      and public.additional_storage_kind(active.item_name, active.item_type) = v_storage_kind
    );
  if v_portable_kind is null and not v_activate
    and exists (select 1 from public.inventory_items child where child.parent_item_id = v_storage.id) then
    raise exception 'That character already has active % storage. Empty this container before gifting or trading it.', v_storage.item_name;
  end if;
  v_slot := case when v_activate then 0 else public.first_free_character_slot(v_target.id) end;
  if v_slot is null then raise exception 'Receiving character inventory is full.'; end if;

  perform set_config('app.canonical_storage_move', 'on', true);
  with recursive moving as (
    select item.id from public.inventory_items item where item.id = v_storage.id
    union all
    select child.id from public.inventory_items child join moving parent on child.parent_item_id = parent.id
  )
  update public.inventory_items
  set character_id = v_target.id,
      property_id = null,
      loadout_slot = null
  where id in (select id from moving);
  update public.inventory_items
  set parent_item_id = null,
      slot_index = v_slot,
      storage_active = v_activate,
      storage_is_main = case
        when v_portable_kind is not null and v_source_owner_user_id is distinct from v_target.owner_user_id then false
        else storage_is_main
      end,
      updated_at = now()
  where id = v_storage.id;
  perform set_config('app.canonical_storage_move', 'off', true);
  perform public.ensure_character_additional_storage_activation(v_source_character_id);
  perform public.ensure_character_additional_storage_activation(v_target.id);
end;
$$;

create or replace function public.transfer_trade_inventory_item(
  p_item_id uuid,
  p_from_character_id uuid,
  p_to_character_id uuid,
  p_quantity numeric
)
returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_source public.inventory_items%rowtype;
  v_target public.inventory_items%rowtype;
  v_target_character public.characters%rowtype;
  v_destination record;
  v_quantity numeric;
  v_slot integer;
  v_destination_character_id uuid;
  v_destination_property_id uuid;
  v_label text;
begin
  select * into v_source from public.inventory_items where id = p_item_id for update;
  select * into v_target_character from public.characters where id = p_to_character_id;
  if v_source.id is null or v_source.character_id is distinct from p_from_character_id then raise exception 'A trade item is no longer held by the expected character.'; end if;
  if v_target_character.id is null then raise exception 'Receiving character was not found.'; end if;
  if v_source.loadout_slot is not null and public.normalize_item_type(v_source.item_type) <> 'pet' then raise exception 'A trade item is currently equipped.'; end if;
  v_quantity := public.assert_valid_item_quantity(v_source.item_name, v_source.item_type, greatest(0.5, coalesce(p_quantity, 1)));
  if v_quantity > v_source.quantity then raise exception 'A trade item quantity is no longer available.'; end if;
  v_label := public.format_item_quantity(v_quantity) || ' ' || coalesce(v_source.display_name, v_source.item_name);

  if v_source.is_storage then
    if v_quantity <> 1 or v_source.quantity <> 1 then raise exception 'Storage containers must be transferred one at a time.'; end if;
    perform public.move_inventory_storage_tree_to_character(v_source.id, v_target_character.id);
    return '1 ' || coalesce(v_source.display_name, v_source.item_name);
  end if;

  if public.normalize_item_type(v_source.item_type) = 'pet' then
    select * into v_destination from public.find_local_animal_destination(v_target_character.id);
    if v_destination.destination_slot is null then raise exception 'No local stable or Caged Wagon has room for this animal.'; end if;
    v_destination_property_id := v_destination.destination_property_id;
    if v_destination.destination_parent_item_id is not null then
      select parent.character_id, parent.property_id into v_destination_character_id, v_destination_property_id
      from public.inventory_items parent where parent.id = v_destination.destination_parent_item_id;
    end if;
    perform set_config('app.canonical_storage_move', 'on', true);
    update public.inventory_items
    set character_id = v_destination_character_id,
        property_id = v_destination_property_id,
        parent_item_id = v_destination.destination_parent_item_id,
        loadout_slot = null,
        slot_index = v_destination.destination_slot,
        updated_at = now()
    where id = v_source.id;
    perform set_config('app.canonical_storage_move', 'off', true);
    return v_label;
  end if;

  select * into v_target
  from public.inventory_items candidate
  where candidate.character_id = v_target_character.id
    and candidate.parent_item_id is null
    and candidate.loadout_slot is null
    and not (candidate.is_storage and candidate.storage_active)
    and public.inventory_items_stackable(candidate, v_source)
  order by candidate.slot_index, candidate.created_at, candidate.id
  limit 1
  for update;

  if v_target.id is not null then
    update public.inventory_items set quantity = quantity + v_quantity, updated_at = now() where id = v_target.id;
    if v_quantity = v_source.quantity then delete from public.inventory_items where id = v_source.id;
    else update public.inventory_items set quantity = quantity - v_quantity, updated_at = now() where id = v_source.id;
    end if;
    return v_label;
  end if;

  v_slot := public.first_free_character_slot(v_target_character.id);
  if v_slot is null then raise exception 'Receiving character inventory is full.'; end if;
  if v_quantity = v_source.quantity then
    update public.inventory_items
    set character_id = v_target_character.id,
        property_id = null,
        parent_item_id = null,
        loadout_slot = null,
        slot_index = v_slot,
        updated_at = now()
    where id = v_source.id;
  else
    insert into public.inventory_items (
      character_id, property_id, parent_item_id, slot_index, loadout_slot,
      item_name, display_name, item_description, item_type, rarity, quantity,
      is_accessory, is_storage, storage_active, storage_capacity, modifiers,
      enchantment, rune_name, material, enhancement_count, is_two_handed,
      potion_strength, potion_property, potion_quality, spell_book_form
    ) values (
      v_target_character.id, null, null, v_slot, null,
      v_source.item_name, v_source.display_name, v_source.item_description, v_source.item_type, v_source.rarity, v_quantity,
      v_source.is_accessory, false, false, 0, v_source.modifiers,
      v_source.enchantment, v_source.rune_name, v_source.material, v_source.enhancement_count, v_source.is_two_handed,
      v_source.potion_strength, v_source.potion_property, v_source.potion_quality, v_source.spell_book_form
    );
    update public.inventory_items set quantity = quantity - v_quantity, updated_at = now() where id = v_source.id;
  end if;
  return v_label;
end;
$$;

create or replace function public.gift_inventory_item(
  p_session_token text,
  p_item_id uuid,
  p_target_character_id uuid,
  p_quantity numeric default 1
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_source public.inventory_items%rowtype;
  v_sender public.characters%rowtype;
  v_target public.characters%rowtype;
  v_label text;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;
  select * into v_source from public.inventory_items where id = p_item_id;
  if v_source.id is null or v_source.character_id is null then raise exception 'Item was not found in a character inventory.'; end if;
  v_sender := public.assert_inventory_access(v_profile, v_source.character_id, false);
  select * into v_target from public.characters where id = p_target_character_id;
  if v_target.id is null or v_target.owner_user_id is null then raise exception 'Target character was not found or assigned.'; end if;
  if v_target.id = v_sender.id then raise exception 'Choose another character to gift this to.'; end if;
  if v_sender.owner_user_id is distinct from v_target.owner_user_id
    and v_profile.role <> 'dm'::public.user_role
    and not coalesce(v_target.gift_inventory_open, true)
  then
    raise exception 'This persons inventory is closed from gifting efforts and grows tired of your pranks';
  end if;
  v_label := public.transfer_trade_inventory_item(v_source.id, v_sender.id, v_target.id, p_quantity);
  if v_sender.owner_user_id is distinct from v_target.owner_user_id then
    insert into public.campaign_notifications(recipient_user_id, title, body, notice_kind, source_type, location_name)
    values (v_target.owner_user_id, v_sender.name || ' gave something to ' || v_target.name,
      v_label || ' was transferred to ' || v_target.name || '.', 'notice', 'gift', v_target.location_name);
  end if;
  return public.get_character_inventory(p_session_token, v_sender.id);
end;
$$;

create or replace function public.inventory_storage_visible_to_profile(
  p_profile public.profiles,
  p_storage public.inventory_items,
  p_owner_character public.characters
)
returns boolean language sql stable set search_path = public as $$
  select coalesce(p_storage.is_storage, false)
    and coalesce(p_storage.storage_active, false)
    and p_storage.parent_item_id is null
    and p_storage.loadout_slot is null
    and (
      (public.inventory_item_is_wagon(p_storage.item_name, p_storage.item_type)
        and not public.inventory_item_is_mobile_home_storage(p_storage.item_name, p_storage.item_type)
        and not public.inventory_item_is_caged_wagon_storage(p_storage.item_name, p_storage.item_type))
      or p_profile.role = 'dm'::public.user_role
      or p_owner_character.owner_user_id is not distinct from p_profile.id
    )
$$;

-- Shared wagon storage remains available to characters at the same location,
-- but Wagon Homes and Caged Wagons are canonical private properties and never
-- pass through the shared-wagon API.
create or replace function public.get_location_wagon_storage(
  p_session_token text,
  p_character_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_character public.characters%rowtype;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;
  v_character := public.assert_inventory_access(v_profile, p_character_id, false);

  return jsonb_build_object(
    'wagons', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'wagon', public.inventory_item_record_to_json(wagon),
        'ownerCharacterId', owner_character.id,
        'ownerName', owner_character.name,
        'ownerUserId', owner_character.owner_user_id,
        'locationName', owner_character.location_name,
        'canManage', v_profile.role = 'dm'::public.user_role or owner_character.owner_user_id is not distinct from v_profile.id
      ) order by owner_character.name, wagon.item_name, wagon.id), '[]'::jsonb)
      from public.inventory_items wagon
      join public.characters owner_character on owner_character.id = wagon.character_id
      where wagon.parent_item_id is null
        and wagon.loadout_slot is null
        and public.inventory_item_is_wagon(wagon.item_name, wagon.item_type)
        and public.portable_property_kind(wagon.item_name, wagon.item_type) is null
        and public.inventory_storage_visible_to_profile(v_profile, wagon, owner_character)
        and public.characters_share_location(owner_character, v_character)
    ),
    'items', (
      select coalesce(jsonb_agg(public.inventory_item_record_to_json(child)
        order by child.parent_item_id, child.slot_index, child.item_name, child.id), '[]'::jsonb)
      from public.inventory_items child
      join public.inventory_items wagon on wagon.id = child.parent_item_id
      join public.characters owner_character on owner_character.id = wagon.character_id
      where public.inventory_item_is_wagon(wagon.item_name, wagon.item_type)
        and public.portable_property_kind(wagon.item_name, wagon.item_type) is null
        and public.inventory_storage_visible_to_profile(v_profile, wagon, owner_character)
        and public.characters_share_location(owner_character, v_character)
    ),
    'activity', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', recent.id,
        'wagonId', recent.wagon_item_id,
        'actorCharacterId', recent.actor_character_id,
        'actorName', recent.actor_name,
        'action', recent.action,
        'itemName', recent.item_name,
        'quantity', recent.quantity,
        'createdAt', recent.created_at
      ) order by recent.created_at desc), '[]'::jsonb)
      from (
        select log_entry.*
        from public.wagon_activity_log log_entry
        join public.inventory_items wagon on wagon.id = log_entry.wagon_item_id
        join public.characters owner_character on owner_character.id = wagon.character_id
        where public.inventory_item_is_wagon(wagon.item_name, wagon.item_type)
          and public.portable_property_kind(wagon.item_name, wagon.item_type) is null
          and public.inventory_storage_visible_to_profile(v_profile, wagon, owner_character)
          and public.characters_share_location(owner_character, v_character)
        order by log_entry.created_at desc
        limit 30
      ) recent
    )
  );
end;
$$;

create or replace function public.move_inventory_item_to_wagon(
  p_session_token text,
  p_actor_character_id uuid,
  p_item_id uuid,
  p_wagon_id uuid,
  p_slot_index integer
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_actor public.characters%rowtype;
  v_wagon public.inventory_items%rowtype;
  v_wagon_owner public.characters%rowtype;
  v_item public.inventory_items%rowtype;
  v_target public.inventory_items%rowtype;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;
  v_actor := public.assert_inventory_access(v_profile, p_actor_character_id, false);

  select * into v_item from public.inventory_items where id = p_item_id for update;
  if v_item.id is null or v_item.character_id is distinct from v_actor.id then
    raise exception 'You can only store this character''s carried items.';
  end if;
  if v_item.loadout_slot is not null then raise exception 'Remove that item from the active loadout first.'; end if;
  if public.normalize_item_type(v_item.item_type) = 'pet' then raise exception 'Animals require a stable or Caged Wagon.'; end if;
  if public.portable_property_kind(v_item.item_name, v_item.item_type) is not null then
    raise exception 'Wagon Homes and Caged Wagons cannot be nested inside shared wagons.';
  end if;
  if v_item.is_storage and exists (select 1 from public.inventory_items child where child.parent_item_id = v_item.id) then
    raise exception 'Empty this storage item before placing it in a shared wagon.';
  end if;

  select * into v_wagon from public.inventory_items where id = p_wagon_id for update;
  if v_wagon.id is null
    or not public.inventory_item_is_wagon(v_wagon.item_name, v_wagon.item_type)
    or public.portable_property_kind(v_wagon.item_name, v_wagon.item_type) is not null
  then raise exception 'Shared wagon storage was not found.'; end if;
  select * into v_wagon_owner from public.characters where id = v_wagon.character_id;
  if v_wagon_owner.id is null or not public.characters_share_location(v_wagon_owner, v_actor) then
    raise exception 'That wagon is not in this character''s location.';
  end if;
  if not public.inventory_storage_visible_to_profile(v_profile, v_wagon, v_wagon_owner) then
    raise exception 'You cannot use that wagon.';
  end if;

  perform public.assert_inventory_item_placement(v_item.id, v_item.item_name, v_item.item_type,
    v_wagon.character_id, null, v_wagon.id, p_slot_index, null);
  select * into v_target from public.inventory_items target
  where target.parent_item_id = v_wagon.id and target.slot_index = p_slot_index
    and target.loadout_slot is null and target.id <> v_item.id
  for update;
  if v_target.id is not null then
    if not public.inventory_items_stackable(v_target, v_item) then raise exception 'That wagon slot is occupied.'; end if;
    update public.inventory_items set quantity = quantity + v_item.quantity, updated_at = now() where id = v_target.id;
    delete from public.inventory_items where id = v_item.id;
  else
    perform set_config('app.canonical_storage_move', 'on', true);
    update public.inventory_items set character_id = v_wagon.character_id, property_id = null,
      parent_item_id = v_wagon.id, slot_index = p_slot_index, loadout_slot = null,
      storage_active = false, updated_at = now()
    where id = v_item.id;
    perform set_config('app.canonical_storage_move', 'off', true);
    perform public.ensure_character_additional_storage_activation(v_actor.id);
  end if;
  insert into public.wagon_activity_log(wagon_item_id, actor_character_id, actor_name, action, item_name, quantity)
  values (v_wagon.id, v_actor.id, v_actor.name, 'stored', v_item.item_name, v_item.quantity);
  return public.get_location_wagon_storage(p_session_token, p_actor_character_id);
end;
$$;

create or replace function public.move_wagon_item_to_inventory(
  p_session_token text,
  p_actor_character_id uuid,
  p_item_id uuid,
  p_parent_item_id uuid default null,
  p_slot_index integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_actor public.characters%rowtype;
  v_wagon public.inventory_items%rowtype;
  v_wagon_owner public.characters%rowtype;
  v_item public.inventory_items%rowtype;
  v_target public.inventory_items%rowtype;
  v_slot integer;
  v_capacity integer;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;
  v_actor := public.assert_inventory_access(v_profile, p_actor_character_id, false);

  select * into v_item from public.inventory_items where id = p_item_id for update;
  if v_item.id is null or v_item.parent_item_id is null then raise exception 'Shared wagon item not found.'; end if;
  select * into v_wagon from public.inventory_items where id = v_item.parent_item_id for update;
  if v_wagon.id is null
    or not public.inventory_item_is_wagon(v_wagon.item_name, v_wagon.item_type)
    or public.portable_property_kind(v_wagon.item_name, v_wagon.item_type) is not null
  then raise exception 'Shared wagon storage was not found.'; end if;
  select * into v_wagon_owner from public.characters where id = v_wagon.character_id;
  if v_wagon_owner.id is null or not public.characters_share_location(v_wagon_owner, v_actor) then
    raise exception 'That wagon is not in this character''s location.';
  end if;
  if not public.inventory_storage_visible_to_profile(v_profile, v_wagon, v_wagon_owner) then
    raise exception 'You cannot use that wagon.';
  end if;

  v_capacity := public.assert_inventory_slot_capacity(v_actor, p_parent_item_id, coalesce(p_slot_index, 0));
  v_slot := p_slot_index;
  if v_slot is null then v_slot := public.find_first_free_inventory_slot(v_actor.id, p_parent_item_id, v_capacity); end if;
  if v_slot is null then raise exception 'No open inventory slot.'; end if;
  perform public.assert_inventory_item_placement(v_item.id, v_item.item_name, v_item.item_type,
    v_actor.id, null, p_parent_item_id, v_slot, null);
  select * into v_target from public.inventory_items target
  where target.character_id = v_actor.id
    and target.parent_item_id is not distinct from p_parent_item_id
    and target.slot_index = v_slot and target.loadout_slot is null
    and not (p_parent_item_id is null and target.is_storage and target.storage_active)
  for update;
  if v_target.id is not null then
    if not public.inventory_items_stackable(v_target, v_item) then raise exception 'That inventory slot is occupied.'; end if;
    update public.inventory_items set quantity = quantity + v_item.quantity, updated_at = now() where id = v_target.id;
    delete from public.inventory_items where id = v_item.id;
  else
    perform set_config('app.canonical_storage_move', 'on', true);
    update public.inventory_items set character_id = v_actor.id, property_id = null,
      parent_item_id = p_parent_item_id, slot_index = v_slot, loadout_slot = null,
      storage_active = false, updated_at = now()
    where id = v_item.id;
    perform set_config('app.canonical_storage_move', 'off', true);
    perform public.ensure_character_additional_storage_activation(v_actor.id);
  end if;
  insert into public.wagon_activity_log(wagon_item_id, actor_character_id, actor_name, action, item_name, quantity)
  values (v_wagon.id, v_actor.id, v_actor.name, 'taken', v_item.item_name, v_item.quantity);
  return public.get_character_inventory(p_session_token, p_actor_character_id);
end;
$$;

-- Final repair catches invalid historical items that were nested inside old containers.
do $$
declare
  v_item public.inventory_items%rowtype;
  v_destination public.storage_properties%rowtype;
  v_source_property public.storage_properties%rowtype;
  v_source_character public.characters%rowtype;
  v_owner_user_id uuid;
  v_city_key text;
  v_needed_kind text;
  v_slot integer;
begin
  perform set_config('app.canonical_storage_move', 'on', true);
  for v_item in
    select item.* from public.inventory_items item
    left join public.storage_properties property on property.id = item.property_id
    where (
      public.normalize_item_type(item.item_type) = 'pet'
      and item.loadout_slot is null
      and not (
        (item.parent_item_id is null and property.property_kind = 'stable')
        or (item.parent_item_id is not null and public.inventory_container_property_kind(item.parent_item_id) = 'stable')
      )
    ) or (
      public.normalize_item_type(item.item_type) <> 'pet'
      and (
        (item.parent_item_id is null and property.property_kind = 'stable')
        or (item.parent_item_id is not null and public.inventory_container_property_kind(item.parent_item_id) = 'stable')
      )
    ) or (
      public.portable_property_kind(item.item_name, item.item_type) is not null
      and item.parent_item_id is not null
    )
    order by item.created_at, item.id
  loop
    v_needed_kind := case when public.normalize_item_type(v_item.item_type) = 'pet' then 'stable' else 'house' end;
    if v_item.property_id is not null then
      select * into v_source_property from public.storage_properties where id = v_item.property_id;
      v_owner_user_id := v_source_property.owner_user_id;
      v_city_key := v_source_property.city_key;
    else
      select * into v_source_character from public.characters where id = v_item.character_id;
      v_owner_user_id := v_source_character.owner_user_id;
      v_city_key := coalesce(v_source_character.location_city_key,
        (select city.city_key from public.cities city where lower(trim(city.name)) = lower(trim(v_source_character.location_name)) limit 1),
        nullif(public.safe_slug(v_source_character.location_name), ''), 'wild');
    end if;
    if v_owner_user_id is null then raise exception 'Cannot preserve invalid item % because it has no owner.', v_item.id; end if;
    v_destination.id := null;
    select storage.* into v_destination from public.storage_properties storage
    where storage.owner_user_id = v_owner_user_id and storage.city_key = v_city_key and storage.property_kind = v_needed_kind
    order by storage.is_main desc, storage.display_order, storage.created_at, storage.id limit 1;
    if v_destination.id is null then
      insert into public.storage_properties(owner_user_id, property_kind, city_key, property_name, capacity, display_order, is_main)
      values(v_owner_user_id, v_needed_kind, v_city_key,
        case when v_needed_kind = 'stable' then 'Recovered Stable' else 'Recovered House' end, 1,
        coalesce((select max(display_order) + 10 from public.storage_properties where owner_user_id = v_owner_user_id), 0),
        v_needed_kind = 'house' and not exists(select 1 from public.storage_properties where owner_user_id = v_owner_user_id and property_kind = 'house' and is_main))
      returning * into v_destination;
    end if;
    v_slot := public.first_free_property_slot(v_destination.id);
    if v_slot is null then
      v_slot := v_destination.capacity;
      update public.storage_properties set capacity = capacity + 1 where id = v_destination.id returning * into v_destination;
    end if;
    update public.inventory_items set parent_item_id = null, loadout_slot = null,
      slot_index = 2147483646, storage_active = false where id = v_item.id;
    with recursive tree as (
      select item.id from public.inventory_items item where item.id = v_item.id
      union all select child.id from public.inventory_items child join tree parent on child.parent_item_id = parent.id
    ) update public.inventory_items set character_id = null, property_id = v_destination.id where id in (select id from tree);
    update public.inventory_items set slot_index = v_slot where id = v_item.id;
  end loop;
  perform set_config('app.canonical_storage_move', 'off', true);

  for v_item in select * from public.inventory_items order by created_at, id loop
    begin
      perform public.assert_inventory_item_placement(v_item.id, v_item.item_name, v_item.item_type,
        v_item.character_id, v_item.property_id, v_item.parent_item_id, v_item.slot_index, v_item.loadout_slot);
    exception when others then
      raise exception 'Canonical storage validation failed for item % (%): %', v_item.id, v_item.item_name, sqlerrm;
    end;
  end loop;

  if exists (
    select 1
    from public.inventory_items item
    where public.portable_property_kind(item.item_name, item.item_type) is not null
      and item.storage_active
  ) then
    raise exception 'Canonical storage validation failed: a Wagon Home or Caged Wagon is deployed as bonus storage.';
  end if;

  if exists (
    select 1 from public.inventory_items item
    where item.storage_active and (
      item.character_id is null
      or item.property_id is not null
      or item.parent_item_id is not null
      or item.loadout_slot is not null
      or not item.is_storage
      or public.additional_storage_kind(item.item_name, item.item_type) is null
    )
  ) then
    raise exception 'Canonical storage validation failed: active additional storage has an invalid location or type.';
  end if;

  if exists (
    select 1
    from public.inventory_items item
    where item.character_id is not null
      and item.parent_item_id is null
      and item.loadout_slot is null
      and item.is_storage
      and public.additional_storage_kind(item.item_name, item.item_type) is not null
    group by item.character_id, public.additional_storage_kind(item.item_name, item.item_type)
    having count(*) filter (where item.storage_active) <> 1
  ) then
    raise exception 'Canonical storage validation failed: each owned additional-storage kind must have exactly one active copy.';
  end if;
end;
$$;

drop trigger if exists app_live_storage_properties on public.storage_properties;
create trigger app_live_storage_properties
after insert or update or delete on public.storage_properties
for each row execute function public.touch_app_live_update_trigger('house,inventory,cities');

grant execute on function public.get_player_homes(text, uuid, uuid, text, uuid) to anon, authenticated;
grant execute on function public.reorder_player_homes(text, uuid, uuid, jsonb) to anon, authenticated;
grant execute on function public.save_player_home(text, uuid, uuid, text, uuid, jsonb) to anon, authenticated;
grant execute on function public.delete_player_home(text, uuid, uuid, text, uuid) to anon, authenticated;
grant execute on function public.add_home_inventory_item(text, uuid, uuid, uuid, uuid, integer, text, text, text, numeric, boolean, integer, jsonb, text, text, integer, boolean, text, text, text, text, boolean) to anon, authenticated;
grant execute on function public.add_mobile_home_inventory_item(text, uuid, uuid, uuid, integer, text, text, text, numeric, boolean, integer, jsonb, text, text, integer, boolean, text, text, text, text, boolean) to anon, authenticated;
grant execute on function public.move_inventory_item_to_home(text, uuid, uuid, uuid, text, integer, uuid) to anon, authenticated;
grant execute on function public.move_home_item_to_inventory(text, uuid, uuid, uuid) to anon, authenticated;
grant execute on function public.move_item_between_homes(text, uuid, uuid, uuid, text, uuid, text, integer, uuid) to anon, authenticated;
grant execute on function public.update_house_inventory_item_state(text, uuid, uuid, jsonb) to anon, authenticated;
grant execute on function public.drop_house_inventory_item_quantity(text, uuid, uuid, numeric) to anon, authenticated;
grant execute on function public.update_mobile_home_item_state(text, uuid, uuid, jsonb) to anon, authenticated;
grant execute on function public.drop_mobile_home_item_quantity(text, uuid, uuid, numeric) to anon, authenticated;
grant execute on function public.place_pet_item_in_stable_for_character(uuid, text, text, text, public.item_rarity, numeric, boolean, jsonb, text, text, text, integer, boolean) to anon, authenticated;
grant execute on function public.place_pet_item_for_character(uuid, text, text, text, public.item_rarity, numeric, boolean, jsonb, text, text, text, integer, boolean) to anon, authenticated;
grant execute on function public.accessible_crafting_items(uuid, text) to anon, authenticated;
grant execute on function public.crafting_house_is_accessible(uuid, text) to anon, authenticated;
grant execute on function public.house_item_quantity_by_name(uuid, text, text) to anon, authenticated;
grant execute on function public.consume_house_item_by_name(uuid, text, numeric, text) to anon, authenticated;
grant execute on function public.crafting_selection_item(uuid, text, uuid, text) to anon, authenticated;
grant execute on function public.consume_crafting_selection(uuid, text, uuid, numeric, text) to anon, authenticated;
grant execute on function public.brewery_available_items(uuid, text) to anon, authenticated;
grant execute on function public.board_pet_at_stable(text, uuid, uuid, uuid) to anon, authenticated;
grant execute on function public.get_stable_boarding_options(text, uuid, uuid) to anon, authenticated;
grant execute on function public.retrieve_boarded_stable_pet(text, uuid, uuid) to anon, authenticated;
grant execute on function public.apply_inventory_item_rune(text, uuid, uuid, text) to anon, authenticated;

-- Internal mutation helpers are intentionally unavailable through PostgREST.
-- Only token-authenticated public RPCs above may invoke them.
revoke execute on function public.portable_property_kind(text, text) from public, anon, authenticated;
revoke execute on function public.inventory_container_property_kind(uuid) from public, anon, authenticated;
revoke execute on function public.ensure_character_additional_storage_activation(uuid) from public, anon, authenticated;
revoke execute on function public.move_inventory_item_instance(public.profiles, uuid, uuid, uuid, uuid, uuid, integer, text) from public, anon, authenticated;
revoke execute on function public.inventory_portable_property_root(uuid) from public, anon, authenticated;
revoke execute on function public.storage_property_accessible(public.profiles, public.storage_properties, uuid) from public, anon, authenticated;
revoke execute on function public.assert_storage_property_access(public.profiles, uuid, uuid) from public, anon, authenticated;
revoke execute on function public.inventory_item_owner_user_id(public.inventory_items) from public, anon, authenticated;
revoke execute on function public.assert_inventory_item_control(public.profiles, public.inventory_items, uuid) from public, anon, authenticated;
revoke execute on function public.update_inventory_item_state_impl(text, uuid, jsonb) from public, anon, authenticated;
revoke execute on function public.move_inventory_storage_tree_to_character(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.transfer_trade_inventory_item(uuid, uuid, uuid, numeric) from public, anon, authenticated;
revoke execute on function public.find_local_animal_destination(uuid) from public, anon, authenticated;
revoke execute on function public.place_pet_item_in_stable_for_character(uuid, text, text, text, public.item_rarity, numeric, boolean, jsonb, text, text, text, integer, boolean) from public, anon, authenticated;
revoke execute on function public.place_pet_item_for_character(uuid, text, text, text, public.item_rarity, numeric, boolean, jsonb, text, text, text, integer, boolean) from public, anon, authenticated;
revoke execute on function public.accessible_crafting_items(uuid, text) from public, anon, authenticated;
revoke execute on function public.crafting_house_is_accessible(uuid, text) from public, anon, authenticated;
revoke execute on function public.house_item_quantity_by_name(uuid, text, text) from public, anon, authenticated;
revoke execute on function public.consume_house_item_by_name(uuid, text, numeric, text) from public, anon, authenticated;
revoke execute on function public.crafting_selection_item(uuid, text, uuid, text) from public, anon, authenticated;
revoke execute on function public.consume_crafting_selection(uuid, text, uuid, numeric, text) from public, anon, authenticated;
revoke execute on function public.brewery_available_items(uuid, text) from public, anon, authenticated;
revoke execute on function public.construction_source_item_accessible(public.profiles, public.characters, public.inventory_items) from public, anon, authenticated;

commit;
