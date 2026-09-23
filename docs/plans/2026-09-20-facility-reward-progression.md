# Facility Reward Progression Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Restrict Qi-stage facility rewards to the four starter launcher families and two starter crafting tables, then unlock the remaining launchers and crafting tables across the three Foundation stages.

**Architecture:** Keep the three mortal tutorial rewards unchanged. Generate each later cultivation level from an explicit ordered family pool, calculate facility levels from each family's occurrences within its realm, and validate both the allowed unlock stage and crafting-table usability. Continue storing generated rewards in `home_meridians.json` and mirror them into `home_meridians.xlsx`.

**Tech Stack:** Python configuration generators and validators, JSON/XLSX configuration tables, TypeScript server smoke tests.

---

### Task 1: Lock the requested progression in tests

**Files:**
- Modify: `server/tests/home_meridian_exp_smoke.ts`

**Steps:**
1. Assert that Qi-stage rewards contain only families 110, 120, 130, 150, 170, and 180.
2. Assert that Foundation Early introduces family 140 before family 210.
3. Assert that Foundation Middle introduces family 230 before family 200.
4. Assert that Foundation Late introduces families 160 and 240 before family 190.
5. Run the smoke test and confirm that the current all-family Qi schedule fails.

### Task 2: Generate realm-specific facility rewards

**Files:**
- Modify: `config/expand_home_meridians.py`
- Modify: `config/home_meridian_progression.py`

**Steps:**
1. Define ordered family pools for Qi, Foundation Early, Foundation Middle, Foundation Late, Gold, and Nascent Soul.
2. Generate two distinct family rewards per circulation.
3. Ramp families already available in Qi from levels 5-8 during Foundation; start newly introduced Foundation families at level 1 and ramp them to level 8.
4. Preserve the mortal tutorial reward rows exactly.
5. Validate that forbidden families never appear before their configured unlock stage.

### Task 3: Support progressive recipe availability

**Files:**
- Modify: `config/facility_reward_validation.py`

**Steps:**
1. Calculate launcher-family dependencies per recipe, including recursively crafted ingredients.
2. Allow a crafting table when at least one assigned recipe has all launcher families available.
3. Continue treating rewards in the same circulation as simultaneous, so a launcher must appear in an earlier circulation than its dependent table.
4. Preserve the fixed tutorial exception for `17001`.

### Task 4: Regenerate and synchronize configuration

**Files:**
- Modify: `config/json_output/home_meridians.json`
- Modify: `config/xlsx/home_meridians.xlsx`
- Modify: `config/CONFIG.md`

**Steps:**
1. Run `config/expand_home_meridians.py`.
2. Copy the generated home-meridian rows into the Excel source workbook.
3. Update the configuration documentation with the new realm unlock pools and progressive table-usability rule.
4. Verify that JSON and Excel contain identical reward rows.

### Task 5: Verify the complete change

**Files:**
- Test: `server/tests/home_meridian_exp_smoke.ts`

**Steps:**
1. Run the home-meridian generator and JSON conversion validation.
2. Run the server TypeScript build.
3. Run the home-meridian and crafting-table smoke tests.
4. Run `git diff --check` and confirm no generated inspection files remain.
