-- Arta Malanda current manual Supabase SQL
-- Updated through checkpoint 3: auth, dashboard shell, database-backed character ledger, seeded class templates.
-- For manual Supabase use: paste this whole file into the Supabase SQL Editor and run it.
-- It is designed to be rerunnable; create-or-replace functions update existing code cleanly.

create schema if not exists extensions;
create extension if not exists "pgcrypto" with schema extensions;
create extension if not exists "citext" with schema extensions;


-- ============================================================
-- Source: supabase\core-v1.sql
-- ============================================================

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
  create type public.item_type as enum ('weapon', 'armor', 'shield', 'pet', 'accessory', 'storage', 'ore', 'potion', 'food', 'plant', 'fabric', 'tool', 'quest', 'misc');
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
  inventory_slots int not null default 12 check (inventory_slots between 0 and 120),
  spell_slots int not null default 0 check (spell_slots >= 0),
  attributes jsonb not null default '{}'::jsonb check (jsonb_typeof(attributes) = 'object'),
  class_passives jsonb not null default '[]'::jsonb check (jsonb_typeof(class_passives) = 'array'),
  personal_passives text not null default '',
  token_color text not null default '#9caf79',
  location_name text not null default 'Calostrynn',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.inventory_items (
  id uuid primary key default gen_random_uuid(),
  character_id uuid not null references public.characters(id) on delete cascade,
  parent_item_id uuid references public.inventory_items(id) on delete cascade,
  item_name text not null,
  item_type public.item_type not null default 'misc',
  rarity public.item_rarity not null default 'Common',
  quantity int not null default 1 check (quantity > 0),
  slot_index int not null default 0 check (slot_index >= 0),
  loadout_slot text,
  is_storage boolean not null default false,
  storage_capacity int not null default 0 check (storage_capacity between 0 and 500),
  modifiers jsonb not null default '{}'::jsonb check (jsonb_typeof(modifiers) = 'object'),
  spell_imbue text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists inventory_container_slot_unique
  on public.inventory_items (character_id, coalesce(parent_item_id, '00000000-0000-0000-0000-000000000000'::uuid), slot_index)
  where loadout_slot is null;

create unique index if not exists inventory_loadout_slot_unique
  on public.inventory_items (character_id, loadout_slot)
  where loadout_slot is not null;

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

create index if not exists profiles_username_idx on public.profiles(username);
create index if not exists app_sessions_profile_idx on public.app_sessions(profile_id);
create index if not exists app_sessions_valid_idx on public.app_sessions(token_hash, expires_at) where revoked_at is null;
create index if not exists characters_owner_idx on public.characters(owner_user_id);
create index if not exists inventory_character_idx on public.inventory_items(character_id);
create index if not exists inventory_parent_idx on public.inventory_items(parent_item_id);
create index if not exists combatants_battle_idx on public.combatants(battle_id);

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

revoke all on table public.profiles from anon, authenticated;
revoke all on table public.dm_lock from anon, authenticated;
revoke all on table public.app_sessions from anon, authenticated;
revoke all on table public.class_templates from anon, authenticated;
revoke all on table public.characters from anon, authenticated;
revoke all on table public.inventory_items from anon, authenticated;
revoke all on table public.battles from anon, authenticated;
revoke all on table public.combatants from anon, authenticated;

grant usage on schema public to anon, authenticated;
grant execute on function public.create_campaign_account(text, text, text, boolean) to anon, authenticated;
grant execute on function public.login_campaign_account(text, text) to anon, authenticated;
grant execute on function public.get_campaign_session(text) to anon, authenticated;
grant execute on function public.logout_campaign_session(text) to anon, authenticated;

-- ============================================================
-- Source: supabase\migrations\20260711000300_character_ledger_foundation.sql
-- ============================================================

-- Character ledger foundation
-- Run this after the username auth core + auth crypto fix migrations.

alter table public.characters
  add column if not exists class_key text;

update public.characters
set class_key = lower(regexp_replace(class_name, '[^a-zA-Z0-9]+', '-', 'g'))
where class_key is null;

alter table public.characters
  alter column class_key set default 'adventurer';

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
    'inventorySlots', p_character.inventory_slots,
    'spellSlots', p_character.spell_slots,
    'attributes', p_character.attributes,
    'classPassives', p_character.class_passives,
    'personalPassives', p_character.personal_passives,
    'tokenColor', p_character.token_color,
    'locationName', p_character.location_name
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
    'characters', (
      select coalesce(jsonb_agg(public.character_record_to_json(c) order by c.name), '[]'::jsonb)
      from public.characters c
      where c.kind = 'player'
    )
  );
