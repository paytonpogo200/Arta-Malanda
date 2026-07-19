from __future__ import annotations

import csv
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ROWS = ROOT.parent / "old_rows_audit" / "rows"
OUT = ROOT / "supabase" / "data_migrations" / "202607190001_import_old_campaign_unclaimed.sql"

csv.field_size_limit(16 * 1024 * 1024)

RARITIES = {"Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythical"}
ITEM_TYPES = {"weapon", "armor", "shield", "pet", "accessory", "storage", "ore", "potion", "food", "plant", "fabric", "tool", "quest", "misc"}
LOADOUT_SLOTS = {"weapon", "armor", "shield", "active-pet", "accessory-1", "accessory-2", "accessory-3", "accessory-4"}
MAX_CHARACTER_INVENTORY_SLOTS = 120
MAX_STORAGE_INVENTORY_SLOTS = 500


def rows(name: str) -> list[dict[str, str]]:
    path = ROWS / f"{name}_rows.csv"
    if not path.exists():
        return []
    with path.open(newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle))


def q(value: object) -> str:
    if value is None:
        return "null"
    text = str(value)
    if text == "":
        return "null"
    return "'" + text.replace("'", "''") + "'"


def clean_text(value: object, fallback: str = "") -> str:
    text = fallback if value is None or str(value) == "" else str(value)
    if "Â" in text or "â" in text:
        try:
            text = text.encode("latin1").decode("utf-8")
        except UnicodeError:
            pass
    return text


def q_text(value: object, fallback: str = "") -> str:
    text = clean_text(value, fallback)
    return "'" + text.replace("'", "''") + "'"


def q_json(value: object, fallback: object) -> str:
    if value is None or str(value).strip() == "":
        obj = fallback
    elif isinstance(value, str):
        try:
            obj = json.loads(value)
        except json.JSONDecodeError:
            obj = fallback
    else:
        obj = value
    return q_text(json.dumps(obj, ensure_ascii=False, separators=(",", ":"))) + "::jsonb"


def num(value: object, fallback: int = 0) -> int:
    try:
        if value is None or str(value).strip() == "":
            return fallback
        return int(float(str(value)))
    except ValueError:
        return fallback


def boolean(value: object, fallback: bool = False) -> str:
    if value is None or str(value).strip() == "":
        return "true" if fallback else "false"
    return "true" if str(value).strip().lower() in {"true", "t", "1", "yes"} else "false"


def slug(value: str, fallback: str = "legacy") -> str:
    result = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
    return result or fallback


def rarity(value: str) -> str:
    return value if value in RARITIES else "Common"


def item_type(value: str) -> str:
    normalized = (value or "misc").strip().lower()
    return normalized if normalized in ITEM_TYPES else "misc"


def spell_school(category: str) -> str:
    category = (category or "").lower()
    if "defensive" in category:
        return "rune"
    if "earth" in category or "wind" in category:
        return "nature"
    if "enhancement" in category:
        return "arcane"
    if "utility" in category:
        return "arcane"
    return "arcane"


def bestiary_category(category: str) -> str:
    text = (category or "").lower()
    if "wildlife" in text or "animal" in text:
        return "animal"
    if "elf" in text or "human" in text or "being" in text:
        return "being"
    if "spirit" in text or "undead" in text:
        return "spirit"
    if "monster" in text or "goblin" in text or "orc" in text:
        return "monster"
    return "beast"


def values_block(records: list[str]) -> str:
    return ",\n".join(records)


