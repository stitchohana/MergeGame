"""Validation shared by recipe configuration conversion scripts."""


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
