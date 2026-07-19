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
