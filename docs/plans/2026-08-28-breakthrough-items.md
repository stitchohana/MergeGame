# Breakthrough Items Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the single breakthrough pill requirement with a configurable list of arbitrary items, display that list above the breakthrough button, and consume every configured requirement atomically.

**Architecture:** `cultivation.xlsx` and generated `cultivation.json` define `breakthrough_items` as item/count pairs. The server is authoritative: it validates all requirements across pouch and board before removing anything, then returns the normal breakthrough state. HomeScreen renders the configured list in a horizontal ScrollContainer and opens `RecipeSourcePopup` for each item.

**Tech Stack:** Godot 4 GDScript UI, TypeScript game engine/routes, JSON generated from XLSX, Godot headless smoke tests, Node/tsx server smoke tests.

---

### Task 1: Replace cultivation configuration schema

**Files:**
- Modify: `config/xlsx/cultivation.xlsx`
- Modify: `config/xlsx_to_json.py`
- Modify: `config/json_output/cultivation.json`
- Modify: `autoload/ConfigDatabase.gd`
- Modify: `server/src/engine/game_engine.ts`

Add a `breakthrough_items` JSON field containing `{item_id, count}` entries. Remove all legacy single-item reads and accessors. Update the source spreadsheet and regenerate/check JSON so every configured breakthrough has valid positive item IDs and counts.

### Task 2: Make server breakthrough validation and consumption atomic

**Files:**
- Modify: `server/src/engine/game_engine.ts`
- Modify: `server/src/routes/cultivation.ts`
- Modify: `autoload/CloudService.gd`
- Modify: `autoload/CultivationService.gd`

Breakthrough requests no longer select one pill. The engine resolves the current level's item requirements, counts matching pouch and grid entries, rejects with a missing-item reason before mutation if any requirement is short, then removes the exact required quantities and applies the breakthrough reward. Preserve the existing response shape where possible.

### Task 3: Add the horizontal breakthrough item list

**Files:**
- Modify: `scenes/screens/HomeScreen.gd`
- Modify: `scenes/screens/HomeScreen.tscn`
- Create or modify: a small reusable UI script/scene under `scenes/ui/common/` if needed

Create a horizontally scrollable list above `BreakthroughBtn`. Populate it only while breakthrough is available, show each configured item icon and required count, and hide it otherwise. Clicking an item opens `RecipeSourcePopup.setup_for_item(item_id)`.

### Task 4: Add regression coverage and verify

**Files:**
- Create: `server/tests/breakthrough_items_smoke.ts`
- Create: `tests/breakthrough_items_ui_smoke.gd`
- Create: `tests/BreakthroughItemsUISmoke.tscn`

Cover arbitrary item IDs, quantities, pouch/board combination, atomic failure, and UI list population/click wiring. Run JSON/config validation, TypeScript tests/build, Godot headless smoke tests, and `git diff --check`.
