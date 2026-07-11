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
