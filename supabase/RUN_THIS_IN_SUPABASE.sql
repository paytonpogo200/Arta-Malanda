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

alter table public.inventory_items drop constraint if exists inventory_items_slot_index_check;
alter table public.inventory_items drop constraint if exists inventory_items_visible_or_storage_slot_check;
alter table public.inventory_items drop constraint if exists inventory_item_type_valid;
alter table public.inventory_items drop constraint if exists inventory_items_item_type_valid;
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

alter table public.inventory_items
  alter column item_type type text using item_type::text,
  alter column quantity type numeric(12,1) using quantity::numeric;

alter table public.inventory_items
  add column if not exists display_name text,
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
  created_at timestamptz not null default now(),
  unique (battle_id, character_id)
);

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
  is_unlocked boolean not null default false,
  display_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.bestiary_entities
drop constraint if exists bestiary_entities_category_check;

alter table public.bestiary_entities
add column if not exists stats jsonb not null default '{}'::jsonb;

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
    values (v_category_key, initcap(replace(v_category_key, '-', ' ')), 1000)
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
    display_order = case when v_patch ? 'order' then (v_patch->>'order')::int else display_order end
  where id = p_entity_id;

  return public.get_bestiary(p_session_token);
end;
$$;


grant execute on function public.bestiary_category_record_to_json(public.bestiary_categories) to anon, authenticated;
grant execute on function public.bestiary_entity_record_to_json(public.bestiary_entities) to anon, authenticated;
grant execute on function public.bestiary_stat_number(jsonb, text[]) to anon, authenticated;
grant execute on function public.get_bestiary(text) to anon, authenticated;
grant execute on function public.update_bestiary_category(text, text, jsonb) to anon, authenticated;
grant execute on function public.update_bestiary_entity(text, uuid, jsonb) to anon, authenticated;


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
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;
  if v_profile.role <> 'dm'::public.user_role then raise exception 'Only the Dungeon Master can import the bestiary.'; end if;

  delete from public.bestiary_entities where true;
  delete from public.bestiary_categories where true;

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

drop function if exists public.import_bestiary_markdown(text, jsonb, jsonb);
drop function if exists public.is_retired_bestiary_category(text);
drop function if exists public.purge_retired_bestiary_categories();
grant execute on function public.import_bestiary_workbook(text, jsonb, jsonb) to anon, authenticated;


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
    'Calostrynn'
  )
  returning * into v_character;

  perform public.ensure_character_starter_armor(v_character.id);

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
    location_name = case when v_patch ? 'locationName' then coalesce(nullif(trim(v_patch->>'locationName'), ''), location_name) else location_name end
  where id = p_character_id
  returning * into v_character;

  return public.character_record_to_json(v_character);
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
      'quest',
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
    when lower(trim(coalesce(p_item_type, ''))) in ('pet', 'storage') then false
    else coalesce((
      select c.is_stackable
      from public.item_catalog c
      where c.item_key = public.catalog_key_for_name(p_item_name)
        and c.is_active = true
      limit 1
    ), true)
  end
$$;

create or replace function public.catalog_storage_capacity(p_item_name text)
returns int
language sql
stable
as $$
  select case
    when lower(coalesce(p_item_name, '')) like '%bag of holding%' then 100
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
  p_display_order int default 0
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
  perform public.upsert_item_catalog_entry('History Book', 'quest', 'Common', 'Books', array['Table-resolved contents']::text[], 1, true, '{}'::jsonb, '', false, 0, 'A general history volume. Resolve its contents at the table.', true, 6);
  perform public.upsert_item_catalog_entry('Alchemy Book', 'quest', 'Common', 'Books', array['Table-resolved contents']::text[], 1, true, '{}'::jsonb, '', false, 0, 'An alchemical study text. Resolve its contents at the table.', true, 7);
  perform public.upsert_item_catalog_entry('Bestiary', 'quest', 'Common', 'Books', array['Table-resolved contents']::text[], 1, true, '{}'::jsonb, '', false, 0, 'A creature reference volume. Resolve its contents at the table.', true, 8);
  perform public.upsert_item_catalog_entry('Magical Research', 'quest', 'Rare', 'Books', array['Research voucher']::text[], 1, true, '{}'::jsonb, '', false, 0, 'Choose a spell category at purchase to receive a rare magic spell book.', true, 9);
  perform public.upsert_item_catalog_entry('Ember Magic Spell Book', 'quest', 'Rare', 'Books', array['Ember research']::text[], 1, true, '{}'::jsonb, '', false, 0, 'A rare Ember magic spell book from library research.', true, 10);
  perform public.upsert_item_catalog_entry('Frost Magic Spell Book', 'quest', 'Rare', 'Books', array['Frost research']::text[], 1, true, '{}'::jsonb, '', false, 0, 'A rare Frost magic spell book from library research.', true, 11);
  perform public.upsert_item_catalog_entry('Lightning Magic Spell Book', 'quest', 'Rare', 'Books', array['Lightning research']::text[], 1, true, '{}'::jsonb, '', false, 0, 'A rare Lightning magic spell book from library research.', true, 12);
  perform public.upsert_item_catalog_entry('Earth Magic Spell Book', 'quest', 'Rare', 'Books', array['Earth research']::text[], 1, true, '{}'::jsonb, '', false, 0, 'A rare Earth magic spell book from library research.', true, 13);
  perform public.upsert_item_catalog_entry('Wind Magic Spell Book', 'quest', 'Rare', 'Books', array['Wind research']::text[], 1, true, '{}'::jsonb, '', false, 0, 'A rare Wind magic spell book from library research.', true, 14);
  perform public.upsert_item_catalog_entry('Energy Magic Spell Book', 'quest', 'Rare', 'Books', array['Energy research']::text[], 1, true, '{}'::jsonb, '', false, 0, 'A rare Energy magic spell book from library research.', true, 15);
  perform public.upsert_item_catalog_entry('Defensive Support Magic Spell Book', 'quest', 'Rare', 'Books', array['Defensive Support research']::text[], 1, true, '{}'::jsonb, '', false, 0, 'A rare Defensive Support magic spell book from library research.', true, 16);
  perform public.upsert_item_catalog_entry('Offensive Support Magic Spell Book', 'quest', 'Rare', 'Books', array['Offensive Support research']::text[], 1, true, '{}'::jsonb, '', false, 0, 'A rare Offensive Support magic spell book from library research.', true, 17);
  perform public.upsert_item_catalog_entry('Enhancement Magic Spell Book', 'quest', 'Rare', 'Books', array['Enhancement research']::text[], 1, true, '{}'::jsonb, '', false, 0, 'A rare Enhancement magic spell book from library research.', true, 18);
  perform public.upsert_item_catalog_entry('Utility Magic Spell Book', 'quest', 'Rare', 'Books', array['Utility research']::text[], 1, true, '{}'::jsonb, '', false, 0, 'A rare Utility magic spell book from library research.', true, 19);
  perform public.upsert_item_catalog_entry('Waist Pouch', 'storage', 'Common', 'Market Storage', array['1 storage slot']::text[], 1, false, '{}'::jsonb, '', false, 1, 'A compact pouch with 1 storage slot.', true, 2000);
  perform public.upsert_item_catalog_entry('Back Bag', 'storage', 'Common', 'Market Storage', array['3 storage slots']::text[], 1, false, '{}'::jsonb, '', false, 3, 'A back bag with 3 storage slots.', true, 2010);
  perform public.upsert_item_catalog_entry('Light Duffle', 'storage', 'Uncommon', 'Market Storage', array['6 storage slots']::text[], 1, false, '{}'::jsonb, '', false, 6, 'A light duffle with 6 storage slots.', true, 2020);
  perform public.upsert_item_catalog_entry('Heavy Duffle', 'storage', 'Rare', 'Market Storage', array['10 storage slots']::text[], 1, false, '{}'::jsonb, '', false, 10, 'A heavy duffle with 10 storage slots.', true, 2030);
  perform public.upsert_item_catalog_entry('Bag of Holding', 'storage', 'Mythical', 'Market Storage', array['100 storage slots']::text[], 1, false, '{}'::jsonb, '', false, 100, 'A magical bag with 100 storage slots.', true, 2040);
  perform public.upsert_item_catalog_entry('Light Wagon', 'storage', 'Rare', 'Market Storage', array['25 storage slots']::text[], 1, false, '{}'::jsonb, '', false, 25, 'A light wagon with 25 storage slots.', true, 2050);
  perform public.upsert_item_catalog_entry('Heavy Wagon', 'storage', 'Epic', 'Market Storage', array['60 storage slots']::text[], 1, false, '{}'::jsonb, '', false, 60, 'A heavy wagon with 60 storage slots.', true, 2060);
  perform public.upsert_item_catalog_entry('Torch', 'tool', 'Common', 'Market Supplies', array['Travel supply']::text[], 1, true, '{}'::jsonb, '', false, 0, 'A basic torch for travel and dungeon work.', true, 2070);
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
  perform public.upsert_item_catalog_entry('Dog', 'pet', 'Epic', 'Market Stable', array['Pet']::text[], 1, false, '{}'::jsonb, '', false, 0, 'A loyal dog.', true, 2300);

  update public.item_catalog
  set storage_capacity = case item_key
    when 'waist-pouch' then 1
    when 'back-bag' then 3
    when 'light-duffle' then 6
    when 'heavy-duffle' then 10
    when 'bag-of-holding' then 100
    when 'light-wagon' then 25
    when 'heavy-wagon' then 60
    else storage_capacity
  end
  where item_key in ('waist-pouch', 'back-bag', 'light-duffle', 'heavy-duffle', 'bag-of-holding', 'light-wagon', 'heavy-wagon');

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
  ('Speed', 'Swiftness', 'Improves speed. Resolve the exact effect at the table.', '', 20),
  ('Agility', 'Agility', 'Improves agility. Resolve the exact effect at the table.', '', 30),
  ('Strength', 'Strength', 'Improves strength. Resolve the exact effect at the table.', '', 40),
  ('Sorcery', 'Sorcery', 'Improves sorcery and intelligence. Resolve the exact effect at the table.', '', 50),
  ('Mana Regen', 'Mana', 'Restores mana when consumed.', 'mana', 60),
  ('Luck', 'Luck', 'Improves luck rolls. Resolve the exact effect at the table.', '', 70),
  ('Antidote', 'Antidote', 'Handles poison effects. Resolve the exact effect at the table.', '', 80),
  ('Warming', 'Warming', 'Protects against cold. Resolve the exact effect at the table.', '', 90),
  ('Cooling', 'Cooling', 'Protects against heat. Resolve the exact effect at the table.', '', 100),
  ('Night-Eye', 'Night-Eye', 'Improves sight in darkness. Resolve the exact effect at the table.', '', 110),
  ('Thickskin', 'Thickskin', 'Improves protection. Resolve the exact effect at the table.', '', 120),
  ('Clear-Mind', 'Clear-Mind', 'Improves magical resistance. Resolve the exact effect at the table.', '', 130),
  ('Wake-Up', 'Wake-Up', 'Wakes a target. Resolve the exact effect at the table.', '', 140),
  ('Clotting', 'Clotting', 'Handles bleeding. Resolve the exact effect at the table.', '', 150)
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
        public.potion_rarity_for_strength(v_strength.strength_name)::text,
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
    'storageCapacity', p_item.storage_capacity,
    'modifiers', p_item.modifiers,
    'enchantment', p_item.enchantment,
    'runeName', p_item.rune_name,
    'material', p_item.material,
    'enhancementCount', p_item.enhancement_count,
    'isTwoHanded', p_item.is_two_handed,
    'potionStrength', p_item.potion_strength,
    'potionProperty', p_item.potion_property,
    'potionQuality', p_item.potion_quality
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
      and i.is_storage = true;

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
      and lower(i.item_name) = lower(trim(coalesce(p_item_name, '')))
  )
$$;

