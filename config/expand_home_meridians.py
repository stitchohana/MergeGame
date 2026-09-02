#!/usr/bin/env python3
"""Expand home meridians to 666 staged circulations.

The transformation preserves each cultivation level's total acupoints, qi
cost, EXP budget, circulation stamina, and non-mine facility quantities.  It
adds explicit ``cultivation_level`` ownership, spreads facility units across
the full progression, and moves the level-1 spirit-stone mine to every
breakthrough reward.
"""

import json
import math
from collections import defaultdict
from copy import deepcopy
from pathlib import Path
from typing import Any, Dict, List, Mapping, Sequence, Tuple

from facility_reward_validation import (
    iter_reward_items,
    launcher_family_maps,
    required_launcher_families_by_crafting_class,
    setup_item_ids,
    validate_facility_reward_order,
)
from home_meridian_progression import (
    CIRCULATIONS_BY_LEVEL,
    EARLY_STAGE_ACUPOINT_EXP,
    EARLY_STAGE_NODES_PER_CIRCULATION,
    EARLY_STAGE_QI_COST,
    MINE_ONLY_REWARD_ID,
    SPIRIT_STONE_MINE_ID,
    TOTAL_CIRCULATIONS,
    early_stage_exp,
    validate_home_progression,
)


BASE = Path(__file__).parent
JSON_DIR = BASE / "json_output"
def read_json(name: str) -> Any:
    with open(JSON_DIR / name, encoding="utf-8") as handle:
        return json.load(handle)


def write_json(name: str, data: Any) -> None:
    with open(JSON_DIR / name, "w", encoding="utf-8") as handle:
        json.dump(data, handle, ensure_ascii=False, indent=2)
        handle.write("\n")


def as_int(value: Any, default: int = 0) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def legacy_level_for_stage(stage_index: int) -> int:
    if stage_index <= 9:
        return stage_index + 1
    return 11 + (stage_index - 10) // 10


def group_existing_stages(
    home_stages: Sequence[Mapping[str, Any]],
    cultivation_count: int,
) -> List[List[Mapping[str, Any]]]:
    groups: List[List[Mapping[str, Any]]] = [[] for _ in range(cultivation_count)]
    for stage_index, stage in enumerate(home_stages):
        level = as_int(stage.get("cultivation_level"), legacy_level_for_stage(stage_index))
        if level < 1 or level > cultivation_count:
            raise ValueError(f"home stage {stage_index} has invalid cultivation level {level}")
        groups[level - 1].append(stage)
    missing = [level for level, stages in enumerate(groups, 1) if not stages]
    if missing:
        raise ValueError(f"home config is missing cultivation levels: {missing}")
    return groups


def allocate_split_counts(weights: Sequence[int], target_parts: int) -> List[int]:
    """Allocate positive split counts proportionally without exceeding weights."""
    if target_parts < len(weights) or target_parts > sum(weights):
        raise ValueError(
            f"cannot split weights totaling {sum(weights)} into {target_parts} positive parts"
        )
    raw = [target_parts * weight / sum(weights) for weight in weights]
    result = [max(1, min(weight, math.floor(value))) for weight, value in zip(weights, raw)]
    while sum(result) < target_parts:
        candidates = [
            index for index, weight in enumerate(weights)
            if result[index] < weight
        ]
        index = max(candidates, key=lambda candidate: (raw[candidate] - result[candidate], weights[candidate]))
        result[index] += 1
    while sum(result) > target_parts:
        candidates = [index for index, value in enumerate(result) if value > 1]
        index = min(candidates, key=lambda candidate: (raw[candidate] - result[candidate], weights[candidate]))
        result[index] -= 1
    return result


def split_positive(total: int, parts: int) -> List[int]:
    if parts <= 0 or total < parts:
        raise ValueError(f"cannot split {total} into {parts} positive values")
    base, remainder = divmod(total, parts)
    return [base + (1 if index < remainder else 0) for index in range(parts)]


def distribute_total(total: int, parts: int) -> List[int]:
    """Distribute an integer total evenly, spacing remainder units across rows."""
    if total < 0 or parts <= 0:
        raise ValueError(f"cannot distribute total={total} across parts={parts}")
    base, remainder = divmod(total, parts)
    values = [base] * parts
    if remainder:
        for remainder_index in range(remainder):
            index = min(parts - 1, math.floor((remainder_index + 0.5) * parts / remainder))
            values[index] += 1
    return values


