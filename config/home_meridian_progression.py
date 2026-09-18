"""Shared progression rules for the 666 home-meridian circulations."""

from collections import Counter
from typing import Any, Mapping, Sequence


TOTAL_CIRCULATIONS = 666
CIRCULATIONS_BY_LEVEL = [3, 6, 10, 13, 16, 19, 22, 25, 29, 32, 35, 38, 41, 44, 48, 51, 54, 57, 60, 63]
SPIRIT_STONE_MINE_ID = 25001
MINE_ONLY_REWARD_ID = 313
MINE_FAMILY = SPIRIT_STONE_MINE_ID // 100

# The initial ten cultivation levels keep four nodes per circulation. The
# tutorial (凡人) uses 5 qi per node so its three circulations cost 60 qi,
# closely matching the 65 qi produced by the seven fixed onboarding orders.
# Later levels are derived from current order values so a maximum order fills
# about half of one circulation after order rewards switch to 1:1 value-to-qi.
# Index 0 is 凡人; indexes 1-9 are the 练气 levels.
EARLY_STAGE_NODES_PER_CIRCULATION = [4, 4, 4, 4, 4, 4, 4, 4, 4, 4]
EARLY_STAGE_QI_COST = [5, 126, 210, 262, 315, 377, 440, 440, 587, 587]
# EXP formerly granted one node at a time is now included in the completed
# circulation reward. Keep the per-circulation budget here for balance checks.
EARLY_STAGE_EXP_PER_CIRCULATION = [4, 8, 8, 8, 8, 12, 12, 12, 12, 12]


def _as_int(value: Any, default: int = 0) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def reward_token_amount(
    reward_config: Any,
    token_id: int,
    rewards: Mapping[str, Any] | None = None,
) -> int:
    if isinstance(reward_config, int) and rewards is not None:
        reward_config = rewards.get(str(reward_config), {})
    if not isinstance(reward_config, Mapping):
        return 0
    return sum(
        _as_int(token.get("amount"))
        for token in reward_config.get("tokens", []) or []
        if isinstance(token, Mapping) and _as_int(token.get("token")) == token_id
    )


def facility_level_cap(cultivation_level: int) -> int:
    """Maximum facility reward level allowed in a cultivation realm."""
    if cultivation_level <= 1:
        return 1
    if cultivation_level <= 10:
        return 4
    if cultivation_level <= 13:
        return 8
    if cultivation_level <= 16:
        return 12
    return 16


def early_stage_exp(cultivation_level: int, circulation_count: int) -> int:
    """Return the reduced EXP budget for 凡人/练气 levels."""
    index = cultivation_level - 1
    if index < 0 or index >= len(EARLY_STAGE_NODES_PER_CIRCULATION):
        raise ValueError(f"not an early cultivation level: {cultivation_level}")
    return (
        circulation_count
        * EARLY_STAGE_EXP_PER_CIRCULATION[index]
    )


