# Network Latency Optimization Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Keep gameplay responsive under network latency and move the authoritative D1 primary database from WNAM to APAC without deleting the rollback database.

**Architecture:** Keep mutations serialized, but separate them from parallel/coalesced queries. Apply reversible optimistic state for deterministic grid actions, use immediate pending feedback for random spawns, and render cached screen state while background synchronization runs. Create a new APAC D1 database, copy and validate production rows, then switch the Worker binding.

**Tech Stack:** Godot 4 GDScript, Cloudflare Workers TypeScript, Cloudflare D1, Wrangler.

---

### Task 1: Request lanes and state request coalescing

**Files:**
- Modify: `autoload/CloudService.gd`

**Steps:**
1. Replace the single global request lock with one serialized mutation lane and independently allocated query requests.
2. Coalesce concurrent `fetch_state` calls into one request and fan out the existing `state_loaded` signal once.
3. Keep mutation ordering unchanged and reject queue overflow explicitly.
4. Run GDScript/static validation and inspect all call sites.

### Task 2: Cache-first screen entry

**Files:**
- Modify: `scenes/screens/GameScreen.gd`
- Modify: `scenes/screens/HomeScreen.gd`
- Modify: `scenes/ui/character/CharacterEntry.gd`
- Modify: `scenes/ui/activity/WeeklyActivityEntry.gd`

**Steps:**
1. Render the cached main grid immediately when entering the game screen.
2. Avoid full-screen loading when valid cache exists; keep background board synchronization.
3. Remove component-level duplicate state fetches and rely on screen-level synchronization.
4. Verify navigation and empty-cache fallback paths.

### Task 3: Optimistic grid interaction

**Files:**
- Modify: `autoload/MergeService.gd`
- Modify: `scenes/grid/GridView.gd`
- Modify: `scenes/grid/LauncherController.gd`

**Steps:**
1. Apply moves locally at drop time and retain a rollback snapshot until confirmation.
2. Apply deterministic merges locally with a temporary UID, then reconcile the authoritative UID and counters.
3. Trigger launcher feedback immediately while keeping random item creation authoritative.
4. Roll back rejected operations and block only cells involved in pending operations.
5. Verify success, rejection, and delayed-response paths.

### Task 4: APAC D1 migration

**Files:**
- Modify: `server/wrangler.toml`
- Create: `server/migrations/0002_state_version.sql` only if optimistic concurrency requires a schema change.

**Steps:**
1. Create `mergegame-db-apac` with the `apac` location hint.
2. Apply the existing schema and export/import users and game states from WNAM.
3. Validate row counts and parse representative `state_json` records.
4. Switch only the Worker D1 binding to the APAC database and deploy.
5. Verify health, login, state read, a mutation, and subsequent persistence through `https://234575.xyz`.
6. Keep the WNAM database intact for rollback.

### Task 5: Final verification

**Files:**
- Verify all files changed above.

**Steps:**
1. Run Worker type checking and deployment build checks.
2. Run available Godot validation; if the Godot CLI is unavailable, report the gap explicitly.
3. Run `git diff --check` and review the scoped diff.
4. Report the migration IDs, production URL, verification results, and rollback path.
