# Spiritual Production Lines Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add 16-level spirit wood garden, spirit pond, and spirit stone vein facilities; integrate their material chains into recipes; make spirit stone item drops convert to currency when clicked; and add the facilities to production rewards with only one level-1 vein granted.

**Architecture:** Keep XLSX files as the configuration source of truth and regenerate JSON through `xlsx_to_json.py`. Use the existing deterministic item-spawn model for all three facilities. Represent spirit stones as effect items that land on the board and are authoritatively consumed into currency through a dedicated endpoint.

**Tech Stack:** Godot 4 / GDScript, TypeScript server, Python config generator, XLSX edited through `@oai/artifact-tool`.

---

### Task 1: Add item and launcher configuration

**Files:**
- Modify: `config/xlsx/items.xlsx`
- Modify: `config/xlsx_to_json.py`
- Modify: `config/json_to_xlsx.py`

1. Add five 16-level material chains, one 4-level spirit-stone effect-item chain, and three 16-level launcher chains with non-conflicting IDs.
2. Configure gardens and ponds from the existing dual-output weight template.
3. Configure veins with a 95:5 jade-to-level-1-spirit-stone split at every level.
4. Give the four spirit-stone levels the names 普通灵石、中品灵石、上品灵石、极品灵石 and effect values 1, 5, 15, and 40.

### Task 2: Integrate materials into recipes

**Files:**
- Modify: `config/xlsx/recipes.xlsx`

1. Replace selected ingredient slots rather than increasing recipe arity.
2. Use spirit resin/fish in pill and wine recipes.
3. Use spirit wood/jade in forging recipes.
4. Use spirit pearl/jade in formation recipes.
5. Use spirit wood/resin in talisman recipes.
6. Verify every new non-currency material appears in at least one recipe.

### Task 3: Update facility reward generation

**Files:**
- Modify: `config/xlsx_to_json.py`

1. Insert level-1 garden, pond, and vein rewards before dependent crafting tables.
2. Add level-2 and level-3 garden/pond tutorial rewards without duplicate item IDs per reward.
3. Add garden and pond to long-term facility target counts and circulation rules.
4. Exclude the vein from circulation and breakthrough rules.
5. Extend validation for resource outcomes and the single level-1 vein grant.

### Task 4: Implement authoritative spirit-stone item use

**Files:**
- Modify: `server/src/engine/game_engine.ts`
- Modify: `server/src/routes/cultivation.ts`

1. Add a spirit-stone effect type and validate it server-side.
2. Remove the used item by UID and increase spirit stone currency by its configured effect value.
3. Advance state version and item-consumption quest progress.
4. Return the latest spirit stone balance and quest progress.

### Task 5: Implement client item-use flow

**Files:**
- Modify: `scripts/utils/Constants.gd`
- Modify: `autoload/CloudService.gd`
- Modify: `scenes/screens/GameScreen.gd`
- Modify: `scenes/screens/BattleScreen.gd`

1. Add the spirit-stone effect enum and cloud request/response signals.
2. Dispatch clicked spirit-stone items to the dedicated consume endpoint.
3. Remove the confirmed item locally, sync spirit stones, and show the gained amount.
4. Clear pending use state on both success and failure.

### Task 6: Regenerate and verify

**Files:**
- Modify: `config/json_output/items.json`
- Modify: `config/json_output/recipes.json`
- Modify: `config/json_output/home_meridians.json`

1. Export and visually verify edited workbooks.
2. Run `config/xlsx_to_json.py`.
3. Validate IDs, group sizes, recipe references, resource weights, and facility reward totals.
4. Add and run a server test for spirit-stone consumption and verify the item is removed exactly once.
5. Run TypeScript checking and Godot headless parse/startup verification.
