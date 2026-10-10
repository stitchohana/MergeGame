"""Validation shared by recipe configuration conversion scripts."""


def validate_no_subrecipe_conflicts(recipes, crafting_items):
    """Reject strict material subsets and identical recipes on the same table."""
    table_ids_by_recipe = {}
    for table in crafting_items:
        for recipe_id in table.get("recipes", []) or []:
            table_ids_by_recipe.setdefault(int(recipe_id), set()).add(int(table["id"]))

    material_sets = [
        {int(ingredient) for ingredient in recipe.get("ingredients", []) or []}
        for recipe in recipes
    ]
    conflicts = []
    for index, recipe in enumerate(recipes):
        ingredients = material_sets[index]
        recipe_id = int(recipe["id"])
        for other_index in range(index + 1, len(recipes)):
            other = recipes[other_index]
            other_ingredients = material_sets[other_index]
            other_id = int(other["id"])
            shared_tables = table_ids_by_recipe.get(recipe_id, set()) & table_ids_by_recipe.get(other_id, set())
            if ingredients < other_ingredients:
                conflicts.append(f"recipe {recipe_id} is a subrecipe of recipe {other_id}")
            elif other_ingredients < ingredients:
                conflicts.append(f"recipe {other_id} is a subrecipe of recipe {recipe_id}")
            elif ingredients == other_ingredients and shared_tables:
                conflicts.append(f"recipes {recipe_id} and {other_id} have identical materials on the same table")
    if conflicts:
        raise ValueError("Recipe material combinations are ambiguous: " + "; ".join(conflicts))


def validate_regular_ingredients(recipes, regular_items):
    """Allow only ordinary item IDs, excluding all recipe results."""
    product_ids = {int(recipe["result"]) for recipe in recipes}
    ordinary_ids = {
        int(item["id"])
        for item in regular_items
        if int(item.get("type", 0)) == 0
    } - product_ids
    invalid = []
    for recipe in recipes:
        ingredient_ids = {int(ingredient) for ingredient in recipe.get("ingredients", []) or []}
        invalid_ids = sorted(ingredient_ids - ordinary_ids)
        if invalid_ids:
            recipe_id = recipe.get("id", "?")
            recipe_name = str(recipe.get("name", "")).strip()
            labels = ", ".join(str(item_id) for item_id in invalid_ids)
            invalid.append(f"recipe {recipe_id} {recipe_name}: {labels}")
    if invalid:
        raise ValueError(
            "Recipe ingredients must be ordinary items (not recipe products): "
            + "; ".join(invalid)
        )


def validate_no_duplicate_ingredients(recipes):
    """Reject repeated item IDs within a single recipe's ingredient list."""
    invalid = []
    for recipe in recipes:
        seen = set()
        duplicates = set()
        for ingredient in recipe.get("ingredients", []) or []:
            ingredient_id = int(ingredient)
            if ingredient_id in seen:
                duplicates.add(ingredient_id)
            seen.add(ingredient_id)
        if duplicates:
            recipe_id = recipe.get("id", "?")
            recipe_name = str(recipe.get("name", "")).strip()
            labels = ", ".join(str(item_id) for item_id in sorted(duplicates))
            invalid.append(f"recipe {recipe_id} {recipe_name}: {labels}")

    if invalid:
        raise ValueError(
            "Recipe ingredients cannot contain duplicate items: " + "; ".join(invalid)
        )


def validate_no_launcher_ingredients(recipes, launcher_items):
    """Reject recipes that use a launcher/facility item as an ingredient.

    Launcher IDs are intentionally derived from the launcher item table rather
    than from an ID range so future chains can use any numbering scheme.
    """
    launcher_by_id = {}
    for item in launcher_items:
        try:
            launcher_id = int(item.get("id"))
        except (AttributeError, TypeError, ValueError):
            continue
        launcher_by_id[launcher_id] = str(item.get("name", "")).strip()

    invalid = []
    for recipe in recipes:
        recipe_id = recipe.get("id", "?")
        recipe_name = str(recipe.get("name", "")).strip()
        for ingredient in recipe.get("ingredients", []) or []:
            try:
                ingredient_id = int(ingredient)
            except (TypeError, ValueError):
                continue
            if ingredient_id in launcher_by_id:
                launcher_name = launcher_by_id[ingredient_id]
                label = f"{ingredient_id} {launcher_name}".strip()
                invalid.append(f"recipe {recipe_id} {recipe_name}: {label}")

    if invalid:
        details = "; ".join(invalid)
        raise ValueError(
            "Recipe ingredients cannot contain launcher items: " + details
        )