def reward_token_total(stages: Sequence[Mapping[str, Any]], token_id: int) -> int:
    total = 0
    for stage in stages:
        reward = stage.get("circulation_reward", {})
        if not isinstance(reward, Mapping):
            continue
        for token in reward.get("tokens", []) or []:
            if isinstance(token, Mapping) and as_int(token.get("token")) == token_id:
                total += as_int(token.get("amount"))
    return total


def build_expanded_stages(
    grouped_stages: Sequence[Sequence[Mapping[str, Any]]],
    cultivation_stages: Sequence[Mapping[str, Any]],
) -> List[Dict[str, Any]]:
    expanded: List[Dict[str, Any]] = []
    for level, (old_stages, target_count) in enumerate(
        zip(grouped_stages, CIRCULATIONS_BY_LEVEL),
        1,
    ):
        level_stages: List[Dict[str, Any]] = []
        cycle_number = 1
        if level <= len(EARLY_STAGE_NODES_PER_CIRCULATION):
            node_count = EARLY_STAGE_NODES_PER_CIRCULATION[level - 1]
            qi_cost = EARLY_STAGE_QI_COST[level - 1]
            acupoint_exp = EARLY_STAGE_ACUPOINT_EXP[level - 1]
            for _cycle in range(target_count):
                level_stages.append({
                    "cultivation_level": level,
                    "name": f"{cultivation_stages[level - 1]['name']}·周天{cycle_number}",
                    "acupoints": node_count,
                    "qi_cost": qi_cost,
                    "acupoint_exp": acupoint_exp,
                    "circulation_reward": {"tokens": [], "items": []},
                })
                cycle_number += 1
        else:
            weights = [as_int(stage.get("acupoints")) for stage in old_stages]
            split_counts = allocate_split_counts(weights, target_count)
            for old_stage, split_count in zip(old_stages, split_counts):
                for acupoints in split_positive(as_int(old_stage.get("acupoints")), split_count):
                    level_stages.append({
                        "cultivation_level": level,
                        "name": f"{cultivation_stages[level - 1]['name']}·周天{cycle_number}",
                        "acupoints": acupoints,
                        "qi_cost": as_int(old_stage.get("qi_cost")),
                        "acupoint_exp": as_int(old_stage.get("acupoint_exp")),
                        "circulation_reward": {"tokens": [], "items": []},
                    })
                    cycle_number += 1

        acupoint_exp_total = sum(
            stage["acupoints"] * stage["acupoint_exp"]
            for stage in level_stages
        )
        if level <= len(EARLY_STAGE_NODES_PER_CIRCULATION):
            target_exp = early_stage_exp(level, target_count)
            cultivation_stages[level - 1]["exp"] = target_exp
        else:
            target_exp = as_int(cultivation_stages[level - 1].get("exp"))
        circulation_exp = target_exp - acupoint_exp_total
        if circulation_exp < 0:
            raise ValueError(
                f"cultivation level {level} acupoints already grant {acupoint_exp_total} EXP, "
                f"above target {target_exp}"
            )

        token_totals: Dict[int, int] = defaultdict(int)
        for old_stage in old_stages:
            reward = old_stage.get("circulation_reward", {})
            if not isinstance(reward, Mapping):
                continue
            for token in reward.get("tokens", []) or []:
                if not isinstance(token, Mapping):
                    continue
                token_id = as_int(token.get("token"))
                if token_id not in (3, 4):
                    token_totals[token_id] += as_int(token.get("amount"))
        token_totals[4] = circulation_exp
        token_totals[3] = reward_token_total(old_stages, 3)

        distributed_tokens = {
            token_id: distribute_total(amount, len(level_stages))
            for token_id, amount in token_totals.items()
            if amount > 0
        }
        for stage_index, stage in enumerate(level_stages):
            tokens = []
            for token_id in [4, 3, *sorted(token for token in distributed_tokens if token not in (3, 4))]:
                amounts = distributed_tokens.get(token_id)
                if amounts is not None and amounts[stage_index] > 0:
                    tokens.append({"token": token_id, "amount": amounts[stage_index]})
            stage["circulation_reward"]["tokens"] = tokens
        expanded.extend(level_stages)
    return expanded


