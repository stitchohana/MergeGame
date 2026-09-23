# Stamina Multiplier Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a one-hour stamina multiplier mode that activates at doubling stamina thresholds, lets players select an active multiplier, and raises launcher output levels by `log2(multiplier)`.

**Architecture:** The server owns activation, expiry, validation, stamina deduction, and output upgrading. The Godot client mirrors the active boost for UI and deterministic prediction, while every spawn request carries the selected multiplier and is reconciled against the authoritative result.

**Tech Stack:** Godot 4/GDScript client, TypeScript/Express server, JSON/XLSX configuration, existing smoke-test infrastructure.

---

### Task 1: Add server boost state and configuration

**Files:**
- Modify: `config/json_output/game_config.json`
- Modify: `server/src/storage/interface.ts`
- Modify: `server/src/engine/game_engine.ts`
- Modify: `server/src/routes/game.ts`

1. Add a 100 threshold coefficient (multiplied by each tier, so x2 starts at 200)
   and a 3600-second duration to stamina config.
2. Add `stamina_multiplier_max` and `stamina_multiplier_expires_at` to persisted state.
3. Centralize stamina gains so qualifying gains activate or refresh the unified boost.
4. Include normalized boost state in state and mutation responses.

### Task 2: Apply multipliers during authoritative spawning

**Files:**
- Modify: `server/src/engine/game_engine.ts`
- Modify: `server/src/routes/game.ts`
- Test: `server/tests/stamina_multiplier_smoke.ts`

1. Validate power-of-two requests against the active maximum.
2. Compute each launcher's safe multiplier from all possible output chains.
3. Roll the original result, then map it to the same type/group at the upgraded level.
4. Deduct `spawn_cost * multiplier` while consuming one charge and one spawn action.
5. Return applied multiplier, stamina cost, and boost metadata.

### Task 3: Add client state, prediction, and request support

**Files:**
- Modify: `autoload/GameState.gd`
- Modify: `autoload/SaveManager.gd`
- Modify: `autoload/CloudService.gd`
- Modify: `autoload/ConfigDatabase.gd`
- Modify: `scenes/grid/LauncherController.gd`
- Modify: `scenes/grid/GridView.gd`

1. Store authoritative maximum and expiry plus the local selected multiplier.
2. Upgrade deterministic predictions using the same type/group/level mapping.
3. Reserve pending stamina using actual multiplier cost.
4. Send the effective multiplier and reconcile it from the response.

### Task 4: Build the multiplier selector

**Files:**
- Create: `scenes/ui/main/StaminaMultiplierControl.gd`
- Create: `scenes/ui/main/StaminaMultiplierControl.tscn`
- Modify: `scenes/screens/GameScreen.tscn`
- Modify: `scenes/screens/GameScreen.gd`

1. Show the control only while a boost is active on the main board.
2. Automatically select the highest tier on a new activation.
3. Let the player choose any active power-of-two tier, including x1.
4. Display the shared remaining time using `TimeUtils.format_countdown`.

### Task 5: Verify boundaries and regression behavior

**Files:**
- Test: `server/tests/stamina_multiplier_smoke.ts`
- Test: `tests/stamina_multiplier_ui_smoke.gd`

1. Cover `199/200/399/400/799/800` thresholds with `>=` semantics.
2. Cover unified one-hour refresh, higher-tier promotion, and expiry.
3. Cover level-one and level-two output upgrades and safe maximum caps.
4. Cover insufficient stamina, free launchers, battle launches, rapid pending clicks, and client selection behavior.
5. Run server build/tests and available Godot smoke tests.

### Task 6: Limit multiplier tiers by cultivation realm

**Files:**
- Modify: `server/src/engine/game_engine.ts`
- Test: `server/tests/stamina_multiplier_smoke.ts`

1. Centralize the realm cap calculation in the authoritative engine.
2. Cap Mortal/Qi Refining at x4, Foundation Establishment at x8, Golden Core at x16,
   and Nascent Soul at x32; later realms retain x32 until a higher tier is designed.
3. Apply the cap when reading persisted boost state and when activating or refreshing it.
4. Normalize legacy active states that exceed the current realm cap.
5. Verify that spawn requests cannot bypass the realm cap.

### Task 7: Prioritize lower-level active-order items

**Files:**
- Modify: `server/src/engine/game_engine.ts`
- Modify: `server/src/routes/game.ts`
- Modify: `scenes/grid/LauncherController.gd`
- Modify: `scenes/grid/GridView.gd`
- Test: `server/tests/stamina_multiplier_smoke.ts`
- Test: `tests/stamina_multiplier_ui_smoke.gd`

1. Count unmet item quantities across active orders after subtracting matching board
   items and ready crafting results.
2. When a rolled base item can satisfy an unmet lower-level item in the same
   type/group chain, emit the lowest-level unmet item before the normal boosted item.
3. Charge only the effective multiplier represented by the emitted item and report
   the difference from the requested multiplier as refunded stamina.
4. Mirror the priority calculation in client prediction while keeping the server
   authoritative.
5. Restore normal boosted output as soon as the outstanding order quantity is filled.
