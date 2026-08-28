# Spirit Stone Countdown Speedup Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add config-priced, server-authoritative spirit-stone acceleration for crafting and launcher recharge countdowns.

**Architecture:** The server owns remaining-time and price calculation, validates and deducts spirit stones, then returns an authoritative grid snapshot. Godot displays a live estimate in ItemDetail and reconciles the server response into the existing grid and timer controllers.

**Tech Stack:** Godot 4 / GDScript, TypeScript / Express worker, JSON and XLSX config tables.

### Task 1: Add pricing configuration

**Files:**
- Modify: `config/json_output/game_config.json`
- Modify: `config/xlsx/game_config.xlsx`
- Modify: `server/src/engine/game_engine.ts`

Add the two per-second rates with defaults of one spirit stone, sync the workbook, and load clamped numeric values in the engine.

### Task 2: Add authoritative speedup operations

**Files:**
- Modify: `server/src/engine/game_engine.ts`
- Modify: `server/src/routes/game.ts`

Implement craft and launcher speedup operations. Calculate `ceil(remaining milliseconds / 1000) * rate`, reject insufficient balances without mutation, and return cost, balance, and authoritative grid state.

### Task 3: Add client service calls and local reconciliation

**Files:**
- Modify: `autoload/CloudService.gd`
- Modify: `autoload/CraftingService.gd`
- Modify: `scenes/grid/LauncherController.gd`
- Modify: `scenes/grid/GridView.gd`

Register both endpoints and signals. On success, synchronize spirit stones, complete local craft timers, clear launcher cooldowns, and refresh charge visuals.

### Task 4: Add ItemDetail interaction

**Files:**
- Modify: `scenes/ui/main/ItemDetailPanel.gd`
- Modify: `scenes/ui/main/ItemDetailPanel.tscn`

Show live remaining time and calculated cost only for active countdowns. Disable duplicate requests and unaffordable actions, submit the correct request, then refresh from the authoritative response.

### Task 5: Verify behavior

Run the TypeScript check and targeted engine assertions for successful craft speedup, successful launcher speedup, exact rounded pricing, and insufficient-stone rejection. Run Godot headless parsing when an executable is available, and inspect the edited workbook before and after export.
