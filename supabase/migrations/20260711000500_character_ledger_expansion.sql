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
grant execute on function public.get_character_ledger(text) to anon, authenticated;
grant execute on function public.create_campaign_character(text, text, uuid, text, text, text) to anon, authenticated;
grant execute on function public.update_campaign_character(text, uuid, jsonb) to anon, authenticated;
