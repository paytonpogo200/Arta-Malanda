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
    'senderCharacterName', coalesce((select c.character_name from public.characters c where c.id = p_trade.sender_character_id), 'Unknown'),
    'targetCharacterName', coalesce((select c.character_name from public.characters c where c.id = p_trade.target_character_id), 'Unknown'),
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
    v_sender.character_name || ' offered a trade to ' || v_target.character_name,
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
    coalesce((select c.character_name from public.characters c where c.id = v_trade.sender_character_id), 'A character') ||
      ' and ' ||
      coalesce((select c.character_name from public.characters c where c.id = v_trade.target_character_id), 'another character') ||
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
grant execute on function public.get_dashboard_state(text) to anon, authenticated;
grant execute on function public.mark_notification_read(text, uuid) to anon, authenticated;
grant execute on function public.create_campaign_announcement(text, text, text, text, boolean) to anon, authenticated;
grant execute on function public.get_trade_offers(text) to anon, authenticated;
grant execute on function public.create_trade_offer(text, uuid, uuid, text, text, text) to anon, authenticated;
grant execute on function public.update_trade_offer_status(text, uuid, text) to anon, authenticated;
