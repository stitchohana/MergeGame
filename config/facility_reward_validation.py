"""Dependency helpers for staged home-meridian facility rewards.

The home-meridian workbook contains both launcher and crafting-table rewards.
Crafting tables expose every recipe assigned to their table family, so a table
must not be granted until every launcher family used by those recipes has
already been granted (or is present on the initial board).
"""

from collections import defaultdict
from typing import Any, Dict, Iterable, List, Mapping, Sequence, Set


def _as_int(value: Any) -> int | None:
    """Convert JSON/XLSX scalar values to an integer when possible."""
    if value is None or value == "":
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _item_id(item: Any) -> int | None:
    if isinstance(item, Mapping):
        return _as_int(item.get("id"))
    return _as_int(item)


def iter_reward_items(
    reward_config: Any,
    rewards: Mapping[str, Any] | None = None,
) -> Iterable[Mapping[str, Any]]:
    """Yield item reward entries from an inline or referenced reward config."""
    resolved = reward_config
    reward_id = _as_int(reward_config)
    if reward_id is not None and rewards is not None:
        resolved = rewards.get(str(reward_id), {})

    if isinstance(resolved, Mapping):
        configs: Sequence[Any] = [resolved]
    elif isinstance(resolved, list):
        configs = resolved
    else:
        configs = []

    for config in configs:
        if not isinstance(config, Mapping):
            continue
        items = config.get("items", [])
        if not isinstance(items, list):
            continue
        for item in items:
            if isinstance(item, Mapping):
                yield item


def setup_item_ids(initial_setup: Mapping[str, Any] | None) -> Set[int]:
    """Return all item IDs placed on the initial board."""
    result: Set[int] = set()
    if not isinstance(initial_setup, Mapping):
        return result
    for section in initial_setup.values():
        if not isinstance(section, Mapping):
            continue
        items = section.get("items", [])
        if not isinstance(items, list):
            continue
        for item in items:
            item_id = _item_id(item)
            if item_id is not None:
                result.add(item_id)
    return result


