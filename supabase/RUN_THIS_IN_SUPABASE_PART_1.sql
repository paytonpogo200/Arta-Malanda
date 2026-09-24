-- Arta Malanda Supabase runner - PART 1 OF 2
-- Run this file first. After it succeeds, run PART 2.

-- Arta Malanda Supabase SQL runner
-- For manual Supabase use: paste this whole file into the Supabase SQL Editor and run it.
-- It is designed to be rerunnable; create-or-replace functions update existing code cleanly.

-- Arta Malanda clean core schema v1
-- Fresh Supabase project/schema only. This rebuild uses username + password campaign accounts.
-- It intentionally does not depend on Supabase email auth or email verification.

create extension if not exists "pgcrypto";
create extension if not exists "citext";

do $$
begin
  create type public.user_role as enum ('player', 'dm');
exception when duplicate_object then null;
end $$;

do $$
begin
  create type public.character_kind as enum ('player', 'enemy', 'npc', 'tamed_beast');
exception when duplicate_object then null;
end $$;

do $$
begin
  create type public.item_rarity as enum ('Common', 'Uncommon', 'Rare', 'Epic', 'Legendary', 'Mythical');
exception when duplicate_object then null;
end $$;

do $$
begin
  create type public.battle_status as enum ('active', 'ended');
exception when duplicate_object then null;
end $$;

create table if not exists public.profiles (
  id uuid primary key default gen_random_uuid(),
  username citext not null unique,
  display_name text not null,
  password_hash text not null,
  role public.user_role not null default 'player',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_login_at timestamptz,
  constraint username_shape check (username ~* '^[a-z0-9_][a-z0-9_-]{2,23}$'),
  constraint display_name_not_blank check (length(trim(display_name)) > 0),
  constraint password_hash_not_blank check (length(password_hash) > 20)
);

create table if not exists public.dm_lock (
  id boolean primary key default true,
  profile_id uuid not null unique references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint only_one_dm check (id = true)
);

create table if not exists public.app_sessions (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  token_hash text not null unique,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '30 days',
  revoked_at timestamptz,
  constraint session_token_hash_not_blank check (length(token_hash) = 64)
);

create table if not exists public.class_templates (
  id uuid primary key default gen_random_uuid(),
  class_key text not null unique,
  name text not null,
  role text not null default '',
  armor text not null default '',
  identity text not null default '',
  base_hp int not null default 100 check (base_hp >= 0),
  base_mana int not null default 0 check (base_mana >= 0),
  base_magic_resist int not null default 0 check (base_magic_resist >= 0),
  inventory_slots int not null default 12 check (inventory_slots between 0 and 120),
  spell_slots int not null default 0 check (spell_slots >= 0),
  attributes jsonb not null default '{}'::jsonb check (jsonb_typeof(attributes) = 'object'),
  passives jsonb not null default '[]'::jsonb check (jsonb_typeof(passives) = 'array'),
  token_color text not null default '#9caf79',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.characters (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  kind public.character_kind not null default 'player',
  owner_user_id uuid references public.profiles(id) on delete set null,
  class_template_id uuid references public.class_templates(id) on delete set null,
  class_name text not null default 'Adventurer',
  level int not null default 1 check (level >= 1),
  max_hp int not null default 100 check (max_hp >= 0),
  current_hp int not null default 100 check (current_hp >= 0),
  max_mana int not null default 0 check (max_mana >= 0),
  current_mana int not null default 0 check (current_mana >= 0),
  magic_resist int not null default 0 check (magic_resist >= 0),
  inventory_slots int not null default 12 check (inventory_slots between 0 and 120),
  gift_inventory_open boolean not null default true,
  spell_slots int not null default 0 check (spell_slots >= 0),
  attributes jsonb not null default '{}'::jsonb check (jsonb_typeof(attributes) = 'object'),
  class_passives jsonb not null default '[]'::jsonb check (jsonb_typeof(class_passives) = 'array'),
  personal_passives text not null default '',
  token_color text not null default '#9caf79',
  location_city_key text,
  location_name text not null default 'Calostrynn',
  previous_owner_name text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.inventory_items (
  id uuid primary key default gen_random_uuid(),
  character_id uuid not null references public.characters(id) on delete cascade,
  parent_item_id uuid references public.inventory_items(id) on delete cascade,
  item_name text not null,
  display_name text,
  item_description text not null default '',
  item_type text not null default 'misc',
  rarity public.item_rarity not null default 'Common',
  quantity numeric(12,1) not null default 1 check (quantity > 0),
  slot_index int not null default 0,
  loadout_slot text,
  is_accessory boolean not null default false,
  is_storage boolean not null default false,
  storage_active boolean not null default false,
  storage_capacity int not null default 0 check (storage_capacity between 0 and 500),
  modifiers jsonb not null default '{}'::jsonb check (jsonb_typeof(modifiers) = 'object'),
  enchantment text,
  rune_name text,
  material text,
  enhancement_count int not null default 0 check (enhancement_count between 0 and 3),
  is_two_handed boolean not null default false,
  potion_strength text,
  potion_property text,
  potion_quality text,
  spell_book_form int not null default 1 check (spell_book_form in (1, 2)),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.inventory_items drop constraint if exists inventory_items_slot_index_check;
alter table public.inventory_items drop constraint if exists inventory_items_visible_or_storage_slot_check;
alter table public.inventory_items drop constraint if exists inventory_item_type_valid;
alter table public.inventory_items drop constraint if exists inventory_items_item_type_valid;
alter table public.inventory_items add column if not exists spell_book_form int not null default 1;
alter table public.inventory_items drop constraint if exists inventory_items_spell_book_form_check;
alter table public.inventory_items add constraint inventory_items_spell_book_form_check check (spell_book_form in (1, 2));
alter table public.inventory_items add constraint inventory_items_visible_or_storage_slot_check
  check (
    slot_index >= 0
    or (
      slot_index < 0
      and loadout_slot is null
    )
    or (
      is_storage = true
      and parent_item_id is null
      and loadout_slot is null
    )
  );

create unique index if not exists inventory_container_slot_unique
  on public.inventory_items (character_id, coalesce(parent_item_id, '00000000-0000-0000-0000-000000000000'::uuid), slot_index)
  where loadout_slot is null;

create unique index if not exists inventory_loadout_slot_unique
  on public.inventory_items (character_id, loadout_slot)
  where loadout_slot is not null;

drop index if exists inventory_storage_kind_unique;

alter table public.inventory_items
  alter column item_type type text using item_type::text,
  alter column quantity type numeric(12,1) using quantity::numeric;

alter table public.inventory_items
  add column if not exists display_name text,
  add column if not exists item_description text not null default '',
  add column if not exists is_accessory boolean not null default false,
  add column if not exists storage_active boolean not null default false,
  add column if not exists enchantment text,
  add column if not exists rune_name text,
  add column if not exists material text,
  add column if not exists enhancement_count int not null default 0 check (enhancement_count between 0 and 3),
  add column if not exists is_two_handed boolean not null default false,
  add column if not exists potion_strength text,
  add column if not exists potion_property text,
  add column if not exists potion_quality text,
  add column if not exists spell_book_form int not null default 1 check (spell_book_form in (1, 2));

create table if not exists public.battles (
  id uuid primary key default gen_random_uuid(),
  created_by uuid not null references public.profiles(id) on delete restrict,
  status public.battle_status not null default 'active',
  grid_width int not null default 24 check (grid_width between 5 and 100),
  grid_height int not null default 24 check (grid_height between 5 and 100),
  created_at timestamptz not null default now(),
  ended_at timestamptz
);

create table if not exists public.combatants (
  id uuid primary key default gen_random_uuid(),
  battle_id uuid not null references public.battles(id) on delete cascade,
  character_id uuid not null references public.characters(id) on delete cascade,
  x int not null default 0 check (x >= 0),
  y int not null default 0 check (y >= 0),
  current_hp int not null default 0 check (current_hp >= 0),
  current_mana int not null default 0 check (current_mana >= 0),
  initiative int check (initiative between 1 and 20),
  statuses jsonb not null default '[]'::jsonb check (jsonb_typeof(statuses) = 'array'),
  created_at timestamptz not null default now()
);

alter table public.combatants drop constraint if exists combatants_battle_id_character_id_key;

create table if not exists public.battle_terrain (
  id uuid primary key default gen_random_uuid(),
  battle_id uuid not null references public.battles(id) on delete cascade,
  x int not null check (x >= 0),
  y int not null check (y >= 0),
  terrain_type text not null default 'blocked',
  created_at timestamptz not null default now(),
  unique (battle_id, x, y)
);

create index if not exists profiles_username_idx on public.profiles(username);
create index if not exists app_sessions_profile_idx on public.app_sessions(profile_id);
create index if not exists app_sessions_valid_idx on public.app_sessions(token_hash, expires_at) where revoked_at is null;
create index if not exists characters_owner_idx on public.characters(owner_user_id);
create index if not exists inventory_character_idx on public.inventory_items(character_id);
create index if not exists inventory_parent_idx on public.inventory_items(parent_item_id);
create index if not exists combatants_battle_idx on public.combatants(battle_id);
create index if not exists battle_terrain_battle_idx on public.battle_terrain(battle_id);

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_touch_updated_at on public.profiles;
create trigger profiles_touch_updated_at
before update on public.profiles
for each row execute function public.touch_updated_at();

drop trigger if exists class_templates_touch_updated_at on public.class_templates;
create trigger class_templates_touch_updated_at
before update on public.class_templates
for each row execute function public.touch_updated_at();

drop trigger if exists characters_touch_updated_at on public.characters;
create trigger characters_touch_updated_at
before update on public.characters
for each row execute function public.touch_updated_at();

drop trigger if exists inventory_items_touch_updated_at on public.inventory_items;
create trigger inventory_items_touch_updated_at
before update on public.inventory_items
for each row execute function public.touch_updated_at();

create or replace function public.normalize_campaign_username(p_username text)
returns text
language sql
immutable
as $$
  select lower(trim(coalesce(p_username, '')));
$$;

create or replace function public.create_campaign_session(p_profile_id uuid)
returns table (
  session_token text,
  expires_at timestamptz
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_token text;
  v_expires_at timestamptz;
begin
  v_token := encode(gen_random_bytes(32), 'hex');
  v_expires_at := now() + interval '30 days';

  insert into public.app_sessions (profile_id, token_hash, expires_at)
  values (p_profile_id, encode(extensions.digest(v_token, 'sha256'), 'hex'), v_expires_at);

  return query select v_token, v_expires_at;
end;
$$;

create or replace function public.create_campaign_account(
  p_username text,
  p_display_name text,
  p_password text,
  p_claim_dm boolean default false
)
returns table (
  user_id uuid,
  username text,
  display_name text,
  role public.user_role,
  session_token text,
  expires_at timestamptz
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_username text;
  v_profile_id uuid;
  v_role public.user_role;
  v_session record;
begin
  v_username := public.normalize_campaign_username(p_username);

  if v_username !~ '^[a-z0-9_][a-z0-9_-]{2,23}$' then
    raise exception 'Username must be 3-24 characters using letters, numbers, underscores, or dashes.';
  end if;

  if length(coalesce(p_password, '')) < 6 then
    raise exception 'Password must be at least 6 characters.';
  end if;

  if p_claim_dm and exists (select 1 from public.dm_lock) then
    raise exception 'The Dungeon Master seat has already been claimed.';
  end if;

  v_role := case when p_claim_dm then 'dm'::public.user_role else 'player'::public.user_role end;

  insert into public.profiles (username, display_name, password_hash, role)
  values (
    v_username,
    coalesce(nullif(trim(p_display_name), ''), v_username),
    extensions.crypt(p_password, extensions.gen_salt('bf', 12)),
    v_role
  )
  returning id into v_profile_id;

  if v_role = 'dm' then
    insert into public.dm_lock (profile_id) values (v_profile_id);
  end if;

  select * into v_session from public.create_campaign_session(v_profile_id);

  return query
  select p.id, p.username::text, p.display_name, p.role, v_session.session_token, v_session.expires_at
  from public.profiles p
  where p.id = v_profile_id;
exception
  when unique_violation then
    raise exception 'That username is already taken.';
end;
$$;

create or replace function public.login_campaign_account(
  p_username text,
  p_password text
)
returns table (
  user_id uuid,
  username text,
  display_name text,
  role public.user_role,
  session_token text,
  expires_at timestamptz
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_session record;
begin
  select *
  into v_profile
  from public.profiles p
  where p.username = public.normalize_campaign_username(p_username)
  limit 1;

  if v_profile.id is null or v_profile.password_hash <> extensions.crypt(coalesce(p_password, ''), v_profile.password_hash) then
    raise exception 'Invalid username or password.';
  end if;

  update public.profiles
  set last_login_at = now()
  where id = v_profile.id;

  select * into v_session from public.create_campaign_session(v_profile.id);

  return query
  select p.id, p.username::text, p.display_name, p.role, v_session.session_token, v_session.expires_at
  from public.profiles p
  where p.id = v_profile.id;
end;
$$;

create or replace function public.get_campaign_session(p_session_token text)
returns table (
  user_id uuid,
  username text,
  display_name text,
  role public.user_role
)
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  return query
  select p.id, p.username::text, p.display_name, p.role
  from public.app_sessions s
  join public.profiles p on p.id = s.profile_id
  where s.token_hash = encode(extensions.digest(coalesce(p_session_token, ''), 'sha256'), 'hex')
    and s.revoked_at is null
    and s.expires_at > now()
  limit 1;
end;
$$;

create or replace function public.logout_campaign_session(p_session_token text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  update public.app_sessions
  set revoked_at = now()
  where token_hash = encode(extensions.digest(coalesce(p_session_token, ''), 'sha256'), 'hex')
    and revoked_at is null;

  return true;
end;
$$;

alter table public.profiles enable row level security;
alter table public.dm_lock enable row level security;
alter table public.app_sessions enable row level security;
alter table public.class_templates enable row level security;
alter table public.characters enable row level security;
alter table public.inventory_items enable row level security;
alter table public.battles enable row level security;
alter table public.combatants enable row level security;
alter table public.battle_terrain enable row level security;

revoke all on table public.profiles from anon, authenticated;
revoke all on table public.dm_lock from anon, authenticated;
revoke all on table public.app_sessions from anon, authenticated;
revoke all on table public.class_templates from anon, authenticated;
revoke all on table public.characters from anon, authenticated;
revoke all on table public.inventory_items from anon, authenticated;
revoke all on table public.battles from anon, authenticated;
revoke all on table public.combatants from anon, authenticated;
revoke all on table public.battle_terrain from anon, authenticated;

grant usage on schema public to anon, authenticated;
grant execute on function public.create_campaign_account(text, text, text, boolean) to anon, authenticated;
grant execute on function public.login_campaign_account(text, text) to anon, authenticated;
grant execute on function public.get_campaign_session(text) to anon, authenticated;
grant execute on function public.logout_campaign_session(text) to anon, authenticated;


-- ============================================================
-- ============================================================

-- Character ledger foundation

alter table public.characters
  add column if not exists class_key text;

alter table public.class_templates
  add column if not exists base_magic_resist int not null default 0 check (base_magic_resist >= 0);

alter table public.characters
  add column if not exists magic_resist int not null default 0 check (magic_resist >= 0);

alter table public.characters
  add column if not exists location_city_key text;

update public.characters
set class_key = lower(regexp_replace(class_name, '[^a-zA-Z0-9]+', '-', 'g'))
where class_key is null;

alter table public.characters
  alter column class_key set default 'adventurer';

alter table public.characters
  add column if not exists previous_owner_name text not null default '';

alter table public.characters
  add column if not exists gift_inventory_open boolean not null default true;

create index if not exists characters_class_key_idx on public.characters(class_key);
create index if not exists characters_location_city_key_idx on public.characters(location_city_key);

create or replace function public.profile_from_campaign_session(p_session_token text)
returns public.profiles
language sql
security definer
stable
set search_path = public, extensions
as $$
  select p.*
  from public.app_sessions s
  join public.profiles p on p.id = s.profile_id
  where s.token_hash = encode(extensions.digest(coalesce(p_session_token, ''), 'sha256'), 'hex')
    and s.revoked_at is null
    and s.expires_at > now()
  limit 1
$$;

create or replace function public.character_record_to_json(p_character public.characters)
returns jsonb
language sql
stable
set search_path = public
as $$
  select jsonb_build_object(
    'id', p_character.id,
    'name', p_character.name,
    'kind', p_character.kind,
    'ownerUserId', p_character.owner_user_id,
    'classKey', coalesce(p_character.class_key, 'adventurer'),
    'className', p_character.class_name,
    'level', p_character.level,
    'maxHp', p_character.max_hp,
    'currentHp', p_character.current_hp,
    'maxMana', p_character.max_mana,
    'currentMana', p_character.current_mana,
    'magicResist', p_character.magic_resist,
    'inventorySlots', p_character.inventory_slots,
    'giftInventoryOpen', p_character.gift_inventory_open,
    'spellSlots', p_character.spell_slots,
    'attributes', p_character.attributes,
    'classPassives', p_character.class_passives,
    'personalPassives', p_character.personal_passives,
    'tokenColor', p_character.token_color,
    'locationCityKey', p_character.location_city_key,
    'locationName', p_character.location_name,
    'previousOwnerName', nullif(p_character.previous_owner_name, '')
  )
$$;



grant execute on function public.profile_from_campaign_session(text) to anon, authenticated;
grant execute on function public.character_record_to_json(public.characters) to anon, authenticated;


-- ============================================================
-- ============================================================

-- Flexible bestiary categories and full stat storage.

create table if not exists public.bestiary_entities (
  id uuid primary key default gen_random_uuid(),
  entity_key text not null unique,
  name text not null,
  category text not null default 'uncategorized',
  habitat text not null default '',
  temperament text not null default '',
  wild_score int not null default 0 check (wild_score >= 0),
  hp int not null default 0 check (hp >= 0),
  mana int not null default 0 check (mana >= 0),
  summary text not null default '',
  details text not null default '',
  stats jsonb not null default '{}'::jsonb check (jsonb_typeof(stats) = 'object'),
  token_color text,
  token_color_secondary text,
  is_unlocked boolean not null default false,
  display_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.bestiary_entities
drop constraint if exists bestiary_entities_category_check;

alter table public.bestiary_entities
add column if not exists stats jsonb not null default '{}'::jsonb;

alter table public.bestiary_entities
add column if not exists token_color text,
add column if not exists token_color_secondary text;

alter table public.bestiary_entities
drop constraint if exists bestiary_entities_token_color_check;

alter table public.bestiary_entities
add constraint bestiary_entities_token_color_check check (
  (token_color is null or token_color ~ '^#[0-9A-Fa-f]{6}$')
  and (token_color_secondary is null or token_color_secondary ~ '^#[0-9A-Fa-f]{6}$')
);

create index if not exists bestiary_entities_category_idx on public.bestiary_entities(category);
create index if not exists bestiary_entities_unlocked_idx on public.bestiary_entities(is_unlocked);

alter table public.bestiary_entities enable row level security;
revoke all on public.bestiary_entities from anon, authenticated;

drop trigger if exists bestiary_entities_touch_updated_at on public.bestiary_entities;
create trigger bestiary_entities_touch_updated_at
before update on public.bestiary_entities
for each row execute function public.touch_updated_at();

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
    'tokenColor', coalesce(p_entity.token_color, ''),
    'tokenColorSecondary', p_entity.token_color_secondary,
    'unlocked', p_entity.is_unlocked,
    'order', p_entity.display_order
  )
$$;

create or replace function public.bestiary_stat_number(p_stats jsonb, p_keys text[])
returns int
language plpgsql
immutable
set search_path = public, extensions
as $$
declare
  v_normalized_keys text[];
  v_key text;
  v_value text;
  v_number text;
begin
  select array_agg(lower(regexp_replace(entry, '[^a-z0-9]+', '', 'g')))
  into v_normalized_keys
  from unnest(coalesce(p_keys, array[]::text[])) as requested(entry);

  if v_normalized_keys is null or array_length(v_normalized_keys, 1) is null then
    return 0;
  end if;

  for v_key, v_value in select key, value from jsonb_each_text(coalesce(p_stats, '{}'::jsonb))
  loop
    if lower(regexp_replace(v_key, '[^a-z0-9]+', '', 'g')) = any(v_normalized_keys) then
      v_number := substring(coalesce(v_value, '') from '-?[0-9]+[.]?[0-9]*');
      if v_number is not null then
        return round(v_number::numeric)::int;
      end if;
    end if;
  end loop;

  return 0;
end;
$$;

create or replace function public.bestiary_token_color(p_entity public.bestiary_entities)
returns text
language plpgsql
stable
set search_path = public
as $$
declare
  v_color text := lower(trim(coalesce(p_entity.stats->>'Color', p_entity.stats->>'color', '')));
begin
  if p_entity.token_color is not null and p_entity.token_color_secondary is not null then
    return format('linear-gradient(135deg, %s 0%%, %s 100%%)', p_entity.token_color, p_entity.token_color_secondary);
  elsif p_entity.token_color is not null then
    return p_entity.token_color;
  end if;

  if p_entity.category = 'bosses' then
    if v_color like '%turquoise%' and v_color like '%lime%' then
      return 'linear-gradient(135deg, #18d3c5 0%, #55f2e8 32%, #a3e635 68%, #f4ff8f 100%)';
    elsif v_color like '%turquoise%' then
      return 'linear-gradient(135deg, #0f766e 0%, #22d3ee 50%, #99f6e4 100%)';
    elsif v_color like '%lime%' then
      return 'linear-gradient(135deg, #3f6212 0%, #84cc16 45%, #ecfccb 100%)';
    end if;
    return 'linear-gradient(135deg, #f59e0b 0%, #dc2626 45%, #7c3aed 100%)';
  end if;

  return case p_entity.category
    when 'common-wildlife' then '#6f8f55'
    when 'magical-wildlife' then '#5c7fd8'
    when 'monsters' then '#9f4f46'
    else '#7f514d'
  end;
end;
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
  v_category_key text;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;
  if v_profile.role <> 'dm'::public.user_role then raise exception 'Only the Dungeon Master can update bestiary categories.'; end if;
  v_category_key := coalesce(nullif(trim(p_category_key), ''), 'unsorted');

  insert into public.bestiary_categories (category_key, name, display_order)
  values (v_category_key, initcap(replace(v_category_key, '-', ' ')), 1000)
  on conflict (category_key) do nothing;

  update public.bestiary_categories
  set
    name = case when v_patch ? 'name' then coalesce(nullif(trim(v_patch->>'name'), ''), name) else name end,
    is_hidden = case when v_patch ? 'hidden' then (v_patch->>'hidden')::boolean else is_hidden end,
    display_order = case when v_patch ? 'order' then (v_patch->>'order')::int else display_order end
  where category_key = v_category_key;

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
  v_category_key text;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;
  if v_profile.role <> 'dm'::public.user_role then raise exception 'Only the Dungeon Master can update the bestiary.'; end if;

  if v_patch ? 'category' then
    v_category_key := coalesce(nullif(trim(v_patch->>'category'), ''), 'uncategorized');
    insert into public.bestiary_categories (category_key, name, display_order)
    values (v_category_key, coalesce(nullif(trim(v_patch->>'categoryName'), ''), initcap(replace(v_category_key, '-', ' '))), 1000)
    on conflict (category_key) do nothing;
  end if;

  update public.bestiary_entities
  set
    is_unlocked = case when v_patch ? 'unlocked' then (v_patch->>'unlocked')::boolean else is_unlocked end,
    name = case when v_patch ? 'name' then coalesce(nullif(trim(v_patch->>'name'), ''), name) else name end,
    category = case when v_patch ? 'category' then v_category_key else category end,
    habitat = case when v_patch ? 'habitat' then coalesce(v_patch->>'habitat', '') else habitat end,
    temperament = case when v_patch ? 'temperament' then coalesce(v_patch->>'temperament', '') else temperament end,
    wild_score = case when v_patch ? 'wildScore' then greatest(0, (v_patch->>'wildScore')::int) else wild_score end,
    hp = case when v_patch ? 'hp' then greatest(0, (v_patch->>'hp')::int) else hp end,
    mana = case when v_patch ? 'mana' then greatest(0, (v_patch->>'mana')::int) else mana end,
    summary = case when v_patch ? 'summary' then coalesce(v_patch->>'summary', '') else summary end,
    details = case when v_patch ? 'details' then coalesce(v_patch->>'details', '') else details end,
    stats = case when v_patch ? 'stats' then coalesce(v_patch->'stats', '{}'::jsonb) else stats end,
    token_color = case when v_patch ? 'tokenColor' then nullif(trim(v_patch->>'tokenColor'), '') else token_color end,
    token_color_secondary = case when v_patch ? 'tokenColorSecondary' then nullif(trim(v_patch->>'tokenColorSecondary'), '') else token_color_secondary end,
    display_order = case when v_patch ? 'order' then (v_patch->>'order')::int else display_order end
  where id = p_entity_id;

  return public.get_bestiary(p_session_token);
end;
$$;

create or replace function public.create_bestiary_entity(
  p_session_token text,
  p_entry jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_entry jsonb := coalesce(p_entry, '{}'::jsonb);
  v_name text;
  v_category_key text;
  v_category_name text;
  v_entity_key text;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;
  if v_profile.role <> 'dm'::public.user_role then raise exception 'Only the Dungeon Master can create bestiary entries.'; end if;

  v_name := nullif(trim(v_entry->>'name'), '');
  if v_name is null then raise exception 'Give the beast a name.'; end if;

  v_category_key := nullif(trim(v_entry->>'category'), '');
  if v_category_key is not null and exists (select 1 from public.bestiary_categories where category_key = v_category_key) then
    select name into v_category_name from public.bestiary_categories where category_key = v_category_key;
  else
    v_category_name := coalesce(nullif(trim(v_entry->>'categoryName'), ''), 'Uncategorized');
    v_category_key := lower(regexp_replace(v_category_name, '[^a-zA-Z0-9]+', '-', 'g'));
    v_category_key := trim(both '-' from v_category_key);
    if v_category_key = '' then v_category_key := 'uncategorized'; end if;
  end if;

  insert into public.bestiary_categories (category_key, name, display_order)
  values (v_category_key, v_category_name, coalesce((select max(display_order) + 10 from public.bestiary_categories), 10))
  on conflict (category_key) do nothing;

  v_entity_key := lower(regexp_replace(v_name, '[^a-zA-Z0-9]+', '-', 'g'));
  v_entity_key := trim(both '-' from v_entity_key) || '-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 8);

  insert into public.bestiary_entities (
    entity_key, name, category, habitat, temperament, wild_score, hp, mana,
    summary, details, stats, token_color, token_color_secondary, is_unlocked, display_order
  )
  values (
    v_entity_key,
    v_name,
    v_category_key,
    coalesce(v_entry->>'habitat', ''),
    coalesce(v_entry->>'temperament', ''),
    greatest(0, coalesce(nullif(v_entry->>'wildScore', '')::int, 0)),
    greatest(1, coalesce(nullif(v_entry->>'hp', '')::int, 1)),
    greatest(0, coalesce(nullif(v_entry->>'mana', '')::int, 0)),
    coalesce(v_entry->>'summary', ''),
    coalesce(v_entry->>'details', ''),
    case when jsonb_typeof(v_entry->'stats') = 'object' then v_entry->'stats' else '{}'::jsonb end,
    coalesce(nullif(trim(v_entry->>'tokenColor'), ''), '#7f514d'),
    nullif(trim(v_entry->>'tokenColorSecondary'), ''),
    coalesce((v_entry->>'unlocked')::boolean, true),
    coalesce((select max(display_order) + 10 from public.bestiary_entities where category = v_category_key), 10)
  );

  return public.get_bestiary(p_session_token);
end;
$$;


grant execute on function public.bestiary_category_record_to_json(public.bestiary_categories) to anon, authenticated;
grant execute on function public.bestiary_entity_record_to_json(public.bestiary_entities) to anon, authenticated;
grant execute on function public.bestiary_stat_number(jsonb, text[]) to anon, authenticated;
grant execute on function public.bestiary_token_color(public.bestiary_entities) to anon, authenticated;
grant execute on function public.get_bestiary(text) to anon, authenticated;
grant execute on function public.update_bestiary_category(text, text, jsonb) to anon, authenticated;
grant execute on function public.update_bestiary_entity(text, uuid, jsonb) to anon, authenticated;
grant execute on function public.create_bestiary_entity(text, jsonb) to anon, authenticated;


-- ============================================================
-- ============================================================

-- Excel workbook import endpoint for bestiary updates.

create or replace function public.import_bestiary_workbook(
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
  v_entity_key text;
  v_entity_name text;
  v_imported_category_keys text[] := array[]::text[];
  v_imported_entity_keys text[] := array[]::text[];
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;
  if v_profile.role <> 'dm'::public.user_role then raise exception 'Only the Dungeon Master can import the bestiary.'; end if;

  for v_category in select value from jsonb_array_elements(coalesce(p_categories, '[]'::jsonb))
  loop
    v_category_key := coalesce(nullif(v_category->>'key', ''), 'unsorted');
    v_imported_category_keys := array_append(v_imported_category_keys, v_category_key);

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
    v_entity_name := coalesce(nullif(v_entity->>'name', ''), 'Unknown Entity');
    v_entity_key := coalesce(nullif(v_entity->>'key', ''), lower(regexp_replace(v_category_key || '-' || v_entity_name, '[^a-z0-9]+', '-', 'g')));
    v_imported_category_keys := array_append(v_imported_category_keys, v_category_key);
    v_imported_entity_keys := array_append(v_imported_entity_keys, v_entity_key);

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
      v_entity_key,
      v_entity_name,
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
        summary = coalesce(nullif(excluded.summary, ''), public.bestiary_entities.summary),
        details = coalesce(nullif(excluded.details, ''), public.bestiary_entities.details),
        stats = excluded.stats,
        display_order = excluded.display_order;
  end loop;

  delete from public.bestiary_entities
  where entity_key <> all(coalesce(v_imported_entity_keys, array[]::text[]));

  delete from public.bestiary_categories
  where category_key <> all(coalesce(v_imported_category_keys, array[]::text[]));

  return public.get_bestiary(p_session_token);
end;
$$;

drop function if exists public.import_bestiary_markdown(text, jsonb, jsonb);
drop function if exists public.is_retired_bestiary_category(text);
drop function if exists public.purge_retired_bestiary_categories();
grant execute on function public.import_bestiary_workbook(text, jsonb, jsonb) to anon, authenticated;

-- Seed/refresh bestiary rows that are expected to exist after running this SQL directly.
-- The workbook importer can still replace the whole bestiary, but the SQL runner itself
-- must not leave new Expedition Threats absent from the app.
insert into public.bestiary_categories (category_key, name, is_hidden, display_order)
values
  ('expedition-threats', 'Expedition Threats', false, 850),
  ('bosses', 'Bosses', false, 900)
on conflict (category_key) do update
set name = excluded.name,
    is_hidden = excluded.is_hidden,
    display_order = excluded.display_order;

delete from public.bestiary_entities
where entity_key in ('bosses-seraphel', 'bosses-healing-support-1', 'bosses-healing-support-2');

delete from public.bestiary_entities
where category = 'expedition-threats'
  and entity_key not in (
    'expedition-threats-ruin-scavenger',
    'expedition-threats-roadside-cutthroat',
    'expedition-threats-contract-blade',
    'expedition-threats-banished-knight',
    'expedition-threats-banished-warlock',
    'expedition-threats-known-mercinary',
    'expedition-threats-fallen-sage',
    'expedition-threats-relic-hunter',
    'expedition-threats-the-exiled-black-knight'
  );

insert into public.bestiary_entities (
  entity_key,
  name,
  category,
  hp,
  mana,
  summary,
  details,
  stats,
  is_unlocked,
  display_order
)
values
  (
    'expedition-threats-ruin-scavenger',
    'Ruin Scavenger',
    'expedition-threats',
    75,
    0,
    '',
    '',
    jsonb_build_object('Damage', '1d6', 'Strength', '+1', 'Vitality', '+2', 'Magic Resistance', '7', 'Armor / Hide', '7'),
    false,
    850
  ),
  (
    'expedition-threats-roadside-cutthroat',
    'Roadside Cutthroat',
    'expedition-threats',
    90,
    0,
    'Can go invisible once per combat',
    '',
    jsonb_build_object('Damage', '1d6', 'Strength', '+2', 'Vitality', '+1', 'Magic Resistance', '7', 'Armor / Hide', '10', 'Special Effects', 'Can go invisible once per combat'),
    false,
    860
  ),
  (
    'expedition-threats-contract-blade',
    'Contract Blade',
    'expedition-threats',
    110,
    0,
    '',
    '',
    jsonb_build_object('Damage', '3d6', 'Strength', '+2', 'Vitality', '+2', 'Magic Resistance', '7', 'Armor / Hide', '10'),
    false,
    870
  ),
  (
    'expedition-threats-banished-knight',
    'Banished Knight',
    'expedition-threats',
    125,
    0,
    'Knight passive',
    '',
    jsonb_build_object('Damage', '2d6', 'Strength', '+1', 'Vitality', '+1', 'Magic Resistance', '7', 'Armor / Hide', '10', 'Special Effects', 'Knight passive'),
    false,
    880
  ),
  (
    'expedition-threats-banished-warlock',
    'Banished Warlock',
    'expedition-threats',
    80,
    150,
    '',
    '',
    jsonb_build_object('Damage', '2d6', 'Strength', '-3', 'Vitality', '-4', 'Magic Resistance', '7', 'Armor / Hide', '7', 'Mana Pool', '150', 'Spells', 'Judas, Fireball, Cripple', 'Role', 'Mage'),
    false,
    890
  ),
  (
    'expedition-threats-known-mercinary',
    'Known Mercinary',
    'expedition-threats',
    90,
    0,
    'Has Swiftness',
    '',
    jsonb_build_object('Damage', '2d6', 'Strength', '+1', 'Vitality', '+1', 'Magic Resistance', '7', 'Armor / Hide', '10', 'Special Effects', 'Has Swiftness'),
    false,
    900
  ),
  (
    'expedition-threats-fallen-sage',
    'Fallen Sage',
    'expedition-threats',
    70,
    100,
    '',
    '',
    jsonb_build_object('Damage', '2d6', 'Strength', '-2', 'Vitality', '-2', 'Magic Resistance', '9', 'Armor / Hide', '10', 'Mana Pool', '100', 'Spells', 'Greater Mend, Retaliation, Insurance', 'Role', 'Sage'),
    false,
    910
  ),
  (
    'expedition-threats-relic-hunter',
    'Relic Hunter',
    'expedition-threats',
    150,
    0,
    'Has a random accessory of varying power',
    '',
    jsonb_build_object('Damage', '3d6', 'Strength', '+2', 'Vitality', '+2', 'Magic Resistance', '5', 'Armor / Hide', '13', 'Special Effects', 'Has a random accessory of varying power'),
    false,
    920
  ),
  (
    'expedition-threats-the-exiled-black-knight',
    'The Exiled Black Knight',
    'expedition-threats',
    250,
    0,
    'Wields the Shadows Accomplice, and 2 invis potions',
    '',
    jsonb_build_object('Damage', '25', 'Strength', '+4', 'Vitality', '+4', 'Magic Resistance', '8', 'Armor / Hide', '13', 'Special Effects', 'Wields the Shadows Accomplice, and 2 invis potions'),
    false,
    930
  ),
  (
    'boss-seraphel',
    'Seraphel',
    'bosses',
    700,
    100,
    'Main boss encounter. Battlefield chip uses the Turquoise/Lime Green boss gradient.',
    'Boss stats imported from Bestiary.md.',
    jsonb_build_object('Damage', '35', 'Strength', '+5', 'Vitality', '+6', 'Magic Resistance', '14', 'Armor / Hide', '10', 'Color', 'Turquoise/Lime green gradient'),
    true,
    901
  ),
  (
    'boss-healing-support-1',
    'Healing Support 1',
    'bosses',
    180,
    90,
    'Boss support encounter. Battlefield chip uses the Turquoise boss gradient.',
    'Boss support stats imported from Bestiary.md.',
    jsonb_build_object('Damage', '18', 'Strength', '+1', 'Vitality', '+3', 'Magic Resistance', '8', 'Armor / Hide', '7', 'Color', 'Turquoise'),
    true,
    902
  ),
  (
    'boss-healing-support-2',
    'Healing Support 2',
    'bosses',
    160,
    100,
    'Boss support encounter. Battlefield chip uses the Lime Green boss gradient.',
    'Boss support stats imported from Bestiary.md.',
    jsonb_build_object('Damage', '16', 'Strength', '0', 'Vitality', '+2', 'Magic Resistance', '9', 'Armor / Hide', '7', 'Color', 'Lime Green'),
    true,
    903
  )
on conflict (entity_key) do update
set name = excluded.name,
    category = excluded.category,
    hp = excluded.hp,
    mana = excluded.mana,
    summary = excluded.summary,
    details = excluded.details,
    stats = excluded.stats,
    is_unlocked = excluded.is_unlocked,
    display_order = excluded.display_order,
    updated_at = now();


-- ============================================================
-- ============================================================

-- Dashboard shell state
-- Gives the app shell a lightweight, session-safe way to detect combat lock and notification count.



-- ============================================================
-- ============================================================

-- Character ledger expansion
-- Seeds class templates, returns class assets with the ledger, and lets the DM reassign/update characters cleanly.

insert into public.class_templates (
  class_key,
  name,
  role,
  armor,
  identity,
  base_hp,
  base_mana,
  base_magic_resist,
  inventory_slots,
  spell_slots,
  attributes,
  passives,
  token_color
)
values
  ('alchemist', 'Alchemist', 'Support · Decent sustain', 'Light armor', $am$Alchemists are intelligent and resourceful, knowing much of the land, yet always yearn for more knowledge. They are cunning and rumor has it, that an order of alchemists pass secrets of the world around to one another. Perhaps its just fables and exaggerations, but then again I've never really seen them ever at a brewery.$am$, 110, 50, 5, 16, 2, '{"strength":-1,"accuracy":0,"intelligence":1,"vitality":-1,"recovery":1,"mana_regen":0,"charisma":0,"wisdom_cunning":3,"perception":0,"alchemy":5,"stealth":0,"agility":0}'::jsonb, jsonb_build_array('Once per combat, an Alchemist can use or make a potion or alchemical item without spending their main action or movement', 'Has unlimited flasks and Arcane Nector (Base ingredient in potions) as long as they have a house or residence'), '#4d8f83'),
  ('apothecary', 'Apothecary', 'Support · Great sustain', 'Medium armor', $am$Apothecaries are incredibly durable mages, known for their legendary support in combat and on the battlefield. They are extremely formidable as mages, and sometimes, even in the frontline. Many a great apothecary was known for their priceless support in battle. But a few, are some of the most feared names Arda Malanda has heard.$am$, 130, 90, 8, 15, 5, '{"strength":-3,"accuracy":-1,"intelligence":0,"vitality":1,"recovery":2,"mana_regen":2,"charisma":0,"wisdom_cunning":2,"perception":0,"alchemy":2,"stealth":-2,"agility":-1}'::jsonb, jsonb_build_array('Can heal an ally for 10 hp in place of a movement'), '#5579a8'),
  ('apprentice', 'Apprentice', 'Hybrid · Decent sustain', 'Medium armor', $am$Apprentices are learners, and are naturally talented mages, but enjoy the freedom of some extra sustainability, as opposed to utility. Their resourcefulness is often a great contribution to many successful expeditions.$am$, 100, 75, 5, 16, 5, '{"strength":0,"accuracy":0,"intelligence":1,"vitality":-1,"recovery":0,"mana_regen":1,"charisma":0,"wisdom_cunning":1,"perception":0,"alchemy":1,"stealth":0,"agility":1}'::jsonb, jsonb_build_array('When paired with a mage, has +1 Intelligence. When paired with a knight, has +1 Strength. When paired with a ranger, has +1 Accuracy. These can stack.'), '#8a6da1'),
  ('armor-clad', 'Armor-clad', 'Defense · Great sustain', 'Heavy armor', $am$Armor-clad warriors are amazing front liners. They are incredibly hard to take down and provide an amazing presence on the battlefield. What they lack in quickness, they make up for in annoying defensive utility. They are often seen as scary or mad due to their nature on the battlefield, or at least thats what they say. Hasn't been one in ages.$am$, 165, 50, 6, 10, 1, '{"strength":2,"accuracy":0,"intelligence":-3,"vitality":3,"recovery":0,"mana_regen":0,"charisma":-1,"wisdom_cunning":-2,"perception":-1,"alchemy":1,"stealth":-3,"agility":-3}'::jsonb, jsonb_build_array($am$Has the ability _Distribution_, which will direct 50% of a target's damage to yourself$am$, 'Does not pay armor labor, only materials. Armor-clad cannot receive extra defensive bonuses from shields'), '#9a6e52'),
  ('beastmaster', 'Beastmaster', 'Hybrid · Poor sustain', 'Light armor', $am$Beastmasters are incredibly rare, but invaluable as an asset. Many have never been much on the battlefield themselves, but their way with the animals and beasts of the land is marvelling. They say a couple hundred years ago, an elvish beastmaster once tamed a dragon, and one must wonder if it was the child's story we all were told, or if there is even a smidgen of truth hidden within.$am$, 90, 50, 5, 20, 1, '{"strength":-3,"accuracy":1,"intelligence":0,"vitality":0,"recovery":1,"mana_regen":0,"charisma":3,"wisdom_cunning":2,"perception":2,"alchemy":0,"stealth":0,"agility":1}'::jsonb, jsonb_build_array($am$Has the Spell "Tame" (doesn't take a spell slot), which allows for a tame roll, which is a d6 plus charisma plus buffs vs the animal's wild score. If the resulting number is positive, the animal/beast is tamed, but health isn't restored. If the resulting number is zero, heads on a coin flip tames. Tame can only be attempted on creatures below 50% health. Creatures below 10% health yield a +3 bonus to a tame roll. Any below 5% yields a +5 to a tame roll.$am$, 'All Attacks from a Beast master will only ever bring an animal or beast to 1hp, never killing it', 'Will always crit against animals and beasts', 'Can bring 20 wild score worth of beasts per mission. Each beast operates independently of the beastmaster with its own initiative and turns.'), '#77875a'),
  ('blacksmith', 'Blacksmith', 'Support · Decent sustain', 'Medium armor', $am$Blacksmiths are highly valued assets in the realm, in all kingdoms. Their utility and knack for anything with their hands is to be much admired. There are many kinds of blacksmiths, but the great runesmith Argon "The Hammer" Tyborgarian has been showing the realm just how versatile runes and magic can be in tools and armor, forming a new study within the craft as we speak.$am$, 125, 50, 5, 18, 3, '{"strength":2,"accuracy":0,"intelligence":0,"vitality":1,"recovery":0,"mana_regen":0,"charisma":2,"wisdom_cunning":1,"perception":0,"alchemy":1,"stealth":-1,"agility":-1}'::jsonb, jsonb_build_array($am$Doesn't need to pay for smithing labor, only materials$am$, 'Has the ability to create weapons away from a forge with a properly made fire', 'Once per combat, enhance a melee weapon of choice with +1 strength. Ends after combat/scene'), '#b28b45'),
  ('knight', 'Knight', 'Attack · Decent sustain', 'Medium armor', $am$Knights are talented swordsmen and combat experts, and pair well with horses. Well liked knights have been known to have been shown favor even when purchasing one and have a larger political sway. They are your classic all around attack type with a nice amount of sustainability.$am$, 125, 25, 5, 14, 2, '{"strength":1,"accuracy":1,"intelligence":-1,"vitality":1,"recovery":0,"mana_regen":-2,"charisma":2,"wisdom_cunning":1,"perception":0,"alchemy":-1,"stealth":0,"agility":0}'::jsonb, jsonb_build_array('+1 Strength while on a Horse.', 'Every hit received, roll for a parry, 18-20 will grant a 100% reduction of damage. 15-17 will grant a 50% (rounding up) reduction', 'Rally the troops: Once per combat, choose a target for the entire party to all attack at once; as long as this attack hits, all others will as well.'), '#a05e5a'),
  ('mage', 'Mage', 'Attack · Poor sustain', 'Light armor', $am$Mages are the hot shots of Calostrynn, their pride and joy. They pack a punch, much like the rangers, but what the rangers have in range and recon, the mages more than make up for in versatility. With enough knowledge, there is nearly a spell for almost all occasions.$am$, 70, 100, 7, 10, 10, '{"strength":-3,"accuracy":0,"intelligence":3,"vitality":-3,"recovery":0,"mana_regen":1,"charisma":1,"wisdom_cunning":2,"perception":0,"alchemy":0,"stealth":0,"agility":0}'::jsonb, jsonb_build_array('Regain 10 Mana for every enemy killed with a spell'), '#567a7f'),
  ('mendrunner', 'Mendrunner', 'Hybrid · Poor sustain', 'Medium armor', $am$Mendrunners are a unique lot. They specialize in botany and natural remedies, resenting magic and its simple lifestyle. They are incredibly nimble and many have once been or sometimes become rogues. Little is known about them though due to their lack of number.$am$, 85, 0, 4, 20, 0, '{"strength":-1,"accuracy":1,"intelligence":-5,"vitality":0,"recovery":3,"mana_regen":0,"charisma":-3,"wisdom_cunning":3,"perception":3,"alchemy":4,"stealth":1,"agility":3}'::jsonb, jsonb_build_array('Heal an ally for 2d6 + Recovery + Alchemy and remove a debuff or negative effect. Cooldown of 1 turn.', 'Is immune to poison and Illness'), '#6b8f68'),
  ('the-muscle', 'The Muscle', 'Defense · Great sustain', 'Medium armor', $am$The Muscle is notorious for their large frame and small brains. They specialize on sustain and being...well, the muscle of a group. When paired with a sage or apothecary, these hulkish freaks of nature are unstoppable.$am$, 150, 40, 4, 10, 1, '{"strength":3,"accuracy":-2,"intelligence":-3,"vitality":1,"recovery":2,"mana_regen":0,"charisma":-2,"wisdom_cunning":-3,"perception":-1,"alchemy":-2,"stealth":-2,"agility":-2}'::jsonb, jsonb_build_array('When The Muscle kills an enemy, gain 1 d6 for ensuing damage rolls. Resets after each combat/scene ends. Max of 5 d6'), '#9f6540'),
  ('ranger', 'Ranger', 'Attack · Poor sustain', 'Light armor', $am$Ranged class is known for being a backline attack type. They can pack a punch and provide great support from range, and can even act as very nice recon, but are very vulnerable alone in most situations. A master archer especially has been the sole reason for many conclusions to wars, a much under appreciated craft, given their grand role in previous wars.$am$, 90, 50, 7, 15, 1, '{"strength":-2,"accuracy":2,"intelligence":1,"vitality":-2,"recovery":0,"mana_regen":0,"charisma":0,"wisdom_cunning":2,"perception":2,"alchemy":0,"stealth":1,"agility":1}'::jsonb, jsonb_build_array('Can tame birds', '3 times per combat, shoot 3 arrows in one draw. Must roll for accuracy for each arrow.', 'Allowed to buy and craft element or effect-tipped arrows'), '#7c8a49'),
  ('rogue', 'Rogue', 'Attack · Poor sustain', 'Light armor', $am$Rogues are shifty and cunning. They might not be strong in groups but are amazing duelists and specialize in catching enemies off guard. Their reputation precedes them, and not always in the best of ways, but they are always more than nice outside and within the castle walls.$am$, 90, 50, 4, 16, 3, '{"strength":-1,"accuracy":0,"intelligence":0,"vitality":-1,"recovery":0,"mana_regen":0,"charisma":-3,"wisdom_cunning":3,"perception":3,"alchemy":1,"stealth":3,"agility":2}'::jsonb, jsonb_build_array('Has the ability *Backstab* which when attacking from behind, from stealth, or against a pinned or otherwise defenseless enemy, Rogue deals double damage.', 'May use Agility instead of Strength for any attack that procs *Backstab*'), '#6b617e'),
  ('sage', 'Sage', 'Support · Poor sustain', 'Medium armor', $am$Sages are loved and appreciated by all. In a world of war and selfish interest, they walk a path of selflessness, aiding others in their prosperity and support on the battlefield. Those who have mastered their craft are known to have boundless mana and spell casting.$am$, 70, 100, 9, 12, 5, '{"strength":-2,"accuracy":-2,"intelligence":-5,"vitality":-2,"recovery":3,"mana_regen":2,"charisma":2,"wisdom_cunning":4,"perception":0,"alchemy":0,"stealth":0,"agility":2}'::jsonb, jsonb_build_array('Healing and enhancement spells use _Recovery_ instead of Intelligence when using magic rolls', 'Heals also heal an additional ally for half (rounding up) of the heals amount. Can be used on the same target'), '#7581a0'),
  ('talismanist', 'Talismanist', 'Attack · Decent sustain', 'Medium armor', $am$Talismanists are experts at using weapons and armor forced with runes, and almost exclusively use weapons that hold spells or magical properties within them. This new class of warriors only recently came about, given the studies and smithsmanship from Argon "The Hammer" Tyborgarian.$am$, 125, 100, 7, 10, 0, '{"strength":1,"accuracy":1,"intelligence":1,"vitality":1,"recovery":0,"mana_regen":0,"charisma":0,"wisdom_cunning":1,"perception":0,"alchemy":-1,"stealth":-2,"agility":0}'::jsonb, jsonb_build_array('Inherits 3 random low-level runes.', 'Requires only 3 runes to force spells into weapons as opposed to 5, with each rune beyond that increasing the chance of a stronger spell.', 'Each spell-infused weapon on hand can cast its spell twice per combat'), '#926d9f'),
  ('warden', 'Warden', 'Hybrid · Decent sustain', 'Medium armor', $am$Wardens are your classic Jack-of-all trades master of none. They bring great all around helpfulness and can be plug and play in most settings. Wardens are known for their survival skills and cunning, but are shunned for a lack of a profitable or secure occupation.$am$, 110, 75, 6, 20, 3, '{"strength":0,"accuracy":0,"intelligence":0,"vitality":0,"recovery":0,"mana_regen":0,"charisma":-2,"wisdom_cunning":3,"perception":2,"alchemy":1,"stealth":0,"agility":0}'::jsonb, jsonb_build_array('Once per combat or exploration scene, Warden may reroll a failed Perception, Alchemy, Survival, or Utility check.', 'Gains a +2 modifier of choice in a single category where the party has no bonuses'), '#79895f')
on conflict (class_key) do update
set
  name = excluded.name,
  role = excluded.role,
  armor = excluded.armor,
  identity = excluded.identity,
  base_hp = excluded.base_hp,
  base_mana = excluded.base_mana,
  base_magic_resist = excluded.base_magic_resist,
  inventory_slots = excluded.inventory_slots,
  spell_slots = excluded.spell_slots,
  attributes = excluded.attributes,
  passives = excluded.passives,
  token_color = excluded.token_color;

with class_resist_adjustments(class_key, old_magic_resist, new_magic_resist) as (
  values
    ('alchemist', 8, 5),
    ('apothecary', 11, 8),
    ('apprentice', 8, 5),
    ('armor-clad', 9, 6),
    ('beastmaster', 8, 5),
    ('blacksmith', 8, 5),
    ('knight', 8, 5),
    ('mage', 10, 7),
    ('mendrunner', 7, 4),
    ('the-muscle', 7, 4),
    ('ranger', 10, 7),
    ('rogue', 7, 4),
    ('sage', 12, 9),
    ('talismanist', 10, 7),
    ('warden', 9, 6)
)
update public.characters c
set magic_resist = a.new_magic_resist,
    updated_at = now()
from class_resist_adjustments a
where c.class_key = a.class_key
  and c.magic_resist = a.old_magic_resist;

update public.characters c
set
  class_template_id = t.id,
  class_name = t.name,
  magic_resist = case when c.magic_resist = 0 then t.base_magic_resist else c.magic_resist end,
  attributes = case when not (c.attributes ? 'wisdom_cunning') then t.attributes else c.attributes end,
  class_passives = case when not (c.attributes ? 'wisdom_cunning') then t.passives else c.class_passives end,
  updated_at = now()
from public.class_templates t
where c.class_key = t.class_key;

create or replace function public.class_template_record_to_json(p_template public.class_templates)
returns jsonb
language sql
stable
set search_path = public
as $$
  select jsonb_build_object(
    'id', p_template.id,
    'key', p_template.class_key,
    'name', p_template.name,
    'role', p_template.role,
    'armor', p_template.armor,
    'identity', p_template.identity,
    'inventorySlots', p_template.inventory_slots,
    'spellSlots', p_template.spell_slots,
    'baseHp', p_template.base_hp,
    'baseMana', p_template.base_mana,
    'baseMagicResist', p_template.base_magic_resist,
    'attributes', p_template.attributes,
    'passives', p_template.passives,
    'tokenColor', p_template.token_color
  )
$$;

create or replace function public.get_character_ledger(p_session_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
begin
  select * into v_profile
  from public.profile_from_campaign_session(p_session_token);

  if v_profile.id is null then
    raise exception 'Invalid or expired session.';
  end if;

  return jsonb_build_object(
    'profile', jsonb_build_object(
      'id', v_profile.id,
      'username', v_profile.username::text,
      'displayName', v_profile.display_name,
      'role', v_profile.role
    ),
    'profiles', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', p.id,
        'username', p.username::text,
        'displayName', p.display_name,
        'role', p.role
      ) order by p.display_name), '[]'::jsonb)
      from public.profiles p
    ),
    'classes', (
      select coalesce(jsonb_agg(public.class_template_record_to_json(t) order by t.name), '[]'::jsonb)
      from public.class_templates t
    ),
    'characters', (
      select coalesce(jsonb_agg(public.character_record_to_json(c) order by c.name), '[]'::jsonb)
      from public.characters c
      where c.kind = 'player'
        and (
          v_profile.role = 'dm'::public.user_role
          or not exists (
            select 1
            from public.profiles owner_profile
            where owner_profile.id = c.owner_user_id
              and owner_profile.role = 'dm'::public.user_role
          )
        )
    )
  );
end;
$$;

drop function if exists public.create_campaign_character(text, text, uuid, text, text, int, int, int, int, int, int, int, jsonb, jsonb, text, text);

create or replace function public.ensure_character_starter_armor(p_character_id uuid)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if p_character_id is null then
    return;
  end if;

  insert into public.inventory_items (
    character_id,
    parent_item_id,
    item_name,
    item_type,
    rarity,
    quantity,
    slot_index,
    loadout_slot,
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
  select
    p_character_id,
    null,
    'Leather Armor',
    'armor',
    'Common'::public.item_rarity,
    1,
    0,
    'armor',
    false,
    0,
    '{"vitality": -1}'::jsonb,
    null,
    'Leather',
    0,
    false,
    null,
    null,
    null
  where not exists (
    select 1
    from public.inventory_items existing
    where existing.character_id = p_character_id
      and existing.loadout_slot = 'armor'
  );
end;
$$;

create or replace function public.create_campaign_character(
  p_session_token text,
  p_name text,
  p_owner_user_id uuid,
  p_class_key text,
  p_personal_passives text default '',
  p_token_color text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_template public.class_templates%rowtype;
  v_character public.characters%rowtype;
  v_class_key text;
  v_location_city_key text;
  v_location_name text;
begin
  select * into v_profile
  from public.profile_from_campaign_session(p_session_token);

  if v_profile.id is null then
    raise exception 'Invalid or expired session.';
  end if;

  if v_profile.role <> 'dm'::public.user_role then
    raise exception 'Only the Dungeon Master can create characters.';
  end if;

  if length(trim(coalesce(p_name, ''))) = 0 then
    raise exception 'Character name is required.';
  end if;

  if p_owner_user_id is not null and not exists (select 1 from public.profiles where id = p_owner_user_id) then
    raise exception 'That player account does not exist.';
  end if;

  v_class_key := coalesce(nullif(trim(p_class_key), ''), 'alchemist');

  select *
  into v_template
  from public.class_templates
  where class_key = v_class_key
  limit 1;

  if v_template.id is null then
    raise exception 'Class template not found.';
  end if;

  select city_key, name
  into v_location_city_key, v_location_name
  from public.cities
  where is_current_residence
  order by display_order, name
  limit 1;

  if v_location_city_key is null then
    select city_key, name
    into v_location_city_key, v_location_name
    from public.cities
    where city_key = 'calostrynn'
    limit 1;
  end if;

  insert into public.characters (
    name,
    kind,
    owner_user_id,
    class_template_id,
    class_key,
    class_name,
    level,
    max_hp,
    current_hp,
    max_mana,
    current_mana,
    magic_resist,
    inventory_slots,
    spell_slots,
    attributes,
    class_passives,
    personal_passives,
    token_color,
    location_city_key,
    location_name
  )
  values (
    trim(p_name),
    'player'::public.character_kind,
    p_owner_user_id,
    v_template.id,
    v_template.class_key,
    v_template.name,
    1,
    v_template.base_hp,
    v_template.base_hp,
    v_template.base_mana,
    v_template.base_mana,
    v_template.base_magic_resist,
    v_template.inventory_slots,
    v_template.spell_slots,
    v_template.attributes,
    v_template.passives,
    coalesce(p_personal_passives, ''),
    coalesce(nullif(trim(p_token_color), ''), v_template.token_color),
    v_location_city_key,
    coalesce(v_location_name, 'Wild')
  )
  returning * into v_character;

  perform public.ensure_character_starter_armor(v_character.id);
  perform public.ensure_dm_testing_wallet(v_character.id);

  return public.character_record_to_json(v_character);
end;
$$;

do $$
declare
  v_character_id uuid;
begin
  for v_character_id in
    select id
    from public.characters
    where kind = 'player'::public.character_kind
  loop
    perform public.ensure_character_starter_armor(v_character_id);
  end loop;
end;
$$;

create or replace function public.update_campaign_character(
  p_session_token text,
  p_character_id uuid,
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
  v_template public.class_templates%rowtype;
  v_patch jsonb := coalesce(p_patch, '{}'::jsonb);
  v_owner_user_id uuid;
  v_class_key text;
  v_location record;
begin
  select * into v_profile
  from public.profile_from_campaign_session(p_session_token);

  if v_profile.id is null then
    raise exception 'Invalid or expired session.';
  end if;

  if v_profile.role <> 'dm'::public.user_role then
    raise exception 'Only the Dungeon Master can edit character sheets.';
  end if;

  select * into v_character
  from public.characters
  where id = p_character_id;

  if v_character.id is null then
    raise exception 'Character not found.';
  end if;

  if v_patch ? 'ownerUserId' then
    v_owner_user_id := nullif(v_patch->>'ownerUserId', '')::uuid;
    if v_owner_user_id is not null and not exists (select 1 from public.profiles where id = v_owner_user_id) then
      raise exception 'That player account does not exist.';
    end if;
  else
    v_owner_user_id := v_character.owner_user_id;
  end if;

  if v_patch ? 'classKey' then
    v_class_key := nullif(trim(v_patch->>'classKey'), '');
    if v_class_key is null then
      raise exception 'Class template is required.';
    end if;

    select *
    into v_template
    from public.class_templates
    where class_key = v_class_key
    limit 1;

    if v_template.id is null then
      raise exception 'Class template not found.';
    end if;
  end if;

  if v_patch ? 'locationCityKey' or v_patch ? 'locationName' then
    select *
    into v_location
    from public.resolve_character_location(v_patch->>'locationCityKey', v_patch->>'locationName');
  end if;

  update public.characters
  set
    owner_user_id = v_owner_user_id,
    class_template_id = case when v_template.id is not null then v_template.id else class_template_id end,
    class_key = case when v_template.id is not null then v_template.class_key else class_key end,
    class_name = case when v_template.id is not null then v_template.name when v_patch ? 'className' then coalesce(nullif(trim(v_patch->>'className'), ''), class_name) else class_name end,
    class_passives = case
      when v_patch ? 'classPassives' and jsonb_typeof(v_patch->'classPassives') = 'array' then v_patch->'classPassives'
      when v_template.id is not null then v_template.passives
      else class_passives
    end,
    name = case when v_patch ? 'name' then coalesce(nullif(trim(v_patch->>'name'), ''), name) else name end,
    level = case when v_patch ? 'level' then greatest(1, (v_patch->>'level')::int) else level end,
    max_hp = case when v_patch ? 'maxHp' then greatest(0, (v_patch->>'maxHp')::int) else max_hp end,
    current_hp = case when v_patch ? 'currentHp' then greatest(0, (v_patch->>'currentHp')::int) else current_hp end,
    max_mana = case when v_patch ? 'maxMana' then greatest(0, (v_patch->>'maxMana')::int) else max_mana end,
    current_mana = case when v_patch ? 'currentMana' then greatest(0, (v_patch->>'currentMana')::int) else current_mana end,
    magic_resist = case when v_patch ? 'magicResist' then greatest(0, (v_patch->>'magicResist')::int) when v_template.id is not null then v_template.base_magic_resist else magic_resist end,
    inventory_slots = case when v_patch ? 'inventorySlots' then greatest(0, least((v_patch->>'inventorySlots')::int, 120)) else inventory_slots end,
    gift_inventory_open = case when v_patch ? 'giftInventoryOpen' then (v_patch->>'giftInventoryOpen')::boolean else gift_inventory_open end,
    spell_slots = case when v_patch ? 'spellSlots' then greatest(0, (v_patch->>'spellSlots')::int) else spell_slots end,
    attributes = case when v_patch ? 'attributes' and jsonb_typeof(v_patch->'attributes') = 'object' then v_patch->'attributes' else attributes end,
    personal_passives = case when v_patch ? 'personalPassives' then coalesce(v_patch->>'personalPassives', '') else personal_passives end,
    token_color = case when v_patch ? 'tokenColor' then coalesce(nullif(trim(v_patch->>'tokenColor'), ''), token_color) else token_color end,
    location_city_key = case when v_location is not null then v_location.location_city_key else location_city_key end,
    location_name = case when v_location is not null then v_location.location_name else location_name end
  where id = p_character_id
  returning * into v_character;

  perform public.ensure_dm_testing_wallet(v_character.id);

  return public.character_record_to_json(v_character);
end;
$$;

create or replace function public.delete_campaign_character(
  p_session_token text,
  p_character_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_character public.characters%rowtype;
begin
  select * into v_profile
  from public.profile_from_campaign_session(p_session_token);

  if v_profile.id is null then
    raise exception 'Invalid or expired session.';
  end if;

  if v_profile.role <> 'dm'::public.user_role then
    raise exception 'Only the Dungeon Master can delete characters.';
  end if;

  select * into v_character
  from public.characters
  where id = p_character_id;

  if v_character.id is null then
    raise exception 'Character not found.';
  end if;

  delete from public.characters where id = p_character_id;
  return p_character_id;
end;
$$;

create or replace function public.set_character_gift_inventory_open(
  p_session_token text,
  p_character_id uuid,
  p_open boolean
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
  select * into v_profile
  from public.profile_from_campaign_session(p_session_token);

  if v_profile.id is null then
    raise exception 'Invalid or expired session.';
  end if;

  select * into v_character
  from public.characters
  where id = p_character_id;

  if v_character.id is null then
    raise exception 'Character not found.';
  end if;

  if v_profile.role <> 'dm'::public.user_role and v_character.owner_user_id is distinct from v_profile.id then
    raise exception 'You can only change gifting for your own character.';
  end if;

  update public.characters
  set gift_inventory_open = coalesce(p_open, false)
  where id = p_character_id
  returning * into v_character;

  return public.character_record_to_json(v_character);
end;
$$;

grant execute on function public.class_template_record_to_json(public.class_templates) to anon, authenticated;


-- ============================================================
-- ============================================================

-- Inventory, loadout, and wallet foundation.

create table if not exists public.currency_units (
  id uuid primary key default gen_random_uuid(),
  currency_system_key text not null default 'calostrynn',
  unit_key text not null unique,
  name text not null,
  symbol text not null default '',
  unit_order int not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.character_wallet_balances (
  character_id uuid not null references public.characters(id) on delete cascade,
  currency_unit_id uuid not null references public.currency_units(id) on delete cascade,
  amount int not null default 0 check (amount >= 0),
  updated_at timestamptz not null default now(),
  primary key (character_id, currency_unit_id)
);

insert into public.currency_units (currency_system_key, unit_key, name, symbol, unit_order)
values
  ('common', 'bit', 'Bit', 'Bit', 10),
  ('common', 'shilling', 'Shilling', 'Shilling', 20),
  ('common', 'mark', 'Mark', 'Mark', 30),
  ('common', 'crown', 'Crown', 'Crown', 40),
  ('common', 'sovereign', 'Sovereign', 'Sovereign', 50),
  ('calostrynn', 'coin', 'Coin', 'coin', 10),
  ('calostrynn', 'callis', 'Callis', 'Callis', 20),
  ('calostrynn', 'callor', 'Callor', 'Callor', 30),
  ('calostrynn', 'cal', 'Cal', 'Cal', 40)
on conflict (unit_key) do update
set
  currency_system_key = excluded.currency_system_key,
  name = excluded.name,
  symbol = excluded.symbol,
  unit_order = excluded.unit_order;

drop trigger if exists character_wallet_balances_touch_updated_at on public.character_wallet_balances;
create trigger character_wallet_balances_touch_updated_at
before update on public.character_wallet_balances
for each row execute function public.touch_updated_at();

alter table public.currency_units enable row level security;
alter table public.character_wallet_balances enable row level security;

revoke all on table public.currency_units from anon, authenticated;
revoke all on table public.character_wallet_balances from anon, authenticated;

-- ============================================================
-- ============================================================

-- Global item catalog foundation. This powers inventory add, shops, loot imports, and crafting.

create table if not exists public.item_catalog (
  id uuid primary key default gen_random_uuid(),
  item_key text not null unique,
  item_name text not null,
  item_type text not null default 'misc',
  rarity public.item_rarity not null default 'Common',
  category text not null default 'General',
  properties text[] not null default array[]::text[],
  quantity_step numeric(12,1) not null default 1 check (quantity_step in (0.5, 1)),
  is_stackable boolean not null default true,
  default_modifiers jsonb not null default '{}'::jsonb check (jsonb_typeof(default_modifiers) = 'object'),
  material text not null default '',
  is_two_handed boolean not null default false,
  storage_capacity int not null default 0 check (storage_capacity between 0 and 500),
  notes text not null default '',
  can_be_enhanced boolean not null default false,
  can_be_enchanted boolean not null default false,
  is_active boolean not null default true,
  display_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.item_catalog enable row level security;
revoke all on public.item_catalog from anon, authenticated;

drop trigger if exists item_catalog_touch_updated_at on public.item_catalog;
create trigger item_catalog_touch_updated_at
before update on public.item_catalog
for each row execute function public.touch_updated_at();

alter table public.item_catalog
  add column if not exists can_be_enhanced boolean not null default false,
  add column if not exists can_be_enchanted boolean not null default false;

create or replace function public.catalog_key_for_name(p_name text)
returns text
language sql
immutable
as $$
  select lower(regexp_replace(trim(coalesce(p_name, '')), '[^a-zA-Z0-9]+', '-', 'g'))
$$;

create or replace function public.normalize_item_type(p_item_type text)
returns text
language sql
immutable
as $$
  select case
    when lower(trim(coalesce(p_item_type, ''))) = any (array[
      'weapon',
      'armor',
      'shield',
      'pet',
      'accessory',
      'storage',
      'material',
      'catalyst',
      'rune',
      'ore',
      'potion',
      'food',
      'plant',
      'fabric',
      'tool',
      'book',
      'quest',
      'spell book',
      'currency',
      'misc'
    ]) then lower(trim(coalesce(p_item_type, '')))
    else 'misc'
  end
$$;

create or replace function public.catalog_record_to_json(p_item public.item_catalog)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'id', p_item.id,
    'key', p_item.item_key,
    'name', p_item.item_name,
    'type', p_item.item_type,
    'rarity', p_item.rarity,
    'category', p_item.category,
    'properties', to_jsonb(p_item.properties),
    'quantityStep', p_item.quantity_step,
    'stackable', p_item.is_stackable,
    'defaultModifiers', p_item.default_modifiers,
    'material', p_item.material,
    'isTwoHanded', p_item.is_two_handed,
    'storageCapacity', p_item.storage_capacity,
    'notes', p_item.notes,
    'canBeEnhanced', p_item.can_be_enhanced,
    'canBeEnchanted', p_item.can_be_enchanted,
    'active', p_item.is_active,
    'order', p_item.display_order
  )
$$;

create or replace function public.item_quantity_step(p_item_name text, p_item_type text)
returns numeric
language sql
stable
as $$
  select case
    when lower(trim(coalesce(p_item_name, ''))) in ('bronze scale', 'iron scale', 'steel scale', 'mythril scale', 'vaylium scale', 'dragonscale scale', 'dragon scale')
      and lower(trim(coalesce(p_item_type, ''))) in ('material', 'ore')
      then 0.5::numeric
    else coalesce((
      select c.quantity_step
      from public.item_catalog c
      where c.item_key = public.catalog_key_for_name(p_item_name)
        and c.is_active = true
      limit 1
    ), 1::numeric)
  end
$$;

create or replace function public.item_catalog_stackable(p_item_name text, p_item_type text)
returns boolean
language sql
stable
as $$
  select case
    when lower(trim(coalesce(p_item_type, ''))) in ('pet', 'storage', 'book', 'spell book') then false
    else coalesce((
      select c.is_stackable
      from public.item_catalog c
      where c.item_key = public.catalog_key_for_name(p_item_name)
        and c.is_active = true
      limit 1
    ), true)
  end
$$;

create or replace function public.item_catalog_can_be_enhanced(p_item_name text, p_item_type text, p_material text default null)
returns boolean
language sql
stable
as $$
  select coalesce((
    select c.can_be_enhanced
    from public.item_catalog c
    where c.item_key = public.catalog_key_for_name(p_item_name)
      and c.is_active = true
    limit 1
  ), lower(concat_ws(' ', coalesce(p_material, ''), coalesce(p_item_name, ''))) like '%mythril%'
      and public.normalize_item_type(p_item_type) in ('weapon', 'shield', 'armor', 'tool'))
$$;

create or replace function public.item_catalog_can_be_enchanted(p_item_name text, p_item_type text, p_material text default null)
returns boolean
language sql
stable
as $$
  select coalesce((
    select c.can_be_enchanted
    from public.item_catalog c
    where c.item_key = public.catalog_key_for_name(p_item_name)
      and c.is_active = true
    limit 1
  ), lower(concat_ws(' ', coalesce(p_material, ''), coalesce(p_item_name, ''))) like '%mythril%'
      and public.normalize_item_type(p_item_type) in ('weapon', 'shield', 'tool'))
$$;

create or replace function public.format_item_quantity(p_quantity numeric)
returns text
language sql
immutable
as $$
  select case
    when p_quantity is null then '0'
    else trim(trailing '.' from trim(trailing '0' from p_quantity::text))
  end
$$;

create or replace function public.catalog_storage_capacity(p_item_name text)
returns int
language sql
stable
as $$
  select case
    when lower(coalesce(p_item_name, '')) like '%bag of holding%' then 100
    when lower(coalesce(p_item_name, '')) like '%wagon home%' then 40
    when lower(coalesce(p_item_name, '')) like '%caged wagon%' then 3
    when lower(coalesce(p_item_name, '')) like '%heavy wagon%' then 60
    when lower(coalesce(p_item_name, '')) like '%light wagon%' then 25
    when lower(coalesce(p_item_name, '')) like '%heavy duffle%' then 10
    when lower(coalesce(p_item_name, '')) like '%light duffle%' then 6
    when lower(coalesce(p_item_name, '')) like '%back bag%' or lower(coalesce(p_item_name, '')) like '%backpack%' then 3
    when lower(coalesce(p_item_name, '')) like '%waist pouch%' or lower(coalesce(p_item_name, '')) like '%pouch%' then 1
    when lower(coalesce(p_item_name, '')) like '%satchel%' then 3
    else 6
  end
$$;

create or replace function public.additional_storage_kind(p_item_name text, p_item_type text default 'storage')
returns text
language sql
immutable
as $$
  select case
    when public.normalize_item_type(coalesce(p_item_type, 'storage')) <> 'storage' then null
    when lower(coalesce(p_item_name, '')) like '%wagon home%' then null
    when lower(coalesce(p_item_name, '')) like '%caged wagon%' then null
    when lower(coalesce(p_item_name, '')) like '%bag of holding%' then 'bag-of-holding'
    when lower(coalesce(p_item_name, '')) like '%heavy wagon%' then 'heavy-wagon'
    when lower(coalesce(p_item_name, '')) like '%light wagon%' then 'light-wagon'
    when lower(coalesce(p_item_name, '')) like '%heavy duffle%' then 'heavy-duffle'
    when lower(coalesce(p_item_name, '')) like '%light duffle%' then 'light-duffle'
    when lower(coalesce(p_item_name, '')) like '%back bag%' or lower(coalesce(p_item_name, '')) like '%backpack%' then 'back-bag'
    when lower(coalesce(p_item_name, '')) like '%waist pouch%' or lower(coalesce(p_item_name, '')) like '%pouch%' then 'waist-pouch'
    else null
  end
$$;

create or replace function public.inventory_item_can_hold_children(p_item public.inventory_items)
returns boolean
language sql
stable
as $$
  select p_item.is_storage = true
    and (
      coalesce(p_item.storage_active, false)
      or (
        public.normalize_item_type(p_item.item_type) = 'storage'
        and (
          lower(coalesce(p_item.item_name, '')) like '%wagon home%'
          or lower(coalesce(p_item.item_name, '')) like '%caged wagon%'
        )
      )
    )
$$;


create or replace function public.assert_valid_item_quantity(p_item_name text, p_item_type text, p_quantity numeric)
returns numeric
language plpgsql
stable
set search_path = public
as $$
declare
  v_quantity numeric := coalesce(p_quantity, 1);
  v_step numeric := public.item_quantity_step(p_item_name, p_item_type);
begin
  if v_quantity <= 0 then
    raise exception 'Item quantity must be greater than zero.';
  end if;

  if v_step = 0.5 then
    if mod((v_quantity * 2)::numeric, 1::numeric) <> 0 then
      raise exception 'This material can only use half-scale increments.';
    end if;
  elsif mod(v_quantity::numeric, 1::numeric) <> 0 then
    raise exception 'This item must use whole-number quantities.';
  end if;

  return round(v_quantity * 2) / 2;
end;
$$;

drop function if exists public.upsert_item_catalog_entry(text, text, text, text, text[], integer, boolean, jsonb, text, boolean, integer, text, boolean, integer);
drop function if exists public.upsert_item_catalog_entry(text, text, text, text, text[], numeric, boolean, jsonb, text, boolean, integer, text, boolean, integer);
drop function if exists public.upsert_item_catalog_entry(text, text, text, text, text[], integer, boolean, jsonb, text, boolean, integer, text, boolean, integer, boolean);
drop function if exists public.upsert_item_catalog_entry(text, text, text, text, text[], numeric, boolean, jsonb, text, boolean, integer, text, boolean, integer, boolean);
drop function if exists public.upsert_item_catalog_entry(text, text, text, text, text[], integer, boolean, jsonb, text, boolean, integer, text, boolean, integer, boolean, boolean);
drop function if exists public.upsert_item_catalog_entry(text, text, text, text, text[], numeric, boolean, jsonb, text, boolean, integer, text, boolean, integer, boolean, boolean);

create or replace function public.upsert_item_catalog_entry(
  p_item_name text,
  p_item_type text,
  p_rarity text,
  p_category text default 'General',
  p_properties text[] default array[]::text[],
  p_quantity_step numeric default 1,
  p_is_stackable boolean default true,
  p_default_modifiers jsonb default '{}'::jsonb,
  p_material text default '',
  p_is_two_handed boolean default false,
  p_storage_capacity int default 0,
  p_notes text default '',
  p_is_active boolean default true,
  p_display_order int default 0,
  p_can_be_enhanced boolean default false,
  p_can_be_enchanted boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_item_name text := trim(coalesce(p_item_name, ''));
begin
  if length(v_item_name) = 0 then
    raise exception 'Item name is required.';
  end if;

  insert into public.item_catalog (
    item_key,
    item_name,
    item_type,
    rarity,
    category,
    properties,
    quantity_step,
    is_stackable,
    default_modifiers,
    material,
    is_two_handed,
    storage_capacity,
    notes,
    can_be_enhanced,
    can_be_enchanted,
    is_active,
    display_order
  )
  values (
    public.catalog_key_for_name(v_item_name),
    v_item_name,
    public.normalize_item_type(p_item_type),
    coalesce(nullif(p_rarity, ''), 'Common')::public.item_rarity,
    coalesce(nullif(trim(p_category), ''), 'General'),
    coalesce(p_properties, array[]::text[]),
    case when coalesce(p_quantity_step, 1) = 0.5 then 0.5 else 1 end,
    coalesce(p_is_stackable, true),
    case when jsonb_typeof(coalesce(p_default_modifiers, '{}'::jsonb)) = 'object' then coalesce(p_default_modifiers, '{}'::jsonb) else '{}'::jsonb end,
    coalesce(trim(p_material), ''),
    coalesce(p_is_two_handed, false),
    greatest(0, coalesce(p_storage_capacity, 0)),
    coalesce(p_notes, ''),
    coalesce(p_can_be_enhanced, false),
    coalesce(p_can_be_enchanted, false),
    coalesce(p_is_active, true),
    coalesce(p_display_order, 0)
  )
  on conflict (item_key) do update
  set item_name = excluded.item_name,
      item_type = excluded.item_type,
      rarity = excluded.rarity,
      category = excluded.category,
      properties = (
        select coalesce(array_agg(distinct prop order by prop), array[]::text[])
        from unnest(public.item_catalog.properties || excluded.properties) as prop
        where nullif(trim(prop), '') is not null
      ),
      quantity_step = excluded.quantity_step,
      is_stackable = excluded.is_stackable,
      default_modifiers = case
        when excluded.default_modifiers = '{}'::jsonb then public.item_catalog.default_modifiers
        else public.item_catalog.default_modifiers || excluded.default_modifiers
      end,
      material = case when excluded.material = '' then public.item_catalog.material else excluded.material end,
      is_two_handed = excluded.is_two_handed,
      storage_capacity = greatest(public.item_catalog.storage_capacity, excluded.storage_capacity),
      notes = case when excluded.notes = '' then public.item_catalog.notes else excluded.notes end,
      can_be_enhanced = case when excluded.can_be_enhanced then true else public.item_catalog.can_be_enhanced end,
      can_be_enchanted = case when excluded.can_be_enchanted then true else public.item_catalog.can_be_enchanted end,
      is_active = excluded.is_active,
      display_order = excluded.display_order
  returning id into v_id;

  return v_id;
end;
$$;

-- Seed/refresh global item catalog from source assets.
do $$
begin
  perform public.upsert_item_catalog_entry('Leather Armor', 'armor', 'Common', 'Armor', array['Starter armor', '-1 Vitality']::text[], 1, true, '{"vitality": -1}'::jsonb, 'Leather', false, 0, 'Starter armor. -1 Vitality while active.', true, 5);
  perform public.upsert_item_catalog_entry('History Book', 'book', 'Common', 'Books', array['Table-resolved contents']::text[], 1, false, '{}'::jsonb, '', false, 0, 'A general history volume. Resolve its contents at the table.', true, 6);
  perform public.upsert_item_catalog_entry('Alchemy Book', 'book', 'Common', 'Books', array['Table-resolved contents']::text[], 1, false, '{}'::jsonb, '', false, 0, 'An alchemical study text. Resolve its contents at the table.', true, 7);
  perform public.upsert_item_catalog_entry('Bestiary', 'book', 'Common', 'Books', array['Table-resolved contents']::text[], 1, false, '{}'::jsonb, '', false, 0, 'A creature reference volume. Resolve its contents at the table.', true, 8);
  perform public.upsert_item_catalog_entry('Magical Research', 'book', 'Rare', 'Books', array['Research voucher']::text[], 1, false, '{}'::jsonb, '', false, 0, 'Choose a spell category at purchase to receive a rare magic spell book.', true, 9);
  perform public.upsert_item_catalog_entry(
    'Peaceful Restoration Spell Book',
    'spell book',
    'Legendary',
    'Unique Spell Books',
    array['Open book', 'Peaceful Restoration', 'Two forms', 'Does not take a spell slot']::text[],
    1,
    false,
    '{}'::jsonb,
    '',
    false,
    0,
    $am$A unique spell book containing Peaceful Restoration. Form 1: 40 Mana, heals an ally for 75 HP and restores 25 Mana; if the caster is on fire, heals 20 HP and restores 10 Mana instead. Form 2: 40 Mana, restores 75 Mana and heals 25 HP; this form cannot be used while the caster is on fire.$am$,
    true,
    9
  );
  perform public.upsert_item_catalog_entry('Ember Magic Spell Book', 'book', 'Rare', 'Books', array['Ember research']::text[], 1, false, '{}'::jsonb, '', false, 0, 'A rare Ember magic spell book from library research.', true, 10);
  perform public.upsert_item_catalog_entry('Frost Magic Spell Book', 'book', 'Rare', 'Books', array['Frost research']::text[], 1, false, '{}'::jsonb, '', false, 0, 'A rare Frost magic spell book from library research.', true, 11);
  perform public.upsert_item_catalog_entry('Lightning Magic Spell Book', 'book', 'Rare', 'Books', array['Lightning research']::text[], 1, false, '{}'::jsonb, '', false, 0, 'A rare Lightning magic spell book from library research.', true, 12);
  perform public.upsert_item_catalog_entry('Earth Magic Spell Book', 'book', 'Rare', 'Books', array['Earth research']::text[], 1, false, '{}'::jsonb, '', false, 0, 'A rare Earth magic spell book from library research.', true, 13);
  perform public.upsert_item_catalog_entry('Wind Magic Spell Book', 'book', 'Rare', 'Books', array['Wind research']::text[], 1, false, '{}'::jsonb, '', false, 0, 'A rare Wind magic spell book from library research.', true, 14);
  perform public.upsert_item_catalog_entry('Energy Magic Spell Book', 'book', 'Rare', 'Books', array['Energy research']::text[], 1, false, '{}'::jsonb, '', false, 0, 'A rare Energy magic spell book from library research.', true, 15);
  perform public.upsert_item_catalog_entry('Defensive Support Magic Spell Book', 'book', 'Rare', 'Books', array['Defensive Support research']::text[], 1, false, '{}'::jsonb, '', false, 0, 'A rare Defensive Support magic spell book from library research.', true, 16);
  perform public.upsert_item_catalog_entry('Offensive Support Magic Spell Book', 'book', 'Rare', 'Books', array['Offensive Support research']::text[], 1, false, '{}'::jsonb, '', false, 0, 'A rare Offensive Support magic spell book from library research.', true, 17);
  perform public.upsert_item_catalog_entry('Enhancement Magic Spell Book', 'book', 'Rare', 'Books', array['Enhancement research']::text[], 1, false, '{}'::jsonb, '', false, 0, 'A rare Enhancement magic spell book from library research.', true, 18);
  perform public.upsert_item_catalog_entry('Utility Magic Spell Book', 'book', 'Rare', 'Books', array['Utility research']::text[], 1, false, '{}'::jsonb, '', false, 0, 'A rare Utility magic spell book from library research.', true, 19);
  perform public.upsert_item_catalog_entry('Waist Pouch', 'storage', 'Common', 'Market Storage', array['1 storage slot']::text[], 1, false, '{}'::jsonb, '', false, 1, 'A compact pouch with 1 storage slot.', true, 2000);
  perform public.upsert_item_catalog_entry('Back Bag', 'storage', 'Common', 'Market Storage', array['3 storage slots']::text[], 1, false, '{}'::jsonb, '', false, 3, 'A back bag with 3 storage slots.', true, 2010);
  perform public.upsert_item_catalog_entry('Light Duffle', 'storage', 'Uncommon', 'Market Storage', array['6 storage slots']::text[], 1, false, '{}'::jsonb, '', false, 6, 'A light duffle with 6 storage slots.', true, 2020);
  perform public.upsert_item_catalog_entry('Heavy Duffle', 'storage', 'Rare', 'Market Storage', array['10 storage slots']::text[], 1, false, '{}'::jsonb, '', false, 10, 'A heavy duffle with 10 storage slots.', true, 2030);
  perform public.upsert_item_catalog_entry('Bag of Holding', 'storage', 'Mythical', 'Market Storage', array['100 storage slots']::text[], 1, false, '{}'::jsonb, '', false, 100, 'A magical bag with 100 storage slots.', true, 2040);
  perform public.upsert_item_catalog_entry('Light Wagon', 'storage', 'Rare', 'Market Storage', array['25 storage slots']::text[], 1, false, '{}'::jsonb, '', false, 25, 'A light wagon with 25 storage slots.', true, 2050);
  perform public.upsert_item_catalog_entry('Heavy Wagon', 'storage', 'Epic', 'Market Storage', array['60 storage slots']::text[], 1, false, '{}'::jsonb, '', false, 60, 'A heavy wagon with 60 storage slots.', true, 2060);
  perform public.upsert_item_catalog_entry('Caged Wagon', 'storage', 'Epic', 'Market Storage', array['Wagon stable', '3 animal slots']::text[], 1, false, '{}'::jsonb, '', false, 3, 'A caged wagon that can carry up to 3 animal companions.', true, 2062);
  perform public.upsert_item_catalog_entry('Wagon Home', 'storage', 'Epic', 'Market Storage', array['Mobile home', '40 storage slots']::text[], 1, false, '{}'::jsonb, '', false, 40, 'A wagon home with 40 storage slots.', true, 2064);
  perform public.upsert_item_catalog_entry('Torch', 'tool', 'Common', 'Market Supplies', array['Travel supply']::text[], 1, true, '{}'::jsonb, '', false, 0, 'A basic torch for travel and dungeon work.', true, 2070);
  perform public.upsert_item_catalog_entry('Arrow', 'weapon', 'Common', 'Market Supplies', array['Ammunition']::text[], 1, true, '{}'::jsonb, '', false, 0, 'A single arrow for bows and ranged combat.', true, 2075);
  perform public.upsert_item_catalog_entry('Rope', 'tool', 'Common', 'Market Supplies', array['Travel supply']::text[], 1, true, '{}'::jsonb, '', false, 0, 'A coil of sturdy rope.', true, 2080);
  perform public.upsert_item_catalog_entry('Blanket', 'fabric', 'Common', 'Market Supplies', array['Travel supply']::text[], 1, true, '{}'::jsonb, '', false, 0, 'A simple travel blanket.', true, 2090);
  perform public.upsert_item_catalog_entry('Cooking Pots', 'tool', 'Common', 'Market Supplies', array['Camp cooking']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Cooking pots for camp meals.', true, 2100);
  perform public.upsert_item_catalog_entry('Cloth', 'fabric', 'Common', 'Market Supplies', array['Fabric']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Common cloth.', true, 2110);
  perform public.upsert_item_catalog_entry('Fine Cloth', 'fabric', 'Common', 'Market Supplies', array['Fine fabric']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Fine cloth.', true, 2120);
  perform public.upsert_item_catalog_entry('Ink and Paper', 'tool', 'Common', 'Market Supplies', array['Writing supply']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Ink and paper for notes, maps, and records.', true, 2130);
  perform public.upsert_item_catalog_entry('Lock', 'tool', 'Common', 'Market Supplies', array['Security supply']::text[], 1, true, '{}'::jsonb, '', false, 0, 'A standard lock.', true, 2140);
  perform public.upsert_item_catalog_entry('Standard Hammer', 'tool', 'Common', 'Market Supplies', array['Tool']::text[], 1, true, '{}'::jsonb, '', false, 0, 'A standard hammer.', true, 2150);
  perform public.upsert_item_catalog_entry('Standard Axe', 'tool', 'Common', 'Market Supplies', array['Tool']::text[], 1, true, '{}'::jsonb, '', false, 0, 'A standard axe.', true, 2160);
  perform public.upsert_item_catalog_entry('Quartz', 'ore', 'Rare', 'Market Jewels', array['Gem']::text[], 1, true, '{}'::jsonb, '', false, 0, 'A quartz gem.', true, 2170);
  perform public.upsert_item_catalog_entry('Emerald', 'ore', 'Epic', 'Market Jewels', array['Gem']::text[], 1, true, '{}'::jsonb, '', false, 0, 'An emerald gem.', true, 2180);
  perform public.upsert_item_catalog_entry('Ruby', 'ore', 'Epic', 'Market Jewels', array['Gem']::text[], 1, true, '{}'::jsonb, '', false, 0, 'A ruby gem.', true, 2190);
  perform public.upsert_item_catalog_entry('Sapphire', 'ore', 'Legendary', 'Market Jewels', array['Gem']::text[], 1, true, '{}'::jsonb, '', false, 0, 'A sapphire gem.', true, 2200);
  perform public.upsert_item_catalog_entry('Winter Wear', 'fabric', 'Uncommon', 'Market Clothing', array['Cold weather clothing']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Clothing suited for winter travel.', true, 2210);
  perform public.upsert_item_catalog_entry('Heat Wear', 'fabric', 'Uncommon', 'Market Clothing', array['Hot weather clothing']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Clothing suited for hot climates.', true, 2220);
  perform public.upsert_item_catalog_entry('Rainproof Wear', 'fabric', 'Uncommon', 'Market Clothing', array['Rainproof clothing']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Clothing suited for wet weather.', true, 2230);
  perform public.upsert_item_catalog_entry('Horse', 'pet', 'Rare', 'Market Stable', array['Mount']::text[], 1, false, '{}'::jsonb, '', false, 0, 'A riding horse.', true, 2280);
  perform public.upsert_item_catalog_entry('War Horse', 'pet', 'Rare', 'Market Stable', array['Mount']::text[], 1, false, '{}'::jsonb, '', false, 0, 'A trained war horse.', true, 2290);
  perform public.upsert_item_catalog_entry('Dog', 'pet', 'Epic', 'Market Stable', array['Pet']::text[], 1, false, '{}'::jsonb, '', false, 0, '', true, 2300);

  update public.item_catalog
  set notes = ''
  where item_key = 'dog';

  update public.item_catalog
  set storage_capacity = case item_key
    when 'waist-pouch' then 1
    when 'back-bag' then 3
    when 'light-duffle' then 6
    when 'heavy-duffle' then 10
    when 'bag-of-holding' then 100
    when 'light-wagon' then 25
    when 'heavy-wagon' then 60
    when 'caged-wagon' then 3
    when 'wagon-home' then 40
    else storage_capacity
  end
  where item_key in ('waist-pouch', 'back-bag', 'light-duffle', 'heavy-duffle', 'bag-of-holding', 'light-wagon', 'heavy-wagon', 'caged-wagon', 'wagon-home');

  update public.item_catalog
  set can_be_enhanced = item_key in (
        'mythril-pickaxe',
        'mythril-sword',
        'mythril-dagger',
        'mythril-axe',
        'mythril-battleaxe',
        'mythril-mace',
        'mythril-shield',
        'mythril-armor',
        'vaylium-armor'
      ),
      can_be_enchanted = item_key in (
        'mythril-sword',
        'mythril-dagger',
        'mythril-axe',
        'mythril-battleaxe',
        'mythril-mace',
        'mythril-shield'
      )
  where item_key in (
    'mythril-pickaxe',
    'mythril-sword',
    'mythril-dagger',
    'mythril-axe',
    'mythril-battleaxe',
    'mythril-mace',
    'mythril-shield',
    'mythril-armor',
    'vaylium-armor'
  );

  delete from public.item_catalog
  where item_key in ('basic-meal', 'tavern-meal', 'inn-room', 'fine-inn')
    and category = 'Market Tavern';

  perform public.upsert_item_catalog_entry('Acer Root', 'plant', 'Uncommon', 'Alchemy Ingredient', array['Strength']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Has Strength property when used as an ingredient', true, 10);
  perform public.upsert_item_catalog_entry('Aethercap', 'plant', 'Uncommon', 'Alchemy Ingredient', array['Sorcery']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Has Sorcery property when used as an ingredient', true, 20);
  perform public.upsert_item_catalog_entry('Agilis', 'plant', 'Uncommon', 'Alchemy Ingredient', array['Agility']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Has Agility property when used as an ingredient', true, 30);
  perform public.upsert_item_catalog_entry('Aloe', 'plant', 'Common', 'Alchemy Ingredient', array['Healing', 'Stabilizer']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Has Healing property when used as an ingredient; Has Stabilizer property when used as an ingredient', true, 40);
  perform public.upsert_item_catalog_entry('Axillium', 'plant', 'Uncommon', 'Alchemy Ingredient', array['Healing']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Has Healing property when used as an ingredient', true, 50);
  perform public.upsert_item_catalog_entry('Bitterleaf', 'plant', 'Common', 'Alchemy Ingredient', array['Antidote']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Has Antidote property when used as an ingredient', true, 60);
  perform public.upsert_item_catalog_entry('Bitterwake Root', 'plant', 'Rare', 'Alchemy Ingredient', array['Wake-Up']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Has Wake-Up property when used as an ingredient', true, 70);
  perform public.upsert_item_catalog_entry('Blessing Berry', 'plant', 'Common', 'Alchemy Ingredient', array['Healing']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Has Healing property when used as an ingredient', true, 80);
  perform public.upsert_item_catalog_entry('Bloodmoss', 'plant', 'Uncommon', 'Alchemy Ingredient', array['Clotting']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Has Clotting property when used as an ingredient', true, 90);
  perform public.upsert_item_catalog_entry('Blue Aloe', 'plant', 'Uncommon', 'Alchemy Ingredient', array['Cooling']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Has Cooling property when used as an ingredient', true, 100);
  perform public.upsert_item_catalog_entry('Blueglass Petal', 'plant', 'Rare', 'Alchemy Ingredient', array['Sorcery']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Has Sorcery property when used as an ingredient', true, 110);
  perform public.upsert_item_catalog_entry('Bogbeast Slime', 'catalyst', 'Uncommon', 'Alchemy Ingredient', array['Catalyst']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Has Catalyst property when used as an ingredient', true, 120);
  perform public.upsert_item_catalog_entry('Cinderroot', 'plant', 'Uncommon', 'Alchemy Ingredient', array['Warming']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Has Warming property when used as an ingredient', true, 130);
  perform public.upsert_item_catalog_entry('Clearbell Flower', 'plant', 'Rare', 'Alchemy Ingredient', array['Clear-Mind']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Has Clear-Mind property when used as an ingredient', true, 140);
  perform public.upsert_item_catalog_entry('Crystaline Fragments', 'catalyst', 'Rare', 'Alchemy Ingredient', array['Catalyst']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Has Catalyst property when used as an ingredient', true, 150);
  perform public.upsert_item_catalog_entry('Dawnpetal', 'plant', 'Uncommon', 'Alchemy Ingredient', array['Wake-Up']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Has Wake-Up property when used as an ingredient', true, 160);
  perform public.upsert_item_catalog_entry('Dragon Gland', 'catalyst', 'Legendary', 'Alchemy Ingredient', array['Catalyst']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Has Catalyst property when used as an ingredient', true, 170);
  perform public.upsert_item_catalog_entry('Dragon Scale', 'catalyst', 'Legendary', 'Alchemy Ingredient', array['Catalyst']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Has Catalyst property when used as an ingredient', true, 180);
  perform public.upsert_item_catalog_entry('Eagle Feather', 'catalyst', 'Uncommon', 'Alchemy Ingredient', array['Catalyst']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Has Catalyst property when used as an ingredient', true, 190);
  perform public.upsert_item_catalog_entry('Emberleaf', 'plant', 'Common', 'Alchemy Ingredient', array['Warming']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Has Warming property when used as an ingredient', true, 200);
  perform public.upsert_item_catalog_entry('Embertoothed Fang', 'catalyst', 'Uncommon', 'Alchemy Ingredient', array['Catalyst']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Has Catalyst property when used as an ingredient', true, 210);
  perform public.upsert_item_catalog_entry('Fortune Clover', 'plant', 'Rare', 'Alchemy Ingredient', array['Luck']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Has Luck property when used as an ingredient', true, 220);
  perform public.upsert_item_catalog_entry('Frosthorn Antler', 'catalyst', 'Uncommon', 'Alchemy Ingredient', array['Catalyst']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Has Catalyst property when used as an ingredient', true, 230);
  perform public.upsert_item_catalog_entry('Frostmint', 'plant', 'Common', 'Alchemy Ingredient', array['Cooling']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Has Cooling property when used as an ingredient', true, 240);
  perform public.upsert_item_catalog_entry('Fulger Wheat', 'plant', 'Common', 'Alchemy Ingredient', array['Speed']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Has Speed property when used as an ingredient', true, 250);
  perform public.upsert_item_catalog_entry('Golem Core', 'catalyst', 'Rare', 'Alchemy Ingredient', array['Catalyst']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Has Catalyst property when used as an ingredient', true, 260);
  perform public.upsert_item_catalog_entry('Griffin Feather', 'catalyst', 'Uncommon', 'Alchemy Ingredient', array['Catalyst']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Has Catalyst property when used as an ingredient', true, 270);
  perform public.upsert_item_catalog_entry('Hawkeye Blossom', 'plant', 'Rare', 'Alchemy Ingredient', array['Accuracy']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Has Accuracy property when used as an ingredient', true, 280);
  perform public.upsert_item_catalog_entry('Heartwood Sprout', 'plant', 'Rare', 'Alchemy Ingredient', array['Vitality']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Has Vitality property when used as an ingredient', true, 290);
  perform public.upsert_item_catalog_entry('Ironmoss', 'plant', 'Rare', 'Alchemy Ingredient', array['Thickskin']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Has Thickskin property when used as an ingredient', true, 300);
  perform public.upsert_item_catalog_entry('Krug Stone', 'catalyst', 'Common', 'Alchemy Ingredient', array['Catalyst']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Has Catalyst property when used as an ingredient', true, 310);
  perform public.upsert_item_catalog_entry('Leyroot', 'plant', 'Rare', 'Alchemy Ingredient', array['Mana Regen']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Has Mana Regen property when used as an ingredient', true, 320);
  perform public.upsert_item_catalog_entry('Mana Leech', 'catalyst', 'Uncommon', 'Alchemy Ingredient', array['Catalyst']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Has Catalyst property when used as an ingredient', true, 330);
  perform public.upsert_item_catalog_entry('Mana Tick', 'catalyst', 'Uncommon', 'Alchemy Ingredient', array['Catalyst']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Has Catalyst property when used as an ingredient', true, 340);
  perform public.upsert_item_catalog_entry('Manabloom', 'plant', 'Uncommon', 'Alchemy Ingredient', array['Mana Regen']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Has Mana Regen property when used as an ingredient', true, 350);
  perform public.upsert_item_catalog_entry('Moonberry', 'plant', 'Uncommon', 'Alchemy Ingredient', array['Night-Eye']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Has Night-Eye property when used as an ingredient', true, 360);
  perform public.upsert_item_catalog_entry('Moonwell Moss', 'plant', 'Uncommon', 'Alchemy Ingredient', array['Stabilizer']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Has Stabilizer property when used as an ingredient', true, 370);
  perform public.upsert_item_catalog_entry('Mystic Serpent Venom', 'catalyst', 'Uncommon', 'Alchemy Ingredient', array['Catalyst']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Has Catalyst property when used as an ingredient', true, 380);
  perform public.upsert_item_catalog_entry('Null Fern', 'plant', 'Rare', 'Alchemy Ingredient', array['Magic Resist']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Has Magic Resist property when used as an ingredient', true, 390);
  perform public.upsert_item_catalog_entry('Purewater Reed', 'plant', 'Common', 'Alchemy Ingredient', array['Stabilizer']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Has Stabilizer property when used as an ingredient', true, 400);
  perform public.upsert_item_catalog_entry('Shade Moss', 'plant', 'Rare', 'Alchemy Ingredient', array['Stealth']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Has Stealth property when used as an ingredient', true, 410);
  perform public.upsert_item_catalog_entry('Snakebane Root', 'plant', 'Uncommon', 'Alchemy Ingredient', array['Antidote']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Has Antidote property when used as an ingredient', true, 420);
  perform public.upsert_item_catalog_entry('Star Sage Orchid', 'plant', 'Rare', 'Alchemy Ingredient', array['Intelligence']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Has Intelligence property when used as an ingredient', true, 430);
  perform public.upsert_item_catalog_entry('Stillwater Reed', 'plant', 'Uncommon', 'Alchemy Ingredient', array['Clear-Mind', 'Stabilizer']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Has Clear-Mind property when used as an ingredient; Has Stabilizer property when used as an ingredient', true, 440);
  perform public.upsert_item_catalog_entry('Stonebark', 'plant', 'Uncommon', 'Alchemy Ingredient', array['Thickskin']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Has Thickskin property when used as an ingredient', true, 450);
  perform public.upsert_item_catalog_entry('Titanvine Root', 'plant', 'Rare', 'Alchemy Ingredient', array['Strength']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Has Strength property when used as an ingredient', true, 460);
  perform public.upsert_item_catalog_entry('Ventus Root', 'plant', 'Uncommon', 'Alchemy Ingredient', array['Speed']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Has Speed property when used as an ingredient', true, 470);
  perform public.upsert_item_catalog_entry('Void Avatar Residue', 'catalyst', 'Legendary', 'Alchemy Ingredient', array['Catalyst']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Has Catalyst property when used as an ingredient', true, 480);
  perform public.upsert_item_catalog_entry('Wolf Fang', 'catalyst', 'Common', 'Alchemy Ingredient', array['Catalyst']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Has Catalyst property when used as an ingredient', true, 490);
  perform public.upsert_item_catalog_entry('Yarrow', 'plant', 'Common', 'Alchemy Ingredient', array['Clotting', 'Healing', 'Stabilizer']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Has Clotting property when used as an ingredient; Has Healing property when used as an ingredient; Has Stabilizer property when used as an ingredient', true, 500);
  perform public.upsert_item_catalog_entry('Bronze Scale', 'material', 'Common', 'Material Scales', array['Bronze: -1 Strength when used for weapons; +1 Vitality when used for shields.']::text[], 0.5, true, '{}'::jsonb, 'Bronze', false, 0, 'Bronze: -1 Strength when used for weapons; +1 Vitality when used for shields.', true, 510);
  perform public.upsert_item_catalog_entry('Iron Scale', 'material', 'Common', 'Material Scales', array['Iron: neutral weapon material; +1 Vitality when used for shields.']::text[], 0.5, true, '{}'::jsonb, 'Iron', false, 0, 'Iron: neutral weapon material; +1 Vitality when used for shields.', true, 520);
  perform public.upsert_item_catalog_entry('Steel Scale', 'material', 'Uncommon', 'Material Scales', array['Steel: +1 Strength when used for weapons; +1 Vitality when used for shields.']::text[], 0.5, true, '{}'::jsonb, 'Steel', false, 0, 'Steel: +1 Strength when used for weapons; +1 Vitality when used for shields.', true, 530);
  perform public.upsert_item_catalog_entry('Mythril Scale', 'material', 'Rare', 'Material Scales', array['Mythril: eligible for enhancement or enchantment when crafted into weapon, shield, or armor.']::text[], 0.5, true, '{}'::jsonb, 'Mythril', false, 0, 'Mythril: eligible for enhancement or enchantment when crafted into weapon, shield, or armor.', true, 540);
  perform public.upsert_item_catalog_entry('Vaylium Scale', 'material', 'Epic', 'Material Scales', array['Vaylium: +1 Intelligence; weapons use Intelligence instead of Strength.']::text[], 0.5, true, '{}'::jsonb, 'Vaylium', false, 0, 'Vaylium: +1 Intelligence; weapons use Intelligence instead of Strength.', true, 550);
  perform public.upsert_item_catalog_entry('Dragonscale Scale', 'material', 'Legendary', 'Material Scales', array['Dragonscale: +2 Strength and +3 Magic Resist for weapons; +2 Vitality and +3 Magic Resist for shields; +2 Vitality and +5 Magic Resist for armor.']::text[], 0.5, true, '{}'::jsonb, 'Dragonscale', false, 0, 'Dragonscale: +2 Strength and +3 Magic Resist for weapons; +2 Vitality and +3 Magic Resist for shields; +2 Vitality and +5 Magic Resist for armor.', true, 560);
  perform public.upsert_item_catalog_entry('Ember Rune', 'rune', 'Epic', 'Runes', array['Can be used for Ember enchantments.']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Can be used for Ember enchantments.', true, 570);
  perform public.upsert_item_catalog_entry('Frost Rune', 'rune', 'Epic', 'Runes', array['Can be used for Frost enchantments.']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Can be used for Frost enchantments.', true, 580);
  perform public.upsert_item_catalog_entry('Lightning Rune', 'rune', 'Epic', 'Runes', array['Can be used for Lightning enchantments.']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Can be used for Lightning enchantments.', true, 590);
  perform public.upsert_item_catalog_entry('Earth Rune', 'rune', 'Epic', 'Runes', array['Can be used for Earth enchantments.']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Can be used for Earth enchantments.', true, 600);
  perform public.upsert_item_catalog_entry('Wind Rune', 'rune', 'Epic', 'Runes', array['Can be used for Wind enchantments.']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Can be used for Wind enchantments.', true, 610);
  perform public.upsert_item_catalog_entry('Mountain Rune', 'rune', 'Epic', 'Runes', array['Cannot be used for enchantments yet.']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Cannot be used for enchantments yet.', true, 620);
  perform public.upsert_item_catalog_entry('Void Rune', 'rune', 'Mythical', 'Runes', array['Cannot be used for enchantments yet.']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Cannot be used for enchantments yet.', true, 625);
  perform public.upsert_item_catalog_entry('Dagger', 'weapon', 'Common', 'Light Weapons', array[]::text[], 1, true, '{}'::jsonb, '', false, 0, '', true, 630);
  perform public.upsert_item_catalog_entry('Throwing Knives', 'weapon', 'Common', 'Light Weapons', array[]::text[], 1, true, '{}'::jsonb, '', false, 0, '', true, 640);
  perform public.upsert_item_catalog_entry('Shortbow', 'weapon', 'Common', 'Light Weapons', array[]::text[], 1, true, '{}'::jsonb, '', false, 0, '', true, 650);
  perform public.upsert_item_catalog_entry('Custom Light Weapon', 'weapon', 'Common', 'Light Weapons', array[]::text[], 1, true, '{}'::jsonb, '', false, 0, '', true, 660);
  perform public.upsert_item_catalog_entry('Sword', 'weapon', 'Common', 'Medium Weapons', array[]::text[], 1, true, '{}'::jsonb, '', false, 0, '', true, 670);
  perform public.upsert_item_catalog_entry('Spear', 'weapon', 'Common', 'Medium Weapons', array[]::text[], 1, true, '{}'::jsonb, '', false, 0, '', true, 680);
  perform public.upsert_item_catalog_entry('Longbow', 'weapon', 'Common', 'Medium Weapons', array[]::text[], 1, true, '{}'::jsonb, '', false, 0, '', true, 690);
  perform public.upsert_item_catalog_entry('Custom Medium Weapon', 'weapon', 'Common', 'Medium Weapons', array[]::text[], 1, true, '{}'::jsonb, '', false, 0, '', true, 700);
  perform public.upsert_item_catalog_entry('Battleaxe', 'weapon', 'Common', 'Heavy Weapons', array[]::text[], 1, true, '{}'::jsonb, '', true, 0, '', true, 710);
  perform public.upsert_item_catalog_entry('Mace', 'weapon', 'Common', 'Heavy Weapons', array[]::text[], 1, true, '{}'::jsonb, '', true, 0, '', true, 720);
  perform public.upsert_item_catalog_entry('Claymore', 'weapon', 'Common', 'Heavy Weapons', array[]::text[], 1, true, '{}'::jsonb, '', true, 0, '', true, 730);
  perform public.upsert_item_catalog_entry('Crossbow', 'weapon', 'Common', 'Heavy Weapons', array[]::text[], 1, true, '{}'::jsonb, '', true, 0, '', true, 740);
  perform public.upsert_item_catalog_entry('Custom Heavy Weapon', 'weapon', 'Common', 'Heavy Weapons', array[]::text[], 1, true, '{}'::jsonb, '', true, 0, '', true, 750);
  perform public.upsert_item_catalog_entry('Magic Bow', 'weapon', 'Common', 'Magecraft Commissions', array[]::text[], 1, true, '{}'::jsonb, '', false, 0, '', true, 760);
  perform public.upsert_item_catalog_entry('Magic Longbow', 'weapon', 'Common', 'Magecraft Commissions', array[]::text[], 1, true, '{}'::jsonb, '', false, 0, '', true, 770);
  perform public.upsert_item_catalog_entry('Wand', 'weapon', 'Common', 'Magecraft Commissions', array[]::text[], 1, true, '{}'::jsonb, '', false, 0, '', true, 780);
  perform public.upsert_item_catalog_entry('Scepter', 'weapon', 'Common', 'Magecraft Commissions', array[]::text[], 1, true, '{}'::jsonb, '', false, 0, '', true, 790);
  perform public.upsert_item_catalog_entry('Staff', 'weapon', 'Common', 'Magecraft Commissions', array[]::text[], 1, true, '{}'::jsonb, '', false, 0, '', true, 800);
  perform public.upsert_item_catalog_entry('Custom Magecraft Commission', 'weapon', 'Common', 'Magecraft Commissions', array[]::text[], 1, true, '{}'::jsonb, '', false, 0, '', true, 810);
  perform public.upsert_item_catalog_entry('Shield', 'shield', 'Common', 'Shield Creation', array[]::text[], 1, true, '{}'::jsonb, '', false, 0, '', true, 820);
  perform public.upsert_item_catalog_entry('Leather Armor', 'armor', 'Common', 'Armor Creation', array['-1 Vitality']::text[], 1, true, jsonb_build_object('vitality', -1), 'Leather', false, 0, 'Flexible baseline armor.', true, 830);
  perform public.upsert_item_catalog_entry('Iron Armor', 'armor', 'Common', 'Armor Creation', array['-1 Agility']::text[], 1, true, jsonb_build_object('agility', -1), 'Iron', false, 0, 'Heavy city-forged armor.', true, 840);
  perform public.upsert_item_catalog_entry('Steel Armor', 'armor', 'Uncommon', 'Armor Creation', array['+1 Vitality']::text[], 1, true, jsonb_build_object('vitality', 1), 'Steel', false, 0, 'Reinforced steel armor.', true, 850);
  perform public.upsert_item_catalog_entry('Mythril Armor', 'armor', 'Rare', 'Armor Creation', array['Enhanceable']::text[], 1, true, '{}'::jsonb, 'Mythril', false, 0, 'Mythril armor can be enhanced.', true, 860);
  perform public.upsert_item_catalog_entry('Vaylium Armor', 'armor', 'Epic', 'Armor Creation', array['+3 Intelligence', '+1 Magic Resist']::text[], 1, true, jsonb_build_object('intelligence', 3, 'magic_resist', 1), 'Vaylium', false, 0, 'Armor tuned for arcane defence.', true, 870);
  perform public.upsert_item_catalog_entry('Dragonscale Armor', 'armor', 'Legendary', 'Armor Creation', array['+2 Vitality', '+5 Magic Resist']::text[], 1, true, jsonb_build_object('vitality', 2, 'magic_resist', 5), 'Dragonscale', false, 0, 'Legendary armor with immense magical resilience.', true, 880);
end $$;

update public.item_catalog
set item_type = public.normalize_item_type(item_type);

delete from public.item_catalog
where item_key = 'mountian-rune';

-- Alchemy and potion foundation.

create table if not exists public.alchemy_potion_definitions (
  property_key text primary key,
  potion_name text not null unique,
  description text not null default '',
  automated_effect text not null default '',
  display_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.alchemy_potion_definitions enable row level security;
revoke all on public.alchemy_potion_definitions from anon, authenticated;

drop trigger if exists alchemy_potion_definitions_touch_updated_at on public.alchemy_potion_definitions;
create trigger alchemy_potion_definitions_touch_updated_at
before update on public.alchemy_potion_definitions
for each row execute function public.touch_updated_at();

insert into public.alchemy_potion_definitions (property_key, potion_name, description, automated_effect, display_order)
values
  ('Healing', 'Healing', 'Restores health when consumed.', 'health', 10),
  ('Speed', 'Swiftness', 'Lesser +1 Speed. Greater +2 Speed. Greatest +5 Speed.', '', 20),
  ('Agility', 'Agility', 'Lesser +1 Agility. Greater +2 Agility. Greatest +5 Agility.', '', 30),
  ('Strength', 'Strength', 'Lesser +1 Strength. Greater +2 Strength. Greatest +5 Strength.', '', 40),
  ('Sorcery', 'Sorcery', 'Lesser +1 Intelligence. Greater +2 Intelligence. Greatest +5 Intelligence.', '', 50),
  ('Mana Regen', 'Mana', 'Restores mana when consumed.', 'mana', 60),
  ('Luck', 'Luck', 'Lesser +1 Rolls. Greater +3 Rolls. Greatest +5 Rolls.', '', 70),
  ('Antidote', 'Antidote', 'Lesser removes poison. Greater removes poison and grants poison resistance for 3 turns. Greatest removes poison and grants poison immunity for 1 scene.', '', 80),
  ('Warming', 'Warming', 'Lesser protects from cold for 1 scene or travel stretch. Greater protects from extreme cold for 1 scene or travel stretch. Greatest protects from cold, frost damage, and frost-based slowing for 1 scene.', '', 90),
  ('Cooling', 'Cooling', 'Lesser protects from heat for 1 scene or travel stretch. Greater protects from extreme heat for 1 scene or travel stretch. Greatest protects from heat, fire damage, and burning for 1 scene.', '', 100),
  ('Night-Eye', 'Night-Eye', 'Lesser allows better sight in darkness for 1 scene. Greater allows clear sight in darkness for 1 scene. Greatest allows clear sight in magical or unnatural darkness for 1 scene.', '', 110),
  ('Thickskin', 'Thickskin', 'Lesser +1 Armor for 3 turns. Greater +2 Armor for 3 turns. Greatest +4 Armor for 3 turns.', '', 120),
  ('Clear-Mind', 'Clear-Mind', 'Lesser +1 Magic Res for 3 turns. Greater +2 Magic Res for 3 turns. Greatest +4 Magic Res for 3 turns.', '', 130),
  ('Wake-Up', 'Wake-Up', 'Lesser wakes an unconscious or magically sleeping target. If unconscious from damage, they wake at 1 HP. Greater wakes the target at 10 HP. Greatest wakes the target at 25 HP.', '', 140),
  ('Clotting', 'Clotting', 'Lesser stops bleeding effects. Greater stops bleeding effects and restores 10 Health. Greatest stops bleeding effects, restores 25 Health, and prevents bleeding for 1 scene.', '', 150)
on conflict (property_key) do update
set potion_name = excluded.potion_name,
    description = excluded.description,
    automated_effect = excluded.automated_effect,
    display_order = excluded.display_order;

create or replace function public.normalize_item_name(p_item_name text)
returns text
language sql
immutable
as $$
  select case
    when lower(trim(coalesce(p_item_name, ''))) in ('glass flask', 'glass flasks', 'empty flasks') then 'Empty Flask'
    when lower(trim(coalesce(p_item_name, ''))) = 'mana recovery potion' then 'Mana Potion'
    when lower(trim(coalesce(p_item_name, ''))) = 'lesser mana recovery potion' then 'Lesser Mana Potion'
    when lower(trim(coalesce(p_item_name, ''))) = 'greater mana recovery potion' then 'Greater Mana Potion'
    when lower(trim(coalesce(p_item_name, ''))) = 'greatest mana recovery potion' then 'Greatest Mana Potion'
    when lower(trim(coalesce(p_item_name, ''))) = 'greatest thinkskin potion' then 'Greatest Thickskin Potion'
    when lower(trim(coalesce(p_item_name, ''))) = 'lesser scorcery potion' then 'Lesser Sorcery Potion'
    when lower(trim(coalesce(p_item_name, ''))) = 'greater scorcery potion' then 'Greater Sorcery Potion'
    when lower(trim(coalesce(p_item_name, ''))) = 'greatest scorcery potion' then 'Greatest Sorcery Potion'
    when lower(trim(coalesce(p_item_name, ''))) = 'fine clothe' then 'Fine Cloth'
    when lower(trim(coalesce(p_item_name, ''))) = 'cooking pots' then 'Cooking Pots'
    when lower(trim(coalesce(p_item_name, ''))) = 'ink and paper' then 'Ink and Paper'
    when lower(trim(coalesce(p_item_name, ''))) = 'standard hammer' then 'Standard Hammer'
    when lower(trim(coalesce(p_item_name, ''))) = 'standard axe' then 'Standard Axe'
    when lower(trim(coalesce(p_item_name, ''))) = 'winter wear' then 'Winter Wear'
    when lower(trim(coalesce(p_item_name, ''))) = 'heat wear' then 'Heat Wear'
    when lower(trim(coalesce(p_item_name, ''))) = 'rainproof wear' then 'Rainproof Wear'
    when lower(trim(coalesce(p_item_name, ''))) = 'basic meal' then 'Basic Meal'
    when lower(trim(coalesce(p_item_name, ''))) = 'tavern meal' then 'Tavern Meal'
    when lower(trim(coalesce(p_item_name, ''))) = 'fine inn' then 'Fine Inn'
    else trim(coalesce(p_item_name, ''))
  end
$$;

create or replace function public.potion_strength_from_name(p_item_name text)
returns text
language sql
stable
set search_path = public
as $$
  select case
    when lower(public.normalize_item_name(p_item_name)) like 'lesser % potion%' then 'Lesser'
    when lower(public.normalize_item_name(p_item_name)) like 'greater % potion%' then 'Greater'
    when lower(public.normalize_item_name(p_item_name)) like 'greatest % potion%' then 'Greatest'
    else null
  end
$$;

create or replace function public.potion_quality_from_name(p_item_name text)
returns text
language sql
stable
set search_path = public
as $$
  select nullif(
    initcap(trim(substring(public.normalize_item_name(p_item_name) from '\(([^)]*)\)'))),
    ''
  )
$$;

create or replace function public.potion_property_from_name(p_item_name text)
returns text
language sql
stable
set search_path = public
as $$
  select d.property_key
  from public.alchemy_potion_definitions d
  where lower(public.normalize_item_name(p_item_name)) like '%' || lower(d.potion_name) || ' potion%'
  order by length(d.potion_name) desc
  limit 1
$$;

create or replace function public.potion_rarity_for_strength(p_strength text)
returns public.item_rarity
language sql
immutable
as $$
  select case lower(trim(coalesce(p_strength, '')))
    when 'lesser' then 'Uncommon'::public.item_rarity
    when 'greater' then 'Rare'::public.item_rarity
    when 'greatest' then 'Legendary'::public.item_rarity
    else 'Common'::public.item_rarity
  end
$$;

create or replace function public.potion_rarity_for(
  p_strength text,
  p_property_key text default null
)
returns public.item_rarity
language sql
immutable
as $$
  select case
    when lower(trim(coalesce(p_property_key, ''))) = 'luck'
      and lower(trim(coalesce(p_strength, ''))) in ('lesser', 'greater') then 'Legendary'::public.item_rarity
    when lower(trim(coalesce(p_property_key, ''))) = 'luck'
      and lower(trim(coalesce(p_strength, ''))) = 'greatest' then 'Mythical'::public.item_rarity
    else public.potion_rarity_for_strength(p_strength)
  end
$$;

create or replace function public.format_potion_item_name(
  p_strength text,
  p_property_key text,
  p_quality text default null
)
returns text
language sql
stable
set search_path = public
as $$
  select concat_ws(
    ' ',
    initcap(lower(trim(coalesce(p_strength, '')))),
    coalesce((select d.potion_name from public.alchemy_potion_definitions d where d.property_key = p_property_key), trim(coalesce(p_property_key, ''))),
    'Potion'
  ) || case
    when p_property_key in ('Healing', 'Mana Regen') then ''
    when nullif(trim(coalesce(p_quality, '')), '') is null then ''
    else ' (' || initcap(lower(trim(p_quality))) || ')'
  end
$$;

create or replace function public.potion_metadata_for_name(p_item_name text)
returns jsonb
language sql
stable
set search_path = public
as $$
  select jsonb_build_object(
    'strength', public.potion_strength_from_name(p_item_name),
    'property', public.potion_property_from_name(p_item_name),
    'quality', public.potion_quality_from_name(p_item_name)
  )
$$;

create or replace function public.catalyst_bonus_for_rarity(p_rarity public.item_rarity)
returns int
language sql
immutable
as $$
  select case p_rarity
    when 'Common' then 1
    when 'Uncommon' then 2
    when 'Rare' then 3
    when 'Epic' then 3
    when 'Legendary' then 4
    when 'Mythical' then 4
    else 0
  end
$$;

do $$
declare
  v_definition record;
  v_strength record;
begin
  perform public.upsert_item_catalog_entry('Empty Flask', 'potion', 'Common', 'Alchemy Supplies', array['Brewing vessel']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Empty byproduct of drinking a potion.', true, 900);
  perform public.upsert_item_catalog_entry('Arcane Nector', 'potion', 'Uncommon', 'Alchemy Supplies', array['Potion canvas']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Required canvas for every brewed potion.', true, 901);

  for v_definition in select * from public.alchemy_potion_definitions order by display_order loop
    for v_strength in
      select * from (values
        ('Lesser', 910),
        ('Greater', 920),
        ('Greatest', 930)
      ) as strength_values(strength_name, order_offset)
    loop
      perform public.upsert_item_catalog_entry(
        public.format_potion_item_name(v_strength.strength_name, v_definition.property_key, null),
        'potion',
        public.potion_rarity_for(v_strength.strength_name, v_definition.property_key)::text,
        'Potion',
        array[v_definition.property_key]::text[],
        1,
        true,
        '{}'::jsonb,
        '',
        false,
        0,
        v_definition.description,
        true,
        v_strength.order_offset + v_definition.display_order
      );
    end loop;
  end loop;
end $$;

update public.inventory_items
set item_type = public.normalize_item_type(item_type),
    item_name = case when item_name = 'Mountian Rune' then 'Mountain Rune' else public.normalize_item_name(item_name) end,
    potion_strength = case when public.normalize_item_type(item_type) = 'potion' then coalesce(potion_strength, public.potion_strength_from_name(item_name)) else potion_strength end,
    potion_property = case when public.normalize_item_type(item_type) = 'potion' then coalesce(potion_property, public.potion_property_from_name(item_name)) else potion_property end,
    potion_quality = case
      when public.normalize_item_type(item_type) <> 'potion' then potion_quality
      when public.potion_property_from_name(item_name) in ('Healing', 'Mana Regen') then null
      when lower(public.normalize_item_name(item_name)) = 'empty flask' then null
      else coalesce(potion_quality, public.potion_quality_from_name(item_name))
    end;

update public.inventory_items
set item_type = 'potion',
    rarity = case when lower(item_name) = 'arcane nector' then 'Uncommon'::public.item_rarity else 'Common'::public.item_rarity end,
    potion_strength = null,
    potion_property = null,
    potion_quality = null
where lower(item_name) in ('empty flask', 'arcane nector');

drop function if exists public.loadout_slot_accepts_item(text, text);

create or replace function public.loadout_slot_accepts_item(p_loadout_slot text, p_item_type text, p_is_accessory boolean default false)
returns boolean
language sql
immutable
as $$
  select case
    when p_loadout_slot = 'weapon' then p_item_type = 'weapon'::text
    when p_loadout_slot = 'armor' then p_item_type = 'armor'::text
    when p_loadout_slot = 'shield' then p_item_type = 'shield'::text
    when p_loadout_slot = 'active-pet' then p_item_type = 'pet'::text
    when p_loadout_slot in ('accessory-1', 'accessory-2', 'accessory-3', 'accessory-4') then p_item_type = 'accessory'::text or coalesce(p_is_accessory, false)
    else false
  end
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

create or replace function public.wallet_balances_for_character(p_character_id uuid)
returns jsonb
language sql
stable
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'unit', jsonb_build_object(
      'id', u.id,
      'systemKey', u.currency_system_key,
      'key', u.unit_key,
      'name', u.name,
      'symbol', u.symbol,
      'order', u.unit_order
    ),
    'amount', coalesce(b.amount, 0)
  ) order by u.unit_order), '[]'::jsonb)
  from public.currency_units u
  left join public.character_wallet_balances b on b.currency_unit_id = u.id and b.character_id = p_character_id
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
  select * into v_profile
  from public.profile_from_campaign_session(p_session_token);

  if v_profile.id is null then
    raise exception 'Invalid or expired session.';
  end if;

  if not exists (select 1 from public.characters where id = p_character_id) then
    raise exception 'Character not found.';
  end if;

  perform public.ensure_dm_testing_wallet(p_character_id);

  return jsonb_build_object(
    'items', (
      select coalesce(jsonb_agg(public.inventory_item_record_to_json(i) order by coalesce(i.loadout_slot, ''), coalesce(i.parent_item_id, '00000000-0000-0000-0000-000000000000'::uuid), i.slot_index, i.item_name), '[]'::jsonb)
      from public.inventory_items i
      where i.character_id = p_character_id
    ),
    'wallet', public.wallet_balances_for_character(p_character_id)
  );
end;
$$;

create or replace function public.assert_inventory_access(
  p_profile public.profiles,
  p_character_id uuid,
  p_dm_only boolean default false
)
returns public.characters
language plpgsql
security definer
set search_path = public
as $$
declare
  v_character public.characters%rowtype;
begin
  select * into v_character
  from public.characters
  where id = p_character_id;

  if v_character.id is null then
    raise exception 'Character not found.';
  end if;

  if p_dm_only and p_profile.role <> 'dm'::public.user_role then
    raise exception 'Only the Dungeon Master can do that.';
  end if;

  if not p_dm_only and p_profile.role <> 'dm'::public.user_role and v_character.owner_user_id is distinct from p_profile.id then
    raise exception 'You can only manage your own character inventory.';
  end if;

  return v_character;
end;
$$;

create or replace function public.find_first_free_inventory_slot(
  p_character_id uuid,
  p_parent_item_id uuid,
  p_capacity int
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_slot int;
begin
  if p_capacity <= 0 then
    return null;
  end if;

  for v_slot in 0..greatest(p_capacity - 1, 0) loop
    if not exists (
      select 1
      from public.inventory_items i
      where i.character_id = p_character_id
        and coalesce(i.parent_item_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(p_parent_item_id, '00000000-0000-0000-0000-000000000000'::uuid)
        and i.loadout_slot is null
        and i.slot_index = v_slot
    ) then
      return v_slot;
    end if;
  end loop;

  return null;
end;
$$;

create or replace function public.assert_inventory_slot_capacity(
  p_character public.characters,
  p_parent_item_id uuid,
  p_slot_index int
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_capacity int;
begin
  if p_slot_index < 0 then
    raise exception 'Inventory slot is invalid.';
  end if;

  if p_parent_item_id is null then
    v_capacity := p_character.inventory_slots;
  else
    select i.storage_capacity into v_capacity
    from public.inventory_items i
    where i.id = p_parent_item_id
      and i.character_id = p_character.id
      and public.inventory_item_can_hold_children(i);

    if v_capacity is null then
      raise exception 'Storage container not found.';
    end if;
  end if;

  if p_slot_index >= v_capacity then
    raise exception 'Inventory slot is outside the container capacity.';
  end if;

  return v_capacity;
end;
$$;

create or replace function public.next_storage_container_slot(p_character_id uuid)
returns int
language sql
stable
as $$
  select coalesce(min(i.slot_index), 0) - 1
  from public.inventory_items i
  where i.character_id = p_character_id
    and i.parent_item_id is null
    and i.loadout_slot is null
    and i.slot_index < 0
$$;

create or replace function public.character_storage_container_exists(
  p_character_id uuid,
  p_item_name text
)
returns boolean
language sql
stable
as $$
  select exists (
    select 1
    from public.inventory_items i
    where i.character_id = p_character_id
      and i.parent_item_id is null
      and i.loadout_slot is null
      and i.item_type = 'storage'::text
      and i.is_storage = true
      and i.storage_active = true
      and public.additional_storage_kind(i.item_name, i.item_type) = public.additional_storage_kind(p_item_name, 'storage')
      and public.additional_storage_kind(p_item_name, 'storage') is not null
  )
$$;

create or replace function public.inventory_items_stackable(a public.inventory_items, b public.inventory_items)
returns boolean
language sql
stable
as $$
  select lower(public.normalize_item_name(a.item_name)) = lower(public.normalize_item_name(b.item_name))
    and public.normalize_item_type(a.item_type) = public.normalize_item_type(b.item_type)
    and a.rarity = b.rarity
    and coalesce(a.enchantment, '') = coalesce(b.enchantment, '')
    and coalesce(a.rune_name, '') = coalesce(b.rune_name, '')
    and coalesce(a.material, '') = coalesce(b.material, '')
    and coalesce(a.potion_strength, '') = coalesce(b.potion_strength, '')
    and coalesce(a.potion_property, '') = coalesce(b.potion_property, '')
    and coalesce(a.potion_quality, '') = coalesce(b.potion_quality, '')
    and a.enhancement_count = b.enhancement_count
    and a.is_two_handed = b.is_two_handed
    and a.is_accessory = b.is_accessory
    and a.modifiers = b.modifiers
    and a.item_type <> 'pet'
    and b.item_type <> 'pet'
    and a.is_storage = false
    and b.is_storage = false
    and public.item_catalog_stackable(a.item_name, a.item_type)
    and public.item_catalog_stackable(b.item_name, b.item_type)
$$;

create or replace function public.inventory_item_is_mythril(
  p_item_name text,
  p_material text
)
returns boolean
language sql
immutable
as $$
  select lower(concat_ws(' ', coalesce(p_material, ''), coalesce(p_item_name, ''))) like '%mythril%'
$$;

create or replace function public.inventory_item_is_wagon(
  p_item_name text,
  p_item_type text
)
returns boolean
language sql
immutable
as $$
  select lower(coalesce(p_item_type, '')) = 'storage'
    and lower(coalesce(p_item_name, '')) like '%wagon%'
    and lower(coalesce(p_item_name, '')) not like '%wagon home%'
    and lower(coalesce(p_item_name, '')) not like '%caged wagon%'
$$;

create or replace function public.inventory_item_is_mobile_home_storage(
  p_item_name text,
  p_item_type text
)
returns boolean
language sql
immutable
as $$
  select lower(coalesce(p_item_type, '')) = 'storage'
    and lower(coalesce(p_item_name, '')) like '%wagon home%'
$$;

create or replace function public.inventory_item_is_caged_wagon_storage(
  p_item_name text,
  p_item_type text
)
returns boolean
language sql
immutable
as $$
  select lower(coalesce(p_item_type, '')) = 'storage'
    and lower(coalesce(p_item_name, '')) like '%caged wagon%'
$$;

drop function if exists public.add_character_inventory_item(text, uuid, uuid, int, text, text, text, numeric, boolean, int, jsonb, text);
drop function if exists public.add_character_inventory_item(text, uuid, uuid, int, text, text, text, numeric, boolean, int, jsonb, text, text, int, boolean);
drop function if exists public.add_character_inventory_item(text, uuid, uuid, int, text, text, text, numeric, boolean, int, jsonb, text, text, int, boolean, text, text, text);
drop function if exists public.add_character_inventory_item(text, uuid, uuid, int, text, text, text, numeric, boolean, int, jsonb, text, text, int, boolean, text, text, text, text);
drop function if exists public.add_character_inventory_item(text, uuid, uuid, int, text, text, text, numeric, boolean, int, jsonb, text, text, int, boolean, text, text, text, text, boolean);

create or replace function public.add_character_inventory_item(
  p_session_token text,
  p_character_id uuid,
  p_parent_item_id uuid,
  p_slot_index int,
  p_item_name text,
  p_item_type text,
  p_rarity text,
  p_quantity numeric,
  p_is_storage boolean default false,
  p_storage_capacity int default 0,
  p_modifiers jsonb default '{}'::jsonb,
  p_enchantment text default null,
  p_material text default null,
  p_enhancement_count int default 0,
  p_is_two_handed boolean default false,
  p_potion_strength text default null,
  p_potion_property text default null,
  p_potion_quality text default null,
  p_item_description text default null,
  p_is_accessory boolean default false
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
  v_catalog public.item_catalog%rowtype;
  v_item_name text := public.normalize_item_name(p_item_name);
  v_item_type text;
  v_quantity numeric := greatest(0.5, coalesce(p_quantity, 1));
  v_rarity public.item_rarity;
  v_modifiers jsonb;
  v_material text := '';
  v_is_two_handed boolean := false;
  v_is_accessory boolean := coalesce(p_is_accessory, false);
  v_enhancement_count int := least(3, greatest(0, coalesce(p_enhancement_count, 0)));
  v_storage_capacity int := greatest(0, coalesce(p_storage_capacity, 0));
  v_make_storage_container boolean := false;
  v_storage_item public.inventory_items%rowtype;
  v_storage_kind text;
  v_storage_should_activate boolean := false;
  v_normal_slot int;
  v_potion_strength text;
  v_potion_property text;
  v_potion_quality text;
  v_item_description text := left(trim(coalesce(p_item_description, '')), 1500);
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;

  v_character := public.assert_inventory_access(v_profile, p_character_id, true);

  if length(trim(coalesce(v_item_name, ''))) = 0 then
    raise exception 'Item name is required.';
  end if;

  select * into v_catalog
  from public.item_catalog
  where item_key = public.catalog_key_for_name(v_item_name)
  limit 1;

  v_item_type := public.normalize_item_type(coalesce(nullif(p_item_type, ''), v_catalog.item_type, 'misc'));
  v_rarity := coalesce(nullif(p_rarity, ''), coalesce(v_catalog.rarity::text, 'Common'))::public.item_rarity;
  v_modifiers := case when jsonb_typeof(coalesce(p_modifiers, '{}'::jsonb)) = 'object' then coalesce(p_modifiers, '{}'::jsonb) else '{}'::jsonb end;

  if v_catalog.id is not null then
    v_modifiers := v_catalog.default_modifiers || v_modifiers;
    v_material := v_catalog.material;
    v_is_two_handed := v_catalog.is_two_handed;
    v_storage_capacity := greatest(v_storage_capacity, v_catalog.storage_capacity);
  end if;

  if length(trim(coalesce(p_material, ''))) > 0 then
    v_material := trim(p_material);
  end if;
  v_is_two_handed := coalesce(p_is_two_handed, false) or v_is_two_handed;
  if length(trim(coalesce(p_enchantment, ''))) > 0 then
    v_enhancement_count := 0;
  end if;

  if v_item_type = 'potion' then
    v_potion_strength := coalesce(nullif(trim(coalesce(p_potion_strength, '')), ''), public.potion_strength_from_name(v_item_name));
    v_potion_property := coalesce(nullif(trim(coalesce(p_potion_property, '')), ''), public.potion_property_from_name(v_item_name));
    v_potion_quality := case
      when coalesce(nullif(trim(coalesce(p_potion_property, '')), ''), public.potion_property_from_name(v_item_name)) in ('Healing', 'Mana Regen') then null
      when lower(v_item_name) = 'empty flask' then null
      else coalesce(nullif(trim(coalesce(p_potion_quality, '')), ''), public.potion_quality_from_name(v_item_name))
    end;

    if v_potion_strength is not null and v_potion_property is not null then
      v_item_name := public.format_potion_item_name(v_potion_strength, v_potion_property, v_potion_quality);
      v_rarity := public.potion_rarity_for(v_potion_strength, v_potion_property);
    end if;
  end if;

  v_quantity := public.assert_valid_item_quantity(v_item_name, v_item_type, v_quantity);
  if v_item_type = 'storage'::text then
    v_quantity := 1;
  end if;

  if v_item_type = 'pet' then
    return public.place_pet_item_for_character(
      v_character.id,
      v_item_name,
      null,
      v_item_description,
      v_rarity,
      v_quantity,
      v_is_accessory,
      v_modifiers,
      nullif(trim(coalesce(p_enchantment, '')), ''),
      null,
      v_material,
      v_enhancement_count,
      v_is_two_handed
    );
  end if;

  v_make_storage_container := v_item_type = 'storage'::text
    and coalesce(p_is_storage, false)
    and p_parent_item_id is null;

  if v_make_storage_container then
    v_storage_kind := public.additional_storage_kind(v_item_name, v_item_type);
    v_storage_should_activate := v_storage_kind is null
      or not public.character_storage_container_exists(p_character_id, v_item_name);
    v_normal_slot := case
      when v_storage_should_activate then null
      else coalesce(p_slot_index, public.find_first_free_inventory_slot(v_character.id, null, v_character.inventory_slots))
    end;
    if not v_storage_should_activate and v_normal_slot is null then
      raise exception 'Inventory full.';
    end if;

    insert into public.inventory_items (
      character_id, parent_item_id, slot_index, item_name, item_type, rarity, quantity,
      item_description, is_accessory, is_storage, storage_active, storage_capacity, modifiers, enchantment, material, enhancement_count,
      is_two_handed, potion_strength, potion_property, potion_quality
    )
    values (
      p_character_id,
      null,
      case when v_storage_should_activate then public.next_storage_container_slot(p_character_id) else v_normal_slot end,
      v_item_name, v_item_type, v_rarity, 1,
      v_item_description, v_is_accessory, true, v_storage_should_activate, greatest(1, coalesce(nullif(v_storage_capacity, 0), 6)), v_modifiers,
      nullif(trim(coalesce(p_enchantment, '')), ''), v_material, v_enhancement_count,
      v_is_two_handed, v_potion_strength, v_potion_property, v_potion_quality
    )
    returning * into v_storage_item;

    v_quantity := v_quantity - 1;
    if v_quantity <= 0 then
      return public.inventory_item_record_to_json(v_storage_item);
    end if;
  end if;

  perform public.assert_inventory_slot_capacity(v_character, p_parent_item_id, p_slot_index);

  select * into v_target
  from public.inventory_items i
  where i.character_id = p_character_id
    and coalesce(i.parent_item_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(p_parent_item_id, '00000000-0000-0000-0000-000000000000'::uuid)
    and i.loadout_slot is null
    and i.slot_index = p_slot_index
  limit 1;

  if v_target.id is not null then
    if lower(public.normalize_item_name(v_target.item_name)) = lower(public.normalize_item_name(v_item_name))
      and coalesce(v_target.display_name, '') = ''
      and public.normalize_item_type(v_target.item_type) = public.normalize_item_type(v_item_type)
      and v_target.rarity = v_rarity
      and coalesce(v_target.enchantment, '') = coalesce(nullif(trim(p_enchantment), ''), '')
      and coalesce(v_target.rune_name, '') = ''
      and coalesce(v_target.material, '') = coalesce(v_material, '')
      and coalesce(v_target.potion_strength, '') = coalesce(v_potion_strength, '')
      and coalesce(v_target.potion_property, '') = coalesce(v_potion_property, '')
      and coalesce(v_target.potion_quality, '') = coalesce(v_potion_quality, '')
      and v_target.enhancement_count = v_enhancement_count
      and v_target.is_two_handed = v_is_two_handed
      and v_target.modifiers = v_modifiers
      and v_target.is_storage = false
      and public.item_catalog_stackable(v_item_name, v_item_type)
    then
      update public.inventory_items
      set quantity = quantity + v_quantity
      where id = v_target.id
      returning * into v_item;
      return public.inventory_item_record_to_json(v_item);
    end if;

    raise exception 'That inventory slot is already occupied.';
  end if;

  insert into public.inventory_items (
    character_id, parent_item_id, slot_index, item_name, item_type, rarity, quantity,
    item_description, is_accessory, is_storage, storage_capacity, modifiers, enchantment, material, enhancement_count,
    is_two_handed, potion_strength, potion_property, potion_quality
  )
  values (
    p_character_id, p_parent_item_id, p_slot_index, v_item_name, v_item_type, v_rarity, v_quantity,
    v_item_description, v_is_accessory, false, 0, v_modifiers, nullif(trim(coalesce(p_enchantment, '')), ''), v_material, v_enhancement_count,
    v_is_two_handed, v_potion_strength, v_potion_property, v_potion_quality
  )
  returning * into v_item;

  return public.inventory_item_record_to_json(v_item);
end;
$$;

create or replace function public.update_inventory_item_state(
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
  v_item public.inventory_items%rowtype;
  v_parent_item public.inventory_items%rowtype;
  v_target public.inventory_items%rowtype;
  v_character public.characters%rowtype;
  v_patch jsonb := coalesce(p_patch, '{}'::jsonb);
  v_parent_item_id uuid;
  v_slot_index int;
  v_loadout_slot text;
  v_capacity int;
  v_original_parent_item_id uuid;
  v_original_slot_index int;
  v_fallback_slot_index int;
  v_temporary_slot_index int;
  v_storage_kind text;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;

  select * into v_item from public.inventory_items where id = p_item_id;
  if v_item.id is null then raise exception 'Item not found.'; end if;

  v_character := public.assert_inventory_access(v_profile, v_item.character_id, false);

  if (v_patch ? 'name' or v_patch ? 'type' or v_patch ? 'rarity' or v_patch ? 'quantity' or v_patch ? 'isStorage' or v_patch ? 'isAccessory' or v_patch ? 'storageCapacity' or v_patch ? 'modifiers' or v_patch ? 'enchantment' or v_patch ? 'material' or v_patch ? 'enhancementCount' or v_patch ? 'isTwoHanded' or v_patch ? 'potionStrength' or v_patch ? 'potionProperty' or v_patch ? 'potionQuality' or v_patch ? 'itemDescription') and v_profile.role <> 'dm'::public.user_role then
    raise exception 'Only the Dungeon Master can edit item details.';
  end if;

  if v_patch ? 'spellBookForm'
    and (
      public.normalize_item_type(v_item.item_type) <> 'spell book'
      or lower(public.normalize_item_name(v_item.item_name)) <> lower(public.normalize_item_name('Peaceful Restoration Spell Book'))
    )
  then
    raise exception 'Only Peaceful Restoration spell books can change form.';
  end if;

  if v_patch ? 'storageActive' and (not v_item.is_storage or public.additional_storage_kind(v_item.item_name, v_item.item_type) is null) then
    raise exception 'Only carried additional storage can be activated or packed up.';
  end if;

  if v_item.item_type = 'pet' and coalesce(v_item.loadout_slot, '') <> 'active-pet' then
    raise exception 'Pets can only occupy active pet slots or house stable slots.';
  end if;

  if v_patch ? 'displayName' and v_item.item_type <> 'pet' then
    raise exception 'Only pet items can be named.';
  end if;

  if v_profile.role = 'dm'::public.user_role then
    update public.inventory_items
    set
      item_name = case when v_patch ? 'name' then public.normalize_item_name(coalesce(nullif(trim(v_patch->>'name'), ''), item_name)) else item_name end,
      item_type = case when v_patch ? 'type' then public.normalize_item_type(v_patch->>'type') else item_type end,
      rarity = case when v_patch ? 'rarity' then (v_patch->>'rarity')::public.item_rarity else rarity end,
      quantity = case when v_patch ? 'quantity' then public.assert_valid_item_quantity(coalesce(nullif(trim(v_patch->>'name'), ''), item_name), case when v_patch ? 'type' then public.normalize_item_type(v_patch->>'type') else item_type end, (v_patch->>'quantity')::numeric) else quantity end,
      item_description = case when v_patch ? 'itemDescription' then left(trim(coalesce(v_patch->>'itemDescription', '')), 1500) else item_description end,
      is_accessory = case when v_patch ? 'isAccessory' then (v_patch->>'isAccessory')::boolean else is_accessory end,
      is_storage = case when v_patch ? 'isStorage' then (v_patch->>'isStorage')::boolean else is_storage end,
      storage_capacity = case when v_patch ? 'storageCapacity' then greatest(0, (v_patch->>'storageCapacity')::int) else storage_capacity end,
      modifiers = case when v_patch ? 'modifiers' and jsonb_typeof(v_patch->'modifiers') = 'object' then v_patch->'modifiers' else modifiers end,
      enchantment = case
        when v_patch ? 'enhancementCount' and (v_patch->>'enhancementCount')::int > 0 then null
        when v_patch ? 'enchantment' then nullif(trim(coalesce(v_patch->>'enchantment', '')), '')
        else enchantment
      end,
      material = case when v_patch ? 'material' then trim(coalesce(v_patch->>'material', '')) else material end,
      enhancement_count = case
        when v_patch ? 'enchantment' and length(trim(coalesce(v_patch->>'enchantment', ''))) > 0 then 0
        when v_patch ? 'enhancementCount' then least(3, greatest(0, (v_patch->>'enhancementCount')::int))
        else enhancement_count
      end,
      is_two_handed = case when v_patch ? 'isTwoHanded' then (v_patch->>'isTwoHanded')::boolean else is_two_handed end,
      potion_strength = case
        when case when v_patch ? 'type' then public.normalize_item_type(v_patch->>'type') else item_type end <> 'potion' then null
        when v_patch ? 'potionStrength' then nullif(trim(coalesce(v_patch->>'potionStrength', '')), '')
        when v_patch ? 'name' then public.potion_strength_from_name(v_patch->>'name')
        else potion_strength
      end,
      potion_property = case
        when case when v_patch ? 'type' then public.normalize_item_type(v_patch->>'type') else item_type end <> 'potion' then null
        when v_patch ? 'potionProperty' then nullif(trim(coalesce(v_patch->>'potionProperty', '')), '')
        when v_patch ? 'name' then public.potion_property_from_name(v_patch->>'name')
        else potion_property
      end,
      potion_quality = case
        when case when v_patch ? 'type' then public.normalize_item_type(v_patch->>'type') else item_type end <> 'potion' then null
        when coalesce(nullif(trim(coalesce(v_patch->>'potionProperty', '')), ''), potion_property, public.potion_property_from_name(coalesce(v_patch->>'name', item_name))) in ('Healing', 'Mana Regen') then null
        when lower(public.normalize_item_name(coalesce(v_patch->>'name', item_name))) = 'empty flask' then null
        when v_patch ? 'potionQuality' then nullif(trim(coalesce(v_patch->>'potionQuality', '')), '')
        when v_patch ? 'name' then public.potion_quality_from_name(v_patch->>'name')
        else potion_quality
      end,
      spell_book_form = case when v_patch ? 'spellBookForm' then least(2, greatest(1, (v_patch->>'spellBookForm')::int)) else spell_book_form end
    where id = p_item_id
    returning * into v_item;

    if v_item.item_type = 'potion'
      and v_item.potion_strength is not null
      and v_item.potion_property is not null
    then
      update public.inventory_items
      set item_name = public.format_potion_item_name(v_item.potion_strength, v_item.potion_property, v_item.potion_quality),
          rarity = public.potion_rarity_for(v_item.potion_strength, v_item.potion_property)
      where id = v_item.id
      returning * into v_item;
    end if;

    if not public.inventory_item_is_mythril(v_item.item_name, v_item.material)
      and v_item.rune_name is not null
    then
      update public.inventory_items
      set rune_name = null
      where id = v_item.id
      returning * into v_item;
    end if;
  end if;

  if v_patch ? 'displayName' and v_item.item_type <> 'pet' then
    raise exception 'Only pet items can be named.';
  end if;

  if v_patch ? 'displayName' then
    update public.inventory_items
    set display_name = nullif(left(trim(coalesce(v_patch->>'displayName', '')), 80), '')
    where id = p_item_id
    returning * into v_item;
  elsif v_item.item_type <> 'pet' and v_item.display_name is not null then
    update public.inventory_items
    set display_name = null
    where id = p_item_id
    returning * into v_item;
  end if;

  if v_patch ? 'spellBookForm' then
    update public.inventory_items
    set spell_book_form = least(2, greatest(1, (v_patch->>'spellBookForm')::int))
    where id = p_item_id
      and public.normalize_item_type(item_type) = 'spell book'
      and lower(public.normalize_item_name(item_name)) = lower(public.normalize_item_name('Peaceful Restoration Spell Book'))
    returning * into v_item;

    if v_item.id is null then raise exception 'Spell book not found.'; end if;
  end if;

  if v_patch ? 'storageActive' then
    v_storage_kind := public.additional_storage_kind(v_item.item_name, v_item.item_type);
    if coalesce((v_patch->>'storageActive')::boolean, false) then
      if exists (
        select 1 from public.inventory_items i
        where i.character_id = v_item.character_id
          and i.id <> v_item.id
          and i.parent_item_id is null
          and i.loadout_slot is null
          and i.is_storage = true
          and i.storage_active = true
          and public.additional_storage_kind(i.item_name, i.item_type) = v_storage_kind
      ) then
        raise exception 'Only one % can be active additional storage.', v_item.item_name;
      end if;

      update public.inventory_items
      set storage_active = true,
          parent_item_id = null,
          loadout_slot = null,
          slot_index = public.next_storage_container_slot(v_item.character_id)
      where id = p_item_id
      returning * into v_item;
    else
      if exists (select 1 from public.inventory_items child where child.parent_item_id = v_item.id) then
        raise exception 'Empty this storage before packing it up.';
      end if;

      v_slot_index := public.find_first_free_inventory_slot(v_item.character_id, null, v_character.inventory_slots);
      if v_slot_index is null then raise exception 'No open inventory slot.'; end if;

      update public.inventory_items
      set storage_active = false,
          parent_item_id = null,
          loadout_slot = null,
          slot_index = v_slot_index
      where id = p_item_id
      returning * into v_item;
    end if;

    return public.inventory_item_record_to_json(v_item);
  end if;

  if v_patch ? 'loadoutSlot' and not (v_patch ? 'slotIndex' or v_patch ? 'parentItemId') then
    v_loadout_slot := nullif(v_patch->>'loadoutSlot', '');

    if v_loadout_slot is null then
      if v_item.item_type = 'pet' then
        raise exception 'Pets can only occupy active pet slots or house stable slots.';
      end if;

      v_slot_index := public.find_first_free_inventory_slot(v_item.character_id, null, v_character.inventory_slots);
      if v_slot_index is null then raise exception 'No open inventory slot.'; end if;

      update public.inventory_items
      set loadout_slot = null, parent_item_id = null, slot_index = v_slot_index
      where id = p_item_id
      returning * into v_item;

      return public.inventory_item_record_to_json(v_item);
    end if;

    if not public.loadout_slot_accepts_item(v_loadout_slot, v_item.item_type, v_item.is_accessory) then
      raise exception 'That item cannot go in that loadout slot.';
    end if;

    if v_loadout_slot = 'shield'
      and exists (
        select 1 from public.inventory_items i
        where i.character_id = v_item.character_id
          and i.loadout_slot = 'weapon'
          and i.is_two_handed = true
      )
    then
      raise exception 'A shield cannot be active with a heavy two-handed weapon.';
    end if;

    if v_loadout_slot = 'weapon'
      and v_item.is_two_handed = true
      and exists (
        select 1 from public.inventory_items i
        where i.character_id = v_item.character_id
          and i.loadout_slot = 'shield'
      )
    then
      raise exception 'A heavy two-handed weapon cannot be active with a shield.';
    end if;

    if exists (select 1 from public.inventory_items where character_id = v_item.character_id and loadout_slot = v_loadout_slot and id <> v_item.id) then
      raise exception 'That loadout slot is already occupied.';
    end if;

    update public.inventory_items
    set loadout_slot = v_loadout_slot, parent_item_id = null
    where id = p_item_id
    returning * into v_item;

    return public.inventory_item_record_to_json(v_item);
  end if;

  if v_patch ? 'slotIndex' or v_patch ? 'parentItemId' then
    v_original_parent_item_id := v_item.parent_item_id;
    v_original_slot_index := v_item.slot_index;
    v_parent_item_id := case when v_patch ? 'parentItemId' then nullif(v_patch->>'parentItemId', '')::uuid else v_item.parent_item_id end;
    v_slot_index := case when v_patch ? 'slotIndex' then (v_patch->>'slotIndex')::int else v_item.slot_index end;

    if v_item.is_storage
      and public.normalize_item_type(v_item.item_type) = 'storage'
      and v_item.storage_active = true
      and v_parent_item_id is null
      and exists (
        select 1
        from public.inventory_items i
        where i.character_id = v_item.character_id
          and i.id <> v_item.id
          and i.parent_item_id is null
          and i.loadout_slot is null
          and i.is_storage = true
          and i.storage_active = true
          and public.normalize_item_type(i.item_type) = 'storage'
          and public.additional_storage_kind(i.item_name, i.item_type) = public.additional_storage_kind(v_item.item_name, v_item.item_type)
          and public.additional_storage_kind(v_item.item_name, v_item.item_type) is not null
      )
    then
      raise exception 'Only one % can be equipped as additional storage.', v_item.item_name;
    end if;

    if v_item.item_type = 'pet' then
      if v_parent_item_id is null then
        raise exception 'Pets can only occupy active pet slots, house stable slots, or Caged Wagon slots.';
      end if;

      select * into v_parent_item
      from public.inventory_items parent
      where parent.id = v_parent_item_id
        and parent.character_id = v_item.character_id
        and public.inventory_item_can_hold_children(parent);

      if v_parent_item.id is null or lower(v_parent_item.item_name) not like '%caged wagon%' then
        raise exception 'Pets can only occupy active pet slots, house stable slots, or Caged Wagon slots.';
      end if;
    elsif v_parent_item_id is not null then
      select * into v_parent_item
      from public.inventory_items parent
      where parent.id = v_parent_item_id
        and parent.character_id = v_item.character_id
        and public.inventory_item_can_hold_children(parent);

      if v_parent_item.id is not null and public.inventory_item_is_caged_wagon_storage(v_parent_item.item_name, v_parent_item.item_type) then
        raise exception 'Only animals can be placed in a Caged Wagon.';
      end if;
    end if;

    v_capacity := public.assert_inventory_slot_capacity(v_character, v_parent_item_id, v_slot_index);

    select * into v_target
    from public.inventory_items i
    where i.character_id = v_item.character_id
      and coalesce(i.parent_item_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(v_parent_item_id, '00000000-0000-0000-0000-000000000000'::uuid)
      and i.loadout_slot is null
      and i.slot_index = v_slot_index
      and i.id <> v_item.id
    limit 1;

  if v_target.id is not null then
    if public.inventory_items_stackable(v_target, v_item) then
      update public.inventory_items
      set quantity = quantity + v_item.quantity
      where id = v_target.id
      returning * into v_target;

      delete from public.inventory_items
      where id = v_item.id;

      return public.inventory_item_record_to_json(v_target);
    end if;

    select coalesce(min(i.slot_index), 0) - 1 into v_temporary_slot_index
    from public.inventory_items i
    where i.character_id = v_item.character_id
      and coalesce(i.parent_item_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(v_parent_item_id, '00000000-0000-0000-0000-000000000000'::uuid)
      and i.loadout_slot is null;

    update public.inventory_items
    set parent_item_id = v_parent_item_id, slot_index = v_temporary_slot_index
    where id = v_target.id;

      if v_item.loadout_slot is null then
        update public.inventory_items
        set parent_item_id = v_parent_item_id, slot_index = v_slot_index, loadout_slot = null
        where id = p_item_id
        returning * into v_item;

        update public.inventory_items
        set parent_item_id = v_original_parent_item_id, slot_index = v_original_slot_index, loadout_slot = null
        where id = v_target.id;
      else
        update public.inventory_items
        set parent_item_id = v_parent_item_id, slot_index = v_slot_index, loadout_slot = null
        where id = p_item_id
        returning * into v_item;

        v_fallback_slot_index := public.find_first_free_inventory_slot(v_item.character_id, v_parent_item_id, v_capacity);
        if v_fallback_slot_index is null then
          raise exception 'No open inventory slot for the item already there.';
        end if;

        update public.inventory_items
        set parent_item_id = v_parent_item_id, slot_index = v_fallback_slot_index, loadout_slot = null
        where id = v_target.id;
      end if;

      return public.inventory_item_record_to_json(v_item);
    end if;

    update public.inventory_items
    set parent_item_id = v_parent_item_id, slot_index = v_slot_index, loadout_slot = null
    where id = p_item_id
    returning * into v_item;
  end if;

  return public.inventory_item_record_to_json(v_item);
end;
$$;

drop function if exists public.drop_inventory_item_quantity(text, uuid, integer);

create or replace function public.drop_inventory_item_quantity(
  p_session_token text,
  p_item_id uuid,
  p_quantity numeric
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_item public.inventory_items%rowtype;
  v_drop_quantity numeric;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;

  select * into v_item from public.inventory_items where id = p_item_id;
  if v_item.id is null then raise exception 'Item not found.'; end if;

  perform public.assert_inventory_access(v_profile, v_item.character_id, false);

  v_drop_quantity := public.assert_valid_item_quantity(v_item.item_name, v_item.item_type, greatest(0.5, coalesce(p_quantity, 1)));

  if v_drop_quantity >= v_item.quantity then
    delete from public.inventory_items where id = v_item.id;
    return null;
  end if;

  update public.inventory_items
  set quantity = quantity - v_drop_quantity
  where id = v_item.id
  returning * into v_item;

  return public.inventory_item_record_to_json(v_item);
end;
$$;

drop function if exists public.split_inventory_item_stack(text, uuid, numeric, boolean);

create or replace function public.split_inventory_item_stack(
  p_session_token text,
  p_item_id uuid,
  p_quantity numeric,
  p_confirm_drop boolean default false
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
  v_new_item public.inventory_items%rowtype;
  v_quantity numeric;
  v_capacity int;
  v_slot_index int;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;

  select * into v_item
  from public.inventory_items
  where id = p_item_id
  for update;

  if v_item.id is null then raise exception 'Item not found.'; end if;

  v_character := public.assert_inventory_access(v_profile, v_item.character_id, false);

  if v_item.loadout_slot is not null then
    raise exception 'Unequip that item before splitting it.';
  end if;

  if v_item.is_storage or not public.item_catalog_stackable(v_item.item_name, v_item.item_type) then
    raise exception 'That item cannot be split into stacks.';
  end if;

  v_quantity := public.assert_valid_item_quantity(v_item.item_name, v_item.item_type, greatest(0.5, coalesce(p_quantity, 1)));
  if v_quantity >= v_item.quantity then
    raise exception 'Split quantity must leave something in the original stack.';
  end if;

  if v_item.parent_item_id is null then
    v_capacity := v_character.inventory_slots;
  else
    select storage_capacity into v_capacity
    from public.inventory_items
    where id = v_item.parent_item_id
      and character_id = v_item.character_id
      and is_storage = true;

    if v_capacity is null then
      raise exception 'Storage container not found.';
    end if;
  end if;

  v_slot_index := public.find_first_free_inventory_slot(v_item.character_id, v_item.parent_item_id, v_capacity);

  if v_slot_index is null and not coalesce(p_confirm_drop, false) then
    return jsonb_build_object(
      'needsDropConfirmation', true,
      'message', 'No open inventory slot. Split anyway and drop the new stack?',
      'inventory', public.get_character_inventory(p_session_token, v_item.character_id)
    );
  end if;

  update public.inventory_items
  set quantity = quantity - v_quantity
  where id = v_item.id
  returning * into v_item;

  if v_slot_index is null then
    return jsonb_build_object(
      'droppedQuantity', v_quantity,
      'inventory', public.get_character_inventory(p_session_token, v_item.character_id)
    );
  end if;

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
    v_item.character_id,
    v_item.parent_item_id,
    v_slot_index,
    v_item.item_name,
    v_item.display_name,
    v_item.item_description,
    v_item.item_type,
    v_item.rarity,
    v_quantity,
    v_item.is_accessory,
    false,
    0,
    v_item.modifiers,
    v_item.enchantment,
    v_item.rune_name,
    v_item.material,
    v_item.enhancement_count,
    v_item.is_two_handed,
    v_item.potion_strength,
    v_item.potion_property,
    v_item.potion_quality
  )
  returning * into v_new_item;

  return jsonb_build_object(
    'item', public.inventory_item_record_to_json(v_new_item),
    'inventory', public.get_character_inventory(p_session_token, v_item.character_id)
  );
end;
$$;

create or replace function public.set_character_wallet_balances(
  p_session_token text,
  p_character_id uuid,
  p_balances jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_character public.characters%rowtype;
  v_entry jsonb;
  v_unit_id uuid;
  v_amount int;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;

  v_character := public.assert_inventory_access(v_profile, p_character_id, true);

  for v_entry in select * from jsonb_array_elements(coalesce(p_balances, '[]'::jsonb)) loop
    v_unit_id := nullif(v_entry->>'unitId', '')::uuid;
    v_amount := greatest(0, coalesce((v_entry->>'amount')::int, 0));

    if v_unit_id is not null and exists (select 1 from public.currency_units where id = v_unit_id) then
      insert into public.character_wallet_balances (character_id, currency_unit_id, amount)
      values (p_character_id, v_unit_id, v_amount)
      on conflict (character_id, currency_unit_id) do update
      set amount = excluded.amount;
    end if;
  end loop;

  return public.wallet_balances_for_character(p_character_id);
end;
$$;

create or replace function public.gift_character_currency(
  p_session_token text,
  p_sender_character_id uuid,
  p_target_character_id uuid,
  p_currency jsonb
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
  v_currency jsonb := case when jsonb_typeof(coalesce(p_currency, '[]'::jsonb)) = 'array' then coalesce(p_currency, '[]'::jsonb) else '[]'::jsonb end;
  v_entry jsonb;
  v_unit_id uuid;
  v_unit_name text;
  v_amount int;
  v_current int;
  v_labels text[] := array[]::text[];
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;

  v_sender := public.assert_inventory_access(v_profile, p_sender_character_id, false);

  select * into v_target
  from public.characters
  where id = p_target_character_id;

  if v_target.id is null then raise exception 'Target character was not found.'; end if;
  if v_target.id = v_sender.id then raise exception 'Choose another character to gift money to.'; end if;
  if v_target.owner_user_id is null then raise exception 'That character is not assigned to a player.'; end if;

  if v_sender.owner_user_id is distinct from v_target.owner_user_id
    and v_profile.role <> 'dm'::public.user_role
    and not coalesce(v_target.gift_inventory_open, true)
  then
    raise exception 'This persons inventory is closed from gifting efforts and grows tired of your pranks';
  end if;

  for v_entry in select * from jsonb_array_elements(v_currency) loop
    v_unit_name := null;
    v_current := 0;
    v_unit_id := nullif(coalesce(v_entry->>'unitId', v_entry->>'unit_id', v_entry->>'id'), '')::uuid;
    v_amount := floor(greatest(0, coalesce(nullif(v_entry->>'amount', '')::numeric, 0)))::int;
    if v_unit_id is null or v_amount <= 0 then continue; end if;

    select name into v_unit_name
    from public.currency_units
    where id = v_unit_id;

    if v_unit_name is null then raise exception 'A gifted currency unit was not found.'; end if;

    select coalesce(amount, 0) into v_current
    from public.character_wallet_balances
    where character_id = v_sender.id
      and currency_unit_id = v_unit_id
    for update;

    v_current := coalesce(v_current, 0);
    if v_current < v_amount then raise exception 'Not enough money to gift.'; end if;

    update public.character_wallet_balances
    set amount = amount - v_amount
    where character_id = v_sender.id
      and currency_unit_id = v_unit_id;

    insert into public.character_wallet_balances (character_id, currency_unit_id, amount)
    values (v_target.id, v_unit_id, v_amount)
    on conflict (character_id, currency_unit_id) do update
    set amount = public.character_wallet_balances.amount + excluded.amount;

    v_labels := array_append(v_labels, v_amount::text || ' ' || v_unit_name);
  end loop;

  if array_length(v_labels, 1) is null then
    raise exception 'Choose at least one amount of money to gift.';
  end if;

  if v_sender.owner_user_id is distinct from v_target.owner_user_id then
    insert into public.campaign_notifications (
      recipient_user_id,
      title,
      body,
      notice_kind,
      source_type,
      location_name
    )
    values (
      v_target.owner_user_id,
      v_sender.name || ' gave money to ' || v_target.name,
      array_to_string(v_labels, ', ') || ' was added to ' || v_target.name || '''s wallet.',
      'notice',
      'gift',
      v_target.location_name
    );
  end if;

  return public.get_character_inventory(p_session_token, v_sender.id);
end;
$$;

grant execute on function public.loadout_slot_accepts_item(text, text, boolean) to anon, authenticated;
grant execute on function public.item_catalog_stackable(text, text) to anon, authenticated;
grant execute on function public.item_catalog_can_be_enhanced(text, text, text) to anon, authenticated;
grant execute on function public.item_catalog_can_be_enchanted(text, text, text) to anon, authenticated;
grant execute on function public.format_item_quantity(numeric) to anon, authenticated;
grant execute on function public.inventory_item_record_to_json(public.inventory_items) to anon, authenticated;
grant execute on function public.wallet_balances_for_character(uuid) to anon, authenticated;
grant execute on function public.get_character_inventory(text, uuid) to anon, authenticated;
grant execute on function public.assert_inventory_access(public.profiles, uuid, boolean) to anon, authenticated;
grant execute on function public.find_first_free_inventory_slot(uuid, uuid, int) to anon, authenticated;
grant execute on function public.assert_inventory_slot_capacity(public.characters, uuid, int) to anon, authenticated;
grant execute on function public.next_storage_container_slot(uuid) to anon, authenticated;
grant execute on function public.character_storage_container_exists(uuid, text) to anon, authenticated;
grant execute on function public.inventory_items_stackable(public.inventory_items, public.inventory_items) to anon, authenticated;
grant execute on function public.inventory_item_is_mythril(text, text) to anon, authenticated;
grant execute on function public.inventory_item_is_mobile_home_storage(text, text) to anon, authenticated;
grant execute on function public.inventory_item_is_caged_wagon_storage(text, text) to anon, authenticated;
grant execute on function public.add_character_inventory_item(text, uuid, uuid, int, text, text, text, numeric, boolean, int, jsonb, text, text, int, boolean, text, text, text, text, boolean) to anon, authenticated;
grant execute on function public.update_inventory_item_state(text, uuid, jsonb) to anon, authenticated;
grant execute on function public.drop_inventory_item_quantity(text, uuid, numeric) to anon, authenticated;
grant execute on function public.split_inventory_item_stack(text, uuid, numeric, boolean) to anon, authenticated;
grant execute on function public.set_character_wallet_balances(text, uuid, jsonb) to anon, authenticated;
grant execute on function public.gift_character_currency(text, uuid, uuid, jsonb) to anon, authenticated;

-- ============================================================
-- ============================================================

-- House, property, and storage foundation.

create table if not exists public.player_houses (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null unique references public.profiles(id) on delete cascade,
  city_name text not null default 'Calostrynn',
  inventory_slots int not null default 45 check (inventory_slots between 0 and 500),
  stable_slots int not null default 0 check (stable_slots between 0 and 200),
  property_slots int not null default 10 check (property_slots between 0 and 200),
  is_locked boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.house_access_permissions (
  owner_user_id uuid not null references public.profiles(id) on delete cascade,
  grantee_user_id uuid not null references public.profiles(id) on delete cascade,
  can_access_house boolean not null default false,
  can_access_stable boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (owner_user_id, grantee_user_id),
  constraint house_access_permissions_not_self check (owner_user_id <> grantee_user_id),
  constraint house_access_permissions_some_access check (can_access_house or can_access_stable)
);

create table if not exists public.mobile_storage_access_permissions (
  storage_item_id uuid not null references public.inventory_items(id) on delete cascade,
  owner_user_id uuid not null references public.profiles(id) on delete cascade,
  grantee_user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (storage_item_id, grantee_user_id),
  constraint mobile_storage_access_permissions_not_self check (owner_user_id <> grantee_user_id)
);

create table if not exists public.house_inventory_items (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references public.profiles(id) on delete cascade,
  parent_item_id uuid references public.house_inventory_items(id) on delete cascade,
  item_name text not null,
  display_name text,
  item_description text not null default '',
  item_type text not null default 'misc',
  rarity public.item_rarity not null default 'Common',
  quantity numeric(12,1) not null default 1 check (quantity > 0),
  slot_index int not null default 0 check (slot_index >= -1000000),
  is_accessory boolean not null default false,
  is_storage boolean not null default false,
  storage_capacity int not null default 0 check (storage_capacity between 0 and 500),
  modifiers jsonb not null default '{}'::jsonb check (jsonb_typeof(modifiers) = 'object'),
  enchantment text,
  rune_name text,
  material text,
  enhancement_count int not null default 0 check (enhancement_count between 0 and 3),
  is_two_handed boolean not null default false,
  potion_strength text,
  potion_property text,
  potion_quality text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.house_inventory_items
  drop constraint if exists house_inventory_item_type_valid,
  drop constraint if exists house_inventory_items_item_type_valid;

alter table public.house_inventory_items
  alter column item_type type text using item_type::text,
  alter column quantity type numeric(12,1) using quantity::numeric;

alter table public.house_inventory_items
  drop constraint if exists house_inventory_items_slot_index_check;

alter table public.house_inventory_items
  add constraint house_inventory_items_slot_index_check check (slot_index >= -1000000);

alter table public.house_inventory_items
  add column if not exists display_name text,
  add column if not exists parent_item_id uuid references public.house_inventory_items(id) on delete cascade,
  add column if not exists item_description text not null default '',
  add column if not exists is_accessory boolean not null default false,
  add column if not exists enchantment text,
  add column if not exists rune_name text,
  add column if not exists material text,
  add column if not exists enhancement_count int not null default 0 check (enhancement_count between 0 and 3),
  add column if not exists is_two_handed boolean not null default false,
  add column if not exists potion_strength text,
  add column if not exists potion_property text,
  add column if not exists potion_quality text;

drop index if exists house_inventory_main_slot_unique;
drop index if exists house_inventory_root_slot_unique;
drop index if exists house_inventory_parent_slot_unique;
create index if not exists house_inventory_parent_idx on public.house_inventory_items(parent_item_id);

alter table public.player_houses
  add column if not exists house_name text not null default 'House',
  add column if not exists stable_name text not null default 'Stable',
  add column if not exists is_locked boolean not null default false,
  add column if not exists stable_slots int not null default 0 check (stable_slots between 0 and 200);

alter table public.player_houses
  alter column inventory_slots set default 45,
  alter column stable_slots set default 0;

update public.house_inventory_items
set item_type = public.normalize_item_type(item_type),
    item_name = case when item_name = 'Mountian Rune' then 'Mountain Rune' else public.normalize_item_name(item_name) end,
    potion_strength = case when public.normalize_item_type(item_type) = 'potion' then coalesce(potion_strength, public.potion_strength_from_name(item_name)) else potion_strength end,
    potion_property = case when public.normalize_item_type(item_type) = 'potion' then coalesce(potion_property, public.potion_property_from_name(item_name)) else potion_property end,
    potion_quality = case
      when public.normalize_item_type(item_type) <> 'potion' then potion_quality
      when public.potion_property_from_name(item_name) in ('Healing', 'Mana Regen') then null
      when lower(public.normalize_item_name(item_name)) = 'empty flask' then null
      else coalesce(potion_quality, public.potion_quality_from_name(item_name))
    end;

update public.house_inventory_items
set item_type = 'potion',
    rarity = case when lower(item_name) = 'arcane nector' then 'Uncommon'::public.item_rarity else 'Common'::public.item_rarity end,
    potion_strength = null,
    potion_property = null,
    potion_quality = null
where lower(item_name) in ('empty flask', 'arcane nector');

update public.item_catalog
set item_type = 'book',
    is_stackable = false,
    quantity_step = 1
where item_key in (
  'history-book',
  'alchemy-book',
  'bestiary',
  'magical-research',
  'ember-magic-spell-book',
  'frost-magic-spell-book',
  'lightning-magic-spell-book',
  'earth-magic-spell-book',
  'wind-magic-spell-book',
  'energy-magic-spell-book',
  'defensive-support-magic-spell-book',
  'offensive-support-magic-spell-book',
  'enhancement-magic-spell-book',
  'utility-magic-spell-book'
);

update public.inventory_items
set item_type = 'book'
where item_type = 'quest'
  and public.catalog_key_for_name(item_name) in (
    'history-book',
    'alchemy-book',
    'bestiary',
    'magical-research',
    'ember-magic-spell-book',
    'frost-magic-spell-book',
    'lightning-magic-spell-book',
    'earth-magic-spell-book',
    'wind-magic-spell-book',
    'energy-magic-spell-book',
    'defensive-support-magic-spell-book',
    'offensive-support-magic-spell-book',
    'enhancement-magic-spell-book',
    'utility-magic-spell-book'
  );

update public.house_inventory_items
set item_type = 'book'
where item_type = 'quest'
  and public.catalog_key_for_name(item_name) in (
    'history-book',
    'alchemy-book',
    'bestiary',
    'magical-research',
    'ember-magic-spell-book',
    'frost-magic-spell-book',
    'lightning-magic-spell-book',
    'earth-magic-spell-book',
    'wind-magic-spell-book',
    'energy-magic-spell-book',
    'defensive-support-magic-spell-book',
    'offensive-support-magic-spell-book',
    'enhancement-magic-spell-book',
    'utility-magic-spell-book'
  );

create table if not exists public.campaign_properties (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references public.profiles(id) on delete cascade,
  caretaker_character_id uuid references public.characters(id) on delete set null,
  property_name text not null,
  property_type text not null default 'other' check (property_type in ('animal', 'wagon', 'pet', 'mount', 'other')),
  property_location text not null default 'at_house' check (property_location in ('with_character', 'at_house')),
  is_pet boolean not null default false,
  slot_index int not null default 0 check (slot_index >= 0),
  storage_capacity int not null default 0 check (storage_capacity between 0 and 500),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.wagon_activity_log (
  id uuid primary key default gen_random_uuid(),
  wagon_item_id uuid not null references public.inventory_items(id) on delete cascade,
  actor_character_id uuid references public.characters(id) on delete set null,
  actor_name text not null default 'Unknown',
  action text not null check (action in ('stored', 'taken')),
  item_name text not null,
  quantity numeric(12,1) not null default 1 check (quantity > 0),
  created_at timestamptz not null default now()
);

create index if not exists wagon_activity_log_wagon_created_idx
  on public.wagon_activity_log (wagon_item_id, created_at desc);

alter table public.player_houses enable row level security;
alter table public.house_access_permissions enable row level security;
alter table public.mobile_storage_access_permissions enable row level security;
alter table public.house_inventory_items enable row level security;
alter table public.campaign_properties enable row level security;
alter table public.wagon_activity_log enable row level security;

-- Canonical property identity is established before house RPCs are compiled.
alter table public.player_houses drop constraint if exists player_houses_owner_user_id_key;
alter table public.player_houses
  add column if not exists house_kind text not null default 'house',
  add column if not exists created_order integer not null default 0;
alter table public.player_houses drop constraint if exists player_houses_house_kind_check;
alter table public.player_houses add constraint player_houses_house_kind_check check (house_kind in ('house', 'stable'));

insert into public.player_houses (owner_user_id, city_name, inventory_slots, stable_slots, property_slots, house_name, stable_name, house_kind, created_order)
select owner.id, 'Wild', 45, 0, 10, 'House', 'Stable', 'house', 10
from (
  select owner_user_id as id from public.house_inventory_items
  union
  select owner_user_id as id from public.campaign_properties
) owner
where owner.id is not null
  and not exists (select 1 from public.player_houses house where house.owner_user_id = owner.id);

alter table public.house_inventory_items
  add column if not exists house_id uuid references public.player_houses(id) on delete cascade;
update public.house_inventory_items item
set house_id = (select house.id from public.player_houses house where house.owner_user_id = item.owner_user_id order by house.created_at, house.id limit 1)
where item.house_id is null;
alter table public.house_inventory_items alter column house_id set not null;
drop index if exists house_inventory_root_slot_unique;
drop index if exists house_inventory_parent_slot_unique;
create unique index if not exists house_inventory_home_root_slot_unique on public.house_inventory_items(house_id, slot_index) where parent_item_id is null;
create unique index if not exists house_inventory_home_parent_slot_unique on public.house_inventory_items(house_id, parent_item_id, slot_index) where parent_item_id is not null;
create index if not exists house_inventory_home_idx on public.house_inventory_items(house_id, parent_item_id, slot_index);

alter table public.campaign_properties
  add column if not exists house_id uuid references public.player_houses(id) on delete cascade;
update public.campaign_properties property
set house_id = (select house.id from public.player_houses house where house.owner_user_id = property.owner_user_id order by house.created_at, house.id limit 1)
where property.house_id is null;
alter table public.campaign_properties alter column house_id set not null;

create table if not exists public.house_unit_access_permissions (
  house_id uuid not null references public.player_houses(id) on delete cascade,
  grantee_user_id uuid not null references public.profiles(id) on delete cascade,
  can_access_house boolean not null default false,
  can_access_stable boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (house_id, grantee_user_id),
  constraint house_unit_access_permissions_some_access check (can_access_house or can_access_stable)
);

alter table public.combatants
add column if not exists statuses jsonb not null default '[]'::jsonb;

alter table public.combatants
drop constraint if exists combatants_statuses_check;

alter table public.combatants
add constraint combatants_statuses_check check (jsonb_typeof(statuses) = 'array');
create table if not exists public.player_main_homes (
  owner_user_id uuid primary key references public.profiles(id) on delete cascade,
  home_source text not null check (home_source in ('static', 'mobile')),
  home_id uuid not null,
  updated_at timestamptz not null default now()
);
create table if not exists public.player_home_display_orders (
  owner_user_id uuid not null references public.profiles(id) on delete cascade,
  home_source text not null check (home_source in ('static', 'mobile')),
  home_id uuid not null,
  display_order integer not null check (display_order >= 0),
  updated_at timestamptz not null default now(),
  primary key (owner_user_id, home_source, home_id)
);
alter table public.house_unit_access_permissions enable row level security;
alter table public.player_main_homes enable row level security;
alter table public.player_home_display_orders enable row level security;
revoke all on public.house_unit_access_permissions from anon, authenticated;
revoke all on public.player_main_homes from anon, authenticated;
revoke all on public.player_home_display_orders from anon, authenticated;

insert into public.house_unit_access_permissions(house_id, grantee_user_id, can_access_house, can_access_stable)
select house.id, permission.grantee_user_id, permission.can_access_house, permission.can_access_stable
from public.house_access_permissions permission
join public.player_houses house on house.owner_user_id = permission.owner_user_id
on conflict (house_id, grantee_user_id) do update
set can_access_house = excluded.can_access_house, can_access_stable = excluded.can_access_stable;

insert into public.player_main_homes(owner_user_id, home_source, home_id)
select distinct on (house.owner_user_id) house.owner_user_id, 'static', house.id
from public.player_houses house
where house.house_kind = 'house' and house.inventory_slots > 0
  and not exists (select 1 from public.player_main_homes preference where preference.owner_user_id = house.owner_user_id)
order by house.owner_user_id, house.created_at, house.id
on conflict (owner_user_id) do nothing;

insert into public.player_home_display_orders(owner_user_id, home_source, home_id, display_order)
select house.owner_user_id, 'static', house.id, greatest(0, house.created_order)
from public.player_houses house
on conflict (owner_user_id, home_source, home_id) do nothing;

create or replace function public.static_home_access(
  p_profile public.profiles,
  p_house public.player_houses,
  p_stable boolean default false
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select p_profile.role = 'dm'::public.user_role
    or (
      not p_house.is_locked
      and (
        p_house.owner_user_id is not distinct from p_profile.id
        or exists (
          select 1
          from public.house_unit_access_permissions permission
          where permission.house_id = p_house.id
            and permission.grantee_user_id = p_profile.id
            and case when p_stable then permission.can_access_stable else permission.can_access_house end
        )
      )
    )
$$;

revoke all on public.player_houses from anon, authenticated;
revoke all on public.house_access_permissions from anon, authenticated;
revoke all on public.mobile_storage_access_permissions from anon, authenticated;
revoke all on public.house_inventory_items from anon, authenticated;
revoke all on public.campaign_properties from anon, authenticated;
revoke all on public.wagon_activity_log from anon, authenticated;

drop trigger if exists player_houses_touch_updated_at on public.player_houses;
create trigger player_houses_touch_updated_at
before update on public.player_houses
for each row execute function public.touch_updated_at();

drop trigger if exists house_access_permissions_touch_updated_at on public.house_access_permissions;
create trigger house_access_permissions_touch_updated_at
before update on public.house_access_permissions
for each row execute function public.touch_updated_at();

create index if not exists house_access_permissions_grantee_idx
  on public.house_access_permissions (grantee_user_id);

drop trigger if exists mobile_storage_access_permissions_touch_updated_at on public.mobile_storage_access_permissions;
create trigger mobile_storage_access_permissions_touch_updated_at
before update on public.mobile_storage_access_permissions
for each row execute function public.touch_updated_at();

create index if not exists mobile_storage_access_permissions_owner_idx
  on public.mobile_storage_access_permissions (owner_user_id, grantee_user_id);

drop trigger if exists house_inventory_items_touch_updated_at on public.house_inventory_items;
create trigger house_inventory_items_touch_updated_at
before update on public.house_inventory_items
for each row execute function public.touch_updated_at();

drop trigger if exists campaign_properties_touch_updated_at on public.campaign_properties;
create trigger campaign_properties_touch_updated_at
before update on public.campaign_properties
for each row execute function public.touch_updated_at();

create or replace function public.get_required_player_house(p_owner_user_id uuid)
returns public.player_houses
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_house public.player_houses%rowtype;
begin
  if p_owner_user_id is null or not exists (select 1 from public.profiles where id = p_owner_user_id) then
    raise exception 'House owner not found.';
  end if;

  select * into v_house
  from public.player_houses
  where owner_user_id = p_owner_user_id;

  if v_house.id is null then
    raise exception 'House not found. The Dungeon Master must create it first.';
  end if;

  return v_house;
end;
$$;

create or replace function public.assert_house_access(
  p_profile public.profiles,
  p_owner_user_id uuid,
  p_dm_only boolean default false
)
returns public.player_houses
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_house public.player_houses%rowtype;
begin
  if p_profile.id is null then
    raise exception 'Invalid or expired session.';
  end if;

  if p_dm_only and p_profile.role <> 'dm'::public.user_role then
    raise exception 'Only the Dungeon Master can do that.';
  end if;

  if not p_dm_only
    and p_profile.role <> 'dm'::public.user_role
    and p_owner_user_id is distinct from p_profile.id
    and not exists (
      select 1
      from public.house_access_permissions a
      where a.owner_user_id = p_owner_user_id
        and a.grantee_user_id = p_profile.id
        and (a.can_access_house or a.can_access_stable)
    )
  then
    raise exception 'You do not have access to this house.';
  end if;

  v_house := public.get_required_player_house(p_owner_user_id);
  return v_house;
end;
$$;

create or replace function public.house_record_to_json(p_house public.player_houses)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'id', p_house.id,
    'ownerUserId', p_house.owner_user_id,
    'name', p_house.house_name,
    'stableName', p_house.stable_name,
    'cityName', p_house.city_name,
    'inventorySlots', p_house.inventory_slots,
    'stableSlots', p_house.stable_slots,
    'propertySlots', p_house.property_slots,
    'locked', p_house.is_locked
  )
$$;

create or replace function public.house_item_record_to_json(p_item public.house_inventory_items)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'id', p_item.id,
    'characterId', p_item.owner_user_id,
    'parentItemId', p_item.parent_item_id,
    'name', p_item.item_name,
    'displayName', p_item.display_name,
    'itemDescription', p_item.item_description,
    'type', p_item.item_type,
    'rarity', p_item.rarity,
    'quantity', p_item.quantity,
    'slotIndex', p_item.slot_index,
    'loadoutSlot', null,
    'stackable', public.item_catalog_stackable(p_item.item_name, p_item.item_type),
    'isAccessory', p_item.is_accessory,
    'isStorage', p_item.is_storage,
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
    'canBeEnhanced', public.item_catalog_can_be_enhanced(p_item.item_name, p_item.item_type, p_item.material),
    'canBeEnchanted', public.item_catalog_can_be_enchanted(p_item.item_name, p_item.item_type, p_item.material)
  )
$$;

create or replace function public.property_record_to_json(p_property public.campaign_properties)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'id', p_property.id,
    'ownerUserId', p_property.owner_user_id,
    'caretakerCharacterId', p_property.caretaker_character_id,
    'name', p_property.property_name,
    'type', p_property.property_type,
    'location', p_property.property_location,
    'isPet', p_property.is_pet,
    'slotIndex', p_property.slot_index,
    'storageCapacity', p_property.storage_capacity
  )
$$;

create or replace function public.house_access_to_json(
  p_profile public.profiles,
  p_owner_user_id uuid
)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'owner', p_owner_user_id is not distinct from p_profile.id,
    'dm', p_profile.role = 'dm'::public.user_role,
    'house', p_profile.role = 'dm'::public.user_role
      or p_owner_user_id is not distinct from p_profile.id
      or exists (
        select 1
        from public.house_access_permissions a
        where a.owner_user_id = p_owner_user_id
          and a.grantee_user_id = p_profile.id
          and a.can_access_house
      ),
    'stable', p_profile.role = 'dm'::public.user_role
      or p_owner_user_id is not distinct from p_profile.id
      or exists (
        select 1
        from public.house_access_permissions a
        where a.owner_user_id = p_owner_user_id
          and a.grantee_user_id = p_profile.id
          and a.can_access_stable
      )
  )
$$;

create or replace function public.house_permissions_to_json(p_owner_user_id uuid)
returns jsonb
language sql
stable
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'ownerUserId', a.owner_user_id,
    'granteeUserId', a.grantee_user_id,
    'granteeName', coalesce(nullif(p.display_name, ''), p.username::text, 'Player'),
    'house', a.can_access_house,
    'stable', a.can_access_stable
  ) order by coalesce(nullif(p.display_name, ''), p.username::text, 'Player')), '[]'::jsonb)
  from public.house_access_permissions a
  join public.profiles p on p.id = a.grantee_user_id
  where a.owner_user_id = p_owner_user_id
$$;

create or replace function public.mobile_storage_permissions_to_json(p_storage_item_id uuid)
returns jsonb
language sql
stable
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'storageItemId', a.storage_item_id,
    'ownerUserId', a.owner_user_id,
    'granteeUserId', a.grantee_user_id,
    'granteeName', coalesce(nullif(p.display_name, ''), p.username::text, 'Player'),
    'access', true
  ) order by coalesce(nullif(p.display_name, ''), p.username::text, 'Player')), '[]'::jsonb)
  from public.mobile_storage_access_permissions a
  join public.profiles p on p.id = a.grantee_user_id
  where a.storage_item_id = p_storage_item_id
$$;

create or replace function public.house_inventory_items_stackable(a public.house_inventory_items, b public.house_inventory_items)
returns boolean
language sql
stable
as $$
  select lower(public.normalize_item_name(a.item_name)) = lower(public.normalize_item_name(b.item_name))
    and public.normalize_item_type(a.item_type) = public.normalize_item_type(b.item_type)
    and a.rarity = b.rarity
    and coalesce(a.enchantment, '') = coalesce(b.enchantment, '')
    and coalesce(a.rune_name, '') = coalesce(b.rune_name, '')
    and coalesce(a.material, '') = coalesce(b.material, '')
    and coalesce(a.potion_strength, '') = coalesce(b.potion_strength, '')
    and coalesce(a.potion_property, '') = coalesce(b.potion_property, '')
    and coalesce(a.potion_quality, '') = coalesce(b.potion_quality, '')
    and a.enhancement_count = b.enhancement_count
    and a.is_two_handed = b.is_two_handed
    and a.is_accessory = b.is_accessory
    and a.modifiers = b.modifiers
    and a.item_type <> 'pet'
    and b.item_type <> 'pet'
    and a.is_storage = false
    and b.is_storage = false
    and public.item_catalog_stackable(a.item_name, a.item_type)
    and public.item_catalog_stackable(b.item_name, b.item_type)
$$;

create or replace function public.find_first_free_house_slot(
  p_owner_user_id uuid,
  p_parent_item_id uuid,
  p_capacity int
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_slot int;
begin
  if p_capacity <= 0 then
    return null;
  end if;

  for v_slot in 0..greatest(p_capacity - 1, 0) loop
    if not exists (
      select 1
      from public.house_inventory_items i
      where i.owner_user_id = p_owner_user_id
        and coalesce(i.parent_item_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(p_parent_item_id, '00000000-0000-0000-0000-000000000000'::uuid)
        and i.slot_index = v_slot
    ) then
      return v_slot;
    end if;
  end loop;

  return null;
end;
$$;

create or replace function public.house_stable_slot_offset()
returns int
language sql
immutable
as $$
  select 1000
$$;

-- Stable slots historically began at 45, which overlaps any house expanded
-- beyond the original 45-slot capacity. Move existing root animals into a
-- dedicated range once; repeated schema runs leave the new positions intact.
update public.house_inventory_items item
set slot_index = 1000 + (item.slot_index - 45)
from public.player_houses house
where item.house_id = house.id
  and item.parent_item_id is null
  and public.normalize_item_type(item.item_type) = 'pet'
  and item.slot_index >= 45
  and item.slot_index < 45 + house.stable_slots;

create or replace function public.find_first_free_house_stable_slot(
  p_owner_user_id uuid,
  p_house public.player_houses
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_slot int;
  v_start int := public.house_stable_slot_offset();
  v_end int := public.house_stable_slot_offset() + greatest(coalesce(p_house.stable_slots, 0), 0) - 1;
begin
  if coalesce(p_house.stable_slots, 0) <= 0 then
    return null;
  end if;

  for v_slot in v_start..v_end loop
    if not exists (
      select 1
      from public.house_inventory_items i
      where i.house_id = p_house.id
        and i.parent_item_id is null
        and i.slot_index = v_slot
    ) then
      return v_slot;
    end if;
  end loop;

  return null;
end;
$$;

create or replace function public.assert_house_item_slot_capacity(
  p_house public.player_houses,
  p_parent_item_id uuid,
  p_slot_index int,
  p_item_type text
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_is_pet boolean := public.normalize_item_type(p_item_type) = 'pet';
  v_stable_start int := public.house_stable_slot_offset();
begin
  if p_slot_index < 0 then raise exception 'Property slot is invalid.'; end if;

  if p_house.house_kind = 'stable' then
    if p_parent_item_id is not null then raise exception 'Animals must occupy a direct stable slot.'; end if;
    if not v_is_pet then raise exception 'Stable slots are only for animals.'; end if;
    if p_slot_index < v_stable_start or p_slot_index >= v_stable_start + p_house.stable_slots then
      raise exception 'Stable slot is outside the stable capacity.';
    end if;
    return p_house.stable_slots;
  end if;

  if v_is_pet then raise exception 'Animals require a stable or Caged Wagon.'; end if;
  if p_parent_item_id is null then
    if p_slot_index >= p_house.inventory_slots then raise exception 'House slot is outside the house capacity.'; end if;
    return p_house.inventory_slots;
  end if;
  return public.assert_house_slot_capacity(p_house, p_parent_item_id, p_slot_index);
end;
$$;

create or replace function public.place_pet_item_in_caged_wagon_for_character(
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
  p_enhancement_count int default 0,
  p_is_two_handed boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_character public.characters%rowtype;
  v_caged record;
  v_slot int;
  v_pet public.inventory_items%rowtype;
  v_quantity numeric := public.assert_valid_item_quantity(p_item_name, 'pet', greatest(1, coalesce(p_quantity, 1)));
begin
  select * into v_character from public.characters where id = p_character_id;
  if v_character.id is null then
    raise exception 'Receiving character was not found.';
  end if;

  if v_character.owner_user_id is null then
    return null;
  end if;

  if v_quantity <> 1 then
    raise exception 'Pets must be moved one at a time.';
  end if;

  select * into v_caged
  from public.caged_wagon_storage_for_owner(v_character.owner_user_id);

  if not found then
    return null;
  end if;

  v_slot := public.find_first_free_inventory_slot(
    (v_caged.storage).character_id,
    (v_caged.storage).id,
    greatest(0, (v_caged.storage).storage_capacity)
  );
  if v_slot is null then
    return null;
  end if;

  insert into public.inventory_items (
    character_id,
    parent_item_id,
    slot_index,
    loadout_slot,
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
    (v_caged.storage).character_id,
    (v_caged.storage).id,
    v_slot,
    null,
    public.normalize_item_name(p_item_name),
    nullif(left(trim(coalesce(p_display_name, '')), 80), ''),
    left(trim(coalesce(p_item_description, '')), 1500),
    'pet',
    p_rarity,
    1,
    coalesce(p_is_accessory, false),
    false,
    0,
    case when jsonb_typeof(coalesce(p_modifiers, '{}'::jsonb)) = 'object' then coalesce(p_modifiers, '{}'::jsonb) else '{}'::jsonb end,
    nullif(trim(coalesce(p_enchantment, '')), ''),
    nullif(trim(coalesce(p_rune_name, '')), ''),
    trim(coalesce(p_material, '')),
    least(3, greatest(0, coalesce(p_enhancement_count, 0))),
    coalesce(p_is_two_handed, false),
    null,
    null,
    null
  )
  returning * into v_pet;

  return public.inventory_item_record_to_json(v_pet);
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
  p_enhancement_count int default 0,
  p_is_two_handed boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_character public.characters%rowtype;
  v_house public.player_houses%rowtype;
  v_slot int;
  v_pet public.inventory_items%rowtype;
  v_caged_pet jsonb;
  v_quantity numeric := public.assert_valid_item_quantity(p_item_name, 'pet', greatest(1, coalesce(p_quantity, 1)));
begin
  select * into v_character from public.characters where id = p_character_id;
  if v_character.id is null then
    raise exception 'Receiving character was not found.';
  end if;

  if v_quantity <> 1 then
    raise exception 'Pets must be moved one at a time.';
  end if;

  if not exists (
    select 1
    from public.inventory_items i
    where i.character_id = v_character.id
      and i.loadout_slot = 'active-pet'
  ) then
    insert into public.inventory_items (
      character_id,
      parent_item_id,
      slot_index,
      loadout_slot,
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
      v_character.id,
      null,
      0,
      'active-pet',
      public.normalize_item_name(p_item_name),
      nullif(left(trim(coalesce(p_display_name, '')), 80), ''),
      left(trim(coalesce(p_item_description, '')), 1500),
      'pet',
      p_rarity,
      1,
      coalesce(p_is_accessory, false),
      false,
      0,
      case when jsonb_typeof(coalesce(p_modifiers, '{}'::jsonb)) = 'object' then coalesce(p_modifiers, '{}'::jsonb) else '{}'::jsonb end,
      nullif(trim(coalesce(p_enchantment, '')), ''),
      nullif(trim(coalesce(p_rune_name, '')), ''),
      trim(coalesce(p_material, '')),
      least(3, greatest(0, coalesce(p_enhancement_count, 0))),
      coalesce(p_is_two_handed, false),
      null,
      null,
      null
    )
    returning * into v_pet;

    return public.inventory_item_record_to_json(v_pet);
  end if;

  if v_character.owner_user_id is null then
    raise exception 'Active pet slot is occupied and that character has no player stable.';
  end if;

  v_caged_pet := public.place_pet_item_in_caged_wagon_for_character(
    p_character_id,
    p_item_name,
    p_display_name,
    p_item_description,
    p_rarity,
    p_quantity,
    p_is_accessory,
    p_modifiers,
    p_enchantment,
    p_rune_name,
    p_material,
    p_enhancement_count,
    p_is_two_handed
  );
  if v_caged_pet is not null then
    return v_caged_pet;
  end if;

  v_house := public.get_required_player_house(v_character.owner_user_id);
  v_slot := public.find_first_free_house_stable_slot(v_character.owner_user_id, v_house);
  if v_slot is null then
    raise exception 'No open active pet or stable slot.';
  end if;

  insert into public.house_inventory_items (
    owner_user_id,
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
    v_character.owner_user_id,
    null,
    v_slot,
    public.normalize_item_name(p_item_name),
    nullif(left(trim(coalesce(p_display_name, '')), 80), ''),
    left(trim(coalesce(p_item_description, '')), 1500),
    'pet',
    p_rarity,
    1,
    coalesce(p_is_accessory, false),
    false,
    0,
    case when jsonb_typeof(coalesce(p_modifiers, '{}'::jsonb)) = 'object' then coalesce(p_modifiers, '{}'::jsonb) else '{}'::jsonb end,
    nullif(trim(coalesce(p_enchantment, '')), ''),
    nullif(trim(coalesce(p_rune_name, '')), ''),
    trim(coalesce(p_material, '')),
    least(3, greatest(0, coalesce(p_enhancement_count, 0))),
    coalesce(p_is_two_handed, false),
    null,
    null,
    null
  );

  return null;
end;
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
  p_enhancement_count int default 0,
  p_is_two_handed boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_character public.characters%rowtype;
  v_house public.player_houses%rowtype;
  v_house_item public.house_inventory_items%rowtype;
  v_caged_pet jsonb;
  v_slot int;
  v_quantity numeric := public.assert_valid_item_quantity(p_item_name, 'pet', greatest(1, coalesce(p_quantity, 1)));
begin
  select * into v_character from public.characters where id = p_character_id;
  if v_character.id is null then
    raise exception 'Receiving character was not found.';
  end if;

  if v_character.owner_user_id is null then
    raise exception 'That character is not assigned to a player stable.';
  end if;

  if v_quantity <> 1 then
    raise exception 'Pets must be moved one at a time.';
  end if;

  v_caged_pet := public.place_pet_item_in_caged_wagon_for_character(
    p_character_id,
    p_item_name,
    p_display_name,
    p_item_description,
    p_rarity,
    p_quantity,
    p_is_accessory,
    p_modifiers,
    p_enchantment,
    p_rune_name,
    p_material,
    p_enhancement_count,
    p_is_two_handed
  );
  if v_caged_pet is not null then
    return v_caged_pet;
  end if;

  v_house := public.get_required_player_house(v_character.owner_user_id);
  v_slot := public.find_first_free_house_stable_slot(v_character.owner_user_id, v_house);
  if v_slot is null then
    raise exception 'No open stable slot.';
  end if;

  insert into public.house_inventory_items (
    owner_user_id,
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
    v_character.owner_user_id,
    null,
    v_slot,
    public.normalize_item_name(p_item_name),
    nullif(left(trim(coalesce(p_display_name, '')), 80), ''),
    left(trim(coalesce(p_item_description, '')), 1500),
    'pet',
    p_rarity,
    1,
    coalesce(p_is_accessory, false),
    false,
    0,
    case when jsonb_typeof(coalesce(p_modifiers, '{}'::jsonb)) = 'object' then coalesce(p_modifiers, '{}'::jsonb) else '{}'::jsonb end,
    nullif(trim(coalesce(p_enchantment, '')), ''),
    nullif(trim(coalesce(p_rune_name, '')), ''),
    trim(coalesce(p_material, '')),
    least(3, greatest(0, coalesce(p_enhancement_count, 0))),
    coalesce(p_is_two_handed, false),
    null,
    null,
    null
  )
  returning * into v_house_item;

  return public.house_item_record_to_json(v_house_item);
end;
$$;

do $$
declare
  v_pet record;
begin
  for v_pet in
    select i.*
    from public.inventory_items i
    where public.normalize_item_type(i.item_type) = 'pet'
      and coalesce(i.loadout_slot, '') <> 'active-pet'
  loop
    begin
      perform public.place_pet_item_for_character(
        v_pet.character_id,
        v_pet.item_name,
        v_pet.display_name,
        v_pet.item_description,
        v_pet.rarity,
        1,
        v_pet.is_accessory,
        v_pet.modifiers,
        v_pet.enchantment,
        v_pet.rune_name,
        v_pet.material,
        v_pet.enhancement_count,
        v_pet.is_two_handed
      );

      delete from public.inventory_items
      where id = v_pet.id;
    exception when others then
      if not exists (
        select 1
        from public.inventory_items active_pet
        where active_pet.character_id = v_pet.character_id
          and active_pet.loadout_slot = 'active-pet'
      ) then
        update public.inventory_items
        set parent_item_id = null,
            slot_index = 0,
            loadout_slot = 'active-pet',
            item_type = 'pet',
            quantity = 1
        where id = v_pet.id;
      end if;
    end;
  end loop;
end $$;

create or replace function public.assert_house_slot_capacity(
  p_house public.player_houses,
  p_parent_item_id uuid,
  p_slot_index int
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_capacity int;
begin
  if p_slot_index < 0 then
    raise exception 'House slot is invalid.';
  end if;

  if p_parent_item_id is null then
    v_capacity := p_house.inventory_slots;
  else
    select h.storage_capacity into v_capacity
    from public.house_inventory_items h
    where h.id = p_parent_item_id
      and h.owner_user_id = p_house.owner_user_id
      and h.is_storage = true;

    if v_capacity is null then
      raise exception 'House storage container not found.';
    end if;
  end if;

  if p_slot_index >= v_capacity then
    raise exception 'House slot is outside the container capacity.';
  end if;

  return v_capacity;
end;
$$;

create or replace function public.get_player_house(
  p_session_token text,
  p_owner_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_house public.player_houses%rowtype;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  v_house := public.assert_house_access(v_profile, p_owner_user_id, false);

  return jsonb_build_object(
    'house', public.house_record_to_json(v_house),
    'access', public.house_access_to_json(v_profile, p_owner_user_id),
    'permissions', case
      when v_profile.role = 'dm'::public.user_role or p_owner_user_id is not distinct from v_profile.id
        then public.house_permissions_to_json(p_owner_user_id)
      else '[]'::jsonb
    end,
    'items', (
      select coalesce(jsonb_agg(public.house_item_record_to_json(i) order by i.slot_index, i.item_name), '[]'::jsonb)
      from public.house_inventory_items i
      where i.owner_user_id = p_owner_user_id
    ),
    'properties', (
      select coalesce(jsonb_agg(public.property_record_to_json(p) order by p.property_location, p.slot_index, p.property_name), '[]'::jsonb)
      from public.campaign_properties p
      where p.owner_user_id = p_owner_user_id
    )
  );
end;
$$;

drop function if exists public.add_house_inventory_item(text, uuid, int, text, text, text, numeric, boolean, int, jsonb, text);
drop function if exists public.add_house_inventory_item(text, uuid, uuid, int, text, text, text, numeric, boolean, int, jsonb, text);
drop function if exists public.add_house_inventory_item(text, uuid, uuid, int, text, text, text, numeric, boolean, int, jsonb, text, text, int, boolean, text, text, text, text);
drop function if exists public.add_house_inventory_item(text, uuid, uuid, int, text, text, text, numeric, boolean, int, jsonb, text, text, int, boolean, text, text, text, text, boolean);

create or replace function public.add_house_inventory_item(
  p_session_token text,
  p_owner_user_id uuid,
  p_parent_item_id uuid,
  p_slot_index int,
  p_item_name text,
  p_item_type text,
  p_rarity text,
  p_quantity numeric,
  p_is_storage boolean default false,
  p_storage_capacity int default 0,
  p_modifiers jsonb default '{}'::jsonb,
  p_enchantment text default null,
  p_material text default null,
  p_enhancement_count int default 0,
  p_is_two_handed boolean default false,
  p_potion_strength text default null,
  p_potion_property text default null,
  p_potion_quality text default null,
  p_item_description text default null,
  p_is_accessory boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_house public.player_houses%rowtype;
  v_item public.house_inventory_items%rowtype;
  v_target public.house_inventory_items%rowtype;
  v_catalog public.item_catalog%rowtype;
  v_item_type text;
  v_rarity public.item_rarity;
  v_quantity numeric := greatest(0.5, coalesce(p_quantity, 1));
  v_modifiers jsonb;
  v_material text := '';
  v_is_two_handed boolean := coalesce(p_is_two_handed, false);
  v_is_accessory boolean := coalesce(p_is_accessory, false);
  v_enhancement_count int := least(3, greatest(0, coalesce(p_enhancement_count, 0)));
  v_storage_capacity int := greatest(0, coalesce(p_storage_capacity, 0));
  v_item_name text := public.normalize_item_name(p_item_name);
  v_item_description text := left(trim(coalesce(p_item_description, '')), 1500);
  v_potion_strength text;
  v_potion_property text;
  v_potion_quality text;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  v_house := public.assert_house_access(v_profile, p_owner_user_id, true);

  if length(trim(coalesce(v_item_name, ''))) = 0 then
    raise exception 'Item name is required.';
  end if;

  select * into v_catalog
  from public.item_catalog
  where item_key = public.catalog_key_for_name(v_item_name)
  limit 1;

  v_item_type := public.normalize_item_type(coalesce(nullif(p_item_type, ''), v_catalog.item_type, 'misc'));
  if v_catalog.id is not null and (v_item_type = 'misc' or v_item_type = '') then
    v_item_type := v_catalog.item_type;
  end if;
  v_rarity := coalesce(nullif(p_rarity, ''), coalesce(v_catalog.rarity::text, 'Common'))::public.item_rarity;
  v_quantity := public.assert_valid_item_quantity(v_item_name, v_item_type, v_quantity);
  v_modifiers := case when jsonb_typeof(coalesce(p_modifiers, '{}'::jsonb)) = 'object' then coalesce(p_modifiers, '{}'::jsonb) else '{}'::jsonb end;
  if v_catalog.id is not null then
    v_modifiers := v_catalog.default_modifiers || v_modifiers;
    v_material := v_catalog.material;
    v_is_two_handed := v_is_two_handed or v_catalog.is_two_handed;
    v_storage_capacity := greatest(v_storage_capacity, v_catalog.storage_capacity);
  end if;
  if length(trim(coalesce(p_material, ''))) > 0 then
    v_material := trim(p_material);
  end if;
  if length(trim(coalesce(p_enchantment, ''))) > 0 then
    v_enhancement_count := 0;
  end if;

  if v_item_type = 'potion' then
    v_potion_strength := coalesce(nullif(trim(coalesce(p_potion_strength, '')), ''), public.potion_strength_from_name(v_item_name));
    v_potion_property := coalesce(nullif(trim(coalesce(p_potion_property, '')), ''), public.potion_property_from_name(v_item_name));
    v_potion_quality := case
      when v_potion_property in ('Healing', 'Mana Regen') then null
      when lower(v_item_name) = 'empty flask' then null
      else coalesce(nullif(trim(coalesce(p_potion_quality, '')), ''), public.potion_quality_from_name(v_item_name))
    end;
    if v_potion_strength is not null and v_potion_property is not null then
      v_item_name := public.format_potion_item_name(v_potion_strength, v_potion_property, v_potion_quality);
      v_rarity := public.potion_rarity_for(v_potion_strength, v_potion_property);
    end if;
  end if;

  perform public.assert_house_item_slot_capacity(v_house, p_parent_item_id, p_slot_index, v_item_type);

  select * into v_target
  from public.house_inventory_items i
  where i.owner_user_id = p_owner_user_id
    and coalesce(i.parent_item_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(p_parent_item_id, '00000000-0000-0000-0000-000000000000'::uuid)
    and i.slot_index = p_slot_index
  limit 1;

  if v_target.id is not null then
    if lower(public.normalize_item_name(v_target.item_name)) = lower(public.normalize_item_name(v_item_name))
      and coalesce(v_target.display_name, '') = ''
      and public.normalize_item_type(v_target.item_type) = public.normalize_item_type(v_item_type)
      and v_target.rarity = v_rarity
      and coalesce(v_target.enchantment, '') = coalesce(nullif(trim(p_enchantment), ''), '')
      and coalesce(v_target.rune_name, '') = ''
      and coalesce(v_target.material, '') = coalesce(v_material, '')
      and coalesce(v_target.potion_strength, '') = coalesce(v_potion_strength, '')
      and coalesce(v_target.potion_property, '') = coalesce(v_potion_property, '')
      and coalesce(v_target.potion_quality, '') = coalesce(v_potion_quality, '')
      and v_target.enhancement_count = v_enhancement_count
      and v_target.is_two_handed = v_is_two_handed
      and v_target.is_accessory = v_is_accessory
      and v_target.modifiers = v_modifiers
      and v_target.item_type <> 'pet'
      and v_target.is_storage = false
      and not coalesce(p_is_storage, false)
      and public.item_catalog_stackable(v_item_name, v_item_type)
    then
      update public.house_inventory_items
      set quantity = quantity + v_quantity
      where id = v_target.id
      returning * into v_item;
      return public.house_item_record_to_json(v_item);
    end if;

    raise exception 'That house slot is already occupied.';
  end if;

  insert into public.house_inventory_items (
    owner_user_id,
    parent_item_id,
    slot_index,
    item_name,
    item_type,
    rarity,
    quantity,
    is_accessory,
    is_storage,
    storage_capacity,
    item_description,
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
    p_owner_user_id,
    p_parent_item_id,
    p_slot_index,
    v_item_name,
    v_item_type,
    v_rarity,
    v_quantity,
    v_is_accessory,
    coalesce(p_is_storage, false),
    case when coalesce(p_is_storage, false) then greatest(1, coalesce(nullif(v_storage_capacity, 0), 6)) else 0 end,
    v_item_description,
    v_modifiers,
    nullif(trim(coalesce(p_enchantment, '')), ''),
    v_material,
    v_enhancement_count,
    v_is_two_handed,
    v_potion_strength,
    v_potion_property,
    v_potion_quality
  )
  returning * into v_item;

  return public.house_item_record_to_json(v_item);
end;
$$;

create or replace function public.update_house_inventory_item_state(
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
  v_house public.player_houses%rowtype;
  v_item public.house_inventory_items%rowtype;
  v_target public.house_inventory_items%rowtype;
  v_patch jsonb := coalesce(p_patch, '{}'::jsonb);
  v_parent_item_id uuid;
  v_slot_index int;
  v_original_parent_item_id uuid;
  v_original_slot_index int;
  v_temporary_slot_index int;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;

  select * into v_item from public.house_inventory_items where id = p_item_id;
  if v_item.id is null then raise exception 'House item not found.'; end if;

  select * into v_house from public.player_houses where id = v_item.house_id;
  if v_house.id is null then raise exception 'The item home was not found.'; end if;

  if not public.static_home_access(
    v_profile,
    v_house,
    public.normalize_item_type(v_item.item_type) = 'pet'
      or (v_item.parent_item_id is null and v_item.slot_index >= public.house_stable_slot_offset())
  ) then
    raise exception 'You do not have permission to use that property.';
  end if;

  if v_profile.role <> 'dm'::public.user_role
    and v_item.owner_user_id is distinct from v_profile.id
    and not exists (
      select 1
      from public.house_unit_access_permissions a
      where a.house_id = v_item.house_id
        and a.grantee_user_id = v_profile.id
        and case
          when public.normalize_item_type(v_item.item_type) = 'pet'
            or (v_item.parent_item_id is null and v_item.slot_index >= public.house_stable_slot_offset())
            then a.can_access_stable
          else a.can_access_house
        end
    )
  then
    raise exception 'You do not have permission to use that house section.';
  end if;

  if (v_patch ? 'name' or v_patch ? 'type' or v_patch ? 'rarity' or v_patch ? 'quantity' or v_patch ? 'isStorage' or v_patch ? 'isAccessory' or v_patch ? 'storageCapacity' or v_patch ? 'modifiers' or v_patch ? 'enchantment' or v_patch ? 'material' or v_patch ? 'enhancementCount' or v_patch ? 'isTwoHanded' or v_patch ? 'itemDescription' or v_patch ? 'potionStrength' or v_patch ? 'potionProperty' or v_patch ? 'potionQuality') and v_profile.role <> 'dm'::public.user_role then
    raise exception 'Only the Dungeon Master can edit item details.';
  end if;

  if v_patch ? 'displayName' and v_item.item_type <> 'pet' then
    raise exception 'Only pet items can be named.';
  end if;

  if v_profile.role = 'dm'::public.user_role then
    update public.house_inventory_items
    set
      item_name = case when v_patch ? 'name' then coalesce(nullif(trim(v_patch->>'name'), ''), item_name) else item_name end,
      item_type = case when v_patch ? 'type' then public.normalize_item_type(v_patch->>'type') else item_type end,
      rarity = case when v_patch ? 'rarity' then (v_patch->>'rarity')::public.item_rarity else rarity end,
      quantity = case when v_patch ? 'quantity' then public.assert_valid_item_quantity(coalesce(nullif(trim(v_patch->>'name'), ''), item_name), case when v_patch ? 'type' then public.normalize_item_type(v_patch->>'type') else item_type end, (v_patch->>'quantity')::numeric) else quantity end,
      is_accessory = case when v_patch ? 'isAccessory' then (v_patch->>'isAccessory')::boolean else is_accessory end,
      is_storage = case when v_patch ? 'isStorage' then (v_patch->>'isStorage')::boolean else is_storage end,
      storage_capacity = case when v_patch ? 'storageCapacity' then greatest(0, (v_patch->>'storageCapacity')::int) else storage_capacity end,
      item_description = case when v_patch ? 'itemDescription' then left(trim(coalesce(v_patch->>'itemDescription', '')), 1500) else item_description end,
      modifiers = case when v_patch ? 'modifiers' and jsonb_typeof(v_patch->'modifiers') = 'object' then v_patch->'modifiers' else modifiers end,
      enchantment = case
        when v_patch ? 'enhancementCount' and (v_patch->>'enhancementCount')::int > 0 then null
        when v_patch ? 'enchantment' then nullif(trim(coalesce(v_patch->>'enchantment', '')), '')
        else enchantment
      end,
      material = case when v_patch ? 'material' then trim(coalesce(v_patch->>'material', '')) else material end,
      enhancement_count = case
        when v_patch ? 'enchantment' and length(trim(coalesce(v_patch->>'enchantment', ''))) > 0 then 0
        when v_patch ? 'enhancementCount' then least(3, greatest(0, (v_patch->>'enhancementCount')::int))
        else enhancement_count
      end,
      is_two_handed = case when v_patch ? 'isTwoHanded' then (v_patch->>'isTwoHanded')::boolean else is_two_handed end,
      potion_strength = case when v_patch ? 'potionStrength' then nullif(trim(coalesce(v_patch->>'potionStrength', '')), '') else potion_strength end,
      potion_property = case when v_patch ? 'potionProperty' then nullif(trim(coalesce(v_patch->>'potionProperty', '')), '') else potion_property end,
      potion_quality = case
        when v_patch ? 'potionProperty' and (v_patch->>'potionProperty') in ('Healing', 'Mana Regen') then null
        when v_patch ? 'potionQuality' then nullif(trim(coalesce(v_patch->>'potionQuality', '')), '')
        else potion_quality
      end
    where id = p_item_id
    returning * into v_item;

    if not public.inventory_item_is_mythril(v_item.item_name, v_item.material)
      and v_item.rune_name is not null
    then
      update public.house_inventory_items
      set rune_name = null
      where id = v_item.id
      returning * into v_item;
    end if;

    perform public.assert_house_item_slot_capacity(v_house, v_item.parent_item_id, v_item.slot_index, v_item.item_type);
  end if;

  if v_patch ? 'displayName' and v_item.item_type <> 'pet' then
    raise exception 'Only pet items can be named.';
  end if;

  if v_patch ? 'displayName' then
    update public.house_inventory_items
    set display_name = nullif(left(trim(coalesce(v_patch->>'displayName', '')), 80), '')
    where id = p_item_id
    returning * into v_item;
  elsif v_item.item_type <> 'pet' and v_item.display_name is not null then
    update public.house_inventory_items
    set display_name = null
    where id = p_item_id
    returning * into v_item;
  end if;

  if v_patch ? 'slotIndex' or v_patch ? 'parentItemId' then
    v_original_parent_item_id := v_item.parent_item_id;
    v_original_slot_index := v_item.slot_index;
    v_parent_item_id := case when v_patch ? 'parentItemId' then nullif(v_patch->>'parentItemId', '')::uuid else v_item.parent_item_id end;
    v_slot_index := case when v_patch ? 'slotIndex' then (v_patch->>'slotIndex')::int else v_item.slot_index end;

    if v_parent_item_id = v_item.id then
      raise exception 'An item cannot be moved inside itself.';
    end if;

    if coalesce(v_parent_item_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(v_item.parent_item_id, '00000000-0000-0000-0000-000000000000'::uuid)
      and v_slot_index = v_item.slot_index
    then
      return public.house_item_record_to_json(v_item);
    end if;

    perform public.assert_house_item_slot_capacity(v_house, v_parent_item_id, v_slot_index, v_item.item_type);

    select * into v_target
    from public.house_inventory_items i
    where i.house_id = v_item.house_id
      and coalesce(i.parent_item_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(v_parent_item_id, '00000000-0000-0000-0000-000000000000'::uuid)
      and i.slot_index = v_slot_index
      and i.id <> v_item.id
    limit 1;

    if v_target.id is not null then
      if public.house_inventory_items_stackable(v_target, v_item) then
        update public.house_inventory_items
        set quantity = quantity + v_item.quantity
        where id = v_target.id
        returning * into v_target;

        delete from public.house_inventory_items
        where id = v_item.id;

        return public.house_item_record_to_json(v_target);
      end if;

      select coalesce(min(i.slot_index), 0) - 1 into v_temporary_slot_index
      from public.house_inventory_items i
      where i.house_id = v_item.house_id
        and coalesce(i.parent_item_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(v_parent_item_id, '00000000-0000-0000-0000-000000000000'::uuid);

      update public.house_inventory_items
      set parent_item_id = v_parent_item_id,
          slot_index = v_temporary_slot_index
      where id = v_target.id;

      update public.house_inventory_items
      set parent_item_id = v_parent_item_id,
          slot_index = v_slot_index
      where id = p_item_id
      returning * into v_item;

      update public.house_inventory_items
      set parent_item_id = v_original_parent_item_id,
          slot_index = v_original_slot_index
      where id = v_target.id;

      return public.house_item_record_to_json(v_item);
    end if;

    update public.house_inventory_items
    set parent_item_id = v_parent_item_id,
        slot_index = v_slot_index
    where id = p_item_id
    returning * into v_item;
  end if;

  return public.house_item_record_to_json(v_item);
end;
$$;

drop function if exists public.drop_house_inventory_item_quantity(text, uuid, int);
drop function if exists public.drop_house_inventory_item_quantity(text, uuid, integer);

create or replace function public.drop_house_inventory_item_quantity(
  p_session_token text,
  p_item_id uuid,
  p_quantity numeric
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_item public.house_inventory_items%rowtype;
  v_drop_quantity numeric;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;

  select * into v_item from public.house_inventory_items where id = p_item_id;
  if v_item.id is null then raise exception 'House item not found.'; end if;

  if not exists (
    select 1 from public.player_houses house
    where house.id = v_item.house_id
      and public.static_home_access(v_profile, house, public.normalize_item_type(v_item.item_type) = 'pet')
  ) then raise exception 'You do not have permission to use that property.'; end if;

  if v_profile.role <> 'dm'::public.user_role
    and v_item.owner_user_id is distinct from v_profile.id
    and not exists (
      select 1
      from public.house_unit_access_permissions a
      where a.house_id = v_item.house_id
        and a.grantee_user_id = v_profile.id
        and case
          when public.normalize_item_type(v_item.item_type) = 'pet'
            or (v_item.parent_item_id is null and v_item.slot_index >= public.house_stable_slot_offset())
            then a.can_access_stable
          else a.can_access_house
        end
    )
  then
    raise exception 'You do not have permission to use that house section.';
  end if;

  v_drop_quantity := public.assert_valid_item_quantity(v_item.item_name, v_item.item_type, greatest(0.5, coalesce(p_quantity, 1)));

  if v_drop_quantity >= v_item.quantity then
    delete from public.house_inventory_items where id = v_item.id;
    return null;
  end if;

  update public.house_inventory_items
  set quantity = quantity - v_drop_quantity
  where id = v_item.id
  returning * into v_item;

  return public.house_item_record_to_json(v_item);
end;
$$;

create or replace function public.move_inventory_item_to_static_house(
  p_session_token text,
  p_item_id uuid,
  p_slot_index int default null,
  p_parent_item_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_character public.characters%rowtype;
  v_house public.player_houses%rowtype;
  v_item public.inventory_items%rowtype;
  v_target public.house_inventory_items%rowtype;
  v_house_item public.house_inventory_items%rowtype;
  v_slot_index int;
  v_is_pet boolean;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;

  select * into v_item from public.inventory_items where id = p_item_id;
  if v_item.id is null then raise exception 'Item not found.'; end if;

  v_character := public.assert_inventory_access(v_profile, v_item.character_id, false);
  if v_character.owner_user_id is null then
    raise exception 'That character is not assigned to a player house.';
  end if;

  if v_item.is_storage and exists (select 1 from public.inventory_items child where child.parent_item_id = v_item.id) then
    raise exception 'Empty this storage item before sending it to the house.';
  end if;

  v_house := public.get_required_player_house(v_character.owner_user_id);
  v_is_pet := public.normalize_item_type(v_item.item_type) = 'pet';

  if p_slot_index is null and not v_is_pet and not v_item.is_storage then
    select * into v_target
    from public.house_inventory_items h
    where h.owner_user_id = v_character.owner_user_id
      and h.parent_item_id is null
      and lower(public.normalize_item_name(h.item_name)) = lower(public.normalize_item_name(v_item.item_name))
      and public.normalize_item_type(h.item_type) = public.normalize_item_type(v_item.item_type)
      and h.rarity = v_item.rarity
      and coalesce(h.enchantment, '') = coalesce(v_item.enchantment, '')
      and coalesce(h.rune_name, '') = coalesce(v_item.rune_name, '')
      and coalesce(h.material, '') = coalesce(v_item.material, '')
      and coalesce(h.potion_strength, '') = coalesce(v_item.potion_strength, '')
      and coalesce(h.potion_property, '') = coalesce(v_item.potion_property, '')
      and coalesce(h.potion_quality, '') = coalesce(v_item.potion_quality, '')
      and h.enhancement_count = v_item.enhancement_count
      and h.is_two_handed = v_item.is_two_handed
      and h.is_accessory = v_item.is_accessory
      and h.modifiers = v_item.modifiers
      and h.item_type <> 'pet'
      and h.is_storage = false
      and public.item_catalog_stackable(v_item.item_name, v_item.item_type)
    order by h.slot_index
    limit 1;

    if v_target.id is not null then
      update public.house_inventory_items
      set quantity = quantity + v_item.quantity
      where id = v_target.id;

      delete from public.inventory_items where id = v_item.id;
      return public.get_player_house(p_session_token, v_character.owner_user_id);
    end if;
  end if;

  if p_slot_index is null then
    v_slot_index := case
      when v_is_pet then public.find_first_free_house_stable_slot(v_character.owner_user_id, v_house)
      else public.find_first_free_house_slot(v_character.owner_user_id, p_parent_item_id, v_house.inventory_slots)
    end;
  else
    v_slot_index := p_slot_index;
  end if;

  if v_slot_index is null then
    raise exception using message = case when v_is_pet then 'No open stable slot.' else 'No open house inventory slot.' end;
  end if;

  perform public.assert_house_item_slot_capacity(v_house, p_parent_item_id, v_slot_index, v_item.item_type);

  select * into v_target
  from public.house_inventory_items h
  where h.owner_user_id = v_character.owner_user_id
    and coalesce(h.parent_item_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(p_parent_item_id, '00000000-0000-0000-0000-000000000000'::uuid)
    and h.slot_index = v_slot_index
  limit 1;

  if v_target.id is not null then
    if not v_is_pet
      and not v_item.is_storage
      and not v_target.is_storage
      and lower(public.normalize_item_name(v_target.item_name)) = lower(public.normalize_item_name(v_item.item_name))
      and public.normalize_item_type(v_target.item_type) = public.normalize_item_type(v_item.item_type)
      and v_target.rarity = v_item.rarity
      and coalesce(v_target.enchantment, '') = coalesce(v_item.enchantment, '')
      and coalesce(v_target.rune_name, '') = coalesce(v_item.rune_name, '')
      and coalesce(v_target.material, '') = coalesce(v_item.material, '')
      and coalesce(v_target.potion_strength, '') = coalesce(v_item.potion_strength, '')
      and coalesce(v_target.potion_property, '') = coalesce(v_item.potion_property, '')
      and coalesce(v_target.potion_quality, '') = coalesce(v_item.potion_quality, '')
      and v_target.enhancement_count = v_item.enhancement_count
      and v_target.is_two_handed = v_item.is_two_handed
      and v_target.is_accessory = v_item.is_accessory
      and v_target.modifiers = v_item.modifiers
      and public.item_catalog_stackable(v_item.item_name, v_item.item_type)
    then
      update public.house_inventory_items
      set quantity = quantity + v_item.quantity
      where id = v_target.id;

      delete from public.inventory_items where id = v_item.id;
      return public.get_player_house(p_session_token, v_character.owner_user_id);
    end if;

    raise exception 'That house slot is already occupied.';
  end if;

  insert into public.house_inventory_items (
    owner_user_id, parent_item_id, slot_index, item_name, display_name, item_description, item_type, rarity, quantity,
    is_accessory, is_storage, storage_capacity, modifiers, enchantment, rune_name, material, enhancement_count,
    is_two_handed, potion_strength, potion_property, potion_quality, spell_book_form
  )
  values (
    v_character.owner_user_id, p_parent_item_id, v_slot_index, v_item.item_name, v_item.display_name, v_item.item_description,
    v_item.item_type, v_item.rarity, v_item.quantity, v_item.is_accessory, v_item.is_storage, v_item.storage_capacity,
    v_item.modifiers, v_item.enchantment, v_item.rune_name, v_item.material, v_item.enhancement_count,
    v_item.is_two_handed, v_item.potion_strength, v_item.potion_property, v_item.potion_quality, v_item.spell_book_form
  )
  returning * into v_house_item;

  delete from public.inventory_items where id = v_item.id;
  return public.get_player_house(p_session_token, v_character.owner_user_id);
end;
$$;

create or replace function public.move_inventory_item_to_house(
  p_session_token text,
  p_item_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_character public.characters%rowtype;
  v_house public.player_houses%rowtype;
  v_item public.inventory_items%rowtype;
  v_target public.house_inventory_items%rowtype;
  v_house_item public.house_inventory_items%rowtype;
  v_slot_index int;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;

  select * into v_item from public.inventory_items where id = p_item_id;
  if v_item.id is null then raise exception 'Item not found.'; end if;

  v_character := public.assert_inventory_access(v_profile, v_item.character_id, false);
  if v_character.owner_user_id is null then
    raise exception 'That character is not assigned to a player house.';
  end if;

  if v_item.is_storage and exists (
    select 1
    from public.inventory_items child
    where child.parent_item_id = v_item.id
  ) then
    raise exception 'Empty this storage item before sending it to the house.';
  end if;

  v_house := public.get_required_player_house(v_character.owner_user_id);

  select * into v_target
  from public.house_inventory_items h
  where h.owner_user_id = v_character.owner_user_id
    and lower(public.normalize_item_name(h.item_name)) = lower(public.normalize_item_name(v_item.item_name))
    and public.normalize_item_type(h.item_type) = public.normalize_item_type(v_item.item_type)
    and h.rarity = v_item.rarity
    and coalesce(h.enchantment, '') = coalesce(v_item.enchantment, '')
    and coalesce(h.rune_name, '') = coalesce(v_item.rune_name, '')
    and coalesce(h.material, '') = coalesce(v_item.material, '')
    and coalesce(h.potion_strength, '') = coalesce(v_item.potion_strength, '')
    and coalesce(h.potion_property, '') = coalesce(v_item.potion_property, '')
    and coalesce(h.potion_quality, '') = coalesce(v_item.potion_quality, '')
    and h.enhancement_count = v_item.enhancement_count
    and h.is_two_handed = v_item.is_two_handed
    and h.is_accessory = v_item.is_accessory
    and h.modifiers = v_item.modifiers
    and h.item_type <> 'pet'
    and h.is_storage = false
    and v_item.is_storage = false
    and public.item_catalog_stackable(v_item.item_name, v_item.item_type)
  order by h.slot_index
  limit 1;

  if v_target.id is not null then
    update public.house_inventory_items
    set quantity = quantity + v_item.quantity
    where id = v_target.id;

    delete from public.inventory_items where id = v_item.id;
    return public.get_player_house(p_session_token, v_character.owner_user_id);
  end if;

  v_slot_index := case
    when v_item.item_type = 'pet' then public.find_first_free_house_stable_slot(v_character.owner_user_id, v_house)
    else public.find_first_free_house_slot(v_character.owner_user_id, null::uuid, v_house.inventory_slots)
  end;
  if v_slot_index is null then
    if v_item.item_type = 'pet' then
      raise exception 'No open stable slot.';
    end if;
    raise exception 'No open house inventory slot.';
  end if;

  insert into public.house_inventory_items (
    owner_user_id,
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
    v_character.owner_user_id,
    null,
    v_slot_index,
    v_item.item_name,
    v_item.display_name,
    v_item.item_description,
    v_item.item_type,
    v_item.rarity,
    v_item.quantity,
    v_item.is_accessory,
    v_item.is_storage,
    v_item.storage_capacity,
    v_item.modifiers,
    v_item.enchantment,
    v_item.rune_name,
    v_item.material,
    v_item.enhancement_count,
    v_item.is_two_handed,
    v_item.potion_strength,
    v_item.potion_property,
    v_item.potion_quality
  )
  returning * into v_house_item;

  delete from public.inventory_items where id = v_item.id;
  return public.get_player_house(p_session_token, v_character.owner_user_id);
end;
$$;

drop function if exists public.move_inventory_item_to_house_slot(text, uuid, int);

create or replace function public.move_inventory_item_to_house_slot(
  p_session_token text,
  p_item_id uuid,
  p_slot_index int,
  p_parent_item_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_character public.characters%rowtype;
  v_house public.player_houses%rowtype;
  v_item public.inventory_items%rowtype;
  v_target public.house_inventory_items%rowtype;
  v_house_item public.house_inventory_items%rowtype;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;

  select * into v_item from public.inventory_items where id = p_item_id;
  if v_item.id is null then raise exception 'Item not found.'; end if;

  v_character := public.assert_inventory_access(v_profile, v_item.character_id, false);
  if v_character.owner_user_id is null then
    raise exception 'That character is not assigned to a player house.';
  end if;

  if v_item.is_storage and exists (
    select 1
    from public.inventory_items child
    where child.parent_item_id = v_item.id
  ) then
    raise exception 'Empty this storage item before sending it to the house.';
  end if;

  v_house := public.get_required_player_house(v_character.owner_user_id);
  perform public.assert_house_item_slot_capacity(v_house, p_parent_item_id, p_slot_index, v_item.item_type);

  select * into v_target
  from public.house_inventory_items h
  where h.owner_user_id = v_character.owner_user_id
    and coalesce(h.parent_item_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(p_parent_item_id, '00000000-0000-0000-0000-000000000000'::uuid)
    and h.slot_index = p_slot_index
  limit 1;

  if v_target.id is not null then
    if lower(public.normalize_item_name(v_target.item_name)) = lower(public.normalize_item_name(v_item.item_name))
      and public.normalize_item_type(v_target.item_type) = public.normalize_item_type(v_item.item_type)
      and v_target.rarity = v_item.rarity
      and coalesce(v_target.enchantment, '') = coalesce(v_item.enchantment, '')
      and coalesce(v_target.rune_name, '') = coalesce(v_item.rune_name, '')
      and coalesce(v_target.material, '') = coalesce(v_item.material, '')
      and coalesce(v_target.potion_strength, '') = coalesce(v_item.potion_strength, '')
      and coalesce(v_target.potion_property, '') = coalesce(v_item.potion_property, '')
      and coalesce(v_target.potion_quality, '') = coalesce(v_item.potion_quality, '')
      and v_target.enhancement_count = v_item.enhancement_count
      and v_target.is_two_handed = v_item.is_two_handed
      and v_target.is_accessory = v_item.is_accessory
      and v_target.modifiers = v_item.modifiers
      and v_target.item_type <> 'pet'
      and v_target.is_storage = false
      and v_item.is_storage = false
      and public.item_catalog_stackable(v_item.item_name, v_item.item_type)
    then
      update public.house_inventory_items
      set quantity = quantity + v_item.quantity
      where id = v_target.id;

      delete from public.inventory_items where id = v_item.id;
      return public.get_player_house(p_session_token, v_character.owner_user_id);
    end if;

    raise exception 'That house slot is already occupied.';
  end if;

  insert into public.house_inventory_items (
    owner_user_id,
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
    v_character.owner_user_id,
    p_parent_item_id,
    p_slot_index,
    v_item.item_name,
    v_item.display_name,
    v_item.item_description,
    v_item.item_type,
    v_item.rarity,
    v_item.quantity,
    v_item.is_accessory,
    v_item.is_storage,
    v_item.storage_capacity,
    v_item.modifiers,
    v_item.enchantment,
    v_item.rune_name,
    v_item.material,
    v_item.enhancement_count,
    v_item.is_two_handed,
    v_item.potion_strength,
    v_item.potion_property,
    v_item.potion_quality
  )
  returning * into v_house_item;

  delete from public.inventory_items where id = v_item.id;
  return public.get_player_house(p_session_token, v_character.owner_user_id);
end;
$$;

create or replace function public.move_house_item_to_inventory(
  p_session_token text,
  p_house_item_id uuid,
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
  v_house public.player_houses%rowtype;
  v_target_house public.player_houses%rowtype;
  v_house_item public.house_inventory_items%rowtype;
  v_active_pet public.inventory_items%rowtype;
  v_target public.inventory_items%rowtype;
  v_item public.inventory_items%rowtype;
  v_slot_index int;
  v_active_pet_stable_slot int;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;

  select * into v_house_item
  from public.house_inventory_items
  where id = p_house_item_id;

  if v_house_item.id is null then raise exception 'House item not found.'; end if;

  v_house := public.assert_house_access(v_profile, v_house_item.owner_user_id, false);
  v_character := public.assert_inventory_access(v_profile, p_character_id, false);

  if v_profile.role <> 'dm'::public.user_role
    and not exists (
      select 1
      from public.house_access_permissions a
      where a.owner_user_id = v_house.owner_user_id
        and a.grantee_user_id = v_profile.id
        and case
          when public.normalize_item_type(v_house_item.item_type) = 'pet' then a.can_access_stable
          else a.can_access_house
        end
    )
    and (
      v_character.owner_user_id is distinct from v_house.owner_user_id
      or v_house.owner_user_id is distinct from v_profile.id
    )
  then
    raise exception 'That character cannot pull from this house.';
  end if;

  if v_house_item.is_storage and exists (
    select 1 from public.house_inventory_items child where child.parent_item_id = v_house_item.id
  ) then
    raise exception 'Empty this storage item before taking it from the house.';
  end if;

  if public.normalize_item_type(v_house_item.item_type) = 'pet' then
    select * into v_active_pet
    from public.inventory_items i
    where i.character_id = v_character.id
      and i.loadout_slot = 'active-pet'
    limit 1;

    if v_active_pet.id is not null then
      if v_character.owner_user_id is null then
        raise exception 'Active pet slot is occupied and that character has no player stable.';
      end if;

      v_target_house := public.get_required_player_house(v_character.owner_user_id);
      v_active_pet_stable_slot := case
        when v_house.owner_user_id = v_character.owner_user_id
          and v_house_item.parent_item_id is null
          and v_house_item.slot_index >= public.house_stable_slot_offset()
          and v_house_item.slot_index < public.house_stable_slot_offset() + v_target_house.stable_slots
          then v_house_item.slot_index
        else public.find_first_free_house_stable_slot(v_character.owner_user_id, v_target_house)
      end;

      if v_active_pet_stable_slot is null then
        raise exception 'Active pet slot is occupied and no stable slot is open.';
      end if;

      if v_house.owner_user_id <> v_character.owner_user_id
        and exists (
          select 1
          from public.house_inventory_items h
          where h.owner_user_id = v_character.owner_user_id
            and h.parent_item_id is null
            and h.slot_index = v_active_pet_stable_slot
        )
      then
        raise exception 'Active pet slot is occupied and no stable slot is open.';
      end if;

      if v_house.owner_user_id = v_character.owner_user_id
        and v_active_pet_stable_slot = v_house_item.slot_index
      then
        delete from public.house_inventory_items where id = v_house_item.id;
      end if;

      insert into public.house_inventory_items (
        owner_user_id,
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
        v_character.owner_user_id,
        null,
        v_active_pet_stable_slot,
        v_active_pet.item_name,
        v_active_pet.display_name,
        v_active_pet.item_description,
        'pet',
        v_active_pet.rarity,
        1,
        v_active_pet.is_accessory,
        false,
        0,
        v_active_pet.modifiers,
        v_active_pet.enchantment,
        v_active_pet.rune_name,
        v_active_pet.material,
        v_active_pet.enhancement_count,
        v_active_pet.is_two_handed,
        null,
        null,
        null
      );

      delete from public.inventory_items where id = v_active_pet.id;
    end if;

    insert into public.inventory_items (
      character_id,
      parent_item_id,
      slot_index,
      loadout_slot,
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
      v_character.id,
      null,
      0,
      'active-pet',
      v_house_item.item_name,
      v_house_item.display_name,
      v_house_item.item_description,
      'pet',
      v_house_item.rarity,
      1,
      v_house_item.is_accessory,
      false,
      0,
      v_house_item.modifiers,
      v_house_item.enchantment,
      v_house_item.rune_name,
      v_house_item.material,
      v_house_item.enhancement_count,
      v_house_item.is_two_handed,
      null,
      null,
      null
    )
    returning * into v_item;

    delete from public.house_inventory_items where id = v_house_item.id;
    return public.get_character_inventory(p_session_token, v_character.id);
  end if;

  select * into v_target
  from public.inventory_items i
  where i.character_id = v_character.id
    and i.parent_item_id is null
    and i.loadout_slot is null
    and lower(public.normalize_item_name(i.item_name)) = lower(public.normalize_item_name(v_house_item.item_name))
    and public.normalize_item_type(i.item_type) = public.normalize_item_type(v_house_item.item_type)
    and i.rarity = v_house_item.rarity
    and coalesce(i.enchantment, '') = coalesce(v_house_item.enchantment, '')
    and coalesce(i.rune_name, '') = coalesce(v_house_item.rune_name, '')
    and coalesce(i.material, '') = coalesce(v_house_item.material, '')
    and coalesce(i.potion_strength, '') = coalesce(v_house_item.potion_strength, '')
    and coalesce(i.potion_property, '') = coalesce(v_house_item.potion_property, '')
    and coalesce(i.potion_quality, '') = coalesce(v_house_item.potion_quality, '')
    and i.enhancement_count = v_house_item.enhancement_count
    and i.is_two_handed = v_house_item.is_two_handed
    and i.is_accessory = v_house_item.is_accessory
    and i.modifiers = v_house_item.modifiers
    and i.item_type <> 'pet'
    and v_house_item.item_type <> 'pet'
    and i.is_storage = false
    and v_house_item.is_storage = false
    and public.item_catalog_stackable(v_house_item.item_name, v_house_item.item_type)
  order by i.slot_index
  limit 1;

  if v_target.id is not null then
    update public.inventory_items
    set quantity = quantity + v_house_item.quantity
    where id = v_target.id;

    delete from public.house_inventory_items where id = v_house_item.id;
    return public.get_character_inventory(p_session_token, v_character.id);
  end if;

  v_slot_index := public.find_first_free_inventory_slot(v_character.id, null::uuid, v_character.inventory_slots);
  if v_slot_index is null then
    raise exception 'No open inventory slot.';
  end if;

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
    v_character.id,
    null,
    v_slot_index,
    v_house_item.item_name,
    v_house_item.display_name,
    v_house_item.item_description,
    v_house_item.item_type,
    v_house_item.rarity,
    v_house_item.quantity,
    v_house_item.is_accessory,
    v_house_item.is_storage,
    v_house_item.storage_capacity,
    v_house_item.modifiers,
    v_house_item.enchantment,
    v_house_item.rune_name,
    v_house_item.material,
    v_house_item.enhancement_count,
    v_house_item.is_two_handed,
    v_house_item.potion_strength,
    v_house_item.potion_property,
    v_house_item.potion_quality
  )
  returning * into v_item;

  delete from public.house_inventory_items where id = v_house_item.id;
  return public.get_character_inventory(p_session_token, v_character.id);
end;
$$;

create or replace function public.inventory_storage_visible_to_profile(
  p_profile public.profiles,
  p_storage public.inventory_items,
  p_owner_character public.characters
)
returns boolean
language sql
stable
set search_path = public
as $$
  select coalesce(p_storage.is_storage, false)
    and p_storage.parent_item_id is null
    and p_storage.loadout_slot is null
    and (
      public.inventory_item_is_wagon(p_storage.item_name, p_storage.item_type)
      or (
        public.inventory_item_is_mobile_home_storage(p_storage.item_name, p_storage.item_type)
        and (
          p_profile.role = 'dm'::public.user_role
          or p_owner_character.owner_user_id is not distinct from p_profile.id
          or exists (
            select 1
            from public.mobile_storage_access_permissions a
            where a.storage_item_id = p_storage.id
              and a.owner_user_id = p_owner_character.owner_user_id
              and a.grantee_user_id = p_profile.id
          )
        )
      )
      or (
        public.inventory_item_is_caged_wagon_storage(p_storage.item_name, p_storage.item_type)
        and (
          p_profile.role = 'dm'::public.user_role
          or p_owner_character.owner_user_id is not distinct from p_profile.id
          or exists (
            select 1
            from public.mobile_storage_access_permissions a
            where a.storage_item_id = p_storage.id
              and a.owner_user_id = p_owner_character.owner_user_id
              and a.grantee_user_id = p_profile.id
          )
        )
      )
    )
$$;

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
        'wagon', public.inventory_item_record_to_json(w),
        'ownerCharacterId', owner_character.id,
        'ownerName', owner_character.name,
        'ownerUserId', owner_character.owner_user_id,
        'locationName', owner_character.location_name,
        'canManage', v_profile.role = 'dm'::public.user_role or owner_character.owner_user_id is not distinct from v_profile.id
      ) order by owner_character.name, w.item_name), '[]'::jsonb)
      from public.inventory_items w
      join public.characters owner_character on owner_character.id = w.character_id
      where public.inventory_storage_visible_to_profile(v_profile, w, owner_character)
        and public.characters_share_location(owner_character, v_character)
    ),
    'items', (
      select coalesce(jsonb_agg(public.inventory_item_record_to_json(child) order by child.parent_item_id, child.slot_index, child.item_name), '[]'::jsonb)
      from public.inventory_items child
      join public.inventory_items w on w.id = child.parent_item_id
      join public.characters owner_character on owner_character.id = w.character_id
      where public.inventory_storage_visible_to_profile(v_profile, w, owner_character)
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
        join public.inventory_items w on w.id = log_entry.wagon_item_id
        join public.characters owner_character on owner_character.id = w.character_id
        where public.inventory_storage_visible_to_profile(v_profile, w, owner_character)
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
  p_slot_index int
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

  select * into v_item from public.inventory_items where id = p_item_id;
  if v_item.id is null then raise exception 'Item not found.'; end if;
  if v_item.character_id <> v_actor.id then
    raise exception 'You can only move this character''s items into a wagon.';
  end if;
  if v_item.is_storage and exists (select 1 from public.inventory_items child where child.parent_item_id = v_item.id) then
    raise exception 'Empty this storage item before moving it into a wagon.';
  end if;
  select * into v_wagon from public.inventory_items where id = p_wagon_id;
  if v_wagon.id is null
    or not v_wagon.is_storage
    or not (
      public.inventory_item_is_wagon(v_wagon.item_name, v_wagon.item_type)
      or public.inventory_item_is_mobile_home_storage(v_wagon.item_name, v_wagon.item_type)
      or public.inventory_item_is_caged_wagon_storage(v_wagon.item_name, v_wagon.item_type)
    )
  then
    raise exception 'Storage was not found.';
  end if;

  if public.inventory_item_is_caged_wagon_storage(v_wagon.item_name, v_wagon.item_type)
    and public.normalize_item_type(v_item.item_type) <> 'pet'
  then
    raise exception 'Only animals can be placed in a Caged Wagon.';
  end if;

  if public.normalize_item_type(v_item.item_type) = 'pet'
    and not public.inventory_item_is_caged_wagon_storage(v_wagon.item_name, v_wagon.item_type)
  then
    raise exception 'Animals can only occupy active pet slots, house stable slots, or Caged Wagon slots.';
  end if;

  select * into v_wagon_owner from public.characters where id = v_wagon.character_id;
  if v_wagon_owner.id is null or not public.characters_share_location(v_wagon_owner, v_actor) then
    raise exception 'That storage is not in this character''s location.';
  end if;

  if not public.inventory_storage_visible_to_profile(v_profile, v_wagon, v_wagon_owner) then
    raise exception 'You do not have permission to use that storage.';
  end if;

  perform public.assert_inventory_slot_capacity(v_wagon_owner, v_wagon.id, p_slot_index);

  select * into v_target
  from public.inventory_items i
  where i.character_id = v_wagon.character_id
    and i.parent_item_id = v_wagon.id
    and i.loadout_slot is null
    and i.slot_index = p_slot_index
    and i.id <> v_item.id
  limit 1;

  if v_target.id is not null then
    if public.inventory_items_stackable(v_target, v_item) then
      insert into public.wagon_activity_log (wagon_item_id, actor_character_id, actor_name, action, item_name, quantity)
      values (v_wagon.id, v_actor.id, v_actor.name, 'stored', v_item.item_name, v_item.quantity);

      update public.inventory_items
      set quantity = quantity + v_item.quantity
      where id = v_target.id;

      delete from public.inventory_items where id = v_item.id;
      return public.get_location_wagon_storage(p_session_token, p_actor_character_id);
    end if;

    raise exception 'That wagon slot is already occupied.';
  end if;

  update public.inventory_items
  set character_id = v_wagon.character_id,
      parent_item_id = v_wagon.id,
      slot_index = p_slot_index,
      loadout_slot = null
  where id = v_item.id;

  insert into public.wagon_activity_log (wagon_item_id, actor_character_id, actor_name, action, item_name, quantity)
  values (v_wagon.id, v_actor.id, v_actor.name, 'stored', v_item.item_name, v_item.quantity);

  return public.get_location_wagon_storage(p_session_token, p_actor_character_id);
end;
$$;

create or replace function public.move_wagon_item_to_inventory(
  p_session_token text,
  p_actor_character_id uuid,
  p_item_id uuid,
  p_parent_item_id uuid default null,
  p_slot_index int default null
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
  v_slot_index int;
  v_capacity int;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;

  v_actor := public.assert_inventory_access(v_profile, p_actor_character_id, false);

  select * into v_item from public.inventory_items where id = p_item_id;
  if v_item.id is null then raise exception 'Wagon item not found.'; end if;
  if v_item.parent_item_id is null then raise exception 'That item is not inside a wagon.'; end if;

  select * into v_wagon from public.inventory_items where id = v_item.parent_item_id;
  if v_wagon.id is null
    or not v_wagon.is_storage
    or not (
      public.inventory_item_is_wagon(v_wagon.item_name, v_wagon.item_type)
      or public.inventory_item_is_mobile_home_storage(v_wagon.item_name, v_wagon.item_type)
      or public.inventory_item_is_caged_wagon_storage(v_wagon.item_name, v_wagon.item_type)
    )
  then
    raise exception 'Storage was not found.';
  end if;

  select * into v_wagon_owner from public.characters where id = v_wagon.character_id;
  if v_wagon_owner.id is null or not public.characters_share_location(v_wagon_owner, v_actor) then
    raise exception 'That storage is not in this character''s location.';
  end if;

  if not public.inventory_storage_visible_to_profile(v_profile, v_wagon, v_wagon_owner) then
    raise exception 'You do not have permission to use that storage.';
  end if;

  if v_item.is_storage and exists (select 1 from public.inventory_items child where child.parent_item_id = v_item.id) then
    raise exception 'Empty this storage item before taking it from the wagon.';
  end if;

  if public.normalize_item_type(v_item.item_type) = 'pet' then
    insert into public.wagon_activity_log (wagon_item_id, actor_character_id, actor_name, action, item_name, quantity)
    values (v_wagon.id, v_actor.id, v_actor.name, 'taken', v_item.item_name, 1);

    perform public.place_pet_item_for_character(
      v_actor.id,
      v_item.item_name,
      v_item.display_name,
      v_item.item_description,
      v_item.rarity,
      1,
      v_item.is_accessory,
      v_item.modifiers,
      v_item.enchantment,
      v_item.rune_name,
      v_item.material,
      v_item.enhancement_count,
      v_item.is_two_handed
    );

    delete from public.inventory_items where id = v_item.id;
    return public.get_character_inventory(p_session_token, p_actor_character_id);
  end if;

  v_capacity := public.assert_inventory_slot_capacity(v_actor, p_parent_item_id, coalesce(p_slot_index, 0));
  v_slot_index := p_slot_index;
  if v_slot_index is null then
    v_slot_index := public.find_first_free_inventory_slot(v_actor.id, p_parent_item_id, v_capacity);
  end if;
  if v_slot_index is null then raise exception 'No open inventory slot.'; end if;
  perform public.assert_inventory_slot_capacity(v_actor, p_parent_item_id, v_slot_index);

  select * into v_target
  from public.inventory_items i
  where i.character_id = v_actor.id
    and coalesce(i.parent_item_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(p_parent_item_id, '00000000-0000-0000-0000-000000000000'::uuid)
    and i.loadout_slot is null
    and i.slot_index = v_slot_index
  limit 1;

  if v_target.id is not null then
    if public.inventory_items_stackable(v_target, v_item) then
      insert into public.wagon_activity_log (wagon_item_id, actor_character_id, actor_name, action, item_name, quantity)
      values (v_wagon.id, v_actor.id, v_actor.name, 'taken', v_item.item_name, v_item.quantity);

      update public.inventory_items
      set quantity = quantity + v_item.quantity
      where id = v_target.id;

      delete from public.inventory_items where id = v_item.id;
      return public.get_character_inventory(p_session_token, p_actor_character_id);
    end if;

    raise exception 'That inventory slot is already occupied.';
  end if;

  update public.inventory_items
  set character_id = v_actor.id,
      parent_item_id = p_parent_item_id,
      slot_index = v_slot_index,
      loadout_slot = null
  where id = v_item.id;

  insert into public.wagon_activity_log (wagon_item_id, actor_character_id, actor_name, action, item_name, quantity)
  values (v_wagon.id, v_actor.id, v_actor.name, 'taken', v_item.item_name, v_item.quantity);

  return public.get_character_inventory(p_session_token, p_actor_character_id);
end;
$$;

create or replace function public.apply_inventory_item_rune(
  p_session_token text,
  p_target_item_id uuid,
  p_rune_item_id uuid,
  p_source text default 'inventory'
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_character public.characters%rowtype;
  v_target public.inventory_items%rowtype;
  v_inventory_rune public.inventory_items%rowtype;
  v_house_rune public.house_inventory_items%rowtype;
  v_source text := lower(trim(coalesce(p_source, 'inventory')));
  v_rune_name text;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;

  select * into v_target from public.inventory_items where id = p_target_item_id;
  if v_target.id is null then raise exception 'Item not found.'; end if;

  v_character := public.assert_inventory_access(v_profile, v_target.character_id, false);

  if not public.inventory_item_is_mythril(v_target.item_name, v_target.material) then
    raise exception 'Runes can only be applied to Mythril items.';
  end if;

  if v_source = 'inventory' then
    select * into v_inventory_rune
    from public.inventory_items
    where id = p_rune_item_id
      and character_id = v_target.character_id
      and item_type = 'rune'
      and quantity >= 1
      and id <> v_target.id;

    if v_inventory_rune.id is null then
      raise exception 'That inventory rune was not found.';
    end if;

    v_rune_name := v_inventory_rune.item_name;

    if v_inventory_rune.quantity <= 1 then
      delete from public.inventory_items where id = v_inventory_rune.id;
    else
      update public.inventory_items
      set quantity = quantity - 1
      where id = v_inventory_rune.id;
    end if;
  elsif v_source = 'house' then
    if v_character.owner_user_id is null then
      raise exception 'That character is not assigned to a player house.';
    end if;

    perform public.assert_house_access(v_profile, v_character.owner_user_id, false);

    select * into v_house_rune
    from public.house_inventory_items
    where id = p_rune_item_id
      and owner_user_id = v_character.owner_user_id
      and item_type = 'rune'
      and quantity >= 1;

    if v_house_rune.id is null then
      raise exception 'That house rune was not found.';
    end if;

    v_rune_name := v_house_rune.item_name;

    if v_house_rune.quantity <= 1 then
      delete from public.house_inventory_items where id = v_house_rune.id;
    else
      update public.house_inventory_items
      set quantity = quantity - 1
      where id = v_house_rune.id;
    end if;
  else
    raise exception 'Rune source must be inventory or house.';
  end if;

  update public.inventory_items
  set rune_name = v_rune_name
  where id = v_target.id
  returning * into v_target;

  return public.inventory_item_record_to_json(v_target);
end;
$$;

create or replace function public.add_campaign_property(
  p_session_token text,
  p_owner_user_id uuid,
  p_caretaker_character_id uuid,
  p_name text,
  p_property_type text,
  p_location text,
  p_is_pet boolean default false,
  p_slot_index int default 0,
  p_storage_capacity int default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_house public.player_houses%rowtype;
  v_property public.campaign_properties%rowtype;
  v_caretaker public.characters%rowtype;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  v_house := public.assert_house_access(v_profile, p_owner_user_id, true);

  if length(trim(coalesce(p_name, ''))) = 0 then
    raise exception 'Property name is required.';
  end if;

  if coalesce(p_slot_index, 0) < 0 or coalesce(p_slot_index, 0) >= v_house.property_slots then
    raise exception 'Property slot is outside the house capacity.';
  end if;

  if p_caretaker_character_id is not null then
    select * into v_caretaker from public.characters where id = p_caretaker_character_id;
    if v_caretaker.id is null or v_caretaker.owner_user_id is distinct from p_owner_user_id then
      raise exception 'Property caretaker must belong to that house owner.';
    end if;
  end if;

  insert into public.campaign_properties (
    owner_user_id,
    caretaker_character_id,
    property_name,
    property_type,
    property_location,
    is_pet,
    slot_index,
    storage_capacity
  )
  values (
    p_owner_user_id,
    case when p_location = 'with_character' then p_caretaker_character_id else null end,
    trim(p_name),
    coalesce(nullif(p_property_type, ''), 'other'),
    coalesce(nullif(p_location, ''), 'at_house'),
    coalesce(p_is_pet, false) or coalesce(nullif(p_property_type, ''), 'other') = 'pet',
    greatest(0, coalesce(p_slot_index, 0)),
    greatest(0, coalesce(p_storage_capacity, 0))
  )
  returning * into v_property;

  return public.property_record_to_json(v_property);
end;
$$;

create or replace function public.update_campaign_property(
  p_session_token text,
  p_property_id uuid,
  p_patch jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_house public.player_houses%rowtype;
  v_property public.campaign_properties%rowtype;
  v_patch jsonb := coalesce(p_patch, '{}'::jsonb);
  v_owner_user_id uuid;
  v_caretaker_character_id uuid;
  v_location text;
  v_slot_index int;
  v_caretaker public.characters%rowtype;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;

  select * into v_property from public.campaign_properties where id = p_property_id;
  if v_property.id is null then raise exception 'Property not found.'; end if;

  select * into v_house from public.player_houses where id = v_property.house_id;
  if v_house.id is null or not public.static_home_access(v_profile, v_house, false) then
    raise exception 'You do not have permission to use that property.';
  end if;
  v_owner_user_id := v_property.owner_user_id;
  v_location := case when v_patch ? 'location' then coalesce(nullif(v_patch->>'location', ''), v_property.property_location) else v_property.property_location end;
  v_slot_index := case when v_patch ? 'slotIndex' then greatest(0, (v_patch->>'slotIndex')::int) else v_property.slot_index end;
  v_caretaker_character_id := case when v_patch ? 'caretakerCharacterId' then nullif(v_patch->>'caretakerCharacterId', '')::uuid else v_property.caretaker_character_id end;

  if v_slot_index >= v_house.property_slots then
    raise exception 'Property slot is outside the house capacity.';
  end if;
  if exists (
    select 1 from public.campaign_properties occupied
    where occupied.house_id = v_house.id
      and occupied.slot_index = v_slot_index
      and occupied.id <> v_property.id
  ) then
    raise exception 'That property slot is already occupied.';
  end if;

  if v_caretaker_character_id is not null then
    select * into v_caretaker from public.characters where id = v_caretaker_character_id;
    if v_caretaker.id is null or v_caretaker.owner_user_id is distinct from v_owner_user_id then
      raise exception 'Property caretaker must belong to that house owner.';
    end if;
  end if;

  update public.campaign_properties
  set
    property_name = case when v_patch ? 'name' then coalesce(nullif(trim(v_patch->>'name'), ''), property_name) else property_name end,
    property_type = case when v_patch ? 'type' then coalesce(nullif(v_patch->>'type', ''), property_type) else property_type end,
    property_location = v_location,
    caretaker_character_id = case when v_location = 'with_character' then v_caretaker_character_id else null end,
    is_pet = case when v_patch ? 'isPet' then (v_patch->>'isPet')::boolean else is_pet end,
    slot_index = v_slot_index,
    storage_capacity = case when v_patch ? 'storageCapacity' then greatest(0, (v_patch->>'storageCapacity')::int) else storage_capacity end
  where id = p_property_id
  returning * into v_property;

  return public.property_record_to_json(v_property);
end;
$$;

grant execute on function public.get_required_player_house(uuid) to anon, authenticated;
drop function if exists public.ensure_player_house(uuid);
grant execute on function public.assert_house_access(public.profiles, uuid, boolean) to anon, authenticated;
grant execute on function public.house_record_to_json(public.player_houses) to anon, authenticated;
grant execute on function public.house_item_record_to_json(public.house_inventory_items) to anon, authenticated;
grant execute on function public.property_record_to_json(public.campaign_properties) to anon, authenticated;
grant execute on function public.house_access_to_json(public.profiles, uuid) to anon, authenticated;
grant execute on function public.house_permissions_to_json(uuid) to anon, authenticated;
grant execute on function public.mobile_storage_permissions_to_json(uuid) to anon, authenticated;
grant execute on function public.house_inventory_items_stackable(public.house_inventory_items, public.house_inventory_items) to anon, authenticated;
grant execute on function public.inventory_item_is_wagon(text, text) to anon, authenticated;
grant execute on function public.inventory_item_is_mobile_home_storage(text, text) to anon, authenticated;
grant execute on function public.inventory_item_is_caged_wagon_storage(text, text) to anon, authenticated;
grant execute on function public.inventory_storage_visible_to_profile(public.profiles, public.inventory_items, public.characters) to anon, authenticated;
grant execute on function public.find_first_free_house_slot(uuid, uuid, int) to anon, authenticated;
grant execute on function public.house_stable_slot_offset() to anon, authenticated;
grant execute on function public.find_first_free_house_stable_slot(uuid, public.player_houses) to anon, authenticated;
grant execute on function public.assert_house_slot_capacity(public.player_houses, uuid, int) to anon, authenticated;
grant execute on function public.assert_house_item_slot_capacity(public.player_houses, uuid, int, text) to anon, authenticated;
grant execute on function public.get_player_house(text, uuid) to anon, authenticated;
grant execute on function public.add_house_inventory_item(text, uuid, uuid, int, text, text, text, numeric, boolean, int, jsonb, text, text, int, boolean, text, text, text, text, boolean) to anon, authenticated;
grant execute on function public.update_house_inventory_item_state(text, uuid, jsonb) to anon, authenticated;
grant execute on function public.drop_house_inventory_item_quantity(text, uuid, numeric) to anon, authenticated;
grant execute on function public.move_inventory_item_to_house(text, uuid) to anon, authenticated;
grant execute on function public.move_inventory_item_to_house_slot(text, uuid, int, uuid) to anon, authenticated;
grant execute on function public.move_house_item_to_inventory(text, uuid, uuid) to anon, authenticated;
grant execute on function public.place_pet_item_in_caged_wagon_for_character(uuid, text, text, text, public.item_rarity, numeric, boolean, jsonb, text, text, text, int, boolean) to anon, authenticated;
grant execute on function public.place_pet_item_for_character(uuid, text, text, text, public.item_rarity, numeric, boolean, jsonb, text, text, text, int, boolean) to anon, authenticated;
grant execute on function public.place_pet_item_in_stable_for_character(uuid, text, text, text, public.item_rarity, numeric, boolean, jsonb, text, text, text, int, boolean) to anon, authenticated;
grant execute on function public.get_location_wagon_storage(text, uuid) to anon, authenticated;
grant execute on function public.move_inventory_item_to_wagon(text, uuid, uuid, uuid, int) to anon, authenticated;
grant execute on function public.move_wagon_item_to_inventory(text, uuid, uuid, uuid, int) to anon, authenticated;
grant execute on function public.apply_inventory_item_rune(text, uuid, uuid, text) to anon, authenticated;
grant execute on function public.add_campaign_property(text, uuid, uuid, text, text, text, boolean, int, int) to anon, authenticated;
grant execute on function public.update_campaign_property(text, uuid, jsonb) to anon, authenticated;

do $$
declare
  v_sparkle public.characters%rowtype;
  v_slot int;
begin
  select * into v_sparkle
  from public.characters
  where lower(trim(name)) = 'sparkle'
    and kind = 'player'::public.character_kind
  order by created_at
  limit 1;

  if v_sparkle.id is not null and not exists (
    select 1
    from public.inventory_items i
    where lower(public.normalize_item_name(i.item_name)) = lower(public.normalize_item_name('Peaceful Restoration Spell Book'))
      and public.normalize_item_type(i.item_type) = 'spell book'
  ) and not exists (
    select 1
    from public.house_inventory_items h
    where lower(public.normalize_item_name(h.item_name)) = lower(public.normalize_item_name('Peaceful Restoration Spell Book'))
      and public.normalize_item_type(h.item_type) = 'spell book'
  ) then
    v_slot := public.find_first_free_inventory_slot(v_sparkle.id, null, v_sparkle.inventory_slots);
    if v_slot is null then
      v_slot := greatest(0, v_sparkle.inventory_slots);
      update public.characters
      set inventory_slots = inventory_slots + 1
      where id = v_sparkle.id
      returning * into v_sparkle;
    end if;

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
      potion_quality,
      spell_book_form
    )
    values (
      v_sparkle.id,
      null,
      v_slot,
      'Peaceful Restoration Spell Book',
      null,
      $am$Peaceful Restoration - 40 Mana

Form 1: Heals an ally for 75 HP and restores 25 Mana. If the caster is on fire, it instead heals 20 HP and restores 10 Mana.

Form 2: Restores 75 Mana and heals 25 HP. This form cannot be used while the caster is on fire.$am$,
      'spell book',
      'Legendary'::public.item_rarity,
      1,
      false,
      false,
      0,
      '{}'::jsonb,
      null,
      null,
      '',
      0,
      false,
      null,
      null,
      null,
      1
    );
  end if;
end $$;


-- ============================================================
-- ============================================================

-- Battlemap and combat foundation.

create or replace function public.battle_record_to_json(p_battle public.battles)
returns jsonb
language sql
stable
as $$
  select case when p_battle.id is null then null else jsonb_build_object(
    'id', p_battle.id,
    'status', p_battle.status,
    'gridWidth', p_battle.grid_width,
    'gridHeight', p_battle.grid_height
  ) end
$$;

create or replace function public.character_battle_attribute(p_character_id uuid, p_attribute_key text)
returns int
language sql
stable
set search_path = public
as $$
  select greatest(0, coalesce((
    select public.bestiary_stat_number(c.attributes, array[p_attribute_key])
      + coalesce((
        select sum(public.bestiary_stat_number(i.modifiers, array[p_attribute_key]))
        from public.inventory_items i
        where i.character_id = c.id and i.loadout_slot is not null
      ), 0)
    from public.characters c
    where c.id = p_character_id
  ), 0))
$$;

create or replace function public.character_battle_resource_max(p_character_id uuid, p_resource text)
returns int
language sql
stable
set search_path = public
as $$
  select greatest(0, coalesce((
    select case when p_resource = 'mana' then c.max_mana else c.max_hp end
      + coalesce((
        select sum(public.bestiary_stat_number(
          i.modifiers,
          case when p_resource = 'mana'
            then array['mana', 'maxMana', 'max_mana']
            else array['health', 'hp', 'maxHp', 'max_hp']
          end
        ))
        from public.inventory_items i
        where i.character_id = c.id and i.loadout_slot is not null
      ), 0)
    from public.characters c
    where c.id = p_character_id
  ), 0))
$$;

create or replace function public.combatant_statuses_to_json(p_combatant public.combatants)
returns jsonb
language plpgsql
stable
set search_path = public
as $$
declare
  v_statuses jsonb := '[]'::jsonb;
  v_recovery int := public.character_battle_attribute(p_combatant.character_id, 'recovery');
  v_mana_regen int := public.character_battle_attribute(p_combatant.character_id, 'mana_regen');
begin
  if v_recovery > 0 then
    v_statuses := v_statuses || jsonb_build_array(jsonb_build_object(
      'id', 'permanent-health-regeneration', 'key', 'health-regeneration', 'name', 'Health Regeneration',
      'kind', 'permanent', 'duration', null, 'amount', v_recovery
    ));
  end if;
  if v_mana_regen > 0 then
    v_statuses := v_statuses || jsonb_build_array(jsonb_build_object(
      'id', 'permanent-mana-regeneration', 'key', 'mana-regeneration', 'name', 'Mana Regeneration',
      'kind', 'permanent', 'duration', null, 'amount', v_mana_regen
    ));
  end if;
  return v_statuses || coalesce(p_combatant.statuses, '[]'::jsonb);
end;
$$;

create or replace function public.combatant_record_to_json(p_combatant public.combatants)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'id', p_combatant.id,
    'battleId', p_combatant.battle_id,
    'characterId', p_combatant.character_id,
    'x', p_combatant.x,
    'y', p_combatant.y,
    'currentHp', p_combatant.current_hp,
    'currentMana', p_combatant.current_mana,
    'initiative', p_combatant.initiative,
    'statuses', public.combatant_statuses_to_json(p_combatant)
  )
$$;

create or replace function public.battle_terrain_record_to_json(p_terrain public.battle_terrain)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'id', p_terrain.id,
    'battleId', p_terrain.battle_id,
    'x', p_terrain.x,
    'y', p_terrain.y,
    'type', p_terrain.terrain_type
  )
$$;

create or replace function public.get_battle_room(p_session_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_battle public.battles%rowtype;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then
    raise exception 'Invalid or expired session.';
  end if;

  select * into v_battle
  from public.battles
  where status = 'active'::public.battle_status
  order by created_at desc
  limit 1;

  return jsonb_build_object(
    'battle', public.battle_record_to_json(v_battle),
    'combatants', (
      select coalesce(jsonb_agg(public.combatant_record_to_json(c) order by c.initiative desc nulls last, c.created_at, c.id), '[]'::jsonb)
      from public.combatants c
      where v_battle.id is not null
        and c.battle_id = v_battle.id
    ),
    'terrain', (
      select coalesce(jsonb_agg(public.battle_terrain_record_to_json(t) order by t.y, t.x), '[]'::jsonb)
      from public.battle_terrain t
      where v_battle.id is not null
        and t.battle_id = v_battle.id
    ),
    'characters', (
      select coalesce(jsonb_agg(public.character_record_to_json(ch) order by ch.kind, ch.name), '[]'::jsonb)
      from public.characters ch
      where ch.kind = 'player'
        or exists (
          select 1
          from public.combatants c
          where v_battle.id is not null
            and c.battle_id = v_battle.id
            and c.character_id = ch.id
        )
    ),
    'classes', (
      select coalesce(jsonb_agg(public.class_template_record_to_json(t) order by t.name), '[]'::jsonb)
      from public.class_templates t
    ),
    'inventoryItems', (
      select coalesce(jsonb_agg(public.inventory_item_record_to_json(i) order by i.character_id, i.loadout_slot, i.item_name), '[]'::jsonb)
      from public.inventory_items i
      where (
          i.loadout_slot is not null
          or (i.item_type = 'weapon' and i.enchantment is not null)
        )
        and exists (
          select 1
          from public.combatants c
          where v_battle.id is not null
            and c.battle_id = v_battle.id
            and c.character_id = i.character_id
        )
    ),
    'bestiary', (
      select coalesce(jsonb_agg(public.bestiary_entity_record_to_json(e) order by e.category, e.display_order, e.name), '[]'::jsonb)
      from public.bestiary_entities e
      where e.is_unlocked or v_profile.role = 'dm'::public.user_role
    )
  );
end;
$$;

create or replace function public.start_campaign_battle(
  p_session_token text,
  p_character_ids uuid[],
  p_grid_width int default 24,
  p_grid_height int default 24
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_battle public.battles%rowtype;
  v_character public.characters%rowtype;
  v_grid_width int := greatest(5, least(100, coalesce(p_grid_width, 24)));
  v_grid_height int := greatest(5, least(100, coalesce(p_grid_height, 24)));
  v_index int := 0;
  v_x int;
  v_y int;
  v_inserted int := 0;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then
    raise exception 'Invalid or expired session.';
  end if;

  if v_profile.role <> 'dm'::public.user_role then
    raise exception 'Only the Dungeon Master can start combat.';
  end if;

  if exists (select 1 from public.battles where status = 'active'::public.battle_status) then
    raise exception 'An encounter is already active.';
  end if;

  if coalesce(array_length(p_character_ids, 1), 0) = 0 then
    raise exception 'Choose at least one combatant.';
  end if;

  insert into public.battles (created_by, status, grid_width, grid_height)
  values (v_profile.id, 'active'::public.battle_status, v_grid_width, v_grid_height)
  returning * into v_battle;

  for v_character in
    select c.*
    from public.characters c
    where c.id = any(p_character_ids)
    order by array_position(p_character_ids, c.id), c.name
  loop
    v_x := greatest(0, least(v_grid_width - 1, (v_grid_width / 2)::int + (v_index % 5) - 2));
    v_y := greatest(0, least(v_grid_height - 1, (v_grid_height / 2)::int + floor(v_index / 5.0)::int));

    insert into public.combatants (
      battle_id,
      character_id,
      x,
      y,
      current_hp,
      current_mana,
      initiative
    )
    values (
      v_battle.id,
      v_character.id,
      v_x,
      v_y,
      v_character.current_hp,
      v_character.current_mana,
      null
    );

    v_index := v_index + 1;
    v_inserted := v_inserted + 1;
  end loop;

  if v_inserted = 0 then
    delete from public.battles where id = v_battle.id;
    raise exception 'No valid combatants were found.';
  end if;

  return public.get_battle_room(p_session_token);
end;
$$;

create or replace function public.update_combatant_state(
  p_session_token text,
  p_combatant_id uuid,
  p_patch jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_combatant public.combatants%rowtype;
  v_battle public.battles%rowtype;
  v_patch jsonb := coalesce(p_patch, '{}'::jsonb);
  v_x int;
  v_y int;
  v_initiative int;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then
    raise exception 'Invalid or expired session.';
  end if;

  if v_profile.role <> 'dm'::public.user_role then
    raise exception 'Only the Dungeon Master can change combatants.';
  end if;

  select * into v_combatant from public.combatants where id = p_combatant_id;
  if v_combatant.id is null then
    raise exception 'Combatant not found.';
  end if;

  select * into v_battle from public.battles where id = v_combatant.battle_id and status = 'active'::public.battle_status;
  if v_battle.id is null then
    raise exception 'That encounter is not active.';
  end if;

  v_x := case when v_patch ? 'x' then (v_patch->>'x')::int else v_combatant.x end;
  v_y := case when v_patch ? 'y' then (v_patch->>'y')::int else v_combatant.y end;

  if v_x < 0 or v_x >= v_battle.grid_width or v_y < 0 or v_y >= v_battle.grid_height then
    raise exception 'Token position is outside the battlemap.';
  end if;

  if exists (
    select 1
    from public.battle_terrain t
    where t.battle_id = v_battle.id
      and t.x = v_x
      and t.y = v_y
      and t.terrain_type = 'blocked'
  ) then
    raise exception 'That cell is blocked.';
  end if;

  if exists (
    select 1
    from public.combatants c
    where c.battle_id = v_battle.id
      and c.id <> p_combatant_id
      and c.x = v_x
      and c.y = v_y
  ) then
    raise exception 'That cell is already occupied.';
  end if;

  v_initiative := case
    when v_patch ? 'initiative' and nullif(v_patch->>'initiative', '') is not null then greatest(1, least(20, (v_patch->>'initiative')::int))
    when v_patch ? 'initiative' then null
    else v_combatant.initiative
  end;

  update public.combatants
  set
    x = v_x,
    y = v_y,
    current_hp = case
      when v_patch ? 'currentHp'
        and (v_patch->>'currentHp')::int > current_hp
        and exists (
          select 1 from jsonb_array_elements(statuses) effect
          where effect->>'key' in ('burning', 'bleeding') and coalesce((effect->>'duration')::int, 0) > 0
        )
        then current_hp
      when v_patch ? 'currentHp' then greatest(0, (v_patch->>'currentHp')::int)
      else current_hp
    end,
    current_mana = case when v_patch ? 'currentMana' then greatest(0, (v_patch->>'currentMana')::int) else current_mana end,
    initiative = v_initiative
  where id = p_combatant_id
  returning * into v_combatant;

  if v_patch ? 'currentHp' then
    update public.combatants
    set current_hp = v_combatant.current_hp
    where battle_id = v_combatant.battle_id
      and character_id = v_combatant.character_id
      and id <> v_combatant.id;
  end if;

  return public.combatant_record_to_json(v_combatant);
end;
$$;

create or replace function public.update_combatant_statuses(
  p_session_token text,
  p_combatant_id uuid,
  p_action text,
  p_status_key text default null,
  p_status_id text default null,
  p_duration int default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_combatant public.combatants%rowtype;
  v_battle public.battles%rowtype;
  v_action text := lower(trim(coalesce(p_action, '')));
  v_status_key text := lower(trim(coalesce(p_status_key, '')));
  v_statuses jsonb;
  v_damage int := 0;
  v_status_name text;
  v_status_kind text;
  v_recovery int := 0;
  v_mana_regen int := 0;
  v_max_hp int := 0;
  v_max_mana int := 0;
  v_health_gain int := 0;
  v_mana_gain int := 0;
  v_healing_blocked boolean := false;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;
  if v_profile.role <> 'dm'::public.user_role then raise exception 'Only the Dungeon Master can change battle effects.'; end if;

  select * into v_combatant from public.combatants where id = p_combatant_id for update;
  if v_combatant.id is null then raise exception 'Combatant not found.'; end if;
  select * into v_battle from public.battles where id = v_combatant.battle_id and status = 'active'::public.battle_status;
  if v_battle.id is null then raise exception 'That encounter is not active.'; end if;
  v_statuses := coalesce(v_combatant.statuses, '[]'::jsonb);

  if v_action = 'add' then
    v_status_name := case v_status_key
      when 'better-dice' then 'Better Dice'
      when 'bleeding' then 'Bleeding'
      when 'burning' then 'Burning'
      when 'counterattack' then 'Counterattack'
      when 'invisible' then 'Invisible'
      when 'ironskin' then 'Ironskin'
      when 'poison' then 'Poison'
      when 'slowness' then 'Slowness'
      when 'stoke-the-flames' then 'Stoke the Flames'
      when 'strength' then 'Strength'
      when 'stunned' then 'Stunned'
      when 'swiftness' then 'Swiftness'
      when 'weakness' then 'Weakness'
      else null
    end;
    if v_status_name is null then raise exception 'That battle effect is not supported.'; end if;
    v_status_kind := case when v_status_key in ('better-dice', 'counterattack', 'invisible', 'ironskin', 'stoke-the-flames', 'strength', 'swiftness') then 'buff' else 'debuff' end;

    if v_status_key = 'poison' then
      v_statuses := v_statuses || jsonb_build_array(jsonb_build_object(
        'id', gen_random_uuid()::text, 'key', v_status_key, 'name', v_status_name, 'kind', v_status_kind, 'duration', 1
      ));
    elsif exists (select 1 from jsonb_array_elements(v_statuses) effect where effect->>'key' = v_status_key) then
      select coalesce(jsonb_agg(
        case when effect->>'key' = v_status_key
          then jsonb_set(effect, '{duration}', to_jsonb(least(99, coalesce((effect->>'duration')::int, 0) + 1)))
          else effect end
        order by ordinality
      ), '[]'::jsonb)
      into v_statuses
      from jsonb_array_elements(v_statuses) with ordinality as entries(effect, ordinality);
    else
      v_statuses := v_statuses || jsonb_build_array(jsonb_build_object(
        'id', gen_random_uuid()::text, 'key', v_status_key, 'name', v_status_name, 'kind', v_status_kind, 'duration', 1
      ));
    end if;
  elsif v_action = 'set-duration' then
    if nullif(trim(coalesce(p_status_id, '')), '') is null then raise exception 'Choose an effect to edit.'; end if;
    select coalesce(jsonb_agg(
      case when effect->>'id' = p_status_id
        then jsonb_set(effect, '{duration}', to_jsonb(greatest(1, least(99, coalesce(p_duration, 1)))))
        else effect end
      order by ordinality
    ), '[]'::jsonb)
    into v_statuses
    from jsonb_array_elements(v_statuses) with ordinality as entries(effect, ordinality);
  elsif v_action = 'extend-poison' then
    select coalesce(jsonb_agg(
      case when effect->>'key' = 'poison'
        then jsonb_set(effect, '{duration}', to_jsonb(least(99, coalesce((effect->>'duration')::int, 0) + 1)))
        else effect end
      order by ordinality
    ), '[]'::jsonb)
    into v_statuses
    from jsonb_array_elements(v_statuses) with ordinality as entries(effect, ordinality);
  elsif v_action = 'start-turn' then
    v_recovery := public.character_battle_attribute(v_combatant.character_id, 'recovery');
    v_mana_regen := public.character_battle_attribute(v_combatant.character_id, 'mana_regen');
    v_max_hp := public.character_battle_resource_max(v_combatant.character_id, 'health');
    v_max_mana := public.character_battle_resource_max(v_combatant.character_id, 'mana');
    v_healing_blocked := exists (
      select 1 from jsonb_array_elements(v_statuses) effect
      where effect->>'key' in ('burning', 'bleeding')
        and coalesce((effect->>'duration')::int, 0) > 0
    );
    v_health_gain := case
      when v_healing_blocked then 0
      else greatest(0, least(greatest(v_combatant.current_hp, v_max_hp), v_combatant.current_hp + v_recovery * 5) - v_combatant.current_hp)
    end;
    v_mana_gain := greatest(0, least(greatest(v_combatant.current_mana, v_max_mana), v_combatant.current_mana + v_mana_regen * 5) - v_combatant.current_mana);

    select
      count(*) filter (where effect->>'key' = 'poison')::int * 5
      + case when count(*) filter (where effect->>'key' = 'burning') > 0 then 10 else 0 end
    into v_damage
    from jsonb_array_elements(v_statuses) effect
    where coalesce((effect->>'duration')::int, 0) > 0;

    select coalesce(jsonb_agg(
      case
        when effect->>'key' = 'stoke-the-flames' then effect
        else jsonb_set(effect, '{duration}', to_jsonb((effect->>'duration')::int - 1))
      end
      order by case when effect->>'key' = 'burning' then 0 else 1 end, ordinality
    ) filter (where effect->>'key' = 'stoke-the-flames' or (effect->>'duration')::int > 1), '[]'::jsonb)
    into v_statuses
    from jsonb_array_elements(v_statuses) with ordinality as entries(effect, ordinality);
  elsif v_action = 'cleanse' then
    select coalesce(jsonb_agg(effect order by ordinality), '[]'::jsonb)
    into v_statuses
    from jsonb_array_elements(v_statuses) with ordinality as entries(effect, ordinality)
    where coalesce(effect->>'kind', 'debuff') <> 'debuff';
  else
    raise exception 'Unknown battle effect action.';
  end if;

  update public.combatants
  set statuses = v_statuses,
      current_hp = case when v_action = 'start-turn'
        then greatest(0, current_hp + v_health_gain - v_damage)
        else current_hp end,
      current_mana = case when v_action = 'start-turn'
        then current_mana + v_mana_gain
        else current_mana end
  where id = p_combatant_id
  returning * into v_combatant;

  update public.combatants
  set statuses = v_combatant.statuses,
      current_hp = v_combatant.current_hp,
      current_mana = v_combatant.current_mana
  where battle_id = v_combatant.battle_id
    and character_id = v_combatant.character_id
    and id <> v_combatant.id;

  if v_action = 'start-turn' then
    update public.characters set current_hp = v_combatant.current_hp, current_mana = v_combatant.current_mana where id = v_combatant.character_id;
  end if;

  return jsonb_build_object(
    'combatant', public.combatant_record_to_json(v_combatant),
    'damage', case when v_action = 'start-turn' then v_damage else 0 end,
    'healthRestored', case when v_action = 'start-turn' then v_health_gain else 0 end,
    'manaRestored', case when v_action = 'start-turn' then v_mana_gain else 0 end
  );
end;
$$;

create or replace function public.split_combatant_token(
  p_session_token text,
  p_combatant_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_source public.combatants%rowtype;
  v_battle public.battles%rowtype;
  v_character public.characters%rowtype;
  v_x int;
  v_y int;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;
  if v_profile.role <> 'dm'::public.user_role then raise exception 'Only the Dungeon Master can split the Malignant Neoplasm.'; end if;

  select * into v_source from public.combatants where id = p_combatant_id;
  if v_source.id is null then raise exception 'Combatant not found.'; end if;
  select * into v_battle from public.battles where id = v_source.battle_id and status = 'active'::public.battle_status;
  if v_battle.id is null then raise exception 'That encounter is not active.'; end if;
  select * into v_character from public.characters where id = v_source.character_id;
  if lower(trim(coalesce(v_character.name, ''))) <> 'the malignant neoplasm' then
    raise exception 'Only The Malignant Neoplasm can use Split.';
  end if;

  select candidate.x, candidate.y into v_x, v_y
  from (
    select grid_x as x, grid_y as y
    from generate_series(0, v_battle.grid_width - 1) grid_x
    cross join generate_series(0, v_battle.grid_height - 1) grid_y
  ) candidate
  where not exists (
      select 1 from public.combatants combatant
      where combatant.battle_id = v_battle.id and combatant.x = candidate.x and combatant.y = candidate.y
    )
    and not exists (
      select 1 from public.battle_terrain terrain
      where terrain.battle_id = v_battle.id and terrain.x = candidate.x and terrain.y = candidate.y and terrain.terrain_type = 'blocked'
    )
  order by ((candidate.x - v_source.x) * (candidate.x - v_source.x) + (candidate.y - v_source.y) * (candidate.y - v_source.y)), candidate.y, candidate.x
  limit 1;

  if v_x is null or v_y is null then raise exception 'There is no open map space for the Neoplasm to split into.'; end if;

  insert into public.combatants (battle_id, character_id, x, y, current_hp, current_mana, initiative, statuses)
  values (v_source.battle_id, v_source.character_id, v_x, v_y, v_source.current_hp, v_source.current_mana, v_source.initiative, v_source.statuses);

  return public.get_battle_room(p_session_token);
end;
$$;

create or replace function public.remove_combatant_from_battle(
  p_session_token text,
  p_combatant_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_combatant public.combatants%rowtype;
  v_battle public.battles%rowtype;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then
    raise exception 'Invalid or expired session.';
  end if;

  if v_profile.role <> 'dm'::public.user_role then
    raise exception 'Only the Dungeon Master can remove combatants.';
  end if;

  select * into v_combatant from public.combatants where id = p_combatant_id;
  if v_combatant.id is null then
    raise exception 'Combatant not found.';
  end if;

  select * into v_battle from public.battles where id = v_combatant.battle_id and status = 'active'::public.battle_status;
  if v_battle.id is null then
    raise exception 'That encounter is not active.';
  end if;

  update public.characters
  set current_hp = v_combatant.current_hp,
      current_mana = v_combatant.current_mana
  where id = v_combatant.character_id;

  delete from public.combatants where id = p_combatant_id;
  return public.get_battle_room(p_session_token);
end;
$$;

create or replace function public.set_battle_terrain(
  p_session_token text,
  p_cells jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_battle public.battles%rowtype;
  v_cell jsonb;
  v_x int;
  v_y int;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;
  if v_profile.role <> 'dm'::public.user_role then raise exception 'Only the Dungeon Master can change terrain.'; end if;

  select * into v_battle from public.battles where status = 'active'::public.battle_status order by created_at desc limit 1;
  if v_battle.id is null then raise exception 'No active encounter.'; end if;

  for v_cell in select value from jsonb_array_elements(coalesce(p_cells, '[]'::jsonb)) loop
    v_x := (v_cell->>'x')::int;
    v_y := (v_cell->>'y')::int;
    if v_x >= 0 and v_x < v_battle.grid_width and v_y >= 0 and v_y < v_battle.grid_height
      and not exists (select 1 from public.combatants c where c.battle_id = v_battle.id and c.x = v_x and c.y = v_y)
    then
      insert into public.battle_terrain (battle_id, x, y, terrain_type)
      values (v_battle.id, v_x, v_y, 'blocked')
      on conflict (battle_id, x, y) do update set terrain_type = 'blocked';
    end if;
  end loop;

  return public.get_battle_room(p_session_token);
end;
$$;

create or replace function public.clear_battle_terrain(
  p_session_token text,
  p_cells jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_battle public.battles%rowtype;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;
  if v_profile.role <> 'dm'::public.user_role then raise exception 'Only the Dungeon Master can change terrain.'; end if;

  select * into v_battle from public.battles where status = 'active'::public.battle_status order by created_at desc limit 1;
  if v_battle.id is null then raise exception 'No active encounter.'; end if;

  if p_cells is null then
    delete from public.battle_terrain where battle_id = v_battle.id;
  else
    delete from public.battle_terrain t
    using (
      select (value->>'x')::int as x, (value->>'y')::int as y
      from jsonb_array_elements(coalesce(p_cells, '[]'::jsonb))
    ) cells
    where t.battle_id = v_battle.id
      and t.x = cells.x
      and t.y = cells.y;
  end if;

  return public.get_battle_room(p_session_token);
end;
$$;

create or replace function public.add_bestiary_to_battle(
  p_session_token text,
  p_entity_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_battle public.battles%rowtype;
  v_entity public.bestiary_entities%rowtype;
  v_character public.characters%rowtype;
  v_x int;
  v_y int;
  v_armor_hide int := 0;
  v_magic_resist int := 0;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;
  if v_profile.role <> 'dm'::public.user_role then raise exception 'Only the Dungeon Master can add bestiary combatants.'; end if;

  select * into v_battle from public.battles where status = 'active'::public.battle_status order by created_at desc limit 1;
  if v_battle.id is null then raise exception 'No active encounter.'; end if;

  select * into v_entity from public.bestiary_entities where id = p_entity_id;
  if v_entity.id is null then raise exception 'Bestiary entry not found.'; end if;

  select candidate.x, candidate.y
  into v_x, v_y
  from (
    select gx.x, gy.y
    from generate_series(0, v_battle.grid_width - 1) as gx(x)
    cross join generate_series(0, v_battle.grid_height - 1) as gy(y)
  ) candidate
  where not exists (select 1 from public.combatants c where c.battle_id = v_battle.id and c.x = candidate.x and c.y = candidate.y)
    and not exists (select 1 from public.battle_terrain t where t.battle_id = v_battle.id and t.x = candidate.x and t.y = candidate.y and t.terrain_type = 'blocked')
  order by
    ((candidate.x - ((v_battle.grid_width - 1) / 2.0)) * (candidate.x - ((v_battle.grid_width - 1) / 2.0)))
    + ((candidate.y - ((v_battle.grid_height - 1) / 2.0)) * (candidate.y - ((v_battle.grid_height - 1) / 2.0))),
    candidate.y,
    candidate.x
  limit 1;

  if v_x is null or v_y is null then raise exception 'No open battlefield cell is available.'; end if;

  v_armor_hide := public.bestiary_stat_number(v_entity.stats, array['Armor / Hide', 'Armor', 'Hide']);
  v_magic_resist := public.bestiary_stat_number(v_entity.stats, array['Magic Resistance', 'Magic Resist', 'Magic Res']);

  insert into public.characters (
    owner_user_id, name, kind, class_key, class_name, level, max_hp, current_hp, max_mana, current_mana,
    magic_resist, inventory_slots, spell_slots, attributes, class_passives, personal_passives, token_color, location_name
  )
  values (
    null,
    v_entity.name,
    'enemy'::public.character_kind,
    public.catalog_key_for_name(coalesce(nullif(v_entity.category, ''), 'Bestiary')),
    coalesce(nullif(v_entity.category, ''), 'Bestiary'),
    1,
    greatest(1, v_entity.hp),
    greatest(1, v_entity.hp),
    greatest(0, v_entity.mana),
    greatest(0, v_entity.mana),
    greatest(0, v_magic_resist),
    0,
    0,
    jsonb_build_object(
      'strength', public.bestiary_stat_number(v_entity.stats, array['Strength']),
      'accuracy', public.bestiary_stat_number(v_entity.stats, array['Accuracy']),
      'intelligence', public.bestiary_stat_number(v_entity.stats, array['Intelligence']),
      'vitality', v_armor_hide + public.bestiary_stat_number(v_entity.stats, array['Vitality']),
      'recovery', public.bestiary_stat_number(v_entity.stats, array['Recovery']),
      'mana_regen', public.bestiary_stat_number(v_entity.stats, array['Mana Regen']),
      'charisma', public.bestiary_stat_number(v_entity.stats, array['Charisma']),
      'wisdom_cunning', public.bestiary_stat_number(v_entity.stats, array['Wisdom / Cunning', 'Wisdom/Cunning']),
      'perception', public.bestiary_stat_number(v_entity.stats, array['Perception']),
      'alchemy', public.bestiary_stat_number(v_entity.stats, array['Alchemy']),
      'stealth', public.bestiary_stat_number(v_entity.stats, array['Stealth']),
      'agility', public.bestiary_stat_number(v_entity.stats, array['Agility'])
    ),
    jsonb_build_array(coalesce(nullif(v_entity.summary, ''), v_entity.temperament)),
    v_entity.details,
    public.bestiary_token_color(v_entity),
    'Battlefield'
  )
  returning * into v_character;

  insert into public.combatants (battle_id, character_id, x, y, current_hp, current_mana, initiative)
  values (v_battle.id, v_character.id, v_x, v_y, v_character.current_hp, v_character.current_mana, null);

  return public.get_battle_room(p_session_token);
end;
$$;

create or replace function public.end_active_battle(p_session_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_battle public.battles%rowtype;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then
    raise exception 'Invalid or expired session.';
  end if;

  if v_profile.role <> 'dm'::public.user_role then
    raise exception 'Only the Dungeon Master can end combat.';
  end if;

  select * into v_battle
  from public.battles
  where status = 'active'::public.battle_status
  order by created_at desc
  limit 1;

  if v_battle.id is null then
    return public.get_battle_room(p_session_token);
  end if;

  update public.characters c
  set current_hp = cb.current_hp,
      current_mana = cb.current_mana
  from public.combatants cb
  where cb.battle_id = v_battle.id
    and cb.character_id = c.id;

  update public.battles
  set status = 'ended'::public.battle_status,
      ended_at = now()
  where id = v_battle.id;

  return public.get_battle_room(p_session_token);
end;
$$;

grant execute on function public.battle_record_to_json(public.battles) to anon, authenticated;
grant execute on function public.character_battle_attribute(uuid, text) to anon, authenticated;
grant execute on function public.character_battle_resource_max(uuid, text) to anon, authenticated;
grant execute on function public.combatant_statuses_to_json(public.combatants) to anon, authenticated;
grant execute on function public.combatant_record_to_json(public.combatants) to anon, authenticated;
grant execute on function public.battle_terrain_record_to_json(public.battle_terrain) to anon, authenticated;
grant execute on function public.get_battle_room(text) to anon, authenticated;
grant execute on function public.start_campaign_battle(text, uuid[], int, int) to anon, authenticated;
grant execute on function public.update_combatant_state(text, uuid, jsonb) to anon, authenticated;
grant execute on function public.update_combatant_statuses(text, uuid, text, text, text, int) to anon, authenticated;
grant execute on function public.split_combatant_token(text, uuid) to anon, authenticated;
grant execute on function public.remove_combatant_from_battle(text, uuid) to anon, authenticated;
grant execute on function public.end_active_battle(text) to anon, authenticated;
grant execute on function public.set_battle_terrain(text, jsonb) to anon, authenticated;
grant execute on function public.clear_battle_terrain(text, jsonb) to anon, authenticated;
grant execute on function public.add_bestiary_to_battle(text, uuid) to anon, authenticated;


-- ============================================================
-- ============================================================

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

alter table public.cities
  add column if not exists description text not null default '',
  add column if not exists primary_color text not null default '#d1a85b',
  add column if not exists secondary_color text not null default '#1f7875',
  add column if not exists accent_color text not null default '#f5b44c',
  add column if not exists is_player_visible boolean not null default true,
  add column if not exists is_current_residence boolean not null default false,
  add column if not exists show_under_construction boolean not null default false;

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
  item_display_name text,
  description text not null default '',
  item_type text not null default 'misc',
  rarity public.item_rarity not null default 'Common',
  price_coin int not null default 0 check (price_coin >= 0),
  currency_system_key text not null default 'calostrynn' check (currency_system_key in ('calostrynn', 'common')),
  stock_quantity numeric(12,1) check (stock_quantity is null or stock_quantity >= 0),
  catalog_item_key text,
  shop_section text not null default 'Wares',
  quantity_step numeric(12,1) not null default 1 check (quantity_step in (0.5, 1)),
  product_kind text not null default 'item',
  document_author text not null default '',
  document_content text not null default '',
  mana_cost int not null default 0 check (mana_cost >= 0),
  mana_label text not null default '',
  item_is_accessory boolean not null default false,
  item_is_storage boolean not null default false,
  item_storage_capacity int not null default 0,
  item_modifiers jsonb not null default '{}'::jsonb,
  item_enchantment text,
  item_rune_name text,
  item_material text,
  item_enhancement_count int not null default 0,
  item_is_two_handed boolean not null default false,
  item_potion_strength text,
  item_potion_property text,
  item_potion_quality text,
  item_spell_book_form int not null default 1,
  boarded_owner_user_id uuid references public.profiles(id) on delete set null,
  boarded_source_character_id uuid references public.characters(id) on delete set null,
  boarded_at timestamptz,
  is_available boolean not null default true,
  display_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists shop_vendors_city_idx on public.shop_vendors(city_key);
create index if not exists market_products_vendor_idx on public.market_products(vendor_id);

alter table public.market_products
  drop constraint if exists market_products_item_type_valid,
  drop constraint if exists market_product_item_type_valid;

alter table public.market_products
  alter column item_type type text using item_type::text,
  alter column stock_quantity type numeric(12,1) using stock_quantity::numeric;

alter table public.market_products
  add column if not exists catalog_item_key text,
  add column if not exists item_display_name text,
  add column if not exists shop_section text not null default 'Wares',
  add column if not exists currency_system_key text not null default 'calostrynn',
  add column if not exists quantity_step numeric(12,1) not null default 1 check (quantity_step in (0.5, 1)),
  add column if not exists product_kind text not null default 'item',
  add column if not exists document_author text not null default '',
  add column if not exists document_content text not null default '',
  add column if not exists document_pages jsonb not null default '[]'::jsonb,
  add column if not exists document_visibility text not null default 'for_sale',
  add column if not exists document_editor_user_id uuid references public.profiles(id) on delete set null,
  add column if not exists mana_cost int not null default 0 check (mana_cost >= 0),
  add column if not exists mana_label text not null default '',
  add column if not exists item_is_accessory boolean not null default false,
  add column if not exists item_is_storage boolean not null default false,
  add column if not exists item_storage_capacity int not null default 0,
  add column if not exists item_modifiers jsonb not null default '{}'::jsonb,
  add column if not exists item_enchantment text,
  add column if not exists item_rune_name text,
  add column if not exists item_material text,
  add column if not exists item_enhancement_count int not null default 0,
  add column if not exists item_is_two_handed boolean not null default false,
  add column if not exists item_potion_strength text,
  add column if not exists item_potion_property text,
  add column if not exists item_potion_quality text,
  add column if not exists item_spell_book_form int not null default 1,
  add column if not exists boarded_owner_user_id uuid references public.profiles(id) on delete set null,
  add column if not exists boarded_source_character_id uuid references public.characters(id) on delete set null,
  add column if not exists boarded_at timestamptz;

alter table public.market_products
  drop constraint if exists market_products_currency_system_key_check,
  add constraint market_products_currency_system_key_check check (currency_system_key in ('calostrynn', 'common'));

alter table public.market_products
  drop constraint if exists market_products_document_visibility_check,
  add constraint market_products_document_visibility_check check (document_visibility in ('government', 'for_sale'));

alter table public.market_products
  drop constraint if exists market_products_item_storage_capacity_check,
  add constraint market_products_item_storage_capacity_check check (item_storage_capacity >= 0 and item_storage_capacity <= 500),
  drop constraint if exists market_products_item_modifiers_object_check,
  add constraint market_products_item_modifiers_object_check check (jsonb_typeof(item_modifiers) = 'object'),
  drop constraint if exists market_products_item_enhancement_count_check,
  add constraint market_products_item_enhancement_count_check check (item_enhancement_count between 0 and 3),
  drop constraint if exists market_products_item_spell_book_form_check,
  add constraint market_products_item_spell_book_form_check check (item_spell_book_form in (1, 2));

update public.market_products
set item_type = 'book'
where product_kind = 'document'
   or (
    item_type = 'quest'
    and public.catalog_key_for_name(item_name) in (
      'history-book',
      'alchemy-book',
      'bestiary',
      'magical-research',
      'ember-magic-spell-book',
      'frost-magic-spell-book',
      'lightning-magic-spell-book',
      'earth-magic-spell-book',
      'wind-magic-spell-book',
      'energy-magic-spell-book',
      'defensive-support-magic-spell-book',
      'offensive-support-magic-spell-book',
      'enhancement-magic-spell-book',
      'utility-magic-spell-book'
    )
  );

update public.inventory_items
set item_type = 'book'
where item_type = 'quest'
  and exists (
    select 1
    from public.market_products p
    where p.product_kind = 'document'
      and public.catalog_key_for_name(p.item_name) = public.catalog_key_for_name(inventory_items.item_name)
  );

update public.house_inventory_items
set item_type = 'book'
where item_type = 'quest'
  and exists (
    select 1
    from public.market_products p
    where p.product_kind = 'document'
      and public.catalog_key_for_name(p.item_name) = public.catalog_key_for_name(house_inventory_items.item_name)
  );

create table if not exists public.shop_sections (
  id uuid primary key default gen_random_uuid(),
  vendor_id uuid not null references public.shop_vendors(id) on delete cascade,
  section_key text not null,
  section_name text not null,
  npc_name text not null default '',
  role_label text not null default '',
  section_type text not null default 'standard',
  slot_count int not null default 0 check (slot_count >= 0 and slot_count <= 200),
  is_hidden boolean not null default false,
  display_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint shop_sections_name_not_blank check (length(trim(section_name)) > 0),
  constraint shop_sections_vendor_key_unique unique (vendor_id, section_key)
);

create index if not exists shop_sections_vendor_idx on public.shop_sections(vendor_id);

alter table public.shop_sections
  add column if not exists slot_count int not null default 0,
  add column if not exists section_type text not null default 'standard';

alter table public.shop_sections
  drop constraint if exists shop_sections_slot_count_check,
  add constraint shop_sections_slot_count_check check (slot_count >= 0 and slot_count <= 200);

alter table public.shop_sections
  drop constraint if exists shop_sections_section_type_check,
  add constraint shop_sections_section_type_check check (section_type in ('standard', 'sale', 'rent', 'holding'));

create table if not exists public.app_data_repairs (
  repair_key text primary key,
  applied_at timestamptz not null default now()
);

alter table public.app_data_repairs enable row level security;
revoke all on public.app_data_repairs from anon, authenticated;

create or replace function public.safe_slug(p_value text)
returns text
language sql
immutable
as $$
  select coalesce(nullif(regexp_replace(lower(trim(coalesce(p_value, ''))), '[^a-z0-9]+', '-', 'g'), ''), 'entry')
$$;

insert into public.app_data_repairs (repair_key)
select 'calostrynn-shop-defaults-preexisting-2026-08-24'
where exists (select 1 from public.shop_vendors where city_key = 'calostrynn')
on conflict (repair_key) do nothing;

delete from public.market_products
where product_key = 'blacksmith-mountian-rune'
  and not exists (select 1 from public.app_data_repairs where repair_key = 'calostrynn-shop-defaults-preexisting-2026-08-24')
  and exists (
    select 1
    from public.market_products existing
    where existing.product_key = 'blacksmith-mountain-rune'
  );

update public.market_products
set item_type = public.normalize_item_type(item_type),
    item_name = case when item_name = 'Mountian Rune' then 'Mountain Rune' else public.normalize_item_name(item_name) end,
    product_key = case when product_key = 'blacksmith-mountian-rune' then 'blacksmith-mountain-rune' else product_key end,
    catalog_item_key = case when catalog_item_key = 'mountian-rune' then 'mountain-rune' else catalog_item_key end
where not exists (select 1 from public.app_data_repairs where repair_key = 'calostrynn-shop-defaults-preexisting-2026-08-24');

update public.market_products
set item_type = 'potion',
    rarity = case when lower(item_name) = 'arcane nector' then 'Uncommon'::public.item_rarity else 'Common'::public.item_rarity end,
    quantity_step = 1
where lower(item_name) in ('empty flask', 'arcane nector')
  and not exists (select 1 from public.app_data_repairs where repair_key = 'calostrynn-shop-defaults-preexisting-2026-08-24');

alter table public.cities enable row level security;
alter table public.shop_vendors enable row level security;
alter table public.shop_sections enable row level security;
alter table public.market_products enable row level security;

revoke all on public.cities from anon, authenticated;
revoke all on public.shop_vendors from anon, authenticated;
revoke all on public.shop_sections from anon, authenticated;
revoke all on public.market_products from anon, authenticated;

drop trigger if exists cities_touch_updated_at on public.cities;
create trigger cities_touch_updated_at
before update on public.cities
for each row execute function public.touch_updated_at();

drop trigger if exists shop_vendors_touch_updated_at on public.shop_vendors;
create trigger shop_vendors_touch_updated_at
before update on public.shop_vendors
for each row execute function public.touch_updated_at();

drop trigger if exists shop_sections_touch_updated_at on public.shop_sections;
create trigger shop_sections_touch_updated_at
before update on public.shop_sections
for each row execute function public.touch_updated_at();

drop trigger if exists market_products_touch_updated_at on public.market_products;
create trigger market_products_touch_updated_at
before update on public.market_products
for each row execute function public.touch_updated_at();

insert into public.cities (city_key, name, is_locked, display_order)
values ('calostrynn', 'Calostrynn', false, 10)
on conflict (city_key) do nothing;

insert into public.shop_vendors (city_key, vendor_key, name, facility, category, display_order)
select seed.city_key, seed.vendor_key, seed.name, seed.facility, seed.category, seed.display_order
from (values
  ('calostrynn', 'calostrynn-armory', 'Armory Quartermaster', 'Armory', 'Arms & Armor', 20),
  ('calostrynn', 'calostrynn-brewery', 'Brewery Keeper', 'Brewery', 'Potions & Ingredients', 30),
  ('calostrynn', 'calostrynn-spells', 'Spell Registrar', 'Spell Shop', 'Spell Catalog', 40),
  ('calostrynn', 'calostrynn-library', 'The Grand Calostrynn Library', 'Library', 'Books & Research', 45),
  ('calostrynn', 'calostrynn-blacksmith', 'Blacksmith', 'Blacksmith', 'Tools & Metalwork', 50),
  ('calostrynn', 'calostrynn-city-market', 'City Market', 'Market', 'General Goods', 60)
) as seed(city_key, vendor_key, name, facility, category, display_order)
where not exists (select 1 from public.shop_vendors existing where existing.city_key = 'calostrynn')
  and not exists (select 1 from public.app_data_repairs where repair_key = 'calostrynn-shop-defaults-preexisting-2026-08-24')
on conflict (vendor_key) do nothing;

-- Replace Blacksmith placeholder wares with source-backed forge materials and runes.
-- Market seed rows keep product metadata current, but existing live stock and DM visibility
-- are intentionally preserved so purchases and shop edits do not get reset by rerunning SQL.
insert into public.market_products (vendor_id, product_key, item_name, description, item_type, rarity, price_coin, stock_quantity, shop_section, quantity_step, catalog_item_key, product_kind, mana_cost, mana_label, is_available, display_order)
select v.id, seed.product_key, seed.item_name, seed.description, public.normalize_item_type(seed.item_type), seed.rarity::public.item_rarity, seed.price_coin, seed.stock_quantity::numeric, seed.shop_section, seed.quantity_step::numeric, seed.catalog_item_key, 'item', 0, '', seed.is_available, seed.display_order
from public.shop_vendors v
join (values
  ('blacksmith-bronze-scale', 'Bronze Scale', 'Bronze: -1 Strength when used for weapons; +1 Vitality when used for shields.', 'material', 'Common', 100, 50, 'Material Scales', 1, 'bronze-scale', true, 10),
  ('blacksmith-iron-scale', 'Iron Scale', 'Iron: neutral weapon material; +1 Vitality when used for shields; -1 Agility when used for armor.', 'material', 'Common', 400, 40, 'Material Scales', 1, 'iron-scale', true, 20),
  ('blacksmith-steel-scale', 'Steel Scale', 'Steel: +1 Strength when used for weapons; +1 Vitality when used for shields or armor.', 'material', 'Uncommon', 1000, 30, 'Material Scales', 1, 'steel-scale', true, 30),
  ('blacksmith-mythril-scale', 'Mythril Scale', 'Mythril: eligible for enhancement or enchantment when crafted into weapon, shield, or armor.', 'material', 'Rare', 6500, 12, 'Material Scales', 1, 'mythril-scale', true, 40),
  ('blacksmith-vaylium-scale', 'Vaylium Scale', 'Vaylium: +1 Intelligence for weapons; +1 Vitality and +1 Intelligence for shields; +3 Intelligence and +1 Magic Resist for armor.', 'material', 'Epic', 5000, 0, 'Material Scales', 1, 'vaylium-scale', false, 50),
  ('blacksmith-dragonscale-scale', 'Dragonscale Scale', 'Dragonscale: +2 Strength and +3 Magic Resist for weapons; +2 Vitality and +3 Magic Resist for shields; +2 Vitality and +5 Magic Resist for armor.', 'material', 'Legendary', 15000, 0, 'Material Scales', 1, 'dragonscale-scale', false, 60),
  ('blacksmith-ember-rune', 'Ember Rune', 'Can be used for Ember enchantments.', 'rune', 'Epic', 0, 0, 'Runes', 1, 'ember-rune', false, 70),
  ('blacksmith-frost-rune', 'Frost Rune', 'Can be used for Frost enchantments.', 'rune', 'Epic', 0, 0, 'Runes', 1, 'frost-rune', false, 80),
  ('blacksmith-lightning-rune', 'Lightning Rune', 'Can be used for Lightning enchantments.', 'rune', 'Epic', 0, 0, 'Runes', 1, 'lightning-rune', false, 90),
  ('blacksmith-earth-rune', 'Earth Rune', 'Can be used for Earth enchantments.', 'rune', 'Epic', 0, 0, 'Runes', 1, 'earth-rune', false, 100),
  ('blacksmith-wind-rune', 'Wind Rune', 'Can be used for Wind enchantments.', 'rune', 'Epic', 0, 0, 'Runes', 1, 'wind-rune', false, 110),
  ('blacksmith-mountain-rune', 'Mountain Rune', 'Cannot be used for enchantments yet.', 'rune', 'Epic', 0, 0, 'Runes', 1, 'mountain-rune', false, 120),
  ('blacksmith-void-rune', 'Void Rune', 'Cannot be used for enchantments yet.', 'rune', 'Mythical', 0, 0, 'Runes', 1, 'void-rune', false, 130)
) as seed(product_key, item_name, description, item_type, rarity, price_coin, stock_quantity, shop_section, quantity_step, catalog_item_key, is_available, display_order) on v.vendor_key = 'calostrynn-blacksmith'
where not exists (
  select 1 from public.market_products existing
  where existing.vendor_id = v.id
    and coalesce(existing.product_kind, 'item') <> 'service'
)
  and not exists (select 1 from public.app_data_repairs where repair_key = 'calostrynn-shop-defaults-preexisting-2026-08-24')
on conflict (product_key) do nothing;

-- Service rows make forge recipe sections editable in the DM shop manager.
insert into public.market_products (vendor_id, product_key, item_name, description, item_type, rarity, price_coin, currency_system_key, stock_quantity, shop_section, quantity_step, catalog_item_key, product_kind, mana_cost, mana_label, is_available, display_order)
select v.id, seed.product_key, seed.item_name, seed.description, public.normalize_item_type(seed.item_type), seed.rarity::public.item_rarity, seed.price_coin, 'calostrynn', null, seed.shop_section, 1, seed.catalog_item_key, 'service', 0, '', true, seed.display_order
from public.shop_vendors v
join (values
  ('blacksmith-service-dagger', 'Dagger', 'Forge labor price for crafting a dagger.', 'weapon', 'Common', 50, 'Light Weapons', 'dagger', 210),
  ('blacksmith-service-throwing-knives', 'Throwing Knives', 'Forge labor price for crafting throwing knives.', 'weapon', 'Common', 100, 'Light Weapons', 'throwing-knives', 220),
  ('blacksmith-service-shortbow', 'Shortbow', 'Forge labor price for crafting a shortbow.', 'weapon', 'Common', 100, 'Light Weapons', 'shortbow', 230),
  ('blacksmith-service-custom-light-weapon', 'Custom Light Weapon', 'Forge labor price for a custom light weapon.', 'weapon', 'Common', 1000, 'Light Weapons', 'custom-light-weapon', 240),
  ('blacksmith-service-sword', 'Sword', 'Forge labor price for crafting a sword.', 'weapon', 'Common', 300, 'Medium Weapons', 'sword', 310),
  ('blacksmith-service-spear', 'Spear', 'Forge labor price for crafting a spear.', 'weapon', 'Common', 500, 'Medium Weapons', 'spear', 320),
  ('blacksmith-service-longbow', 'Longbow', 'Forge labor price for crafting a longbow.', 'weapon', 'Common', 500, 'Medium Weapons', 'longbow', 330),
  ('blacksmith-service-custom-medium-weapon', 'Custom Medium Weapon', 'Forge labor price for a custom medium weapon.', 'weapon', 'Common', 2500, 'Medium Weapons', 'custom-medium-weapon', 340),
  ('blacksmith-service-battleaxe', 'Battleaxe', 'Forge labor price for crafting a battleaxe.', 'weapon', 'Common', 3000, 'Heavy Weapons', 'battleaxe', 410),
  ('blacksmith-service-mace', 'Mace', 'Forge labor price for crafting a mace.', 'weapon', 'Common', 3000, 'Heavy Weapons', 'mace', 420),
  ('blacksmith-service-claymore', 'Claymore', 'Forge labor price for crafting a claymore.', 'weapon', 'Common', 3000, 'Heavy Weapons', 'claymore', 430),
  ('blacksmith-service-crossbow', 'Crossbow', 'Forge labor price for crafting a crossbow.', 'weapon', 'Common', 4000, 'Heavy Weapons', 'crossbow', 440),
  ('blacksmith-service-custom-heavy-weapon', 'Custom Heavy Weapon', 'Forge labor price for a custom heavy weapon.', 'weapon', 'Common', 5000, 'Heavy Weapons', 'custom-heavy-weapon', 450),
  ('blacksmith-service-magic-bow', 'Magic Bow', 'Commission labor price for a magic bow.', 'weapon', 'Common', 3000, 'Magecraft Commissions', 'magic-bow', 510),
  ('blacksmith-service-magic-longbow', 'Magic Longbow', 'Commission labor price for a magic longbow.', 'weapon', 'Common', 5000, 'Magecraft Commissions', 'magic-longbow', 520),
  ('blacksmith-service-wand', 'Wand', 'Commission labor price for a wand.', 'weapon', 'Common', 100, 'Magecraft Commissions', 'wand', 530),
  ('blacksmith-service-scepter', 'Scepter', 'Commission labor price for a scepter.', 'weapon', 'Common', 1000, 'Magecraft Commissions', 'scepter', 540),
  ('blacksmith-service-staff', 'Staff', 'Commission labor price for a staff.', 'weapon', 'Common', 5000, 'Magecraft Commissions', 'staff', 550),
  ('blacksmith-service-custom-magecraft', 'Custom Magecraft Commission', 'Labor price for a flexible magecraft commission.', 'weapon', 'Common', 6500, 'Magecraft Commissions', 'custom-magecraft', 560),
  ('blacksmith-service-shield', 'Shield', 'Forge labor price for crafting a shield.', 'shield', 'Common', 5000, 'Shield Creation', 'shield', 610)
) as seed(product_key, item_name, description, item_type, rarity, price_coin, shop_section, catalog_item_key, display_order) on v.vendor_key = 'calostrynn-blacksmith'
where not exists (
  select 1 from public.market_products existing
  where existing.vendor_id = v.id
    and existing.product_kind = 'service'
)
  and not exists (select 1 from public.app_data_repairs where repair_key = 'calostrynn-shop-defaults-preexisting-2026-08-24')
on conflict (product_key) do nothing;

-- Seed Armory scales as Armory-owned wares instead of borrowing Blacksmith product rows.
insert into public.market_products (vendor_id, product_key, item_name, description, item_type, rarity, price_coin, stock_quantity, shop_section, quantity_step, catalog_item_key, product_kind, mana_cost, mana_label, is_available, display_order)
select v.id, seed.product_key, seed.item_name, seed.description, public.normalize_item_type(seed.item_type), seed.rarity::public.item_rarity, seed.price_coin, seed.stock_quantity::numeric, seed.shop_section, seed.quantity_step::numeric, seed.catalog_item_key, 'item', 0, '', seed.is_available, seed.display_order
from public.shop_vendors v
join (values
  ('armory-bronze-scale', 'Bronze Scale', 'Bronze: +1 Vitality when used for shields.', 'material', 'Common', 100, 50, 'Material Scales', 1, 'bronze-scale', true, 10),
  ('armory-iron-scale', 'Iron Scale', 'Iron: -1 Agility when used for armor.', 'material', 'Common', 400, 40, 'Material Scales', 1, 'iron-scale', true, 20),
  ('armory-steel-scale', 'Steel Scale', 'Steel: +1 Vitality when used for shields or armor.', 'material', 'Uncommon', 1000, 30, 'Material Scales', 1, 'steel-scale', true, 30),
  ('armory-mythril-scale', 'Mythril Scale', 'Mythril: eligible for enhancement or enchantment when crafted into weapon, shield, or armor.', 'material', 'Rare', 6500, 12, 'Material Scales', 1, 'mythril-scale', true, 40),
  ('armory-vaylium-scale', 'Vaylium Scale', 'Vaylium: +1 Vitality and +1 Intelligence for shields; +3 Intelligence and +1 Magic Resist for armor.', 'material', 'Epic', 5000, 0, 'Material Scales', 1, 'vaylium-scale', false, 50),
  ('armory-dragonscale-scale', 'Dragonscale Scale', 'Dragonscale: +2 Vitality and +3 Magic Resist for shields; +2 Vitality and +5 Magic Resist for armor.', 'material', 'Legendary', 15000, 0, 'Material Scales', 1, 'dragonscale-scale', false, 60)
) as seed(product_key, item_name, description, item_type, rarity, price_coin, stock_quantity, shop_section, quantity_step, catalog_item_key, is_available, display_order) on v.vendor_key = 'calostrynn-armory'
where not exists (
  select 1 from public.market_products existing
  where existing.vendor_id = v.id
    and coalesce(existing.product_kind, 'item') <> 'service'
)
  and not exists (select 1 from public.app_data_repairs where repair_key = 'calostrynn-shop-defaults-preexisting-2026-08-24')
on conflict (product_key) do nothing;

insert into public.market_products (vendor_id, product_key, item_name, description, item_type, rarity, price_coin, currency_system_key, stock_quantity, shop_section, quantity_step, catalog_item_key, product_kind, mana_cost, mana_label, is_available, display_order)
select v.id, seed.product_key, seed.item_name, seed.description, public.normalize_item_type(seed.item_type), seed.rarity::public.item_rarity, seed.price_coin, 'calostrynn', null, seed.shop_section, 1, seed.catalog_item_key, 'service', 0, '', true, seed.display_order
from public.shop_vendors v
join (values
  ('armory-service-leather-armor', 'Leather Armor', 'Armory labor price for leather armor.', 'armor', 'Common', 0, 'Armor Creation', 'leather-armor', 210),
  ('armory-service-iron-armor', 'Iron Armor', 'Armory labor price for iron armor.', 'armor', 'Common', 500, 'Armor Creation', 'iron-armor', 220),
  ('armory-service-steel-armor', 'Steel Armor', 'Armory labor price for steel armor.', 'armor', 'Uncommon', 2500, 'Armor Creation', 'steel-armor', 230),
  ('armory-service-mythril-armor', 'Mythril Armor', 'Armory labor price for mythril armor.', 'armor', 'Rare', 5000, 'Armor Creation', 'mythril-armor', 240),
  ('armory-service-vaylium-armor', 'Vaylium Armor', 'Armory labor price for vaylium armor.', 'armor', 'Epic', 7500, 'Armor Creation', 'vaylium-armor', 250),
  ('armory-service-dragonscale-armor', 'Dragonscale Armor', 'Armory labor price for dragonscale armor.', 'armor', 'Legendary', 10000, 'Armor Creation', 'dragonscale-armor', 260)
) as seed(product_key, item_name, description, item_type, rarity, price_coin, shop_section, catalog_item_key, display_order) on v.vendor_key = 'calostrynn-armory'
where not exists (
  select 1 from public.market_products existing
  where existing.vendor_id = v.id
    and existing.product_kind = 'service'
)
  and not exists (select 1 from public.app_data_repairs where repair_key = 'calostrynn-shop-defaults-preexisting-2026-08-24')
on conflict (product_key) do nothing;

-- Repair existing custom forge shops created before service rows existed.
insert into public.market_products (vendor_id, product_key, item_name, description, item_type, rarity, price_coin, currency_system_key, stock_quantity, shop_section, quantity_step, catalog_item_key, product_kind, mana_cost, mana_label, is_available, display_order)
select
  v.id,
  public.safe_slug(v.vendor_key || '-service-' || seed.catalog_item_key),
  seed.item_name,
  seed.description,
  public.normalize_item_type(seed.item_type),
  seed.rarity::public.item_rarity,
  case when v.city_key = 'calostrynn' then seed.price_coin else 0 end,
  case when v.city_key = 'calostrynn' then 'calostrynn' else 'common' end,
  null,
  seed.shop_section,
  1,
  seed.catalog_item_key,
  'service',
  0,
  '',
  true,
  seed.display_order
from public.shop_vendors v
join (values
  ('Dagger', 'Forge labor price for crafting a dagger.', 'weapon', 'Common', 50, 'Light Weapons', 'dagger', 210),
  ('Throwing Knives', 'Forge labor price for crafting throwing knives.', 'weapon', 'Common', 100, 'Light Weapons', 'throwing-knives', 220),
  ('Shortbow', 'Forge labor price for crafting a shortbow.', 'weapon', 'Common', 100, 'Light Weapons', 'shortbow', 230),
  ('Custom Light Weapon', 'Forge labor price for a custom light weapon.', 'weapon', 'Common', 1000, 'Light Weapons', 'custom-light-weapon', 240),
  ('Sword', 'Forge labor price for crafting a sword.', 'weapon', 'Common', 300, 'Medium Weapons', 'sword', 310),
  ('Spear', 'Forge labor price for crafting a spear.', 'weapon', 'Common', 500, 'Medium Weapons', 'spear', 320),
  ('Longbow', 'Forge labor price for crafting a longbow.', 'weapon', 'Common', 500, 'Medium Weapons', 'longbow', 330),
  ('Custom Medium Weapon', 'Forge labor price for a custom medium weapon.', 'weapon', 'Common', 2500, 'Medium Weapons', 'custom-medium-weapon', 340),
  ('Battleaxe', 'Forge labor price for crafting a battleaxe.', 'weapon', 'Common', 3000, 'Heavy Weapons', 'battleaxe', 410),
  ('Mace', 'Forge labor price for crafting a mace.', 'weapon', 'Common', 3000, 'Heavy Weapons', 'mace', 420),
  ('Claymore', 'Forge labor price for crafting a claymore.', 'weapon', 'Common', 3000, 'Heavy Weapons', 'claymore', 430),
  ('Crossbow', 'Forge labor price for crafting a crossbow.', 'weapon', 'Common', 4000, 'Heavy Weapons', 'crossbow', 440),
  ('Custom Heavy Weapon', 'Forge labor price for a custom heavy weapon.', 'weapon', 'Common', 5000, 'Heavy Weapons', 'custom-heavy-weapon', 450),
  ('Magic Bow', 'Commission labor price for a magic bow.', 'weapon', 'Common', 3000, 'Magecraft Commissions', 'magic-bow', 510),
  ('Magic Longbow', 'Commission labor price for a magic longbow.', 'weapon', 'Common', 5000, 'Magecraft Commissions', 'magic-longbow', 520),
  ('Wand', 'Commission labor price for a wand.', 'weapon', 'Common', 100, 'Magecraft Commissions', 'wand', 530),
  ('Scepter', 'Commission labor price for a scepter.', 'weapon', 'Common', 1000, 'Magecraft Commissions', 'scepter', 540),
  ('Staff', 'Commission labor price for a staff.', 'weapon', 'Common', 5000, 'Magecraft Commissions', 'staff', 550),
  ('Custom Magecraft Commission', 'Labor price for a flexible magecraft commission.', 'weapon', 'Common', 6500, 'Magecraft Commissions', 'custom-magecraft', 560),
  ('Shield', 'Forge labor price for crafting a shield.', 'shield', 'Common', 5000, 'Shield Creation', 'shield', 610)
) as seed(item_name, description, item_type, rarity, price_coin, shop_section, catalog_item_key, display_order) on v.blueprint_type = 'blacksmith'
where not exists (
  select 1
  from public.market_products existing
  where existing.vendor_id = v.id
    and existing.product_kind = 'service'
    and lower(existing.catalog_item_key) = lower(seed.catalog_item_key)
)
  and not exists (select 1 from public.app_data_repairs where repair_key = 'calostrynn-shop-defaults-preexisting-2026-08-24')
on conflict (product_key) do nothing;

insert into public.market_products (vendor_id, product_key, item_name, description, item_type, rarity, price_coin, currency_system_key, stock_quantity, shop_section, quantity_step, catalog_item_key, product_kind, mana_cost, mana_label, is_available, display_order)
select
  v.id,
  public.safe_slug(v.vendor_key || '-service-' || seed.catalog_item_key),
  seed.item_name,
  seed.description,
  public.normalize_item_type(seed.item_type),
  seed.rarity::public.item_rarity,
  case when v.city_key = 'calostrynn' then seed.price_coin else 0 end,
  case when v.city_key = 'calostrynn' then 'calostrynn' else 'common' end,
  null,
  seed.shop_section,
  1,
  seed.catalog_item_key,
  'service',
  0,
  '',
  true,
  seed.display_order
from public.shop_vendors v
join (values
  ('Leather Armor', 'Armory labor price for leather armor.', 'armor', 'Common', 0, 'Armor Creation', 'leather-armor', 210),
  ('Iron Armor', 'Armory labor price for iron armor.', 'armor', 'Common', 500, 'Armor Creation', 'iron-armor', 220),
  ('Steel Armor', 'Armory labor price for steel armor.', 'armor', 'Uncommon', 2500, 'Armor Creation', 'steel-armor', 230),
  ('Mythril Armor', 'Armory labor price for mythril armor.', 'armor', 'Rare', 5000, 'Armor Creation', 'mythril-armor', 240),
  ('Vaylium Armor', 'Armory labor price for vaylium armor.', 'armor', 'Epic', 7500, 'Armor Creation', 'vaylium-armor', 250),
  ('Dragonscale Armor', 'Armory labor price for dragonscale armor.', 'armor', 'Legendary', 10000, 'Armor Creation', 'dragonscale-armor', 260)
) as seed(item_name, description, item_type, rarity, price_coin, shop_section, catalog_item_key, display_order) on v.blueprint_type = 'armory'
where not exists (
  select 1
  from public.market_products existing
  where existing.vendor_id = v.id
    and existing.product_kind = 'service'
    and lower(existing.catalog_item_key) = lower(seed.catalog_item_key)
)
  and not exists (select 1 from public.app_data_repairs where repair_key = 'calostrynn-shop-defaults-preexisting-2026-08-24')
on conflict (product_key) do nothing;

with forge_recipe_duplicates as (
  select p.id
  from public.market_products p
  join public.shop_vendors v on v.id = p.vendor_id
  join (values
    ('blacksmith', 'dagger', 'Light Weapons', 'Dagger'),
    ('blacksmith', 'throwing-knives', 'Light Weapons', 'Throwing Knives'),
    ('blacksmith', 'shortbow', 'Light Weapons', 'Shortbow'),
    ('blacksmith', 'custom-light-weapon', 'Light Weapons', 'Custom Light Weapon'),
    ('blacksmith', 'sword', 'Medium Weapons', 'Sword'),
    ('blacksmith', 'spear', 'Medium Weapons', 'Spear'),
    ('blacksmith', 'longbow', 'Medium Weapons', 'Longbow'),
    ('blacksmith', 'custom-medium-weapon', 'Medium Weapons', 'Custom Medium Weapon'),
    ('blacksmith', 'battleaxe', 'Heavy Weapons', 'Battleaxe'),
    ('blacksmith', 'mace', 'Heavy Weapons', 'Mace'),
    ('blacksmith', 'claymore', 'Heavy Weapons', 'Claymore'),
    ('blacksmith', 'crossbow', 'Heavy Weapons', 'Crossbow'),
    ('blacksmith', 'custom-heavy-weapon', 'Heavy Weapons', 'Custom Heavy Weapon'),
    ('blacksmith', 'magic-bow', 'Magecraft Commissions', 'Magic Bow'),
    ('blacksmith', 'magic-longbow', 'Magecraft Commissions', 'Magic Longbow'),
    ('blacksmith', 'wand', 'Magecraft Commissions', 'Wand'),
    ('blacksmith', 'scepter', 'Magecraft Commissions', 'Scepter'),
    ('blacksmith', 'staff', 'Magecraft Commissions', 'Staff'),
    ('blacksmith', 'custom-magecraft', 'Magecraft Commissions', 'Custom Magecraft Commission'),
    ('blacksmith', 'shield', 'Shield Creation', 'Shield'),
    ('armory', 'leather-armor', 'Armor Creation', 'Leather Armor'),
    ('armory', 'iron-armor', 'Armor Creation', 'Iron Armor'),
    ('armory', 'steel-armor', 'Armor Creation', 'Steel Armor'),
    ('armory', 'mythril-armor', 'Armor Creation', 'Mythril Armor'),
    ('armory', 'vaylium-armor', 'Armor Creation', 'Vaylium Armor'),
    ('armory', 'dragonscale-armor', 'Armor Creation', 'Dragonscale Armor')
  ) as seed(blueprint_type, catalog_item_key, shop_section, item_name)
    on v.blueprint_type = seed.blueprint_type
   and (
     lower(coalesce(p.catalog_item_key, '')) = seed.catalog_item_key
     or (
       lower(coalesce(p.shop_section, '')) = lower(seed.shop_section)
       and lower(p.item_name) = lower(seed.item_name)
     )
   )
  where coalesce(p.product_kind, 'item') <> 'service'
    and exists (
      select 1
      from public.market_products service_row
      where service_row.vendor_id = p.vendor_id
        and service_row.product_kind = 'service'
        and lower(coalesce(service_row.catalog_item_key, '')) = seed.catalog_item_key
    )
)
delete from public.market_products p
using forge_recipe_duplicates d
where p.id = d.id;

create table if not exists public.app_data_repairs (
  repair_key text primary key,
  applied_at timestamptz not null default now()
);

with repair as (
  insert into public.app_data_repairs (repair_key)
  values ('forge-scale-live-stock-preservation-2026-08-01')
  on conflict (repair_key) do nothing
  returning repair_key
)
update public.market_products
set stock_quantity = 0,
    is_available = false,
    updated_at = now()
where exists (select 1 from repair)
  and product_key in ('blacksmith-vaylium-scale', 'blacksmith-dragonscale-scale', 'armory-vaylium-scale', 'armory-dragonscale-scale')
  and is_available
  and (
    (product_key in ('blacksmith-vaylium-scale', 'armory-vaylium-scale') and stock_quantity = 10)
    or (product_key in ('blacksmith-dragonscale-scale', 'armory-dragonscale-scale') and stock_quantity = 2)
  );

-- Seed Brewery defaults only when the Brewery has no rows yet.
insert into public.market_products (vendor_id, product_key, item_name, description, item_type, rarity, price_coin, stock_quantity, shop_section, quantity_step, catalog_item_key, product_kind, mana_cost, mana_label, is_available, display_order)
select v.id, seed.product_key, seed.item_name, seed.description, 'potion', seed.rarity::public.item_rarity, seed.price_coin, seed.stock_quantity::numeric, seed.shop_section, 1, seed.catalog_item_key, 'item', 0, '', seed.is_available, seed.display_order
from public.shop_vendors v
join (values
  ('brewery-arcane-nector', 'Arcane Nector', 'Required canvas for every brewed potion.', 'Uncommon', 100, 80, 'Brewing Supplies', 'arcane-nector', true, 10),
  ('brewery-empty-flask', 'Empty Flask', 'Empty byproduct of drinking a potion.', 'Common', 6, 80, 'Brewing Supplies', 'empty-flask', true, 20),
  ('brewery-lesser-healing-potion', 'Lesser Healing Potion', 'Restores 20 health when consumed.', 'Uncommon', 80, 6, 'Finished Potions', 'lesser-healing-potion', true, 100),
  ('brewery-greater-healing-potion', 'Greater Healing Potion', 'Restores 50 health when consumed.', 'Rare', 300, 3, 'Finished Potions', 'greater-healing-potion', true, 110),
  ('brewery-greatest-healing-potion', 'Greatest Healing Potion', 'Fully restores health when consumed.', 'Legendary', 1200, 1, 'Finished Potions', 'greatest-healing-potion', true, 120),
  ('brewery-lesser-swiftness-potion', 'Lesser Swiftness Potion (Fine)', 'Fine lesser swiftness potion. Resolve the effect at the table.', 'Uncommon', 80, 4, 'Finished Potions', 'lesser-swiftness-potion', true, 130),
  ('brewery-greater-swiftness-potion', 'Greater Swiftness Potion (Fine)', 'Fine greater swiftness potion. Resolve the effect at the table.', 'Rare', 300, 2, 'Finished Potions', 'greater-swiftness-potion', true, 140),
  ('brewery-greatest-swiftness-potion', 'Greatest Swiftness Potion (Fine)', 'Fine greatest swiftness potion. Resolve the effect at the table.', 'Legendary', 1500, 1, 'Finished Potions', 'greatest-swiftness-potion', true, 150),
  ('brewery-lesser-agility-potion', 'Lesser Agility Potion (Fine)', 'Fine lesser agility potion. Resolve the effect at the table.', 'Uncommon', 80, 4, 'Finished Potions', 'lesser-agility-potion', true, 160),
  ('brewery-greater-agility-potion', 'Greater Agility Potion (Fine)', 'Fine greater agility potion. Resolve the effect at the table.', 'Rare', 300, 2, 'Finished Potions', 'greater-agility-potion', true, 170),
  ('brewery-greatest-agility-potion', 'Greatest Agility Potion (Fine)', 'Fine greatest agility potion. Resolve the effect at the table.', 'Legendary', 1600, 1, 'Finished Potions', 'greatest-agility-potion', true, 180),
  ('brewery-lesser-strength-potion', 'Lesser Strength Potion (Fine)', 'Fine lesser strength potion. Resolve the effect at the table.', 'Uncommon', 80, 4, 'Finished Potions', 'lesser-strength-potion', true, 190),
  ('brewery-greater-strength-potion', 'Greater Strength Potion (Fine)', 'Fine greater strength potion. Resolve the effect at the table.', 'Rare', 300, 2, 'Finished Potions', 'greater-strength-potion', true, 200),
  ('brewery-greatest-strength-potion', 'Greatest Strength Potion (Fine)', 'Fine greatest strength potion. Resolve the effect at the table.', 'Legendary', 1500, 1, 'Finished Potions', 'greatest-strength-potion', true, 210),
  ('brewery-lesser-sorcery-potion', 'Lesser Sorcery Potion (Fine)', 'Fine lesser sorcery potion. Resolve the effect at the table.', 'Uncommon', 100, 3, 'Finished Potions', 'lesser-sorcery-potion', true, 220),
  ('brewery-greater-sorcery-potion', 'Greater Sorcery Potion (Fine)', 'Fine greater sorcery potion. Resolve the effect at the table.', 'Rare', 400, 2, 'Finished Potions', 'greater-sorcery-potion', true, 230),
  ('brewery-greatest-sorcery-potion', 'Greatest Sorcery Potion (Fine)', 'Fine greatest sorcery potion. Resolve the effect at the table.', 'Legendary', 1800, 1, 'Finished Potions', 'greatest-sorcery-potion', true, 240),
  ('brewery-lesser-mana-potion', 'Lesser Mana Potion', 'Restores 15 mana when consumed.', 'Uncommon', 200, 3, 'Finished Potions', 'lesser-mana-potion', true, 250),
  ('brewery-greater-mana-potion', 'Greater Mana Potion', 'Restores 40 mana when consumed.', 'Rare', 600, 2, 'Finished Potions', 'greater-mana-potion', true, 260),
  ('brewery-greatest-mana-potion', 'Greatest Mana Potion', 'Fully restores mana when consumed.', 'Legendary', 2200, 1, 'Finished Potions', 'greatest-mana-potion', true, 270),
  ('brewery-lesser-luck-potion', 'Lesser Luck Potion (Fine)', 'Fine lesser luck potion. Resolve the effect at the table.', 'Legendary', 10000, 1, 'Finished Potions', 'lesser-luck-potion', true, 280),
  ('brewery-greater-luck-potion', 'Greater Luck Potion (Fine)', 'Fine greater luck potion. Resolve the effect at the table.', 'Legendary', 70000, 0, 'Finished Potions', 'greater-luck-potion', false, 290),
  ('brewery-greatest-luck-potion', 'Greatest Luck Potion (Fine)', 'Fine greatest luck potion. Resolve the effect at the table.', 'Mythical', 300000, 0, 'Finished Potions', 'greatest-luck-potion', false, 300),
  ('brewery-lesser-antidote-potion', 'Lesser Antidote Potion (Fine)', 'Fine lesser antidote potion. Resolve the effect at the table.', 'Uncommon', 60, 6, 'Finished Potions', 'lesser-antidote-potion', true, 310),
  ('brewery-greater-antidote-potion', 'Greater Antidote Potion (Fine)', 'Fine greater antidote potion. Resolve the effect at the table.', 'Rare', 150, 3, 'Finished Potions', 'greater-antidote-potion', true, 320),
  ('brewery-greatest-antidote-potion', 'Greatest Antidote Potion (Fine)', 'Fine greatest antidote potion. Resolve the effect at the table.', 'Legendary', 400, 1, 'Finished Potions', 'greatest-antidote-potion', true, 330),
  ('brewery-lesser-warming-potion', 'Lesser Warming Potion (Fine)', 'Fine lesser warming potion. Resolve the effect at the table.', 'Uncommon', 80, 4, 'Finished Potions', 'lesser-warming-potion', true, 340),
  ('brewery-greater-warming-potion', 'Greater Warming Potion (Fine)', 'Fine greater warming potion. Resolve the effect at the table.', 'Rare', 200, 2, 'Finished Potions', 'greater-warming-potion', true, 350),
  ('brewery-greatest-warming-potion', 'Greatest Warming Potion (Fine)', 'Fine greatest warming potion. Resolve the effect at the table.', 'Legendary', 600, 1, 'Finished Potions', 'greatest-warming-potion', true, 360),
  ('brewery-lesser-cooling-potion', 'Lesser Cooling Potion (Fine)', 'Fine lesser cooling potion. Resolve the effect at the table.', 'Uncommon', 80, 4, 'Finished Potions', 'lesser-cooling-potion', true, 370),
  ('brewery-greater-cooling-potion', 'Greater Cooling Potion (Fine)', 'Fine greater cooling potion. Resolve the effect at the table.', 'Rare', 200, 2, 'Finished Potions', 'greater-cooling-potion', true, 380),
  ('brewery-greatest-cooling-potion', 'Greatest Cooling Potion (Fine)', 'Fine greatest cooling potion. Resolve the effect at the table.', 'Legendary', 600, 1, 'Finished Potions', 'greatest-cooling-potion', true, 390),
  ('brewery-lesser-night-eye-potion', 'Lesser Night-Eye Potion (Fine)', 'Fine lesser night-eye potion. Resolve the effect at the table.', 'Uncommon', 100, 4, 'Finished Potions', 'lesser-night-eye-potion', true, 400),
  ('brewery-greater-night-eye-potion', 'Greater Night-Eye Potion (Fine)', 'Fine greater night-eye potion. Resolve the effect at the table.', 'Rare', 300, 2, 'Finished Potions', 'greater-night-eye-potion', true, 410),
  ('brewery-greatest-night-eye-potion', 'Greatest Night-Eye Potion (Fine)', 'Fine greatest night-eye potion. Resolve the effect at the table.', 'Legendary', 800, 1, 'Finished Potions', 'greatest-night-eye-potion', true, 420),
  ('brewery-lesser-thickskin-potion', 'Lesser Thickskin Potion (Fine)', 'Fine lesser thickskin potion. Resolve the effect at the table.', 'Uncommon', 150, 3, 'Finished Potions', 'lesser-thickskin-potion', true, 430),
  ('brewery-greater-thickskin-potion', 'Greater Thickskin Potion (Fine)', 'Fine greater thickskin potion. Resolve the effect at the table.', 'Rare', 400, 2, 'Finished Potions', 'greater-thickskin-potion', true, 440),
  ('brewery-greatest-thickskin-potion', 'Greatest Thickskin Potion (Fine)', 'Fine greatest thickskin potion. Resolve the effect at the table.', 'Legendary', 1400, 1, 'Finished Potions', 'greatest-thickskin-potion', true, 450),
  ('brewery-lesser-clear-mind-potion', 'Lesser Clear-Mind Potion (Fine)', 'Fine lesser clear-mind potion. Resolve the effect at the table.', 'Uncommon', 150, 3, 'Finished Potions', 'lesser-clear-mind-potion', true, 460),
  ('brewery-greater-clear-mind-potion', 'Greater Clear-Mind Potion (Fine)', 'Fine greater clear-mind potion. Resolve the effect at the table.', 'Rare', 400, 2, 'Finished Potions', 'greater-clear-mind-potion', true, 470),
  ('brewery-greatest-clear-mind-potion', 'Greatest Clear-Mind Potion (Fine)', 'Fine greatest clear-mind potion. Resolve the effect at the table.', 'Legendary', 1400, 1, 'Finished Potions', 'greatest-clear-mind-potion', true, 480),
  ('brewery-lesser-wake-up-potion', 'Lesser Wake-Up Potion (Fine)', 'Fine lesser wake-up potion. Resolve the effect at the table.', 'Uncommon', 200, 3, 'Finished Potions', 'lesser-wake-up-potion', true, 490),
  ('brewery-greater-wake-up-potion', 'Greater Wake-Up Potion (Fine)', 'Fine greater wake-up potion. Resolve the effect at the table.', 'Rare', 500, 2, 'Finished Potions', 'greater-wake-up-potion', true, 500),
  ('brewery-greatest-wake-up-potion', 'Greatest Wake-Up Potion (Fine)', 'Fine greatest wake-up potion. Resolve the effect at the table.', 'Legendary', 1000, 1, 'Finished Potions', 'greatest-wake-up-potion', true, 510),
  ('brewery-lesser-clotting-potion', 'Lesser Clotting Potion (Fine)', 'Fine lesser clotting potion. Resolve the effect at the table.', 'Uncommon', 80, 5, 'Finished Potions', 'lesser-clotting-potion', true, 520),
  ('brewery-greater-clotting-potion', 'Greater Clotting Potion (Fine)', 'Fine greater clotting potion. Resolve the effect at the table.', 'Rare', 200, 3, 'Finished Potions', 'greater-clotting-potion', true, 530),
  ('brewery-greatest-clotting-potion', 'Greatest Clotting Potion (Fine)', 'Fine greatest clotting potion. Resolve the effect at the table.', 'Legendary', 600, 1, 'Finished Potions', 'greatest-clotting-potion', true, 540)
) as seed(product_key, item_name, description, rarity, price_coin, stock_quantity, shop_section, catalog_item_key, is_available, display_order)
on v.vendor_key = 'calostrynn-brewery'
where not exists (
  select 1 from public.market_products existing
  where existing.vendor_id = v.id
)
  and not exists (select 1 from public.app_data_repairs where repair_key = 'calostrynn-shop-defaults-preexisting-2026-08-24')
on conflict (product_key) do nothing;

insert into public.market_products (vendor_id, product_key, item_name, description, item_type, rarity, price_coin, stock_quantity, shop_section, quantity_step, catalog_item_key, is_available, display_order)
select v.id, seed.product_key, seed.item_name, seed.description, 'book', seed.rarity::public.item_rarity, seed.price_coin, seed.stock_quantity::numeric, 'Books', 1, seed.catalog_item_key, true, seed.display_order
from public.shop_vendors v
join (values
  ('library-history-book', 'History Book', 'A general history volume. Resolve its contents at the table.', 'Common', 100, null, 'history-book', 10),
  ('library-alchemy-book', 'Alchemy Book', 'An alchemical study text. Resolve its contents at the table.', 'Common', 500, null, 'alchemy-book', 20),
  ('library-bestiary', 'Bestiary', 'A creature reference volume. Resolve its contents at the table.', 'Common', 1000, null, 'bestiary', 30),
  ('library-magical-research', 'Magical Research', 'Choose a spell category to receive a rare magic spell book for that category.', 'Rare', 2500, null, 'magical-research', 40)
) as seed(product_key, item_name, description, rarity, price_coin, stock_quantity, catalog_item_key, display_order)
on v.vendor_key = 'calostrynn-library'
where not exists (
  select 1 from public.market_products existing
  where existing.vendor_id = v.id
)
  and not exists (select 1 from public.app_data_repairs where repair_key = 'calostrynn-shop-defaults-preexisting-2026-08-24')
on conflict (product_key) do nothing;

insert into public.market_products (vendor_id, product_key, item_name, description, item_type, rarity, price_coin, stock_quantity, shop_section, quantity_step, catalog_item_key, is_available, display_order)
select v.id, seed.product_key, seed.item_name, seed.description, public.normalize_item_type(seed.item_type), seed.rarity::public.item_rarity, seed.price_coin, seed.stock_quantity::numeric, seed.shop_section, 1, seed.catalog_item_key, true, seed.display_order
from public.shop_vendors v
join (values
  ('city-market-waist-pouch', 'Waist Pouch', 'Rowan sells a compact pouch with 1 storage slot.', 'storage', 'Common', 8, null, 'Rowan - Storage', 'waist-pouch', 10),
  ('city-market-back-bag', 'Back Bag', 'Rowan sells a back bag with 3 storage slots.', 'storage', 'Common', 80, null, 'Rowan - Storage', 'back-bag', 20),
  ('city-market-light-duffle', 'Light Duffle', 'Rowan sells a light duffle with 6 storage slots.', 'storage', 'Uncommon', 200, null, 'Rowan - Storage', 'light-duffle', 30),
  ('city-market-heavy-duffle', 'Heavy Duffle', 'Rowan sells a heavy duffle with 10 storage slots.', 'storage', 'Rare', 500, null, 'Rowan - Storage', 'heavy-duffle', 40),
  ('city-market-bag-of-holding', 'Bag of Holding', 'Rowan sells a magical bag with 100 storage slots.', 'storage', 'Mythical', 2500000, null, 'Rowan - Storage', 'bag-of-holding', 50),
  ('city-market-light-wagon', 'Light Wagon', 'Rowan sells a light wagon with 25 storage slots.', 'storage', 'Rare', 2500, null, 'Rowan - Storage', 'light-wagon', 60),
  ('city-market-heavy-wagon', 'Heavy Wagon', 'Rowan sells a heavy wagon with 60 storage slots.', 'storage', 'Epic', 6000, null, 'Rowan - Storage', 'heavy-wagon', 70),
  ('city-market-caged-wagon', 'Caged Wagon', 'Rowan sells a caged wagon that acts as a 3-animal stable.', 'storage', 'Epic', 8000, null, 'Rowan - Storage', 'caged-wagon', 80),
  ('city-market-wagon-home', 'Wagon Home', 'Rowan sells a wagon home with 40 storage slots.', 'storage', 'Epic', 10000, null, 'Rowan - Storage', 'wagon-home', 90),
  ('city-market-torch', 'Torch', 'Cedrick sells a basic torch for travel and dungeon work.', 'tool', 'Common', 3, null, 'Cedrick - Supplies', 'torch', 100),
  ('city-market-arrow', 'Arrow', 'Cedrick sells individual arrows for bows and ranged combat.', 'weapon', 'Common', 10, null, 'Cedrick - Supplies', 'arrow', 105),
  ('city-market-rope', 'Rope', 'Cedrick sells a coil of sturdy rope.', 'tool', 'Common', 10, null, 'Cedrick - Supplies', 'rope', 110),
  ('city-market-blanket', 'Blanket', 'Cedrick sells a simple travel blanket.', 'fabric', 'Common', 8, null, 'Cedrick - Supplies', 'blanket', 120),
  ('city-market-cooking-pots', 'Cooking Pots', 'Cedrick sells cooking pots for camp meals.', 'tool', 'Common', 10, null, 'Cedrick - Supplies', 'cooking-pots', 130),
  ('city-market-cloth', 'Cloth', 'Cedrick sells common cloth.', 'fabric', 'Common', 2, null, 'Cedrick - Supplies', 'cloth', 140),
  ('city-market-fine-cloth', 'Fine Cloth', 'Cedrick sells fine cloth.', 'fabric', 'Common', 50, null, 'Cedrick - Supplies', 'fine-cloth', 150),
  ('city-market-ink-and-paper', 'Ink and Paper', 'Cedrick sells ink and paper for notes, maps, and records.', 'tool', 'Common', 5, null, 'Cedrick - Supplies', 'ink-and-paper', 160),
  ('city-market-lock', 'Lock', 'Cedrick sells a standard lock.', 'tool', 'Common', 20, null, 'Cedrick - Supplies', 'lock', 170),
  ('city-market-standard-hammer', 'Standard Hammer', 'Cedrick sells a standard hammer.', 'tool', 'Common', 10, null, 'Cedrick - Supplies', 'standard-hammer', 180),
  ('city-market-standard-axe', 'Standard Axe', 'Cedrick sells a standard axe.', 'tool', 'Common', 40, null, 'Cedrick - Supplies', 'standard-axe', 190),
  ('city-market-quartz', 'Quartz', 'Dorien sells a quartz gem.', 'ore', 'Rare', 1000, null, 'Dorien - Jeweler', 'quartz', 220),
  ('city-market-emerald', 'Emerald', 'Dorien sells an emerald gem.', 'ore', 'Epic', 4000, null, 'Dorien - Jeweler', 'emerald', 230),
  ('city-market-ruby', 'Ruby', 'Dorien sells a ruby gem.', 'ore', 'Epic', 5000, null, 'Dorien - Jeweler', 'ruby', 240),
  ('city-market-sapphire', 'Sapphire', 'Dorien sells a sapphire gem.', 'ore', 'Legendary', 10000, null, 'Dorien - Jeweler', 'sapphire', 250),
  ('city-market-winter-wear', 'Winter Wear', 'Elara sells clothing suited for winter travel.', 'fabric', 'Uncommon', 50, null, 'Elara - Clothier', 'winter-wear', 300),
  ('city-market-heat-wear', 'Heat Wear', 'Elara sells clothing suited for hot climates.', 'fabric', 'Uncommon', 40, null, 'Elara - Clothier', 'heat-wear', 310),
  ('city-market-rainproof-wear', 'Rainproof Wear', 'Elara sells clothing suited for wet weather.', 'fabric', 'Uncommon', 60, null, 'Elara - Clothier', 'rainproof-wear', 320),
  ('city-market-basic-meal', 'Basic Meal', 'Lucien serves a basic meal.', 'food', 'Common', 2, null, 'Lucien - Tavern Keep', 'basic-meal', 350),
  ('city-market-tavern-meal', 'Tavern Meal', 'Lucien serves a filling tavern meal.', 'food', 'Common', 5, null, 'Lucien - Tavern Keep', 'tavern-meal', 360),
  ('city-market-inn-room', 'Inn Room', 'Lucien offers a standard inn room voucher.', 'quest', 'Common', 10, null, 'Lucien - Tavern Keep', 'inn-room', 370),
  ('city-market-fine-inn', 'Fine Inn', 'Lucien offers a fine inn voucher.', 'quest', 'Common', 50, null, 'Lucien - Tavern Keep', 'fine-inn', 380),
  ('city-market-horse', 'Horse', 'Cassandra sells a riding horse.', 'pet', 'Rare', 1000, null, 'Cassandra - Stable Keeper', 'horse', 420),
  ('city-market-war-horse', 'War Horse', 'Cassandra sells a trained war horse.', 'pet', 'Rare', 5000, null, 'Cassandra - Stable Keeper', 'war-horse', 430),
  ('city-market-dog', 'Dog', '', 'pet', 'Epic', 1000, null, 'Cassandra - Stable Keeper', 'dog', 440)
) as seed(product_key, item_name, description, item_type, rarity, price_coin, stock_quantity, shop_section, catalog_item_key, display_order)
on v.vendor_key = 'calostrynn-city-market'
where not exists (
  select 1 from public.market_products existing
  where existing.vendor_id = v.id
)
  and not exists (select 1 from public.app_data_repairs where repair_key = 'calostrynn-shop-defaults-preexisting-2026-08-24')
on conflict (product_key) do nothing;

update public.market_products
set description = ''
where public.catalog_key_for_name(item_name) = 'dog'
   or catalog_item_key = 'dog';

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

create or replace function public.city_names_match(p_left text, p_right text)
returns boolean
language sql
immutable
as $$
  select length(trim(regexp_replace(coalesce(p_left, ''), '\*+$', ''))) > 0
    and lower(trim(regexp_replace(coalesce(p_left, ''), '\*+$', ''))) = lower(trim(regexp_replace(coalesce(p_right, ''), '\*+$', '')))
$$;

create or replace function public.assert_valid_character_location(p_location_name text)
returns text
language plpgsql
stable
set search_path = public, extensions
as $$
declare
  v_location text := coalesce(nullif(trim(p_location_name), ''), 'Wild');
  v_city public.cities%rowtype;
begin
  if public.city_names_match(v_location, 'Wild') then
    return 'Wild';
  end if;

  select *
  into v_city
  from public.cities
  where public.city_names_match(name, v_location)
  order by display_order, name
  limit 1;

  if v_city.id is null then
    raise exception 'Character location must be a discovered city or Wild.';
  end if;

  return v_city.name;
end;
$$;

create or replace function public.resolve_character_location(
  p_location_city_key text,
  p_location_name text
)
returns table(location_city_key text, location_name text)
language plpgsql
stable
set search_path = public, extensions
as $$
declare
  v_key text := nullif(trim(coalesce(p_location_city_key, '')), '');
  v_name text := nullif(trim(coalesce(p_location_name, '')), '');
  v_city public.cities%rowtype;
begin
  if v_key is null and (v_name is null or public.city_names_match(v_name, 'Wild')) then
    location_city_key := null;
    location_name := 'Wild';
    return next;
    return;
  end if;

  if v_key is not null then
    if public.city_names_match(v_key, 'Wild') then
      location_city_key := null;
      location_name := 'Wild';
      return next;
      return;
    end if;

    select *
    into v_city
    from public.cities
    where city_key = v_key
    limit 1;
  end if;

  if v_city.id is null and v_name is not null then
    select *
    into v_city
    from public.cities
    where public.city_names_match(name, v_name)
    order by display_order, name
    limit 1;
  end if;

  if v_city.id is null then
    raise exception 'Character location must be a discovered city or Wild.';
  end if;

  location_city_key := v_city.city_key;
  location_name := v_city.name;
  return next;
end;
$$;

create or replace function public.character_is_in_city(
  p_character public.characters,
  p_city_key text
)
returns boolean
language sql
stable
set search_path = public
as $$
  select coalesce(p_character.location_city_key, '') = coalesce(p_city_key, '')
    or (
      p_character.location_city_key is null
      and exists (
        select 1
        from public.cities city
        where city.city_key = p_city_key
          and public.city_names_match(city.name, p_character.location_name)
      )
    )
$$;

create or replace function public.characters_share_location(
  p_left public.characters,
  p_right public.characters
)
returns boolean
language sql
stable
set search_path = public
as $$
  select case
    when p_left.location_city_key is not null or p_right.location_city_key is not null
      then coalesce(p_left.location_city_key, '') = coalesce(p_right.location_city_key, '')
    else public.city_names_match(p_left.location_name, p_right.location_name)
  end
$$;

create or replace function public.market_product_record_to_json(p_product public.market_products, p_is_dm boolean default false)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'id', p_product.id,
    'vendorId', p_product.vendor_id,
    'key', p_product.product_key,
    'name', p_product.item_name,
    'displayName', p_product.item_display_name,
    'description', p_product.description,
    'type', p_product.item_type,
    'rarity', p_product.rarity,
    'priceCoin', p_product.price_coin,
    'currencySystemKey', p_product.currency_system_key,
    'stockQuantity', p_product.stock_quantity,
    'catalogItemKey', p_product.catalog_item_key,
    'section', p_product.shop_section,
    'quantityStep', p_product.quantity_step,
    'kind', p_product.product_kind,
    'manaCost', p_product.mana_cost,
    'manaLabel', p_product.mana_label,
    'documentAuthor', p_product.document_author,
    'documentContent', case when p_product.product_kind = 'document' and p_product.document_visibility <> 'government' and not coalesce(p_is_dm, false) then '' else p_product.document_content end,
    'documentPages', case when p_product.product_kind = 'document' and p_product.document_visibility <> 'government' and not coalesce(p_is_dm, false) then '[]'::jsonb else coalesce(p_product.document_pages, '[]'::jsonb) end,
    'documentVisibility', p_product.document_visibility,
    'documentEditorUserId', p_product.document_editor_user_id,
    'boardedOwnerUserId', p_product.boarded_owner_user_id,
    'boardedSourceCharacterId', p_product.boarded_source_character_id,
    'boardedAt', p_product.boarded_at,
    'available', p_product.is_available
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

create or replace function public.currency_unit_value(p_currency_system_key text, p_unit_key text)
returns int
language sql
immutable
as $$
  select case coalesce(p_currency_system_key, 'calostrynn')
    when 'common' then case p_unit_key
      when 'bit' then 1
      when 'shilling' then 10
      when 'mark' then 100
      when 'crown' then 1000
      when 'sovereign' then 10000
      else 0
    end
    else public.currency_coin_value(p_unit_key)
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

create or replace function public.wallet_total_currency(p_character_id uuid, p_currency_system_key text)
returns int
language sql
stable
set search_path = public
as $$
  select coalesce(sum(b.amount * public.currency_unit_value(u.currency_system_key, u.unit_key)), 0)::int
  from public.character_wallet_balances b
  join public.currency_units u on u.id = b.currency_unit_id
  where b.character_id = p_character_id
    and u.currency_system_key = coalesce(nullif(trim(p_currency_system_key), ''), 'calostrynn')
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

create or replace function public.set_wallet_from_currency_value(
  p_character_id uuid,
  p_currency_system_key text,
  p_value int
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_system text := case when p_currency_system_key = 'common' then 'common' else 'calostrynn' end;
  v_remaining int := greatest(0, coalesce(p_value, 0));
  v_amount int;
  v_unit record;
begin
  for v_unit in
    select unit_key, id, public.currency_unit_value(currency_system_key, unit_key) as value
    from public.currency_units
    where currency_system_key = v_system
    order by public.currency_unit_value(currency_system_key, unit_key) desc
  loop
    v_amount := case when v_unit.value > 0 then floor(v_remaining / v_unit.value) else 0 end;
    v_remaining := v_remaining - v_amount * v_unit.value;

    insert into public.character_wallet_balances (character_id, currency_unit_id, amount)
    values (p_character_id, v_unit.id, v_amount)
    on conflict (character_id, currency_unit_id) do update
    set amount = excluded.amount;
  end loop;
end;
$$;

create or replace function public.credit_character_wallet_value(
  p_character_id uuid,
  p_currency_system_key text,
  p_value int
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total int;
begin
  if p_character_id is null or coalesce(p_value, 0) <= 0 then
    return;
  end if;

  v_total := public.wallet_total_currency(p_character_id, p_currency_system_key) + greatest(0, coalesce(p_value, 0));
  perform public.set_wallet_from_currency_value(p_character_id, p_currency_system_key, v_total);
end;
$$;

create or replace function public.ensure_dm_testing_wallet(p_character_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner public.profiles%rowtype;
  v_floor int := 9999 * 10000;
begin
  if p_character_id is null then
    return;
  end if;

  select p.* into v_owner
  from public.characters c
  join public.profiles p on p.id = c.owner_user_id
  where c.id = p_character_id
    and p.role = 'dm'::public.user_role;

  if v_owner.id is null then
    return;
  end if;

  if public.wallet_total_currency(p_character_id, 'calostrynn') < v_floor then
    perform public.set_wallet_from_currency_value(p_character_id, 'calostrynn', v_floor);
  end if;

  if public.wallet_total_currency(p_character_id, 'common') < v_floor then
    perform public.set_wallet_from_currency_value(p_character_id, 'common', v_floor);
  end if;
end;
$$;

create or replace function public.profile_runs_shop_vendor(
  p_profile public.profiles,
  p_vendor public.shop_vendors
)
returns boolean
language sql
stable
set search_path = public
as $$
  select coalesce(p_vendor.payout_character_id is not null, false)
    and exists (
      select 1
      from public.characters c
      where c.id = p_vendor.payout_character_id
        and c.owner_user_id = p_profile.id
    )
$$;

create or replace function public.profile_can_manage_shop_vendor(
  p_profile public.profiles,
  p_vendor public.shop_vendors
)
returns boolean
language sql
stable
set search_path = public
as $$
  select p_profile.role = 'dm'::public.user_role
    or public.profile_runs_shop_vendor(p_profile, p_vendor)
$$;

create or replace function public.profile_can_price_stable_vendor(
  p_profile public.profiles,
  p_vendor public.shop_vendors
)
returns boolean
language sql
stable
set search_path = public
as $$
  select p_profile.role = 'dm'::public.user_role
    or (
      public.profile_runs_shop_vendor(p_profile, p_vendor)
      and p_vendor.blueprint_type = 'stable'
    )
$$;

create or replace function public.stable_section_type_for_product(p_product public.market_products)
returns text
language sql
stable
set search_path = public
as $$
  select coalesce((
    select s.section_type
    from public.shop_sections s
    where s.vendor_id = p_product.vendor_id
      and s.section_name = coalesce(nullif(trim(p_product.shop_section), ''), 'Wares')
    limit 1
  ), case
    when lower(coalesce(p_product.shop_section, '')) like '%rent%' then 'rent'
    when lower(coalesce(p_product.shop_section, '')) like '%hold%' then 'holding'
    when lower(coalesce(p_product.shop_section, '')) like '%sale%' or lower(coalesce(p_product.shop_section, '')) like '%sell%' then 'sale'
    else 'sale'
  end)
$$;

alter table public.shop_vendors
add column if not exists npc_name text not null default 'Shopkeeper',
add column if not exists blueprint_type text not null default 'market',
add column if not exists payout_character_id uuid references public.characters(id) on delete set null,
add column if not exists is_custom boolean not null default false,
add column if not exists boarding_fee_coin int not null default 0 check (boarding_fee_coin >= 0);

alter table public.shop_vendors
  drop constraint if exists shop_vendors_blueprint_type_check,
  add constraint shop_vendors_blueprint_type_check check (blueprint_type in ('market', 'blacksmith', 'armory', 'brewery', 'spell_registrar', 'library', 'stable'));

alter table public.market_products
  add column if not exists product_kind text not null default 'item',
  add column if not exists item_display_name text,
  add column if not exists document_author text not null default '',
  add column if not exists document_content text not null default '',
  add column if not exists document_pages jsonb not null default '[]'::jsonb,
  add column if not exists document_visibility text not null default 'for_sale',
  add column if not exists document_editor_user_id uuid references public.profiles(id) on delete set null,
  add column if not exists mana_cost int not null default 0 check (mana_cost >= 0),
  add column if not exists mana_label text not null default '',
  add column if not exists item_is_accessory boolean not null default false,
  add column if not exists item_is_storage boolean not null default false,
  add column if not exists item_storage_capacity int not null default 0,
  add column if not exists item_modifiers jsonb not null default '{}'::jsonb,
  add column if not exists item_enchantment text,
  add column if not exists item_rune_name text,
  add column if not exists item_material text,
  add column if not exists item_enhancement_count int not null default 0,
  add column if not exists item_is_two_handed boolean not null default false,
  add column if not exists item_potion_strength text,
  add column if not exists item_potion_property text,
  add column if not exists item_potion_quality text,
  add column if not exists item_spell_book_form int not null default 1,
  add column if not exists boarded_owner_user_id uuid references public.profiles(id) on delete set null,
  add column if not exists boarded_source_character_id uuid references public.characters(id) on delete set null,
  add column if not exists boarded_at timestamptz;

alter table public.market_products
  drop constraint if exists market_products_product_kind_check,
  add constraint market_products_product_kind_check check (product_kind in ('item', 'spell', 'document', 'service'));

alter table public.market_products
  drop constraint if exists market_products_document_visibility_check,
  add constraint market_products_document_visibility_check check (document_visibility in ('government', 'for_sale'));

alter table public.market_products
  drop constraint if exists market_products_item_storage_capacity_check,
  add constraint market_products_item_storage_capacity_check check (item_storage_capacity >= 0 and item_storage_capacity <= 500),
  drop constraint if exists market_products_item_modifiers_object_check,
  add constraint market_products_item_modifiers_object_check check (jsonb_typeof(item_modifiers) = 'object'),
  drop constraint if exists market_products_item_enhancement_count_check,
  add constraint market_products_item_enhancement_count_check check (item_enhancement_count between 0 and 3),
  drop constraint if exists market_products_item_spell_book_form_check,
  add constraint market_products_item_spell_book_form_check check (item_spell_book_form in (1, 2));

update public.shop_vendors
set blueprint_type = 'market'
where vendor_key = 'calostrynn-city-market'
  and blueprint_type <> 'market'
  and not exists (select 1 from public.app_data_repairs where repair_key = 'calostrynn-shop-defaults-preexisting-2026-08-24');

update public.shop_vendors
set blueprint_type = case
  when vendor_key = 'calostrynn-blacksmith' then 'blacksmith'
  when vendor_key = 'calostrynn-armory' then 'armory'
  when vendor_key = 'calostrynn-brewery' then 'brewery'
  when vendor_key = 'calostrynn-spells' then 'spell_registrar'
  when vendor_key = 'calostrynn-library' then 'library'
  else blueprint_type
end,
is_custom = false
where vendor_key in ('calostrynn-blacksmith', 'calostrynn-armory', 'calostrynn-brewery', 'calostrynn-spells', 'calostrynn-library', 'calostrynn-city-market')
  and not exists (select 1 from public.app_data_repairs where repair_key = 'calostrynn-shop-defaults-preexisting-2026-08-24');

update public.market_products
set product_kind = case
  when item_type = 'spell' or shop_section ilike '%spells%' then 'spell'
  when vendor_id in (select id from public.shop_vendors where blueprint_type = 'library') then 'document'
  when item_type = 'food' and shop_section ilike '%tavern%' then 'service'
  else 'item'
end
where not exists (select 1 from public.app_data_repairs where repair_key = 'calostrynn-shop-defaults-preexisting-2026-08-24');

insert into public.shop_sections (vendor_id, section_key, section_name, display_order)
select
  p.vendor_id,
  public.safe_slug(coalesce(nullif(trim(p.shop_section), ''), 'Wares')),
  coalesce(nullif(trim(p.shop_section), ''), 'Wares'),
  coalesce(min(p.display_order), 0)
from public.market_products p
group by p.vendor_id, coalesce(nullif(trim(p.shop_section), ''), 'Wares')
on conflict (vendor_id, section_key) do update
set section_name = excluded.section_name,
    display_order = least(public.shop_sections.display_order, excluded.display_order);

insert into public.shop_sections (vendor_id, section_key, section_name, section_type, display_order, slot_count)
select v.id, public.safe_slug(seed.section_name), seed.section_name, seed.section_type, seed.display_order, seed.slot_count
from public.shop_vendors v
join (values
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
) as seed(blueprint_type, section_name, section_type, display_order, slot_count) on seed.blueprint_type = v.blueprint_type
on conflict (vendor_id, section_key) do nothing;

update public.shop_sections s
set section_type = case
    when lower(s.section_name) like '%rent%' then 'rent'
    when lower(s.section_name) like '%hold%' then 'holding'
    when lower(s.section_name) like '%sale%' or lower(s.section_name) like '%sell%' then 'sale'
    else 'sale'
  end
from public.shop_vendors v
where v.id = s.vendor_id
  and v.blueprint_type = 'stable';

delete from public.shop_sections s
using public.shop_vendors v
where s.vendor_id = v.id
  and v.blueprint_type = 'library'
  and v.vendor_key <> 'calostrynn-library'
  and s.section_name in ('Government', 'Recreation', 'For Sale')
  and not exists (
    select 1
    from public.market_products p
    where p.vendor_id = s.vendor_id
      and coalesce(nullif(trim(p.shop_section), ''), 'Wares') = s.section_name
  );

update public.market_products
set document_pages = to_jsonb(array[document_content])
where product_kind = 'document'
  and jsonb_array_length(coalesce(document_pages, '[]'::jsonb)) = 0
  and length(trim(coalesce(document_content, ''))) > 0;

update public.market_products
set document_visibility = case
  when lower(coalesce(shop_section, '')) = 'government' then 'government'
  else 'for_sale'
end
where product_kind = 'document'
  and document_visibility not in ('government', 'for_sale');

create or replace function public.shop_section_record_to_json(p_section public.shop_sections)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'id', p_section.id,
    'vendorId', p_section.vendor_id,
    'key', p_section.section_key,
    'name', p_section.section_name,
    'npcName', p_section.npc_name,
    'roleLabel', p_section.role_label,
    'sectionType', p_section.section_type,
    'slotCount', p_section.slot_count,
    'hidden', p_section.is_hidden,
    'order', p_section.display_order,
    'productCount', (
      select count(*)::int
      from public.market_products p
      where p.vendor_id = p_section.vendor_id
        and coalesce(nullif(trim(p.shop_section), ''), 'Wares') = p_section.section_name
    )
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
    'npcName', p_vendor.npc_name,
    'facility', p_vendor.facility,
    'category', p_vendor.category,
    'blueprintType', p_vendor.blueprint_type,
    'payoutCharacterId', p_vendor.payout_character_id,
    'boardingFeeCoin', p_vendor.boarding_fee_coin,
    'custom', p_vendor.is_custom,
    'hidden', p_vendor.is_hidden,
    'order', p_vendor.display_order,
    'sections', (
      select coalesce(jsonb_agg(public.shop_section_record_to_json(s) order by s.display_order, s.section_name), '[]'::jsonb)
      from public.shop_sections s
      where s.vendor_id = p_vendor.id
        and (p_is_dm or not s.is_hidden)
    ),
    'products', (
      select coalesce(jsonb_agg(public.market_product_record_to_json(p, p_is_dm) order by p.display_order, p.item_name), '[]'::jsonb)
      from public.market_products p
      where p.vendor_id = p_vendor.id
        and (p_is_dm or p.is_available)
    )
  );
$$;


create or replace function public.get_discovered_cities(p_session_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_construction_projects jsonb := '[]'::jsonb;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then
    raise exception 'Invalid or expired session.';
  end if;

  if to_regclass('public.city_construction_projects') is not null
    and to_regprocedure('public.city_construction_project_to_json(public.city_construction_projects)') is not null
  then
    execute $query$
      select coalesce(jsonb_agg(public.city_construction_project_to_json(project) order by project.city_key, project.display_order, project.project_name), '[]'::jsonb)
      from public.city_construction_projects project
      join public.cities city on city.city_key = project.city_key
      where project.status = 'active'
        and ($1 = 'dm'::public.user_role or city.is_player_visible)
    $query$
    into v_construction_projects
    using v_profile.role;
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
    'constructionProjects', v_construction_projects
  );
end;
$$;

drop function if exists public.purchase_market_product(text, uuid, uuid, numeric);

create or replace function public.purchase_market_product(
  p_session_token text,
  p_character_id uuid,
  p_product_id uuid,
  p_quantity numeric default 1,
  p_purchase_option text default null
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
  v_catalog public.item_catalog%rowtype;
  v_spell public.spell_catalog%rowtype;
  v_quantity numeric := greatest(0.5, coalesce(p_quantity, 1));
  v_cost int;
  v_wallet int;
  v_slot int;
  v_inventory_quantity numeric;
  v_modifiers jsonb := '{}'::jsonb;
  v_material text := '';
  v_is_two_handed boolean := false;
  v_storage_capacity int := 0;
  v_storage_item public.inventory_items%rowtype;
  v_target public.inventory_items%rowtype;
  v_item public.inventory_items%rowtype;
  v_item_name text;
  v_potion_strength text;
  v_potion_property text;
  v_potion_quality text;
  v_research_type text;
  v_storage_kind text;
  v_storage_active boolean := false;
  v_storage_slot int;
  v_stable_section_type text := 'sale';
  v_is_accessory boolean := false;
  v_is_storage boolean := false;
  v_enchantment text;
  v_rune_name text;
  v_spell_book_form int := 1;
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
  if v_product.price_coin <= 0 then
    raise exception 'That item is out of stock until the DM sets a price.';
  end if;

  select * into v_catalog
  from public.item_catalog
  where item_key = coalesce(nullif(v_product.catalog_item_key, ''), public.catalog_key_for_name(v_product.item_name))
  limit 1;

  v_item_name := public.normalize_item_name(v_product.item_name);
  v_quantity := public.assert_valid_item_quantity(v_item_name, v_product.item_type, v_quantity);
  if v_catalog.id is not null then
    v_modifiers := v_catalog.default_modifiers;
    v_material := v_catalog.material;
    v_is_two_handed := v_catalog.is_two_handed;
    v_storage_capacity := v_catalog.storage_capacity;
  end if;
  if v_product.item_modifiers <> '{}'::jsonb then v_modifiers := v_product.item_modifiers; end if;
  v_is_accessory := coalesce(v_product.item_is_accessory, false);
  v_is_storage := coalesce(v_product.item_is_storage, false);
  v_enchantment := nullif(v_product.item_enchantment, '');
  v_rune_name := nullif(v_product.item_rune_name, '');
  if nullif(v_product.item_material, '') is not null then v_material := v_product.item_material; end if;
  if coalesce(v_product.item_storage_capacity, 0) > 0 then v_storage_capacity := v_product.item_storage_capacity; end if;
  if coalesce(v_product.item_enhancement_count, 0) > 0 then v_product.item_enhancement_count := least(3, v_product.item_enhancement_count); end if;
  if v_product.item_is_two_handed then v_is_two_handed := true; end if;
  v_spell_book_form := case when v_product.item_spell_book_form = 2 then 2 else 1 end;
  v_potion_strength := nullif(v_product.item_potion_strength, '');
  v_potion_property := nullif(v_product.item_potion_property, '');
  v_potion_quality := nullif(v_product.item_potion_quality, '');
  if v_product.item_type = 'potion' then
    v_potion_strength := coalesce(v_potion_strength, public.potion_strength_from_name(v_item_name));
    v_potion_property := coalesce(v_potion_property, public.potion_property_from_name(v_item_name));
    v_potion_quality := case
      when v_potion_property in ('Healing', 'Mana Regen') then null
      when lower(v_item_name) = 'empty flask' then null
      else coalesce(v_potion_quality, public.potion_quality_from_name(v_item_name))
    end;
    if v_potion_strength is not null and v_potion_property is not null then
      v_item_name := public.format_potion_item_name(v_potion_strength, v_potion_property, v_potion_quality);
      v_product.rarity := public.potion_rarity_for(v_potion_strength, v_potion_property);
    end if;
  end if;

  select * into v_vendor from public.shop_vendors where id = v_product.vendor_id;
  select * into v_city from public.cities where city_key = v_vendor.city_key;
  if v_city.id is null then
    raise exception 'City not found.';
  end if;

  if v_city.is_locked then
    raise exception 'That city is currently locked.';
  end if;

  if v_vendor.blueprint_type = 'stable' then
    v_stable_section_type := public.stable_section_type_for_product(v_product);
    if v_stable_section_type = 'holding' then
      raise exception 'Animals in holding are not available for purchase.';
    end if;
  end if;

  if not public.character_is_in_city(v_character, v_city.city_key) then
    raise exception 'That character is not in %.', v_city.name;
  end if;

  if v_product.product_kind = 'service'
    or (
      v_vendor.vendor_key = 'calostrynn-city-market'
      and lower(trim(coalesce(v_product.shop_section, ''))) = 'lucien - tavern keep'
    )
  then
    if v_product.stock_quantity is not null and v_quantity > v_product.stock_quantity then
      raise exception 'Not enough stock.';
    end if;

    v_cost := ceil((v_product.price_coin * v_quantity)::numeric)::int;
    if v_vendor.payout_character_id is not distinct from v_character.id then
      v_cost := 0;
    end if;
    v_wallet := public.wallet_total_currency(v_character.id, v_product.currency_system_key);
    if v_wallet < v_cost then
      raise exception 'Not enough currency.';
    end if;

    perform public.set_wallet_from_currency_value(v_character.id, v_product.currency_system_key, v_wallet - v_cost);
    perform public.credit_character_wallet_value(v_vendor.payout_character_id, v_product.currency_system_key, v_cost);
    perform public.ensure_dm_testing_wallet(v_character.id);

    if v_product.stock_quantity is not null then
      update public.market_products
      set stock_quantity = greatest(0, stock_quantity - v_quantity)
      where id = v_product.id;
    end if;

    return public.get_discovered_cities(p_session_token);
  end if;

  if v_vendor.blueprint_type = 'spell_registrar'
    or v_product.product_kind = 'spell'
    or v_product.shop_section ilike '%spells%'
  then
    select * into v_spell
    from public.spell_catalog
    where spell_key = coalesce(nullif(v_product.catalog_item_key, ''), public.catalog_key_for_name(v_product.item_name))
      and is_available
    limit 1;

    if v_spell.id is null then
      raise exception 'Spell is not available.';
    end if;

    v_quantity := 1;

    if v_product.stock_quantity is not null and v_product.stock_quantity < 1 then
      raise exception 'Not enough stock.';
    end if;

    v_cost := v_product.price_coin;
    if v_vendor.payout_character_id is not distinct from v_character.id then
      v_cost := 0;
    end if;
    v_wallet := public.wallet_total_currency(v_character.id, v_product.currency_system_key);
    if v_wallet < v_cost then
      raise exception 'Not enough currency.';
    end if;

    v_slot := public.find_first_free_spell_slot(v_character.id, v_character.spell_slots);

    insert into public.character_spells (character_id, spell_id, is_active, slot_index)
    values (v_character.id, v_spell.id, v_slot is not null, v_slot);

    perform public.set_wallet_from_currency_value(v_character.id, v_product.currency_system_key, v_wallet - v_cost);
    perform public.credit_character_wallet_value(v_vendor.payout_character_id, v_product.currency_system_key, v_cost);
    perform public.ensure_dm_testing_wallet(v_character.id);

    if v_product.stock_quantity is not null then
      update public.market_products
      set stock_quantity = greatest(0, stock_quantity - 1),
          is_available = case
            when v_vendor.blueprint_type = 'stable' and greatest(0, stock_quantity - 1) <= 0 then false
            else is_available
          end
      where id = v_product.id;
    end if;

    return public.get_discovered_cities(p_session_token);
  end if;

  if v_vendor.vendor_key = 'calostrynn-library' and v_product.product_key = 'library-magical-research' then
    v_research_type := case lower(trim(coalesce(p_purchase_option, '')))
      when 'ember' then 'Ember'
      when 'frost' then 'Frost'
      when 'lightning' then 'Lightning'
      when 'earth' then 'Earth'
      when 'wind' then 'Wind'
      when 'energy' then 'Energy'
      when 'defensive support' then 'Defensive Support'
      when 'offensive support' then 'Offensive Support'
      when 'enhancement' then 'Enhancement'
      when 'enhancment' then 'Enhancement'
      when 'utility' then 'Utility'
      else null
    end;

    if v_research_type is null then
      raise exception 'Choose a spell category to research.';
    end if;

    v_item_name := v_research_type || ' Magic Spell Book';
    v_product.item_type := 'book';
    v_product.rarity := 'Rare'::public.item_rarity;
    v_quantity := 1;

    select * into v_catalog
    from public.item_catalog
    where item_key = public.catalog_key_for_name(v_item_name)
    limit 1;

    if v_catalog.id is not null then
      v_modifiers := v_catalog.default_modifiers;
      v_material := v_catalog.material;
      v_is_two_handed := v_catalog.is_two_handed;
      v_storage_capacity := v_catalog.storage_capacity;
    end if;
  end if;

  if v_product.product_kind = 'document' then
    if v_product.document_visibility = 'government' then
      raise exception 'Display books can be read in the library, not purchased.';
    end if;

    v_quantity := 1;
    if v_product.stock_quantity is not null and v_product.stock_quantity < 1 then
      raise exception 'That book is no longer on the shelf.';
    end if;

    v_cost := v_product.price_coin;
    if v_vendor.payout_character_id is not distinct from v_character.id then
      v_cost := 0;
    end if;
    v_wallet := public.wallet_total_currency(v_character.id, v_product.currency_system_key);
    if v_wallet < v_cost then
      raise exception 'Not enough currency.';
    end if;

    v_slot := public.find_first_free_inventory_slot(v_character.id, null, v_character.inventory_slots);
    if v_slot is null then
      raise exception 'Inventory full.';
    end if;

    insert into public.inventory_items (
      character_id,
      parent_item_id,
      slot_index,
      item_name,
      item_description,
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
      left(trim(concat_ws(E'\n\n', nullif(v_product.document_author, ''), coalesce(nullif(v_product.document_content, ''), (
        select string_agg(page.value #>> '{}', E'\n\n--- page ---\n\n')
        from jsonb_array_elements(coalesce(v_product.document_pages, '[]'::jsonb)) as page(value)
      )))), 12000),
      'book',
      v_product.rarity,
      1,
      false,
      0,
      '{}'::jsonb,
      null,
      '',
      0,
      false,
      null,
      null,
      null
    );

    perform public.set_wallet_from_currency_value(v_character.id, v_product.currency_system_key, v_wallet - v_cost);
    perform public.credit_character_wallet_value(v_vendor.payout_character_id, v_product.currency_system_key, v_cost);
    perform public.ensure_dm_testing_wallet(v_character.id);

    update public.market_products
    set stock_quantity = 0,
        is_available = false
    where id = v_product.id;

    return public.get_discovered_cities(p_session_token);
  end if;

  if public.normalize_item_type(v_product.item_type) = 'pet' then
    v_quantity := 1;
  end if;
  if public.normalize_item_type(v_product.item_type) = 'storage' then
    v_quantity := 1;
  end if;
  if v_product.product_kind = 'document' and length(trim(coalesce(v_product.document_content, ''))) > 0 then
    v_product.description := concat_ws(E'\n\n', nullif(trim(v_product.document_author), ''), v_product.document_content);
  end if;

  if v_product.stock_quantity is not null and v_quantity > v_product.stock_quantity then
    raise exception 'Not enough stock.';
  end if;

  v_cost := ceil((v_product.price_coin * v_quantity)::numeric)::int;
  if v_vendor.payout_character_id is not distinct from v_character.id then
    v_cost := 0;
  end if;
  v_wallet := public.wallet_total_currency(v_character.id, v_product.currency_system_key);
  if v_wallet < v_cost then
    raise exception 'Not enough currency.';
  end if;

  if public.normalize_item_type(v_product.item_type) = 'pet' then
    perform public.set_wallet_from_currency_value(v_character.id, v_product.currency_system_key, v_wallet - v_cost);
    perform public.credit_character_wallet_value(v_vendor.payout_character_id, v_product.currency_system_key, v_cost);
    perform public.ensure_dm_testing_wallet(v_character.id);
    perform public.place_pet_item_in_stable_for_character(
      v_character.id,
      v_item_name,
      null,
      coalesce(v_product.description, ''),
      v_product.rarity,
      1,
      false,
      v_modifiers,
      v_enchantment,
      v_rune_name,
      v_material,
      v_product.item_enhancement_count,
      v_is_two_handed
    );

    if v_product.stock_quantity is not null and v_stable_section_type <> 'rent' then
      update public.market_products
      set stock_quantity = greatest(0, stock_quantity - 1),
          is_available = case
            when v_vendor.blueprint_type = 'stable' and greatest(0, stock_quantity - 1) <= 0 then false
            else is_available
          end
      where id = v_product.id;
    end if;

    return public.get_discovered_cities(p_session_token);
  end if;

  v_inventory_quantity := v_quantity;

  if v_product.item_type = 'storage'::text or v_is_storage then
    v_storage_kind := public.additional_storage_kind(v_item_name, v_product.item_type);
    v_storage_active := v_storage_kind is null
      or not public.character_storage_container_exists(v_character.id, v_item_name);
    v_storage_slot := case
      when v_storage_active then public.next_storage_container_slot(v_character.id)
      else public.find_first_free_inventory_slot(v_character.id, null, v_character.inventory_slots)
    end;
    if v_storage_slot is null then
      raise exception 'Inventory full.';
    end if;

    insert into public.inventory_items (
      character_id,
      parent_item_id,
      slot_index,
      item_name,
      item_description,
      item_type,
      rarity,
      quantity,
      is_accessory,
      is_storage,
      storage_active,
      storage_capacity,
      modifiers,
      enchantment,
      rune_name,
      material,
      enhancement_count,
      is_two_handed,
      potion_strength,
      potion_property,
      potion_quality,
      spell_book_form
    )
    values (
      v_character.id,
      null,
      v_storage_slot,
      v_item_name,
      left(trim(coalesce(v_product.description, '')), 1500),
      v_product.item_type,
      v_product.rarity,
      1,
      v_is_accessory,
      true,
      v_storage_active,
      greatest(1, coalesce(nullif(v_storage_capacity, 0), public.catalog_storage_capacity(v_item_name))),
      v_modifiers,
      v_enchantment,
      v_rune_name,
      v_material,
      v_product.item_enhancement_count,
      v_is_two_handed,
      v_potion_strength,
      v_potion_property,
      v_potion_quality,
      v_spell_book_form
    )
    returning * into v_storage_item;

    v_inventory_quantity := v_inventory_quantity - 1;
  end if;

  if v_inventory_quantity > 0 then

  select * into v_target
  from public.inventory_items i
  where i.character_id = v_character.id
    and i.parent_item_id is null
    and i.loadout_slot is null
    and lower(public.normalize_item_name(i.item_name)) = lower(public.normalize_item_name(v_item_name))
    and public.normalize_item_type(i.item_type) = public.normalize_item_type(v_product.item_type)
    and i.rarity = v_product.rarity
    and coalesce(i.item_description, '') = left(trim(coalesce(v_product.description, '')), 1500)
    and coalesce(i.enchantment, '') = coalesce(v_enchantment, '')
    and coalesce(i.rune_name, '') = coalesce(v_rune_name, '')
    and coalesce(i.material, '') = coalesce(v_material, '')
    and coalesce(i.potion_strength, '') = coalesce(v_potion_strength, '')
    and coalesce(i.potion_property, '') = coalesce(v_potion_property, '')
    and coalesce(i.potion_quality, '') = coalesce(v_potion_quality, '')
    and i.enhancement_count = v_product.item_enhancement_count
    and i.is_two_handed = v_is_two_handed
    and i.is_accessory = v_is_accessory
    and i.spell_book_form = v_spell_book_form
    and i.modifiers = v_modifiers
    and i.is_storage = false
  order by i.slot_index
  limit 1;

  if v_target.id is not null then
    update public.inventory_items
    set quantity = quantity + v_inventory_quantity
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
      potion_quality,
      spell_book_form
    )
    values (
      v_character.id,
      null,
      v_slot,
      v_item_name,
      left(trim(coalesce(v_product.description, '')), 1500),
      v_product.item_type,
      v_product.rarity,
      v_inventory_quantity,
      v_is_accessory,
      false,
      0,
      v_modifiers,
      v_enchantment,
      v_rune_name,
      v_material,
      v_product.item_enhancement_count,
      v_is_two_handed,
      v_potion_strength,
      v_potion_property,
      v_potion_quality,
      v_spell_book_form
    )
    returning * into v_item;
  end if;

  end if;

  perform public.set_wallet_from_currency_value(v_character.id, v_product.currency_system_key, v_wallet - v_cost);
  perform public.credit_character_wallet_value(v_vendor.payout_character_id, v_product.currency_system_key, v_cost);
  perform public.ensure_dm_testing_wallet(v_character.id);

  if v_product.stock_quantity is not null and (v_vendor.blueprint_type <> 'stable' or v_stable_section_type <> 'rent') then
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
  v_product public.market_products%rowtype;
  v_vendor public.shop_vendors%rowtype;
  v_document_editor boolean := false;
  v_can_manage boolean := false;
  v_can_price_stable boolean := false;
  v_spell_type text;
  v_spell_key text;
  v_next_section text;
  v_section public.shop_sections%rowtype;
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

  select * into v_vendor
  from public.shop_vendors
  where id = v_product.vendor_id;

  v_document_editor := v_product.product_kind = 'document'
    and v_product.document_visibility = 'government'
    and v_product.document_editor_user_id = v_profile.id;
  v_can_manage := public.profile_can_manage_shop_vendor(v_profile, v_vendor);
  v_can_price_stable := public.profile_can_price_stable_vendor(v_profile, v_vendor);

  if not v_can_manage and not v_document_editor and not v_can_price_stable then
    raise exception 'You do not have permission to change this shop stock.';
  end if;

  if v_profile.role <> 'dm'::public.user_role
    and v_patch ? 'stockQuantity'
    and ((v_product.stock_quantity is null) <> (jsonb_typeof(v_patch->'stockQuantity') = 'null'))
  then
    raise exception 'Only the Dungeon Master can change infinite stock.';
  end if;

  if v_document_editor and not v_can_manage then
    v_patch := jsonb_strip_nulls(jsonb_build_object(
      'documentAuthor', v_patch->'documentAuthor',
      'documentContent', v_patch->'documentContent',
      'documentPages', v_patch->'documentPages'
    ));
  elsif v_can_price_stable and not v_can_manage then
    v_patch := jsonb_strip_nulls(jsonb_build_object(
      'priceCoin', v_patch->'priceCoin',
      'currencySystemKey', 'common'
    ));
  end if;

  if v_vendor.blueprint_type = 'stable' then
    v_next_section := case when v_patch ? 'section' then coalesce(nullif(trim(v_patch->>'section'), ''), 'Sale Stalls') else v_product.shop_section end;
    select * into v_section
    from public.shop_sections
    where vendor_id = v_product.vendor_id
      and section_name = v_next_section;

    if v_section.id is null then
      raise exception 'Create that stable section before moving animals into it.';
    end if;

    if v_section.id is not null
      and v_section.slot_count > 0
      and v_next_section <> v_product.shop_section
      and (
        select count(*)::int
        from public.market_products p
        where p.vendor_id = v_product.vendor_id
          and coalesce(nullif(trim(p.shop_section), ''), 'Wares') = v_next_section
      ) >= v_section.slot_count
    then
      raise exception 'That stable section has no open listing slots.';
    end if;

    v_patch := v_patch || jsonb_build_object(
      'kind', 'item',
      'type', 'pet',
      'quantityStep', 1
    );
  end if;

  update public.market_products
  set
    item_name = case when v_patch ? 'name' then coalesce(nullif(trim(v_patch->>'name'), ''), item_name) else item_name end,
    item_display_name = case when v_patch ? 'displayName' then nullif(left(trim(coalesce(v_patch->>'displayName', '')), 80), '') else item_display_name end,
    description = case when v_patch ? 'description' then coalesce(v_patch->>'description', '') else description end,
    item_type = case when v_patch ? 'type' then public.normalize_item_type(v_patch->>'type') else item_type end,
    rarity = case when v_patch ? 'rarity' then (v_patch->>'rarity')::public.item_rarity else rarity end,
    price_coin = case when v_patch ? 'priceCoin' then greatest(0, (v_patch->>'priceCoin')::int) else price_coin end,
    currency_system_key = case
      when v_vendor.city_key <> 'calostrynn' then 'common'
      when v_patch ? 'currencySystemKey' and v_patch->>'currencySystemKey' = 'common' then 'common'
      when v_patch ? 'currencySystemKey' then 'calostrynn'
      else currency_system_key
    end,
    stock_quantity = case
      when v_patch ? 'stockQuantity' and jsonb_typeof(v_patch->'stockQuantity') = 'null' then null
      when v_patch ? 'stockQuantity' then greatest(0, (v_patch->>'stockQuantity')::numeric)
      else stock_quantity
    end,
    catalog_item_key = case when v_patch ? 'catalogItemKey' then nullif(trim(coalesce(v_patch->>'catalogItemKey', '')), '') else catalog_item_key end,
    shop_section = case when v_patch ? 'section' then coalesce(nullif(trim(v_patch->>'section'), ''), 'Wares') else shop_section end,
    product_kind = case when v_patch ? 'kind' and v_patch->>'kind' in ('item', 'spell', 'document', 'service') then v_patch->>'kind' else product_kind end,
    mana_cost = case when v_patch ? 'manaCost' then greatest(0, (v_patch->>'manaCost')::int) else mana_cost end,
    mana_label = case
      when v_patch ? 'manaCost' then greatest(0, (v_patch->>'manaCost')::int)::text || ' mana'
      when v_patch ? 'manaLabel' then coalesce(nullif(trim(v_patch->>'manaLabel'), ''), mana_label)
      else mana_label
    end,
    document_author = case when v_patch ? 'documentAuthor' then left(trim(coalesce(v_patch->>'documentAuthor', '')), 160) else document_author end,
    document_content = case when v_patch ? 'documentContent' then left(coalesce(v_patch->>'documentContent', ''), 12000) else document_content end,
    document_pages = case
      when v_patch ? 'documentPages' and jsonb_typeof(v_patch->'documentPages') = 'array'
        then (
          select coalesce(jsonb_agg(left(page.value #>> '{}', 950)), '[]'::jsonb)
          from jsonb_array_elements(v_patch->'documentPages') as page(value)
        )
      else document_pages
    end,
    document_visibility = case
      when v_patch ? 'documentVisibility' and v_patch->>'documentVisibility' = 'government' then 'government'
      when v_patch ? 'documentVisibility' then 'for_sale'
      else document_visibility
    end,
    document_editor_user_id = case
      when v_patch ? 'documentEditorUserId' then nullif(v_patch->>'documentEditorUserId', '')::uuid
      else document_editor_user_id
    end,
    quantity_step = case
      when lower(coalesce(nullif(trim(v_patch->>'name'), ''), item_name)) in ('bronze scale', 'iron scale', 'steel scale', 'mythril scale', 'vaylium scale', 'dragonscale scale') then 1
      when v_patch ? 'quantityStep' and (v_patch->>'quantityStep')::numeric = 0.5 then 0.5
      when v_patch ? 'quantityStep' then 1
      else quantity_step
    end,
    is_available = case when v_patch ? 'available' then (v_patch->>'available')::boolean else is_available end
  where id = p_product_id
  returning * into v_product;

  if v_patch ? 'section' then
    insert into public.shop_sections (vendor_id, section_key, section_name, section_type, display_order)
    values (
      v_product.vendor_id,
      public.safe_slug(v_product.shop_section),
      v_product.shop_section,
      case when v_vendor.blueprint_type = 'stable' then v_section.section_type else 'standard' end,
      coalesce((select max(display_order) + 10 from public.shop_sections where vendor_id = v_product.vendor_id), 10)
    )
    on conflict (vendor_id, section_key) do update
    set section_name = excluded.section_name,
        section_type = excluded.section_type;
  end if;

  if v_product.product_kind = 'spell' then
    v_spell_type := case
      when regexp_replace(v_product.shop_section, '\s+Spells$', '', 'i') in ('Ember', 'Frost', 'Lightning', 'Earth', 'Wind', 'Energy', 'Defensive Support', 'Offensive Support', 'Enhancement', 'Utility') then regexp_replace(v_product.shop_section, '\s+Spells$', '', 'i')
      else 'Utility'
    end;
    v_spell_key := coalesce(nullif(v_product.catalog_item_key, ''), public.catalog_key_for_name(v_product.item_name));

    insert into public.spell_catalog (spell_key, name, school, spell_type, mana_cost, mana_label, summary, details, rarity, is_available, display_order, price_coin)
    values (
      v_spell_key,
      v_product.item_name,
      'arcane',
      v_spell_type,
      v_product.mana_cost,
      coalesce(nullif(v_product.mana_label, ''), v_product.mana_cost::text || ' mana'),
      v_product.description,
      v_product.description,
      v_product.rarity,
      v_product.is_available,
      coalesce((select max(display_order) + 10 from public.spell_catalog), 10),
      v_product.price_coin
    )
    on conflict (spell_key) do update
    set name = excluded.name,
        spell_type = excluded.spell_type,
        mana_cost = excluded.mana_cost,
        mana_label = excluded.mana_label,
        summary = excluded.summary,
        details = excluded.details,
        rarity = excluded.rarity,
        is_available = excluded.is_available,
        price_coin = excluded.price_coin;
  end if;

  return public.get_discovered_cities(p_session_token);
end;
$$;

create or replace function public.consume_character_item_by_name(
  p_character_id uuid,
  p_item_name text,
  p_quantity numeric
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_needed numeric := greatest(0.5, coalesce(p_quantity, 1));
  v_item public.inventory_items%rowtype;
  v_take numeric;
begin
  if v_needed <= 0 then
    return;
  end if;

  for v_item in
    select *
    from public.inventory_items
    where character_id = p_character_id
      and loadout_slot is null
      and is_storage = false
      and lower(item_name) = lower(trim(p_item_name))
    order by parent_item_id nulls first, slot_index, created_at
  loop
    exit when v_needed <= 0;
    v_take := least(v_item.quantity, v_needed);
    if v_take >= v_item.quantity then
      delete from public.inventory_items where id = v_item.id;
    else
      update public.inventory_items
      set quantity = quantity - v_take
      where id = v_item.id;
    end if;
    v_needed := v_needed - v_take;
  end loop;

  if v_needed > 0 then
    raise exception 'Missing required item: % x%.', p_item_name, p_quantity;
  end if;
end;
$$;

revoke execute on function public.consume_character_item_by_name(uuid, text, numeric) from anon, authenticated;

create or replace function public.assert_character_can_use_vendor(
  p_character public.characters,
  p_vendor_key text
)
returns public.cities
language plpgsql
security definer
set search_path = public
as $$
declare
  v_vendor public.shop_vendors%rowtype;
  v_city public.cities%rowtype;
begin
  select * into v_vendor
  from public.shop_vendors
  where vendor_key = p_vendor_key;

  if v_vendor.id is null then
    raise exception 'Crafting station not found.';
  end if;

  select * into v_city
  from public.cities
  where city_key = v_vendor.city_key;

  if v_city.id is null then
    raise exception 'Crafting city not found.';
  end if;

  if v_city.is_locked then
    raise exception '% is currently locked.', v_city.name;
  end if;

  if not public.character_is_in_city(p_character, v_city.city_key) then
    raise exception '% is in %, not %.', p_character.name, p_character.location_name, v_city.name;
  end if;

  return v_city;
end;
$$;

create or replace function public.crafting_house_is_accessible(
  p_character_id uuid,
  p_station_city_name text
)
returns boolean
language sql
stable
set search_path = public
as $$
  select exists (
    select 1
    from public.characters c
    join public.player_houses h on h.owner_user_id = c.owner_user_id
    where c.id = p_character_id
      and c.owner_user_id is not null
      and h.is_locked = false
      and public.city_names_match(h.city_name, c.location_name)
      and public.city_names_match(h.city_name, p_station_city_name)
    union all
    select 1
    from public.characters c
    join public.characters owner_character on owner_character.owner_user_id = c.owner_user_id
    join public.inventory_items mobile_home on mobile_home.character_id = owner_character.id
    where c.id = p_character_id
      and mobile_home.parent_item_id is null
      and mobile_home.loadout_slot is null
      and mobile_home.is_storage
      and public.inventory_item_is_mobile_home_storage(mobile_home.item_name, mobile_home.item_type)
      and public.city_names_match(owner_character.location_name, c.location_name)
      and public.city_names_match(owner_character.location_name, p_station_city_name)
  )
$$;

create or replace function public.house_item_quantity_by_name(
  p_character_id uuid,
  p_item_name text,
  p_station_city_name text
)
returns numeric
language sql
stable
set search_path = public
as $$
  select case
    when public.crafting_house_is_accessible(p_character_id, p_station_city_name) then coalesce((
      select sum(h.quantity)
      from public.characters c
      join public.house_inventory_items h on h.owner_user_id = c.owner_user_id
      join public.player_houses home on home.id = h.house_id
      where c.id = p_character_id
        and not home.is_locked
        and public.city_names_match(home.city_name, c.location_name)
        and public.city_names_match(home.city_name, p_station_city_name)
        and h.is_storage = false
        and lower(h.item_name) = lower(trim(p_item_name))
    ), 0) + coalesce((
      select sum(child.quantity)
      from public.characters c
      join public.characters owner_character
        on owner_character.owner_user_id = c.owner_user_id
      join public.inventory_items mobile_home
        on mobile_home.character_id = owner_character.id
      join public.inventory_items child
        on child.parent_item_id = mobile_home.id
      where c.id = p_character_id
        and public.city_names_match(owner_character.location_name, p_station_city_name)
        and mobile_home.parent_item_id is null
        and mobile_home.loadout_slot is null
        and mobile_home.is_storage = true
        and public.inventory_item_is_mobile_home_storage(mobile_home.item_name, mobile_home.item_type)
        and child.is_storage = false
        and child.loadout_slot is null
        and lower(child.item_name) = lower(trim(p_item_name))
    ), 0)
    else 0
  end
$$;

create or replace function public.carried_item_quantity_by_name(
  p_character_id uuid,
  p_item_name text
)
returns numeric
language sql
stable
as $$
  select coalesce(sum(i.quantity), 0)
  from public.inventory_items i
  where i.character_id = p_character_id
    and i.loadout_slot is null
    and i.is_storage = false
    and lower(i.item_name) = lower(trim(p_item_name))
    and (
      i.parent_item_id is null
      or exists (
        select 1
        from public.inventory_items storage
        where storage.id = i.parent_item_id
          and storage.character_id = p_character_id
          and storage.is_storage = true
      )
    )
$$;


create or replace function public.accessible_item_quantity_by_name(
  p_character_id uuid,
  p_item_name text,
  p_station_city_name text
)
returns numeric
language sql
stable
set search_path = public
as $$
  select public.carried_item_quantity_by_name(p_character_id, p_item_name)
       + public.house_item_quantity_by_name(p_character_id, p_item_name, p_station_city_name)
$$;

create or replace function public.consume_house_item_by_name(
  p_character_id uuid,
  p_item_name text,
  p_quantity numeric,
  p_station_city_name text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_needed numeric := greatest(0.5, coalesce(p_quantity, 1));
  v_item public.house_inventory_items%rowtype;
  v_mobile_item public.inventory_items%rowtype;
  v_take numeric;
begin
  if v_needed <= 0 then return; end if;
  if not public.crafting_house_is_accessible(p_character_id, p_station_city_name) then
    raise exception 'House storage is not accessible from here.';
  end if;

  for v_item in
    select h.*
    from public.characters c
    join public.house_inventory_items h on h.owner_user_id = c.owner_user_id
    join public.player_houses home on home.id = h.house_id
    where c.id = p_character_id
      and not home.is_locked
      and public.city_names_match(home.city_name, c.location_name)
      and public.city_names_match(home.city_name, p_station_city_name)
      and h.is_storage = false
      and lower(h.item_name) = lower(trim(p_item_name))
    order by h.slot_index, h.created_at
  loop
    exit when v_needed <= 0;
    v_take := least(v_item.quantity, v_needed);
    if v_take >= v_item.quantity then
      delete from public.house_inventory_items where id = v_item.id;
    else
      update public.house_inventory_items set quantity = quantity - v_take where id = v_item.id;
    end if;
    v_needed := v_needed - v_take;
  end loop;

  for v_mobile_item in
    select child.*
    from public.characters c
    join public.characters owner_character
      on owner_character.owner_user_id = c.owner_user_id
    join public.inventory_items mobile_home
      on mobile_home.character_id = owner_character.id
    join public.inventory_items child
      on child.parent_item_id = mobile_home.id
    where c.id = p_character_id
      and public.city_names_match(owner_character.location_name, p_station_city_name)
      and mobile_home.parent_item_id is null
      and mobile_home.loadout_slot is null
      and mobile_home.is_storage = true
      and public.inventory_item_is_mobile_home_storage(mobile_home.item_name, mobile_home.item_type)
      and child.is_storage = false
      and child.loadout_slot is null
      and lower(child.item_name) = lower(trim(p_item_name))
    order by owner_character.name, mobile_home.slot_index, child.slot_index, child.created_at
  loop
    exit when v_needed <= 0;
    v_take := least(v_mobile_item.quantity, v_needed);
    if v_take >= v_mobile_item.quantity then
      delete from public.inventory_items where id = v_mobile_item.id;
    else
      update public.inventory_items set quantity = quantity - v_take where id = v_mobile_item.id;
    end if;
    v_needed := v_needed - v_take;
  end loop;

  if v_needed > 0 then
    raise exception 'Missing house item: % x%.', p_item_name, p_quantity;
  end if;
end;
$$;

create or replace function public.consume_crafting_item_by_name(
  p_character_id uuid,
  p_item_name text,
  p_quantity numeric,
  p_station_city_name text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_needed numeric := greatest(0.5, coalesce(p_quantity, 1));
  v_from_carried numeric;
  v_from_house numeric;
begin
  if v_needed <= 0 then return; end if;

  v_from_carried := least(v_needed, public.carried_item_quantity_by_name(p_character_id, p_item_name));
  if v_from_carried > 0 then
    perform public.consume_character_item_by_name(p_character_id, p_item_name, v_from_carried);
    v_needed := v_needed - v_from_carried;
  end if;

  v_from_house := least(v_needed, public.house_item_quantity_by_name(p_character_id, p_item_name, p_station_city_name));
  if v_from_house > 0 then
    perform public.consume_house_item_by_name(p_character_id, p_item_name, v_from_house, p_station_city_name);
    v_needed := v_needed - v_from_house;
  end if;

  if v_needed > 0 then
    raise exception 'Missing required item: % x%.', p_item_name, p_quantity;
  end if;
end;
$$;

create or replace function public.forge_material_modifiers(
  p_material text,
  p_item_type text
)
returns jsonb
language sql
immutable
as $$
  select case lower(trim(coalesce(p_material, '')))
    when 'bronze' then case when p_item_type = 'weapon' then jsonb_build_object('strength', -1) when p_item_type = 'shield' then jsonb_build_object('vitality', 1) else '{}'::jsonb end
    when 'iron' then case when p_item_type = 'shield' then jsonb_build_object('vitality', 1) when p_item_type = 'armor' then jsonb_build_object('agility', -1) else '{}'::jsonb end
    when 'steel' then case when p_item_type = 'weapon' then jsonb_build_object('strength', 1) when p_item_type in ('shield', 'armor') then jsonb_build_object('vitality', 1) else '{}'::jsonb end
    when 'mythril' then case when p_item_type = 'shield' then jsonb_build_object('vitality', 1) else '{}'::jsonb end
    when 'vaylium' then case when p_item_type = 'weapon' then jsonb_build_object('intelligence', 1) when p_item_type = 'shield' then jsonb_build_object('vitality', 1, 'intelligence', 1) when p_item_type = 'armor' then jsonb_build_object('intelligence', 3, 'magic_resist', 1) else jsonb_build_object('intelligence', 1) end
    when 'dragonscale' then case when p_item_type = 'weapon' then jsonb_build_object('strength', 2, 'magic_resist', 3) when p_item_type = 'shield' then jsonb_build_object('vitality', 2, 'magic_resist', 3) when p_item_type = 'armor' then jsonb_build_object('vitality', 2, 'magic_resist', 5) else jsonb_build_object('magic_resist', 3) end
    when 'leather' then case when p_item_type = 'armor' then jsonb_build_object('vitality', -1) else '{}'::jsonb end
    else '{}'::jsonb
  end
$$;

create table if not exists public.material_conversion_recipes (
  recipe_key text primary key,
  item_name text not null,
  item_type text not null default 'misc',
  rarity public.item_rarity not null default 'Common',
  material text not null,
  scale_item_name text not null,
  scale_quantity numeric(12,1) not null check (scale_quantity > 0),
  is_active boolean not null default true,
  display_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.material_conversion_recipes enable row level security;
revoke all on public.material_conversion_recipes from anon, authenticated;

drop trigger if exists material_conversion_recipes_touch_updated_at on public.material_conversion_recipes;
create trigger material_conversion_recipes_touch_updated_at
before update on public.material_conversion_recipes
for each row execute function public.touch_updated_at();

create table if not exists public.dragon_scale_fragment_catalog (
  item_key text primary key,
  item_name text not null,
  item_type text not null default 'misc',
  rarity public.item_rarity not null default 'Legendary',
  is_active boolean not null default true,
  display_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.dragon_scale_fragment_catalog enable row level security;
revoke all on public.dragon_scale_fragment_catalog from anon, authenticated;

drop trigger if exists dragon_scale_fragment_catalog_touch_updated_at on public.dragon_scale_fragment_catalog;
create trigger dragon_scale_fragment_catalog_touch_updated_at
before update on public.dragon_scale_fragment_catalog
for each row execute function public.touch_updated_at();

create or replace function public.upsert_dragon_scale_fragment(
  p_item_name text,
  p_item_type text,
  p_rarity text,
  p_display_order int default 0
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item_name text := public.normalize_item_name(p_item_name);
  v_type text := public.normalize_item_type(p_item_type);
  v_rarity public.item_rarity := coalesce(nullif(p_rarity, ''), 'Legendary')::public.item_rarity;
begin
  if length(trim(coalesce(v_item_name, ''))) = 0 then
    raise exception 'Dragon scale fragment name is required.';
  end if;

  perform public.upsert_item_catalog_entry(
    v_item_name,
    v_type,
    v_rarity::text,
    'Dragon Scales',
    array['Dragon scale fragment']::text[],
    1,
    true,
    '{}'::jsonb,
    'Dragon',
    false,
    0,
    'Raw dragon scale fragments. Twenty-five compatible fragments can be forged into one Dragonscale Scale.',
    true,
    p_display_order
  );

  insert into public.dragon_scale_fragment_catalog (
    item_key,
    item_name,
    item_type,
    rarity,
    is_active,
    display_order
  )
  values (
    public.catalog_key_for_name(v_item_name),
    v_item_name,
    v_type,
    v_rarity,
    true,
    coalesce(p_display_order, 0)
  )
  on conflict (item_key) do update
  set item_name = excluded.item_name,
      item_type = excluded.item_type,
      rarity = excluded.rarity,
      is_active = true,
      display_order = excluded.display_order,
      updated_at = now();
end;
$$;

create or replace function public.upsert_material_conversion_recipe(
  p_recipe_key text,
  p_item_name text,
  p_item_type text,
  p_rarity text,
  p_material text,
  p_scale_item_name text,
  p_scale_quantity numeric,
  p_display_order int default 0
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if length(trim(coalesce(p_recipe_key, ''))) = 0
    or length(trim(coalesce(p_item_name, ''))) = 0
    or length(trim(coalesce(p_material, ''))) = 0
    or length(trim(coalesce(p_scale_item_name, ''))) = 0
    or coalesce(p_scale_quantity, 0) <= 0 then
    raise exception 'Material conversion recipe is incomplete.';
  end if;

  insert into public.material_conversion_recipes (
    recipe_key,
    item_name,
    item_type,
    rarity,
    material,
    scale_item_name,
    scale_quantity,
    is_active,
    display_order
  )
  values (
    public.catalog_key_for_name(p_recipe_key),
    public.normalize_item_name(p_item_name),
    public.normalize_item_type(p_item_type),
    coalesce(nullif(p_rarity, ''), 'Common')::public.item_rarity,
    trim(p_material),
    public.normalize_item_name(p_scale_item_name),
    public.assert_valid_item_quantity(p_scale_item_name, 'material', p_scale_quantity),
    true,
    coalesce(p_display_order, 0)
  )
  on conflict (recipe_key) do update
  set item_name = excluded.item_name,
      item_type = excluded.item_type,
      rarity = excluded.rarity,
      material = excluded.material,
      scale_item_name = excluded.scale_item_name,
      scale_quantity = excluded.scale_quantity,
      is_active = true,
      display_order = excluded.display_order,
      updated_at = now();
end;
$$;

create or replace function public.material_conversion_recipe_to_json(p_recipe public.material_conversion_recipes)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'key', p_recipe.recipe_key,
    'itemName', p_recipe.item_name,
    'itemType', p_recipe.item_type,
    'rarity', p_recipe.rarity,
    'material', p_recipe.material,
    'scaleItemName', p_recipe.scale_item_name,
    'scaleQuantity', p_recipe.scale_quantity,
    'active', p_recipe.is_active,
    'order', p_recipe.display_order
  )
$$;

create or replace function public.material_conversion_recipe_matches_item(
  p_recipe public.material_conversion_recipes,
  p_item public.inventory_items
)
returns boolean
language sql
stable
as $$
  select p_recipe.is_active
    and (
      lower(public.normalize_item_name(p_recipe.item_name)) = lower(public.normalize_item_name(p_item.item_name))
      or lower(public.normalize_item_name(p_recipe.item_name)) = lower(public.normalize_item_name(concat_ws(' ', nullif(p_item.material, ''), p_item.item_name)))
    )
    and public.normalize_item_type(p_recipe.item_type) = public.normalize_item_type(p_item.item_type)
    and lower(coalesce(nullif(p_item.material, ''), p_recipe.material, '')) = lower(p_recipe.material)
$$;

create or replace function public.material_conversion_two_handed(p_item_name text, p_item_type text)
returns boolean
language sql
immutable
as $$
  select public.normalize_item_type(p_item_type) = 'weapon'
    and lower(public.normalize_item_name(p_item_name)) ~ '(battleaxe|mace|claymore|crossbow)'
$$;

do $$
begin
  perform public.upsert_item_catalog_entry('Steel Scale', 'material', 'Uncommon', 'Material Scales', array['Forge scale']::text[], 0.5, true, '{}'::jsonb, 'Steel', false, 0, 'A half-step compatible steel material scale.', true, 3000);
  perform public.upsert_item_catalog_entry('Mythril Scale', 'material', 'Rare', 'Material Scales', array['Forge scale']::text[], 0.5, true, '{}'::jsonb, 'Mythril', false, 0, 'A half-step compatible mythril material scale.', true, 3010);
  perform public.upsert_item_catalog_entry('Vaylium Scale', 'material', 'Epic', 'Material Scales', array['Forge scale']::text[], 0.5, true, '{}'::jsonb, 'Vaylium', false, 0, 'A half-step compatible vaylium material scale.', true, 3020);
  perform public.upsert_item_catalog_entry('Dragonscale Scale', 'material', 'Legendary', 'Material Scales', array['Forge scale']::text[], 0.5, true, '{}'::jsonb, 'Dragonscale', false, 0, 'A refined Dragonscale unit forged from dragon scale fragments.', true, 3030);
  perform public.upsert_dragon_scale_fragment('Young Dragons Scales', 'misc', 'Legendary', 3040);
  perform public.upsert_dragon_scale_fragment('Ember Dragons Scales', 'misc', 'Legendary', 3050);
  perform public.upsert_dragon_scale_fragment('Frost Dragons Scales', 'misc', 'Legendary', 3060);
  perform public.upsert_dragon_scale_fragment('Storm Dragons Scales', 'misc', 'Legendary', 3070);
  perform public.upsert_dragon_scale_fragment('Mountian Dragons Scales', 'misc', 'Legendary', 3080);
  perform public.upsert_dragon_scale_fragment('Elder Dragons Scales', 'misc', 'Mythical', 3090);
  perform public.upsert_dragon_scale_fragment('Void Dragon Scales', 'misc', 'Mythical', 3100);
  perform public.upsert_dragon_scale_fragment('Young Dragon Scales', 'misc', 'Legendary', 3110);
  perform public.upsert_dragon_scale_fragment('Ember Dragon Scales', 'misc', 'Legendary', 3120);
  perform public.upsert_dragon_scale_fragment('Frost Dragon Scales', 'misc', 'Legendary', 3130);
  perform public.upsert_dragon_scale_fragment('Storm Dragon Scales', 'misc', 'Legendary', 3140);
  perform public.upsert_dragon_scale_fragment('Mountain Dragon Scales', 'misc', 'Legendary', 3150);
  perform public.upsert_dragon_scale_fragment('Elder Dragon Scales', 'misc', 'Mythical', 3160);

  perform public.upsert_material_conversion_recipe('steel-shovel', 'Steel Shovel', 'tool', 'Uncommon', 'Steel', 'Steel Scale', 1, 10);
  perform public.upsert_material_conversion_recipe('steel-pickaxe', 'Steel Pickaxe', 'tool', 'Uncommon', 'Steel', 'Steel Scale', 1, 20);
  perform public.upsert_material_conversion_recipe('steel-sword', 'Steel Sword', 'weapon', 'Uncommon', 'Steel', 'Steel Scale', 1, 30);
  perform public.upsert_material_conversion_recipe('steel-axe', 'Steel Axe', 'tool', 'Uncommon', 'Steel', 'Steel Scale', 1, 40);
  perform public.upsert_material_conversion_recipe('steel-battleaxe', 'Steel Battleaxe', 'weapon', 'Uncommon', 'Steel', 'Steel Scale', 2, 50);
  perform public.upsert_material_conversion_recipe('steel-mace', 'Steel Mace', 'weapon', 'Uncommon', 'Steel', 'Steel Scale', 2, 60);
  perform public.upsert_material_conversion_recipe('steel-shield', 'Steel Shield', 'shield', 'Rare', 'Steel', 'Steel Scale', 1, 70);
  perform public.upsert_material_conversion_recipe('mythril-pickaxe', 'Mythril Pickaxe', 'tool', 'Rare', 'Mythril', 'Mythril Scale', 1, 80);
  perform public.upsert_material_conversion_recipe('mythril-sword', 'Mythril Sword', 'weapon', 'Rare', 'Mythril', 'Mythril Scale', 1, 90);
  perform public.upsert_material_conversion_recipe('mythril-dagger', 'Mythril Dagger', 'weapon', 'Rare', 'Mythril', 'Mythril Scale', 0.5, 100);
  perform public.upsert_material_conversion_recipe('mythril-axe', 'Mythril Axe', 'tool', 'Rare', 'Mythril', 'Mythril Scale', 1, 110);
  perform public.upsert_material_conversion_recipe('mythril-battleaxe', 'Mythril Battleaxe', 'weapon', 'Rare', 'Mythril', 'Mythril Scale', 2, 120);
  perform public.upsert_material_conversion_recipe('mythril-mace', 'Mythril Mace', 'weapon', 'Rare', 'Mythril', 'Mythril Scale', 2, 130);
  perform public.upsert_material_conversion_recipe('vaylium-battleaxe', 'Vaylium Battleaxe', 'weapon', 'Epic', 'Vaylium', 'Vaylium Scale', 2, 140);
  perform public.upsert_material_conversion_recipe('vaylium-mace', 'Vaylium Mace', 'weapon', 'Epic', 'Vaylium', 'Vaylium Scale', 2, 150);
  perform public.upsert_material_conversion_recipe('vaylium-pickaxe', 'Vaylium Pickaxe', 'tool', 'Epic', 'Vaylium', 'Vaylium Scale', 1, 160);
  perform public.upsert_material_conversion_recipe('vaylium-sword', 'Vaylium Sword', 'weapon', 'Epic', 'Vaylium', 'Vaylium Scale', 1, 170);
  perform public.upsert_material_conversion_recipe('vaylium-dagger', 'Vaylium Dagger', 'weapon', 'Epic', 'Vaylium', 'Vaylium Scale', 0.5, 180);
  perform public.upsert_material_conversion_recipe('vaylium-axe', 'Vaylium Axe', 'tool', 'Epic', 'Vaylium', 'Vaylium Scale', 1, 190);
  perform public.upsert_material_conversion_recipe('dragonscale-sword', 'Dragonscale Sword', 'weapon', 'Legendary', 'Dragonscale', 'Dragonscale Scale', 1, 200);
  perform public.upsert_material_conversion_recipe('dragonscale-dagger', 'Dragonscale Dagger', 'weapon', 'Legendary', 'Dragonscale', 'Dragonscale Scale', 0.5, 210);
  perform public.upsert_material_conversion_recipe('dragonscale-pickaxe', 'Dragonscale Pickaxe', 'tool', 'Legendary', 'Dragonscale', 'Dragonscale Scale', 1, 220);
  perform public.upsert_material_conversion_recipe('dragonscale-axe', 'Dragonscale Axe', 'tool', 'Legendary', 'Dragonscale', 'Dragonscale Scale', 1, 230);
  perform public.upsert_material_conversion_recipe('dragonscale-shield', 'Dragonscale Shield', 'shield', 'Legendary', 'Dragonscale', 'Dragonscale Scale', 1, 240);
  perform public.upsert_material_conversion_recipe('dragonscale-battleaxe', 'Dragonscale Battleaxe', 'weapon', 'Legendary', 'Dragonscale', 'Dragonscale Scale', 2, 250);
  perform public.upsert_material_conversion_recipe('dragonscale-mace', 'Dragonscale Mace', 'weapon', 'Legendary', 'Dragonscale', 'Dragonscale Scale', 2, 260);
  perform public.upsert_material_conversion_recipe('steel-dagger', 'Steel Dagger', 'weapon', 'Uncommon', 'Steel', 'Steel Scale', 0.5, 270);
  perform public.upsert_material_conversion_recipe('steel-armor', 'Steel Armor', 'armor', 'Rare', 'Steel', 'Steel Scale', 3, 280);
  perform public.upsert_material_conversion_recipe('mythril-armor', 'Mythril Armor', 'armor', 'Rare', 'Mythril', 'Mythril Scale', 3, 290);
  perform public.upsert_material_conversion_recipe('vaylium-armor', 'Vaylium Armor', 'armor', 'Epic', 'Vaylium', 'Vaylium Scale', 3, 300);
  perform public.upsert_material_conversion_recipe('dragonscale-armor', 'Dragonscale Armor', 'armor', 'Legendary', 'Dragonscale', 'Dragonscale Scale', 3, 310);
end;
$$;

drop function if exists public.blacksmith_material_modifiers(text, text);


create or replace function public.add_forge_material_leftover(
  p_character_id uuid,
  p_product public.market_products,
  p_quantity numeric,
  p_inventory_slots int
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_slot int;
  v_target public.inventory_items%rowtype;
begin
  if coalesce(p_quantity, 0) <= 0 then
    return;
  end if;

  select * into v_target
  from public.inventory_items
  where character_id = p_character_id
    and loadout_slot is null
    and is_storage = false
    and lower(item_name) = lower(p_product.item_name)
    and item_type = 'material'
  order by parent_item_id nulls first, slot_index, created_at
  limit 1;

  if v_target.id is not null then
    update public.inventory_items
    set quantity = quantity + p_quantity
    where id = v_target.id;
    return;
  end if;

  v_slot := public.find_first_free_inventory_slot(p_character_id, null, p_inventory_slots);
  if v_slot is null then
    raise exception 'Inventory full for leftover material.';
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
    enchantment,
    material,
    enhancement_count,
    is_two_handed,
    potion_strength,
    potion_property,
    potion_quality
  )
  values (
    p_character_id,
    null,
    v_slot,
    p_product.item_name,
    'material',
    p_product.rarity,
    p_quantity,
    false,
    0,
    '{}'::jsonb,
    null,
    regexp_replace(p_product.item_name, '[[:space:]]+Scale$', '', 'i'),
    0,
    false,
    null,
    null,
    null
  );
end;
$$;

create or replace function public.update_player_house(
  p_session_token text,
  p_owner_user_id uuid,
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
  v_house public.player_houses%rowtype;
  v_home record;
  v_caged record;
  v_has_house boolean := false;
  v_has_home boolean := false;
  v_has_caged boolean := false;
  v_name text;
  v_stable_name text;
  v_city_name text;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;

  if v_profile.role <> 'dm'::public.user_role and p_owner_user_id is distinct from v_profile.id then
    raise exception 'Only the home owner or Dungeon Master can change these settings.';
  end if;

  select * into v_house
  from public.player_houses
  where owner_user_id = p_owner_user_id;
  v_has_house := found;

  select * into v_home
  from public.home_wagon_storage_for_owner(p_owner_user_id);
  v_has_home := found;

  select * into v_caged
  from public.caged_wagon_storage_for_owner(p_owner_user_id);
  v_has_caged := found;

  v_name := nullif(trim(coalesce(v_patch->>'name', '')), '');
  v_stable_name := nullif(trim(coalesce(v_patch->>'stableName', '')), '');
  if v_profile.role = 'dm'::public.user_role and v_patch ? 'cityName' then
    v_city_name := public.assert_valid_character_location(v_patch->>'cityName');
  end if;

  if not v_has_house and not v_has_home and not v_has_caged then
    if v_profile.role <> 'dm'::public.user_role then
      raise exception 'Only the Dungeon Master can create a home.';
    end if;

    insert into public.player_houses (
      owner_user_id,
      house_name,
      stable_name,
      city_name,
      inventory_slots,
      stable_slots,
      property_slots,
      is_locked
    )
    values (
      p_owner_user_id,
      coalesce(v_name, 'House'),
      coalesce(v_stable_name, 'Stable'),
      coalesce(v_city_name, 'Wild'),
      case when v_patch ? 'inventorySlots' then greatest(0, least(500, (v_patch->>'inventorySlots')::int)) else 45 end,
      case when v_patch ? 'stableSlots' then greatest(0, least(200, (v_patch->>'stableSlots')::int)) else 5 end,
      case when v_patch ? 'propertySlots' then greatest(0, least(200, (v_patch->>'propertySlots')::int)) else 10 end,
      case when v_patch ? 'locked' then (v_patch->>'locked')::boolean else false end
    )
    returning * into v_house;

    v_has_house := true;
  end if;

  if v_has_home and v_name is not null then
    update public.inventory_items
    set display_name = v_name,
        storage_capacity = case
          when v_profile.role = 'dm'::public.user_role and v_patch ? 'inventorySlots'
            then greatest(0, least(500, (v_patch->>'inventorySlots')::int))
          else storage_capacity
        end
    where id = (v_home.storage).id;
  elsif v_has_home and v_profile.role = 'dm'::public.user_role and v_patch ? 'inventorySlots' then
    update public.inventory_items
    set storage_capacity = greatest(0, least(500, (v_patch->>'inventorySlots')::int))
    where id = (v_home.storage).id;
  end if;

  if v_has_caged and v_stable_name is not null then
    update public.inventory_items
    set display_name = v_stable_name,
        storage_capacity = case
          when v_profile.role = 'dm'::public.user_role and v_patch ? 'stableSlots'
            then greatest(0, least(200, (v_patch->>'stableSlots')::int))
          else storage_capacity
        end
    where id = (v_caged.storage).id;
  elsif v_has_caged and v_profile.role = 'dm'::public.user_role and v_patch ? 'stableSlots' then
    update public.inventory_items
    set storage_capacity = greatest(0, least(200, (v_patch->>'stableSlots')::int))
    where id = (v_caged.storage).id;
  end if;

  if v_city_name is not null and v_has_home then
    update public.characters
    set location_name = v_city_name
    where id = (v_home.owner_character).id;
  end if;

  if v_city_name is not null and v_has_caged then
    update public.characters
    set location_name = v_city_name
    where id = (v_caged.owner_character).id;
  end if;

  if v_has_house then
    update public.player_houses
    set house_name = case when v_name is not null then v_name else house_name end,
        stable_name = case when v_stable_name is not null then v_stable_name else stable_name end,
        city_name = case
          when v_city_name is not null
            then v_city_name
          else city_name
        end,
        inventory_slots = case
          when v_profile.role = 'dm'::public.user_role and v_patch ? 'inventorySlots'
            then greatest(0, least(500, (v_patch->>'inventorySlots')::int))
          else inventory_slots
        end,
        stable_slots = case
          when v_profile.role = 'dm'::public.user_role and v_patch ? 'stableSlots'
            then greatest(0, least(200, (v_patch->>'stableSlots')::int))
          else stable_slots
        end,
        property_slots = case
          when v_profile.role = 'dm'::public.user_role and v_patch ? 'propertySlots'
            then greatest(0, least(200, (v_patch->>'propertySlots')::int))
          else property_slots
        end,
        is_locked = case
          when v_profile.role = 'dm'::public.user_role and v_patch ? 'locked'
            then (v_patch->>'locked')::boolean
          else is_locked
        end
    where owner_user_id = p_owner_user_id
    returning * into v_house;
  end if;


  return public.get_player_house(p_session_token, p_owner_user_id);
end;
$$;

create or replace function public.delete_player_house(
  p_session_token text,
  p_owner_user_id uuid
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

  if v_profile.role <> 'dm'::public.user_role then
    raise exception 'Only the Dungeon Master can delete houses.';
  end if;

  delete from public.house_inventory_items
  where owner_user_id = p_owner_user_id;

  delete from public.campaign_properties
  where owner_user_id = p_owner_user_id;

  delete from public.house_access_permissions
  where owner_user_id = p_owner_user_id;

  delete from public.player_houses
  where owner_user_id = p_owner_user_id;

  return public.get_player_house(p_session_token, p_owner_user_id);
end;
$$;

create or replace function public.set_player_house_permissions(
  p_session_token text,
  p_owner_user_id uuid,
  p_permissions jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_entry jsonb;
  v_grantee_user_id uuid;
  v_house boolean;
  v_stable boolean;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;

  if v_profile.role <> 'dm'::public.user_role and p_owner_user_id is distinct from v_profile.id then
    raise exception 'Only the house owner or Dungeon Master can change house permissions.';
  end if;

  delete from public.house_access_permissions
  where owner_user_id = p_owner_user_id;

  for v_entry in select * from jsonb_array_elements(coalesce(p_permissions, '[]'::jsonb)) loop
    v_grantee_user_id := nullif(coalesce(v_entry->>'granteeUserId', v_entry->>'grantee_user_id', ''), '')::uuid;
    v_house := coalesce((v_entry->>'house')::boolean, false);
    v_stable := coalesce((v_entry->>'stable')::boolean, false);

    if v_grantee_user_id is null or v_grantee_user_id = p_owner_user_id or not (v_house or v_stable) then
      continue;
    end if;

    if not exists (select 1 from public.profiles where id = v_grantee_user_id) then
      raise exception 'A selected player account does not exist.';
    end if;

    insert into public.house_access_permissions (owner_user_id, grantee_user_id, can_access_house, can_access_stable)
    values (p_owner_user_id, v_grantee_user_id, v_house, v_stable)
    on conflict (owner_user_id, grantee_user_id) do update
    set can_access_house = excluded.can_access_house,
        can_access_stable = excluded.can_access_stable;
  end loop;

  return public.get_player_house(p_session_token, p_owner_user_id);
end;
$$;

create or replace function public.assert_mobile_storage_permission_owner(
  p_profile public.profiles,
  p_storage_item_id uuid
)
returns table(storage public.inventory_items, owner_character public.characters)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_storage public.inventory_items%rowtype;
  v_owner_character public.characters%rowtype;
begin
  select * into v_storage
  from public.inventory_items
  where id = p_storage_item_id;

  if v_storage.id is null
    or not coalesce(v_storage.is_storage, false)
    or v_storage.parent_item_id is not null
    or v_storage.loadout_slot is not null
    or not (
      public.inventory_item_is_mobile_home_storage(v_storage.item_name, v_storage.item_type)
      or public.inventory_item_is_caged_wagon_storage(v_storage.item_name, v_storage.item_type)
    )
  then
    raise exception 'Permissioned mobile storage was not found.';
  end if;

  select * into v_owner_character
  from public.characters
  where id = v_storage.character_id;

  if v_owner_character.id is null or v_owner_character.owner_user_id is null then
    raise exception 'Permissioned mobile storage must be owned by an assigned character.';
  end if;

  if p_profile.role <> 'dm'::public.user_role and v_owner_character.owner_user_id is distinct from p_profile.id then
    raise exception 'Only the storage owner or Dungeon Master can change these permissions.';
  end if;

  storage := v_storage;
  owner_character := v_owner_character;
  return next;
end;
$$;

create or replace function public.get_mobile_storage_permissions(
  p_session_token text,
  p_storage_item_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_record record;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;

  select * into v_record
  from public.assert_mobile_storage_permission_owner(v_profile, p_storage_item_id);

  return jsonb_build_object(
    'storageItemId', (v_record.storage).id,
    'ownerUserId', (v_record.owner_character).owner_user_id,
    'storageLabel', case
      when public.inventory_item_is_mobile_home_storage((v_record.storage).item_name, (v_record.storage).item_type) then 'Wagon Home'
      else 'Caged Wagon'
    end,
    'permissions', public.mobile_storage_permissions_to_json(p_storage_item_id)
  );
end;
$$;

create or replace function public.set_mobile_storage_permissions(
  p_session_token text,
  p_storage_item_id uuid,
  p_permissions jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_record record;
  v_entry jsonb;
  v_grantee_user_id uuid;
  v_access boolean;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;

  select * into v_record
  from public.assert_mobile_storage_permission_owner(v_profile, p_storage_item_id);

  delete from public.mobile_storage_access_permissions
  where storage_item_id = p_storage_item_id;

  for v_entry in select * from jsonb_array_elements(coalesce(p_permissions, '[]'::jsonb)) loop
    v_grantee_user_id := nullif(coalesce(v_entry->>'granteeUserId', v_entry->>'grantee_user_id', ''), '')::uuid;
    v_access := coalesce((v_entry->>'access')::boolean, false);

    if v_grantee_user_id is null
      or v_grantee_user_id = (v_record.owner_character).owner_user_id
      or not v_access
    then
      continue;
    end if;

    if not exists (select 1 from public.profiles where id = v_grantee_user_id) then
      raise exception 'A selected player account does not exist.';
    end if;

    insert into public.mobile_storage_access_permissions (storage_item_id, owner_user_id, grantee_user_id)
    values (p_storage_item_id, (v_record.owner_character).owner_user_id, v_grantee_user_id)
    on conflict (storage_item_id, grantee_user_id) do update
    set owner_user_id = excluded.owner_user_id;
  end loop;

  return public.get_mobile_storage_permissions(p_session_token, p_storage_item_id);
end;
$$;

grant execute on function public.assert_mobile_storage_permission_owner(public.profiles, uuid) to anon, authenticated;
grant execute on function public.get_mobile_storage_permissions(text, uuid) to anon, authenticated;
grant execute on function public.set_mobile_storage_permissions(text, uuid, jsonb) to anon, authenticated;

drop function if exists public.consume_forge_materials(uuid, uuid, numeric, int);
drop function if exists public.consume_forge_materials(uuid, uuid, numeric, int, text);
drop function if exists public.consume_forge_materials(uuid, uuid, numeric, int, text, text);

create or replace function public.consume_forge_materials(
  p_character_id uuid,
  p_material_product_id uuid,
  p_required_quantity numeric,
  p_inventory_slots int,
  p_station_city_name text,
  p_expected_material_name text default null
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_product public.market_products%rowtype;
  v_required numeric := greatest(0, coalesce(p_required_quantity, 0));
  v_accessible numeric;
  v_from_accessible numeric;
  v_missing numeric;
  v_buy_quantity numeric;
  v_leftover numeric;
begin
  if v_required <= 0 then
    return 0;
  end if;

  select * into v_product from public.market_products where id = p_material_product_id;
  if v_product.id is null or v_product.item_type <> 'material' then
    raise exception 'Choose a material scale.';
  end if;
  if p_expected_material_name is not null and lower(v_product.item_name) <> lower(trim(p_expected_material_name)) then
    raise exception 'That recipe needs %, not %.', p_expected_material_name, v_product.item_name;
  end if;

  v_accessible := public.accessible_item_quantity_by_name(p_character_id, v_product.item_name, p_station_city_name);
  v_from_accessible := least(v_required, v_accessible);
  v_missing := greatest(0, v_required - v_from_accessible);
  v_buy_quantity := case when v_missing > 0 then ceil(v_missing) else 0 end;

  if v_buy_quantity > 0 then
    if not v_product.is_available or v_product.price_coin <= 0 then
      raise exception '% is not available from this forge.', v_product.item_name;
    end if;
    if v_product.stock_quantity is not null and v_product.stock_quantity < v_buy_quantity then
      raise exception 'Not enough % stock.', v_product.item_name;
    end if;
  end if;

  if v_from_accessible > 0 then
    perform public.consume_crafting_item_by_name(p_character_id, v_product.item_name, v_from_accessible, p_station_city_name);
  end if;

  if v_buy_quantity > 0 and v_product.stock_quantity is not null then
    update public.market_products
    set stock_quantity = greatest(0, stock_quantity - v_buy_quantity)
    where id = v_product.id;
  end if;

  v_leftover := greatest(0, v_buy_quantity - v_missing);
  if v_leftover > 0 then
    perform public.add_forge_material_leftover(p_character_id, v_product, v_leftover, p_inventory_slots);
  end if;

  return (v_product.price_coin * v_buy_quantity)::int;
end;
$$;

create or replace function public.grant_material_conversion_item(
  p_character_id uuid,
  p_item_name text,
  p_item_type text,
  p_rarity public.item_rarity,
  p_quantity numeric,
  p_material text default '',
  p_modifiers jsonb default '{}'::jsonb,
  p_is_two_handed boolean default false
)
returns public.inventory_items
language plpgsql
security definer
set search_path = public
as $$
declare
  v_character public.characters%rowtype;
  v_target public.inventory_items%rowtype;
  v_item public.inventory_items%rowtype;
  v_slot int;
  v_quantity numeric;
begin
  select * into v_character from public.characters where id = p_character_id;
  if v_character.id is null then
    raise exception 'Character not found.';
  end if;

  v_quantity := public.assert_valid_item_quantity(p_item_name, p_item_type, p_quantity);

  select * into v_target
  from public.inventory_items i
  where i.character_id = p_character_id
    and i.loadout_slot is null
    and i.is_storage = false
    and lower(public.normalize_item_name(i.item_name)) = lower(public.normalize_item_name(p_item_name))
    and public.normalize_item_type(i.item_type) = public.normalize_item_type(p_item_type)
    and i.rarity = p_rarity
    and coalesce(i.display_name, '') = ''
    and coalesce(i.enchantment, '') = ''
    and coalesce(i.rune_name, '') = ''
    and (
      coalesce(i.material, '') = coalesce(p_material, '')
      or public.normalize_item_type(p_item_type) = 'material'
    )
    and coalesce(i.potion_strength, '') = ''
    and coalesce(i.potion_property, '') = ''
    and coalesce(i.potion_quality, '') = ''
    and i.enhancement_count = 0
    and i.is_two_handed = coalesce(p_is_two_handed, false)
    and i.is_accessory = false
    and i.modifiers = case when jsonb_typeof(coalesce(p_modifiers, '{}'::jsonb)) = 'object' then coalesce(p_modifiers, '{}'::jsonb) else '{}'::jsonb end
    and public.item_catalog_stackable(p_item_name, p_item_type)
  order by i.parent_item_id nulls first, i.slot_index, i.created_at, i.id
  limit 1;

  if v_target.id is not null then
    update public.inventory_items
    set quantity = quantity + v_quantity,
        material = case when public.normalize_item_type(p_item_type) = 'material' and length(trim(coalesce(p_material, ''))) > 0 then trim(p_material) else material end
    where id = v_target.id
    returning * into v_item;
    return v_item;
  end if;

  v_slot := public.find_first_free_inventory_slot(p_character_id, null, v_character.inventory_slots);
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
    enchantment,
    material,
    enhancement_count,
    is_two_handed
  )
  values (
    p_character_id,
    null,
    v_slot,
    public.normalize_item_name(p_item_name),
    public.normalize_item_type(p_item_type),
    p_rarity,
    v_quantity,
    false,
    0,
    case when jsonb_typeof(coalesce(p_modifiers, '{}'::jsonb)) = 'object' then coalesce(p_modifiers, '{}'::jsonb) else '{}'::jsonb end,
    null,
    coalesce(p_material, ''),
    0,
    coalesce(p_is_two_handed, false)
  )
  returning * into v_item;

  return v_item;
end;
$$;

create or replace function public.jursh_conversion_item_has_extras(
  p_item public.inventory_items,
  p_recipe public.material_conversion_recipes
)
returns boolean
language sql
stable
as $$
  select coalesce(p_item.enchantment, '') <> ''
    or coalesce(p_item.rune_name, '') <> ''
    or coalesce(p_item.enhancement_count, 0) > 0
    or coalesce(p_item.modifiers, '{}'::jsonb) <> public.forge_material_modifiers(p_recipe.material, p_recipe.item_type)
$$;

create or replace function public.is_jursh_conversion_character(p_character public.characters)
returns boolean
language sql
stable
set search_path = public
as $$
  select lower(trim(coalesce(p_character.name, ''))) = 'jursh'
    and (
      lower(trim(coalesce(p_character.class_key, ''))) = 'blacksmith'
      or lower(trim(coalesce(p_character.class_name, ''))) = 'blacksmith'
    )
    and exists (
      select 1
      from public.profiles p
      where p.id = p_character.owner_user_id
        and (
          lower(trim(coalesce(p.username, ''))) = 'eoshigande'
          or lower(trim(coalesce(p.display_name, ''))) = 'eoshigande'
        )
    )
$$;

create or replace function public.assert_jursh_conversion_access(
  p_profile public.profiles,
  p_character_id uuid
)
returns public.characters
language plpgsql
security definer
set search_path = public
as $$
declare
  v_character public.characters%rowtype;
begin
  v_character := public.assert_inventory_access(p_profile, p_character_id, false);
  if not public.is_jursh_conversion_character(v_character) then
    raise exception 'Only Jursh, Eoshigande''s Blacksmith, can use this conversion menu.';
  end if;
  return v_character;
end;
$$;

create or replace function public.dragon_scale_fragment_names()
returns text[]
language sql
stable
set search_path = public
as $$
  select coalesce(array_agg(item_name order by display_order, item_name), array[]::text[])
  from public.dragon_scale_fragment_catalog
  where is_active
$$;

create or replace function public.dragon_scale_fragment_matches(p_item_name text)
returns boolean
language sql
stable
set search_path = public
as $$
  select exists (
    select 1
    from public.dragon_scale_fragment_catalog d
    where d.is_active
      and lower(public.normalize_item_name(d.item_name)) = lower(public.normalize_item_name(p_item_name))
  )
$$;

create or replace function public.consume_accessible_dragon_scale_fragments(
  p_character_id uuid,
  p_station_city_name text,
  p_quantity numeric default 25
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_needed numeric := greatest(1, coalesce(p_quantity, 25));
  v_name text;
  v_available numeric;
  v_take numeric;
  v_consumed jsonb := '[]'::jsonb;
begin
  foreach v_name in array public.dragon_scale_fragment_names() loop
    exit when v_needed <= 0;
    v_available := public.accessible_item_quantity_by_name(p_character_id, v_name, p_station_city_name);
    v_take := least(v_needed, v_available);
    if v_take > 0 then
      perform public.consume_crafting_item_by_name(p_character_id, v_name, v_take, p_station_city_name);
      v_consumed := v_consumed || jsonb_build_array(jsonb_build_object('name', v_name, 'quantity', v_take));
      v_needed := v_needed - v_take;
    end if;
  end loop;

  if v_needed > 0 then
    raise exception 'Need 25 total dragon scale fragments to forge 1 Dragonscale Scale.';
  end if;

  return v_consumed;
end;
$$;

create or replace function public.consume_dragon_scale_fragment_selections(
  p_character_id uuid,
  p_station_city_name text,
  p_selections jsonb,
  p_required_quantity numeric default 25
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_entry jsonb;
  v_source text;
  v_item_id uuid;
  v_quantity numeric;
  v_total numeric := 0;
  v_selected record;
  v_consumed jsonb := '[]'::jsonb;
begin
  if jsonb_typeof(coalesce(p_selections, '[]'::jsonb)) <> 'array' then
    raise exception 'Choose dragon scale fragments before forging.';
  end if;

  for v_entry in select * from jsonb_array_elements(coalesce(p_selections, '[]'::jsonb)) loop
    v_source := lower(trim(coalesce(v_entry->>'source', '')));
    v_item_id := nullif(coalesce(v_entry->>'itemId', v_entry->>'id', ''), '')::uuid;
    v_quantity := coalesce((v_entry->>'quantity')::numeric, 0);
    if v_item_id is null or v_quantity <= 0 then
      continue;
    end if;

    select * into v_selected
    from public.crafting_selection_item(p_character_id, v_source, v_item_id, p_station_city_name)
    limit 1;

    if v_selected.item_name is null then
      raise exception 'A selected dragon scale stack is no longer available.';
    end if;
    if not public.dragon_scale_fragment_matches(v_selected.item_name) then
      raise exception '% cannot be forged into a Dragonscale Scale.', v_selected.item_name;
    end if;
    if v_selected.quantity < v_quantity then
      raise exception 'Not enough %.', v_selected.item_name;
    end if;

    v_total := v_total + v_quantity;
  end loop;

  if v_total < coalesce(p_required_quantity, 25) then
    raise exception 'Choose at least % dragon scale fragments.', coalesce(p_required_quantity, 25);
  end if;

  v_total := coalesce(p_required_quantity, 25);
  for v_entry in select * from jsonb_array_elements(coalesce(p_selections, '[]'::jsonb)) loop
    exit when v_total <= 0;
    v_source := lower(trim(coalesce(v_entry->>'source', '')));
    v_item_id := nullif(coalesce(v_entry->>'itemId', v_entry->>'id', ''), '')::uuid;
    v_quantity := least(coalesce((v_entry->>'quantity')::numeric, 0), v_total);
    if v_item_id is null or v_quantity <= 0 then
      continue;
    end if;

    select * into v_selected
    from public.crafting_selection_item(p_character_id, v_source, v_item_id, p_station_city_name)
    limit 1;

    perform public.consume_crafting_selection(p_character_id, v_source, v_item_id, v_quantity, p_station_city_name);
    v_consumed := v_consumed || jsonb_build_array(jsonb_build_object(
      'source', v_source,
      'itemId', v_item_id,
      'name', v_selected.item_name,
      'type', v_selected.item_type,
      'rarity', v_selected.rarity,
      'quantity', v_quantity
    ));
    v_total := v_total - v_quantity;
  end loop;

  return v_consumed;
end;
$$;

create or replace function public.get_jursh_conversion_state(
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

  v_character := public.assert_jursh_conversion_access(v_profile, p_character_id);

  return jsonb_build_object(
    'characterId', v_character.id,
    'recipes', (
      select coalesce(jsonb_agg(public.material_conversion_recipe_to_json(r) order by r.display_order, r.item_name), '[]'::jsonb)
      from public.material_conversion_recipes r
      where r.is_active
    ),
    'convertibleItems', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'item', public.inventory_item_record_to_json(i),
        'recipe', public.material_conversion_recipe_to_json(r),
        'hasExtras', public.jursh_conversion_item_has_extras(i, r)
      ) order by i.parent_item_id nulls first, i.slot_index, i.item_name), '[]'::jsonb)
      from public.inventory_items i
      join public.material_conversion_recipes r on public.material_conversion_recipe_matches_item(r, i)
      where i.character_id = v_character.id
        and i.loadout_slot is null
        and i.is_storage = false
    ),
    'scaleTotals', (
      select coalesce(jsonb_object_agg(scale_name, quantity order by scale_name), '{}'::jsonb)
      from (
        select r.scale_item_name as scale_name,
          coalesce(sum(i.quantity), 0) as quantity
        from (select distinct scale_item_name from public.material_conversion_recipes where is_active) r
        left join public.inventory_items i
          on i.character_id = v_character.id
          and i.loadout_slot is null
          and i.is_storage = false
          and lower(public.normalize_item_name(i.item_name)) = lower(public.normalize_item_name(r.scale_item_name))
        group by r.scale_item_name
      ) totals
    ),
    'scaleItems', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'source', 'inventory',
        'item', public.inventory_item_record_to_json(i)
      ) order by i.item_name, i.slot_index, i.id), '[]'::jsonb)
      from public.inventory_items i
      where i.character_id = v_character.id
        and i.loadout_slot is null
        and i.is_storage = false
        and exists (
          select 1
          from public.material_conversion_recipes r
          where r.is_active
            and lower(public.normalize_item_name(r.scale_item_name)) = lower(public.normalize_item_name(i.item_name))
        )
    ),
    'dragonScaleTotal', (
      select coalesce(sum(i.quantity), 0)
      from public.inventory_items i
      where i.character_id = v_character.id
        and i.loadout_slot is null
        and i.is_storage = false
        and public.dragon_scale_fragment_matches(i.item_name)
    ),
    'dragonScaleItems', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'source', 'inventory',
        'item', public.inventory_item_record_to_json(i)
      ) order by i.slot_index, i.item_name, i.id), '[]'::jsonb)
      from public.inventory_items i
      where i.character_id = v_character.id
        and i.loadout_slot is null
        and i.is_storage = false
        and public.dragon_scale_fragment_matches(i.item_name)
    )
  );
end;
$$;

drop function if exists public.convert_jursh_item_to_scales(text, uuid, uuid, boolean);

create or replace function public.convert_jursh_item_to_scales(
  p_session_token text,
  p_character_id uuid,
  p_item_id uuid,
  p_confirm_destroy_extras boolean default false,
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
  v_item public.inventory_items%rowtype;
  v_recipe public.material_conversion_recipes%rowtype;
  v_has_extras boolean;
  v_output public.inventory_items%rowtype;
  v_quantity numeric := greatest(1, coalesce(p_quantity, 1));
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;

  v_character := public.assert_jursh_conversion_access(v_profile, p_character_id);

  select * into v_item
  from public.inventory_items
  where id = p_item_id
    and character_id = v_character.id
    and loadout_slot is null
    and is_storage = false;

  if v_item.id is null then
    raise exception 'Choose a convertible item in Jursh''s inventory.';
  end if;

  select * into v_recipe
  from public.material_conversion_recipes r
  where public.material_conversion_recipe_matches_item(r, v_item)
  order by r.display_order, r.item_name
  limit 1;

  if v_recipe.recipe_key is null then
    raise exception 'That item is not convertible.';
  end if;

  v_quantity := floor(v_quantity);
  if v_quantity <= 0 then
    raise exception 'Quantity must be at least 1.';
  end if;
  if v_item.quantity < v_quantity then
    raise exception 'Not enough % to convert.', v_item.item_name;
  end if;

  v_has_extras := public.jursh_conversion_item_has_extras(v_item, v_recipe);
  if v_has_extras and not coalesce(p_confirm_destroy_extras, false) then
    return public.get_jursh_conversion_state(p_session_token, p_character_id)
      || jsonb_build_object(
        'needsConfirmation', true,
        'confirmationMessage', 'This item has modifiers, enhancements, runes, or enchantments that will be destroyed. Proceed?'
      );
  end if;

  if v_item.quantity > v_quantity then
    update public.inventory_items
    set quantity = quantity - v_quantity
    where id = v_item.id;
  else
    delete from public.inventory_items where id = v_item.id;
  end if;

  v_output := public.grant_material_conversion_item(
    v_character.id,
    v_recipe.scale_item_name,
    'material',
    v_recipe.rarity,
    v_recipe.scale_quantity * v_quantity,
    v_recipe.material,
    '{}'::jsonb,
    false
  );

  return public.get_jursh_conversion_state(p_session_token, p_character_id)
    || jsonb_build_object('createdItem', public.inventory_item_record_to_json(v_output));
end;
$$;

create or replace function public.consume_jursh_scale_by_name(
  p_character_id uuid,
  p_scale_item_name text,
  p_quantity numeric
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_needed numeric := public.assert_valid_item_quantity(p_scale_item_name, 'material', p_quantity);
  v_item public.inventory_items%rowtype;
  v_take numeric;
begin
  for v_item in
    select *
    from public.inventory_items
    where character_id = p_character_id
      and loadout_slot is null
      and is_storage = false
      and lower(public.normalize_item_name(item_name)) = lower(public.normalize_item_name(p_scale_item_name))
    order by parent_item_id nulls first, slot_index, created_at, id
  loop
    exit when v_needed <= 0;
    v_take := least(v_item.quantity, v_needed);
    if v_take >= v_item.quantity then
      delete from public.inventory_items where id = v_item.id;
    else
      update public.inventory_items set quantity = quantity - v_take where id = v_item.id;
    end if;
    v_needed := v_needed - v_take;
  end loop;

  if v_needed > 0 then
    raise exception 'Not enough %.', p_scale_item_name;
  end if;
end;
$$;

create or replace function public.convert_jursh_scales_to_item(
  p_session_token text,
  p_character_id uuid,
  p_recipe_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_character public.characters%rowtype;
  v_recipe public.material_conversion_recipes%rowtype;
  v_available numeric;
  v_output public.inventory_items%rowtype;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;

  v_character := public.assert_jursh_conversion_access(v_profile, p_character_id);

  select * into v_recipe
  from public.material_conversion_recipes
  where recipe_key = public.catalog_key_for_name(p_recipe_key)
    and is_active;

  if v_recipe.recipe_key is null then
    raise exception 'Unknown conversion recipe.';
  end if;

  select coalesce(sum(quantity), 0) into v_available
  from public.inventory_items
  where character_id = v_character.id
    and loadout_slot is null
    and is_storage = false
    and lower(public.normalize_item_name(item_name)) = lower(public.normalize_item_name(v_recipe.scale_item_name));

  if v_available < v_recipe.scale_quantity then
    raise exception 'Not enough %.', v_recipe.scale_item_name;
  end if;

  perform public.consume_jursh_scale_by_name(v_character.id, v_recipe.scale_item_name, v_recipe.scale_quantity);

  v_output := public.grant_material_conversion_item(
    v_character.id,
    v_recipe.item_name,
    v_recipe.item_type,
    v_recipe.rarity,
    1,
    v_recipe.material,
    public.forge_material_modifiers(v_recipe.material, v_recipe.item_type),
    public.material_conversion_two_handed(v_recipe.item_name, v_recipe.item_type)
  );

  return public.get_jursh_conversion_state(p_session_token, p_character_id)
    || jsonb_build_object('createdItem', public.inventory_item_record_to_json(v_output));
end;
$$;

create or replace function public.convert_jursh_selected_scales_to_item(
  p_session_token text,
  p_character_id uuid,
  p_recipe_key text,
  p_selections jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_character public.characters%rowtype;
  v_recipe public.material_conversion_recipes%rowtype;
  v_entry jsonb;
  v_item_id uuid;
  v_quantity numeric;
  v_total numeric := 0;
  v_item public.inventory_items%rowtype;
  v_needed numeric;
  v_take numeric;
  v_output public.inventory_items%rowtype;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;

  v_character := public.assert_jursh_conversion_access(v_profile, p_character_id);

  select * into v_recipe
  from public.material_conversion_recipes
  where recipe_key = public.catalog_key_for_name(p_recipe_key)
    and is_active;

  if v_recipe.recipe_key is null then
    raise exception 'Unknown conversion recipe.';
  end if;

  if jsonb_typeof(coalesce(p_selections, '[]'::jsonb)) <> 'array' then
    raise exception 'Choose material scale inputs before forging.';
  end if;

  for v_entry in select * from jsonb_array_elements(coalesce(p_selections, '[]'::jsonb)) loop
    v_item_id := nullif(coalesce(v_entry->>'itemId', v_entry->>'id', ''), '')::uuid;
    v_quantity := public.assert_valid_item_quantity(v_recipe.scale_item_name, 'material', coalesce((v_entry->>'quantity')::numeric, 0));
    if v_item_id is null or v_quantity <= 0 then
      continue;
    end if;

    select * into v_item
    from public.inventory_items
    where id = v_item_id
      and character_id = v_character.id
      and loadout_slot is null
      and is_storage = false;

    if v_item.id is null then
      raise exception 'A selected scale stack is no longer available.';
    end if;
    if lower(public.normalize_item_name(v_item.item_name)) <> lower(public.normalize_item_name(v_recipe.scale_item_name)) then
      raise exception '% cannot be used for this recipe.', v_item.item_name;
    end if;
    if v_item.quantity < v_quantity then
      raise exception 'Not enough %.', v_item.item_name;
    end if;

    v_total := v_total + v_quantity;
  end loop;

  if v_total < v_recipe.scale_quantity then
    raise exception 'Choose at least % %.', v_recipe.scale_quantity, v_recipe.scale_item_name;
  end if;

  v_needed := v_recipe.scale_quantity;
  for v_entry in select * from jsonb_array_elements(coalesce(p_selections, '[]'::jsonb)) loop
    exit when v_needed <= 0;
    v_item_id := nullif(coalesce(v_entry->>'itemId', v_entry->>'id', ''), '')::uuid;
    v_quantity := public.assert_valid_item_quantity(v_recipe.scale_item_name, 'material', coalesce((v_entry->>'quantity')::numeric, 0));
    if v_item_id is null or v_quantity <= 0 then
      continue;
    end if;

    select * into v_item
    from public.inventory_items
    where id = v_item_id
      and character_id = v_character.id
      and loadout_slot is null
      and is_storage = false;

    v_take := least(v_item.quantity, v_quantity, v_needed);
    if v_take >= v_item.quantity then
      delete from public.inventory_items where id = v_item.id;
    else
      update public.inventory_items set quantity = quantity - v_take where id = v_item.id;
    end if;
    v_needed := v_needed - v_take;
  end loop;

  if v_needed > 0 then
    raise exception 'Selected scale inputs changed before crafting finished.';
  end if;

  v_output := public.grant_material_conversion_item(
    v_character.id,
    v_recipe.item_name,
    v_recipe.item_type,
    v_recipe.rarity,
    1,
    v_recipe.material,
    public.forge_material_modifiers(v_recipe.material, v_recipe.item_type),
    public.material_conversion_two_handed(v_recipe.item_name, v_recipe.item_type)
  );

  return public.get_jursh_conversion_state(p_session_token, p_character_id)
    || jsonb_build_object('createdItem', public.inventory_item_record_to_json(v_output));
end;
$$;

drop function if exists public.forge_dragonscale_scale_from_dragon_scales(text, uuid, text);

create or replace function public.forge_dragonscale_scale_from_dragon_scales(
  p_session_token text,
  p_character_id uuid,
  p_station_city_name text default null,
  p_selections jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_character public.characters%rowtype;
  v_station_city_name text;
  v_consumed jsonb;
  v_output public.inventory_items%rowtype;
  v_available_total numeric := 0;
  v_output_quantity numeric := 0;
  v_required_quantity numeric := 0;
  v_entry jsonb;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;

  v_character := public.assert_inventory_access(v_profile, p_character_id, false);
  v_station_city_name := coalesce(nullif(trim(p_station_city_name), ''), v_character.location_name);

  if p_selections is not null and jsonb_typeof(p_selections) = 'array' then
    for v_entry in select * from jsonb_array_elements(coalesce(p_selections, '[]'::jsonb)) loop
      v_available_total := v_available_total + greatest(0, coalesce(nullif(v_entry->>'quantity', '')::numeric, 0));
    end loop;
  else
    select coalesce(sum(public.accessible_item_quantity_by_name(v_character.id, fragment_name, v_station_city_name)), 0)
    into v_available_total
    from unnest(public.dragon_scale_fragment_names()) as fragment_name;
  end if;

  v_output_quantity := floor(v_available_total / 25);
  if v_output_quantity < 1 then
    raise exception 'Need 25 total dragon scale fragments to forge 1 Dragonscale Scale.';
  end if;
  v_required_quantity := v_output_quantity * 25;

  v_consumed := case
    when p_selections is not null and jsonb_typeof(p_selections) = 'array'
      then public.consume_dragon_scale_fragment_selections(v_character.id, v_station_city_name, p_selections, v_required_quantity)
    else public.consume_accessible_dragon_scale_fragments(v_character.id, v_station_city_name, v_required_quantity)
  end;
  v_output := public.grant_material_conversion_item(
    v_character.id,
    'Dragonscale Scale',
    'material',
    'Legendary',
    v_output_quantity,
    'Dragonscale',
    '{}'::jsonb,
    false
  );

  return jsonb_build_object(
    'consumed', v_consumed,
    'createdQuantity', v_output_quantity,
    'returnedFragments', v_available_total - v_required_quantity,
    'createdItem', public.inventory_item_record_to_json(v_output)
  );
end;
$$;

drop function if exists public.enchantment_spell_for_rune(text);
drop function if exists public.enchantment_spell_for_rune(text, int, int);

create or replace function public.enchantment_spell_for_rune(
  p_rune_name text,
  p_rune_count int default 5,
  p_minimum_runes int default 5
)
returns text
language plpgsql
volatile
set search_path = public
as $$
declare
  v_key text := lower(trim(regexp_replace(coalesce(p_rune_name, ''), '\s+rune$', '', 'i')));
  v_spell_type text;
  v_options text[];
  v_roll int;
  v_weight int;
  v_total int;
  v_index int;
  v_count int;
  v_extra_runes int;
begin
  v_key := replace(v_key, '-', ' ');
  v_spell_type := case v_key
    when 'ember' then 'Ember'
    when 'frost' then 'Frost'
    when 'lightning' then 'Lightning'
    when 'earth' then 'Earth'
    when 'mountain' then 'Earth'
    when 'wind' then 'Wind'
    when 'void' then 'Utility'
    when 'energy' then 'Energy'
    when 'defensive support' then 'Defensive Support'
    when 'offensive support' then 'Offensive Support'
    when 'enhancement' then 'Enhancement'
    when 'utility' then 'Utility'
    else null
  end;

  if v_spell_type is null then
    raise exception 'That rune cannot be used for enchantment yet.';
  end if;

  select array_agg(name order by display_order, name)
  into v_options
  from public.spell_catalog
  where spell_type = v_spell_type
    and is_available;

  v_count := coalesce(array_length(v_options, 1), 0);
  if v_count = 0 then
    raise exception 'No % spells are available for enchantment.', v_spell_type;
  end if;

  v_extra_runes := greatest(0, coalesce(p_rune_count, p_minimum_runes, 1) - greatest(1, coalesce(p_minimum_runes, 1)));
  v_total := 0;
  for v_index in 1..v_count loop
    v_total := v_total + least(v_count, v_count - v_index + 1 + v_extra_runes);
  end loop;

  v_roll := floor(random() * v_total)::int + 1;

  for v_index in 1..v_count loop
    v_weight := least(v_count, v_count - v_index + 1 + v_extra_runes);
    if v_roll <= v_weight then
      return v_options[v_index];
    end if;
    v_roll := v_roll - v_weight;
  end loop;

  return v_options[1];
end;
$$;

drop function if exists public.run_blacksmith_action(text, uuid, text, text, uuid, uuid, uuid, text);
drop function if exists public.run_blacksmith_action(text, uuid, text, text, uuid, uuid, uuid, text, int);
drop function if exists public.run_blacksmith_action(text, uuid, text, text, uuid, uuid, uuid, text, int, jsonb);
drop function if exists public.run_blacksmith_action(text, uuid, text, text, uuid, uuid, uuid, text, int, jsonb, text);

create or replace function public.run_blacksmith_action(
  p_session_token text,
  p_character_id uuid,
  p_action text,
  p_recipe_key text default null,
  p_material_product_id uuid default null,
  p_target_item_id uuid default null,
  p_rune_product_id uuid default null,
  p_modifier_key text default null,
  p_rune_quantity int default null,
  p_dragon_scale_selections jsonb default null,
  p_rune_name text default null,
  p_vendor_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_character public.characters%rowtype;
  v_material_product public.market_products%rowtype;
  v_service_product public.market_products%rowtype;
  v_rune_product public.market_products%rowtype;
  v_target public.inventory_items%rowtype;
  v_item public.inventory_items%rowtype;
  v_wallet int;
  v_cost int := 0;
  v_labor int := 0;
  v_material_quantity numeric := 0;
  v_recipe_name text := '';
  v_recipe_type text := 'weapon';
  v_two_handed boolean := false;
  v_material text := '';
  v_rarity public.item_rarity := 'Common';
  v_slot int;
  v_modifiers jsonb := '{}'::jsonb;
  v_key text := lower(trim(coalesce(p_modifier_key, 'strength')));
  v_required_runes int;
  v_rune_quantity int;
  v_rune_name text := '';
  v_spell_name text;
  v_city public.cities%rowtype;
  v_vendor public.shop_vendors%rowtype;
  v_currency_system text := 'calostrynn';
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;

  v_character := public.assert_inventory_access(v_profile, p_character_id, false);
  v_city := public.assert_character_can_use_vendor(v_character, coalesce(nullif(p_vendor_key, ''), 'calostrynn-blacksmith'));
  select * into v_vendor from public.shop_vendors where vendor_key = coalesce(nullif(p_vendor_key, ''), 'calostrynn-blacksmith');
  v_currency_system := case when coalesce(v_vendor.city_key, 'calostrynn') = 'calostrynn' then 'calostrynn' else 'common' end;

  if lower(coalesce(p_action, '')) = 'dragon-scales' then
    perform public.forge_dragonscale_scale_from_dragon_scales(p_session_token, v_character.id, v_city.name, p_dragon_scale_selections);
    return public.get_discovered_cities(p_session_token);
  end if;

  if lower(coalesce(p_action, '')) = 'craft' then
    case lower(coalesce(p_recipe_key, ''))
      when 'dagger' then v_recipe_name := 'Dagger'; v_labor := 50; v_material_quantity := 0.5;
      when 'throwing-knives' then v_recipe_name := 'Throwing Knives'; v_labor := 100; v_material_quantity := 0.5;
      when 'shortbow' then v_recipe_name := 'Shortbow'; v_labor := 100; v_material_quantity := 0.5;
      when 'custom-light-weapon' then v_recipe_name := 'Custom Light Weapon'; v_labor := 1000; v_material_quantity := 0.5;
      when 'sword' then v_recipe_name := 'Sword'; v_labor := 300; v_material_quantity := 1;
      when 'spear' then v_recipe_name := 'Spear'; v_labor := 500; v_material_quantity := 1;
      when 'longbow' then v_recipe_name := 'Longbow'; v_labor := 500; v_material_quantity := 1;
      when 'custom-medium-weapon' then v_recipe_name := 'Custom Medium Weapon'; v_labor := 2500; v_material_quantity := 1;
      when 'battleaxe' then v_recipe_name := 'Battleaxe'; v_labor := 3000; v_material_quantity := 2; v_two_handed := true;
      when 'mace' then v_recipe_name := 'Mace'; v_labor := 3000; v_material_quantity := 2; v_two_handed := true;
      when 'claymore' then v_recipe_name := 'Claymore'; v_labor := 3000; v_material_quantity := 2; v_two_handed := true;
      when 'crossbow' then v_recipe_name := 'Crossbow'; v_labor := 4000; v_material_quantity := 2; v_two_handed := true;
      when 'custom-heavy-weapon' then v_recipe_name := 'Custom Heavy Weapon'; v_labor := 5000; v_material_quantity := 2; v_two_handed := true;
      when 'magic-bow' then v_recipe_name := 'Magic Bow'; v_labor := 3000; v_material_quantity := 0;
      when 'magic-longbow' then v_recipe_name := 'Magic Longbow'; v_labor := 5000; v_material_quantity := 0;
      when 'wand' then v_recipe_name := 'Wand'; v_labor := 100; v_material_quantity := 0.5;
      when 'scepter' then v_recipe_name := 'Scepter'; v_labor := 1000; v_material_quantity := 1;
      when 'staff' then v_recipe_name := 'Staff'; v_labor := 5000; v_material_quantity := 2;
      when 'custom-magecraft' then v_recipe_name := 'Custom Magecraft Commission'; v_labor := 6500; v_material_quantity := 1;
      when 'shield' then v_recipe_name := 'Shield'; v_recipe_type := 'shield'; v_labor := 5000; v_material_quantity := 1;
      else raise exception 'Unknown blacksmith recipe.';
    end case;

    select * into v_service_product
    from public.market_products
    where vendor_id = v_vendor.id
      and product_kind = 'service'
      and (
        product_key = v_vendor.vendor_key || '-service-' || lower(coalesce(p_recipe_key, ''))
        or (lower(item_name) = lower(v_recipe_name) and lower(shop_section) in ('light weapons', 'medium weapons', 'heavy weapons', 'magecraft commissions', 'shield creation'))
      )
    order by case when product_key = v_vendor.vendor_key || '-service-' || lower(coalesce(p_recipe_key, '')) then 0 else 1 end
    limit 1;

    if v_service_product.id is not null then
      v_labor := v_service_product.price_coin;
      v_currency_system := v_service_product.currency_system_key;
    end if;

    if lower(v_character.class_key) = 'blacksmith' or lower(v_character.class_name) = 'blacksmith' then
      v_labor := 0;
    end if;

    v_cost := v_labor;
    if v_material_quantity > 0 then
      select * into v_material_product from public.market_products where id = p_material_product_id;
      if v_material_product.id is null or v_material_product.item_type <> 'material' then
        raise exception 'Choose an available material scale.';
      end if;
      v_material := regexp_replace(v_material_product.item_name, '[[:space:]]+Scale$', '', 'i');
      v_rarity := v_material_product.rarity;
      v_cost := v_cost + public.consume_forge_materials(v_character.id, v_material_product.id, v_material_quantity, v_character.inventory_slots, v_city.name);
    end if;

    v_wallet := public.wallet_total_currency(v_character.id, v_currency_system);
    if v_wallet < v_cost then raise exception 'Not enough currency.'; end if;
    perform public.set_wallet_from_currency_value(v_character.id, v_currency_system, v_wallet - v_cost);
    perform public.ensure_dm_testing_wallet(v_character.id);

    v_slot := public.find_first_free_inventory_slot(v_character.id, null, v_character.inventory_slots);
    if v_slot is null then raise exception 'Inventory full.'; end if;

    v_modifiers := public.forge_material_modifiers(v_material, v_recipe_type);

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
      trim(concat_ws(' ', nullif(v_material, ''), v_recipe_name)),
      v_recipe_type,
      v_rarity,
      1,
      false,
      0,
      v_modifiers,
      null,
      v_material,
      0,
      v_two_handed,
      null,
      null,
      null
    )
    returning * into v_item;

    return public.get_discovered_cities(p_session_token);
  end if;

  select * into v_target
  from public.inventory_items
  where id = p_target_item_id
    and character_id = v_character.id;

  if v_target.id is null then raise exception 'Choose an eligible item.'; end if;

  if p_rune_product_id is not null then
    select * into v_rune_product from public.market_products where id = p_rune_product_id and item_type = 'rune' and is_available;
  end if;
  v_rune_name := public.normalize_item_name(coalesce(nullif(trim(p_rune_name), ''), v_rune_product.item_name, ''));
  if v_rune_name = '' then raise exception 'Choose a rune.'; end if;
  if lower(v_rune_name) not in ('ember rune', 'frost rune', 'lightning rune', 'earth rune', 'wind rune', 'mountain rune', 'void rune') then
    raise exception 'Choose an Ember, Frost, Lightning, Earth, Wind, Mountain, or Void rune.';
  end if;

  if lower(coalesce(p_action, '')) = 'enhance' then
    if v_target.item_type = 'armor' then raise exception 'Armor enhancement belongs at the armory.'; end if;
    if not public.item_catalog_can_be_enhanced(v_target.item_name, v_target.item_type, v_target.material) then raise exception 'That item is not marked enhanceable.'; end if;
    if v_target.enchantment is not null then raise exception 'An enchanted item cannot be enhanced.'; end if;
    if v_target.enhancement_count >= 3 then raise exception 'That item already has three enhancements.'; end if;
    if v_key not in ('strength', 'accuracy', 'intelligence', 'vitality', 'recovery', 'mana_regen', 'charisma', 'wisdom_cunning', 'perception', 'alchemy', 'stealth', 'agility') then
      raise exception 'Choose an attribute or skill to enhance.';
    end if;

    perform public.consume_crafting_item_by_name(v_character.id, v_rune_name, 1, v_city.name);

    v_modifiers := coalesce(v_target.modifiers, '{}'::jsonb) || jsonb_build_object(v_key, coalesce((v_target.modifiers->>v_key)::int, 0) + 1);
    update public.inventory_items
    set modifiers = v_modifiers,
        enhancement_count = enhancement_count + 1
    where id = v_target.id;

    return public.get_discovered_cities(p_session_token);
  end if;

  if lower(coalesce(p_action, '')) = 'enchant' then
    if not public.item_catalog_can_be_enchanted(v_target.item_name, v_target.item_type, v_target.material) then raise exception 'That item is not marked enchantable.'; end if;
    if v_target.enchantment is not null then raise exception 'That weapon is already enchanted.'; end if;
    if v_target.enhancement_count > 0 then raise exception 'An enhanced weapon cannot be enchanted.'; end if;
    v_required_runes := case when lower(v_character.class_key) = 'talismanist' or lower(v_character.class_name) = 'talismanist' then 3 else 5 end;
    v_rune_quantity := greatest(v_required_runes, coalesce(p_rune_quantity, v_required_runes));

    v_spell_name := public.enchantment_spell_for_rune(v_rune_name, v_rune_quantity, v_required_runes);
    perform public.consume_crafting_item_by_name(v_character.id, v_rune_name, v_rune_quantity, v_city.name);

    update public.inventory_items
    set enchantment = v_spell_name
    where id = v_target.id;

    return public.get_discovered_cities(p_session_token);
  end if;

  raise exception 'Unknown blacksmith action.';
end;
$$;

drop function if exists public.run_armory_action(text, uuid, text, text, uuid, uuid, uuid, text);
drop function if exists public.run_armory_action(text, uuid, text, text, uuid, uuid, uuid, text, jsonb);
drop function if exists public.run_armory_action(text, uuid, text, text, uuid, uuid, uuid, text, jsonb, text);

create or replace function public.run_armory_action(
  p_session_token text,
  p_character_id uuid,
  p_action text,
  p_recipe_key text default null,
  p_material_product_id uuid default null,
  p_target_item_id uuid default null,
  p_rune_product_id uuid default null,
  p_modifier_key text default null,
  p_dragon_scale_selections jsonb default null,
  p_rune_name text default null,
  p_vendor_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_character public.characters%rowtype;
  v_material_product public.market_products%rowtype;
  v_service_product public.market_products%rowtype;
  v_rune_product public.market_products%rowtype;
  v_target public.inventory_items%rowtype;
  v_item public.inventory_items%rowtype;
  v_wallet int;
  v_cost int := 0;
  v_labor int := 0;
  v_material_quantity numeric := 0;
  v_material_name text;
  v_recipe_name text := '';
  v_material text := '';
  v_rarity public.item_rarity := 'Common';
  v_slot int;
  v_modifiers jsonb := '{}'::jsonb;
  v_key text := lower(trim(coalesce(p_modifier_key, 'strength')));
  v_rune_name text := '';
  v_city public.cities%rowtype;
  v_vendor public.shop_vendors%rowtype;
  v_currency_system text := 'calostrynn';
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;

  v_character := public.assert_inventory_access(v_profile, p_character_id, false);
  v_city := public.assert_character_can_use_vendor(v_character, coalesce(nullif(p_vendor_key, ''), 'calostrynn-armory'));
  select * into v_vendor from public.shop_vendors where vendor_key = coalesce(nullif(p_vendor_key, ''), 'calostrynn-armory');
  v_currency_system := case when coalesce(v_vendor.city_key, 'calostrynn') = 'calostrynn' then 'calostrynn' else 'common' end;

  if lower(coalesce(p_action, '')) = 'dragon-scales' then
    perform public.forge_dragonscale_scale_from_dragon_scales(p_session_token, v_character.id, v_city.name, p_dragon_scale_selections);
    return public.get_discovered_cities(p_session_token);
  end if;

  if lower(coalesce(p_action, '')) = 'craft' then
    case lower(coalesce(p_recipe_key, ''))
      when 'leather-armor' then v_recipe_name := 'Leather Armor'; v_labor := 0; v_material_quantity := 0; v_material := 'Leather'; v_rarity := 'Common';
      when 'iron-armor' then v_recipe_name := 'Iron Armor'; v_labor := 500; v_material_quantity := 3; v_material_name := 'Iron Scale';
      when 'steel-armor' then v_recipe_name := 'Steel Armor'; v_labor := 2500; v_material_quantity := 3; v_material_name := 'Steel Scale';
      when 'mythril-armor' then v_recipe_name := 'Mythril Armor'; v_labor := 5000; v_material_quantity := 3; v_material_name := 'Mythril Scale';
      when 'vaylium-armor' then v_recipe_name := 'Vaylium Armor'; v_labor := 7500; v_material_quantity := 3; v_material_name := 'Vaylium Scale';
      when 'dragonscale-armor' then v_recipe_name := 'Dragonscale Armor'; v_labor := 10000; v_material_quantity := 3; v_material_name := 'Dragonscale Scale';
      else raise exception 'Unknown armory recipe.';
    end case;

    select * into v_service_product
    from public.market_products
    where vendor_id = v_vendor.id
      and product_kind = 'service'
      and (
        product_key = v_vendor.vendor_key || '-service-' || lower(coalesce(p_recipe_key, ''))
        or (lower(item_name) = lower(v_recipe_name) and lower(shop_section) = 'armor creation')
      )
    order by case when product_key = v_vendor.vendor_key || '-service-' || lower(coalesce(p_recipe_key, '')) then 0 else 1 end
    limit 1;

    if v_service_product.id is not null then
      v_labor := v_service_product.price_coin;
      v_currency_system := v_service_product.currency_system_key;
    end if;

    if lower(v_character.class_key) = 'armor-clad' or lower(v_character.class_name) = 'armor-clad' then
      v_labor := 0;
    end if;

    v_cost := v_labor;
    if v_material_quantity > 0 then
      select * into v_material_product from public.market_products where id = p_material_product_id;
      if v_material_product.id is null or v_material_product.item_type <> 'material' then
        raise exception 'Choose a material scale.';
      end if;
      v_material := regexp_replace(v_material_product.item_name, '[[:space:]]+Scale$', '', 'i');
      v_rarity := v_material_product.rarity;
      v_cost := v_cost + public.consume_forge_materials(v_character.id, v_material_product.id, v_material_quantity, v_character.inventory_slots, v_city.name, v_material_name);
    end if;

    v_wallet := public.wallet_total_currency(v_character.id, v_currency_system);
    if v_wallet < v_cost then raise exception 'Not enough currency.'; end if;
    perform public.set_wallet_from_currency_value(v_character.id, v_currency_system, v_wallet - v_cost);
    perform public.ensure_dm_testing_wallet(v_character.id);

    v_slot := public.find_first_free_inventory_slot(v_character.id, null, v_character.inventory_slots);
    if v_slot is null then raise exception 'Inventory full.'; end if;

    v_modifiers := public.forge_material_modifiers(v_material, 'armor');

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
      is_two_handed
    )
    values (
      v_character.id,
      null,
      v_slot,
      v_recipe_name,
      'armor',
      v_rarity,
      1,
      false,
      0,
      v_modifiers,
      null,
      v_material,
      0,
      false
    )
    returning * into v_item;

    return public.get_discovered_cities(p_session_token);
  end if;

  if lower(coalesce(p_action, '')) = 'enhance' then
    select * into v_target
    from public.inventory_items
    where id = p_target_item_id
      and character_id = v_character.id;

    if v_target.id is null then raise exception 'Choose an eligible armor.'; end if;
    if v_target.item_type <> 'armor' then raise exception 'Armory enhancement is for armor.'; end if;
    if not public.item_catalog_can_be_enhanced(v_target.item_name, v_target.item_type, v_target.material) then raise exception 'That armor is not marked enhanceable.'; end if;
    if v_target.enchantment is not null then raise exception 'An enchanted item cannot be enhanced.'; end if;
    if v_target.enhancement_count >= 3 then raise exception 'That armor already has three enhancements.'; end if;

    if p_rune_product_id is not null then
      select * into v_rune_product from public.market_products where id = p_rune_product_id and item_type = 'rune' and is_available;
    end if;
    v_rune_name := public.normalize_item_name(coalesce(nullif(trim(p_rune_name), ''), v_rune_product.item_name, ''));
    if v_rune_name = '' then raise exception 'Choose a rune.'; end if;
    if lower(v_rune_name) not in ('ember rune', 'frost rune', 'lightning rune', 'earth rune', 'wind rune', 'mountain rune', 'void rune') then
      raise exception 'Choose an Ember, Frost, Lightning, Earth, Wind, Mountain, or Void rune.';
    end if;
    if v_key not in ('strength', 'accuracy', 'intelligence', 'vitality', 'recovery', 'mana_regen', 'charisma', 'wisdom_cunning', 'perception', 'alchemy', 'stealth', 'agility') then
      raise exception 'Choose an attribute or skill to enhance.';
    end if;

    perform public.consume_crafting_item_by_name(v_character.id, v_rune_name, 1, v_city.name);

    v_modifiers := coalesce(v_target.modifiers, '{}'::jsonb) || jsonb_build_object(v_key, coalesce((v_target.modifiers->>v_key)::int, 0) + 1);
    update public.inventory_items
    set modifiers = v_modifiers,
        enhancement_count = enhancement_count + 1
    where id = v_target.id;

    return public.get_discovered_cities(p_session_token);
  end if;

  raise exception 'Unknown armory action.';
end;
$$;

create or replace function public.crafting_selection_item(
  p_character_id uuid,
  p_source text,
  p_item_id uuid,
  p_station_city_name text
)
returns table (
  item_name text,
  item_type text,
  rarity public.item_rarity,
  quantity numeric,
  properties text[]
)
language sql
stable
set search_path = public
as $$
  select
    public.normalize_item_name(i.item_name),
    i.item_type,
    i.rarity,
    i.quantity,
    coalesce(c.properties, array[]::text[])
  from public.inventory_items i
  left join public.item_catalog c on c.item_key = public.catalog_key_for_name(public.normalize_item_name(i.item_name))
  where lower(trim(coalesce(p_source, ''))) = 'inventory'
    and i.id = p_item_id
    and i.character_id = p_character_id
    and i.loadout_slot is null
    and i.is_storage = false
    and public.normalize_item_type(i.item_type) <> 'potion'
    and (
      i.parent_item_id is null
      or exists (
        select 1
        from public.inventory_items storage
        where storage.id = i.parent_item_id
          and storage.character_id = p_character_id
          and storage.is_storage = true
      )
    )
  union all
  select
    public.normalize_item_name(h.item_name),
    h.item_type,
    h.rarity,
    h.quantity,
    coalesce(c.properties, array[]::text[])
  from public.characters ch
  join public.house_inventory_items h on h.owner_user_id = ch.owner_user_id
  join public.player_houses home on home.id = h.house_id
  left join public.item_catalog c on c.item_key = public.catalog_key_for_name(public.normalize_item_name(h.item_name))
  where lower(trim(coalesce(p_source, ''))) = 'house'
    and public.crafting_house_is_accessible(p_character_id, p_station_city_name)
    and ch.id = p_character_id
    and not home.is_locked
    and public.city_names_match(home.city_name, ch.location_name)
    and public.city_names_match(home.city_name, p_station_city_name)
    and h.id = p_item_id
    and h.is_storage = false
    and public.normalize_item_type(h.item_type) <> 'potion'
$$;

create or replace function public.consume_crafting_selection(
  p_character_id uuid,
  p_source text,
  p_item_id uuid,
  p_quantity numeric,
  p_station_city_name text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_needed numeric := coalesce(p_quantity, 0);
  v_inventory_item public.inventory_items%rowtype;
  v_house_item public.house_inventory_items%rowtype;
begin
  if v_needed <= 0 then
    raise exception 'Quantity must be positive.';
  end if;

  if lower(trim(coalesce(p_source, ''))) = 'inventory' then
    select * into v_inventory_item
    from public.inventory_items
    where id = p_item_id
      and character_id = p_character_id
      and loadout_slot is null
      and is_storage = false
      and public.normalize_item_type(item_type) <> 'potion';

    if v_inventory_item.id is null then raise exception 'Selected inventory ingredient was not found.'; end if;
    if v_inventory_item.quantity < v_needed then raise exception 'Not enough %.', v_inventory_item.item_name; end if;

    if v_inventory_item.quantity <= v_needed then
      delete from public.inventory_items where id = v_inventory_item.id;
    else
      update public.inventory_items set quantity = quantity - v_needed where id = v_inventory_item.id;
    end if;
    return;
  end if;

  if lower(trim(coalesce(p_source, ''))) = 'house' then
    if not public.crafting_house_is_accessible(p_character_id, p_station_city_name) then
      raise exception 'House storage is not accessible from here.';
    end if;

    select h.* into v_house_item
    from public.characters c
    join public.house_inventory_items h on h.owner_user_id = c.owner_user_id
    join public.player_houses home on home.id = h.house_id
    where c.id = p_character_id
      and not home.is_locked
      and public.city_names_match(home.city_name, c.location_name)
      and public.city_names_match(home.city_name, p_station_city_name)
      and h.id = p_item_id
      and h.is_storage = false
      and public.normalize_item_type(h.item_type) <> 'potion';

    if v_house_item.id is null then raise exception 'Selected house ingredient was not found.'; end if;
    if v_house_item.quantity < v_needed then raise exception 'Not enough % in the house.', v_house_item.item_name; end if;

    if v_house_item.quantity <= v_needed then
      delete from public.house_inventory_items where id = v_house_item.id;
    else
      update public.house_inventory_items set quantity = quantity - v_needed where id = v_house_item.id;
    end if;
    return;
  end if;

  raise exception 'Unknown ingredient source.';
end;
$$;

create or replace function public.brewery_available_items(
  p_character_id uuid,
  p_station_city_name text
)
returns jsonb
language sql
stable
set search_path = public
as $$
  with available as (
    select
      0 as source_order,
      'inventory'::text as source,
      i.id,
      public.normalize_item_name(i.item_name) as item_name,
      i.item_type,
      i.rarity,
      i.quantity,
      coalesce(c.properties, array[]::text[]) as properties
    from public.inventory_items i
    left join public.item_catalog c on c.item_key = public.catalog_key_for_name(public.normalize_item_name(i.item_name))
    where i.character_id = p_character_id
      and i.loadout_slot is null
      and i.is_storage = false
      and (
        public.normalize_item_type(i.item_type) <> 'potion'
        or lower(public.normalize_item_name(i.item_name)) = 'arcane nector'
      )
      and (
        i.parent_item_id is null
        or exists (
          select 1
          from public.inventory_items storage
          where storage.id = i.parent_item_id
            and storage.character_id = p_character_id
            and storage.is_storage = true
        )
      )
    union all
    select
      1 as source_order,
      'house'::text as source,
      h.id,
      public.normalize_item_name(h.item_name) as item_name,
      h.item_type,
      h.rarity,
      h.quantity,
      coalesce(c.properties, array[]::text[]) as properties
    from public.characters ch
    join public.house_inventory_items h on h.owner_user_id = ch.owner_user_id
    join public.player_houses home on home.id = h.house_id
    left join public.item_catalog c on c.item_key = public.catalog_key_for_name(public.normalize_item_name(h.item_name))
    where ch.id = p_character_id
      and public.crafting_house_is_accessible(p_character_id, p_station_city_name)
      and not home.is_locked
      and public.city_names_match(home.city_name, ch.location_name)
      and public.city_names_match(home.city_name, p_station_city_name)
      and h.is_storage = false
      and (
        public.normalize_item_type(h.item_type) <> 'potion'
        or lower(public.normalize_item_name(h.item_name)) = 'arcane nector'
      )
  ),
  useful as (
    select *
    from available a
    where lower(a.item_name) = 'arcane nector'
      or exists (
        select 1
        from unnest(a.properties) as prop(property_name)
        where prop.property_name in ('Catalyst', 'Stabilizer')
           or exists (select 1 from public.alchemy_potion_definitions d where d.property_key = prop.property_name)
      )
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'source', source,
    'id', id,
    'name', item_name,
    'type', item_type,
    'rarity', rarity,
    'quantity', quantity,
    'properties', to_jsonb(properties),
    'catalystBonus', case when 'Catalyst' = any(properties) then public.catalyst_bonus_for_rarity(rarity) else 0 end
  ) order by source_order, item_name, id), '[]'::jsonb)
  from useful
$$;

drop function if exists public.get_brewery_state(text, uuid);

create or replace function public.get_brewery_state(
  p_session_token text,
  p_character_id uuid,
  p_vendor_key text default null
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
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;

  v_character := public.assert_inventory_access(v_profile, p_character_id, false);
  v_city := public.assert_character_can_use_vendor(v_character, coalesce(nullif(p_vendor_key, ''), 'calostrynn-brewery'));

  return jsonb_build_object(
    'definitions', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'propertyKey', property_key,
        'potionName', potion_name,
        'description', description,
        'automatedEffect', automated_effect,
        'order', display_order
      ) order by display_order), '[]'::jsonb)
      from public.alchemy_potion_definitions
    ),
    'availableItems', public.brewery_available_items(v_character.id, v_city.name),
    'houseAccess', jsonb_build_object(
      'accessible', public.crafting_house_is_accessible(v_character.id, v_city.name),
      'city', v_city.name
    )
  );
end;
$$;

drop function if exists public.brew_potion(text, uuid, text, text, jsonb, jsonb, jsonb);

create or replace function public.brew_potion(
  p_session_token text,
  p_character_id uuid,
  p_strength text,
  p_property_key text,
  p_property_selections jsonb,
  p_stabilizer_selections jsonb,
  p_catalyst_selection jsonb default null,
  p_vendor_key text default null
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
  v_definition public.alchemy_potion_definitions%rowtype;
  v_strength text := initcap(lower(trim(coalesce(p_strength, ''))));
  v_property_required numeric;
  v_stabilizer_required numeric;
  v_selection jsonb;
  v_source text;
  v_item_id uuid;
  v_quantity numeric;
  v_selected record;
  v_property_total numeric := 0;
  v_stabilizer_total numeric := 0;
  v_catalyst_bonus int := 0;
  v_d20 int;
  v_alchemy int := 0;
  v_total int;
  v_quality text;
  v_success boolean;
  v_item_name text;
  v_rarity public.item_rarity;
  v_slot int;
  v_existing public.inventory_items%rowtype;
  v_created_item jsonb := null;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;

  v_character := public.assert_inventory_access(v_profile, p_character_id, false);
  v_city := public.assert_character_can_use_vendor(v_character, coalesce(nullif(p_vendor_key, ''), 'calostrynn-brewery'));

  if v_strength not in ('Lesser', 'Greater', 'Greatest') then
    raise exception 'Choose Lesser, Greater, or Greatest strength.';
  end if;

  select * into v_definition
  from public.alchemy_potion_definitions
  where lower(property_key) = lower(trim(coalesce(p_property_key, '')))
     or lower(potion_name) = lower(trim(coalesce(p_property_key, '')));

  if v_definition.property_key is null then
    raise exception 'Choose a valid potion property.';
  end if;

  case v_strength
    when 'Lesser' then v_property_required := 10; v_stabilizer_required := 3;
    when 'Greater' then v_property_required := 25; v_stabilizer_required := 10;
    when 'Greatest' then v_property_required := 50; v_stabilizer_required := 25;
  end case;

  for v_selection in select * from jsonb_array_elements(coalesce(p_property_selections, '[]'::jsonb)) loop
    v_quantity := coalesce((v_selection->>'quantity')::numeric, 0);
    if v_quantity <= 0 then continue; end if;
    v_source := v_selection->>'source';
    v_item_id := nullif(v_selection->>'id', '')::uuid;

    select * into v_selected from public.crafting_selection_item(v_character.id, v_source, v_item_id, v_city.name) limit 1;
    if v_selected.item_name is null then raise exception 'A selected potion ingredient is not available.'; end if;
    if not v_definition.property_key = any(v_selected.properties) then
      raise exception '% is not valid for a % potion.', v_selected.item_name, v_definition.potion_name;
    end if;
    if v_selected.quantity < v_quantity then raise exception 'Not enough %.', v_selected.item_name; end if;

    v_property_total := v_property_total + v_quantity;
    perform public.consume_crafting_selection(v_character.id, v_source, v_item_id, v_quantity, v_city.name);
  end loop;

  if v_property_total < v_property_required then
    raise exception '% % Potion needs % matching-property ingredients.', v_strength, v_definition.potion_name, v_property_required;
  end if;

  for v_selection in select * from jsonb_array_elements(coalesce(p_stabilizer_selections, '[]'::jsonb)) loop
    v_quantity := coalesce((v_selection->>'quantity')::numeric, 0);
    if v_quantity <= 0 then continue; end if;
    v_source := v_selection->>'source';
    v_item_id := nullif(v_selection->>'id', '')::uuid;

    select * into v_selected from public.crafting_selection_item(v_character.id, v_source, v_item_id, v_city.name) limit 1;
    if v_selected.item_name is null then raise exception 'A selected stabilizer is not available.'; end if;
    if not 'Stabilizer' = any(v_selected.properties) then
      raise exception '% is not a stabilizer.', v_selected.item_name;
    end if;
    if v_selected.quantity < v_quantity then raise exception 'Not enough %.', v_selected.item_name; end if;

    v_stabilizer_total := v_stabilizer_total + v_quantity;
    perform public.consume_crafting_selection(v_character.id, v_source, v_item_id, v_quantity, v_city.name);
  end loop;

  if v_stabilizer_total < v_stabilizer_required then
    raise exception '% % Potion needs % stabilizers.', v_strength, v_definition.potion_name, v_stabilizer_required;
  end if;

  if public.accessible_item_quantity_by_name(v_character.id, 'Arcane Nector', v_city.name) < 1 then
    raise exception 'Every brew requires 1 Arcane Nector.';
  end if;
  perform public.consume_crafting_item_by_name(v_character.id, 'Arcane Nector', 1, v_city.name);

  if p_catalyst_selection is not null and jsonb_typeof(p_catalyst_selection) = 'array' and jsonb_array_length(p_catalyst_selection) > 1 then
    raise exception 'Only one catalyst can be used per brew.';
  end if;

  if p_catalyst_selection is not null
    and jsonb_typeof(p_catalyst_selection) = 'object'
    and nullif(p_catalyst_selection->>'id', '') is not null
  then
    v_source := p_catalyst_selection->>'source';
    v_item_id := nullif(p_catalyst_selection->>'id', '')::uuid;

    select * into v_selected from public.crafting_selection_item(v_character.id, v_source, v_item_id, v_city.name) limit 1;
    if v_selected.item_name is null then raise exception 'Selected catalyst is not available.'; end if;
    if not 'Catalyst' = any(v_selected.properties) then raise exception '% is not a catalyst.', v_selected.item_name; end if;
    if v_selected.quantity < 1 then raise exception 'Not enough %.', v_selected.item_name; end if;

    v_catalyst_bonus := public.catalyst_bonus_for_rarity(v_selected.rarity);
    perform public.consume_crafting_selection(v_character.id, v_source, v_item_id, 1, v_city.name);
  end if;

  v_d20 := floor(random() * 20)::int + 1;
  v_alchemy := coalesce((v_character.attributes->>'alchemy')::int, 0);
  v_total := v_d20 + v_alchemy + v_catalyst_bonus;
  v_success := v_d20 <> 1 and v_total > 5;

  if v_success then
    v_quality := case
      when v_total <= 10 then 'Shoddy'
      when v_total <= 15 then 'Basic'
      when v_total <= 20 then 'Fine'
      when v_total <= 24 then 'Strong'
      else 'Enriched'
    end;

    if v_definition.property_key in ('Healing', 'Mana Regen') then
      v_quality := null;
    end if;

    v_item_name := public.format_potion_item_name(v_strength, v_definition.property_key, v_quality);
    v_rarity := public.potion_rarity_for(v_strength, v_definition.property_key);

    select * into v_existing
    from public.inventory_items
    where character_id = v_character.id
      and loadout_slot is null
      and is_storage = false
      and item_name = v_item_name
      and item_type = 'potion'
      and rarity = v_rarity
      and coalesce(potion_strength, '') = v_strength
      and coalesce(potion_property, '') = v_definition.property_key
      and coalesce(potion_quality, '') = coalesce(v_quality, '')
    order by parent_item_id nulls first, slot_index, created_at
    limit 1;

    if v_existing.id is null then
      v_slot := public.find_first_free_inventory_slot(v_character.id, null, v_character.inventory_slots);
      if v_slot is null then raise exception 'Inventory full for brewed potion.'; end if;
      v_created_item := public.add_character_inventory_item(p_session_token, v_character.id, null, v_slot, v_item_name, 'potion', v_rarity::text, 1, false, 0, '{}'::jsonb, null, null, 0, false, v_strength, v_definition.property_key, v_quality);
    else
      v_created_item := public.add_character_inventory_item(p_session_token, v_character.id, v_existing.parent_item_id, v_existing.slot_index, v_item_name, 'potion', v_rarity::text, 1, false, 0, '{}'::jsonb, null, null, 0, false, v_strength, v_definition.property_key, v_quality);
    end if;
  end if;

  return jsonb_build_object(
    'result', jsonb_build_object(
      'success', v_success,
      'd20', v_d20,
      'alchemyBonus', v_alchemy,
      'catalystBonus', v_catalyst_bonus,
      'total', v_total,
      'quality', v_quality,
      'item', v_created_item,
      'message', case when v_success then 'Brew successful.' else 'The brew failed and the ingredients were consumed.' end
    ),
    'brewery', public.get_brewery_state(p_session_token, v_character.id, p_vendor_key),
    'cities', public.get_discovered_cities(p_session_token)
  );
end;
$$;

create or replace function public.consume_inventory_potion(
  p_session_token text,
  p_item_id uuid,
  p_confirm_drop_flask boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_item public.inventory_items%rowtype;
  v_character public.characters%rowtype;
  v_strength text;
  v_property text;
  v_effect text := 'none';
  v_amount int := 0;
  v_current int;
  v_new_value int;
  v_active_combatant public.combatants%rowtype;
  v_flask_stack public.inventory_items%rowtype;
  v_flask_slot int;
  v_flask_parent_id uuid := null;
  v_parent_capacity int;
  v_flask_dropped boolean := false;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;

  select * into v_item from public.inventory_items where id = p_item_id;
  if v_item.id is null then raise exception 'Potion not found.'; end if;

  v_character := public.assert_inventory_access(v_profile, v_item.character_id, false);

  if v_item.item_type <> 'potion' then raise exception 'Only potions can be consumed.'; end if;
  if lower(public.normalize_item_name(v_item.item_name)) = 'empty flask' then raise exception 'Empty Flask cannot be consumed.'; end if;

  v_strength := coalesce(v_item.potion_strength, public.potion_strength_from_name(v_item.item_name));
  v_property := coalesce(v_item.potion_property, public.potion_property_from_name(v_item.item_name));

  select cb.* into v_active_combatant
  from public.combatants cb
  join public.battles b on b.id = cb.battle_id and b.status = 'active'
  where cb.character_id = v_character.id
  order by cb.created_at desc
  limit 1;

  if v_property = 'Healing' then
    if v_active_combatant.id is not null and exists (
      select 1 from jsonb_array_elements(v_active_combatant.statuses) effect
      where effect->>'key' in ('burning', 'bleeding') and coalesce((effect->>'duration')::int, 0) > 0
    ) then
      raise exception 'Healing cannot take effect while this character is burning or bleeding.';
    end if;
    v_effect := 'health';
    v_current := coalesce(v_active_combatant.current_hp, v_character.current_hp);
    if v_current >= v_character.max_hp then raise exception 'Health is already full.'; end if;
    v_amount := case v_strength when 'Lesser' then 20 when 'Greater' then 50 when 'Greatest' then v_character.max_hp else 0 end;
    v_new_value := least(v_character.max_hp, v_current + v_amount);
  elsif v_property = 'Mana Regen' then
    v_effect := 'mana';
    v_current := coalesce(v_active_combatant.current_mana, v_character.current_mana);
    if v_current >= v_character.max_mana then raise exception 'Mana is already full.'; end if;
    v_amount := case v_strength when 'Lesser' then 15 when 'Greater' then 40 when 'Greatest' then v_character.max_mana else 0 end;
    v_new_value := least(v_character.max_mana, v_current + v_amount);
  end if;

  select * into v_flask_stack
  from public.inventory_items
  where character_id = v_character.id
    and loadout_slot is null
    and is_storage = false
    and lower(public.normalize_item_name(item_name)) = 'empty flask'
  order by parent_item_id nulls first, slot_index, created_at
  limit 1;

  if v_flask_stack.id is null then
    if v_item.quantity <= 1 and v_item.loadout_slot is null then
      v_flask_parent_id := v_item.parent_item_id;
      v_flask_slot := v_item.slot_index;
    elsif v_item.parent_item_id is not null then
      select storage_capacity into v_parent_capacity from public.inventory_items where id = v_item.parent_item_id and is_storage = true;
      v_flask_parent_id := v_item.parent_item_id;
      v_flask_slot := public.find_first_free_inventory_slot(v_character.id, v_item.parent_item_id, coalesce(v_parent_capacity, 0));
      if v_flask_slot is null then
        v_flask_parent_id := null;
        v_flask_slot := public.find_first_free_inventory_slot(v_character.id, null, v_character.inventory_slots);
      end if;
    else
      v_flask_parent_id := null;
      v_flask_slot := public.find_first_free_inventory_slot(v_character.id, null, v_character.inventory_slots);
    end if;

    if v_flask_slot is null and not coalesce(p_confirm_drop_flask, false) then
      return jsonb_build_object(
        'needsFlaskDropConfirmation', true,
        'message', 'No open inventory slot for the Empty Flask. Drink it anyway and drop the flask?'
      );
    end if;
  end if;

  if v_item.quantity <= 1 then
    delete from public.inventory_items where id = v_item.id;
  else
    update public.inventory_items set quantity = quantity - 1 where id = v_item.id;
  end if;

  if v_flask_stack.id is not null then
    update public.inventory_items set quantity = quantity + 1 where id = v_flask_stack.id;
  elsif v_flask_slot is not null then
    insert into public.inventory_items (
      character_id, parent_item_id, slot_index, item_name, item_type, rarity, quantity,
      is_storage, storage_capacity, modifiers, enchantment, material, enhancement_count,
      is_two_handed, potion_strength, potion_property, potion_quality
    )
    values (
      v_character.id, v_flask_parent_id, v_flask_slot, 'Empty Flask', 'potion', 'Common', 1,
      false, 0, '{}'::jsonb, null, '', 0, false, null, null, null
    );
  else
    v_flask_dropped := true;
  end if;

  if v_effect = 'health' then
    update public.characters set current_hp = v_new_value where id = v_character.id;
    update public.combatants cb
    set current_hp = v_new_value
    from public.battles b
    where b.id = cb.battle_id
      and b.status = 'active'
      and cb.character_id = v_character.id;
  elsif v_effect = 'mana' then
    update public.characters set current_mana = v_new_value where id = v_character.id;
    update public.combatants cb
    set current_mana = v_new_value
    from public.battles b
    where b.id = cb.battle_id
      and b.status = 'active'
      and cb.character_id = v_character.id;
  end if;

  return jsonb_build_object(
    'needsFlaskDropConfirmation', false,
    'flaskDropped', v_flask_dropped,
    'effect', jsonb_build_object('type', v_effect, 'amount', v_amount, 'newValue', v_new_value),
    'inventory', public.get_character_inventory(p_session_token, v_character.id)
  );
end;
$$;

grant execute on function public.city_record_to_json(public.cities) to anon, authenticated;
grant execute on function public.assert_valid_character_location(text) to anon, authenticated;
grant execute on function public.currency_coin_value(text) to anon, authenticated;
grant execute on function public.currency_unit_value(text, text) to anon, authenticated;
grant execute on function public.wallet_total_coin(uuid) to anon, authenticated;
grant execute on function public.wallet_total_currency(uuid, text) to anon, authenticated;
grant execute on function public.set_wallet_from_coin_value(uuid, int) to anon, authenticated;
grant execute on function public.set_wallet_from_currency_value(uuid, text, int) to anon, authenticated;
grant execute on function public.credit_character_wallet_value(uuid, text, int) to anon, authenticated;
grant execute on function public.ensure_dm_testing_wallet(uuid) to anon, authenticated;
grant execute on function public.get_discovered_cities(text) to anon, authenticated;
grant execute on function public.purchase_market_product(text, uuid, uuid, numeric, text) to anon, authenticated;
grant execute on function public.update_city_access(text, text, jsonb) to anon, authenticated;
grant execute on function public.update_market_product(text, uuid, jsonb) to anon, authenticated;
grant execute on function public.forge_material_modifiers(text, text) to anon, authenticated;
grant execute on function public.upsert_dragon_scale_fragment(text, text, text, int) to anon, authenticated;
grant execute on function public.upsert_material_conversion_recipe(text, text, text, text, text, text, numeric, int) to anon, authenticated;
grant execute on function public.material_conversion_recipe_to_json(public.material_conversion_recipes) to anon, authenticated;
grant execute on function public.material_conversion_recipe_matches_item(public.material_conversion_recipes, public.inventory_items) to anon, authenticated;
grant execute on function public.material_conversion_two_handed(text, text) to anon, authenticated;
grant execute on function public.grant_material_conversion_item(uuid, text, text, public.item_rarity, numeric, text, jsonb, boolean) to anon, authenticated;
grant execute on function public.jursh_conversion_item_has_extras(public.inventory_items, public.material_conversion_recipes) to anon, authenticated;
grant execute on function public.is_jursh_conversion_character(public.characters) to anon, authenticated;
grant execute on function public.assert_jursh_conversion_access(public.profiles, uuid) to anon, authenticated;
grant execute on function public.dragon_scale_fragment_names() to anon, authenticated;
grant execute on function public.dragon_scale_fragment_matches(text) to anon, authenticated;
grant execute on function public.consume_accessible_dragon_scale_fragments(uuid, text, numeric) to anon, authenticated;
grant execute on function public.consume_dragon_scale_fragment_selections(uuid, text, jsonb, numeric) to anon, authenticated;
grant execute on function public.get_jursh_conversion_state(text, uuid) to anon, authenticated;
grant execute on function public.convert_jursh_item_to_scales(text, uuid, uuid, boolean, numeric) to anon, authenticated;
grant execute on function public.consume_jursh_scale_by_name(uuid, text, numeric) to anon, authenticated;
grant execute on function public.convert_jursh_scales_to_item(text, uuid, text) to anon, authenticated;
grant execute on function public.convert_jursh_selected_scales_to_item(text, uuid, text, jsonb) to anon, authenticated;
grant execute on function public.forge_dragonscale_scale_from_dragon_scales(text, uuid, text, jsonb) to anon, authenticated;
grant execute on function public.enchantment_spell_for_rune(text, int, int) to anon, authenticated;
grant execute on function public.assert_character_can_use_vendor(public.characters, text) to anon, authenticated;
grant execute on function public.resolve_character_location(text, text) to anon, authenticated;
grant execute on function public.character_is_in_city(public.characters, text) to anon, authenticated;
grant execute on function public.characters_share_location(public.characters, public.characters) to anon, authenticated;
grant execute on function public.crafting_house_is_accessible(uuid, text) to anon, authenticated;
grant execute on function public.house_item_quantity_by_name(uuid, text, text) to anon, authenticated;
grant execute on function public.accessible_item_quantity_by_name(uuid, text, text) to anon, authenticated;
grant execute on function public.consume_crafting_item_by_name(uuid, text, numeric, text) to anon, authenticated;
grant execute on function public.update_player_house(text, uuid, jsonb) to anon, authenticated;
grant execute on function public.delete_player_house(text, uuid) to anon, authenticated;
grant execute on function public.set_player_house_permissions(text, uuid, jsonb) to anon, authenticated;
grant execute on function public.consume_forge_materials(uuid, uuid, numeric, int, text, text) to anon, authenticated;
grant execute on function public.run_blacksmith_action(text, uuid, text, text, uuid, uuid, uuid, text, int, jsonb, text, text) to anon, authenticated;
grant execute on function public.run_armory_action(text, uuid, text, text, uuid, uuid, uuid, text, jsonb, text, text) to anon, authenticated;
grant execute on function public.crafting_selection_item(uuid, text, uuid, text) to anon, authenticated;
grant execute on function public.consume_crafting_selection(uuid, text, uuid, numeric, text) to anon, authenticated;
grant execute on function public.brewery_available_items(uuid, text) to anon, authenticated;
grant execute on function public.get_brewery_state(text, uuid, text) to anon, authenticated;
grant execute on function public.brew_potion(text, uuid, text, text, jsonb, jsonb, jsonb, text) to anon, authenticated;
grant execute on function public.consume_inventory_potion(text, uuid, boolean) to anon, authenticated;

update public.market_products
set item_name = 'Mountain Rune',
    catalog_item_key = 'mountain-rune'
where (lower(item_name) = 'mountian rune'
   or product_key = 'blacksmith-mountian-rune')
  and not exists (select 1 from public.app_data_repairs where repair_key = 'calostrynn-shop-defaults-preexisting-2026-08-24');

update public.market_products
set item_type = 'rune',
    rarity = 'Epic',
    quantity_step = 1
where lower(item_name) in ('ember rune', 'frost rune', 'lightning rune', 'earth rune', 'wind rune', 'mountain rune')
  and not exists (select 1 from public.app_data_repairs where repair_key = 'calostrynn-shop-defaults-preexisting-2026-08-24');

update public.market_products
set item_type = 'rune',
    rarity = 'Mythical',
    quantity_step = 1
where lower(item_name) = 'void rune'
  and not exists (select 1 from public.app_data_repairs where repair_key = 'calostrynn-shop-defaults-preexisting-2026-08-24');

update public.market_products
set item_type = 'material',
    quantity_step = 1
where lower(item_name) in ('bronze scale', 'iron scale', 'steel scale', 'mythril scale', 'vaylium scale', 'dragonscale scale')
  and not exists (select 1 from public.app_data_repairs where repair_key = 'calostrynn-shop-defaults-preexisting-2026-08-24');

update public.market_products
set description = 'Dragonscale: +2 Strength and +3 Magic Resist for weapons; +2 Vitality and +3 Magic Resist for shields; +2 Vitality and +5 Magic Resist for armor.'
where product_key = 'blacksmith-dragonscale-scale'
  and description like '%+5 Magic Resist for shields%'
  and not exists (select 1 from public.app_data_repairs where repair_key = 'calostrynn-shop-defaults-preexisting-2026-08-24');

update public.item_catalog
set item_name = 'Mountain Rune',
    item_key = 'mountain-rune'
where lower(item_name) = 'mountian rune';

update public.item_catalog
set item_type = 'rune',
    rarity = 'Epic',
    quantity_step = 1
where lower(item_name) in ('ember rune', 'frost rune', 'lightning rune', 'earth rune', 'wind rune', 'mountain rune');

update public.item_catalog
set item_type = 'rune',
    rarity = 'Mythical',
    quantity_step = 1
where lower(item_name) = 'void rune';

update public.inventory_items
set item_name = case when lower(item_name) = 'mountian rune' then 'Mountain Rune' else item_name end,
    item_type = case when lower(item_name) like '%rune' then 'rune' else item_type end,
    rarity = case
      when lower(item_name) in ('void rune') then 'Mythical'::public.item_rarity
      when lower(item_name) in ('ember rune', 'frost rune', 'lightning rune', 'earth rune', 'wind rune', 'mountain rune', 'mountian rune') then 'Epic'::public.item_rarity
      else rarity
    end
where lower(item_name) in ('ember rune', 'frost rune', 'lightning rune', 'earth rune', 'wind rune', 'mountain rune', 'mountian rune', 'void rune');

update public.house_inventory_items
set item_name = case when lower(item_name) = 'mountian rune' then 'Mountain Rune' else item_name end,
    item_type = case when lower(item_name) like '%rune' then 'rune' else item_type end,
    rarity = case
      when lower(item_name) in ('void rune') then 'Mythical'::public.item_rarity
      when lower(item_name) in ('ember rune', 'frost rune', 'lightning rune', 'earth rune', 'wind rune', 'mountain rune', 'mountian rune') then 'Epic'::public.item_rarity
      else rarity
    end
where lower(item_name) in ('ember rune', 'frost rune', 'lightning rune', 'earth rune', 'wind rune', 'mountain rune', 'mountian rune', 'void rune');

update public.loot_items
set item_name = case when lower(item_name) = 'mountian rune' then 'Mountain Rune' else item_name end,
    item_type = case when lower(item_name) like '%rune' then 'rune' else item_type end,
    rarity = case
      when lower(item_name) in ('void rune') then 'Mythical'::public.item_rarity
      when lower(item_name) in ('ember rune', 'frost rune', 'lightning rune', 'earth rune', 'wind rune', 'mountain rune', 'mountian rune') then 'Epic'::public.item_rarity
      else rarity
    end
where lower(item_name) in ('ember rune', 'frost rune', 'lightning rune', 'earth rune', 'wind rune', 'mountain rune', 'mountian rune', 'void rune');

update public.inventory_items
set modifiers = jsonb_set(
      coalesce(modifiers, '{}'::jsonb),
      '{magic_resist}',
      to_jsonb(greatest(3, coalesce((modifiers->>'magic_resist')::int, 0) - 2)),
      true
    )
where item_type = 'shield'
  and lower(coalesce(material, '') || ' ' || item_name) like '%dragonscale%'
  and modifiers ? 'magic_resist'
  and coalesce((modifiers->>'magic_resist')::int, 0) >= 5;

update public.inventory_items
set item_name = 'Leather Armor',
    item_type = 'armor',
    rarity = 'Common',
    material = 'Leather',
    modifiers = coalesce(modifiers, '{}'::jsonb) || jsonb_build_object('vitality', -1)
where lower(item_name) in ('light armor', 'leather armor');

update public.inventory_items
set item_type = 'armor',
    rarity = 'Common',
    material = 'Iron',
    modifiers = coalesce(modifiers, '{}'::jsonb) || jsonb_build_object('agility', -1)
where lower(item_name) = 'iron armor';

update public.inventory_items
set item_type = 'armor',
    rarity = 'Uncommon',
    material = 'Steel',
    modifiers = coalesce(modifiers, '{}'::jsonb) || jsonb_build_object('vitality', 1)
where lower(item_name) = 'steel armor';

update public.inventory_items
set item_type = 'armor',
    rarity = 'Rare',
    material = 'Mythril'
where lower(item_name) = 'mythril armor';

update public.inventory_items
set item_type = 'armor',
    rarity = 'Epic',
    material = 'Vaylium',
    modifiers = coalesce(modifiers, '{}'::jsonb) || jsonb_build_object('intelligence', 3, 'magic_resist', 1)
where lower(item_name) = 'vaylium armor';

update public.inventory_items
set item_type = 'armor',
    rarity = 'Legendary',
    material = 'Dragonscale',
    modifiers = coalesce(modifiers, '{}'::jsonb) || jsonb_build_object('vitality', 2, 'magic_resist', 5)
where lower(item_name) = 'dragonscale armor';


