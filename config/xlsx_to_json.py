#!/usr/bin/env python3
"""Convert separate .xlsx files under config/xlsx/ back to JSON config files.

Usage: cd config && python xlsx_to_json.py
Output: config/json_output/
"""

import json, re
from pathlib import Path
from openpyxl import load_workbook

BASE = Path(__file__).parent
XLSX_DIR = BASE / "xlsx"
OUT = BASE / "json_output"
OUT.mkdir(exist_ok=True)


def parse_int(v):
    if v is None or v == "" or v == "None":
        return None
    return int(float(v))


def parse_bool(v):
    if v is None or v == "":
        return False
    if isinstance(v, bool):
        return v
    return str(v).upper() in ("TRUE", "1", "YES")


def parse_int_list(v, sep=";"):
    if v is None or v == "":
        return []
    return [int(x.strip()) for x in str(v).split(sep) if x.strip()]

def parse_ingredient_list(v):
    if v is None or v == "":
        return []
    import re
    result = []
    for part in str(v).split(";"):
        part = part.strip()
        if not part:
            continue
        # Handle dict-like: {'id': 1002, 'count': 3} or JSON: {"id": 1002, "count": 3}
        if part.startswith("{"):
            m = re.search(r"['\"]id['\"]\s*:\s*(\d+)", part)
            if m:
                result.append(int(m.group(1)))
            continue
        # Handle id:count format: 1002:3
        if ":" in part:
            iid, _ = part.split(":", 1)
            result.append(int(iid.strip()))
            continue
        result.append(int(part))
    return result


def parse_dict_list(v, key1="id", key2="weight", sep=";"):
    if v is None or v == "":
        return []
    result = []
    for part in str(v).split(sep):
        part = part.strip()
        if not part:
            continue
        if ":" in part:
            a, b = part.split(":", 1)
            result.append({key1: int(a), key2: int(b)})
        else:
            result.append(int(part))
    return result


def parse_reward_config(v):
    if v is None or v == "":
        return None
    text = str(v).strip()
    if text.startswith("{") or text.startswith("["):
        return json.loads(text)
    if re.fullmatch(r"\d+", text):
        return parse_int(text)
    return None


def parse_fixed_orders(v):
    if v is None or v == "":
        return []
    text = str(v).strip()
    if text.startswith("["):
        parsed = json.loads(text)
        result = []
        for entry in parsed:
            if isinstance(entry, dict):
                item_ids = parse_int_list(entry.get("item_ids", [])) if isinstance(entry.get("item_ids"), str) else [int(x) for x in entry.get("item_ids", [])]
            elif isinstance(entry, list):
                item_ids = [int(x) for x in entry]
            else:
                item_ids = [int(entry)]
            if item_ids:
                result.append({"item_ids": item_ids})
        return result
    return [{"item_ids": [int(x.strip())]} for x in text.split(";") if x.strip()]


def read_rows(ws):
    headers = [str(c.value).strip() if c.value else "" for c in ws[1]]
    rows = []
    for row in ws.iter_rows(min_row=2, values_only=True):
        d = {}
        for i, val in enumerate(row):
            if i < len(headers) and headers[i]:
                d[headers[i]] = str(val).strip() if val is not None and str(val).strip() != "None" else ""
        if any(v != "" for v in d.values()):
            rows.append(d)
    return rows


def save_json(filename, data):
    path = OUT / filename
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"  -> {filename}")


def open_book(name):
    return load_workbook(XLSX_DIR / f"{name}.xlsx")


# ─── items ─────────────────────────────────────────────────
print("Building items.json...")
wb = open_book("items")

regular = []
for row in read_rows(wb["items_regular"]):
    item = {"id": parse_int(row["id"]), "level": parse_int(row["level"]),
            "name": row["name"], "icon": row.get("icon", ""),
            "group_id": parse_int(row["group_id"]), "describe": row["describe"]}
    if row.get("type") != "":
        item["type"] = parse_int(row["type"])
    if row.get("value"):
        item["value"] = parse_int(row["value"])
    if row.get("sell_price"):
        item["sell_price"] = parse_int(row["sell_price"])

    regular.append(item)