def launcher_family_maps(items: Mapping[str, Any]) -> tuple[Set[int], Dict[int, Set[int]]]:
    """Build launcher IDs and item-to-launcher-family mappings.

    Launcher family IDs are the first three digits (for example, 230 for
    ``23001``).  A launcher maps to every regular-item merge group represented
    by one of its direct spawn outputs.  Direct output IDs are also mapped so
    that special outputs without a group (such as the spirit-stone effect) are
    retained.
    """
    regular = [item for item in items.get("regular", []) if isinstance(item, Mapping)]
    launchers = [item for item in items.get("launcher", []) if isinstance(item, Mapping)]
    regular_by_id = {
        item_id: item
        for item in regular
        if (item_id := _item_id(item)) is not None
    }
    launcher_ids = {
        item_id
        for item in launchers
        if (item_id := _item_id(item)) is not None
    }

    families_by_group: Dict[int, Set[int]] = defaultdict(set)
    families_by_item: Dict[int, Set[int]] = defaultdict(set)
    for launcher in launchers:
        launcher_id = _item_id(launcher)
        if launcher_id is None:
            continue
        family = launcher_id // 100
        outputs: List[int] = []
        for spawn in launcher.get("spawns", []) or []:
            spawn_id = _item_id(spawn)
            if spawn_id is not None:
                outputs.append(spawn_id)
        for spawn_id in launcher.get("fixed_spawns", []) or []:
            parsed_id = _as_int(spawn_id)
            if parsed_id is not None:
                outputs.append(parsed_id)
        for output_id in outputs:
            families_by_item[output_id].add(family)
            output = regular_by_id.get(output_id)
            group_id = _as_int(output.get("group_id")) if output else None
            if group_id is not None:
                families_by_group[group_id].add(family)

    for item in regular:
        item_id = _item_id(item)
        group_id = _as_int(item.get("group_id"))
        if item_id is not None and group_id is not None:
            families_by_item[item_id].update(families_by_group.get(group_id, set()))
    for launcher_id in launcher_ids:
        families_by_item[launcher_id].add(launcher_id // 100)

    return launcher_ids, dict(families_by_item)


def required_launcher_families_by_crafting_class(
    items: Mapping[str, Any],
    recipes: Sequence[Mapping[str, Any]],
) -> Dict[int, Set[int]]:
    """Return launcher-family dependencies for each crafting-table class."""
    _, families_by_item = launcher_family_maps(items)
    recipes_by_id = {
        recipe_id: recipe
        for recipe in recipes
        if isinstance(recipe, Mapping)
        and (recipe_id := _as_int(recipe.get("id"))) is not None
    }
    recipes_by_result: Dict[int, List[Mapping[str, Any]]] = defaultdict(list)
    for recipe in recipes_by_id.values():
        result_id = _as_int(recipe.get("result"))
        if result_id is not None:
            recipes_by_result[result_id].append(recipe)

    cache: Dict[int, Set[int]] = {}

    def dependency_families(item_id: int, visiting: Set[int] | None = None) -> Set[int]:
        if item_id in cache:
            return set(cache[item_id])
        visiting = set() if visiting is None else visiting
        if item_id in visiting:
            return set(families_by_item.get(item_id, set()))
        next_visiting = set(visiting)
        next_visiting.add(item_id)
        result = set(families_by_item.get(item_id, set()))
        for recipe in recipes_by_result.get(item_id, []):
            for ingredient in recipe.get("ingredients", []) or []:
                ingredient_id = _as_int(ingredient)
                if ingredient_id is not None:
                    result.update(dependency_families(ingredient_id, next_visiting))
        cache[item_id] = set(result)
        return result

    requirements: Dict[int, Set[int]] = defaultdict(set)
    for table in items.get("crafting", []) or []:
        table_id = _item_id(table)
        if table_id is None or not isinstance(table, Mapping):
            continue
        table_class = table_id // 100
        for recipe_id in table.get("recipes", []) or []:
            parsed_recipe_id = _as_int(recipe_id)
            recipe = recipes_by_id.get(parsed_recipe_id) if parsed_recipe_id is not None else None
            if recipe is None:
                continue
            for ingredient in recipe.get("ingredients", []) or []:
                ingredient_id = _as_int(ingredient)
                if ingredient_id is not None:
                    requirements[table_class].update(dependency_families(ingredient_id))
    return dict(requirements)


def first_launcher_family_stages(
    home_stages: Sequence[Mapping[str, Any]],
    items: Mapping[str, Any],
    initial_setup: Mapping[str, Any] | None,
    rewards: Mapping[str, Any] | None = None,
) -> Dict[int, int]:
    """Return the first stage index that grants each launcher family.

    A family present on the initial board is represented by ``-1``.  Stages
    use zero-based indexes, matching the order in ``home_meridians.json``.
    """
    launcher_ids, _ = launcher_family_maps(items)
    first_stage: Dict[int, int] = {}
    for item_id in setup_item_ids(initial_setup):
        if item_id in launcher_ids:
            first_stage.setdefault(item_id // 100, -1)
    for stage_index, stage in enumerate(home_stages):
        for item in iter_reward_items(stage.get("circulation_reward"), rewards):
            item_id = _item_id(item)
            if item_id in launcher_ids:
                first_stage.setdefault(item_id // 100, stage_index)
    return first_stage


def validate_facility_reward_order(
    home_stages: Sequence[Mapping[str, Any]],
    items: Mapping[str, Any],
    recipes: Sequence[Mapping[str, Any]],
    initial_setup: Mapping[str, Any] | None,
    rewards: Mapping[str, Any] | None = None,
    cultivation_stages: Sequence[Mapping[str, Any]] | None = None,
) -> None:
    """Raise ``ValueError`` when a table precedes a required launcher family.

    Home stages are processed in cultivation order.  Before the first home
    stage of level N, the configured breakthrough reward of level N-1 is
    applied, matching the server's progression flow.  Rewards inside one home
    circulation or one breakthrough bundle remain simultaneous.
    """
    launcher_ids, _ = launcher_family_maps(items)
    crafting_ids = {
        item_id
        for table in items.get("crafting", []) or []
        if (item_id := _item_id(table)) is not None
    }
    requirements = required_launcher_families_by_crafting_class(items, recipes)
    setup_ids = setup_item_ids(initial_setup)
    granted_families = {
        item_id // 100
        for item_id in setup_ids
        if item_id in launcher_ids
    }
    granted_tables = setup_ids.intersection(crafting_ids)
    issues: List[str] = []

    def validate_reward_items(
        reward_items: Sequence[Mapping[str, Any]],
        label: str,
        require_facilities: bool,
    ) -> None:
        for item in reward_items:
            item_id = _item_id(item)
            if item_id is None:
                issues.append(f"{label} contains a facility reward without an item id")
                continue
            if item_id not in launcher_ids and item_id not in crafting_ids:
                if require_facilities:
                    issues.append(f"{label} references unknown facility {item_id}")
                continue
            if item_id in crafting_ids and item_id not in granted_tables:
                missing = sorted(requirements.get(item_id // 100, set()) - granted_families)
                if missing:
                    labels = ", ".join(f"{family}xx" for family in missing)
                    issues.append(
                        f"{label} grants crafting table {item_id} before "
                        f"launcher families {labels}"
                    )

    def grant_reward_items(reward_items: Sequence[Mapping[str, Any]]) -> None:
        for item in reward_items:
            item_id = _item_id(item)
            if item_id in launcher_ids:
                granted_families.add(item_id // 100)
            if item_id in crafting_ids:
                granted_tables.add(item_id)

    def home_stage_level(stage: Mapping[str, Any], stage_index: int) -> int:
        configured = _as_int(stage.get("cultivation_level"))
        if configured is not None and configured > 0:
            return configured
        # Legacy 110-stage layout: levels 1-10 had one circulation each and
        # levels 11+ had ten each.
        if stage_index <= 9:
            return stage_index + 1
        return 11 + (stage_index - 10) // 10

    applied_breakthrough_level = 0
    previous_home_level = 0
    for stage_index, stage in enumerate(home_stages):
        stage_level = home_stage_level(stage, stage_index)
        if stage_level < previous_home_level:
            issues.append(
                f"stage {stage_index} cultivation level {stage_level} is before level {previous_home_level}"
            )
        previous_home_level = max(previous_home_level, stage_level)

        if cultivation_stages is not None and rewards is not None:
            while applied_breakthrough_level < stage_level - 1:
                applied_breakthrough_level += 1
                if applied_breakthrough_level > len(cultivation_stages):
                    break
                cultivation_stage = cultivation_stages[applied_breakthrough_level - 1]
                reward_id = _as_int(cultivation_stage.get("breakthrough_reward_id"))
                breakthrough_items = list(iter_reward_items(reward_id, rewards)) if reward_id else []
                label = f"breakthrough reward at cultivation level {applied_breakthrough_level}"
                validate_reward_items(breakthrough_items, label, False)
                grant_reward_items(breakthrough_items)

        stage_items = list(iter_reward_items(stage.get("circulation_reward"), rewards))
        label = f"stage {stage_index}"
        validate_reward_items(stage_items, label, True)
        # Rewards in one circulation stage are simultaneous; only grant their
        # launcher families after all crafting-table checks for this stage.
        grant_reward_items(stage_items)

    if issues:
        raise ValueError("facility reward dependency validation failed:\n- " + "\n- ".join(issues))