with duplicate_empty_storage as (
  select id
  from (
    select i.id,
      row_number() over (
        partition by i.character_id, lower(i.item_name)
        order by i.created_at, i.id
      ) as duplicate_rank
    from public.inventory_items i
    where i.parent_item_id is null
      and i.loadout_slot is null
      and i.item_type = 'storage'::text
      and i.is_storage = true
  ) ranked
  where duplicate_rank > 1
    and not exists (
      select 1 from public.inventory_items child where child.parent_item_id = ranked.id
    )
)
update public.inventory_items i
set is_storage = false,
    storage_capacity = 0
where i.id in (select id from duplicate_empty_storage);

with active_storage as (
  select i.id,
    row_number() over (partition by i.character_id order by i.created_at, i.id) as storage_rank
  from public.inventory_items i
  where i.parent_item_id is null
    and i.loadout_slot is null
    and i.item_type = 'storage'::text
    and i.is_storage = true
)
update public.inventory_items i
set slot_index = -100000 - active_storage.storage_rank
from active_storage
where i.id = active_storage.id;

with active_storage as (
  select i.id,
    row_number() over (partition by i.character_id order by i.created_at, i.id) as storage_rank
  from public.inventory_items i
  where i.parent_item_id is null
    and i.loadout_slot is null
    and i.item_type = 'storage'::text
    and i.is_storage = true
)
update public.inventory_items i
set slot_index = -active_storage.storage_rank
from active_storage
where i.id = active_storage.id;

