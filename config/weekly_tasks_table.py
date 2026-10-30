"""Current weekly-task schedule, completion points and milestone reward schema."""
import json

WEEKLY_COLUMNS = {
    "weekly_tasks": ["activity_id", "day", "quests", "points_per_task"],
    "milestones": ["activity_id", "stage", "required_points", "rewards"],
}


def validate_weekly_tasks(data):
    activity_ids = set()
    all_quest_ids = set()
    for definition in data["weekly_tasks"]:
        activity_id = definition["activity_id"]
        if not isinstance(activity_id, int) or activity_id <= 0 or activity_id in activity_ids:
            raise ValueError("weekly activity ids must be unique positive integers")
        activity_ids.add(activity_id)
        points = definition["points_per_task"]
        if not isinstance(points, int) or isinstance(points, bool) or points <= 0:
            raise ValueError("weekly points_per_task must be a positive integer")
        days = definition["daily_quests"]
        if len(days) != 7:
            raise ValueError("weekly task schedule requires seven days")
        quest_ids = [qid for day in days for qid in day]
        if len(set(quest_ids)) != len(quest_ids) or all_quest_ids.intersection(quest_ids):
            raise ValueError("weekly task ids must be unique across activities and days")
        if any(not isinstance(qid, int) or qid <= 0 for qid in quest_ids):
            raise ValueError("weekly quest ids must be positive integers")
        all_quest_ids.update(quest_ids)
        previous = 0
        stage_ids = set()
        if not definition["milestones"]:
            raise ValueError("weekly milestones are required")
        for milestone in definition["milestones"]:
            stage = milestone["stage"]
            required = milestone["required_points"]
            if not isinstance(stage, int) or stage <= 0 or stage in stage_ids:
                raise ValueError("weekly milestone stages must be unique positive integers")
            if not isinstance(required, int) or required <= previous or required > points * len(quest_ids):
                raise ValueError("weekly thresholds must increase and remain reachable")
            stage_ids.add(stage)
            previous = required
            rewards = milestone["rewards"]
            if not isinstance(rewards, dict) or not (rewards.get("tokens") or rewards.get("items")):
                raise ValueError("weekly milestone rewards must not be empty")
            for token in rewards.get("tokens", []):
                if token["token"] != 3 or not isinstance(token["amount"], int) or token["amount"] <= 0:
                    raise ValueError("weekly token rewards must grant positive stamina")
            for item in rewards.get("items", []):
                if not isinstance(item["id"], int) or item["id"] <= 0 or not isinstance(item["count"], int) or item["count"] <= 0:
                    raise ValueError("weekly item rewards must be positive integers")


def read_weekly_tasks(workbook):
    def rows(sheet):
        values = list(sheet.values)
        headers = values[0]
        return [dict(zip(headers, row)) for row in values[1:] if any(v is not None for v in row)]

    def integer(value):
        result = int(value)
        if float(value) != result:
            raise ValueError("weekly numeric fields must be integers")
        return result

    definitions = {}
    days = {}
    for row in rows(workbook["weekly_tasks"]):
        aid = integer(row["activity_id"])
        day = integer(row["day"])
        points = integer(row["points_per_task"])
        if aid not in definitions:
            definitions[aid] = {"activity_id": aid, "points_per_task": points, "daily_quests": [], "milestones": []}
            days[aid] = {}
        if definitions[aid]["points_per_task"] != points or day in days[aid] or day not in range(1, 8):
            raise ValueError("weekly day or points_per_task is inconsistent")
        days[aid][day] = [integer(v.strip()) for v in str(row["quests"] or "").split(";") if v.strip()]
    for aid, definition in definitions.items():
        if set(days[aid]) != set(range(1, 8)):
            raise ValueError("weekly schedule must define all seven days")
        definition["daily_quests"] = [days[aid][day] for day in range(1, 8)]
    for row in rows(workbook["milestones"]):
        definition = definitions[integer(row["activity_id"])]
        definition["milestones"].append({"stage": integer(row["stage"]), "required_points": integer(row["required_points"]),
            "rewards": json.loads(row["rewards"])})
    data = {"weekly_tasks": list(definitions.values())}
    validate_weekly_tasks(data)
    return data


def weekly_task_rows(data):
    validate_weekly_tasks(data)
    result = {name: [] for name in WEEKLY_COLUMNS}
    for definition in data["weekly_tasks"]:
        for day, ids in enumerate(definition["daily_quests"], 1):
            result["weekly_tasks"].append([definition["activity_id"], day, ";".join(map(str, ids)), definition["points_per_task"]])
        for milestone in definition["milestones"]:
            result["milestones"].append([definition["activity_id"], milestone["stage"], milestone["required_points"],
                json.dumps(milestone["rewards"], ensure_ascii=False, separators=(",", ":"))])
    return result
