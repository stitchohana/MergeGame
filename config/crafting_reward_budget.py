"""Budget guaranteed facility rewards by their fully merged result."""

from collections import Counter
from typing import Any, Mapping, Sequence

from facility_reward_validation import iter_reward_items


# Each checkpoint is inclusive: complete that realm's last circulation.
FACILITY_MERGE_CHECKPOINTS = ((10, 4), (13, 8), (16, 12), (19, 16), (20, 16))


def facility_definitions(items: Mapping[str, Any], sections: Sequence[str]) -> dict[int, Mapping[str, Any]]:
    return {int(item["id"]): item for section in sections for item in items.get(section, [])}


def merge_units(item: Mapping[str, Any], definitions: Mapping[int, Any]) -> int:
    definition = definitions.get(int(item.get("id", 0)))
    return int(item.get("count", 1)) * (1 << (int(definition["level"]) - 1)) if definition else 0


def fixed_units(
    definitions: Mapping[int, Any], setup: Mapping[str, Any],
    cultivation: Sequence[Mapping[str, Any]], rewards: Mapping[str, Any],
    through_level: int,
) -> Counter:
    """Include every initial-board copy and breakthrough into this level."""
    totals = Counter()
    sources = list(setup.get("main", {}).get("items", []))
    for stage in cultivation[:through_level - 1]:
        sources.extend(iter_reward_items(stage.get("breakthrough_reward_id"), rewards))
    for item in sources:
        definition = definitions.get(int(item.get("id", 0)))
        if definition:
            totals[int(definition["id"]) // 100] += merge_units(item, definitions)
    return totals


def split_budget(units: int, slots: int, first_level_one: bool) -> list[int]:
    """Split an exact budget into powers of two; keep as many slots as fit."""
    if units < 0:
        raise ValueError("fixed facility rewards already exceed the realm budget")
    if units == 0:
        return []
    pieces = [1] if first_level_one else []
    remainder = units - len(pieces)
    pieces.extend(1 << bit for bit in range(remainder.bit_length()) if remainder & (1 << bit))
    if len(pieces) > slots:
        raise ValueError(f"facility budget {units} requires at least {len(pieces)} slots, got {slots}")
    while len(pieces) < slots and max(pieces) > 1:
        largest = max(pieces)
        pieces.remove(largest)
        pieces.extend((largest // 2, largest // 2))
    return sorted(piece.bit_length() for piece in pieces)


def budget_facility_rewards(
    stages: Sequence[Mapping[str, Any]], items: Mapping[str, Any],
    setup: Mapping[str, Any], cultivation: Sequence[Mapping[str, Any]],
    rewards: Mapping[str, Any],
    sections: Sequence[str] = ("crafting",),
) -> list[dict[str, Any]]:
    """Reassign selected facility slots; retain tutorial and other rewards."""
    definitions = {item_id: item for item_id, item in facility_definitions(items, sections).items() if item_id // 100 != 250}
    all_facility_ids = set(facility_definitions(items, ("launcher", "crafting")))
    ids_by_level = {(item_id // 100, int(item["level"])): item_id for item_id, item in definitions.items()}
    cumulative = Counter()
    report = []
    previous_end = 0
    for end_level, target_level in FACILITY_MERGE_CHECKPOINTS:
        rows = [stage for stage in stages if previous_end < int(stage["cultivation_level"]) <= end_level]
        slots = {}
        tutorial = Counter()
        for stage in rows:
            for index, item in enumerate(stage["circulation_reward"]["items"]):
                item_id = int(item["id"])
                if item_id not in definitions:
                    continue
                family = item_id // 100
                if int(stage["cultivation_level"]) == 1:
                    tutorial[family] += merge_units(item, definitions)
                else:
                    slots.setdefault(family, []).append((stage, index))
        fixed = fixed_units(definitions, setup, cultivation, rewards, end_level)
        families = sorted(set(cumulative) | set(fixed) | set(tutorial) | set(slots))
        # A newly unlocked table needs a level-1 first reward. Its remaining
        # binary budget can require more slots than the old round-robin pool
        # assigned (the late-Foundation array table is one such case).
        minimum_slots = {}
        for family in families:
            prior = cumulative[family] + fixed[family] + tutorial[family]
            remaining = (1 << (target_level - 1)) - prior
            minimum_slots[family] = (
                1 + (remaining - 1).bit_count() if prior == 0 and remaining > 0
                else max(0, remaining).bit_count()
            )
        row_order = {id(stage): index for index, stage in enumerate(rows)}
        for family in families:
            while len(slots.get(family, [])) < minimum_slots[family]:
                family_slots = slots.setdefault(family, [])
                already_available = cumulative[family] + fixed[family] + tutorial[family] > 0
                if not family_slots and not already_available:
                    raise ValueError(f"facility family {family} has no configured unlock slot")
                first_row = min((row_order[id(stage)] for stage, _ in family_slots), default=0)
                spare = next((stage for stage in rows[first_row:]
                              if int(stage["cultivation_level"]) > 1
                              and sum(int(item["id"]) in all_facility_ids for item in stage["circulation_reward"]["items"]) < 2
                              and not any(id(stage) == id(existing) for existing, _ in family_slots)), None)
                if spare is not None:
                    entries = spare["circulation_reward"]["items"]
                    family_slots.append((spare, len(entries)))
                    entries.append({"id": ids_by_level[(family, 1)], "count": 1})
                    continue
                candidates = [
                    (donor, position) for donor, positions in slots.items()
                    if donor != family and len(positions) > minimum_slots[donor]
                    for position in positions[1:]
                    if row_order[id(position[0])] >= first_row
                    and all(id(stage) != id(position[0]) for stage, _ in family_slots)
                ]
                if not candidates:
                    raise ValueError(f"not enough circulation slots for facility family {family}")
                donor, position = max(candidates, key=lambda pair: (len(slots[pair[0]]), row_order[id(pair[1][0])]))
                slots[donor].remove(position)
                slots[family].append(position)
        for positions in slots.values():
            positions.sort(key=lambda position: (row_order[id(position[0])], position[1]))
        replacements = {}
        for family in families:
            prior_units = cumulative[family] + fixed[family] + tutorial[family]
            target_units = 1 << (target_level - 1)
            family_slots = slots.get(family, [])
            levels = split_budget(target_units - prior_units, len(family_slots), prior_units == 0)
            # Keep the first unlock and the final reward, with even spacing.
            selected = [
                index * (len(family_slots) - 1) // (len(levels) - 1) if len(levels) > 1 else 0
                for index in range(len(levels))
            ]
            assigned = dict(zip(selected, levels))
            for ordinal, (stage, index) in enumerate(family_slots):
                level = assigned.get(ordinal)
                replacements[(id(stage), index)] = (
                    {"id": ids_by_level[(family, level)], "count": 1} if level else None
                )
            cumulative[family] += tutorial[family] + sum(1 << (level - 1) for level in levels)
            report.append({
                "through_level": end_level, "family": family, "target_level": target_level,
                "available_slots": len(family_slots), "reward_count": len(levels),
                "reward_levels": levels, "cumulative_units": cumulative[family] + fixed[family],
            })
        for stage in rows:
            stage["circulation_reward"]["items"] = [
                replacement for index, item in enumerate(stage["circulation_reward"]["items"])
                if (replacement := replacements.get((id(stage), index), item)) is not None
            ]
        previous_end = end_level
    return report


def validate_facility_merge_budgets(
    stages: Sequence[Mapping[str, Any]], items: Mapping[str, Any],
    setup: Mapping[str, Any], cultivation: Sequence[Mapping[str, Any]],
    rewards: Mapping[str, Any],
    sections: Sequence[str] = ("launcher", "crafting"),
) -> None:
    """Check every prefix against its realm cap and exact checkpoint totals."""
    # Spirit-stone mines retain their one-level-1-mine breakthrough schedule.
    definitions = {item_id: item for item_id, item in facility_definitions(items, sections).items() if item_id // 100 != 250}
    totals = Counter()
    for stage_index, stage in enumerate(stages):
        level = int(stage["cultivation_level"])
        target_level = next(target for end, target in FACILITY_MERGE_CHECKPOINTS if level <= end)
        fixed = fixed_units(definitions, setup, cultivation, rewards, level)
        for item in iter_reward_items(stage.get("circulation_reward"), rewards):
            item_id = int(item["id"])
            if item_id in definitions:
                totals[item_id // 100] += merge_units(item, definitions)
        for family in set(totals) | set(fixed):
            units = totals[family] + fixed[family]
            if units > 1 << (target_level - 1):
                raise ValueError(f"circulation {stage_index}: facility family {family} exceeds merged level {target_level}")
        is_level_end = stage_index + 1 == len(stages) or int(stages[stage_index + 1]["cultivation_level"]) != level
        if is_level_end and level in dict(FACILITY_MERGE_CHECKPOINTS):
            expected_families = set()
            if "crafting" in sections:
                expected_families.update({170, 180} if level == 10 else {170, 180, 190, 200, 210})
            if "launcher" in sections:
                expected_families.update({110, 120, 130, 150, 160} if level == 10 else {110, 120, 130, 140, 150, 160, 230, 240})
            for family in expected_families:
                if totals[family] + fixed[family] != 1 << (target_level - 1):
                    raise ValueError(f"facility family {family} does not merge to exactly level {target_level} at level {level}")


def budget_crafting_rewards(stages, items, setup, cultivation, rewards):
    return budget_facility_rewards(stages, items, setup, cultivation, rewards, ("crafting",))


def validate_crafting_merge_budgets(stages, items, setup, cultivation, rewards):
    validate_facility_merge_budgets(stages, items, setup, cultivation, rewards, ("crafting",))