launcher = []
for row in read_rows(wb["items_launcher"]):
    item = {"id": parse_int(row["id"]), "level": parse_int(row["level"]),
            "name": row["name"], "icon": row.get("icon", ""),
            "group_id": parse_int(row["group_id"]),
            "max_charges": parse_int(row["max_charges"]),
            "recharge_time": parse_int(row["recharge_time"]),
            "describe": row["describe"]}
    if row.get("type"):
        item["type"] = row["type"]
    if parse_bool(row.get("no_cost")):
        item["no_cost"] = True
    spawns = parse_dict_list(row.get("spawns(id:weight)", ""))
    fixed = parse_int_list(row.get("fixed_spawns", ""))
    if fixed:
        item["fixed_spawns"] = fixed
    elif spawns:
        item["spawns"] = spawns
    launcher.append(item)

crafting = []
for row in read_rows(wb["items_crafting"]):
    item = {
        "id": parse_int(row["id"]), "level": parse_int(row["level"]),
        "name": row["name"], "group_id": parse_int(row["group_id"]),
        "icon": row.get("icon", ""), "describe": row["describe"],
        "recipes": parse_int_list(row.get("recipes", "")),
    }
    if row.get("type") != "":
        item["type"] = parse_int(row["type"])
    crafting.append(item)
# Read items_recipe_product sheet if it exists
if "items_recipe_product" in [ws.title for ws in wb.worksheets]:
    for row in read_rows(wb["items_recipe_product"]):
        item = {"id": parse_int(row["id"]),
                "name": row["name"], "icon": row.get("icon", ""),
                "describe": row["describe"],
                "type": 4}
        if row.get("value"):
            item["value"] = parse_int(row["value"])
        if row.get("effect_type"):
            item["effect_type"] = parse_int(row["effect_type"])
        if row.get("effect_value"):
            item["effect_value"] = parse_int(row["effect_value"])
        # Optional launcher fields
        if row.get("max_charges"):
            item["max_charges"] = parse_int(row["max_charges"])
        if row.get("recharge_time"):
            item["recharge_time"] = parse_int(row["recharge_time"])
        if parse_bool(row.get("no_cost")):
            item["no_cost"] = True
        spawns = parse_dict_list(row.get("spawns(id:weight)", ""))
        fixed = parse_int_list(row.get("fixed_spawns", ""))
        if fixed:
            item["fixed_spawns"] = fixed
        elif spawns:
            item["spawns"] = spawns
        regular.append(item)
effect_items = []
if "items_effect" in [ws.title for ws in wb.worksheets]:
    for row in read_rows(wb["items_effect"]):
        item = {"id": parse_int(row["id"]), "level": parse_int(row["level"]),
                "name": row["name"], "icon": row.get("icon", ""),
                "group_id": parse_int(row["group_id"]), "describe": row["describe"],
                "effect_type": parse_int(row["effect_type"]),
                "effect_value": parse_int(row["effect_value"]),
                "type": 5}

        if row.get("value"):
            item["value"] = parse_int(row["value"])

        effect_items.append(item)
save_json("items.json", {"regular": regular, "launcher": launcher, "crafting": crafting, "effect": effect_items})

# ─── meridians ─────────────────────────────────────────────
print("Building meridians.json...")
wb = open_book("meridians")
thresholds = []
for row in read_rows(wb["meridians"]):
    threshold = {
        "stage": parse_int(row["stage"]),
        "item_pool": parse_int_list(row["item_pool"]),
        "count_min": parse_int(row["count_min"]),
        "count_max": parse_int(row["count_max"]),
        "acupoint_rewards": parse_int(row.get("acupoint_rewards", "")),
        "order_count": parse_int(row["order_count"]),
    }
    fixed_orders = parse_fixed_orders(row.get("fixed_orders", ""))
    if fixed_orders:
        threshold["fixed_orders"] = fixed_orders
    thresholds.append(threshold)
save_json("meridians.json", {"thresholds": thresholds})

