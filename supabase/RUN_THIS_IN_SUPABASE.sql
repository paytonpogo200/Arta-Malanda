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
  create type public.item_type as enum ('weapon', 'armor', 'shield', 'pet', 'accessory', 'storage', 'ore', 'potion', 'food', 'plant', 'fabric', 'tool', 'quest', 'currency', 'misc');
exception when duplicate_object then null;
end $$;

do $$
begin
  if not exists (
    select 1
    from pg_enum e
    join pg_type t on t.oid = e.enumtypid
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'public'
      and t.typname = 'item_type'
      and e.enumlabel = 'currency'
  ) then
    alter type public.item_type add value 'currency' before 'misc';
  end if;
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
  previous_owner_name text not null default '',
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
-- ============================================================

-- Character ledger foundation

alter table public.characters
  add column if not exists class_key text;

update public.characters
set class_key = lower(regexp_replace(class_name, '[^a-zA-Z0-9]+', '-', 'g'))
where class_key is null;

alter table public.characters
  alter column class_key set default 'adventurer';

alter table public.characters
  add column if not exists previous_owner_name text not null default '';

do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'characters'
      and column_name = 'legacy_owner_name'
  ) then
    update public.characters
    set previous_owner_name = legacy_owner_name
    where previous_owner_name = ''
      and legacy_owner_name <> '';

    alter table public.characters drop column legacy_owner_name;
  end if;
end $$;

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

create or replace function public.is_retired_bestiary_category(p_category text)
returns boolean
language sql
immutable
as $$
  select lower(trim(coalesce(p_category, ''))) in ('animal', 'beast', 'being', 'monster', 'spirit')
$$;

create or replace function public.purge_retired_bestiary_categories()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  delete from public.bestiary_entities
  where public.is_retired_bestiary_category(category);

  delete from public.bestiary_categories
  where public.is_retired_bestiary_category(category_key)
     or public.is_retired_bestiary_category(name);
end;
$$;

select public.purge_retired_bestiary_categories();

insert into public.bestiary_categories (category_key, name, display_order)
select distinct
  e.category,
  initcap(replace(e.category, '-', ' ')),
  1000