end;
$$;

create or replace function public.create_campaign_character(
  p_session_token text,
  p_name text,
  p_owner_user_id uuid,
  p_class_key text,
  p_class_name text,
  p_level int,
  p_max_hp int,
  p_current_hp int,
  p_max_mana int,
  p_current_mana int,
  p_inventory_slots int,
  p_spell_slots int,
  p_attributes jsonb,
  p_class_passives jsonb,
  p_personal_passives text,
  p_token_color text
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

  if v_profile.role <> 'dm'::public.user_role then
    raise exception 'Only the Dungeon Master can create characters.';
  end if;

  if length(trim(coalesce(p_name, ''))) = 0 then
    raise exception 'Character name is required.';
  end if;

  if p_owner_user_id is not null and not exists (select 1 from public.profiles where id = p_owner_user_id) then
    raise exception 'That player account does not exist.';
  end if;

  insert into public.characters (
    name,
    kind,
    owner_user_id,
    class_key,
    class_name,
    level,
    max_hp,
    current_hp,
    max_mana,
    current_mana,
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
    coalesce(nullif(trim(p_class_key), ''), 'adventurer'),
    coalesce(nullif(trim(p_class_name), ''), 'Adventurer'),
    greatest(1, coalesce(p_level, 1)),
    greatest(0, coalesce(p_max_hp, 100)),
    greatest(0, coalesce(p_current_hp, p_max_hp, 100)),
    greatest(0, coalesce(p_max_mana, 0)),
    greatest(0, coalesce(p_current_mana, p_max_mana, 0)),
    greatest(0, least(coalesce(p_inventory_slots, 12), 120)),
    greatest(0, coalesce(p_spell_slots, 0)),
    case when jsonb_typeof(coalesce(p_attributes, '{}'::jsonb)) = 'object' then coalesce(p_attributes, '{}'::jsonb) else '{}'::jsonb end,
    case when jsonb_typeof(coalesce(p_class_passives, '[]'::jsonb)) = 'array' then coalesce(p_class_passives, '[]'::jsonb) else '[]'::jsonb end,
    coalesce(p_personal_passives, ''),
    coalesce(nullif(trim(p_token_color), ''), '#9caf79'),
    'Calostrynn'
  )
  returning * into v_character;

  return public.character_record_to_json(v_character);
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
  v_patch jsonb := coalesce(p_patch, '{}'::jsonb);
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

  update public.characters
  set
    name = case when v_patch ? 'name' then coalesce(nullif(trim(v_patch->>'name'), ''), name) else name end,
    level = case when v_patch ? 'level' then greatest(1, (v_patch->>'level')::int) else level end,
    max_hp = case when v_patch ? 'maxHp' then greatest(0, (v_patch->>'maxHp')::int) else max_hp end,
    current_hp = case when v_patch ? 'currentHp' then greatest(0, (v_patch->>'currentHp')::int) else current_hp end,
    max_mana = case when v_patch ? 'maxMana' then greatest(0, (v_patch->>'maxMana')::int) else max_mana end,
    current_mana = case when v_patch ? 'currentMana' then greatest(0, (v_patch->>'currentMana')::int) else current_mana end,
    inventory_slots = case when v_patch ? 'inventorySlots' then greatest(0, least((v_patch->>'inventorySlots')::int, 120)) else inventory_slots end,
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

grant execute on function public.profile_from_campaign_session(text) to anon, authenticated;
grant execute on function public.character_record_to_json(public.characters) to anon, authenticated;
grant execute on function public.get_character_ledger(text) to anon, authenticated;
grant execute on function public.create_campaign_character(text, text, uuid, text, text, int, int, int, int, int, int, int, jsonb, jsonb, text, text) to anon, authenticated;
grant execute on function public.update_campaign_character(text, uuid, jsonb) to anon, authenticated;

-- ============================================================
-- Source: supabase\migrations\20260711000400_dashboard_shell_state.sql
-- ============================================================

-- Dashboard shell state
-- Gives the app shell a lightweight, session-safe way to detect combat lock and notification count.

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
    'notifications', '[]'::jsonb
  );
