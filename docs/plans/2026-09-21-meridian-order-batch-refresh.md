# Meridian Order Batch Refresh Implementation Plan

**Goal:** Random meridian orders are consumed as a configured batch, refresh only after the batch is empty, reset active launcher charges at that boundary, and select order items using launcher spawn probabilities.

**Architecture:** Keep breakthrough and fixed onboarding orders on their existing paths. Add a weighted random-order pool alongside the existing candidate pool, use weighted sampling without replacement inside each order, and centralize random batch creation so the configured order count is regenerated only when the prior random batch is complete.

**Tech Stack:** TypeScript, Node.js, existing `GameEngine` and server smoke tests.

---

### Task 1: Add weighted candidate generation

- Modify `server/src/engine/game_engine.ts`.
- Preserve `getUnlockedOrderPool()` as an ID-only wrapper for existing callers.
- Add a weighted pool helper that accumulates normalized launcher spawn weights by merge chain, gives recipe products a dependency-derived weight, and defaults fixed spawns to a small positive weight.
- Extend `_genOneAcupoint()` with optional weights and sample without replacement.

### Task 2: Generate random orders in batches

- Add a helper that creates exactly the active threshold's configured `order_count` random orders and applies scaled rewards.
- Use the weighted pool for initial random generation and for the batch refresh.
- Sort each generated random batch by total order value from low to high.
- In `completeMeridianAcupoint()`, remove the completed random order without replacement; refresh only when the random list becomes empty, then reset launcher charges before generating the next batch.
- Leave fixed onboarding and breakthrough branches unchanged.

### Task 3: Verify behavior

- Add focused assertions to a new server smoke test for no immediate replacement, full-batch refresh, launcher charge reset, weighted selection, and no duplicate item IDs within an order.
- Run the existing home-meridian and stamina smoke tests plus the TypeScript worker check.
- Run `git diff --check` and inspect the final diff without committing or pushing.