from public.bestiary_entities e
where not public.is_retired_bestiary_category(e.category)
  and not exists (
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
  perform public.purge_retired_bestiary_categories();

  return jsonb_build_object(
    'categories', (
      select coalesce(jsonb_agg(public.bestiary_category_record_to_json(c) order by c.display_order, c.name), '[]'::jsonb)
      from public.bestiary_categories c
      where not public.is_retired_bestiary_category(c.category_key)
        and not public.is_retired_bestiary_category(c.name)
        and (v_is_dm or not c.is_hidden)
    ),
    'entities', (
      select coalesce(jsonb_agg(public.bestiary_entity_record_to_json(e) order by coalesce(c.display_order, 999999), e.display_order, e.name), '[]'::jsonb)
      from public.bestiary_entities e
      left join public.bestiary_categories c on c.category_key = e.category
      where not public.is_retired_bestiary_category(e.category)
        and (v_is_dm or e.is_unlocked)
        and (v_is_dm or coalesce(c.is_hidden, false) = false)
    ),
    'unlockedCount', (
      select count(*)
      from public.bestiary_entities e
      left join public.bestiary_categories c on c.category_key = e.category
      where not public.is_retired_bestiary_category(e.category)
        and e.is_unlocked
        and (v_is_dm or coalesce(c.is_hidden, false) = false)
    ),
    'totalCount', (
      select count(*)
      from public.bestiary_entities e
      left join public.bestiary_categories c on c.category_key = e.category
      where not public.is_retired_bestiary_category(e.category)
        and (v_is_dm or (e.is_unlocked and coalesce(c.is_hidden, false) = false))
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

  if public.is_retired_bestiary_category(v_category_key)
    or public.is_retired_bestiary_category(v_patch->>'name') then
    raise exception 'That retired bestiary category cannot be restored.';
  end if;

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
    if public.is_retired_bestiary_category(v_category_key) then
      raise exception 'That retired bestiary category cannot be restored.';
    end if;
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
grant execute on function public.is_retired_bestiary_category(text) to anon, authenticated;
grant execute on function public.purge_retired_bestiary_categories() to anon, authenticated;
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
    if public.is_retired_bestiary_category(v_category_key)
      or public.is_retired_bestiary_category(v_category->>'name') then
      continue;
    end if;

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
    if public.is_retired_bestiary_category(v_category_key) then
      continue;
    end if;

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

  perform public.purge_retired_bestiary_categories();

  return public.get_bestiary(p_session_token);
end;
$$;

drop function if exists public.import_bestiary_markdown(text, jsonb, jsonb);
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
  inventory_slots,
  spell_slots,
  attributes,
  passives,
  token_color
)
values
  ('alchemist', 'Alchemist', 'Support · Decent sustain', 'Light armor', 'Intelligent and resourceful seekers of knowledge, renowned for their command of potions and alchemical craft.', 110, 50, 16, 2, '{"strength":-1,"agility":0,"vitality":-1,"intelligence":1,"recovery":1,"charisma":0,"accuracy":0,"range":0,"mana_regen":0,"perception":0,"alchemy":5,"stealth":0}'::jsonb, '["Once per combat, use or make a potion or alchemical item without spending the main action or movement.","Has unlimited flasks and Arcane Nectar while maintaining a house or residence."]'::jsonb, '#4d8f83'),
  ('apothecary', 'Apothecary', 'Support · Great sustain', 'Medium armor', 'Durable battlefield mages whose restorative support can hold a party together even on the front line.', 130, 90, 15, 5, '{"strength":-3,"agility":-1,"vitality":1,"intelligence":0,"recovery":2,"charisma":0,"accuracy":-1,"range":0,"mana_regen":2,"perception":0,"alchemy":2,"stealth":-2}'::jsonb, '["Can heal an ally for 5 HP in place of movement."]'::jsonb, '#5579a8'),
  ('apprentice', 'Apprentice', 'Hybrid · Decent sustain', 'Medium armor', 'Naturally talented learners who trade some magical utility for freedom, adaptability, and staying power.', 100, 75, 16, 5, '{"strength":0,"agility":1,"vitality":-1,"intelligence":1,"recovery":0,"charisma":0,"accuracy":0,"range":0,"mana_regen":1,"perception":0,"alchemy":1,"stealth":0}'::jsonb, '["While paired with a Mage: +1 Intelligence.","While paired with a Knight: +1 Strength.","While paired with a Ranger: +1 Accuracy. These bonuses can stack."]'::jsonb, '#8a6da1'),
  ('armor-clad', 'Armor-clad', 'Defense · Great sustain', 'Heavy armor', 'Relentless front-line warriors who sacrifice speed and subtlety for overwhelming defensive presence.', 165, 50, 10, 1, '{"strength":2,"agility":-3,"vitality":3,"intelligence":-3,"recovery":0,"charisma":-1,"accuracy":0,"range":-2,"mana_regen":0,"perception":-1,"alchemy":1,"stealth":-2}'::jsonb, '["Distribution redirects 50% of a target’s incoming damage to the Armor-clad.","Pays only material costs for armor labor.","Cannot receive additional defensive bonuses from shields."]'::jsonb, '#9a6e52'),
  ('beastmaster', 'Beastmaster', 'Hybrid · Poor sustain', 'Light armor', 'Rare animal handlers whose companions become a force of their own across the battlefield.', 90, 50, 20, 1, '{"strength":-3,"agility":1,"vitality":0,"intelligence":0,"recovery":1,"charisma":3,"accuracy":1,"range":0,"mana_regen":0,"perception":2,"alchemy":0,"stealth":0}'::jsonb, '["Tame is a free spell and uses d6 + Charisma + buffs against a creature’s Wild score.","May bring up to 20 Wild score worth of beasts per mission."]'::jsonb, '#77875a'),
  ('blacksmith', 'Blacksmith', 'Support · Decent sustain', 'Medium armor', 'Practical craftspeople whose command of tools, weapons, armor, and runes makes them invaluable anywhere.', 125, 50, 18, 3, '{"strength":2,"agility":-1,"vitality":1,"intelligence":0,"recovery":0,"charisma":2,"accuracy":0,"range":-2,"mana_regen":0,"perception":0,"alchemy":1,"stealth":-1}'::jsonb, '["Pays only material costs for smithing labor.","Once per combat, grant a chosen melee weapon +1 Strength until combat or the scene ends."]'::jsonb, '#b28b45'),
  ('knight', 'Knight', 'Attack · Decent sustain', 'Medium armor', 'Well-rounded combat experts with political presence, battlefield leadership, and a talent for mounted fighting.', 125, 25, 14, 2, '{"strength":1,"agility":0,"vitality":1,"intelligence":-1,"recovery":0,"charisma":2,"accuracy":1,"range":-1,"mana_regen":-2,"perception":0,"alchemy":-1,"stealth":0}'::jsonb, '["+1 Strength while mounted on a horse.","When hit, a parry roll of 18–20 prevents all damage; 15–17 prevents half."]'::jsonb, '#a05e5a'),
  ('mage', 'Mage', 'Attack · Poor sustain', 'Light armor', 'Versatile magical heavy-hitters with an answer for nearly every problem—provided they survive long enough to cast it.', 70, 100, 10, 10, '{"strength":-3,"agility":0,"vitality":-3,"intelligence":3,"recovery":0,"charisma":1,"accuracy":0,"range":1,"mana_regen":1,"perception":0,"alchemy":0,"stealth":0}'::jsonb, '["Regain 10 Mana whenever an enemy is killed with a spell."]'::jsonb, '#567a7f'),
  ('mendrunner', 'Mendrunner', 'Hybrid · Poor sustain', 'Medium armor', 'Nimble practitioners of botany and natural medicine who reject magic in favor of hard-won remedies.', 85, 0, 20, 0, '{"strength":-1,"agility":3,"vitality":0,"intelligence":-5,"recovery":3,"charisma":-3,"accuracy":1,"range":0,"mana_regen":0,"perception":3,"alchemy":4,"stealth":1}'::jsonb, '["Heal an ally for 2d6 + Recovery + Alchemy and remove one debuff or negative effect.","Immune to poison and illness."]'::jsonb, '#6b8f68'),
  ('the-muscle', 'The Muscle', 'Defense · Great sustain', 'Medium armor', 'Notorious for a large frame and small brains, built to soak punishment and become the group’s blunt-force answer.', 150, 40, 10, 1, '{"strength":3,"agility":-1,"vitality":1,"intelligence":-3,"recovery":2,"charisma":-2,"accuracy":-2,"range":-2,"mana_regen":0,"perception":-1,"alchemy":-2,"stealth":-2}'::jsonb, '["When The Muscle kills an enemy, gain 1d6 for ensuing damage rolls. Resets after each combat or scene ends. Max of 5d6."]'::jsonb, '#9f6540'),
  ('ranger', 'Ranger', 'Attack · Poor sustain', 'Light armor', 'Back-line attackers and scouts who combine punishing range with reconnaissance and specialized ammunition.', 90, 50, 15, 1, '{"strength":-2,"agility":1,"vitality":-2,"intelligence":1,"recovery":0,"charisma":0,"accuracy":2,"range":3,"mana_regen":0,"perception":2,"alchemy":0,"stealth":1}'::jsonb, '["Can tame birds.","Three times per combat, fire three arrows in one draw.","May buy and craft elemental or effect-tipped arrows."]'::jsonb, '#7c8a49'),
  ('rogue', 'Rogue', 'Attack · Poor sustain', 'Light armor', 'Cunning duelists who thrive on surprise, isolation, and catching enemies at their most vulnerable.', 90, 50, 16, 3, '{"strength":-1,"agility":2,"vitality":-1,"intelligence":0,"recovery":0,"charisma":-3,"accuracy":0,"range":0,"mana_regen":0,"perception":3,"alchemy":1,"stealth":3}'::jsonb, '["Backstab deals double damage from behind, from stealth, or against a pinned or defenseless target.","May use Agility instead of Strength for attacks that trigger Backstab."]'::jsonb, '#6b617e'),
  ('sage', 'Sage', 'Support · Poor sustain', 'Medium armor', 'Selfless support casters whose mastery of recovery turns a single act of healing into aid for the whole party.', 70, 100, 12, 5, '{"strength":-2,"agility":2,"vitality":-2,"intelligence":-5,"recovery":3,"charisma":2,"accuracy":-2,"range":0,"mana_regen":2,"perception":0,"alchemy":0,"stealth":0}'::jsonb, '["Healing and enhancement spells use Recovery instead of Intelligence for magic rolls.","Heals also restore half the amount, rounded up, to another ally or the original target."]'::jsonb, '#7581a0'),
  ('talismanist', 'Talismanist', 'Attack · Decent sustain', 'Medium armor', 'Rune-armed warriors who bind magic into weapons and armor, turning every piece of gear into a spell vessel.', 125, 100, 10, 0, '{"strength":1,"agility":0,"vitality":1,"intelligence":1,"recovery":0,"charisma":0,"accuracy":1,"range":0,"mana_regen":0,"perception":0,"alchemy":-1,"stealth":-2}'::jsonb, '["Begins with three random low-level runes.","Each spell-infused weapon on hand can cast its spell twice per combat."]'::jsonb, '#926d9f'),
  ('warden', 'Warden', 'Hybrid · Decent sustain', 'Medium armor', 'Jack-of-all-trades survivalists with broad usefulness, cunning instincts, and flexible party support.', 110, 75, 20, 3, '{"strength":0,"agility":0,"vitality":0,"intelligence":0,"recovery":0,"charisma":-2,"accuracy":0,"range":0,"mana_regen":0,"perception":2,"alchemy":1,"stealth":0}'::jsonb, '["Once per combat or exploration scene, reroll a failed Perception, Alchemy, Survival, or Utility check.","Gains a +2 modifier of choice in a single category where the party has no bonuses."]'::jsonb, '#79895f')
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

create or replace function public.loadout_slot_accepts_item(p_loadout_slot text, p_item_type public.item_type)
returns boolean
language sql
immutable
as $$
  select case
    when p_loadout_slot = 'weapon' then p_item_type = 'weapon'::public.item_type
    when p_loadout_slot = 'armor' then p_item_type = 'armor'::public.item_type
    when p_loadout_slot = 'shield' then p_item_type = 'shield'::public.item_type
    when p_loadout_slot = 'active-pet' then p_item_type = 'pet'::public.item_type
    when p_loadout_slot in ('accessory-1', 'accessory-2', 'accessory-3', 'accessory-4') then p_item_type = 'accessory'::public.item_type
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
    'type', p_item.item_type,
    'rarity', p_item.rarity,
    'quantity', p_item.quantity,
    'slotIndex', p_item.slot_index,
    'loadoutSlot', p_item.loadout_slot,
    'isStorage', p_item.is_storage,
    'storageCapacity', p_item.storage_capacity,
    'modifiers', p_item.modifiers,
    'spellImbue', p_item.spell_imbue
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

create or replace function public.inventory_items_stackable(a public.inventory_items, b public.inventory_items)
returns boolean
language sql
immutable
as $$
  select a.item_name = b.item_name
    and a.item_type = b.item_type
    and a.rarity = b.rarity
    and coalesce(a.spell_imbue, '') = coalesce(b.spell_imbue, '')
    and a.is_storage = false
    and b.is_storage = false
$$;

create or replace function public.add_character_inventory_item(
  p_session_token text,
  p_character_id uuid,
  p_parent_item_id uuid,
  p_slot_index int,
  p_item_name text,
  p_item_type text,
  p_rarity text,
  p_quantity int,
  p_is_storage boolean default false,
  p_storage_capacity int default 0,
  p_modifiers jsonb default '{}'::jsonb,
  p_spell_imbue text default null
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
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;

  v_character := public.assert_inventory_access(v_profile, p_character_id, true);
  perform public.assert_inventory_slot_capacity(v_character, p_parent_item_id, p_slot_index);

  if length(trim(coalesce(p_item_name, ''))) = 0 then
    raise exception 'Item name is required.';
  end if;

  select * into v_target
  from public.inventory_items i
  where i.character_id = p_character_id
    and coalesce(i.parent_item_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(p_parent_item_id, '00000000-0000-0000-0000-000000000000'::uuid)
    and i.loadout_slot is null
    and i.slot_index = p_slot_index
  limit 1;

  if v_target.id is not null then
    if v_target.item_name = trim(p_item_name)
      and v_target.item_type = p_item_type::public.item_type
      and v_target.rarity = p_rarity::public.item_rarity
      and coalesce(v_target.spell_imbue, '') = coalesce(nullif(trim(p_spell_imbue), ''), '')
      and v_target.is_storage = false
      and not coalesce(p_is_storage, false)
    then
      update public.inventory_items
      set quantity = quantity + greatest(1, coalesce(p_quantity, 1))
      where id = v_target.id
      returning * into v_item;
      return public.inventory_item_record_to_json(v_item);
    end if;

    raise exception 'That inventory slot is already occupied.';
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
    p_character_id,
    p_parent_item_id,
    p_slot_index,
    trim(p_item_name),
    p_item_type::public.item_type,
    p_rarity::public.item_rarity,
    greatest(1, coalesce(p_quantity, 1)),
    coalesce(p_is_storage, false),
    case when coalesce(p_is_storage, false) then greatest(1, coalesce(p_storage_capacity, 6)) else 0 end,
    case when jsonb_typeof(coalesce(p_modifiers, '{}'::jsonb)) = 'object' then coalesce(p_modifiers, '{}'::jsonb) else '{}'::jsonb end,
    nullif(trim(coalesce(p_spell_imbue, '')), '')
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
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;

  select * into v_item from public.inventory_items where id = p_item_id;
  if v_item.id is null then raise exception 'Item not found.'; end if;

  v_character := public.assert_inventory_access(v_profile, v_item.character_id, false);

  if (v_patch ? 'name' or v_patch ? 'type' or v_patch ? 'rarity' or v_patch ? 'quantity' or v_patch ? 'isStorage' or v_patch ? 'storageCapacity' or v_patch ? 'spellImbue') and v_profile.role <> 'dm'::public.user_role then
    raise exception 'Only the Dungeon Master can edit item details.';
  end if;

  if v_profile.role = 'dm'::public.user_role then
    update public.inventory_items
    set
      item_name = case when v_patch ? 'name' then coalesce(nullif(trim(v_patch->>'name'), ''), item_name) else item_name end,
      item_type = case when v_patch ? 'type' then (v_patch->>'type')::public.item_type else item_type end,
      rarity = case when v_patch ? 'rarity' then (v_patch->>'rarity')::public.item_rarity else rarity end,
      quantity = case when v_patch ? 'quantity' then greatest(1, (v_patch->>'quantity')::int) else quantity end,
      is_storage = case when v_patch ? 'isStorage' then (v_patch->>'isStorage')::boolean else is_storage end,
      storage_capacity = case when v_patch ? 'storageCapacity' then greatest(0, (v_patch->>'storageCapacity')::int) else storage_capacity end,
      spell_imbue = case when v_patch ? 'spellImbue' then nullif(trim(coalesce(v_patch->>'spellImbue', '')), '') else spell_imbue end
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

    if not public.loadout_slot_accepts_item(v_loadout_slot, v_item.item_type) then
      raise exception 'That item cannot go in that loadout slot.';
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
      if public.inventory_items_stackable(v_item, v_target) then
        update public.inventory_items
        set quantity = quantity + v_item.quantity
        where id = v_target.id
        returning * into v_target;

        delete from public.inventory_items where id = v_item.id;
        return public.inventory_item_record_to_json(v_target);
      end if;

      raise exception 'That inventory slot is already occupied.';
    end if;

    update public.inventory_items
    set parent_item_id = v_parent_item_id, slot_index = v_slot_index, loadout_slot = null
    where id = p_item_id
    returning * into v_item;
  end if;

  return public.inventory_item_record_to_json(v_item);
end;
$$;

create or replace function public.drop_inventory_item_quantity(
  p_session_token text,
  p_item_id uuid,
  p_quantity int
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_item public.inventory_items%rowtype;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;

  select * into v_item from public.inventory_items where id = p_item_id;
  if v_item.id is null then raise exception 'Item not found.'; end if;

  perform public.assert_inventory_access(v_profile, v_item.character_id, false);

  if greatest(1, coalesce(p_quantity, 1)) >= v_item.quantity then
    delete from public.inventory_items where id = v_item.id;
    return null;
  end if;

  update public.inventory_items
  set quantity = quantity - greatest(1, coalesce(p_quantity, 1))
  where id = v_item.id
  returning * into v_item;

  return public.inventory_item_record_to_json(v_item);
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

grant execute on function public.loadout_slot_accepts_item(text, public.item_type) to anon, authenticated;
grant execute on function public.inventory_item_record_to_json(public.inventory_items) to anon, authenticated;
grant execute on function public.wallet_balances_for_character(uuid) to anon, authenticated;
grant execute on function public.get_character_inventory(text, uuid) to anon, authenticated;
grant execute on function public.assert_inventory_access(public.profiles, uuid, boolean) to anon, authenticated;
grant execute on function public.find_first_free_inventory_slot(uuid, uuid, int) to anon, authenticated;
grant execute on function public.assert_inventory_slot_capacity(public.characters, uuid, int) to anon, authenticated;
grant execute on function public.inventory_items_stackable(public.inventory_items, public.inventory_items) to anon, authenticated;
grant execute on function public.add_character_inventory_item(text, uuid, uuid, int, text, text, text, int, boolean, int, jsonb, text) to anon, authenticated;
grant execute on function public.update_inventory_item_state(text, uuid, jsonb) to anon, authenticated;
grant execute on function public.drop_inventory_item_quantity(text, uuid, int) to anon, authenticated;
grant execute on function public.set_character_wallet_balances(text, uuid, jsonb) to anon, authenticated;


-- ============================================================
-- ============================================================

-- House, property, and storage foundation.

create table if not exists public.player_houses (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null unique references public.profiles(id) on delete cascade,
  city_name text not null default 'Calostrynn',
  inventory_slots int not null default 50 check (inventory_slots between 0 and 500),
  property_slots int not null default 10 check (property_slots between 0 and 200),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.house_inventory_items (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references public.profiles(id) on delete cascade,
  item_name text not null,
  item_type public.item_type not null default 'misc',
  rarity public.item_rarity not null default 'Common',
  quantity int not null default 1 check (quantity > 0),
  slot_index int not null default 0 check (slot_index >= 0),
  is_storage boolean not null default false,
  storage_capacity int not null default 0 check (storage_capacity between 0 and 500),
  modifiers jsonb not null default '{}'::jsonb check (jsonb_typeof(modifiers) = 'object'),
  spell_imbue text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists house_inventory_main_slot_unique
  on public.house_inventory_items (owner_user_id, slot_index);

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

alter table public.player_houses enable row level security;
alter table public.house_inventory_items enable row level security;
alter table public.campaign_properties enable row level security;

revoke all on public.player_houses from anon, authenticated;
revoke all on public.house_inventory_items from anon, authenticated;
revoke all on public.campaign_properties from anon, authenticated;

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
    'propertySlots', p_house.property_slots
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
    'parentItemId', null,
    'name', p_item.item_name,
    'type', p_item.item_type,
    'rarity', p_item.rarity,
    'quantity', p_item.quantity,
    'slotIndex', p_item.slot_index,
    'loadoutSlot', null,
    'isStorage', p_item.is_storage,
    'storageCapacity', p_item.storage_capacity,
    'modifiers', p_item.modifiers,
    'spellImbue', p_item.spell_imbue
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
immutable
as $$
  select a.item_name = b.item_name
    and a.item_type = b.item_type
    and a.rarity = b.rarity
    and coalesce(a.spell_imbue, '') = coalesce(b.spell_imbue, '')
    and a.is_storage = false
    and b.is_storage = false
$$;

create or replace function public.find_first_free_house_slot(p_owner_user_id uuid, p_capacity int)
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
        and i.slot_index = v_slot
    ) then
      return v_slot;
    end if;
  end loop;

  return null;
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

create or replace function public.add_house_inventory_item(
  p_session_token text,
  p_owner_user_id uuid,
  p_slot_index int,
  p_item_name text,
  p_item_type text,
  p_rarity text,
  p_quantity int,
  p_is_storage boolean default false,
  p_storage_capacity int default 0,
  p_modifiers jsonb default '{}'::jsonb,
  p_spell_imbue text default null
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
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  v_house := public.assert_house_access(v_profile, p_owner_user_id, true);

  if p_slot_index < 0 or p_slot_index >= v_house.inventory_slots then
    raise exception 'House slot is outside the house capacity.';
  end if;

  if length(trim(coalesce(p_item_name, ''))) = 0 then
    raise exception 'Item name is required.';
  end if;

  select * into v_target
  from public.house_inventory_items i
  where i.owner_user_id = p_owner_user_id
    and i.slot_index = p_slot_index
  limit 1;

  if v_target.id is not null then
    if v_target.item_name = trim(p_item_name)
      and v_target.item_type = p_item_type::public.item_type
      and v_target.rarity = p_rarity::public.item_rarity
      and coalesce(v_target.spell_imbue, '') = coalesce(nullif(trim(p_spell_imbue), ''), '')
      and v_target.is_storage = false
      and not coalesce(p_is_storage, false)
    then
      update public.house_inventory_items
      set quantity = quantity + greatest(1, coalesce(p_quantity, 1))
      where id = v_target.id
      returning * into v_item;
      return public.house_item_record_to_json(v_item);
    end if;

    raise exception 'That house slot is already occupied.';
  end if;

  insert into public.house_inventory_items (
    owner_user_id,
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
    p_owner_user_id,
    p_slot_index,
    trim(p_item_name),
    p_item_type::public.item_type,
    p_rarity::public.item_rarity,
    greatest(1, coalesce(p_quantity, 1)),
    coalesce(p_is_storage, false),
    case when coalesce(p_is_storage, false) then greatest(1, coalesce(p_storage_capacity, 6)) else 0 end,
    case when jsonb_typeof(coalesce(p_modifiers, '{}'::jsonb)) = 'object' then coalesce(p_modifiers, '{}'::jsonb) else '{}'::jsonb end,
    nullif(trim(coalesce(p_spell_imbue, '')), '')
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
  v_slot_index int;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;

  select * into v_item from public.house_inventory_items where id = p_item_id;
  if v_item.id is null then raise exception 'House item not found.'; end if;

  v_house := public.assert_house_access(v_profile, v_item.owner_user_id, false);

  if (v_patch ? 'name' or v_patch ? 'type' or v_patch ? 'rarity' or v_patch ? 'quantity' or v_patch ? 'isStorage' or v_patch ? 'storageCapacity' or v_patch ? 'spellImbue') and v_profile.role <> 'dm'::public.user_role then
    raise exception 'Only the Dungeon Master can edit item details.';
  end if;

  if v_profile.role = 'dm'::public.user_role then
    update public.house_inventory_items
    set
      item_name = case when v_patch ? 'name' then coalesce(nullif(trim(v_patch->>'name'), ''), item_name) else item_name end,
      item_type = case when v_patch ? 'type' then (v_patch->>'type')::public.item_type else item_type end,
      rarity = case when v_patch ? 'rarity' then (v_patch->>'rarity')::public.item_rarity else rarity end,
      quantity = case when v_patch ? 'quantity' then greatest(1, (v_patch->>'quantity')::int) else quantity end,
      is_storage = case when v_patch ? 'isStorage' then (v_patch->>'isStorage')::boolean else is_storage end,
      storage_capacity = case when v_patch ? 'storageCapacity' then greatest(0, (v_patch->>'storageCapacity')::int) else storage_capacity end,
      spell_imbue = case when v_patch ? 'spellImbue' then nullif(trim(coalesce(v_patch->>'spellImbue', '')), '') else spell_imbue end
    where id = p_item_id
    returning * into v_item;
  end if;

  if v_patch ? 'slotIndex' then
    v_slot_index := (v_patch->>'slotIndex')::int;
    if v_slot_index < 0 or v_slot_index >= v_house.inventory_slots then
      raise exception 'House slot is outside the house capacity.';
    end if;

    select * into v_target
    from public.house_inventory_items i
    where i.owner_user_id = v_item.owner_user_id
      and i.slot_index = v_slot_index
      and i.id <> v_item.id
    limit 1;

    if v_target.id is not null then
      if public.house_inventory_items_stackable(v_item, v_target) then
        update public.house_inventory_items
        set quantity = quantity + v_item.quantity
        where id = v_target.id
        returning * into v_target;

        delete from public.house_inventory_items where id = v_item.id;
        return public.house_item_record_to_json(v_target);
      end if;

      raise exception 'That house slot is already occupied.';
    end if;

    update public.house_inventory_items
    set slot_index = v_slot_index
    where id = p_item_id
    returning * into v_item;
  end if;

  return public.house_item_record_to_json(v_item);
end;
$$;

create or replace function public.drop_house_inventory_item_quantity(
  p_session_token text,
  p_item_id uuid,
  p_quantity int
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_item public.house_inventory_items%rowtype;
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;

  select * into v_item from public.house_inventory_items where id = p_item_id;
  if v_item.id is null then raise exception 'House item not found.'; end if;

  perform public.assert_house_access(v_profile, v_item.owner_user_id, false);

  if greatest(1, coalesce(p_quantity, 1)) >= v_item.quantity then
    delete from public.house_inventory_items where id = v_item.id;
    return null;
  end if;

  update public.house_inventory_items
  set quantity = quantity - greatest(1, coalesce(p_quantity, 1))
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

  v_house := public.ensure_player_house(v_character.owner_user_id);

  select * into v_target
  from public.house_inventory_items h
  where h.owner_user_id = v_character.owner_user_id
    and h.item_name = v_item.item_name
    and h.item_type = v_item.item_type
    and h.rarity = v_item.rarity
    and coalesce(h.spell_imbue, '') = coalesce(v_item.spell_imbue, '')
    and h.is_storage = false
    and v_item.is_storage = false
  order by h.slot_index
  limit 1;

  if v_target.id is not null then
    update public.house_inventory_items
    set quantity = quantity + v_item.quantity
    where id = v_target.id;

    delete from public.inventory_items where id = v_item.id;
    return public.get_player_house(p_session_token, v_character.owner_user_id);
  end if;

  v_slot_index := public.find_first_free_house_slot(v_character.owner_user_id, v_house.inventory_slots);
  if v_slot_index is null then
    raise exception 'No open house inventory slot.';
  end if;

  insert into public.house_inventory_items (
    owner_user_id,
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
    v_character.owner_user_id,
    v_slot_index,
    v_item.item_name,
    v_item.item_type,
    v_item.rarity,
    v_item.quantity,
    v_item.is_storage,
    v_item.storage_capacity,
    v_item.modifiers,
    v_item.spell_imbue
  )
  returning * into v_house_item;

  delete from public.inventory_items where id = v_item.id;
  return public.get_player_house(p_session_token, v_character.owner_user_id);
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
grant execute on function public.find_first_free_house_slot(uuid, int) to anon, authenticated;
grant execute on function public.get_player_house(text, uuid) to anon, authenticated;
grant execute on function public.add_house_inventory_item(text, uuid, int, text, text, text, int, boolean, int, jsonb, text) to anon, authenticated;
grant execute on function public.update_house_inventory_item_state(text, uuid, jsonb) to anon, authenticated;
grant execute on function public.drop_house_inventory_item_quantity(text, uuid, int) to anon, authenticated;
grant execute on function public.move_inventory_item_to_house(text, uuid) to anon, authenticated;
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
      select coalesce(jsonb_agg(public.combatant_record_to_json(c) order by c.created_at, c.id), '[]'::jsonb)
      from public.combatants c
      where v_battle.id is not null
        and c.battle_id = v_battle.id
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
grant execute on function public.get_battle_room(text) to anon, authenticated;
grant execute on function public.start_campaign_battle(text, uuid[], int, int) to anon, authenticated;
grant execute on function public.update_combatant_state(text, uuid, jsonb) to anon, authenticated;
grant execute on function public.remove_combatant_from_battle(text, uuid) to anon, authenticated;
grant execute on function public.end_active_battle(text) to anon, authenticated;


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
select
  v.id,
  seed.product_key,
  seed.item_name,
  seed.description,
  seed.item_type::public.item_type,
  seed.rarity::public.item_rarity,
  seed.price_coin,
  seed.stock_quantity,
  seed.display_order
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
grant execute on function public.currency_coin_value(text) to anon, authenticated;
grant execute on function public.wallet_total_coin(uuid) to anon, authenticated;
grant execute on function public.set_wallet_from_coin_value(uuid, int) to anon, authenticated;
grant execute on function public.get_discovered_cities(text) to anon, authenticated;
grant execute on function public.purchase_market_product(text, uuid, uuid, int) to anon, authenticated;
grant execute on function public.update_city_access(text, text, jsonb) to anon, authenticated;
grant execute on function public.update_market_product(text, uuid, jsonb) to anon, authenticated;


-- ============================================================
-- ============================================================

-- Shop vendor controls for Discovered Cities.

alter table public.shop_vendors
add column if not exists npc_name text not null default 'Shopkeeper';

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

insert into public.spell_catalog (spell_key, name, school, mana_cost, summary, details, rarity, display_order)
values
  ('spark', 'Spark', 'arcane', 5, 'A small controlled flame or arc of heat.', 'Useful for lighting, signaling, or small combat tricks.', 'Common', 10),
  ('mend-flesh', 'Mend Flesh', 'restoration', 12, 'Restore a modest amount of health to one target.', 'A staple restorative spell for keeping allies upright.', 'Common', 20),
  ('arcane-bolt', 'Arcane Bolt', 'arcane', 15, 'A direct bolt of force against a target.', 'Reliable magical damage with little flourish.', 'Uncommon', 30),
  ('warding-shell', 'Warding Shell', 'rune', 18, 'Briefly reinforce a target against harm.', 'A rune-like defensive veil that can turn a hit from terrible to survivable.', 'Uncommon', 40),
  ('verdant-snare', 'Verdant Snare', 'nature', 16, 'Roots or vines hinder a creature.', 'Best used to slow movement, set up allies, or control a narrow path.', 'Uncommon', 50),
  ('shadow-step', 'Shadow Step', 'shadow', 22, 'Slip through dim space to reposition.', 'A short evasive movement spell favored by skirmishers.', 'Rare', 60),
  ('greater-mend', 'Greater Mend', 'restoration', 30, 'Restore a large amount of health to one target.', 'A stronger recovery spell for rough encounters.', 'Rare', 70),
  ('alchemy-flare', 'Alchemy Flare', 'alchemy', 20, 'Ignite volatile reagents into a burst.', 'A flexible spell for alchemists and potion-heavy casters.', 'Rare', 80)
on conflict (spell_key) do update
set name = excluded.name,
    school = excluded.school,
    mana_cost = excluded.mana_cost,
    summary = excluded.summary,
    details = excluded.details,
    rarity = excluded.rarity,
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
select
  v.id,
  'spell-scroll-' || s.spell_key,
  s.name || ' Spell',
  s.summary,
  'quest'::public.item_type,
  s.rarity,
  greatest(50, s.mana_cost * 12),
  3,
  100 + s.display_order
from public.shop_vendors v
join public.spell_catalog s on true
where v.vendor_key = 'calostrynn-library'
on conflict (product_key) do update
set item_name = excluded.item_name,
    description = excluded.description,
    item_type = excluded.item_type,
    rarity = excluded.rarity,
    price_coin = excluded.price_coin,
    display_order = excluded.display_order;

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
    'manaCost', p_spell.mana_cost,
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

  if exists (
    select 1
    from public.character_spells cs
    where cs.character_id = v_entry.character_id
      and cs.is_active
      and cs.slot_index = v_slot
      and cs.id <> v_entry.id
  ) then
    raise exception 'That spell slot is already occupied.';
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

grant execute on function public.spell_record_to_json(public.spell_catalog) to anon, authenticated;
grant execute on function public.character_spell_record_to_json(public.character_spells) to anon, authenticated;
grant execute on function public.character_has_active_battle(uuid) to anon, authenticated;
grant execute on function public.find_first_free_spell_slot(uuid, int) to anon, authenticated;
grant execute on function public.get_character_spells(text, uuid) to anon, authenticated;
grant execute on function public.grant_character_spell(text, uuid, uuid) to anon, authenticated;
grant execute on function public.update_character_spell_state(text, uuid, jsonb) to anon, authenticated;
grant execute on function public.use_character_spell(text, uuid) to anon, authenticated;


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
  item_type public.item_type not null default 'misc',
  rarity public.item_rarity not null default 'Common',
  generator_biomes text[] not null default array['Any']::text[],
  difficulty_min int not null default 1 check (difficulty_min >= 1),
  difficulty_max int not null default 5 check (difficulty_max >= difficulty_min),
  loot_weight numeric not null default 1 check (loot_weight >= 0),
  tower_base_only boolean not null default false,
  min_quantity int not null default 1 check (min_quantity >= 1),
  max_quantity int not null default 1 check (max_quantity >= min_quantity),
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



create or replace function public.loot_item_record_to_json(p_item public.loot_items)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'id', p_item.id,
    'poolId', p_item.pool_id,
    'name', p_item.item_name,
    'category', p_item.item_type::text,
    'biomes', to_jsonb(p_item.generator_biomes),
    'minDifficulty', p_item.difficulty_min,
    'maxDifficulty', p_item.difficulty_max,
    'type', p_item.item_type,
    'rarity', p_item.rarity,
    'minQuantity', p_item.min_quantity,
    'maxQuantity', p_item.max_quantity,
    'weight', p_item.loot_weight,
    'towerBaseOnly', p_item.tower_base_only,
    'notes', p_item.notes
  )
$$;


grant execute on function public.loot_pool_record_to_json(public.loot_pools) to anon, authenticated;
grant execute on function public.loot_item_record_to_json(public.loot_items) to anon, authenticated;


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
  message text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists trade_offers_sender_idx on public.trade_offers(sender_user_id, status, created_at desc);
create index if not exists trade_offers_recipient_idx on public.trade_offers(recipient_user_id, status, created_at desc);

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

create or replace function public.create_trade_offer(
  p_session_token text,
  p_sender_character_id uuid,
  p_target_character_id uuid,
  p_offer_note text default '',
  p_request_note text default '',
  p_message text default ''
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
  v_trade public.trade_offers%rowtype;
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
  if v_target.owner_user_id = v_sender.owner_user_id then raise exception 'That trade is already within the same player account.'; end if;

  insert into public.trade_offers (
    sender_user_id,
    recipient_user_id,
    sender_character_id,
    target_character_id,
    offer_note,
    request_note,
    message
  )
  values (
    coalesce(v_sender.owner_user_id, v_profile.id),
    v_target.owner_user_id,
    v_sender.id,
    v_target.id,
    coalesce(p_offer_note, ''),
    coalesce(p_request_note, ''),
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
    trim(both from concat_ws(E'\n\n', nullif(coalesce(p_message, ''), ''), 'Offers: ' || nullif(coalesce(p_offer_note, ''), ''), 'Requests: ' || nullif(coalesce(p_request_note, ''), ''))),
    'trade',
    'trade',
    v_trade.id,
    v_target.location_name
  );

  return public.trade_offer_record_to_json(v_trade);
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
grant execute on function public.create_trade_offer(text, uuid, uuid, text, text, text) to anon, authenticated;
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
    mana_cost = case when v_patch ? 'manaCost' then greatest(0, (v_patch->>'manaCost')::int) else mana_cost end,
    summary = case when v_patch ? 'summary' then coalesce(v_patch->>'summary', '') else summary end,
    details = case when v_patch ? 'details' then coalesce(v_patch->>'details', '') else details end,
    rarity = case when v_patch ? 'rarity' then (v_patch->>'rarity')::public.item_rarity else rarity end,
    is_available = case when v_patch ? 'available' then (v_patch->>'available')::boolean else is_available end
  where id = p_spell_id;

  if not found then raise exception 'Spell was not found.'; end if;

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
  v_min int;
  v_max int;
begin
  v_profile := public.require_dm_profile(p_session_token);

  select
    case when v_patch ? 'minQuantity' then greatest(1, (v_patch->>'minQuantity')::int) else min_quantity end,
    case when v_patch ? 'maxQuantity' then greatest(1, (v_patch->>'maxQuantity')::int) else max_quantity end
  into v_min, v_max
  from public.loot_items
  where id = p_loot_item_id;

  if v_min is null then raise exception 'Loot item was not found.'; end if;
  if v_max < v_min then v_max := v_min; end if;

  update public.loot_items
  set
    item_name = case when v_patch ? 'name' then coalesce(nullif(trim(v_patch->>'name'), ''), item_name) else item_name end,
    item_type = case when v_patch ? 'type' then (v_patch->>'type')::public.item_type else item_type end,
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
grant execute on function public.update_spell_asset(text, uuid, jsonb) to anon, authenticated;
grant execute on function public.update_loot_item_asset(text, uuid, jsonb) to anon, authenticated;


-- Workbook-backed loot generator.

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
    'settings', coalesce(v_settings, jsonb_build_object(
      'biomes', jsonb_build_array('Any', 'Caves', 'Goblins', 'Elven', 'Volcano', 'Mountains', 'Snow', 'Voidlands'),
      'difficulties', jsonb_build_array(1, 2, 3, 4, 5),
      'poolSizes', jsonb_build_array('Night Encounter', 'Small Cave', 'Medium Cave', 'Large Cave', 'Dragon Lair', 'Tower Floor', 'Base'),
      'roomTypes', jsonb_build_array('Normal', 'Secret Room', 'Tower Boss Room'),
      'baseRollsByPoolSize', jsonb_build_object('Night Encounter', 5, 'Small Cave', 10, 'Medium Cave', 15, 'Large Cave', 20, 'Dragon Lair', 50, 'Tower Floor', 25, 'Base', 50),
      'poolMultipliers', jsonb_build_object('Large Cave', 1.33, 'Dragon Lair', 5, 'Tower Floor', 2, 'Base', 2),
      'roomMultipliers', jsonb_build_object('Secret Room', 2, 'Tower Boss Room', 2),
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
  v_min_quantity int;
  v_max_quantity int;
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

    v_type_text := lower(coalesce(nullif(v_row->>'type', ''), nullif(v_row->>'item_type', ''), 'misc'));
    if v_type_text not in ('weapon', 'armor', 'shield', 'pet', 'accessory', 'storage', 'ore', 'potion', 'food', 'plant', 'fabric', 'tool', 'quest', 'currency', 'misc') then
      v_type_text := 'misc';
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

    v_min_quantity := greatest(1, coalesce(nullif(v_row->>'minQuantity', '')::int, nullif(v_row->>'min_quantity', '')::int, nullif(v_row->>'min', '')::int, 1));
    v_max_quantity := greatest(v_min_quantity, coalesce(nullif(v_row->>'maxQuantity', '')::int, nullif(v_row->>'max_quantity', '')::int, nullif(v_row->>'max', '')::int, v_min_quantity));

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
      min_quantity,
      max_quantity,
      notes,
      is_active
    )
    values (
      v_pool.id,
      v_name,
      v_type_text::public.item_type,
      v_rarity_text::public.item_rarity,
      v_biomes,
      greatest(1, coalesce(nullif(v_row->>'minDifficulty', '')::int, nullif(v_row->>'min_difficulty', '')::int, 1)),
      greatest(greatest(1, coalesce(nullif(v_row->>'minDifficulty', '')::int, nullif(v_row->>'min_difficulty', '')::int, 1)), coalesce(nullif(v_row->>'maxDifficulty', '')::int, nullif(v_row->>'max_difficulty', '')::int, 5)),
      greatest(0, coalesce(nullif(v_row->>'weight', '')::numeric, nullif(v_row->>'lootWeight', '')::numeric, nullif(v_row->>'loot_weight', '')::numeric, 1)),
      coalesce((v_row->>'towerBaseOnly')::boolean, false),
      v_min_quantity,
      v_max_quantity,
      coalesce(v_row->>'notes', ''),
      true
    );
  end loop;

  return public.get_exploration_state(p_session_token);
end;
$$;


-- One-time clean seed from the attached Loot Drops.xlsm workbook.
create table if not exists public.app_migrations (
  id text primary key,
  applied_at timestamptz not null default now()
);

revoke all on public.app_migrations from anon, authenticated;

do $$
begin
  if not exists (select 1 from public.app_migrations where id = 'seed_loot_drops_xlsm_20260721') then
    delete from public.loot_items where true;
    delete from public.loot_pools where true;

    insert into public.loot_workbook_settings (id, settings, source, imported_at)
    values ('default', '{"biomes":["Any","Caves","Goblins","Elven","Volcano","Mountains","Snow","Voidlands"],"difficulties":[1,2,3,4,5],"poolSizes":["Night Encounter","Small Cave","Medium Cave","Large Cave","Dragon Lair","Tower Floor","Base"],"roomTypes":["Normal","Secret Room","Tower Boss Room"],"baseRollsByPoolSize":{"Night Encounter":5,"Small Cave":10,"Medium Cave":15,"Large Cave":20,"Dragon Lair":50,"Tower Floor":25,"Base":50},"poolMultipliers":{"Large Cave":1.33,"Dragon Lair":5,"Tower Floor":2,"Base":2},"roomMultipliers":{"Secret Room":2,"Tower Boss Room":2},"rareBoostRarities":["Rare","Epic","Legendary","Mythical"],"sourceFormulas":{"lootRolls":"SWITCH($B$4,\"Secret Room\",MAX(1,ROUNDUP(SWITCH($B$3,\"Night Encounter\",5,\"Small Cave\",10,\"Medium Cave\",15,\"Large Cave\",20,\"Dragon Lair\",50,\"Tower Floor\",25,\"Base\",50)/2,0)),\"Tower Boss Room\",SWITCH($B$3,\"Night Encounter\",5,\"Small Cave\",10,\"Medium Cave\",15,\"Large Cave\",20,\"Dragon Lair\",50,\"Tower Floor\",25,\"Base\",50)*2,SWITCH($B$3,\"Night Encounter\",5,\"Small Cave\",10,\"Medium Cave\",15,\"Large Cave\",20,\"Dragon Lair\",50,\"Tower Floor\",25,\"Base\",50))","multiplier":"SWITCH($B$3,\"Large Cave\",1.33,\"Dragon Lair\",5,\"Tower Floor\",2,\"Base\",2,1)*SWITCH($B$4,\"Secret Room\",2,\"Tower Boss Room\",2,1)","eligibility":"IF(AND(A2<>\"\",OR(Generator!$B$1=\"Any\",ISNUMBER(SEARCH(\",Any,\",\",\"&SUBSTITUTE(C2,\" \",\"\")&\",\")),ISNUMBER(SEARCH(\",\"&SUBSTITUTE(Generator!$B$1,\" \",\"\")&\",\",\",\"&SUBSTITUTE(C2,\" \",\"\")&\",\"))),VALUE(D2)<=VALUE(Generator!$B$2),VALUE(E2)>=VALUE(Generator!$B$2),OR(''Loot Table''!$J2<>TRUE,Generator!$B$3=\"Tower Floor\",Generator!$B$3=\"Base\")),1,0)","adjustedWeight":"IF(J2=1,G2*IF(ISNUMBER(MATCH(F2,{\"Rare\",\"Epic\",\"Legendary\",\"Mythical\"},0)),Generator!$D$2,1),0)"}}'::jsonb, '{"seededFrom":"Loot Drops.xlsm","sheets":["Loot Table","Generator","Roll Helper","Settings"],"importedRows":146}'::jsonb, now())
    on conflict (id) do update
    set settings = excluded.settings,
        source = excluded.source,
        imported_at = excluded.imported_at;

    insert into public.loot_pools (pool_key, name, description, display_order)
    values
    ('catalog-tool', 'Tool Catalog', 'Imported from Loot Drops.xlsm.', 1),
    ('catalog-storage', 'Storage Catalog', 'Imported from Loot Drops.xlsm.', 2),
    ('catalog-fabric', 'Fabric Catalog', 'Imported from Loot Drops.xlsm.', 3),
    ('catalog-accessory', 'Accessory Catalog', 'Imported from Loot Drops.xlsm.', 4),
    ('catalog-weapon', 'Weapon Catalog', 'Imported from Loot Drops.xlsm.', 5),
    ('catalog-currency', 'Currency Catalog', 'Imported from Loot Drops.xlsm.', 6),
    ('catalog-food', 'Food Catalog', 'Imported from Loot Drops.xlsm.', 7),
    ('catalog-misc', 'Misc Catalog', 'Imported from Loot Drops.xlsm.', 8),
    ('catalog-potion', 'Potion Catalog', 'Imported from Loot Drops.xlsm.', 9),
    ('catalog-pet', 'Pet Catalog', 'Imported from Loot Drops.xlsm.', 10),
    ('catalog-ore', 'Ore Catalog', 'Imported from Loot Drops.xlsm.', 11),
    ('catalog-shield', 'Shield Catalog', 'Imported from Loot Drops.xlsm.', 12),
    ('catalog-quest', 'Quest Catalog', 'Imported from Loot Drops.xlsm.', 13)
    on conflict (pool_key) do update
    set name = excluded.name,
        description = excluded.description,
        display_order = excluded.display_order;

    insert into public.loot_items (pool_id, item_name, item_type, rarity, generator_biomes, difficulty_min, difficulty_max, loot_weight, tower_base_only, min_quantity, max_quantity, notes, is_active)
    values
    ((select id from public.loot_pools where pool_key = 'catalog-tool'), 'Torch', 'tool'::public.item_type, 'Common'::public.item_rarity, array['Any']::text[], 1, 3, 100, false, 1, 3, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-tool'), 'Rope', 'tool'::public.item_type, 'Common'::public.item_rarity, array['Any']::text[], 1, 3, 90, false, 1, 5, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-storage'), 'Waist Pouch', 'storage'::public.item_type, 'Common'::public.item_rarity, array['Any']::text[], 1, 2, 70, false, 1, 3, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-storage'), 'Back Bag', 'storage'::public.item_type, 'Common'::public.item_rarity, array['Any']::text[], 1, 3, 60, false, 1, 2, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-fabric'), 'Leather', 'fabric'::public.item_type, 'Common'::public.item_rarity, array['Any', 'Goblins']::text[], 1, 5, 100, false, 1, 10, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-accessory'), 'Jewlery', 'accessory'::public.item_type, 'Common'::public.item_rarity, array['Any', 'Goblins']::text[], 1, 5, 80, false, 1, 3, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-weapon'), 'Loose Arrows', 'weapon'::public.item_type, 'Common'::public.item_rarity, array['Any']::text[], 1, 5, 80, false, 3, 25, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-fabric'), 'Cloth', 'fabric'::public.item_type, 'Common'::public.item_rarity, array['Any']::text[], 1, 2, 80, false, 1, 3, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-fabric'), 'Fine Cloth', 'fabric'::public.item_type, 'Common'::public.item_rarity, array['Any']::text[], 3, 5, 75, false, 1, 5, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-weapon'), 'Magic Bow', 'weapon'::public.item_type, 'Epic'::public.item_rarity, array['Any']::text[], 3, 5, 25, false, 1, 2, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-currency'), 'Coin', 'currency'::public.item_type, 'Common'::public.item_rarity, array['Any']::text[], 1, 2, 80, false, 1, 50, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-tool'), 'Fishing Rod', 'tool'::public.item_type, 'Common'::public.item_rarity, array['Caves']::text[], 1, 5, 60, false, 1, 1, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-tool'), 'Hunting Trap', 'tool'::public.item_type, 'Common'::public.item_rarity, array['Caves']::text[], 1, 5, 60, false, 1, 2, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-food'), 'Dried Rations', 'food'::public.item_type, 'Common'::public.item_rarity, array['Caves']::text[], 1, 5, 60, false, 1, 3, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-fabric'), 'Tattered Cloak', 'fabric'::public.item_type, 'Common'::public.item_rarity, array['Any']::text[], 1, 5, 60, false, 1, 1, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-misc'), 'Leather Belt', 'misc'::public.item_type, 'Common'::public.item_rarity, array['Caves']::text[], 1, 5, 60, false, 1, 2, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-potion'), 'Glass Flasks', 'potion'::public.item_type, 'Common'::public.item_rarity, array['Any']::text[], 1, 5, 60, false, 1, 5, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-tool'), 'Small Net', 'tool'::public.item_type, 'Common'::public.item_rarity, array['Caves']::text[], 1, 3, 60, false, 1, 3, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-misc'), 'Looks like a good walking stick', 'misc'::public.item_type, 'Common'::public.item_rarity, array['Caves']::text[], 1, 3, 60, false, 1, 200, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-currency'), 'Callis', 'currency'::public.item_type, 'Uncommon'::public.item_rarity, array['Any']::text[], 2, 4, 60, false, 1, 50, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-weapon'), 'Longbow', 'weapon'::public.item_type, 'Uncommon'::public.item_rarity, array['Any']::text[], 1, 3, 50, false, 1, 3, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-fabric'), 'Fur Skin', 'fabric'::public.item_type, 'Uncommon'::public.item_rarity, array['Any', 'Goblins']::text[], 1, 5, 60, false, 1, 5, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-storage'), 'Light Duffle', 'storage'::public.item_type, 'Uncommon'::public.item_rarity, array['Any']::text[], 2, 4, 50, false, 1, 2, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-tool'), 'Steel Shovel', 'tool'::public.item_type, 'Uncommon'::public.item_rarity, array['Any']::text[], 1, 3, 50, false, 1, 2, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-tool'), 'Steel Pickaxe', 'tool'::public.item_type, 'Uncommon'::public.item_rarity, array['Any']::text[], 1, 3, 50, false, 1, 2, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-weapon'), 'Steel Sword', 'weapon'::public.item_type, 'Uncommon'::public.item_rarity, array['Any']::text[], 1, 3, 50, false, 1, 2, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-tool'), 'Steel Axe', 'tool'::public.item_type, 'Uncommon'::public.item_rarity, array['Any']::text[], 1, 3, 50, false, 1, 2, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-tool'), 'Spyglass', 'tool'::public.item_type, 'Uncommon'::public.item_rarity, array['Caves']::text[], 1, 5, 50, false, 1, 1, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-tool'), 'Smoke Bomb', 'tool'::public.item_type, 'Uncommon'::public.item_rarity, array['Caves']::text[], 1, 5, 50, false, 1, 1, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-accessory'), 'Steel ring', 'accessory'::public.item_type, 'Uncommon'::public.item_rarity, array['Caves']::text[], 1, 5, 50, false, 1, 1, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-tool'), 'Large Net', 'tool'::public.item_type, 'Uncommon'::public.item_rarity, array['Caves']::text[], 1, 5, 50, false, 1, 2, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-misc'), 'An actual walking stick', 'misc'::public.item_type, 'Uncommon'::public.item_rarity, array['Caves']::text[], 1, 5, 50, false, 1, 2, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-weapon'), 'Steel Battleaxe', 'weapon'::public.item_type, 'Uncommon'::public.item_rarity, array['Any']::text[], 1, 3, 55, false, 1, 1, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-weapon'), 'Steel Mace', 'weapon'::public.item_type, 'Uncommon'::public.item_rarity, array['Any']::text[], 1, 3, 55, false, 1, 1, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-potion'), 'Arcane Nector', 'potion'::public.item_type, 'Uncommon'::public.item_rarity, array['Any']::text[], 1, 5, 50, false, 1, 10, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-potion'), 'Lesser Healing Potion', 'potion'::public.item_type, 'Uncommon'::public.item_rarity, array['Any']::text[], 1, 3, 45, false, 1, 5, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-potion'), 'Lesser Swiftness Potion', 'potion'::public.item_type, 'Uncommon'::public.item_rarity, array['Any']::text[], 1, 3, 36, false, 1, 5, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-potion'), 'Lesser Agility Potion', 'potion'::public.item_type, 'Uncommon'::public.item_rarity, array['Any']::text[], 1, 3, 36, false, 1, 5, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-potion'), 'Lesser Strength Potion', 'potion'::public.item_type, 'Uncommon'::public.item_rarity, array['Any']::text[], 1, 3, 36, false, 1, 5, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-potion'), 'Lesser Sorcery Potion', 'potion'::public.item_type, 'Uncommon'::public.item_rarity, array['Any']::text[], 1, 3, 36, false, 1, 5, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-potion'), 'Lesser Mana Potion', 'potion'::public.item_type, 'Uncommon'::public.item_rarity, array['Any']::text[], 1, 3, 36, false, 1, 5, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-potion'), 'Lesser Antidote Potion', 'potion'::public.item_type, 'Uncommon'::public.item_rarity, array['Any']::text[], 1, 3, 36, false, 1, 5, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-potion'), 'Lesser Warming Potion', 'potion'::public.item_type, 'Uncommon'::public.item_rarity, array['Any']::text[], 1, 3, 36, false, 1, 5, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-potion'), 'Lesser Cooling Potion', 'potion'::public.item_type, 'Uncommon'::public.item_rarity, array['Any']::text[], 1, 3, 36, false, 1, 5, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-potion'), 'Lesser Night-Eye Potion', 'potion'::public.item_type, 'Uncommon'::public.item_rarity, array['Any']::text[], 1, 3, 36, false, 1, 5, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-potion'), 'Lesser Thickskin Potion', 'potion'::public.item_type, 'Uncommon'::public.item_rarity, array['Any']::text[], 1, 3, 36, false, 1, 5, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-potion'), 'Lesser Clear-Mind Potion', 'potion'::public.item_type, 'Uncommon'::public.item_rarity, array['Any']::text[], 1, 3, 36, false, 1, 5, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-potion'), 'Lesser Wake-Up Potion', 'potion'::public.item_type, 'Uncommon'::public.item_rarity, array['Any']::text[], 1, 3, 30, false, 1, 5, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-potion'), 'Lesser Clotting Potion', 'potion'::public.item_type, 'Uncommon'::public.item_rarity, array['Any']::text[], 1, 3, 36, false, 1, 5, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-currency'), 'Callor', 'currency'::public.item_type, 'Rare'::public.item_rarity, array['Any']::text[], 3, 5, 35, false, 1, 50, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-pet'), 'Horse', 'pet'::public.item_type, 'Rare'::public.item_rarity, array['Any']::text[], 1, 3, 35, true, 1, 5, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-pet'), 'War Horse', 'pet'::public.item_type, 'Rare'::public.item_rarity, array['Any']::text[], 3, 5, 35, true, 1, 5, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-ore'), 'Quartz', 'ore'::public.item_type, 'Rare'::public.item_rarity, array['Any', 'Goblins']::text[], 1, 5, 40, false, 1, 5, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-storage'), 'Heavy Duffle', 'storage'::public.item_type, 'Rare'::public.item_rarity, array['Any']::text[], 2, 5, 35, false, 1, 2, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-shield'), 'Steel Shield', 'shield'::public.item_type, 'Rare'::public.item_rarity, array['Any']::text[], 3, 5, 30, false, 1, 2, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-tool'), 'Mythril Pickaxe', 'tool'::public.item_type, 'Rare'::public.item_rarity, array['Any']::text[], 2, 4, 35, false, 1, 2, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-weapon'), 'Mythril Sword', 'weapon'::public.item_type, 'Rare'::public.item_rarity, array['Any']::text[], 2, 4, 35, false, 1, 2, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-weapon'), 'Mythril Dagger', 'weapon'::public.item_type, 'Rare'::public.item_rarity, array['Any']::text[], 2, 4, 35, false, 1, 2, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-tool'), 'Mythril Axe', 'tool'::public.item_type, 'Rare'::public.item_rarity, array['Any']::text[], 2, 4, 35, false, 1, 2, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-weapon'), 'Mythril Battleaxe', 'weapon'::public.item_type, 'Rare'::public.item_rarity, array['Any']::text[], 2, 4, 30, false, 1, 1, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-weapon'), 'Mythril Mace', 'weapon'::public.item_type, 'Rare'::public.item_rarity, array['Any']::text[], 2, 4, 30, false, 1, 1, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-potion'), 'Greater Wake-Up Potion', 'potion'::public.item_type, 'Rare'::public.item_rarity, array['Any']::text[], 1, 5, 18, false, 1, 4, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-potion'), 'Greater Clotting Potion', 'potion'::public.item_type, 'Rare'::public.item_rarity, array['Any']::text[], 1, 5, 22, false, 1, 4, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-potion'), 'Greater Clear-Mind Potion', 'potion'::public.item_type, 'Rare'::public.item_rarity, array['Any']::text[], 1, 5, 22, false, 1, 4, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-potion'), 'Greater Thickskin Potion', 'potion'::public.item_type, 'Rare'::public.item_rarity, array['Any']::text[], 1, 5, 22, false, 1, 4, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-potion'), 'Greater Night-Eye Potion', 'potion'::public.item_type, 'Rare'::public.item_rarity, array['Any']::text[], 1, 5, 22, false, 1, 4, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-potion'), 'Greater Cooling Potion', 'potion'::public.item_type, 'Rare'::public.item_rarity, array['Any']::text[], 1, 5, 22, false, 1, 4, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-potion'), 'Greater Warming Potion', 'potion'::public.item_type, 'Rare'::public.item_rarity, array['Any']::text[], 1, 5, 22, false, 1, 4, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-potion'), 'Greater Antidote Potion', 'potion'::public.item_type, 'Rare'::public.item_rarity, array['Any']::text[], 1, 5, 22, false, 1, 4, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-potion'), 'Greater Mana Potion', 'potion'::public.item_type, 'Rare'::public.item_rarity, array['Any']::text[], 1, 5, 22, false, 1, 4, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-potion'), 'Greater Sorcery Potion', 'potion'::public.item_type, 'Rare'::public.item_rarity, array['Any']::text[], 1, 5, 22, false, 1, 4, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-potion'), 'Greater Strength Potion', 'potion'::public.item_type, 'Rare'::public.item_rarity, array['Any']::text[], 1, 5, 22, false, 1, 4, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-potion'), 'Greater Agility Potion', 'potion'::public.item_type, 'Rare'::public.item_rarity, array['Any']::text[], 1, 5, 22, false, 1, 4, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-potion'), 'Greater Swiftness Potion', 'potion'::public.item_type, 'Rare'::public.item_rarity, array['Any']::text[], 1, 5, 22, false, 1, 4, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-potion'), 'Greater Healing Potion', 'potion'::public.item_type, 'Rare'::public.item_rarity, array['Any']::text[], 1, 5, 28, false, 1, 4, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-weapon'), 'Vaylium Battleaxe', 'weapon'::public.item_type, 'Epic'::public.item_rarity, array['Any']::text[], 3, 5, 15, false, 1, 1, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-weapon'), 'Vaylium Mace', 'weapon'::public.item_type, 'Epic'::public.item_rarity, array['Any']::text[], 3, 5, 15, false, 1, 1, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-tool'), 'Vaylium Pickaxe', 'tool'::public.item_type, 'Epic'::public.item_rarity, array['Any']::text[], 3, 5, 20, false, 1, 2, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-weapon'), 'Vaylium Sword', 'weapon'::public.item_type, 'Epic'::public.item_rarity, array['Any']::text[], 3, 5, 20, false, 1, 2, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-weapon'), 'Vaylium Dagger', 'weapon'::public.item_type, 'Epic'::public.item_rarity, array['Any']::text[], 3, 5, 20, false, 1, 2, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-tool'), 'Vaylium Axe', 'tool'::public.item_type, 'Epic'::public.item_rarity, array['Any']::text[], 3, 5, 20, false, 1, 2, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-quest'), 'Fire Scroll', 'quest'::public.item_type, 'Epic'::public.item_rarity, array['Any']::text[], 3, 5, 20, true, 1, 2, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-quest'), 'Frost Scroll', 'quest'::public.item_type, 'Epic'::public.item_rarity, array['Any']::text[], 3, 5, 20, true, 1, 2, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-quest'), 'Lightning Scroll', 'quest'::public.item_type, 'Epic'::public.item_rarity, array['Any']::text[], 3, 5, 20, true, 1, 2, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-quest'), 'Earth Scroll', 'quest'::public.item_type, 'Epic'::public.item_rarity, array['Any']::text[], 3, 5, 20, true, 1, 2, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-quest'), 'Wind Scroll', 'quest'::public.item_type, 'Epic'::public.item_rarity, array['Any']::text[], 3, 5, 20, true, 1, 2, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-quest'), 'Energy Scroll', 'quest'::public.item_type, 'Epic'::public.item_rarity, array['Any']::text[], 3, 5, 20, true, 1, 2, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-quest'), 'Healing Scroll', 'quest'::public.item_type, 'Epic'::public.item_rarity, array['Any']::text[], 3, 5, 20, true, 1, 2, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-quest'), 'Enhancment Scroll', 'quest'::public.item_type, 'Epic'::public.item_rarity, array['Any']::text[], 3, 5, 20, true, 1, 2, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-quest'), 'Utility Scroll', 'quest'::public.item_type, 'Epic'::public.item_rarity, array['Any']::text[], 3, 5, 25, true, 1, 1, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-quest'), 'Mystery Tome', 'quest'::public.item_type, 'Epic'::public.item_rarity, array['Any']::text[], 1, 5, 20, true, 1, 1, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-quest'), 'World Map Fragment', 'quest'::public.item_type, 'Epic'::public.item_rarity, array['Any']::text[], 1, 5, 20, true, 1, 1, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-quest'), 'World History', 'quest'::public.item_type, 'Epic'::public.item_rarity, array['Any']::text[], 1, 5, 20, true, 1, 1, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-ore'), 'Emerald', 'ore'::public.item_type, 'Epic'::public.item_rarity, array['Goblins', 'Caves']::text[], 2, 5, 30, false, 1, 4, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-ore'), 'Ruby', 'ore'::public.item_type, 'Epic'::public.item_rarity, array['Goblins', 'Caves']::text[], 3, 5, 20, false, 1, 3, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-ore'), 'Ember Rune', 'ore'::public.item_type, 'Epic'::public.item_rarity, array['Any']::text[], 1, 5, 15, false, 1, 3, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-ore'), 'Frost Rune', 'ore'::public.item_type, 'Epic'::public.item_rarity, array['Any']::text[], 1, 5, 15, false, 1, 3, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-ore'), 'Lightning Rune', 'ore'::public.item_type, 'Epic'::public.item_rarity, array['Any']::text[], 1, 5, 15, false, 1, 3, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-ore'), 'Earth Rune', 'ore'::public.item_type, 'Epic'::public.item_rarity, array['Any']::text[], 1, 5, 15, false, 1, 3, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-ore'), 'Wind Rune', 'ore'::public.item_type, 'Epic'::public.item_rarity, array['Any']::text[], 1, 5, 15, false, 1, 3, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-ore'), 'Mountian Rune', 'ore'::public.item_type, 'Epic'::public.item_rarity, array['Any']::text[], 1, 5, 11, false, 1, 3, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-weapon'), 'Dragonscale Sword', 'weapon'::public.item_type, 'Legendary'::public.item_rarity, array['Any']::text[], 4, 5, 5, false, 1, 2, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-weapon'), 'Dragonscale Dagger', 'weapon'::public.item_type, 'Legendary'::public.item_rarity, array['Any']::text[], 4, 5, 5, false, 1, 2, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-tool'), 'Dragonscale Pickaxe', 'tool'::public.item_type, 'Legendary'::public.item_rarity, array['Any']::text[], 4, 5, 5, false, 1, 2, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-tool'), 'Dragonscale Axe', 'tool'::public.item_type, 'Legendary'::public.item_rarity, array['Any']::text[], 4, 5, 5, false, 1, 2, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-ore'), 'Mythril Ore', 'ore'::public.item_type, 'Legendary'::public.item_rarity, array['Any']::text[], 2, 4, 5, false, 1, 3, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-ore'), 'Vaylium Ore', 'ore'::public.item_type, 'Legendary'::public.item_rarity, array['Any']::text[], 3, 5, 5, false, 1, 3, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-misc'), 'Young Dragons Scales', 'misc'::public.item_type, 'Legendary'::public.item_rarity, array['Any']::text[], 4, 5, 5, false, 1, 3, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-misc'), 'Ember Dragons Scales', 'misc'::public.item_type, 'Legendary'::public.item_rarity, array['Volcano', 'Caves']::text[], 4, 5, 5, false, 1, 3, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-misc'), 'Frost Dragons Scales', 'misc'::public.item_type, 'Legendary'::public.item_rarity, array['Mountains', 'Snow']::text[], 4, 5, 5, false, 1, 3, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-misc'), 'Storm Dragons Scales', 'misc'::public.item_type, 'Legendary'::public.item_rarity, array['Caves']::text[], 4, 5, 5, false, 1, 3, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-misc'), 'Mountian Dragons Scales', 'misc'::public.item_type, 'Legendary'::public.item_rarity, array['Mountains', 'Caves']::text[], 4, 5, 5, false, 1, 3, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-currency'), 'Cal', 'currency'::public.item_type, 'Legendary'::public.item_rarity, array['Any']::text[], 5, 5, 5, false, 1, 50, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-weapon'), 'Dragonscale Bow', 'weapon'::public.item_type, 'Legendary'::public.item_rarity, array['Any']::text[], 4, 5, 5, false, 1, 1, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-quest'), 'Fire Spell Upgrade', 'quest'::public.item_type, 'Legendary'::public.item_rarity, array['Elven']::text[], 3, 5, 9, true, 1, 1, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-quest'), 'Frost Spell Upgrade', 'quest'::public.item_type, 'Legendary'::public.item_rarity, array['Elven']::text[], 3, 5, 9, true, 1, 1, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-quest'), 'Lightning Spell Upgrade', 'quest'::public.item_type, 'Legendary'::public.item_rarity, array['Elven']::text[], 3, 5, 9, true, 1, 1, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-quest'), 'Earth Spell Upgrade', 'quest'::public.item_type, 'Legendary'::public.item_rarity, array['Elven']::text[], 3, 5, 9, true, 1, 1, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-quest'), 'Wind Spell Upgrade', 'quest'::public.item_type, 'Legendary'::public.item_rarity, array['Elven']::text[], 3, 5, 9, true, 1, 1, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-quest'), 'Energy Spell Upgrade', 'quest'::public.item_type, 'Legendary'::public.item_rarity, array['Elven']::text[], 3, 5, 9, true, 1, 1, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-quest'), 'Healing Spell Upgrade', 'quest'::public.item_type, 'Legendary'::public.item_rarity, array['Elven']::text[], 3, 5, 9, true, 1, 1, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-quest'), 'Enhancement Spell Upgrade', 'quest'::public.item_type, 'Legendary'::public.item_rarity, array['Elven']::text[], 3, 5, 9, true, 1, 1, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-quest'), 'Utility Spell Upgrade', 'quest'::public.item_type, 'Legendary'::public.item_rarity, array['Elven']::text[], 3, 5, 9, true, 1, 1, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-ore'), 'Sapphire', 'ore'::public.item_type, 'Legendary'::public.item_rarity, array['Goblins', 'Caves']::text[], 4, 5, 10, false, 1, 2, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-weapon'), 'Legendary Weapon', 'weapon'::public.item_type, 'Legendary'::public.item_rarity, array['Any']::text[], 1, 5, 10, false, 1, 1, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-weapon'), 'Dragonscale Battleaxe', 'weapon'::public.item_type, 'Legendary'::public.item_rarity, array['Any']::text[], 4, 5, 5, false, 1, 2, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-weapon'), 'Dragonscale Mace', 'weapon'::public.item_type, 'Legendary'::public.item_rarity, array['Any']::text[], 4, 5, 5, false, 1, 2, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-potion'), 'Greatest Healing Potion', 'potion'::public.item_type, 'Legendary'::public.item_rarity, array['Any']::text[], 3, 5, 4, false, 1, 3, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-potion'), 'Greatest Swiftness Potion', 'potion'::public.item_type, 'Legendary'::public.item_rarity, array['Any']::text[], 3, 5, 3, false, 1, 3, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-potion'), 'Greatest Agility Potion', 'potion'::public.item_type, 'Legendary'::public.item_rarity, array['Any']::text[], 3, 5, 3, false, 1, 3, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-potion'), 'Greatest Strength Potion', 'potion'::public.item_type, 'Legendary'::public.item_rarity, array['Any']::text[], 3, 5, 3, false, 1, 3, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-potion'), 'Greatest Sorcery Potion', 'potion'::public.item_type, 'Legendary'::public.item_rarity, array['Any']::text[], 3, 5, 3, false, 1, 3, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-potion'), 'Greatest Mana Potion', 'potion'::public.item_type, 'Legendary'::public.item_rarity, array['Any']::text[], 3, 5, 3, false, 1, 3, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-potion'), 'Greatest Antidote Potion', 'potion'::public.item_type, 'Legendary'::public.item_rarity, array['Any']::text[], 3, 5, 3, false, 1, 3, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-potion'), 'Greatest Warming Potion', 'potion'::public.item_type, 'Legendary'::public.item_rarity, array['Any']::text[], 3, 5, 3, false, 1, 3, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-potion'), 'Greatest Cooling Potion', 'potion'::public.item_type, 'Legendary'::public.item_rarity, array['Any']::text[], 3, 5, 3, false, 1, 3, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-potion'), 'Greatest Night-Eye Potion', 'potion'::public.item_type, 'Legendary'::public.item_rarity, array['Any']::text[], 3, 5, 3, false, 1, 3, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-potion'), 'Greatest Thinkskin Potion', 'potion'::public.item_type, 'Legendary'::public.item_rarity, array['Any']::text[], 3, 5, 3, false, 1, 3, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-potion'), 'Greatest Clear-Mind Potion', 'potion'::public.item_type, 'Legendary'::public.item_rarity, array['Any']::text[], 3, 5, 3, false, 1, 3, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-potion'), 'Greatest Wake-Up Potion', 'potion'::public.item_type, 'Legendary'::public.item_rarity, array['Any']::text[], 3, 5, 2, false, 1, 3, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-potion'), 'Greatest Clotting Potion', 'potion'::public.item_type, 'Legendary'::public.item_rarity, array['Any']::text[], 3, 5, 3, false, 1, 3, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-storage'), 'Bag of Holding', 'storage'::public.item_type, 'Mythical'::public.item_rarity, array['Any']::text[], 3, 5, 2, false, 1, 1, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-ore'), 'Void Rune', 'ore'::public.item_type, 'Mythical'::public.item_rarity, array['Any']::text[], 1, 5, 2, false, 1, 5, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-misc'), 'Elder Dragons Scales', 'misc'::public.item_type, 'Mythical'::public.item_rarity, array['Elven']::text[], 5, 5, 2, true, 1, 3, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-misc'), 'Void Dragon Scales', 'misc'::public.item_type, 'Mythical'::public.item_rarity, array['Voidlands']::text[], 5, 5, 2, false, 1, 3, '', true),
    ((select id from public.loot_pools where pool_key = 'catalog-weapon'), 'Father''s Belt', 'weapon'::public.item_type, 'Mythical'::public.item_rarity, array['Any']::text[], 1, 5, 2, false, 1, 1, '', true);

    insert into public.app_migrations (id) values ('seed_loot_drops_xlsm_20260721');
  end if;
