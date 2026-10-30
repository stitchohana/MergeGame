"""Schema adapter for the secret-realm workbook used by the existing config pipeline."""
import json

SECRET_REALM_COLUMNS = {
    "settings": ["activity_id", "period", "cols", "rows", "advance"],
    "items": ["id", "chain", "level", "name", "value"],
    "layout": ["col", "row", "fog", "id", "immovable", "monster"],
    "monsters": ["id", "name", "boss", "costs", "drops"],
    "stages": ["boss", "name"],
    "merge_drops": ["min_level", "max_level", "drops"],
    "order_supply": ["id", "count", "immovable"],
    "order_supply_realms": ["cultivation_min", "cultivation_max", "drops"],
}
JSON_FIELDS = {"costs", "drops"}
BOOL_FIELDS = {"fog", "immovable", "boss"}
INT_FIELDS = {"activity_id", "cols", "rows", "advance", "level", "value", "col", "row", "min_level", "max_level", "count", "cultivation_min", "cultivation_max"}


def validate_secret_realm(data):
    def require(condition, reason):
        if not condition:
            raise ValueError("secret_realm: " + reason)

    def number(value, minimum=0):
        return type(value) is int and value >= minimum

    require(set(data) == set(SECRET_REALM_COLUMNS), "invalid sheets")
    for sheet, columns in SECRET_REALM_COLUMNS.items():
        require(isinstance(data[sheet], list) and data[sheet], sheet + " is empty")
        for record in data[sheet]:
            require(set(record) == set(columns), sheet + " invalid columns")
            for key, value in record.items():
                if key in JSON_FIELDS:
                    require(isinstance(value, list), key + " must be an array")
                elif key in BOOL_FIELDS and sheet != "stages":
                    require(type(value) is bool, key + " must be boolean")
                elif key in INT_FIELDS:
                    require(number(value), key + " must be a nonnegative integer")
                else:
                    require(isinstance(value, str), key + " must be text")
    require(len(data["settings"]) == 1, "exactly one settings row required")
    settings = data["settings"][0]
    require(settings["cols"] == 6 and settings["rows"] == 8 and 1 <= settings["advance"] <= 8, "invalid viewport")
    require(settings["activity_id"] > 0 and settings["period"].strip(), "invalid activity/period")
    definitions = {record["id"]: record for record in data["items"]}
    require(len(definitions) == len(data["items"]) == 24, "duplicate/missing item")
    for chain, cap in (("sword", 12), ("qi", 6), ("stamina", 3), ("stone", 3)):
        require(sorted(d["level"] for d in definitions.values() if d["chain"] == chain) == list(range(1, cap + 1)), "invalid " + chain + " chain")
    require(all(d["name"].strip() and (d["value"] > 0 if d["chain"] in ("stamina", "stone") else True) for d in definitions.values()), "invalid item name/value")

    def drops_valid(drops):
        return isinstance(drops, list) and all(set(d) == {"id", "count", "immovable"} and d["id"] in definitions
            and number(d["count"], 1) and d["count"] <= 100 and type(d["immovable"]) is bool
            and (not d["immovable"] or definitions[d["id"]]["chain"] == "sword") for d in drops)

    monsters = {m["id"]: m for m in data["monsters"]}
    require(len(monsters) == len(data["monsters"]), "duplicate monster")
    for monster in monsters.values():
        require(monster["id"] and monster["name"] and monster["costs"], "invalid monster")
        require(drops_valid(monster["drops"]), "invalid monster drops")
        require(all(definitions[d["id"]]["chain"] in ("stamina", "stone") for d in monster["drops"]), "monster rewards must be items")
        require(len({c["id"] for c in monster["costs"]}) == len(monster["costs"]), "duplicate cost")
        for cost in monster["costs"]:
            require(set(cost) == {"id", "count"} and cost["id"] in definitions and number(cost["count"], 1) and cost["count"] <= 100, "invalid cost")
            require(definitions[cost["id"]]["chain"] in ("sword", "qi"), "invalid cost chain")
        if monster["boss"]:
            costs = [definitions[c["id"]] for c in monster["costs"]]
            require(any(d["chain"] == "sword" for d in costs) and any(d["chain"] == "qi" for d in costs)
                    and all(d["level"] == 6 for d in costs if d["chain"] == "qi"), "Boss requires sword and max qi")
    positions = {}
    height = 8 + settings["advance"] * (len(data["stages"]) - 1)
    for cell in data["layout"]:
        position = (cell["col"], cell["row"])
        require(0 <= cell["col"] < 6 and 0 <= cell["row"] < height and position not in positions, "invalid/duplicate layout position")
        require(bool(cell["id"]) != bool(cell["monster"]), "one occupant per cell")
        require(cell["id"] in definitions if cell["id"] else cell["monster"] in monsters, "unknown occupant")
        if cell["id"] and cell["immovable"]:
            require(definitions[cell["id"]]["chain"] in ("sword", "qi"), "only swords and qi may be fixed")
        positions[position] = cell
    require(len(positions) == height * 6, "layout must fill world")
    previous_level = 1
    for row in range(height):
        levels = [definitions[c["id"]]["level"] for c in positions.values() if c["row"] == row and c["id"] and c["immovable"] and definitions[c["id"]]["chain"] == "sword"]
        if levels:
            require(min(levels) >= previous_level, "fixed sword levels must ascend with map rows")
            previous_level = max(levels)
    starters = [c for c in positions.values() if c["row"] < 8 and c["id"] and not c["immovable"]]
    require(len(starters) == 3 and all(not c["fog"] and definitions[c["id"]]["level"] == 1 for c in starters), "exactly three revealed movable level-1 items required")
    require(any(any(c != t and not t["fog"] and t["id"] == c["id"] for t in positions.values() if t["row"] < 8) for c in starters), "no initial merge")
    boss_fog_stages = {}
    for index, stage in enumerate(data["stages"]):
        bosses = [c for c in positions.values() if c["monster"] == stage["boss"]]
        require(stage["boss"] in monsters and monsters[stage["boss"]]["boss"] and len(bosses) == 1, "invalid stage Boss")
        require(index * settings["advance"] <= bosses[0]["row"] < index * settings["advance"] + 8, "Boss outside stage viewport")
        boss = bosses[0]
        zone = {pos: c for pos, c in positions.items() if abs(pos[0]-boss["col"]) <= 1 and abs(pos[1]-boss["row"]) <= 1}
        require(len(zone) == 9 and all(c["fog"] and index * settings["advance"] <= pos[1] < index * settings["advance"] + 8
                and (not c["monster"] or c["monster"] == stage["boss"]) for pos, c in zone.items()), "Boss fog must be nine fogged cells without mobs")
        require(not set(zone) & set(boss_fog_stages), "overlapping Boss fog zones")
        boss_fog_stages.update({pos: index for pos in zone})
    require(drops_valid(data["order_supply"]) and any(definitions[d["id"]]["chain"] == "sword" and definitions[d["id"]]["level"] == 1 and not d["immovable"] for d in data["order_supply"]), "missing level-1 supply")
    supply_levels = set()
    for rule in data["order_supply_realms"]:
        require(1 <= rule["cultivation_min"] <= rule["cultivation_max"] <= 20, "invalid supply cultivation range")
        levels = set(range(rule["cultivation_min"], rule["cultivation_max"] + 1))
        require(not levels & supply_levels, "overlapping supply cultivation ranges")
        supply_levels.update(levels)
        require(rule["drops"] and drops_valid(rule["drops"]), "invalid realm supply drops")
        require(all(definitions[d["id"]]["chain"] == "sword" and not d["immovable"] for d in rule["drops"]), "realm supply must be movable swords")
    for rule in data["merge_drops"]:
        require(2 <= rule["min_level"] <= rule["max_level"] <= 12 and drops_valid(rule["drops"]), "invalid merge drop rule")
        for drop in rule["drops"]:
            definition = definitions[drop["id"]]
            require(definition["chain"] in ("sword", "qi") and drop["immovable"] == (definition["chain"] == "sword"), "invalid drop mobility")
            require(definition["chain"] != "sword" or definition["level"] < rule["min_level"], "sword drop must be lower than output")
    require(any(definitions[d["id"]]["chain"] == "qi" for rule in data["merge_drops"] for d in rule["drops"]), "no qi source")
    for level in range(2, 13):
        require(sum(drop["count"] for rule in data["merge_drops"] if rule["min_level"] <= level <= rule["max_level"]
                    for drop in rule["drops"] if definitions[drop["id"]]["chain"] == "sword") <= 2,
                "at most two sword drops per merge")
    revealed = {pos for pos, cell in positions.items() if not cell["fog"]}
    for index, stage in enumerate(data["stages"]):
        window = {pos: c for pos, c in positions.items() if index * settings["advance"] <= pos[1] < index * settings["advance"] + 8}
        while True:
            added = {neighbor for pos, c in window.items() if pos in revealed and c["id"] for neighbor in window
                     if abs(pos[0]-neighbor[0]) + abs(pos[1]-neighbor[1]) == 1 and boss_fog_stages.get(neighbor, -1) < index} - revealed
            if not added:
                break
            revealed.update(added)
        require(all(pos in revealed for pos, c in window.items() if c["monster"] and not monsters[c["monster"]]["boss"]), "mob cannot be revealed outside Boss fog")
        revealed.update(pos for pos in window if boss_fog_stages.get(pos) == index)
        require(any(pos in revealed for pos, c in window.items() if c["monster"] == stage["boss"]), "Boss cannot be revealed")
    return data


