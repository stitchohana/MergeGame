# Home Meridian Run Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make each home-meridian circulation require an explicit “运转周天” click after all acupoints are lit, then animate qi returning to the dantian, grant the circulation reward, show a received-reward popup, and only then display the next circulation.

**Architecture:** Keep the server authoritative. Lighting an acupoint only consumes qi and grants the per-acupoint reward; a new server operation validates that the current stage is fully lit, applies its circulation reward exactly once, marks the stage complete, and returns the reward bundle plus updated cultivation/progress. The HomeScreen owns the run button and animation, while a reusable reward-received popup is used after both circulation runs and breakthroughs.

**Tech Stack:** TypeScript/Express game server, Godot 4 GDScript UI, existing CloudService endpoint registry and UIManager popup layer.

---

### Task 1: Separate lighting from circulation completion on the server

1. Update `lightHomeAcupoint` so the final lit node leaves `circulation_completed` false and does not apply `circulation_reward`.
2. Add `runHomeMeridianCirculation` with validation for unlocked stage, fully lit progress, and not-yet-completed state; apply the configured reward once and return updated state/rewards.
3. Add `POST /api/game/home_meridian/run` and extend the TypeScript smoke test for the new two-step lifecycle and duplicate/early-run rejection.

### Task 2: Add the client endpoint and explicit run action

1. Add CloudService signals, endpoint registration, submit method, and response handler for the run operation.
2. Add a HomeScreen “运转周天” button visible only when the active stage is fully lit; disable it while a request or animation is in progress.
3. Apply returned cultivation/resource/progress state without locally inventing rewards.

### Task 3: Animate qi and show received rewards

1. Add a reusable `RewardReceivedPopup` that renders the returned token/item bundle and closes with one acknowledgement button.
2. After a successful run, animate a qi orb through the visible acupoints and into the center/dantian, then refresh to the next stage and show the popup.
3. After a successful breakthrough, show the same popup with the server-returned breakthrough rewards.

### Task 4: Verify

1. Run the server TypeScript check and home-meridian smoke test.
2. Run a Godot parse/headless check if the editor executable is available; otherwise perform static scene/script checks and report the limitation.

