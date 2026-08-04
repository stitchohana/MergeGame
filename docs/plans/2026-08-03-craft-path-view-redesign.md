# CraftPathView Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rebuild `CraftPathView` to match the confirmed 780×1688 MasterGo layout while preserving its item-selection and launcher-source behavior.

**Architecture:** Keep `CraftPathView` as a full-screen `BasePopup`. The popup scene owns the fixed design geometry and texture-backed visual layers; the script only populates semantic containers with item icons, level labels, arrows, selection state, and source data. Existing textures act as placeholders until final sliced assets are available.

**Tech Stack:** Godot 4, GDScript, Control/NinePatchRect/TextureRect containers.

---

### Task 1: Rebuild the popup scene geometry

**Files:**
- Modify: `scenes/ui/main/CraftPathView.tscn`

**Step 1:** Replace the old centered 620×1000 panel with a full-screen 780×1688 popup and a panel at `(20.8, 145.6)` sized `738.4×1404`.

**Step 2:** Add fixed texture-backed slots for the header, description, three-row viewport, source divider, source card, and bottom ornament.

**Step 3:** Keep all designed surfaces as `TextureRect`, `NinePatchRect`, or texture-themed buttons; do not introduce color-only `StyleBoxFlat` surfaces.

### Task 2: Rebuild the dynamic merge path

**Files:**
- Modify: `scenes/ui/main/CraftPathView.gd`

**Step 1:** Populate four nodes per row with 128.96×141.44 item cards and 27.04×27.04 arrow texture slots.

**Step 2:** Place extra rows in the scrollable path viewport so 16-level groups remain reachable while the default viewport matches the three-row design.

**Step 3:** Update title, description, selected state, and source card whenever the user selects another item.

### Task 3: Verify behavior and layout

**Files:**
- Verify: `scenes/ui/main/CraftPathView.tscn`
- Verify: `scenes/ui/main/CraftPathView.gd`

**Step 1:** Run Godot in headless editor mode to parse the project and scene.

**Step 2:** Check that all caller-facing methods and signals remain compatible.

**Step 3:** Review the final diff and confirm no unrelated user changes were overwritten.