end;
$$;

grant execute on function public.get_dashboard_state(text) to anon, authenticated;

-- ============================================================
-- Source: supabase\migrations\20260711000500_character_ledger_expansion.sql
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
  inventory_slots,
  spell_slots,
  attributes,
  passives,
  token_color
)
values
  ('alchemist', 'Alchemist', 'Support Â· Decent sustain', 'Light armor', 'Intelligent and resourceful seekers of knowledge, renowned for their command of potions and alchemical craft.', 110, 50, 16, 2, '{"strength":-1,"agility":0,"vitality":-1,"intelligence":1,"recovery":1,"charisma":0,"accuracy":0,"range":0,"mana_regen":0,"perception":0,"alchemy":5,"stealth":0}'::jsonb, '["Once per combat, use or make a potion or alchemical item without spending the main action or movement.","Has unlimited flasks and Arcane Nectar while maintaining a house or residence."]'::jsonb, '#4d8f83'),
  ('apothecary', 'Apothecary', 'Support Â· Great sustain', 'Medium armor', 'Durable battlefield mages whose restorative support can hold a party together even on the front line.', 130, 90, 15, 5, '{"strength":-3,"agility":-1,"vitality":1,"intelligence":0,"recovery":2,"charisma":0,"accuracy":-1,"range":0,"mana_regen":2,"perception":0,"alchemy":2,"stealth":-2}'::jsonb, '["Can heal an ally for 5 HP in place of movement."]'::jsonb, '#5579a8'),
  ('apprentice', 'Apprentice', 'Hybrid Â· Decent sustain', 'Medium armor', 'Naturally talented learners who trade some magical utility for freedom, adaptability, and staying power.', 100, 75, 16, 5, '{"strength":0,"agility":1,"vitality":-1,"intelligence":1,"recovery":0,"charisma":0,"accuracy":0,"range":0,"mana_regen":1,"perception":0,"alchemy":1,"stealth":0}'::jsonb, '["While paired with a Mage: +1 Intelligence.","While paired with a Knight: +1 Strength.","While paired with a Ranger: +1 Accuracy. These bonuses can stack."]'::jsonb, '#8a6da1'),
  ('armor-clad', 'Armor-clad', 'Defense Â· Great sustain', 'Heavy armor', 'Relentless front-line warriors who sacrifice speed and subtlety for overwhelming defensive presence.', 165, 50, 10, 1, '{"strength":2,"agility":-3,"vitality":3,"intelligence":-3,"recovery":0,"charisma":-1,"accuracy":0,"range":-2,"mana_regen":0,"perception":-1,"alchemy":1,"stealth":-2}'::jsonb, '["Distribution redirects 50% of a targetâ€™s incoming damage to the Armor-clad.","Pays only material costs for armor labor.","Cannot receive additional defensive bonuses from shields."]'::jsonb, '#9a6e52'),
  ('beastmaster', 'Beastmaster', 'Hybrid Â· Poor sustain', 'Light armor', 'Rare animal handlers whose companions become a force of their own across the battlefield.', 90, 50, 20, 1, '{"strength":-3,"agility":1,"vitality":0,"intelligence":0,"recovery":1,"charisma":3,"accuracy":1,"range":0,"mana_regen":0,"perception":2,"alchemy":0,"stealth":0}'::jsonb, '["Tame is a free spell and uses d6 + Charisma + buffs against a creatureâ€™s Wild score.","May bring up to 20 Wild score worth of beasts per mission."]'::jsonb, '#77875a'),
  ('blacksmith', 'Blacksmith', 'Support Â· Decent sustain', 'Medium armor', 'Practical craftspeople whose command of tools, weapons, armor, and runes makes them invaluable anywhere.', 125, 50, 18, 3, '{"strength":2,"agility":-1,"vitality":1,"intelligence":0,"recovery":0,"charisma":2,"accuracy":0,"range":-2,"mana_regen":0,"perception":0,"alchemy":1,"stealth":-1}'::jsonb, '["Pays only material costs for smithing labor.","Once per combat, grant a chosen melee weapon +1 Strength until combat or the scene ends."]'::jsonb, '#b28b45'),
  ('knight', 'Knight', 'Attack Â· Decent sustain', 'Medium armor', 'Well-rounded combat experts with political presence, battlefield leadership, and a talent for mounted fighting.', 125, 25, 14, 2, '{"strength":1,"agility":0,"vitality":1,"intelligence":-1,"recovery":0,"charisma":2,"accuracy":1,"range":-1,"mana_regen":-2,"perception":0,"alchemy":-1,"stealth":0}'::jsonb, '["+1 Strength while mounted on a horse.","When hit, a parry roll of 18â€“20 prevents all damage; 15â€“17 prevents half."]'::jsonb, '#a05e5a'),
  ('mage', 'Mage', 'Attack Â· Poor sustain', 'Light armor', 'Versatile magical heavy-hitters with an answer for nearly every problemâ€”provided they survive long enough to cast it.', 70, 100, 10, 10, '{"strength":-3,"agility":0,"vitality":-3,"intelligence":3,"recovery":0,"charisma":1,"accuracy":0,"range":1,"mana_regen":1,"perception":0,"alchemy":0,"stealth":0}'::jsonb, '["Regain 10 Mana whenever an enemy is killed with a spell."]'::jsonb, '#567a7f'),
  ('mendrunner', 'Mendrunner', 'Hybrid Â· Poor sustain', 'Medium armor', 'Nimble practitioners of botany and natural medicine who reject magic in favor of hard-won remedies.', 85, 0, 20, 0, '{"strength":-1,"agility":3,"vitality":0,"intelligence":-5,"recovery":3,"charisma":-3,"accuracy":1,"range":0,"mana_regen":0,"perception":3,"alchemy":4,"stealth":1}'::jsonb, '["Heal an ally for 2d6 + Recovery + Alchemy and remove one debuff or negative effect.","Immune to poison and illness."]'::jsonb, '#6b8f68'),
  ('the-muscle', 'The Muscle', 'Defense Â· Great sustain', 'Medium armor', 'Notorious for a large frame and small brains, built to soak punishment and become the groupâ€™s blunt-force answer.', 150, 40, 10, 1, '{"strength":3,"agility":-1,"vitality":1,"intelligence":-3,"recovery":2,"charisma":-2,"accuracy":-2,"range":-2,"mana_regen":0,"perception":-1,"alchemy":-2,"stealth":-2}'::jsonb, '["When The Muscle kills an enemy, gain 1d6 for ensuing damage rolls. Resets after each combat or scene ends. Max of 5d6."]'::jsonb, '#9f6540'),
  ('ranger', 'Ranger', 'Attack Â· Poor sustain', 'Light armor', 'Back-line attackers and scouts who combine punishing range with reconnaissance and specialized ammunition.', 90, 50, 15, 1, '{"strength":-2,"agility":1,"vitality":-2,"intelligence":1,"recovery":0,"charisma":0,"accuracy":2,"range":3,"mana_regen":0,"perception":2,"alchemy":0,"stealth":1}'::jsonb, '["Can tame birds.","Three times per combat, fire three arrows in one draw.","May buy and craft elemental or effect-tipped arrows."]'::jsonb, '#7c8a49'),
  ('rogue', 'Rogue', 'Attack Â· Poor sustain', 'Light armor', 'Cunning duelists who thrive on surprise, isolation, and catching enemies at their most vulnerable.', 90, 50, 16, 3, '{"strength":-1,"agility":2,"vitality":-1,"intelligence":0,"recovery":0,"charisma":-3,"accuracy":0,"range":0,"mana_regen":0,"perception":3,"alchemy":1,"stealth":3}'::jsonb, '["Backstab deals double damage from behind, from stealth, or against a pinned or defenseless target.","May use Agility instead of Strength for attacks that trigger Backstab."]'::jsonb, '#6b617e'),
  ('sage', 'Sage', 'Support Â· Poor sustain', 'Medium armor', 'Selfless support casters whose mastery of recovery turns a single act of healing into aid for the whole party.', 70, 100, 12, 5, '{"strength":-2,"agility":2,"vitality":-2,"intelligence":-5,"recovery":3,"charisma":2,"accuracy":-2,"range":0,"mana_regen":2,"perception":0,"alchemy":0,"stealth":0}'::jsonb, '["Healing and enhancement spells use Recovery instead of Intelligence for magic rolls.","Heals also restore half the amount, rounded up, to another ally or the original target."]'::jsonb, '#7581a0'),
  ('talismanist', 'Talismanist', 'Attack Â· Decent sustain', 'Medium armor', 'Rune-armed warriors who bind magic into weapons and armor, turning every piece of gear into a spell vessel.', 125, 100, 10, 0, '{"strength":1,"agility":0,"vitality":1,"intelligence":1,"recovery":0,"charisma":0,"accuracy":1,"range":0,"mana_regen":0,"perception":0,"alchemy":-1,"stealth":-2}'::jsonb, '["Begins with three random low-level runes.","Each spell-infused weapon on hand can cast its spell twice per combat."]'::jsonb, '#926d9f'),
  ('warden', 'Warden', 'Hybrid Â· Decent sustain', 'Medium armor', 'Jack-of-all-trades survivalists with broad usefulness, cunning instincts, and flexible party support.', 110, 75, 20, 3, '{"strength":0,"agility":0,"vitality":0,"intelligence":0,"recovery":0,"charisma":-2,"accuracy":0,"range":0,"mana_regen":0,"perception":2,"alchemy":1,"stealth":0}'::jsonb, '["Once per combat or exploration scene, reroll a failed Perception, Alchemy, Survival, or Utility check.","Gains a +2 modifier of choice in a single category where the party has no bonuses."]'::jsonb, '#79895f')
