# Item Discovery Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** A first-time item from production, rewards, or merging unlocks its icon and shows one notification; later acquisitions and state restoration stay quiet.

**Architecture:** Reuse the server-persisted `crafted_item_ids` as the acquired-item ledger, with a migration that seeds existing inventory without notifications. The client inspects successful mutation responses, records only confirmed new IDs, and emits one toast per response. The path view continues reading the same ledger.

**Tech Stack:** Godot 4 GDScript, TypeScript authoritative game engine, smoke tests.

---

### Task 1: Persist discoveries

**Files:** `server/src/engine/game_engine.ts`, `server/src/routes/game.ts`, `server/tests/item_discovery_smoke.ts`.

1. Test initial board, duplicate item, spawn, merge, reward, and recipe retrieval updating `crafted_item_ids` only once.
2. Add a reusable server method to record an item ID and migrate existing grid, pouch, stored items, and pending rewards into the ledger.
3. Verify with `npx tsx tests/item_discovery_smoke.ts` and `npm run worker:check` from `server`.

### Task 2: Confirmed client notification

**Files:** `autoload/GameState.gd`, `autoload/CloudService.gd`, `tests/item_discovery_smoke.gd`, `tests/ItemDiscoverySmoke.tscn`.

1. Test silent server-history restore and a one-time toast for a confirmed new ID.
2. Collect IDs from successful spawn, merge, action batch, craft retrieval, granted rewards, and battle loot; skip requests that restore state.
3. Verify duplicates are quiet, including replayed spawn responses.

### Task 3: Final check

1. Run the server smoke test and TypeScript check.
2. Run the Godot smoke scene when a Godot CLI is available.
3. Review `git diff --check` and avoid unrelated worktree changes.
