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
