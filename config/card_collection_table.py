"""Shared schema for the card collection Excel/JSON round trip."""
import json

CARD_COLLECTION_COLUMNS = {
    "collections": ["collection_id", "activity_id", "name", "duplicate_points_by_star", "exchange_pack_id", "exchange_cost"],
    "card_sets": ["set_id", "collection_id", "name", "rewards"],
    "cards": ["card_id", "set_id", "name", "star", "icon"],
    "packs": ["pack_id", "collection_id", "name", "star", "icon", "card_count", "normal_weights"],
    "source_rewards": ["collection_id", "source_type", "source_id", "min_value", "pack_id", "count", "enabled"],
}
INTEGER_FIELDS = {"collection_id", "activity_id", "set_id", "card_id", "star", "pack_id", "card_count", "source_id", "min_value", "count", "exchange_pack_id", "exchange_cost"}
JSON_FIELDS = {"rewards", "normal_weights", "duplicate_points_by_star"}


def read_card_collection(workbook):
    result = {}
    for name, columns in CARD_COLLECTION_COLUMNS.items():
        sheet = workbook[name]
        headers = [cell.value for cell in sheet[1]]
        if any(column not in headers for column in columns):
            raise ValueError(f"{name}: missing columns")
        entries = []
        for row in sheet.iter_rows(min_row=2, values_only=True):
            if all(value is None for value in row):
                continue
            source = dict(zip(headers, row))
            entry = {}
            for key in columns:
                value = source.get(key)
                if key == "source_id" and (value is None or value == ""):
                    continue
                if key in INTEGER_FIELDS:
                    if value is None or value == "" or float(value) != int(float(value)):
                        raise ValueError(f"{name}.{key}: expected integer, got {value!r}")
                    entry[key] = int(float(value))
                elif key in JSON_FIELDS:
                    entry[key] = json.loads(str(value))
                elif key == "enabled":
                    if str(value).lower() not in ("true", "false", "1", "0"):
                        raise ValueError(f"{name}.enabled: expected boolean")
                    entry[key] = str(value).lower() in ("true", "1")
                else:
                    entry[key] = str(value) if value is not None else ""
            entries.append(entry)
        result[name] = entries
    return result


def card_collection_rows(data, name):
    return [[json.dumps(row[key], ensure_ascii=False, separators=(",", ":"))
             if key in JSON_FIELDS else row.get(key, "")
             for key in CARD_COLLECTION_COLUMNS[name]] for row in data[name]]
