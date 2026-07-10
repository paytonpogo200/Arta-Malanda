-- Arta Malanda clean core schema v1
-- Intended for a fresh Supabase project. Do not run against the live Ladders and Snakes database.

create extension if not exists "pgcrypto";

create type public.user_role as enum ('player', 'dm');
create type public.character_kind as enum ('player', 'enemy', 'npc', 'tamed_beast');
create type public.item_rarity as enum ('Common', 'Uncommon', 'Rare', 'Epic', 'Legendary', 'Mythical');
create type public.item_type as enum ('weapon', 'armor', 'shield', 'pet', 'accessory', 'storage', 'ore', 'potion', 'food', 'plant', 'fabric', 'tool', 'quest', 'misc');
create type public.battle_status as enum ('active', 'ended');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  role public.user_role not null default 'player',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.dm_lock (
  id boolean primary key default true,
  profile_id uuid not null unique references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint only_one_dm check (id = true)
);

create table public.class_templates (
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

create table public.characters (
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

create table public.inventory_items (
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
  updated_at timestamptz not null default now(),
  constraint inventory_slot_unique unique nulls not distinct (character_id, parent_item_id, slot_index),
  constraint loadout_slot_unique unique nulls not distinct (character_id, loadout_slot)
);

create table public.battles (
  id uuid primary key default gen_random_uuid(),
  created_by uuid not null references public.profiles(id) on delete restrict,
  status public.battle_status not null default 'active',
  grid_width int not null default 24 check (grid_width between 5 and 100),
  grid_height int not null default 24 check (grid_height between 5 and 100),
  created_at timestamptz not null default now(),
  ended_at timestamptz
);

create table public.combatants (
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

create index characters_owner_idx on public.characters(owner_user_id);
create index inventory_character_idx on public.inventory_items(character_id);
create index inventory_parent_idx on public.inventory_items(parent_item_id);
create index combatants_battle_idx on public.combatants(battle_id);

alter table public.profiles enable row level security;
alter table public.dm_lock enable row level security;
alter table public.class_templates enable row level security;
alter table public.characters enable row level security;
alter table public.inventory_items enable row level security;
alter table public.battles enable row level security;
alter table public.combatants enable row level security;

create or replace function public.is_dm()
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'dm'
  );
$$;

create policy profiles_read on public.profiles for select to authenticated using (true);
create policy profiles_self_update on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

create policy class_templates_read on public.class_templates for select to authenticated using (true);
create policy class_templates_dm_all on public.class_templates for all to authenticated using (public.is_dm()) with check (public.is_dm());

create policy characters_read on public.characters for select to authenticated using (true);
create policy characters_dm_all on public.characters for all to authenticated using (public.is_dm()) with check (public.is_dm());

create policy inventory_read on public.inventory_items for select to authenticated using (
  public.is_dm()
  or exists (select 1 from public.characters c where c.id = character_id and c.owner_user_id = auth.uid())
);
create policy inventory_owner_or_dm_all on public.inventory_items for all to authenticated using (
  public.is_dm()
  or exists (select 1 from public.characters c where c.id = character_id and c.owner_user_id = auth.uid())
) with check (
  public.is_dm()
  or exists (select 1 from public.characters c where c.id = character_id and c.owner_user_id = auth.uid())
);

create policy battles_read on public.battles for select to authenticated using (true);
create policy battles_dm_all on public.battles for all to authenticated using (public.is_dm()) with check (public.is_dm());
create policy combatants_read on public.combatants for select to authenticated using (true);
create policy combatants_dm_all on public.combatants for all to authenticated using (public.is_dm()) with check (public.is_dm());