# ─── rewards ───────────────────────────────────────────────
print("Building rewards.json...")
wb = open_book("rewards")
rewards = {}
for row in read_rows(wb["rewards"]):
    entry = {}
    tokens = parse_dict_list(row.get("tokens(token:amount)", ""), "token", "amount")
    if tokens:
        entry["tokens"] = tokens
    items = parse_dict_list(row.get("items(id:count)", ""), "id", "count")
    if items:
        entry["items"] = items
    if entry:
        rewards[row["reward_id"]] = entry
save_json("rewards.json", {"rewards": rewards})

# ─── game_config ───────────────────────────────────────────
print("Building game_config.json...")
wb = open_book("game_config")
def unflatten(rows):
    result = {}
    for row in rows:
        key = row["parameter"]
        val = row["value"]
        if not key or val == "":
            continue
        v = parse_int(val) if val.lstrip("-").isdigit() else val
        parts = key.split(".")
        target = result
        for part in parts[:-1]:
            if part not in target:
                target[part] = {}
            target = target[part]
        target[parts[-1]] = v
    return result
save_json("game_config.json", unflatten(read_rows(wb["game_config"])))

# ─── recipes ───────────────────────────────────────────────
print("Building recipes.json...")
wb = open_book("recipes")
recipes = []
for row in read_rows(wb["recipes"]):
    recipes.append({
        "id": parse_int(row["id"]), "name": row["name"],
        "ingredients": parse_ingredient_list(row["ingredients"]),
        "result": parse_int(row["result"]),
        "craft_time": parse_int(row["craft_time"]),
    })
save_json("recipes.json", {"recipes": recipes})

# ─── initial_setup ─────────────────────────────────────────
print("Building initial_setup.json...")
wb = open_book("initial_setup")
setup = {}
for row in read_rows(wb["initial_setup"]):
    section = row["section"]
    if section not in setup:
        setup[section] = {"items": []}
    setup[section]["items"].append({
        "id": parse_int(row["id"]), "col": parse_int(row["col"]),
        "row": parse_int(row["row"]), "immovable": parse_bool(row["immovable"]),
    })
save_json("initial_setup.json", setup)

# ─── cultivation ───────────────────────────────────────────
print("Building cultivation.json...")
wb = open_book("cultivation")
stages = []
for row in read_rows(wb["cultivation"]):
    stage = {"name": row["name"], "exp": parse_int(row["exp"]),
             "max_qi": parse_int(row["max_qi"])}
    if row.get("breakthrough_pill"):
        stage["breakthrough_pill"] = parse_int(row["breakthrough_pill"])
    if row.get("breakthrough_reward_id"):
        stage["breakthrough_reward_id"] = parse_int(row["breakthrough_reward_id"])
    stages.append(stage)
save_json("cultivation.json", {"stages": stages})

# ─── shop ──────────────────────────────────────────────────
print("Building shop.json...")
wb = open_book("shop")
items_list = []
for row in read_rows(wb["shop"]):
    items_list.append({"id": parse_int(row["id"]), "price": parse_int(row["price"])})
save_json("shop.json", {"items": items_list})

# ─── expedition ────────────────────────────────────────────
print("Building expedition.json...")
wb = open_book("expedition")
monsters = []
for row in read_rows(wb["monsters"]):
    monsters.append({
        "id": parse_int(row["id"]), "name": row["name"],
        "hp": parse_int(row["hp"]), "atk": parse_int(row["atk"]),
        "accept_effect_ids": parse_int_list(row["accept_effect_ids"]),
        "loot": parse_int_list(row["loot"]),
        "describe": row["describe"],
    })

maps_raw = {row["id"]: row for row in read_rows(wb["maps"])}
stages_by_map = {}
for row in read_rows(wb["map_stages"]):
    mid = row["map_id"]
    if mid not in stages_by_map:
        stages_by_map[mid] = []
    stage = {
        "stage": parse_int(row["stage"]), "name": row["name"],
        "monsters": parse_dict_list(row.get("monsters(monster_id:count)", ""), "monster_id", "count"),
    }
    boss_id = row.get("boss_monster_id", "")
    if boss_id:
        stage["boss"] = {"monster_id": parse_int(boss_id)}
    stages_by_map[mid].append(stage)