def secret_realm_rows(data, sheet):
    validate_secret_realm(data)
    return [[json.dumps(row[key], ensure_ascii=False, separators=(",", ":")) if key in JSON_FIELDS else row[key]
             for key in SECRET_REALM_COLUMNS[sheet]] for row in data[sheet]]


def read_secret_realm(workbook):
    data = {}
    for name, columns in SECRET_REALM_COLUMNS.items():
        rows = list(workbook[name].values)
        if list(rows[0]) != columns:
            raise ValueError("secret_realm." + name + ": invalid headers")
        data[name] = []
        for values in rows[1:]:
            if all(v is None for v in values):
                continue
            record = {}
            for key, value in zip(columns, values):
                if key in JSON_FIELDS:
                    value = json.loads(value)
                elif key in BOOL_FIELDS and name != "stages":
                    if type(value) is not bool:
                        if str(value).upper() not in ("TRUE", "FALSE"):
                            raise ValueError("secret_realm: invalid boolean " + key)
                        value = str(value).upper() == "TRUE"
                elif key in INT_FIELDS:
                    if isinstance(value, bool) or not isinstance(value, (float, int)) or int(value) != value:
                        raise ValueError("secret_realm: invalid integer " + key)
                    value = int(value)
                else:
                    value = "" if value is None else str(value)
                record[key] = value
            data[name].append(record)
    return validate_secret_realm(data)
