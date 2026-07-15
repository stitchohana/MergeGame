# 300-Day Progression Balance Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rebalance item values, order qi rewards, Home meridian rewards, and qi caps so the configured progression consumes about 300 days of stamina-equivalent resources.

**Architecture:** Item `value` becomes the expected stamina cost of producing an item. Requirement orders convert total item value into base qi, then apply a separate activity multiplier. Home meridians consume the resulting qi and award EXP plus uncapped reward stamina; natural stamina regeneration remains capped at 100.

**Tech Stack:** Godot 4.6/GDScript, Node.js/TypeScript server, JSON configuration, XLSX source tables.

---

### Task 1: Build the stamina-cost model

**Files:**
- Create: `config/progression_balance.mjs`
- Modify: `config/json_output/items.json`

**Steps:**
1. Load items, launcher spawn tables, recipes, meridian thresholds, cultivation stages, and Home meridians.
2. Assign launcher outputs an expected stamina cost from weighted spawn probability.
3. Assign merge-chain items twice the previous-level acquisition cost.
4. Assign recipe products the sum of ingredient stamina costs.
5. Validate every item in every order pool has a positive stamina cost.
6. Emit a stage summary with expected order cost and maximum order cost.

### Task 2: Separate base order qi from activity bonuses

**Files:**
- Modify: `server/src/engine/game_engine.ts`
- Modify: `config/json_output/meridians.json`

**Steps:**
1. Add threshold fields for base `qi_per_value` and optional `activity_qi_multiplier`.
2. Calculate base order qi from total stamina value.
3. Apply the activity multiplier as a separate step so future activities can stack without changing base rewards.
4. Preserve reward previews and completion rewards through the same calculation path.
5. Build the TypeScript server and verify no type errors.

### Task 3: Rebalance Home meridians and cultivation caps

**Files:**
- Modify: `config/json_output/home_meridians.json`
- Modify: `config/json_output/cultivation.json`

**Steps:**
1. Make every acupoint reward EXP plus 15 stamina.
2. Make every circulation reward approximately 30% of its progression segment EXP plus 100 stamina.
3. Ensure each cultivation segment's total Home EXP matches its breakthrough requirement.
4. Scale total Home qi cost against the 300-day stamina budget.
5. Set each stage max qi high enough to receive at least two maximum-value orders without clipping.
6. Verify reward stamina remains uncapped while natural regeneration remains capped at 100.

### Task 4: Synchronize source workbooks

**Files:**
- Modify: `config/xlsx/items.xlsx`
- Modify: `config/xlsx/meridians.xlsx`
- Modify: `config/xlsx/home_meridians.xlsx`
- Modify: `config/xlsx/cultivation.xlsx`

**Steps:**
1. Import and render each existing workbook before editing.
2. Preserve workbook layout and formatting.
3. Update changed values and any new order-reward columns.
4. Export each workbook back to its source path.
5. Render all changed sheets and inspect key ranges for truncation or formula errors.
6. Run `config/xlsx_to_json.py` and confirm generated JSON matches the balance model.

### Task 5: Verify the progression model

**Files:**
- Verify: `config/progression_balance.mjs`
- Verify: `server/src/engine/game_engine.ts`

**Steps:**
1. Confirm total natural stamina over 300 days is 216,000.
2. Confirm Home rewards add 91,120 uncapped stamina.
3. Confirm modeled required item value is approximately 307,120 stamina.
4. Confirm every Home acupoint grants EXP and 15 stamina.
5. Confirm every circulation grants about 30% segment EXP and 100 stamina.
6. Confirm order previews and applied rewards match with activity multiplier 1.0.
7. Run `npm run build` in `server`.
8. Launch Godot and complete startup/login/config loading without new errors.