on conflict (class_key) do update
set
  name = excluded.name,
  role = excluded.role,
  armor = excluded.armor,
  identity = excluded.identity,
  base_hp = excluded.base_hp,
  base_mana = excluded.base_mana,
  inventory_slots = excluded.inventory_slots,
  spell_slots = excluded.spell_slots,
  attributes = excluded.attributes,
  passives = excluded.passives,
  token_color = excluded.token_color;

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
    v_template.inventory_slots,
    v_template.spell_slots,
    v_template.attributes,
    v_template.passives,
    coalesce(p_personal_passives, ''),
    coalesce(nullif(trim(p_token_color), ''), v_template.token_color),
    'Calostrynn'
  )
  returning * into v_character;

  return public.character_record_to_json(v_character);
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
    inventory_slots = case when v_patch ? 'inventorySlots' then greatest(0, least((v_patch->>'inventorySlots')::int, 120)) else inventory_slots end,
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

grant execute on function public.class_template_record_to_json(public.class_templates) to anon, authenticated;
grant execute on function public.get_character_ledger(text) to anon, authenticated;
grant execute on function public.create_campaign_character(text, text, uuid, text, text, text) to anon, authenticated;
grant execute on function public.update_campaign_character(text, uuid, jsonb) to anon, authenticated;