create or replace function public.inventory_items_stackable(a public.inventory_items, b public.inventory_items)
returns boolean
language sql
stable
as $$
  select a.item_name = b.item_name
    and coalesce(a.display_name, '') = coalesce(b.display_name, '')
    and coalesce(a.item_description, '') = coalesce(b.item_description, '')
    and a.item_type = b.item_type
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
      v_rarity := public.potion_rarity_for_strength(v_potion_strength);
    end if;
  end if;

  v_quantity := public.assert_valid_item_quantity(v_item_name, v_item_type, v_quantity);

  v_make_storage_container := v_item_type = 'storage'::text
    and coalesce(p_is_storage, false)
    and p_parent_item_id is null
    and not public.character_storage_container_exists(p_character_id, v_item_name);

  if v_make_storage_container then
    insert into public.inventory_items (
      character_id, parent_item_id, slot_index, item_name, item_type, rarity, quantity,
      item_description, is_accessory, is_storage, storage_capacity, modifiers, enchantment, material, enhancement_count,
      is_two_handed, potion_strength, potion_property, potion_quality
    )
    values (
      p_character_id, null, public.next_storage_container_slot(p_character_id), v_item_name, v_item_type, v_rarity, 1,
      v_item_description, v_is_accessory, true, greatest(1, coalesce(nullif(v_storage_capacity, 0), 6)), v_modifiers,
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
    if v_target.item_name = v_item_name
      and coalesce(v_target.display_name, '') = ''
      and v_target.item_type = v_item_type
      and v_target.rarity = v_rarity
      and coalesce(v_target.item_description, '') = coalesce(v_item_description, '')
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
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;

  select * into v_item from public.inventory_items where id = p_item_id;
  if v_item.id is null then raise exception 'Item not found.'; end if;

  v_character := public.assert_inventory_access(v_profile, v_item.character_id, false);

  if (v_patch ? 'name' or v_patch ? 'type' or v_patch ? 'rarity' or v_patch ? 'quantity' or v_patch ? 'isStorage' or v_patch ? 'isAccessory' or v_patch ? 'storageCapacity' or v_patch ? 'modifiers' or v_patch ? 'enchantment' or v_patch ? 'material' or v_patch ? 'enhancementCount' or v_patch ? 'isTwoHanded' or v_patch ? 'potionStrength' or v_patch ? 'potionProperty' or v_patch ? 'potionQuality' or v_patch ? 'itemDescription') and v_profile.role <> 'dm'::public.user_role then
    raise exception 'Only the Dungeon Master can edit item details.';
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
      end
    where id = p_item_id
    returning * into v_item;

    if v_item.item_type = 'potion'
      and v_item.potion_strength is not null
      and v_item.potion_property is not null
    then
      update public.inventory_items
      set item_name = public.format_potion_item_name(v_item.potion_strength, v_item.potion_property, v_item.potion_quality),
          rarity = public.potion_rarity_for_strength(v_item.potion_strength)
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

  if v_patch ? 'loadoutSlot' then
    v_loadout_slot := nullif(v_patch->>'loadoutSlot', '');

    if v_loadout_slot is null then
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

    update public.inventory_items
    set parent_item_id = v_parent_item_id, slot_index = -1000000
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

grant execute on function public.loadout_slot_accepts_item(text, text, boolean) to anon, authenticated;
grant execute on function public.item_catalog_stackable(text, text) to anon, authenticated;
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
grant execute on function public.add_character_inventory_item(text, uuid, uuid, int, text, text, text, numeric, boolean, int, jsonb, text, text, int, boolean, text, text, text, text, boolean) to anon, authenticated;
grant execute on function public.update_inventory_item_state(text, uuid, jsonb) to anon, authenticated;
grant execute on function public.drop_inventory_item_quantity(text, uuid, numeric) to anon, authenticated;
grant execute on function public.split_inventory_item_stack(text, uuid, numeric, boolean) to anon, authenticated;
grant execute on function public.set_character_wallet_balances(text, uuid, jsonb) to anon, authenticated;


-- ============================================================
-- ============================================================

-- House, property, and storage foundation.

create table if not exists public.player_houses (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null unique references public.profiles(id) on delete cascade,
  city_name text not null default 'Calostrynn',
  inventory_slots int not null default 45 check (inventory_slots between 0 and 500),
  stable_slots int not null default 5 check (stable_slots between 0 and 200),
  property_slots int not null default 10 check (property_slots between 0 and 200),
  is_locked boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
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
  slot_index int not null default 0 check (slot_index >= 0),
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
  add constraint house_inventory_items_slot_index_check check (slot_index >= -1);

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

create unique index if not exists house_inventory_root_slot_unique
  on public.house_inventory_items (owner_user_id, slot_index)
  where parent_item_id is null;

create unique index if not exists house_inventory_parent_slot_unique
  on public.house_inventory_items (parent_item_id, slot_index)
  where parent_item_id is not null;

create index if not exists house_inventory_parent_idx on public.house_inventory_items(parent_item_id);

alter table public.player_houses
  add column if not exists is_locked boolean not null default false,
  add column if not exists stable_slots int not null default 5 check (stable_slots between 0 and 200);

alter table public.player_houses
  alter column inventory_slots set default 45,
  alter column stable_slots set default 5;

update public.player_houses
set inventory_slots = 45,
    stable_slots = case
      when exists (
        select 1
        from public.profiles p
        where p.id = public.player_houses.owner_user_id
          and (lower(p.username::text) = 'm0' or lower(p.display_name) = 'm0')
      ) or exists (
        select 1
        from public.characters c
        where c.owner_user_id = public.player_houses.owner_user_id
          and lower(c.name) in ('toren', 'rylas', 'halric')
      )
        then 20
      else 5
    end
where inventory_slots <> 45
   or stable_slots <> case
      when exists (
        select 1
        from public.profiles p
        where p.id = public.player_houses.owner_user_id
          and (lower(p.username::text) = 'm0' or lower(p.display_name) = 'm0')
      ) or exists (
        select 1
        from public.characters c
        where c.owner_user_id = public.player_houses.owner_user_id
          and lower(c.name) in ('toren', 'rylas', 'halric')
      )
        then 20
      else 5
    end;

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

with ranked_house_items as (
  select i.id,
    row_number() over (partition by i.owner_user_id order by greatest(i.slot_index, 0), i.created_at, i.id) as item_rank
  from public.house_inventory_items i
  where i.parent_item_id is null
    and i.item_type <> 'pet'
    and i.slot_index >= 0
)
update public.house_inventory_items i
set slot_index = 200000 + ranked_house_items.item_rank
from ranked_house_items
where i.id = ranked_house_items.id;

with ranked_house_pets as (
  select i.id,
    row_number() over (partition by i.owner_user_id order by greatest(i.slot_index, 0), i.created_at, i.id) as pet_rank
  from public.house_inventory_items i
  where i.parent_item_id is null
    and i.item_type = 'pet'
)
update public.house_inventory_items i
set slot_index = 300000 + ranked_house_pets.pet_rank
from ranked_house_pets
where i.id = ranked_house_pets.id;

with ranked_house_items as (
  select i.id,
    row_number() over (partition by i.owner_user_id order by i.slot_index, i.created_at, i.id) as item_rank
  from public.house_inventory_items i
  where i.parent_item_id is null
    and i.item_type <> 'pet'
    and i.slot_index >= 200000
)
update public.house_inventory_items i
set slot_index = case
  when ranked_house_items.item_rank <= 45 then ranked_house_items.item_rank - 1
  else 200000 + ranked_house_items.item_rank
end
from ranked_house_items
where i.id = ranked_house_items.id;

with ranked_house_pets as (
  select i.id,
    i.owner_user_id,
    coalesce(h.stable_slots, 5) as stable_slots,
    row_number() over (partition by i.owner_user_id order by i.slot_index, i.created_at, i.id) as pet_rank
  from public.house_inventory_items i
  join public.player_houses h on h.owner_user_id = i.owner_user_id
  where i.parent_item_id is null
    and i.item_type = 'pet'
    and i.slot_index >= 300000
)
update public.house_inventory_items i
set slot_index = case
  when ranked_house_pets.pet_rank <= ranked_house_pets.stable_slots then 45 + ranked_house_pets.pet_rank - 1
  else 300000 + ranked_house_pets.pet_rank
end
from ranked_house_pets
where i.id = ranked_house_pets.id;

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
alter table public.house_inventory_items enable row level security;
alter table public.campaign_properties enable row level security;
alter table public.wagon_activity_log enable row level security;

revoke all on public.player_houses from anon, authenticated;
revoke all on public.house_inventory_items from anon, authenticated;
revoke all on public.campaign_properties from anon, authenticated;
revoke all on public.wagon_activity_log from anon, authenticated;

drop trigger if exists player_houses_touch_updated_at on public.player_houses;
create trigger player_houses_touch_updated_at
before update on public.player_houses
for each row execute function public.touch_updated_at();

drop trigger if exists house_inventory_items_touch_updated_at on public.house_inventory_items;
create trigger house_inventory_items_touch_updated_at
before update on public.house_inventory_items
for each row execute function public.touch_updated_at();

drop trigger if exists campaign_properties_touch_updated_at on public.campaign_properties;
create trigger campaign_properties_touch_updated_at
before update on public.campaign_properties
for each row execute function public.touch_updated_at();

create or replace function public.ensure_player_house(p_owner_user_id uuid)
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

  insert into public.player_houses (owner_user_id)
  values (p_owner_user_id)
  on conflict (owner_user_id) do update
  set owner_user_id = excluded.owner_user_id
  returning * into v_house;

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

  if not p_dm_only and p_profile.role <> 'dm'::public.user_role and p_owner_user_id is distinct from p_profile.id then
    raise exception 'You can only manage your own house.';
  end if;

  v_house := public.ensure_player_house(p_owner_user_id);
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
    'potionQuality', p_item.potion_quality
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

create or replace function public.house_inventory_items_stackable(a public.house_inventory_items, b public.house_inventory_items)
returns boolean
language sql
stable
as $$
  select a.item_name = b.item_name
    and coalesce(a.display_name, '') = coalesce(b.display_name, '')
    and coalesce(a.item_description, '') = coalesce(b.item_description, '')
    and a.item_type = b.item_type
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
  select 45
$$;

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
      where i.owner_user_id = p_owner_user_id
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
  v_capacity int;
  v_stable_start int := public.house_stable_slot_offset();
begin
  if p_slot_index < 0 then
    raise exception 'House slot is invalid.';
  end if;

  if p_parent_item_id is null and p_slot_index >= v_stable_start then
    if public.normalize_item_type(p_item_type) <> 'pet' then
      raise exception 'Only animals can be placed in stable slots.';
    end if;

    if p_slot_index >= v_stable_start + p_house.stable_slots then
      raise exception 'Stable slot is outside the stable capacity.';
    end if;

    return p_house.stable_slots;
  end if;

  v_capacity := public.assert_house_slot_capacity(p_house, p_parent_item_id, p_slot_index);

  if p_parent_item_id is null
    and p_slot_index >= p_house.inventory_slots
  then
    raise exception 'Only animals can be placed in stable slots.';
  end if;

  return v_capacity;
end;
$$;

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
      v_rarity := public.potion_rarity_for_strength(v_potion_strength);
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
    if v_target.item_name = v_item_name
      and coalesce(v_target.display_name, '') = ''
      and v_target.item_type = v_item_type
      and v_target.rarity = v_rarity
      and coalesce(v_target.item_description, '') = v_item_description
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
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;

  select * into v_item from public.house_inventory_items where id = p_item_id;
  if v_item.id is null then raise exception 'House item not found.'; end if;

  v_house := public.assert_house_access(v_profile, v_item.owner_user_id, false);

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
    where i.owner_user_id = v_item.owner_user_id
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

      update public.house_inventory_items
      set slot_index = -1
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

  perform public.assert_house_access(v_profile, v_item.owner_user_id, false);

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

  v_house := public.ensure_player_house(v_character.owner_user_id);

  select * into v_target
  from public.house_inventory_items h
  where h.owner_user_id = v_character.owner_user_id
    and h.item_name = v_item.item_name
    and coalesce(h.display_name, '') = coalesce(v_item.display_name, '')
    and coalesce(h.item_description, '') = coalesce(v_item.item_description, '')
    and h.item_type = v_item.item_type
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

  v_house := public.ensure_player_house(v_character.owner_user_id);
  perform public.assert_house_item_slot_capacity(v_house, p_parent_item_id, p_slot_index, v_item.item_type);

  select * into v_target
  from public.house_inventory_items h
  where h.owner_user_id = v_character.owner_user_id
    and coalesce(h.parent_item_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(p_parent_item_id, '00000000-0000-0000-0000-000000000000'::uuid)
    and h.slot_index = p_slot_index
  limit 1;

  if v_target.id is not null then
    if v_target.item_name = v_item.item_name
      and coalesce(v_target.display_name, '') = coalesce(v_item.display_name, '')
      and coalesce(v_target.item_description, '') = coalesce(v_item.item_description, '')
      and v_target.item_type = v_item.item_type
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
  v_house_item public.house_inventory_items%rowtype;
  v_target public.inventory_items%rowtype;
  v_item public.inventory_items%rowtype;
  v_slot_index int;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;

  select * into v_house_item
  from public.house_inventory_items
  where id = p_house_item_id;

  if v_house_item.id is null then raise exception 'House item not found.'; end if;

  v_house := public.assert_house_access(v_profile, v_house_item.owner_user_id, false);
  v_character := public.assert_inventory_access(v_profile, p_character_id, false);

  if v_character.owner_user_id is distinct from v_house.owner_user_id then
    raise exception 'That character cannot pull from this house.';
  end if;

  if v_house_item.is_storage and exists (
    select 1 from public.house_inventory_items child where child.parent_item_id = v_house_item.id
  ) then
    raise exception 'Empty this storage item before taking it from the house.';
  end if;

  select * into v_target
  from public.inventory_items i
  where i.character_id = v_character.id
    and i.parent_item_id is null
    and i.loadout_slot is null
    and i.item_name = v_house_item.item_name
    and coalesce(i.display_name, '') = coalesce(v_house_item.display_name, '')
    and coalesce(i.item_description, '') = coalesce(v_house_item.item_description, '')
    and i.item_type = v_house_item.item_type
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
      where w.is_storage
        and public.inventory_item_is_wagon(w.item_name, w.item_type)
        and w.parent_item_id is null
        and w.loadout_slot is null
        and public.city_names_match(owner_character.location_name, v_character.location_name)
    ),
    'items', (
      select coalesce(jsonb_agg(public.inventory_item_record_to_json(child) order by child.parent_item_id, child.slot_index, child.item_name), '[]'::jsonb)
      from public.inventory_items child
      join public.inventory_items w on w.id = child.parent_item_id
      join public.characters owner_character on owner_character.id = w.character_id
      where w.is_storage
        and public.inventory_item_is_wagon(w.item_name, w.item_type)
        and w.parent_item_id is null
        and w.loadout_slot is null
        and public.city_names_match(owner_character.location_name, v_character.location_name)
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
        where w.is_storage
          and public.inventory_item_is_wagon(w.item_name, w.item_type)
          and w.parent_item_id is null
          and w.loadout_slot is null
          and public.city_names_match(owner_character.location_name, v_character.location_name)
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
  if v_wagon.id is null or not v_wagon.is_storage or not public.inventory_item_is_wagon(v_wagon.item_name, v_wagon.item_type) then
    raise exception 'Wagon storage not found.';
  end if;

  select * into v_wagon_owner from public.characters where id = v_wagon.character_id;
  if v_wagon_owner.id is null or not public.city_names_match(v_wagon_owner.location_name, v_actor.location_name) then
    raise exception 'That wagon is not in this character''s location.';
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
  if v_wagon.id is null or not v_wagon.is_storage or not public.inventory_item_is_wagon(v_wagon.item_name, v_wagon.item_type) then
    raise exception 'Wagon storage not found.';
  end if;

  select * into v_wagon_owner from public.characters where id = v_wagon.character_id;
  if v_wagon_owner.id is null or not public.city_names_match(v_wagon_owner.location_name, v_actor.location_name) then
    raise exception 'That wagon is not in this character''s location.';
  end if;

  if v_item.is_storage and exists (select 1 from public.inventory_items child where child.parent_item_id = v_item.id) then
    raise exception 'Empty this storage item before taking it from the wagon.';
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

  v_house := public.assert_house_access(v_profile, v_property.owner_user_id, false);
  v_owner_user_id := v_property.owner_user_id;
  v_location := case when v_patch ? 'location' then coalesce(nullif(v_patch->>'location', ''), v_property.property_location) else v_property.property_location end;
  v_slot_index := case when v_patch ? 'slotIndex' then greatest(0, (v_patch->>'slotIndex')::int) else v_property.slot_index end;
  v_caretaker_character_id := case when v_patch ? 'caretakerCharacterId' then nullif(v_patch->>'caretakerCharacterId', '')::uuid else v_property.caretaker_character_id end;

  if v_slot_index >= v_house.property_slots then
    raise exception 'Property slot is outside the house capacity.';
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

grant execute on function public.ensure_player_house(uuid) to anon, authenticated;
grant execute on function public.assert_house_access(public.profiles, uuid, boolean) to anon, authenticated;
grant execute on function public.house_record_to_json(public.player_houses) to anon, authenticated;
grant execute on function public.house_item_record_to_json(public.house_inventory_items) to anon, authenticated;
grant execute on function public.property_record_to_json(public.campaign_properties) to anon, authenticated;
grant execute on function public.house_inventory_items_stackable(public.house_inventory_items, public.house_inventory_items) to anon, authenticated;
grant execute on function public.inventory_item_is_wagon(text, text) to anon, authenticated;
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
grant execute on function public.get_location_wagon_storage(text, uuid) to anon, authenticated;
grant execute on function public.move_inventory_item_to_wagon(text, uuid, uuid, uuid, int) to anon, authenticated;
grant execute on function public.move_wagon_item_to_inventory(text, uuid, uuid, uuid, int) to anon, authenticated;
grant execute on function public.apply_inventory_item_rune(text, uuid, uuid, text) to anon, authenticated;
grant execute on function public.add_campaign_property(text, uuid, uuid, text, text, text, boolean, int, int) to anon, authenticated;
grant execute on function public.update_campaign_property(text, uuid, jsonb) to anon, authenticated;


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
    'initiative', p_combatant.initiative
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
      where (i.loadout_slot is not null or (i.item_type = 'weapon' and i.enchantment is not null))
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
    current_hp = case when v_patch ? 'currentHp' then greatest(0, (v_patch->>'currentHp')::int) else current_hp end,
    current_mana = case when v_patch ? 'currentMana' then greatest(0, (v_patch->>'currentMana')::int) else current_mana end,
    initiative = v_initiative
  where id = p_combatant_id
  returning * into v_combatant;

  return public.combatant_record_to_json(v_combatant);
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
  v_vitality int := 0;
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
  v_vitality := public.bestiary_stat_number(v_entity.stats, array['Vitality']);
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
      'strength', 0,
      'accuracy', 0,
      'intelligence', 0,
      'vitality', greatest(0, v_armor_hide + v_vitality),
      'recovery', 0,
      'mana_regen', 0,
      'charisma', 0,
      'wisdom_cunning', 0,
      'perception', 0,
      'alchemy', 0,
      'stealth', 0,
      'agility', 0
    ),
    jsonb_build_array(coalesce(nullif(v_entity.summary, ''), v_entity.temperament)),
    v_entity.details,
    '#7f514d',
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
grant execute on function public.combatant_record_to_json(public.combatants) to anon, authenticated;
grant execute on function public.battle_terrain_record_to_json(public.battle_terrain) to anon, authenticated;
grant execute on function public.get_battle_room(text) to anon, authenticated;
grant execute on function public.start_campaign_battle(text, uuid[], int, int) to anon, authenticated;
grant execute on function public.update_combatant_state(text, uuid, jsonb) to anon, authenticated;
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
  item_type text not null default 'misc',
  rarity public.item_rarity not null default 'Common',
  price_coin int not null default 0 check (price_coin >= 0),
  stock_quantity numeric(12,1) check (stock_quantity is null or stock_quantity >= 0),
  catalog_item_key text,
  shop_section text not null default 'Wares',
  quantity_step numeric(12,1) not null default 1 check (quantity_step in (0.5, 1)),
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
  add column if not exists shop_section text not null default 'Wares',
  add column if not exists quantity_step numeric(12,1) not null default 1 check (quantity_step in (0.5, 1));

delete from public.market_products
where product_key = 'blacksmith-mountian-rune'
  and exists (
    select 1
    from public.market_products existing
    where existing.product_key = 'blacksmith-mountain-rune'
  );

update public.market_products
set item_type = public.normalize_item_type(item_type),
    item_name = case when item_name = 'Mountian Rune' then 'Mountain Rune' else public.normalize_item_name(item_name) end,
    product_key = case when product_key = 'blacksmith-mountian-rune' then 'blacksmith-mountain-rune' else product_key end,
    catalog_item_key = case when catalog_item_key = 'mountian-rune' then 'mountain-rune' else catalog_item_key end;

update public.market_products
set item_type = 'potion',
    rarity = case when lower(item_name) = 'arcane nector' then 'Uncommon'::public.item_rarity else 'Common'::public.item_rarity end,
    quantity_step = 1
where lower(item_name) in ('empty flask', 'arcane nector');

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
on conflict (city_key) do nothing;

insert into public.shop_vendors (city_key, vendor_key, name, facility, category, display_order)
values
  ('calostrynn', 'calostrynn-armory', 'Armory Quartermaster', 'Armory', 'Arms & Armor', 20),
  ('calostrynn', 'calostrynn-brewery', 'Brewery Keeper', 'Brewery', 'Potions & Ingredients', 30),
  ('calostrynn', 'calostrynn-spells', 'Spell Registrar', 'Spell Shop', 'Spell Catalog', 40),
  ('calostrynn', 'calostrynn-library', 'The Grand Calostrynn Library', 'Library', 'Books & Research', 45),
  ('calostrynn', 'calostrynn-blacksmith', 'Blacksmith', 'Blacksmith', 'Tools & Metalwork', 50),
  ('calostrynn', 'calostrynn-city-market', 'City Market', 'Market', 'General Goods', 60)
on conflict (vendor_key) do nothing;

delete from public.shop_vendors
where city_key = 'calostrynn'
  and vendor_key not in ('calostrynn-armory', 'calostrynn-brewery', 'calostrynn-city-market', 'calostrynn-library', 'calostrynn-spells', 'calostrynn-blacksmith');

-- Replace Blacksmith placeholder wares with source-backed forge materials and runes.
with blacksmith_vendor as (select id from public.shop_vendors where vendor_key = 'calostrynn-blacksmith')
delete from public.market_products p using blacksmith_vendor v where p.vendor_id = v.id and p.product_key not in ('blacksmith-bronze-scale', 'blacksmith-iron-scale', 'blacksmith-steel-scale', 'blacksmith-mythril-scale', 'blacksmith-vaylium-scale', 'blacksmith-dragonscale-scale', 'blacksmith-ember-rune', 'blacksmith-frost-rune', 'blacksmith-lightning-rune', 'blacksmith-earth-rune', 'blacksmith-wind-rune', 'blacksmith-mountain-rune', 'blacksmith-void-rune');
with armory_vendor as (select id from public.shop_vendors where vendor_key = 'calostrynn-armory')
delete from public.market_products p using armory_vendor v where p.vendor_id = v.id and p.product_key not in ('armory-bronze-scale', 'armory-iron-scale', 'armory-steel-scale', 'armory-mythril-scale', 'armory-vaylium-scale', 'armory-dragonscale-scale');
insert into public.market_products (vendor_id, product_key, item_name, description, item_type, rarity, price_coin, stock_quantity, shop_section, quantity_step, catalog_item_key, is_available, display_order)
select v.id, seed.product_key, seed.item_name, seed.description, public.normalize_item_type(seed.item_type), seed.rarity::public.item_rarity, seed.price_coin, seed.stock_quantity::numeric, seed.shop_section, seed.quantity_step::numeric, seed.catalog_item_key, seed.is_available, seed.display_order
from public.shop_vendors v
join (values
  ('blacksmith-bronze-scale', 'Bronze Scale', 'Bronze: -1 Strength when used for weapons; +1 Vitality when used for shields.', 'material', 'Common', 100, 50, 'Material Scales', 1, 'bronze-scale', true, 10),
  ('blacksmith-iron-scale', 'Iron Scale', 'Iron: neutral weapon material; +1 Vitality when used for shields; -1 Agility when used for armor.', 'material', 'Common', 400, 40, 'Material Scales', 1, 'iron-scale', true, 20),
  ('blacksmith-steel-scale', 'Steel Scale', 'Steel: +1 Strength when used for weapons; +1 Vitality when used for shields or armor.', 'material', 'Uncommon', 1000, 30, 'Material Scales', 1, 'steel-scale', true, 30),
  ('blacksmith-mythril-scale', 'Mythril Scale', 'Mythril: eligible for enhancement or enchantment when crafted into weapon, shield, or armor.', 'material', 'Rare', 6500, 12, 'Material Scales', 1, 'mythril-scale', true, 40),
  ('blacksmith-vaylium-scale', 'Vaylium Scale', 'Vaylium: +1 Intelligence for weapons; +1 Vitality and +1 Intelligence for shields; +3 Intelligence and +1 Magic Resist for armor.', 'material', 'Epic', 5000, 10, 'Material Scales', 1, 'vaylium-scale', true, 50),
  ('blacksmith-dragonscale-scale', 'Dragonscale Scale', 'Dragonscale: +2 Strength and +3 Magic Resist for weapons; +2 Vitality and +3 Magic Resist for shields; +2 Vitality and +5 Magic Resist for armor.', 'material', 'Legendary', 15000, 2, 'Material Scales', 1, 'dragonscale-scale', true, 60),
  ('blacksmith-ember-rune', 'Ember Rune', 'Can be used for Ember enchantments.', 'rune', 'Epic', 0, 0, 'Runes', 1, 'ember-rune', false, 70),
  ('blacksmith-frost-rune', 'Frost Rune', 'Can be used for Frost enchantments.', 'rune', 'Epic', 0, 0, 'Runes', 1, 'frost-rune', false, 80),
  ('blacksmith-lightning-rune', 'Lightning Rune', 'Can be used for Lightning enchantments.', 'rune', 'Epic', 0, 0, 'Runes', 1, 'lightning-rune', false, 90),
  ('blacksmith-earth-rune', 'Earth Rune', 'Can be used for Earth enchantments.', 'rune', 'Epic', 0, 0, 'Runes', 1, 'earth-rune', false, 100),
  ('blacksmith-wind-rune', 'Wind Rune', 'Can be used for Wind enchantments.', 'rune', 'Epic', 0, 0, 'Runes', 1, 'wind-rune', false, 110),
  ('blacksmith-mountain-rune', 'Mountain Rune', 'Cannot be used for enchantments yet.', 'rune', 'Epic', 0, 0, 'Runes', 1, 'mountain-rune', false, 120),
  ('blacksmith-void-rune', 'Void Rune', 'Cannot be used for enchantments yet.', 'rune', 'Mythical', 0, 0, 'Runes', 1, 'void-rune', false, 130)
) as seed(product_key, item_name, description, item_type, rarity, price_coin, stock_quantity, shop_section, quantity_step, catalog_item_key, is_available, display_order) on v.vendor_key = 'calostrynn-blacksmith'
on conflict (product_key) do update
set vendor_id = excluded.vendor_id,
    item_name = excluded.item_name,
    description = excluded.description,
    item_type = excluded.item_type,
    rarity = excluded.rarity,
    price_coin = excluded.price_coin,
    stock_quantity = excluded.stock_quantity,
    shop_section = excluded.shop_section,
    quantity_step = excluded.quantity_step,
    catalog_item_key = excluded.catalog_item_key,
    is_available = excluded.is_available,
    display_order = excluded.display_order,
    updated_at = now();

-- Seed Armory scales as Armory-owned wares instead of borrowing Blacksmith product rows.
insert into public.market_products (vendor_id, product_key, item_name, description, item_type, rarity, price_coin, stock_quantity, shop_section, quantity_step, catalog_item_key, is_available, display_order)
select v.id, seed.product_key, seed.item_name, seed.description, public.normalize_item_type(seed.item_type), seed.rarity::public.item_rarity, seed.price_coin, seed.stock_quantity::numeric, seed.shop_section, seed.quantity_step::numeric, seed.catalog_item_key, seed.is_available, seed.display_order
from public.shop_vendors v
join (values
  ('armory-bronze-scale', 'Bronze Scale', 'Bronze: +1 Vitality when used for shields.', 'material', 'Common', 100, 50, 'Material Scales', 1, 'bronze-scale', true, 10),
  ('armory-iron-scale', 'Iron Scale', 'Iron: -1 Agility when used for armor.', 'material', 'Common', 400, 40, 'Material Scales', 1, 'iron-scale', true, 20),
  ('armory-steel-scale', 'Steel Scale', 'Steel: +1 Vitality when used for shields or armor.', 'material', 'Uncommon', 1000, 30, 'Material Scales', 1, 'steel-scale', true, 30),
  ('armory-mythril-scale', 'Mythril Scale', 'Mythril: eligible for enhancement or enchantment when crafted into weapon, shield, or armor.', 'material', 'Rare', 6500, 12, 'Material Scales', 1, 'mythril-scale', true, 40),
  ('armory-vaylium-scale', 'Vaylium Scale', 'Vaylium: +1 Vitality and +1 Intelligence for shields; +3 Intelligence and +1 Magic Resist for armor.', 'material', 'Epic', 5000, 10, 'Material Scales', 1, 'vaylium-scale', true, 50),
  ('armory-dragonscale-scale', 'Dragonscale Scale', 'Dragonscale: +2 Vitality and +3 Magic Resist for shields; +2 Vitality and +5 Magic Resist for armor.', 'material', 'Legendary', 15000, 2, 'Material Scales', 1, 'dragonscale-scale', true, 60)
) as seed(product_key, item_name, description, item_type, rarity, price_coin, stock_quantity, shop_section, quantity_step, catalog_item_key, is_available, display_order) on v.vendor_key = 'calostrynn-armory'
on conflict (product_key) do update
set vendor_id = excluded.vendor_id,
    item_name = excluded.item_name,
    description = excluded.description,
    item_type = excluded.item_type,
    rarity = excluded.rarity,
    price_coin = excluded.price_coin,
    stock_quantity = excluded.stock_quantity,
    shop_section = excluded.shop_section,
    quantity_step = excluded.quantity_step,
    catalog_item_key = excluded.catalog_item_key,
    is_available = excluded.is_available,
    display_order = excluded.display_order,
    updated_at = now();

-- Replace Brewery placeholder wares with source-backed finished potions and brewing supplies.
with brewery_vendor as (select id from public.shop_vendors where vendor_key = 'calostrynn-brewery')
delete from public.market_products p
using brewery_vendor v
where p.vendor_id = v.id
  and (
    p.product_key in ('minor-healing-potion', 'minor-mana-potion', 'glass-flask')
    or lower(p.item_name) in ('minor healing potion', 'minor mana potion', 'glass flask', 'glass flasks')
  );

insert into public.market_products (vendor_id, product_key, item_name, description, item_type, rarity, price_coin, stock_quantity, shop_section, quantity_step, catalog_item_key, is_available, display_order)
select v.id, seed.product_key, seed.item_name, seed.description, 'potion', seed.rarity::public.item_rarity, seed.price_coin, seed.stock_quantity::numeric, seed.shop_section, 1, seed.catalog_item_key, seed.is_available, seed.display_order
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
  ('brewery-lesser-luck-potion', 'Lesser Luck Potion (Fine)', 'Fine lesser luck potion. Resolve the effect at the table.', 'Uncommon', 10000, 1, 'Finished Potions', 'lesser-luck-potion', true, 280),
  ('brewery-greater-luck-potion', 'Greater Luck Potion (Fine)', 'Fine greater luck potion. Resolve the effect at the table.', 'Rare', 70000, 0, 'Finished Potions', 'greater-luck-potion', false, 290),
  ('brewery-greatest-luck-potion', 'Greatest Luck Potion (Fine)', 'Fine greatest luck potion. Resolve the effect at the table.', 'Legendary', 300000, 0, 'Finished Potions', 'greatest-luck-potion', false, 300),
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
on conflict (product_key) do nothing;

with library_vendor as (select id from public.shop_vendors where vendor_key = 'calostrynn-library')
delete from public.market_products p
using library_vendor v
where p.vendor_id = v.id
  and p.product_key not in ('library-history-book', 'library-alchemy-book', 'library-bestiary', 'library-magical-research');

insert into public.market_products (vendor_id, product_key, item_name, description, item_type, rarity, price_coin, stock_quantity, shop_section, quantity_step, catalog_item_key, is_available, display_order)
select v.id, seed.product_key, seed.item_name, seed.description, 'quest', seed.rarity::public.item_rarity, seed.price_coin, seed.stock_quantity::numeric, 'Books', 1, seed.catalog_item_key, true, seed.display_order
from public.shop_vendors v
join (values
  ('library-history-book', 'History Book', 'A general history volume. Resolve its contents at the table.', 'Common', 100, null, 'history-book', 10),
  ('library-alchemy-book', 'Alchemy Book', 'An alchemical study text. Resolve its contents at the table.', 'Common', 500, null, 'alchemy-book', 20),
  ('library-bestiary', 'Bestiary', 'A creature reference volume. Resolve its contents at the table.', 'Common', 1000, null, 'bestiary', 30),
  ('library-magical-research', 'Magical Research', 'Choose a spell category to receive a rare magic spell book for that category.', 'Rare', 2500, null, 'magical-research', 40)
) as seed(product_key, item_name, description, rarity, price_coin, stock_quantity, catalog_item_key, display_order)
on v.vendor_key = 'calostrynn-library'
on conflict (product_key) do update
set vendor_id = excluded.vendor_id,
    item_name = excluded.item_name,
    description = excluded.description,
    item_type = excluded.item_type,
    rarity = excluded.rarity,
    price_coin = excluded.price_coin,
    stock_quantity = excluded.stock_quantity,
    shop_section = excluded.shop_section,
    quantity_step = excluded.quantity_step,
    catalog_item_key = excluded.catalog_item_key,
    is_available = excluded.is_available,
    display_order = excluded.display_order,
    updated_at = now();

with city_market_vendor as (select id from public.shop_vendors where vendor_key = 'calostrynn-city-market')
delete from public.market_products p
using city_market_vendor v
where p.vendor_id = v.id
  and p.product_key not in (
    'city-market-waist-pouch',
    'city-market-back-bag',
    'city-market-light-duffle',
    'city-market-heavy-duffle',
    'city-market-bag-of-holding',
    'city-market-light-wagon',
    'city-market-heavy-wagon',
    'city-market-torch',
    'city-market-rope',
    'city-market-blanket',
    'city-market-cooking-pots',
    'city-market-cloth',
    'city-market-fine-cloth',
    'city-market-ink-and-paper',
    'city-market-lock',
    'city-market-standard-hammer',
    'city-market-standard-axe',
    'city-market-quartz',
    'city-market-emerald',
    'city-market-ruby',
    'city-market-sapphire',
    'city-market-winter-wear',
    'city-market-heat-wear',
    'city-market-rainproof-wear',
    'city-market-basic-meal',
    'city-market-tavern-meal',
    'city-market-inn-room',
    'city-market-fine-inn',
    'city-market-horse',
    'city-market-war-horse',
    'city-market-dog'
  );

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
  ('city-market-torch', 'Torch', 'Cedrick sells a basic torch for travel and dungeon work.', 'tool', 'Common', 3, null, 'Cedrick - Supplies', 'torch', 100),
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
  ('city-market-dog', 'Dog', 'Cassandra sells a loyal dog.', 'pet', 'Epic', 1000, null, 'Cassandra - Stable Keeper', 'dog', 440)
) as seed(product_key, item_name, description, item_type, rarity, price_coin, stock_quantity, shop_section, catalog_item_key, display_order)
on v.vendor_key = 'calostrynn-city-market'
on conflict (product_key) do update
set vendor_id = excluded.vendor_id,
    item_name = excluded.item_name,
    description = excluded.description,
    item_type = excluded.item_type,
    rarity = excluded.rarity,
    price_coin = excluded.price_coin,
    stock_quantity = excluded.stock_quantity,
    shop_section = excluded.shop_section,
    quantity_step = excluded.quantity_step,
    catalog_item_key = excluded.catalog_item_key,
    is_available = excluded.is_available,
    display_order = excluded.display_order,
    updated_at = now();

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

create or replace function public.city_names_match(p_left text, p_right text)
returns boolean
language sql
immutable
as $$
  select length(trim(coalesce(p_left, ''))) > 0
    and lower(trim(coalesce(p_left, ''))) = lower(trim(coalesce(p_right, '')))
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
    'catalogItemKey', p_product.catalog_item_key,
    'section', p_product.shop_section,
    'quantityStep', p_product.quantity_step,
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

alter table public.shop_vendors
add column if not exists npc_name text not null default 'Shopkeeper';

update public.shop_vendors
set name = 'City Market',
    facility = 'Market',
    category = 'General Goods',
    npc_name = 'Market Stalls',
    is_hidden = false,
    display_order = 60
where vendor_key = 'calostrynn-city-market';

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
    'hidden', p_vendor.is_hidden,
    'order', p_vendor.display_order,
    'products', (
      select coalesce(jsonb_agg(public.market_product_record_to_json(p) order by p.display_order, p.item_name), '[]'::jsonb)
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
  if v_product.item_type = 'potion' then
    v_potion_strength := public.potion_strength_from_name(v_item_name);
    v_potion_property := public.potion_property_from_name(v_item_name);
    v_potion_quality := case
      when v_potion_property in ('Healing', 'Mana Regen') then null
      when lower(v_item_name) = 'empty flask' then null
      else public.potion_quality_from_name(v_item_name)
    end;
    if v_potion_strength is not null and v_potion_property is not null then
      v_item_name := public.format_potion_item_name(v_potion_strength, v_potion_property, v_potion_quality);
      v_product.rarity := public.potion_rarity_for_strength(v_potion_strength);
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

  if not public.city_names_match(v_character.location_name, v_city.name) then
    raise exception 'That character is not in %.', v_city.name;
  end if;

  if v_vendor.vendor_key = 'calostrynn-city-market'
    and lower(trim(coalesce(v_product.shop_section, ''))) = 'lucien - tavern keep'
  then
    if v_product.stock_quantity is not null and v_quantity > v_product.stock_quantity then
      raise exception 'Not enough stock.';
    end if;

    v_cost := ceil((v_product.price_coin * v_quantity)::numeric)::int;
    v_wallet := public.wallet_total_coin(v_character.id);
    if v_wallet < v_cost then
      raise exception 'Not enough currency.';
    end if;

    perform public.set_wallet_from_coin_value(v_character.id, v_wallet - v_cost);

    if v_product.stock_quantity is not null then
      update public.market_products
      set stock_quantity = greatest(0, stock_quantity - v_quantity)
      where id = v_product.id;
    end if;

    return public.get_discovered_cities(p_session_token);
  end if;

  if v_vendor.vendor_key = 'calostrynn-spells' then
    select * into v_spell
    from public.spell_catalog
    where spell_key = coalesce(nullif(v_product.catalog_item_key, ''), public.catalog_key_for_name(v_product.item_name))
      and is_available
    limit 1;

    if v_spell.id is null then
      raise exception 'Spell is not available.';
    end if;

    if exists (
      select 1
      from public.character_spells cs
      where cs.character_id = v_character.id
        and cs.spell_id = v_spell.id
    ) then
      raise exception '% already knows %.', v_character.name, v_spell.name;
    end if;

    v_quantity := 1;

    if v_product.stock_quantity is not null and v_product.stock_quantity < 1 then
      raise exception 'Not enough stock.';
    end if;

    v_cost := v_product.price_coin;
    v_wallet := public.wallet_total_coin(v_character.id);
    if v_wallet < v_cost then
      raise exception 'Not enough currency.';
    end if;

    v_slot := public.find_first_free_spell_slot(v_character.id, v_character.spell_slots);

    insert into public.character_spells (character_id, spell_id, is_active, slot_index)
    values (v_character.id, v_spell.id, v_slot is not null, v_slot);

    perform public.set_wallet_from_coin_value(v_character.id, v_wallet - v_cost);

    if v_product.stock_quantity is not null then
      update public.market_products
      set stock_quantity = greatest(0, stock_quantity - 1)
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
    v_product.item_type := 'quest';
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

  if v_product.stock_quantity is not null and v_quantity > v_product.stock_quantity then
    raise exception 'Not enough stock.';
  end if;

  v_cost := ceil((v_product.price_coin * v_quantity)::numeric)::int;
  v_wallet := public.wallet_total_coin(v_character.id);
  if v_wallet < v_cost then
    raise exception 'Not enough currency.';
  end if;

  v_inventory_quantity := v_quantity;

  if v_product.item_type = 'storage'::text
    and not public.character_storage_container_exists(v_character.id, v_item_name)
  then
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
      public.next_storage_container_slot(v_character.id),
      v_item_name,
      v_product.item_type,
      v_product.rarity,
      1,
      true,
      greatest(1, coalesce(nullif(v_storage_capacity, 0), public.catalog_storage_capacity(v_item_name))),
      v_modifiers,
      null,
      v_material,
      0,
      v_is_two_handed,
      v_potion_strength,
      v_potion_property,
      v_potion_quality
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
    and i.item_name = v_item_name
    and i.item_type = v_product.item_type
    and i.rarity = v_product.rarity
    and coalesce(i.enchantment, '') = ''
    and coalesce(i.material, '') = coalesce(v_material, '')
    and coalesce(i.potion_strength, '') = coalesce(v_potion_strength, '')
    and coalesce(i.potion_property, '') = coalesce(v_potion_property, '')
    and coalesce(i.potion_quality, '') = coalesce(v_potion_quality, '')
    and i.enhancement_count = 0
    and i.is_two_handed = v_is_two_handed
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
      v_product.item_type,
      v_product.rarity,
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
    item_type = case when v_patch ? 'type' then public.normalize_item_type(v_patch->>'type') else item_type end,
    rarity = case when v_patch ? 'rarity' then (v_patch->>'rarity')::public.item_rarity else rarity end,
    price_coin = case when v_patch ? 'priceCoin' then greatest(0, (v_patch->>'priceCoin')::int) else price_coin end,
    stock_quantity = case when v_patch ? 'stockQuantity' then greatest(0, (v_patch->>'stockQuantity')::numeric) else stock_quantity end,
    catalog_item_key = case when v_patch ? 'catalogItemKey' then nullif(trim(coalesce(v_patch->>'catalogItemKey', '')), '') else catalog_item_key end,
    shop_section = case when v_patch ? 'section' then coalesce(nullif(trim(v_patch->>'section'), ''), 'Wares') else shop_section end,
    quantity_step = case
      when lower(coalesce(nullif(trim(v_patch->>'name'), ''), item_name)) in ('bronze scale', 'iron scale', 'steel scale', 'mythril scale', 'vaylium scale', 'dragonscale scale') then 1
      when v_patch ? 'quantityStep' and (v_patch->>'quantityStep')::numeric = 0.5 then 0.5
      when v_patch ? 'quantityStep' then 1
      else quantity_step
    end,
    is_available = case when v_patch ? 'available' then (v_patch->>'available')::boolean else is_available end
  where id = p_product_id;

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

  if not public.city_names_match(p_character.location_name, v_city.name) then
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
      where c.id = p_character_id
        and h.is_storage = false
        and lower(h.item_name) = lower(trim(p_item_name))
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
    where c.id = p_character_id
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
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;
  if v_profile.role <> 'dm'::public.user_role then raise exception 'Only the Dungeon Master can change house access.'; end if;

  v_house := public.ensure_player_house(p_owner_user_id);

  update public.player_houses
  set is_locked = case when v_patch ? 'locked' then (v_patch->>'locked')::boolean else is_locked end
  where owner_user_id = p_owner_user_id
  returning * into v_house;

  return public.get_player_house(p_session_token, p_owner_user_id);
end;
$$;

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

create or replace function public.enchantment_spell_for_rune(p_rune_name text)
returns text
language plpgsql
stable
set search_path = public
as $$
declare
  v_key text := lower(trim(replace(coalesce(p_rune_name, ''), ' Rune', '')));
  v_options text[];
  v_roll int;
  v_weight int;
  v_total int;
  v_index int;
begin
  v_options := case v_key
    when 'ember' then array['Emberbolt', 'Scorch', 'Flame Ring', 'Solar Flare', 'Radiance', 'Fireball', 'Sear']
    when 'frost' then array['Frostbite', 'Ice Shard', 'Hypothermia', 'Ice Wall', 'Ice Cube', 'Christmas Tree', 'Absolute Zero']
    when 'lightning' then array['Sparkshot', 'Static Charge', 'Arc Shot', 'Defibrillate', 'Electric Explosion', 'Thunder Crash', 'Lightning Chain']
    when 'earth' then array['Stone Fist', 'Quicksand', 'Earthen Spikes', 'Earthquake']
    when 'wind' then array['Wind Cutter', 'Mighty Gust', 'Wind Be With Me', 'Gale Burst']
    else null
  end;

  if v_options is null or array_length(v_options, 1) is null then
    raise exception 'That rune cannot be used for enchantment yet.';
  end if;

  v_total := (array_length(v_options, 1) * (array_length(v_options, 1) + 1)) / 2;
  v_roll := floor(random() * v_total)::int + 1;

  for v_index in 1..array_length(v_options, 1) loop
    v_weight := array_length(v_options, 1) - v_index + 1;
    if v_roll <= v_weight then
      return v_options[v_index];
    end if;
    v_roll := v_roll - v_weight;
  end loop;

  return v_options[1];
end;
$$;

create or replace function public.run_blacksmith_action(
  p_session_token text,
  p_character_id uuid,
  p_action text,
  p_recipe_key text default null,
  p_material_product_id uuid default null,
  p_target_item_id uuid default null,
  p_rune_product_id uuid default null,
  p_modifier_key text default null
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
  v_catalyst text;
  v_required_runes int;
  v_spell_name text;
  v_city public.cities%rowtype;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;

  v_character := public.assert_inventory_access(v_profile, p_character_id, false);
  v_city := public.assert_character_can_use_vendor(v_character, 'calostrynn-blacksmith');

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

    v_wallet := public.wallet_total_coin(v_character.id);
    if v_wallet < v_cost then raise exception 'Not enough currency.'; end if;
    perform public.set_wallet_from_coin_value(v_character.id, v_wallet - v_cost);

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

  if v_target.id is null then raise exception 'Choose an eligible Mythril item.'; end if;
  if lower(coalesce(v_target.material, '') || ' ' || v_target.item_name) not like '%mythril%' then
    raise exception 'Only Mythril items can use that service.';
  end if;

  select * into v_rune_product from public.market_products where id = p_rune_product_id and item_type = 'rune' and is_available and price_coin > 0;
  if v_rune_product.id is null then raise exception 'Choose a rune.'; end if;

  if lower(coalesce(p_action, '')) = 'enhance' then
    if v_target.item_type not in ('weapon', 'shield') then raise exception 'Blacksmith enhancement is for Mythril weapons and shields.'; end if;
    if v_target.enchantment is not null then raise exception 'An enchanted item cannot be enhanced.'; end if;
    if v_target.enhancement_count >= 3 then raise exception 'That item already has three enhancements.'; end if;
    if v_rune_product.stock_quantity is not null and v_rune_product.stock_quantity < 1 then raise exception 'Not enough rune stock.'; end if;

    v_catalyst := case v_key
      when 'strength' then 'Titanvine Root'
      when 'accuracy' then 'Hawkeye Blossom'
      when 'intelligence' then 'Star Sage Orchid'
      when 'vitality' then 'Heartwood Sprout'
      when 'magic_resist' then 'Null Fern'
      when 'stealth' then 'Shade Moss'
      else null
    end;
    if v_catalyst is null then raise exception 'Unsupported enhancement.'; end if;

    v_cost := 1000 + v_rune_product.price_coin;
    v_wallet := public.wallet_total_coin(v_character.id);
    if v_wallet < v_cost then raise exception 'Not enough currency.'; end if;

    perform public.consume_crafting_item_by_name(v_character.id, v_catalyst, 20, v_city.name);
    perform public.set_wallet_from_coin_value(v_character.id, v_wallet - v_cost);
    if v_rune_product.stock_quantity is not null then
      update public.market_products set stock_quantity = greatest(0, stock_quantity - 1) where id = v_rune_product.id;
    end if;

    v_modifiers := coalesce(v_target.modifiers, '{}'::jsonb) || jsonb_build_object(v_key, coalesce((v_target.modifiers->>v_key)::int, 0) + 1);
    update public.inventory_items
    set modifiers = v_modifiers,
        enhancement_count = enhancement_count + 1
    where id = v_target.id;

    return public.get_discovered_cities(p_session_token);
  end if;

  if lower(coalesce(p_action, '')) = 'enchant' then
    if v_target.item_type <> 'weapon' then raise exception 'Only Mythril weapons can be enchanted.'; end if;
    if v_target.enchantment is not null then raise exception 'That weapon is already enchanted.'; end if;
    if v_target.enhancement_count > 0 then raise exception 'An enhanced weapon cannot be enchanted.'; end if;
    v_required_runes := case when lower(v_character.class_key) = 'talismanist' or lower(v_character.class_name) = 'talismanist' then 3 else 5 end;
    if v_rune_product.stock_quantity is not null and v_rune_product.stock_quantity < v_required_runes then raise exception 'Not enough rune stock.'; end if;

    v_spell_name := public.enchantment_spell_for_rune(v_rune_product.item_name);
    v_cost := 1000 + (v_rune_product.price_coin * v_required_runes);
    v_wallet := public.wallet_total_coin(v_character.id);
    if v_wallet < v_cost then raise exception 'Not enough currency.'; end if;
    perform public.set_wallet_from_coin_value(v_character.id, v_wallet - v_cost);
    if v_rune_product.stock_quantity is not null then
      update public.market_products set stock_quantity = greatest(0, stock_quantity - v_required_runes) where id = v_rune_product.id;
    end if;

    update public.inventory_items
    set enchantment = v_spell_name
    where id = v_target.id;

    return public.get_discovered_cities(p_session_token);
  end if;

  raise exception 'Unknown blacksmith action.';
end;
$$;

create or replace function public.run_armory_action(
  p_session_token text,
  p_character_id uuid,
  p_action text,
  p_recipe_key text default null,
  p_material_product_id uuid default null,
  p_target_item_id uuid default null,
  p_rune_product_id uuid default null,
  p_modifier_key text default null
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
  v_catalyst text;
  v_city public.cities%rowtype;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;

  v_character := public.assert_inventory_access(v_profile, p_character_id, false);
  v_city := public.assert_character_can_use_vendor(v_character, 'calostrynn-armory');

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

    v_wallet := public.wallet_total_coin(v_character.id);
    if v_wallet < v_cost then raise exception 'Not enough currency.'; end if;
    perform public.set_wallet_from_coin_value(v_character.id, v_wallet - v_cost);

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

    if v_target.id is null then raise exception 'Choose an eligible Mythril armor.'; end if;
    if v_target.item_type <> 'armor' then raise exception 'Armory enhancement is for Mythril armor.'; end if;
    if lower(coalesce(v_target.material, '') || ' ' || v_target.item_name) not like '%mythril%' then
      raise exception 'Only Mythril armor can use that service.';
    end if;
    if v_target.enchantment is not null then raise exception 'An enchanted item cannot be enhanced.'; end if;
    if v_target.enhancement_count >= 3 then raise exception 'That armor already has three enhancements.'; end if;

    select * into v_rune_product from public.market_products where id = p_rune_product_id and item_type = 'rune' and is_available and price_coin > 0;
    if v_rune_product.id is null then raise exception 'Choose a rune.'; end if;
    if v_rune_product.stock_quantity is not null and v_rune_product.stock_quantity < 1 then raise exception 'Not enough rune stock.'; end if;

    v_catalyst := case v_key
      when 'strength' then 'Titanvine Root'
      when 'accuracy' then 'Hawkeye Blossom'
      when 'intelligence' then 'Star Sage Orchid'
      when 'vitality' then 'Heartwood Sprout'
      when 'magic_resist' then 'Null Fern'
      when 'stealth' then 'Shade Moss'
      else null
    end;
    if v_catalyst is null then raise exception 'Unsupported enhancement.'; end if;

    v_labor := case when lower(v_character.class_key) = 'armor-clad' or lower(v_character.class_name) = 'armor-clad' then 0 else 1000 end;
    v_cost := v_labor + v_rune_product.price_coin;
    v_wallet := public.wallet_total_coin(v_character.id);
    if v_wallet < v_cost then raise exception 'Not enough currency.'; end if;

    perform public.consume_crafting_item_by_name(v_character.id, v_catalyst, 20, v_city.name);
    perform public.set_wallet_from_coin_value(v_character.id, v_wallet - v_cost);
    if v_rune_product.stock_quantity is not null then
      update public.market_products set stock_quantity = greatest(0, stock_quantity - 1) where id = v_rune_product.id;
    end if;

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
  left join public.item_catalog c on c.item_key = public.catalog_key_for_name(public.normalize_item_name(h.item_name))
  where lower(trim(coalesce(p_source, ''))) = 'house'
    and public.crafting_house_is_accessible(p_character_id, p_station_city_name)
    and ch.id = p_character_id
    and h.id = p_item_id
    and h.is_storage = false
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
      and is_storage = false;

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
    where c.id = p_character_id
      and h.id = p_item_id
      and h.is_storage = false;

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
    left join public.item_catalog c on c.item_key = public.catalog_key_for_name(public.normalize_item_name(h.item_name))
    where ch.id = p_character_id
      and public.crafting_house_is_accessible(p_character_id, p_station_city_name)
      and h.is_storage = false
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

create or replace function public.get_brewery_state(
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
  v_city public.cities%rowtype;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;

  v_character := public.assert_inventory_access(v_profile, p_character_id, false);
  v_city := public.assert_character_can_use_vendor(v_character, 'calostrynn-brewery');

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

create or replace function public.brew_potion(
  p_session_token text,
  p_character_id uuid,
  p_strength text,
  p_property_key text,
  p_property_selections jsonb,
  p_stabilizer_selections jsonb,
  p_catalyst_selection jsonb default null
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
  v_city := public.assert_character_can_use_vendor(v_character, 'calostrynn-brewery');

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
    v_rarity := public.potion_rarity_for_strength(v_strength);

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
    'brewery', public.get_brewery_state(p_session_token, v_character.id),
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
grant execute on function public.market_product_record_to_json(public.market_products) to anon, authenticated;
grant execute on function public.currency_coin_value(text) to anon, authenticated;
grant execute on function public.wallet_total_coin(uuid) to anon, authenticated;
grant execute on function public.set_wallet_from_coin_value(uuid, int) to anon, authenticated;
grant execute on function public.get_discovered_cities(text) to anon, authenticated;
grant execute on function public.purchase_market_product(text, uuid, uuid, numeric, text) to anon, authenticated;
grant execute on function public.update_city_access(text, text, jsonb) to anon, authenticated;
grant execute on function public.update_market_product(text, uuid, jsonb) to anon, authenticated;
grant execute on function public.forge_material_modifiers(text, text) to anon, authenticated;
grant execute on function public.enchantment_spell_for_rune(text) to anon, authenticated;
grant execute on function public.assert_character_can_use_vendor(public.characters, text) to anon, authenticated;
grant execute on function public.crafting_house_is_accessible(uuid, text) to anon, authenticated;
grant execute on function public.house_item_quantity_by_name(uuid, text, text) to anon, authenticated;
grant execute on function public.accessible_item_quantity_by_name(uuid, text, text) to anon, authenticated;
grant execute on function public.consume_crafting_item_by_name(uuid, text, numeric, text) to anon, authenticated;
grant execute on function public.update_player_house(text, uuid, jsonb) to anon, authenticated;
grant execute on function public.consume_forge_materials(uuid, uuid, numeric, int, text, text) to anon, authenticated;
grant execute on function public.run_blacksmith_action(text, uuid, text, text, uuid, uuid, uuid, text) to anon, authenticated;
grant execute on function public.run_armory_action(text, uuid, text, text, uuid, uuid, uuid, text) to anon, authenticated;
grant execute on function public.crafting_selection_item(uuid, text, uuid, text) to anon, authenticated;
grant execute on function public.consume_crafting_selection(uuid, text, uuid, numeric, text) to anon, authenticated;
grant execute on function public.brewery_available_items(uuid, text) to anon, authenticated;
grant execute on function public.get_brewery_state(text, uuid) to anon, authenticated;
grant execute on function public.brew_potion(text, uuid, text, text, jsonb, jsonb, jsonb) to anon, authenticated;
grant execute on function public.consume_inventory_potion(text, uuid, boolean) to anon, authenticated;

update public.market_products
set item_name = 'Mountain Rune',
    catalog_item_key = 'mountain-rune'
where lower(item_name) = 'mountian rune'
   or product_key = 'blacksmith-mountian-rune';

update public.market_products
set item_type = 'rune',
    rarity = 'Epic',
    quantity_step = 1
where lower(item_name) in ('ember rune', 'frost rune', 'lightning rune', 'earth rune', 'wind rune', 'mountain rune');

update public.market_products
set item_type = 'rune',
    rarity = 'Mythical',
    quantity_step = 1
where lower(item_name) = 'void rune';

update public.market_products
set item_type = 'material',
    quantity_step = 1
where lower(item_name) in ('bronze scale', 'iron scale', 'steel scale', 'mythril scale', 'vaylium scale', 'dragonscale scale');

update public.market_products
set description = 'Dragonscale: +2 Strength and +3 Magic Resist for weapons; +2 Vitality and +3 Magic Resist for shields; +2 Vitality and +5 Magic Resist for armor.'
where product_key = 'blacksmith-dragonscale-scale'
  and description like '%+5 Magic Resist for shields%';

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
  updated_at timestamptz not null default now(),
  unique (character_id, spell_id)
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

create table if not exists public.app_checkpoints (
  checkpoint_key text primary key,
  applied_at timestamptz not null default now()
);

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

  if not exists (select 1 from public.app_checkpoints where checkpoint_key = 'clear-owned-spells-official-catalog-2026-07-25') then
    delete from public.character_spells;
    insert into public.app_checkpoints (checkpoint_key) values ('clear-owned-spells-official-catalog-2026-07-25');
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

with spell_vendor as (select id from public.shop_vendors where vendor_key = 'calostrynn-spells')
delete from public.market_products p
using spell_vendor v
where p.vendor_id = v.id
  and p.product_key not in ('spell-emberbolt', 'spell-scorch', 'spell-flame-ring', 'spell-solar-flare', 'spell-radiance', 'spell-fireball', 'spell-sear', 'spell-frostbite', 'spell-ice-shard', 'spell-hypothermia', 'spell-ice-wall', 'spell-ice-cube', 'spell-christmas-tree', 'spell-absolute-zero', 'spell-sparkshot', 'spell-static-charge', 'spell-arc-shot', 'spell-defibrillate', 'spell-electric-explosion', 'spell-thunder-crash', 'spell-lightning-chain', 'spell-stone-fist', 'spell-quicksand', 'spell-earthen-spikes', 'spell-earthquake', 'spell-wind-cutter', 'spell-mighty-gust', 'spell-wind-be-with-me', 'spell-gale-burst', 'spell-pulse', 'spell-energy-shield', 'spell-mend-wounds', 'spell-greater-mend', 'spell-antivenom', 'spell-fortify', 'spell-iron-skin', 'spell-shield', 'spell-cleanse', 'spell-revitalize', 'spell-golden-boy', 'spell-insurance', 'spell-counter-attack', 'spell-retaliation', 'spell-internal-bleeding', 'spell-strip', 'spell-demoralize', 'spell-weaken', 'spell-cripple', 'spell-enfeeblement', 'spell-dreadfall', 'spell-whats-mine-is-yours', 'spell-judas', 'spell-jump-him', 'spell-follow-the-leader', 'spell-bloodthirsty', 'spell-swiftness', 'spell-clarity', 'spell-mana-surge', 'spell-guided-strike', 'spell-stabilize', 'spell-light-orb', 'spell-warmth', 'spell-cooling', 'spell-levitation', 'spell-seal', 'spell-magecraft-detection', 'spell-purify-water', 'spell-silent-step', 'spell-taunt', 'spell-entangle', 'spell-pure-chaos', 'spell-equilibrium', 'spell-preparation');

insert into public.market_products (vendor_id, product_key, item_name, description, item_type, rarity, price_coin, stock_quantity, shop_section, quantity_step, catalog_item_key, is_available, display_order)
select
  v.id,
  'spell-' || s.spell_key,
  s.name,
  coalesce(nullif(s.summary, ''), s.spell_type || ' spell - ' || s.mana_label),
  'quest',
  s.rarity,
  s.price_coin,
  null,
  s.spell_type || ' Spells',
  1,
  s.spell_key,
  s.is_available,
  s.display_order
from public.shop_vendors v
join public.spell_catalog s on s.spell_key in ('emberbolt', 'scorch', 'flame-ring', 'solar-flare', 'radiance', 'fireball', 'sear', 'frostbite', 'ice-shard', 'hypothermia', 'ice-wall', 'ice-cube', 'christmas-tree', 'absolute-zero', 'sparkshot', 'static-charge', 'arc-shot', 'defibrillate', 'electric-explosion', 'thunder-crash', 'lightning-chain', 'stone-fist', 'quicksand', 'earthen-spikes', 'earthquake', 'wind-cutter', 'mighty-gust', 'wind-be-with-me', 'gale-burst', 'pulse', 'energy-shield', 'mend-wounds', 'greater-mend', 'antivenom', 'fortify', 'iron-skin', 'shield', 'cleanse', 'revitalize', 'golden-boy', 'insurance', 'counter-attack', 'retaliation', 'internal-bleeding', 'strip', 'demoralize', 'weaken', 'cripple', 'enfeeblement', 'dreadfall', 'whats-mine-is-yours', 'judas', 'jump-him', 'follow-the-leader', 'bloodthirsty', 'swiftness', 'clarity', 'mana-surge', 'guided-strike', 'stabilize', 'light-orb', 'warmth', 'cooling', 'levitation', 'seal', 'magecraft-detection', 'purify-water', 'silent-step', 'taunt', 'entangle', 'pure-chaos', 'equilibrium', 'preparation')
where v.vendor_key = 'calostrynn-spells'
on conflict (product_key) do update
set vendor_id = excluded.vendor_id,
    item_name = excluded.item_name,
    description = excluded.description,
    item_type = excluded.item_type,
    rarity = excluded.rarity,
    price_coin = excluded.price_coin,
    stock_quantity = excluded.stock_quantity,
    shop_section = excluded.shop_section,
    quantity_step = excluded.quantity_step,
    catalog_item_key = excluded.catalog_item_key,
    is_available = excluded.is_available,
    display_order = excluded.display_order,
    updated_at = now();

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
    'spell', public.spell_record_to_json(s)
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

  v_character := public.assert_inventory_access(v_profile, p_character_id, false);

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
  values (p_character_id, p_spell_id, v_slot is not null, v_slot)
  on conflict (character_id, spell_id) do nothing;

  return public.get_character_spells(p_session_token, p_character_id);
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

  select cb.* into v_combatant
  from public.combatants cb
  join public.battles b on b.id = cb.battle_id
  where cb.character_id = v_entry.character_id
    and b.status = 'active'::public.battle_status
  order by cb.created_at desc
  limit 1;

  v_current_mana := coalesce(v_combatant.current_mana, v_character.current_mana);

  if v_current_mana < v_spell.mana_cost then
    raise exception 'Not enough mana.';
  end if;

  v_remaining_mana := v_current_mana - v_spell.mana_cost;

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
    'manaSpent', v_spell.mana_cost,
    'spellName', v_spell.name
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

  if v_item.id is null then raise exception 'Enchanted weapon not found.'; end if;
  if v_item.item_type <> 'weapon' then raise exception 'Only enchanted weapons can cast this way.'; end if;
  if nullif(trim(coalesce(v_item.enchantment, '')), '') is null then raise exception 'That weapon has no spell enchantment.'; end if;

  select * into v_spell from public.spell_catalog where id = p_spell_id;
  if v_spell.id is null then raise exception 'Spell not found.'; end if;

  if lower(regexp_replace(v_item.enchantment, '[^a-z0-9]+', ' ', 'g')) <> lower(regexp_replace(v_spell.name, '[^a-z0-9]+', ' ', 'g'))
     and lower(regexp_replace(v_item.enchantment, '[^a-z0-9]+', ' ', 'g')) <> lower(regexp_replace(v_spell.spell_key, '[^a-z0-9]+', ' ', 'g')) then
    raise exception 'That spell does not match this weapon enchantment.';
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

grant execute on function public.spell_record_to_json(public.spell_catalog) to anon, authenticated;
grant execute on function public.character_spell_record_to_json(public.character_spells) to anon, authenticated;
grant execute on function public.character_has_active_battle(uuid) to anon, authenticated;
grant execute on function public.find_first_free_spell_slot(uuid, int) to anon, authenticated;
grant execute on function public.get_character_spells(text, uuid) to anon, authenticated;
grant execute on function public.grant_character_spell(text, uuid, uuid) to anon, authenticated;
grant execute on function public.update_character_spell_state(text, uuid, jsonb) to anon, authenticated;
grant execute on function public.use_character_spell(text, uuid) to anon, authenticated;
grant execute on function public.use_inventory_enchantment_spell(text, uuid, uuid, uuid) to anon, authenticated;


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

alter table public.loot_items
  alter column item_type type text using item_type::text,
  alter column min_quantity type numeric(12,1) using min_quantity::numeric,
  alter column max_quantity type numeric(12,1) using max_quantity::numeric;

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
      when public.potion_strength_from_name(item_name) is not null then public.potion_rarity_for_strength(public.potion_strength_from_name(item_name))
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

-- Seed/refresh City Market loot rows from the checked workbook shape without replacing the full generator table.
do $$
declare
  v_row record;
  v_pool_id uuid;
begin
  delete from public.loot_items
  where lower(item_name) in (
    'torch',
    'rope',
    'waist pouch',
    'back bag',
    'cloth',
    'fine cloth',
    'light duffle',
    'horse',
    'war horse',
    'quartz',
    'heavy duffle',
    'emerald',
    'ruby',
    'sapphire',
    'bag of holding',
    'blanket',
    'cooking pots',
    'ink and paper',
    'lock',
    'standard hammer',
    'standard axe',
    'winter wear',
    'heat wear',
    'rainproof wear',
    'dog'
  );

  for v_row in
    select * from (values
      ('Torch', 'tool', 'Tool Catalog', 'catalog-tool', array['Any']::text[], 1, 3, 'Common', 100::numeric, 1::numeric, 3::numeric, false),
      ('Rope', 'tool', 'Tool Catalog', 'catalog-tool', array['Any']::text[], 1, 3, 'Common', 90::numeric, 1::numeric, 5::numeric, false),
      ('Waist Pouch', 'storage', 'Storage Catalog', 'catalog-storage', array['Any']::text[], 1, 2, 'Common', 70::numeric, 1::numeric, 3::numeric, false),
      ('Back Bag', 'storage', 'Storage Catalog', 'catalog-storage', array['Any']::text[], 1, 3, 'Common', 60::numeric, 1::numeric, 2::numeric, false),
      ('Cloth', 'fabric', 'Fabric Catalog', 'catalog-fabric', array['Any']::text[], 1, 2, 'Common', 80::numeric, 1::numeric, 3::numeric, false),
      ('Fine Cloth', 'fabric', 'Fabric Catalog', 'catalog-fabric', array['Any']::text[], 3, 5, 'Common', 75::numeric, 1::numeric, 5::numeric, false),
      ('Light Duffle', 'storage', 'Storage Catalog', 'catalog-storage', array['Any']::text[], 2, 4, 'Uncommon', 50::numeric, 1::numeric, 2::numeric, false),
      ('Horse', 'pet', 'Pet Catalog', 'catalog-pet', array['Any']::text[], 1, 3, 'Rare', 35::numeric, 1::numeric, 5::numeric, true),
      ('War Horse', 'pet', 'Pet Catalog', 'catalog-pet', array['Any']::text[], 3, 5, 'Rare', 35::numeric, 1::numeric, 5::numeric, true),
      ('Quartz', 'ore', 'Ore Catalog', 'catalog-ore', array['Any', 'Goblins']::text[], 1, 5, 'Rare', 40::numeric, 1::numeric, 5::numeric, false),
      ('Heavy Duffle', 'storage', 'Storage Catalog', 'catalog-storage', array['Any']::text[], 2, 5, 'Rare', 35::numeric, 1::numeric, 2::numeric, false),
      ('Emerald', 'ore', 'Ore Catalog', 'catalog-ore', array['Goblins', 'Caves']::text[], 2, 5, 'Epic', 30::numeric, 1::numeric, 4::numeric, false),
      ('Ruby', 'ore', 'Ore Catalog', 'catalog-ore', array['Goblins', 'Caves']::text[], 3, 5, 'Epic', 20::numeric, 1::numeric, 3::numeric, false),
      ('Sapphire', 'ore', 'Ore Catalog', 'catalog-ore', array['Goblins', 'Caves']::text[], 4, 5, 'Legendary', 10::numeric, 1::numeric, 2::numeric, false),
      ('Bag of Holding', 'storage', 'Storage Catalog', 'catalog-storage', array['Any']::text[], 3, 5, 'Mythical', 2::numeric, 1::numeric, 1::numeric, false),
      ('Blanket', 'fabric', 'Fabric Catalog', 'catalog-fabric', array['Any']::text[], 1, 5, 'Common', 10::numeric, 1::numeric, 5::numeric, false),
      ('Cooking Pots', 'tool', 'Tool Catalog', 'catalog-tool', array['Any']::text[], 1, 5, 'Common', 10::numeric, 1::numeric, 5::numeric, false),
      ('Ink and Paper', 'tool', 'Tool Catalog', 'catalog-tool', array['Any']::text[], 1, 5, 'Common', 10::numeric, 1::numeric, 1::numeric, false),
      ('Lock', 'tool', 'Tool Catalog', 'catalog-tool', array['Any']::text[], 1, 5, 'Common', 10::numeric, 1::numeric, 1::numeric, false),
      ('Standard Hammer', 'tool', 'Tool Catalog', 'catalog-tool', array['Any']::text[], 1, 5, 'Common', 10::numeric, 1::numeric, 1::numeric, false),
      ('Standard Axe', 'tool', 'Tool Catalog', 'catalog-tool', array['Any']::text[], 1, 5, 'Common', 10::numeric, 1::numeric, 1::numeric, false),
      ('Winter Wear', 'fabric', 'Fabric Catalog', 'catalog-fabric', array['Any']::text[], 1, 5, 'Uncommon', 10::numeric, 1::numeric, 1::numeric, false),
      ('Heat Wear', 'fabric', 'Fabric Catalog', 'catalog-fabric', array['Any']::text[], 1, 5, 'Uncommon', 10::numeric, 1::numeric, 1::numeric, false),
      ('Rainproof Wear', 'fabric', 'Fabric Catalog', 'catalog-fabric', array['Any']::text[], 1, 5, 'Uncommon', 5::numeric, 1::numeric, 1::numeric, false),
      ('Dog', 'pet', 'Pet Catalog', 'catalog-pet', array['Any']::text[], 1, 5, 'Epic', 5::numeric, 1::numeric, 5::numeric, false)
    ) as seed(item_name, item_type, pool_name, pool_key, biomes, min_difficulty, max_difficulty, rarity, loot_weight, min_quantity, max_quantity, tower_base_only)
  loop
    insert into public.loot_pools (pool_key, name, description, display_order)
    values (v_row.pool_key, v_row.pool_name, 'Imported item catalog group.', 100)
    on conflict (pool_key) do update
    set name = excluded.name,
        description = excluded.description
    returning id into v_pool_id;

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
      min_quantity,
      max_quantity,
      notes,
      is_active
    )
    values (
      v_pool_id,
      v_row.item_name,
      public.normalize_item_type(v_row.item_type),
      v_row.rarity::public.item_rarity,
      v_row.biomes,
      v_row.min_difficulty,
      v_row.max_difficulty,
      v_row.loot_weight,
      v_row.tower_base_only,
      v_row.min_quantity,
      v_row.max_quantity,
      '',
      true
    );
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
  message text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists trade_offers_sender_idx on public.trade_offers(sender_user_id, status, created_at desc);
create index if not exists trade_offers_recipient_idx on public.trade_offers(recipient_user_id, status, created_at desc);

alter table public.trade_offers
  add column if not exists offered_item_id uuid references public.inventory_items(id) on delete set null,
  add column if not exists offered_item_name text not null default '',
  add column if not exists offered_quantity numeric(12,1) not null default 1 check (offered_quantity > 0);

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
    'message', p_trade.message,
    'createdAt', p_trade.created_at,
    'updatedAt', p_trade.updated_at
  )
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

drop function if exists public.create_trade_offer(text, uuid, uuid, text, text, text);
drop function if exists public.create_trade_offer(text, uuid, uuid, text, text, text, uuid, numeric);

create or replace function public.create_trade_offer(
  p_session_token text,
  p_sender_character_id uuid,
  p_target_character_id uuid,
  p_offer_note text default '',
  p_request_note text default '',
  p_message text default '',
  p_offered_item_id uuid default null,
  p_offered_quantity numeric default 1
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
  v_trade public.trade_offers%rowtype;
  v_offered_quantity numeric := greatest(0.5, coalesce(p_offered_quantity, 1));
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

  if p_offered_item_id is not null then
    select * into v_offered_item
    from public.inventory_items
    where id = p_offered_item_id
      and character_id = v_sender.id;

    if v_offered_item.id is null then raise exception 'Offered item was not found in that inventory.'; end if;
    if v_offered_item.loadout_slot is not null then raise exception 'Unequip that item before offering it.'; end if;
    if v_offered_item.is_storage then raise exception 'Storage containers cannot be offered through trades.'; end if;
    if v_offered_item.quantity < v_offered_quantity then raise exception 'Not enough quantity to offer.'; end if;
  end if;

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
    message
  )
  values (
    coalesce(v_sender.owner_user_id, v_profile.id),
    v_target.owner_user_id,
    v_sender.id,
    v_target.id,
    coalesce(nullif(p_offer_note, ''), case when v_offered_item.id is not null then v_offered_quantity::text || ' ' || coalesce(v_offered_item.display_name, v_offered_item.item_name) else '' end),
    coalesce(p_request_note, ''),
    v_offered_item.id,
    coalesce(v_offered_item.display_name, v_offered_item.item_name, ''),
    v_offered_quantity,
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
    trim(both from concat_ws(E'\n\n', nullif(coalesce(p_message, ''), ''), 'Offers: ' || nullif(coalesce(coalesce(nullif(p_offer_note, ''), case when v_offered_item.id is not null then v_offered_quantity::text || ' ' || coalesce(v_offered_item.display_name, v_offered_item.item_name) else '' end), ''), ''), 'Requests: ' || nullif(coalesce(p_request_note, ''), ''))),
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
  if v_source_item.loadout_slot is not null then raise exception 'Unequip that item before gifting it.'; end if;
  if v_source_item.is_storage then raise exception 'Storage containers cannot be gifted.'; end if;

  if v_sender.owner_user_id is distinct from v_target_character.owner_user_id
    and v_profile.role <> 'dm'::public.user_role
    and not coalesce(v_target_character.gift_inventory_open, true)
  then
    raise exception 'This persons inventory is closed from gifting efforts and grows tired of your pranks';
  end if;

  v_quantity := public.assert_valid_item_quantity(v_source_item.item_name, v_source_item.item_type, greatest(0.5, coalesce(p_quantity, 1)));
  if v_quantity > v_source_item.quantity then raise exception 'Not enough quantity to gift.'; end if;

  select * into v_target_item
  from public.inventory_items i
  where i.character_id = v_target_character.id
    and i.parent_item_id is null
    and i.loadout_slot is null
    and i.item_name = v_source_item.item_name
    and coalesce(i.display_name, '') = coalesce(v_source_item.display_name, '')
    and coalesce(i.item_description, '') = coalesce(v_source_item.item_description, '')
    and i.item_type = v_source_item.item_type
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
      v_quantity::text || ' ' || coalesce(v_source_item.display_name, v_source_item.item_name) || ' was placed into ' || v_target_character.name || '''s inventory.',
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
  v_target_character public.characters%rowtype;
  v_target_item public.inventory_items%rowtype;
  v_slot_index int;
  v_next_status text := lower(trim(coalesce(p_status, '')));
  v_notify_user uuid;
  v_title text;
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

  if v_next_status = 'accepted' and v_trade.offered_item_id is not null then
    select * into v_source_item
    from public.inventory_items
    where id = v_trade.offered_item_id
    for update;

    if v_source_item.id is null then raise exception 'The offered item is no longer available.'; end if;
    if v_source_item.character_id <> v_trade.sender_character_id then raise exception 'The offered item is no longer held by the offering character.'; end if;
    if v_source_item.loadout_slot is not null then raise exception 'The offered item is currently equipped.'; end if;
    if v_source_item.quantity < v_trade.offered_quantity then raise exception 'The offered item quantity is no longer available.'; end if;

    select * into v_target_character from public.characters where id = v_trade.target_character_id;
    if v_target_character.id is null then raise exception 'Target character was not found.'; end if;

    select * into v_target_item
    from public.inventory_items i
    where i.character_id = v_target_character.id
      and i.parent_item_id is null
      and i.loadout_slot is null
      and i.item_name = v_source_item.item_name
      and coalesce(i.display_name, '') = coalesce(v_source_item.display_name, '')
      and coalesce(i.item_description, '') = coalesce(v_source_item.item_description, '')
      and i.item_type = v_source_item.item_type
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
grant execute on function public.mark_notification_read(text, uuid) to anon, authenticated;
grant execute on function public.create_campaign_announcement(text, text, text, text, boolean) to anon, authenticated;
grant execute on function public.get_trade_offers(text) to anon, authenticated;
grant execute on function public.create_trade_offer(text, uuid, uuid, text, text, text, uuid, numeric) to anon, authenticated;
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

    v_min_quantity := greatest(0.5, coalesce(nullif(v_row->>'minQuantity', '')::numeric, nullif(v_row->>'min_quantity', '')::numeric, nullif(v_row->>'min', '')::numeric, 1));
    v_max_quantity := greatest(v_min_quantity, coalesce(nullif(v_row->>'maxQuantity', '')::numeric, nullif(v_row->>'max_quantity', '')::numeric, nullif(v_row->>'max', '')::numeric, v_min_quantity));
    v_stackable := case lower(trim(coalesce(v_row->>'stackable', v_row->>'isStackable', v_row->>'is_stackable', '')))
      when 'false' then false
      when 'no' then false
      when '0' then false
      when 'true' then true
      when 'yes' then true
      when '1' then true
      else true
    end;

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
      coalesce(v_row->>'notes', ''),
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
      '',
      false,
      case when v_type_text = 'storage' then public.catalog_storage_capacity(v_name) else 0 end,
      coalesce(v_row->>'notes', ''),
      true,
      100
    );
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
      v_rarity := public.potion_rarity_for_strength(v_potion_strength);
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

  v_inventory_quantity := v_quantity;

  if v_item_type = 'storage'::text
    and not public.character_storage_container_exists(v_character.id, v_item_name)
  then
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
      public.next_storage_container_slot(v_character.id),
      v_item_name,
      v_item_type,
      v_rarity,
      1,
      true,
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
    and i.item_name = v_item_name
    and i.item_type = v_item_type
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

-- Consolidated final grants
grant execute on function public.get_character_ledger(text) to anon, authenticated;
grant execute on function public.create_campaign_character(text, text, uuid, text, text, text) to anon, authenticated;
grant execute on function public.ensure_character_starter_armor(uuid) to anon, authenticated;
grant execute on function public.update_campaign_character(text, uuid, jsonb) to anon, authenticated;
grant execute on function public.set_character_gift_inventory_open(text, uuid, boolean) to anon, authenticated;
grant execute on function public.get_dashboard_state(text) to anon, authenticated;
grant execute on function public.shop_vendor_record_to_json(public.shop_vendors, boolean) to anon, authenticated;
grant execute on function public.is_currency_loot_item(public.loot_items) to anon, authenticated;
grant execute on function public.loot_item_record_to_json(public.loot_items) to anon, authenticated;
grant execute on function public.get_exploration_state(text) to anon, authenticated;
grant execute on function public.get_exploration_cave_nicknames(text) to anon, authenticated;
grant execute on function public.set_exploration_cave_nickname(text, int, text) to anon, authenticated;
grant execute on function public.import_loot_items(text, jsonb) to anon, authenticated;
grant execute on function public.update_shop_vendor(text, uuid, jsonb) to anon, authenticated;
grant execute on function public.item_catalog_stackable(text, text) to anon, authenticated;
grant execute on function public.catalog_storage_capacity(text) to anon, authenticated;
grant execute on function public.split_inventory_item_stack(text, uuid, numeric, boolean) to anon, authenticated;
grant execute on function public.award_exploration_loot_item(text, uuid, uuid, numeric) to anon, authenticated;


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

drop trigger if exists app_live_cities on public.cities;
create trigger app_live_cities
after insert or update or delete on public.cities
for each row execute function public.touch_app_live_update_trigger('dashboard,cities,assets');

drop trigger if exists app_live_shop_vendors on public.shop_vendors;
create trigger app_live_shop_vendors
after insert or update or delete on public.shop_vendors
for each row execute function public.touch_app_live_update_trigger('cities,assets');

drop trigger if exists app_live_market_products on public.market_products;
create trigger app_live_market_products
after insert or update or delete on public.market_products
for each row execute function public.touch_app_live_update_trigger('cities,assets');

drop trigger if exists app_live_house_inventory_items on public.house_inventory_items;
create trigger app_live_house_inventory_items
after insert or update or delete on public.house_inventory_items
for each row execute function public.touch_app_live_update_trigger('house,inventory,cities');

drop trigger if exists app_live_campaign_properties on public.campaign_properties;
create trigger app_live_campaign_properties
after insert or update or delete on public.campaign_properties
for each row execute function public.touch_app_live_update_trigger('house,cities,assets');

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

