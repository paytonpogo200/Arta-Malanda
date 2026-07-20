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

grant execute on function public.import_bestiary_workbook(text, jsonb, jsonb) to anon, authenticated;
