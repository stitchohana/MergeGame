# Configurable Recipe Order Probability Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Random order item slots select recipe products with configurable probability, initially 80%.

**Architecture:** Filter the existing obtainable item pool by category for each draw, then retain the existing weighted selection within that category. A missing/exhausted category falls back to the remaining pool; batch deduplication and fixed/breakthrough orders continue through their existing paths.

**Tech Stack:** TypeScript game engine, JSON config, Excel source config, tsx smoke tests.

---

### Task 1: Define behavior with deterministic tests

Create `server/tests/order_recipe_probability_smoke.ts`. Cover the 0.8 category boundary, custom 0/1/intermediate probabilities, missing or invalid config, independent category weights, weighted picks within each category, single-category and exhausted pools, batch deduplication, and fixed tutorial orders. Run `cd server; node_modules/.bin/tsx.cmd tests/order_recipe_probability_smoke.ts` and confirm the current pooled selection fails the category boundary.

### Task 2: Implement category selection and synchronize config

Modify `server/src/engine/game_engine.ts`: load `orders.recipe_product_probability`, default to 0.8, clamp finite values to 0–1, and select type=4 versus other eligible candidates before the existing weighted draw. Store 0.8 in `config/json_output/game_config.json` and `config/xlsx/game_config.xlsx` as `orders.recipe_product_probability`. Preserve other workbook cells and styles. Document semantics and fallback behavior in `config/CONFIG.md`.

### Task 3: Verify final behavior

Run the new test, `meridian_order_batch_smoke.ts`, `home_meridian_exp_smoke.ts`, and `npm run worker:check`. Check a seeded statistical sample against 80%, validate Excel/JSON round-trip conversion, and run `git diff --check` for changed files. Do not deploy or change existing saved orders as part of this implementation.
