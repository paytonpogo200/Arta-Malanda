-- Bestiary catalog and discovery foundation.

create table if not exists public.bestiary_entities (
  id uuid primary key default gen_random_uuid(),
  entity_key text not null unique,
  name text not null,
  category text not null default 'beast' check (category in ('animal', 'beast', 'being', 'monster', 'spirit')),
  habitat text not null default '',
  temperament text not null default '',
  wild_score int not null default 0 check (wild_score >= 0),
  hp int not null default 0 check (hp >= 0),
  mana int not null default 0 check (mana >= 0),
  summary text not null default '',
  details text not null default '',
  is_unlocked boolean not null default false,
  display_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists bestiary_entities_category_idx on public.bestiary_entities(category);
create index if not exists bestiary_entities_unlocked_idx on public.bestiary_entities(is_unlocked);

alter table public.bestiary_entities enable row level security;
revoke all on public.bestiary_entities from anon, authenticated;

drop trigger if exists bestiary_entities_touch_updated_at on public.bestiary_entities;
create trigger bestiary_entities_touch_updated_at
before update on public.bestiary_entities
for each row execute function public.touch_updated_at();

insert into public.bestiary_entities (
  entity_key,
  name,
  category,
  habitat,
  temperament,
  wild_score,
  hp,
  mana,
  summary,
  details,
  is_unlocked,
  display_order
)
values
  ('field-mouse', 'Field Mouse', 'animal', 'Grasslands and farms', 'Timid', 1, 2, 0, 'A tiny creature mostly useful as an omen of nearby food stores.', 'Common, harmless, and easy to overlook.', true, 10),
  ('calostrynn-stray-dog', 'Calostrynn Stray Dog', 'animal', 'City streets', 'Wary but loyal when fed', 3, 12, 0, 'A hardy street dog familiar with alleys, markets, and people.', 'Often adopted by travelers as an early companion.', true, 20),
  ('bramble-hare', 'Bramble Hare', 'animal', 'Briar patches', 'Skittish', 2, 6, 0, 'Fast, quiet, and difficult to catch once startled.', 'Useful as a tracking lesson for new adventurers.', false, 30),
  ('gutter-imp', 'Gutter Imp', 'being', 'Ruins and sewers', 'Cruel and opportunistic', 7, 22, 10, 'A small malicious being that steals shiny objects and starts trouble.', 'Individually weak, but dangerous in packs or tight places.', false, 40),
  ('ash-wolf', 'Ash Wolf', 'beast', 'Burned woods', 'Territorial', 9, 35, 0, 'A soot-gray wolf with a habit of stalking campfires.', 'Known for circling prey and testing weak watches.', false, 50),
  ('mire-troll', 'Mire Troll', 'monster', 'Swamps', 'Hungry and stubborn', 14, 90, 5, 'A thick-skinned swamp brute that refuses to stay down easily.', 'Avoid muddy ground when fighting one.', false, 60),
  ('lantern-wisp', 'Lantern Wisp', 'spirit', 'Old roads and wetlands', 'Curious and misleading', 8, 18, 40, 'A drifting light that mimics safe lantern glow.', 'Some guide travelers; others lead them into water or graves.', false, 70),
  ('glasswing-moth', 'Glasswing Moth', 'beast', 'Moonlit groves', 'Passive unless threatened', 5, 10, 20, 'A fragile winged creature whose scales shimmer like cut glass.', 'Alchemy-minded travelers prize its shed dust.', false, 80)
on conflict (entity_key) do update
set name = excluded.name,
    category = excluded.category,
    habitat = excluded.habitat,
    temperament = excluded.temperament,
    wild_score = excluded.wild_score,
    hp = excluded.hp,
    mana = excluded.mana,
    summary = excluded.summary,
    details = excluded.details,
    display_order = excluded.display_order;

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

  return jsonb_build_object(
    'entities', (
      select coalesce(jsonb_agg(public.bestiary_entity_record_to_json(e) order by e.category, e.display_order, e.name), '[]'::jsonb)
      from public.bestiary_entities e
      where v_is_dm or e.is_unlocked
    ),
    'unlockedCount', (select count(*) from public.bestiary_entities where is_unlocked),
    'totalCount', (select count(*) from public.bestiary_entities)
  );
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
begin
  select * into v_profile from public.profile_from_campaign_session(p_session_token);
  if v_profile.id is null then raise exception 'Invalid or expired session.'; end if;
  if v_profile.role <> 'dm'::public.user_role then raise exception 'Only the Dungeon Master can update the bestiary.'; end if;

  update public.bestiary_entities
  set
    is_unlocked = case when v_patch ? 'unlocked' then (v_patch->>'unlocked')::boolean else is_unlocked end,
    name = case when v_patch ? 'name' then coalesce(nullif(trim(v_patch->>'name'), ''), name) else name end,
    category = case when v_patch ? 'category' then coalesce(nullif(v_patch->>'category', ''), category) else category end,
    habitat = case when v_patch ? 'habitat' then coalesce(v_patch->>'habitat', '') else habitat end,
    temperament = case when v_patch ? 'temperament' then coalesce(v_patch->>'temperament', '') else temperament end,
    wild_score = case when v_patch ? 'wildScore' then greatest(0, (v_patch->>'wildScore')::int) else wild_score end,
    hp = case when v_patch ? 'hp' then greatest(0, (v_patch->>'hp')::int) else hp end,
    mana = case when v_patch ? 'mana' then greatest(0, (v_patch->>'mana')::int) else mana end,
    summary = case when v_patch ? 'summary' then coalesce(v_patch->>'summary', '') else summary end,
    details = case when v_patch ? 'details' then coalesce(v_patch->>'details', '') else details end
  where id = p_entity_id;

  return public.get_bestiary(p_session_token);
end;
$$;

grant execute on function public.bestiary_entity_record_to_json(public.bestiary_entities) to anon, authenticated;
grant execute on function public.get_bestiary(text) to anon, authenticated;
grant execute on function public.update_bestiary_entity(text, uuid, jsonb) to anon, authenticated;