def main() -> None:
    profiles = rows("profiles")
    profile_by_id = {row["id"]: row for row in profiles}
    locations = rows("campaign_locations")
    location_by_id = {row["id"]: row for row in locations}
    class_assets = rows("class_assets")
    class_by_key = {row["class_key"]: row for row in class_assets}
    characters = rows("characters")
    inventory = rows("inventory_items")

    adjusted_slot_by_item: dict[str, int] = {}
    adjusted_inventory_capacity: dict[str, int] = {}
    inventory_by_id = {item["id"]: item for item in inventory}
    container_groups: dict[tuple[str, str], list[dict[str, str]]] = defaultdict(list)

    for item in inventory:
        if item.get("loadout_slot"):
            continue
        character_id = item.get("character_id")
        if not character_id:
            continue
        parent_id = item.get("parent_item_id") or ""
        container_groups[(character_id, parent_id)].append(item)

    for character in characters:
        character_id = character["id"]
        main_items = container_groups.get((character_id, ""), [])
        requested_capacity = num(character.get("inventory_slots"), 12)
        desired_capacity = max(requested_capacity, len(main_items), 0)
        adjusted_inventory_capacity[character_id] = min(MAX_CHARACTER_INVENTORY_SLOTS, max(0, desired_capacity))

    for (character_id, parent_id), group_items in container_groups.items():
        if parent_id:
            parent = inventory_by_id.get(parent_id, {})
            requested_capacity = num(parent.get("storage_capacity"), 0)
            capacity = min(MAX_STORAGE_INVENTORY_SLOTS, max(requested_capacity, len(group_items), 1))
        else:
            capacity = adjusted_inventory_capacity.get(character_id, min(MAX_CHARACTER_INVENTORY_SLOTS, max(len(group_items), 12)))

        occupied: set[int] = set()
        next_slot = 0
        for item in sorted(group_items, key=lambda row: (num(row.get("slot_index"), 999999) if num(row.get("slot_index"), -1) >= 0 else 999999, row.get("created_at", ""), row["id"])):
            original = num(item.get("slot_index"), -1)
            if 0 <= original < capacity and original not in occupied:
                slot = original
            else:
                while next_slot in occupied:
                    next_slot += 1
                if next_slot >= capacity:
                    # The old app allowed broken/hidden slot values. The new app should not.
                    # Keep the item importable by placing true overflow at the last legal slot;
                    # duplicates are rare and will be surfaced by SQL if a container genuinely has
                    # more items than its allowed capacity.
                    slot = max(0, capacity - 1)
                else:
                    slot = next_slot
            occupied.add(slot)
            adjusted_slot_by_item[item["id"]] = slot

    lines: list[str] = []
    lines.append("-- One-time legacy campaign import for Arta Malanda.")
    lines.append("-- Source: old Supabase CSV export rows.zip.")
    lines.append("-- Safe intent: import campaign context while keeping old player characters unclaimed.")
    lines.append("-- Run after supabase/RUN_THIS_IN_SUPABASE.sql has completed successfully.")
    lines.append("")
    lines.append("begin;")
    lines.append("")
    lines.append("alter table public.characters add column if not exists legacy_owner_name text not null default '';")
    lines.append("")
    lines.append("create table if not exists public.legacy_profiles (")
    lines.append("  id uuid primary key,")
    lines.append("  display_name text not null,")
    lines.append("  role text not null default 'player',")
    lines.append("  imported_at timestamptz not null default now()")
    lines.append(");")
    lines.append("")
    lines.append("create table if not exists public.legacy_loot_generator_config (")
    lines.append("  id text primary key,")
    lines.append("  biomes jsonb not null default '[]'::jsonb,")
    lines.append("  difficulties jsonb not null default '[]'::jsonb,")
    lines.append("  pool_sizes jsonb not null default '[]'::jsonb,")
    lines.append("  room_types jsonb not null default '[]'::jsonb,")
    lines.append("  room_rules jsonb not null default '{}'::jsonb,")
    lines.append("  rare_rules jsonb not null default '{}'::jsonb,")
    lines.append("  formula_notes jsonb not null default '{}'::jsonb,")
    lines.append("  source_updated_at timestamptz,")
    lines.append("  imported_at timestamptz not null default now()")
    lines.append(");")
    lines.append("")

    if profiles:
        lines.append("insert into public.legacy_profiles (id, display_name, role) values")
        lines.append(values_block(f"({q(row['id'])}::uuid, {q_text(row.get('display_name'))}, {q_text(row.get('role'), 'player')})" for row in profiles))
        lines.append("on conflict (id) do update set display_name = excluded.display_name, role = excluded.role;")
        lines.append("")

    if class_assets:
        lines.append("insert into public.class_templates (id, class_key, name, role, armor, identity, base_hp, base_mana, inventory_slots, spell_slots, attributes, passives, token_color) values")
        lines.append(values_block(
            f"({q(row['id'])}::uuid, {q_text(row['class_key'])}, {q_text(row['name'])}, {q_text(row.get('type'))}, {q_text(row.get('armor'))}, {q_text(row.get('identity'))}, {num(row.get('health'), 100)}, {num(row.get('mana'), 0)}, {num(row.get('inventory_slots'), 12)}, {num(row.get('spell_slots'), 0)}, {q_json(row.get('attributes'), {})}, {q_json(row.get('passives'), [])}, {q_text(row.get('token_color'), '#9caf79')})"
            for row in class_assets
        ))
        lines.append("on conflict (class_key) do update set name = excluded.name, role = excluded.role, armor = excluded.armor, identity = excluded.identity, base_hp = excluded.base_hp, base_mana = excluded.base_mana, inventory_slots = excluded.inventory_slots, spell_slots = excluded.spell_slots, attributes = excluded.attributes, passives = excluded.passives, token_color = excluded.token_color;")
        lines.append("")

    if rows("cities"):
        lines.append("insert into public.cities (id, city_key, name, is_locked, display_order) values")
        lines.append(values_block(
            f"({q(row['id'])}::uuid, {q_text(row.get('city_key'))}, {q_text(row.get('name'))}, {('false' if str(row.get('is_open', '')).lower() in {'true','t','1'} else 'true')}, {index * 10 + 10})"
            for index, row in enumerate(rows("cities"))
        ))
        lines.append("on conflict (city_key) do update set name = excluded.name, is_locked = excluded.is_locked, display_order = excluded.display_order;")
        lines.append("")

    facilities = {row["id"]: row for row in rows("city_facilities")}
    cities_by_id = {row["id"]: row for row in rows("cities")}
    vendors = rows("city_vendors")
    if vendors:
        lines.append("insert into public.shop_vendors (id, city_key, vendor_key, name, facility, category, is_hidden, display_order) values")
        vendor_values = []
        for vendor in vendors:
            facility = facilities.get(vendor.get("facility_id", ""), {})
            city = cities_by_id.get(facility.get("city_id", ""), {})
            vendor_values.append(
                f"({q(vendor['id'])}::uuid, {q_text(city.get('city_key'), 'calostrynn')}, {q_text(vendor.get('vendor_key'), slug(vendor.get('name','vendor')))}, {q_text(vendor.get('name'), 'Vendor')}, {q_text(facility.get('name'), 'Market')}, {q_text(vendor.get('role'), 'General')}, false, {num(vendor.get('sort_order'), 0)})"
            )
        lines.append(values_block(vendor_values))
        lines.append("on conflict (vendor_key) do update set city_key = excluded.city_key, name = excluded.name, facility = excluded.facility, category = excluded.category, is_hidden = excluded.is_hidden, display_order = excluded.display_order;")
        lines.append("")

    listings = rows("market_listings")
    listing_by_product = {row["product_id"]: row for row in listings}
    products = rows("market_products")
    if products:
        lines.append("insert into public.market_products (id, vendor_id, product_key, item_name, description, item_type, rarity, price_coin, stock_quantity, is_available, display_order) values")
        product_values = []
        for row in products:
            listing = listing_by_product.get(row["id"])
            if not listing:
                continue
            product_values.append(
                f"({q(row['id'])}::uuid, {q(listing['vendor_id'])}::uuid, {q_text(row.get('product_key'), slug(row.get('name','product')))}, {q_text(row.get('name'), 'Item')}, {q_text(row.get('description'))}, {q_text(item_type(row.get('item_type')))}::public.item_type, {q_text(rarity(row.get('rarity')))}::public.item_rarity, {num(row.get('price_base'), 0)}, {num(row.get('stock_quantity'), 0) if row.get('stock_quantity') else 'null'}, {boolean(row.get('is_available'), True)}, {num(listing.get('sort_order'), 0)})"
            )
        lines.append(values_block(product_values))
        lines.append("on conflict (product_key) do update set vendor_id = excluded.vendor_id, item_name = excluded.item_name, description = excluded.description, item_type = excluded.item_type, rarity = excluded.rarity, price_coin = excluded.price_coin, stock_quantity = excluded.stock_quantity, is_available = excluded.is_available, display_order = excluded.display_order;")
        lines.append("")

    spells = rows("spells")
    spell_by_id = {row["id"]: row for row in spells}
    if spells:
        lines.append("insert into public.spell_catalog (id, spell_key, name, school, mana_cost, summary, details, rarity, is_available, display_order) values")
        lines.append(values_block(
            f"({q(row['id'])}::uuid, {q_text(row.get('spell_key'), slug(row.get('name','spell')))}, {q_text(row.get('name'), 'Spell')}, {q_text(spell_school(row.get('category')))}, {num(row.get('mana_cost'), 0)}, {q_text(row.get('category'))}, {q_text(row.get('description'))}, 'Common'::public.item_rarity, true, {index * 10 + 10})"
            for index, row in enumerate(spells)
        ))
        lines.append("on conflict (spell_key) do update set name = excluded.name, school = excluded.school, mana_cost = excluded.mana_cost, summary = excluded.summary, details = excluded.details, is_available = excluded.is_available, display_order = excluded.display_order;")
        lines.append("")

    if characters:
        lines.append("insert into public.characters (id, name, kind, owner_user_id, class_template_id, class_key, class_name, level, max_hp, current_hp, max_mana, current_mana, inventory_slots, spell_slots, attributes, class_passives, personal_passives, token_color, location_name, legacy_owner_name) values")
        character_values = []
        for row in characters:
            class_key = row.get("class_key") or slug(row.get("class_name", "adventurer"), "adventurer")
            class_asset = class_by_key.get(class_key, {})
            owner = profile_by_id.get(row.get("owner_user_id", ""), {})
            location = location_by_id.get(row.get("location_id", ""), {})
            character_values.append(
                f"({q(row['id'])}::uuid, {q_text(row.get('name'), 'Unnamed')}, {q_text(row.get('kind'), 'player')}::public.character_kind, null, (select id from public.class_templates where class_key = {q_text(class_key)} limit 1), {q_text(class_key)}, {q_text(row.get('class_name'), class_asset.get('name', 'Adventurer'))}, {num(row.get('level'), 1)}, {num(row.get('max_hp'), num(class_asset.get('health'), 100))}, {num(row.get('current_hp'), num(row.get('max_hp'), 100))}, {num(row.get('max_mana'), num(class_asset.get('mana'), 0))}, {num(row.get('current_mana'), num(row.get('max_mana'), 0))}, {adjusted_inventory_capacity.get(row['id'], num(row.get('inventory_slots'), 12))}, {num(row.get('spell_slots'), num(class_asset.get('spell_slots'), 0))}, {q_json(row.get('attributes'), {})}, {q_json(class_asset.get('passives'), [])}, {q_text(row.get('notes'))}, {q_text(row.get('token_color') or class_asset.get('token_color'), '#9caf79')}, {q_text(location.get('name'), 'Calostrynn')}, {q_text(owner.get('display_name') if row.get('kind') == 'player' else '')})"
            )
        lines.append(values_block(character_values))
        lines.append("on conflict (id) do update set name = excluded.name, kind = excluded.kind, class_template_id = excluded.class_template_id, class_key = excluded.class_key, class_name = excluded.class_name, level = excluded.level, max_hp = excluded.max_hp, current_hp = excluded.current_hp, max_mana = excluded.max_mana, current_mana = excluded.current_mana, inventory_slots = excluded.inventory_slots, spell_slots = excluded.spell_slots, attributes = excluded.attributes, class_passives = excluded.class_passives, personal_passives = excluded.personal_passives, token_color = excluded.token_color, location_name = excluded.location_name, legacy_owner_name = excluded.legacy_owner_name;")
        lines.append("")

    if inventory:
        lines.append("delete from public.inventory_items where id in (")
        lines.append(", ".join(f"{q(row['id'])}::uuid" for row in inventory))
        lines.append(");")
        lines.append("insert into public.inventory_items (id, character_id, parent_item_id, item_name, item_type, rarity, quantity, slot_index, loadout_slot, is_storage, storage_capacity, modifiers, spell_imbue) values")
        item_values = []
        for row in inventory:
            slot = adjusted_slot_by_item.get(row["id"], max(0, num(row.get("slot_index"), 0)))
            loadout = row.get("loadout_slot") if row.get("loadout_slot") in LOADOUT_SLOTS else None
            item_values.append(
                f"({q(row['id'])}::uuid, {q(row['character_id'])}::uuid, {q(row.get('parent_item_id')) + '::uuid' if row.get('parent_item_id') else 'null'}, {q_text(row.get('item_name'), 'Item')}, {q_text(item_type(row.get('item_type')))}::public.item_type, {q_text(rarity(row.get('rarity')))}::public.item_rarity, {max(1, num(row.get('quantity'), 1))}, {slot}, {q(loadout)}, {boolean(row.get('is_storage'))}, {num(row.get('storage_capacity'), 0)}, {q_json(row.get('modifiers'), {})}, null)"
            )
        lines.append(values_block(item_values))
        lines.append("on conflict (id) do nothing;")
        lines.append("")

    wallets = rows("character_wallets")
    if wallets:
        lines.append("delete from public.character_wallet_balances where character_id in (")
        lines.append(", ".join(sorted({f"{q(row['character_id'])}::uuid" for row in wallets})))
        lines.append(");")
        wallet_values = []
        for row in wallets:
            balance = max(0, num(row.get("balance_base"), 0))
            cal, rem = divmod(balance, 10000)
            callor, rem = divmod(rem, 100)
            callis, coin = divmod(rem, 10)
            for unit, amount in [("coin", coin), ("callis", callis), ("callor", callor), ("cal", cal)]:
                wallet_values.append(f"({q(row['character_id'])}::uuid, (select id from public.currency_units where unit_key = {q_text(unit)}), {amount})")
        lines.append("insert into public.character_wallet_balances (character_id, currency_unit_id, amount) values")
        lines.append(values_block(wallet_values))
        lines.append("on conflict (character_id, currency_unit_id) do update set amount = excluded.amount;")
        lines.append("")

    character_spells = rows("character_spells")
    if character_spells:
        lines.append("delete from public.character_spells where id in (")
        lines.append(", ".join(f"{q(row['id'])}::uuid" for row in character_spells))
        lines.append(");")
        lines.append("insert into public.character_spells (id, character_id, spell_id, is_active, slot_index) values")
        lines.append(values_block(
            f"({q(row['id'])}::uuid, {q(row['character_id'])}::uuid, (select id from public.spell_catalog where spell_key = {q_text(spell_by_id.get(row.get('spell_id'), {}).get('spell_key'), 'missing-legacy-spell')} limit 1), {('true' if row.get('prepared_slot') not in {'', None} else 'false')}, {num(row.get('prepared_slot'), 0) if row.get('prepared_slot') not in {'', None} else 'null'})"
            for row in character_spells
        ))
        lines.append("on conflict (character_id, spell_id) do update set is_active = excluded.is_active, slot_index = excluded.slot_index;")
        lines.append("")

    enemies = rows("enemy_assets")
    if enemies:
        lines.append("insert into public.bestiary_entities (entity_key, name, category, habitat, temperament, wild_score, hp, mana, summary, details, is_unlocked, display_order) values")
        lines.append(values_block(
            f"({q_text(row.get('enemy_key'), slug(row.get('name','enemy')))}, {q_text(row.get('name'), 'Enemy')}, {q_text(bestiary_category(row.get('category')))}, {q_text(row.get('category'))}, '', {num(row.get('damage'), 0)}, {num(row.get('health'), 0)}, {num(row.get('mana'), 0)}, {q_text(row.get('category'))}, {q_text(row.get('notes'))}, {boolean(row.get('is_discovered'))}, {index * 10 + 10})"
            for index, row in enumerate(enemies)
        ))
        lines.append("on conflict (entity_key) do update set name = excluded.name, category = excluded.category, habitat = excluded.habitat, wild_score = excluded.wild_score, hp = excluded.hp, mana = excluded.mana, summary = excluded.summary, details = excluded.details, is_unlocked = excluded.is_unlocked, display_order = excluded.display_order;")
        lines.append("")

    loot_entries = rows("loot_entries")
    if loot_entries:
        categories = sorted({row.get("category") or "Legacy Loot" for row in loot_entries})
        lines.append("insert into public.loot_pools (pool_key, name, description, display_order) values")
        lines.append(values_block(f"({q_text('legacy-' + slug(category))}, {q_text(category)}, 'Imported legacy loot category.', {index * 10 + 100})" for index, category in enumerate(categories)))
        lines.append("on conflict (pool_key) do update set name = excluded.name, description = excluded.description, display_order = excluded.display_order;")
        lines.append("")
        lines.append("delete from public.loot_items where id in (")
        lines.append(", ".join(f"{q(row['id'])}::uuid" for row in loot_entries))
        lines.append(");")
        lines.append("insert into public.loot_items (id, pool_id, item_name, item_type, rarity, min_quantity, max_quantity, weight, notes, is_active) values")
        lines.append(values_block(
            f"({q(row['id'])}::uuid, (select id from public.loot_pools where pool_key = {q_text('legacy-' + slug(row.get('category') or 'Legacy Loot'))}), {q_text(row.get('item_name'), 'Loot')}, {q_text(item_type(row.get('item_type')))}::public.item_type, {q_text(rarity(row.get('rarity')))}::public.item_rarity, {max(1, num(row.get('min_quantity'), 1))}, {max(max(1, num(row.get('min_quantity'), 1)), num(row.get('max_quantity'), 1))}, {max(1, num(row.get('weight'), 1))}, {q_text('Biomes: ' + (row.get('biomes') or 'Any'))}, true)"
            for row in loot_entries
        ))
        lines.append("on conflict (id) do update set pool_id = excluded.pool_id, item_name = excluded.item_name, item_type = excluded.item_type, rarity = excluded.rarity, min_quantity = excluded.min_quantity, max_quantity = excluded.max_quantity, weight = excluded.weight, notes = excluded.notes, is_active = excluded.is_active;")
        lines.append("")

    configs = rows("loot_generator_config")
    if configs:
        lines.append("insert into public.legacy_loot_generator_config (id, biomes, difficulties, pool_sizes, room_types, room_rules, rare_rules, formula_notes, source_updated_at) values")
        lines.append(values_block(
            f"({q_text(row.get('id'), 'default')}, {q_json(row.get('biomes'), [])}, {q_json(row.get('difficulties'), [])}, {q_json(row.get('pool_sizes'), [])}, {q_json(row.get('room_types'), [])}, {q_json(row.get('room_rules'), {})}, {q_json(row.get('rare_rules'), {})}, {q_json(row.get('formula_notes'), {})}, {q(row.get('updated_at'))}::timestamptz)"
            for row in configs
        ))
        lines.append("on conflict (id) do update set biomes = excluded.biomes, difficulties = excluded.difficulties, pool_sizes = excluded.pool_sizes, room_types = excluded.room_types, room_rules = excluded.room_rules, rare_rules = excluded.rare_rules, formula_notes = excluded.formula_notes, source_updated_at = excluded.source_updated_at;")
        lines.append("")

    lines.append("commit;")
    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Wrote {OUT}")


if __name__ == "__main__":
    main()