def collect_facility_units(home_stages: Sequence[Mapping[str, Any]]) -> Tuple[List[Dict[str, int]], int]:
    units: List[Dict[str, int]] = []
    removed_mines = 0
    for stage in home_stages:
        reward = stage.get("circulation_reward", {})
        if not isinstance(reward, Mapping):
            continue
        for item in reward.get("items", []) or []:
            if not isinstance(item, Mapping):
                continue
            item_id = as_int(item.get("id"))
            count = as_int(item.get("count"), 1)
            if item_id == SPIRIT_STONE_MINE_ID:
                removed_mines += count
                continue
            units.extend({"id": item_id, "count": 1} for _ in range(count))
    return units, removed_mines


def facility_level_map(items: Mapping[str, Any]) -> Dict[Tuple[int, int], int]:
    """Return the configured facility ID for each family/merge level."""
    result: Dict[Tuple[int, int], int] = {}
    for section in ("launcher", "crafting"):
        for item in items.get(section, []) or []:
            if not isinstance(item, Mapping):
                continue
            item_id = as_int(item.get("id"))
            level = as_int(item.get("level"))
            if item_id <= 0 or level <= 0 or item_id // 100 == SPIRIT_STONE_MINE_ID // 100:
                continue
            result[(item_id // 100, level)] = item_id
    return result


def facility_reward_schedule(
    expanded_stages: Sequence[Mapping[str, Any]],
    items: Mapping[str, Any],
) -> List[List[Dict[str, int]]]:
    """Build two facility rewards per circulation with realm-based level caps.

    The first pass through the families is launcher-first so every crafting
    table is preceded by all of its launcher dependencies.  Within each
    broad cultivation realm, each family ramps from the previous realm's
    starting level to that realm's cap.  This gives all 13 families level-16
    rewards by the Nascent Soul realm while keeping early rewards modest.
    """
    levels = facility_level_map(items)
    families = sorted({family for family, _level in levels if family != SPIRIT_STONE_MINE_ID // 100})
    if len(families) != 13:
        raise ValueError(f"expected 13 non-mine facility families, got {families}")
    for family in families:
        for level in range(1, 17):
            if (family, level) not in levels:
                raise ValueError(f"facility family {family} is missing level {level}")

    def realm(level: int) -> Tuple[str, int, int]:
        if level <= 1:
            return "mortal", 1, 1
        if level <= 10:
            return "qi", 1, 4
        if level <= 13:
            return "foundation", 5, 8
        if level <= 16:
            return "gold", 9, 12
        return "nascent", 13, 16

    # Keep launchers ahead of crafting tables on the first pass.  The family
    # IDs are naturally ordered as launcher families (11x..16x, 23x, 24x)
    # followed by crafting-table families (17x..21x).
    launcher_families = sorted({as_int(item.get("id")) // 100
                                for item in items.get("launcher", []) or []
                                if isinstance(item, Mapping)
                                and as_int(item.get("id")) // 100 != SPIRIT_STONE_MINE_ID // 100})
    crafting_families = sorted(set(families) - set(launcher_families))
    family_order = launcher_families + crafting_families
    if family_order != families:
        # The validator is authoritative, but this guard makes an accidental
        # family classification change visible in the generator output.
        if set(family_order) != set(families):
            raise ValueError(f"facility family order is incomplete: {family_order}")

    slots = len(expanded_stages) * 2
    phase_slots: Dict[str, Dict[int, int]] = defaultdict(lambda: defaultdict(int))
    phase_totals: Dict[str, int] = defaultdict(int)
    for stage in expanded_stages:
        phase, _start, _cap = realm(as_int(stage.get("cultivation_level")))
        phase_totals[phase] += 2
    phase_occurrences: Dict[str, Dict[int, int]] = defaultdict(lambda: defaultdict(int))
    for slot_index in range(slots):
        stage = expanded_stages[slot_index // 2]
        phase, _start, _cap = realm(as_int(stage.get("cultivation_level")))
        family = family_order[slot_index % len(family_order)]
        phase_slots[phase][family] += 1

    schedule: List[List[Dict[str, int]]] = []
    for slot_index in range(slots):
        stage = expanded_stages[slot_index // 2]
        phase, start, cap = realm(as_int(stage.get("cultivation_level")))
        family = family_order[slot_index % len(family_order)]
        ordinal = phase_occurrences[phase][family]
        phase_occurrences[phase][family] += 1
        family_total = phase_slots[phase][family]
        if family_total <= 1:
            reward_level = cap
        else:
            reward_level = start + math.floor(
                ordinal * (cap - start) / (family_total - 1)
            )
        reward = {"id": levels[(family, reward_level)], "count": 1}
        if slot_index % 2 == 0:
            schedule.append([reward])
        else:
            schedule[-1].append(reward)

    if len(schedule) != len(expanded_stages) or any(len(row) != 2 for row in schedule):
        raise ValueError("facility schedule must contain exactly two rewards per circulation")
    return schedule


def expand_facility_units(
    source_units: Sequence[Mapping[str, Any]],
    target_count: int,
) -> List[Dict[str, int]]:
    """Expand facilities proportionally while preserving their progression order."""
    if not source_units:
        raise ValueError("home config has no facility rewards to expand")
    if target_count < len(source_units):
        raise ValueError(
            f"cannot preserve {len(source_units)} facility units in only {target_count} circulations"
        )
    expanded: List[Dict[str, int]] = []
    previous_boundary = 0
    for index, source in enumerate(source_units):
        boundary = math.floor((index + 1) * target_count / len(source_units))
        repeat_count = boundary - previous_boundary
        expanded.extend(
            {"id": as_int(source.get("id")), "count": 1}
            for _ in range(repeat_count)
        )
        previous_boundary = boundary
    if len(expanded) != target_count:
        raise ValueError(
            f"facility expansion produced {len(expanded)} units, expected {target_count}"
        )
    return expanded


def ensure_breakthrough_mines(
    cultivation_stages: List[Dict[str, Any]],
    rewards: Dict[str, Any],
    items: Mapping[str, Any],
) -> None:
    reward_table = rewards.setdefault("rewards", {})
    facility_ids = {
        as_int(item.get("id"))
        for section in ("launcher", "crafting")
        for item in items.get(section, []) or []
        if isinstance(item, Mapping)
        and as_int(item.get("id")) > 0
    }
    reward_table[str(MINE_ONLY_REWARD_ID)] = {
        "items": [{"id": SPIRIT_STONE_MINE_ID, "count": 1}],
    }
    for level, stage in enumerate(cultivation_stages[:-1], 1):
        reward_id = as_int(stage.get("breakthrough_reward_id"))
        if reward_id <= 0:
            reward_id = MINE_ONLY_REWARD_ID
            stage["breakthrough_reward_id"] = reward_id
        reward = reward_table.setdefault(str(reward_id), {})
        configured_items = [
            deepcopy(item)
            for item in reward.get("items", []) or []
            if as_int(item.get("id")) not in facility_ids
            and as_int(item.get("id")) != SPIRIT_STONE_MINE_ID
        ]
        configured_items.append({"id": SPIRIT_STONE_MINE_ID, "count": 1})
        reward["items"] = configured_items


def even_positions(total_slots: int, item_count: int) -> List[int]:
    if item_count <= 0:
        return []
    positions = [
        round((index + 1) * (total_slots + 1) / (item_count + 1)) - 1
        for index in range(item_count)
    ]
    for index in range(1, len(positions)):
        positions[index] = max(positions[index], positions[index - 1] + 1)
    if positions[-1] >= total_slots:
        shift = positions[-1] - total_slots + 1
        positions = [position - shift for position in positions]
    if positions[0] < 0 or len(set(positions)) != len(positions):
        raise ValueError("could not create unique facility reward positions")
    return positions


def reorder_units_for_dependencies(
    units: List[Dict[str, int]],
    positions: Sequence[int],
    expanded_stages: Sequence[Mapping[str, Any]],
    items: Mapping[str, Any],
    recipes: Sequence[Mapping[str, Any]],
    setup: Mapping[str, Any],
    cultivation_stages: Sequence[Mapping[str, Any]],
    reward_table: Mapping[str, Any],
) -> int:
    launcher_ids, _ = launcher_family_maps(items)
    crafting_ids = {
        as_int(table.get("id"))
        for table in items.get("crafting", []) or []
        if isinstance(table, Mapping)
    }
    requirements = required_launcher_families_by_crafting_class(items, recipes)
    initial_ids = setup_item_ids(setup)
    level_end_positions: Dict[int, int] = {}
    for position, stage in enumerate(expanded_stages):
        level_end_positions[as_int(stage.get("cultivation_level"))] = position

    def first_dependency_issue() -> Tuple[int, int, str] | None:
        granted_families = {
            item_id // 100 for item_id in initial_ids if item_id in launcher_ids
        }
        granted_tables = initial_ids.intersection(crafting_ids)
        unit_index_by_position = {position: index for index, position in enumerate(positions)}

        def check_table(item_id: int, allowed_index: int, label: str) -> Tuple[int, int, str] | None:
            if item_id not in crafting_ids or item_id in granted_tables:
                return None
            missing = sorted(requirements.get(item_id // 100, set()) - granted_families)
            if missing:
                return allowed_index, missing[0], label
            return None

        def grant(item_id: int) -> None:
            if item_id in launcher_ids:
                granted_families.add(item_id // 100)
            if item_id in crafting_ids:
                granted_tables.add(item_id)

        for level in range(1, len(cultivation_stages) + 1):
            level_start = 0 if level == 1 else level_end_positions[level - 1] + 1
            level_end = level_end_positions[level]
            for position in range(level_start, level_end + 1):
                unit_index = unit_index_by_position.get(position)
                if unit_index is None:
                    continue
                item_id = as_int(units[unit_index].get("id"))
                issue = check_table(item_id, unit_index - 1, f"home position {position}")
                if issue is not None:
                    return issue
                grant(item_id)

            if level >= len(cultivation_stages):
                continue
            reward_id = as_int(cultivation_stages[level - 1].get("breakthrough_reward_id"))
            breakthrough_items = list(iter_reward_items(reward_id, reward_table)) if reward_id else []
            allowed_index = sum(1 for position in positions if position <= level_end) - 1
            for item in breakthrough_items:
                item_id = as_int(item.get("id"))
                issue = check_table(item_id, allowed_index, f"breakthrough level {level}")
                if issue is not None:
                    return issue
            for item in breakthrough_items:
                grant(as_int(item.get("id")))
        return None

    moved = 0
    for _attempt in range(len(units) * 4):
        issue = first_dependency_issue()
        if issue is None:
            return moved
        allowed_index, missing_family, label = issue
        if allowed_index < 0:
            raise ValueError(f"{label} needs launcher family {missing_family}xx before the first facility slot")
        source_index = next(
            (
                index for index in range(allowed_index + 1, len(units))
                if as_int(units[index].get("id")) in launcher_ids
                and as_int(units[index].get("id")) // 100 == missing_family
            ),
            None,
        )
        if source_index is None:
            raise ValueError(f"{label} needs launcher family {missing_family}xx, but no future reward provides it")
        source = units.pop(source_index)
        units.insert(allowed_index, source)
        moved += 1
    raise ValueError("facility dependency ordering did not converge")


def main() -> None:
    if sum(CIRCULATIONS_BY_LEVEL) != TOTAL_CIRCULATIONS:
        raise ValueError("configured circulation counts do not total 666")
    if any(
        CIRCULATIONS_BY_LEVEL[index] >= CIRCULATIONS_BY_LEVEL[index + 1]
        for index in range(len(CIRCULATIONS_BY_LEVEL) - 1)
    ):
        raise ValueError("circulation counts must strictly increase by cultivation level")

    home = read_json("home_meridians.json")
    cultivation = read_json("cultivation.json")
    rewards = read_json("rewards.json")
    items = read_json("items.json")
    recipes = read_json("recipes.json")["recipes"]
    setup = read_json("initial_setup.json")

    cultivation_stages: List[Dict[str, Any]] = cultivation["stages"]
    if len(cultivation_stages) != len(CIRCULATIONS_BY_LEVEL):
        raise ValueError(
            f"expected {len(CIRCULATIONS_BY_LEVEL)} cultivation stages, got {len(cultivation_stages)}"
        )
    grouped = group_existing_stages(home["stages"], len(cultivation_stages))
    ensure_breakthrough_mines(cultivation_stages, rewards, items)
    expanded_stages = build_expanded_stages(grouped, cultivation_stages)
    facility_schedule = facility_reward_schedule(expanded_stages, items)
    for stage, facilities in zip(expanded_stages, facility_schedule):
        stage["circulation_reward"]["items"] = facilities

    validate_facility_reward_order(
        expanded_stages,
        items,
        recipes,
        setup,
        rewards["rewards"],
        cultivation_stages,
    )
    validate_home_progression(
        expanded_stages,
        cultivation_stages,
        rewards["rewards"],
        items,
    )
    home["stages"] = expanded_stages
    write_json("home_meridians.json", home)
    write_json("cultivation.json", cultivation)
    write_json("rewards.json", rewards)

    print(json.dumps({
        "total_circulations": len(expanded_stages),
        "circulations_by_level": CIRCULATIONS_BY_LEVEL,
        "facility_units": len(expanded_stages) * 2,
        "facility_families": 13,
        "breakthroughs_with_mine": len(cultivation_stages) - 1,
    }, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