maps_list = []
for mid, mp in maps_raw.items():
    maps_list.append({
        "id": parse_int(mp["id"]), "name": mp["name"],
        "describe": mp["describe"],
        "stages": stages_by_map.get(mid, []),
    })
save_json("expedition.json", {"monsters": monsters, "maps": maps_list})


# ─── tokens ────────────────────────────────────────────────
print("Building tokens.json...")
wb = open_book("tokens")
tokens = []
for row in read_rows(wb["tokens"]):
    tokens.append({
        "id": parse_int(row["id"]), "name": row["name"],
        "icon": row.get("icon", ""), "describe": row["describe"],
    })
save_json("tokens.json", {"tokens": tokens})

# ─── server ────────────────────────────────────────────────
print("Building server.json...")
wb = open_book("server")
server = {}
for row in read_rows(wb["server"]):
    val = row["value"]
    server[row["parameter"]] = parse_int(val) if val.isdigit() else val
save_json("server.json", server)

# ─── quests ────────────────────────────────────────────────
print("Building quests.json...")
wb = open_book("quests")
quests = []
for row in read_rows(wb["quests"]):
    quests.append({
        "id": parse_int(row["id"]), "type": parse_int(row["type"]),
        "name": row["name"], "description": row["description"],
        "target_count": parse_int(row["target_count"]),
        "rewards": parse_int(row["rewards"]),
        "auto_reward": parse_bool(row["auto_reward"]),
        "reset_cycle": parse_int(row["reset_cycle"]),
    })
save_json("quests.json", {"quests": quests})

# ─── activities ────────────────────────────────────────────
print("Building activities.json...")
wb = open_book("activities")
activities = []
for row in read_rows(wb["activities"]):
    act = {"id": parse_int(row["id"]), "name": row["name"],
           "cycle": parse_int(row["cycle"]), "widget": row.get("widget", "")}
    if row.get("start_time"):
        act["start_time"] = row["start_time"]
    if row.get("end_time"):
        act["end_time"] = row["end_time"]
    activities.append(act)
save_json("activities.json", {"activities": activities})

# ─── weekly_tasks ───────────────────────────────────────────
print("Building weekly_tasks.json...")
wb = open_book("weekly_tasks")
tasks_by_activity = {}
for row in read_rows(wb["weekly_tasks"]):
    aid = row["activity_id"]
    if aid not in tasks_by_activity:
        tasks_by_activity[aid] = {"activity_id": parse_int(aid), "daily_quests": []}
    tasks_by_activity[aid]["daily_quests"].append(parse_int_list(row["quests"]))
weekly_tasks = list(tasks_by_activity.values())
save_json("weekly_tasks.json", {"weekly_tasks": weekly_tasks})

# ─── home_meridians ────────────────────────────────────────
print("Building home_meridians.json...")
wb = open_book("home_meridians")
home_stages = []
for row in read_rows(wb["home_meridians"]):
    acupoint_exp = parse_int(row.get("acupoint_exp", "")) or 0
    circulation_exp = parse_int(row.get("circulation_exp", "")) or 0
    acupoint_rewards = parse_reward_config(row.get("acupoint_rewards", ""))
    if acupoint_rewards is None:
        acupoint_rewards = {"tokens": [
            {"token": 4, "amount": acupoint_exp},
            {"token": 3, "amount": 15},
        ]}
    home_stages.append({
        "name": row["name"], "acupoints": parse_int(row["acupoints"]),
        "qi_cost": parse_int(row["qi_cost"]),
        "acupoint_rewards": acupoint_rewards,
        "circulation_rewards": {"tokens": [
            {"token": 4, "amount": circulation_exp},
            {"token": 3, "amount": 100},
        ]},
    })
save_json("home_meridians.json", {"stages": home_stages})

print(f"\nDone! JSON files written to {OUT}")
