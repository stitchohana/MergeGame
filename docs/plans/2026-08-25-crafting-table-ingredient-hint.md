# Crafting Table Ingredient Hint Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 点击或拖拽棋盘上带 require 标记的物品时，在可接收该物品的制作台上方显示带物品图标的晃动气泡。

**Architecture:** 每个 `GridItem` 自带一个默认隐藏的制作提示气泡，由 `GridView` 统一控制显示周期。`CraftingController` 提供无副作用的接收判定，确保提示结果与实际拖入制作台的规则一致。

**Tech Stack:** Godot 4、GDScript、TSCN、现有配置驱动配方系统。

---

### Task 1: 增加无副作用的制作台接收判定

**Files:**
- Modify: `scenes/grid/CraftingController.gd`

**Step 1:** 添加 `can_accept_ingredient(table_item, ingredient_id)`，检查制作状态、配方包含关系、重复材料以及与已放材料的配方兼容性。

**Step 2:** 保持 `try_add_ingredient` 的服务端提交和错误提示行为不变。

### Task 2: 增加制作提示气泡

**Files:**
- Modify: `scenes/items/GridItem.tscn`
- Modify: `scenes/items/GridItem.gd`

**Step 1:** 在物品节点上方增加圆角气泡、物品图标和气泡尾部，默认隐藏且忽略鼠标输入。

**Step 2:** 添加 `is_required()`、`show_crafting_hint(texture)` 与 `hide_crafting_hint()`，显示时循环左右轻晃。

### Task 3: 接入点击与拖拽生命周期

**Files:**
- Modify: `scenes/grid/GridView.gd`

**Step 1:** 点击带 require 标记的物品时，查找所有可接收它的制作台并显示 1.5 秒。

**Step 2:** 开始拖拽时持续显示提示，结束、取消或切换物品时立即清理。

**Step 3:** 普通物品、不可用制作台和不兼容的已放材料不显示提示。

### Task 4: 验证

**Files:**
- Verify: `scenes/grid/CraftingController.gd`
- Verify: `scenes/items/GridItem.gd`
- Verify: `scenes/items/GridItem.tscn`
- Verify: `scenes/grid/GridView.gd`

**Step 1:** 运行 Godot 无界面项目加载，确认脚本和场景无解析错误。

**Step 2:** 在主棋盘分别点击、拖拽 require 物品，确认只有对应可用制作台显示正确图标；拖拽结束后气泡消失。