end $$;

create or replace function public.catalog_storage_capacity(p_item_name text)
returns int
language sql
stable
as $$
  select case
    when lower(coalesce(p_item_name, '')) like '%bag of holding%' then 500
    when lower(coalesce(p_item_name, '')) like '%heavy duffle%' then 12
    when lower(coalesce(p_item_name, '')) like '%light duffle%' then 6
    when lower(coalesce(p_item_name, '')) like '%back bag%' or lower(coalesce(p_item_name, '')) like '%backpack%' then 4
    when lower(coalesce(p_item_name, '')) like '%waist pouch%' or lower(coalesce(p_item_name, '')) like '%pouch%' then 1
    when lower(coalesce(p_item_name, '')) like '%satchel%' then 3
    else 6
  end
$$;

create or replace function public.award_exploration_loot_item(
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
  if v_profile.role <> 'dm'::public.user_role then raise exception 'Only the Dungeon Master can give generated loot.'; end if;

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
      v_loot.item_name,
      v_loot.item_type,
      v_loot.rarity,
      v_quantity,
      v_loot.item_type = 'storage'::public.item_type,
      case when v_loot.item_type = 'storage'::public.item_type then public.catalog_storage_capacity(v_loot.item_name) else 0 end,
      '{}'::jsonb,
      null
    )
    returning * into v_item;
  end if;

  return public.inventory_item_record_to_json(v_item);
end;
$$;

-- Consolidated final grants
grant execute on function public.get_character_ledger(text) to anon, authenticated;
grant execute on function public.create_campaign_character(text, text, uuid, text, text, text) to anon, authenticated;
grant execute on function public.update_campaign_character(text, uuid, jsonb) to anon, authenticated;
grant execute on function public.get_dashboard_state(text) to anon, authenticated;
grant execute on function public.shop_vendor_record_to_json(public.shop_vendors, boolean) to anon, authenticated;
grant execute on function public.loot_item_record_to_json(public.loot_items) to anon, authenticated;
grant execute on function public.get_exploration_state(text) to anon, authenticated;
grant execute on function public.import_loot_items(text, jsonb) to anon, authenticated;
grant execute on function public.update_shop_vendor(text, uuid, jsonb) to anon, authenticated;
grant execute on function public.catalog_storage_capacity(text) to anon, authenticated;
grant execute on function public.award_exploration_loot_item(text, uuid, uuid, int) to anon, authenticated;