def validate_facility_reward_schedule(
    home_stages: Sequence[Mapping[str, Any]],
    items: Mapping[str, Any],
) -> None:
    """Validate reward levels and family coverage for the 666-stage schedule."""
    levels_by_id = {}
    families = set()
    for section in ("launcher", "crafting"):
        for item in items.get(section, []) or []:
            if not isinstance(item, Mapping):
                continue
            item_id = _as_int(item.get("id"))
            level = _as_int(item.get("level"))
            if item_id <= 0 or level <= 0 or item_id // 100 == MINE_FAMILY:
                continue
            levels_by_id[item_id] = level
            families.add(item_id // 100)
    if len(families) != 13:
        raise ValueError(f"expected 13 non-mine facility families, got {sorted(families)}")

    family_by_realm = {"qi": set(), "foundation": set(), "gold": set(), "nascent": set()}
    level16_families = set()
    for stage_index, stage in enumerate(home_stages):
        cultivation_level = _as_int(stage.get("cultivation_level"))
        realm = (
            "qi" if 2 <= cultivation_level <= 10 else
            "foundation" if 11 <= cultivation_level <= 13 else
            "gold" if 14 <= cultivation_level <= 16 else
            "nascent" if cultivation_level >= 17 else None
        )
        reward_config = stage.get("circulation_reward")
        if isinstance(reward_config, int):
            continue
        reward_items = reward_config.get("items", []) if isinstance(reward_config, Mapping) else []
        for item in reward_items:
            item_id = _as_int(item.get("id")) if isinstance(item, Mapping) else 0
            facility_level = levels_by_id.get(item_id)
            if facility_level is None:
                continue
            if facility_level > facility_level_cap(cultivation_level):
                raise ValueError(
                    f"home circulation {stage_index} grants facility {item_id} level {facility_level}, "
                    f"above cultivation level {cultivation_level} cap {facility_level_cap(cultivation_level)}"
                )
            if realm in family_by_realm:
                family_by_realm[realm].add(item_id // 100)
            if cultivation_level >= 17 and facility_level == 16:
                level16_families.add(item_id // 100)

    missing_qi = sorted(families - family_by_realm["qi"])
    if missing_qi:
        raise ValueError(f"练气期未覆盖设施族群: {missing_qi}")
    missing_foundation = sorted(families - family_by_realm["foundation"])
    if missing_foundation:
        raise ValueError(f"筑基期未覆盖设施族群: {missing_foundation}")
    missing_level16 = sorted(families - level16_families)
    if missing_level16:
        raise ValueError(f"元婴期未发放16级设施: {missing_level16}")


def validate_home_progression(
    home_stages: Sequence[Mapping[str, Any]],
    cultivation_stages: Sequence[Mapping[str, Any]],
    rewards: Mapping[str, Any] | None = None,
    items: Mapping[str, Any] | None = None,
) -> None:
    if len(cultivation_stages) != len(CIRCULATIONS_BY_LEVEL):
        raise ValueError(
            f"expected {len(CIRCULATIONS_BY_LEVEL)} cultivation stages, got {len(cultivation_stages)}"
        )
    if len(home_stages) != TOTAL_CIRCULATIONS:
        raise ValueError(
            f"home meridians must contain {TOTAL_CIRCULATIONS} circulations, got {len(home_stages)}"
        )

    counts = Counter()
    previous_level = 0
    exp_by_level = Counter()
    for stage_index, stage in enumerate(home_stages):
        level = _as_int(stage.get("cultivation_level"))
        if level < 1 or level > len(cultivation_stages):
            raise ValueError(f"home circulation {stage_index} has invalid cultivation_level {level}")
        if level < previous_level:
            raise ValueError(
                f"home circulation {stage_index} level {level} appears after level {previous_level}"
            )
        previous_level = level
        acupoints = _as_int(stage.get("acupoints"))
        if acupoints <= 0:
            raise ValueError(f"home circulation {stage_index} must have at least one acupoint")
        if "acupoint_exp" in stage:
            raise ValueError(
                f"home circulation {stage_index} must not configure acupoint_exp"
            )
        counts[level] += 1
        exp_by_level[level] += reward_token_amount(
            stage.get("circulation_reward"),
            4,
            rewards,
        )
        reward_config = stage.get("circulation_reward")
        if isinstance(reward_config, int) and rewards is not None:
            reward_config = rewards.get(str(reward_config), {})
        reward_items = reward_config.get("items", []) if isinstance(reward_config, Mapping) else []
        mortal_facility_counts = (1, 0, 2)
        expected_facility_count = (
            mortal_facility_counts[counts[level] - 1]
            if level == 1
            else 2
        )
        if not isinstance(reward_items, list) or len(reward_items) != expected_facility_count:
            raise ValueError(
                f"home circulation {stage_index} must grant exactly "
                f"{expected_facility_count} facilities, got {reward_items}"
            )
        for facility in reward_items:
            facility_id = _as_int(facility.get("id")) if isinstance(facility, Mapping) else 0
            facility_count = _as_int(facility.get("count"), 1) if isinstance(facility, Mapping) else 0
            if facility_id == SPIRIT_STONE_MINE_ID:
                raise ValueError(
                    f"home circulation {stage_index} must not grant spirit-stone mine {SPIRIT_STONE_MINE_ID}"
                )
            if facility_id <= 0 or facility_count != 1:
                raise ValueError(
                    f"home circulation {stage_index} has invalid facility reward {facility}"
                )

    actual_counts = [counts[level] for level in range(1, len(cultivation_stages) + 1)]
    if actual_counts != CIRCULATIONS_BY_LEVEL:
        raise ValueError(
            f"home circulation distribution must be {CIRCULATIONS_BY_LEVEL}, got {actual_counts}"
        )
    if any(actual_counts[index] >= actual_counts[index + 1] for index in range(len(actual_counts) - 1)):
        raise ValueError("home circulation counts must strictly increase by cultivation level")

    for level, cultivation_stage in enumerate(cultivation_stages, 1):
        expected_exp = _as_int(cultivation_stage.get("exp"))
        if exp_by_level[level] != expected_exp:
            raise ValueError(
                f"home circulations at cultivation level {level} grant {exp_by_level[level]} EXP, "
                f"but cultivation requires {expected_exp}"
            )
    if items is not None:
        validate_facility_reward_schedule(home_stages, items)

    for level in range(1, min(10, len(cultivation_stages)) + 1):
        expected_exp = early_stage_exp(level, CIRCULATIONS_BY_LEVEL[level - 1])
        if _as_int(cultivation_stages[level - 1].get("exp")) != expected_exp:
            raise ValueError(
                f"early cultivation level {level} EXP must be {expected_exp} after balance adjustment"
            )
        level_rows = [
            stage for stage in home_stages
            if _as_int(stage.get("cultivation_level")) == level
        ]
        expected_nodes = EARLY_STAGE_NODES_PER_CIRCULATION[level - 1]
        expected_cost = EARLY_STAGE_QI_COST[level - 1]
        expected_cycle_exp = EARLY_STAGE_EXP_PER_CIRCULATION[level - 1]
        for stage in level_rows:
            if _as_int(stage.get("acupoints")) != expected_nodes:
                raise ValueError(
                    f"early cultivation level {level} must use {expected_nodes} nodes per circulation"
                )
            if _as_int(stage.get("qi_cost")) != expected_cost:
                raise ValueError(
                    f"early cultivation level {level} must use qi_cost {expected_cost}"
                )
            if reward_token_amount(stage.get("circulation_reward"), 4) != expected_cycle_exp:
                raise ValueError(
                    f"early cultivation level {level} must grant {expected_cycle_exp} EXP per circulation"
                )
