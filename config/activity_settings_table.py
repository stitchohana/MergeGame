"""Column schemas and validation for dedicated activity configuration tables."""
import math

ACTIVITY_SETTINGS_COLUMNS = {
    "stair_climb": {
        "settings": ["activity_id", "group_size", "bot_min_minutes", "bot_max_minutes", "order_points_ratio", "bot_order_value"],
        "rewards": ["activity_id", "min_rank", "max_rank", "stamina", "spirit_stones"],
    },
    "order_supply": {"settings": ["activity_id", "target_count", "reward_count"]},
    "order_duel": {
        "settings": ["activity_id", "target_points", "order_points_ratio", "win_stamina", "win_points", "matchmaking_seconds", "bot_min_seconds", "bot_max_seconds", "bot_order_value"],
        "rewards": ["activity_id", "tier", "required_points", "stamina", "spirit_stones"],
    },
}
DECIMAL_FIELDS = {"bot_min_minutes", "bot_max_minutes", "order_points_ratio", "bot_order_value"}


def read_activity_settings(workbook, name):
    result = {}
    for sheet_name, columns in ACTIVITY_SETTINGS_COLUMNS[name].items():
        sheet = workbook[sheet_name]
        headers = [cell.value for cell in sheet[1]]
        if any(column not in headers for column in columns):
            raise ValueError(f"{name}.{sheet_name}: missing columns")
        entries = []
        for values in sheet.iter_rows(min_row=2, values_only=True):
            if all(value is None for value in values):
                continue
            source = dict(zip(headers, values))
            entry = {}
            for key in columns:
                value = source[key]
                if isinstance(value, bool) or value in (None, ""):
                    raise ValueError(f"{name}.{sheet_name}.{key}: expected number")
                number = float(value)
                if not math.isfinite(number) or (key not in DECIMAL_FIELDS and number != int(number)):
                    raise ValueError(f"{name}.{sheet_name}.{key}: invalid number {value!r}")
                entry[key] = number if key in DECIMAL_FIELDS else int(number)
            entries.append(entry)
        result[sheet_name] = entries
    return result


def activity_settings_rows(data, name, sheet_name):
    return [[row[key] for key in ACTIVITY_SETTINGS_COLUMNS[name][sheet_name]] for row in data[sheet_name]]


def validate_activity_settings(activities, stair_climb, order_supply):
    for name, widget, data in (("stair_climb", "StairClimb", stair_climb), ("order_supply", "OrderSupply", order_supply)):
        expected_ids = {activity["id"] for activity in activities if activity.get("widget") == widget}
        settings = data.get("settings", [])
        ids = [row["activity_id"] for row in settings]
        if len(set(ids)) != len(ids) or set(ids) != expected_ids:
            raise ValueError(f"{name}: settings must match activity IDs {expected_ids}")
        if any(activity.get("config") for activity in activities if activity.get("widget") == widget):
            raise ValueError(f"{name}: move embedded activity config into the dedicated table")
        for row in settings:
            for key in ACTIVITY_SETTINGS_COLUMNS[name]["settings"]:
                value = row.get(key)
                if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or value <= 0:
                    raise ValueError(f"{name}.{key}: expected positive number")
                if key not in DECIMAL_FIELDS and int(value) != value:
                    raise ValueError(f"{name}.{key}: expected integer")
            if name == "stair_climb":
                if row["group_size"] != 20 or row["bot_max_minutes"] < row["bot_min_minutes"]:
                    raise ValueError("stair_climb: invalid group size or bot interval")
        if name == "stair_climb":
            for reward in data.get("rewards", []):
                if reward.get("activity_id") not in expected_ids:
                    raise ValueError("stair_climb.rewards: unknown activity ID")
                if any(isinstance(reward.get(key), bool) or not isinstance(reward.get(key), int)
                       for key in ACTIVITY_SETTINGS_COLUMNS[name]["rewards"]):
                    raise ValueError("stair_climb.rewards: expected integers")
                if not 1 <= reward["min_rank"] <= reward["max_rank"] <= 20 or min(reward["stamina"], reward["spirit_stones"]) < 0:
                    raise ValueError("stair_climb.rewards: invalid rank or reward")
            for activity_id in expected_ids:
                for rank in range(1, 21):
                    matching = [reward for reward in data.get("rewards", []) if reward["activity_id"] == activity_id
                                and reward["min_rank"] <= rank <= reward["max_rank"]]
                    if len(matching) != 1:
                        raise ValueError(f"stair_climb.rewards: rank {rank} must have exactly one reward")


def validate_order_duel(activities, data):
    expected = [a["id"] for a in activities if a.get("widget") == "OrderDuel"]
    settings = data.get("settings", [])
    if len(expected) > 1 or [s["activity_id"] for s in settings] != expected:
        raise ValueError("order_duel: settings must match exactly one activity")
    for row in settings:
        for key in ACTIVITY_SETTINGS_COLUMNS["order_duel"]["settings"]:
            value = row.get(key)
            if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or value < (0 if key == "win_stamina" else 0.000000001):
                raise ValueError(f"order_duel.{key}: invalid value")
            if key not in DECIMAL_FIELDS and int(value) != value:
                raise ValueError(f"order_duel.{key}: expected integer")
        if row["bot_max_seconds"] < row["bot_min_seconds"]:
            raise ValueError("order_duel: invalid bot interval")
    rewards = data.get("rewards", [])
    if len(rewards) != 10 * len(expected):
        raise ValueError("order_duel: exactly ten rewards required")
    previous = 0
    for index, reward in enumerate(rewards):
        if any(isinstance(reward.get(key), bool) or not isinstance(reward.get(key), int)
               for key in ACTIVITY_SETTINGS_COLUMNS["order_duel"]["rewards"]):
            raise ValueError("order_duel.rewards: expected integers")
        if reward["activity_id"] not in expected or reward["tier"] != index + 1 or reward["required_points"] <= previous or min(reward["stamina"], reward["spirit_stones"]) < 0 or reward["stamina"] + reward["spirit_stones"] <= 0:
            raise ValueError("order_duel.rewards: invalid tier, threshold or reward")
        previous = reward["required_points"]
