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

grant execute on function public.shop_vendor_record_to_json(public.shop_vendors, boolean) to anon, authenticated;
grant execute on function public.update_shop_vendor(text, uuid, jsonb) to anon, authenticated;
