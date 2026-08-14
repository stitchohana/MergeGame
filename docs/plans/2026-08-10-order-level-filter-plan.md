# 订单境界等级过滤 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 按当前修为境界限制动态订单中的副产物与制作台产物等级。

**Architecture:** 在 `meridians.json.order_pool` 配置修为等级区间和两类订单来源的物品等级范围。服务端根据 `cultivation.current_level` 选择适用规则，只对动态随机订单候选进行过滤；固定引导订单继续读取 `fixed_orders`。

**Tech Stack:** TypeScript/Godot worker、JSON 配置、Python XLSX 转换脚本、tsx 检查脚本。

---

### Task 1: 添加可配置等级规则

**Files:**
- Modify: `config/json_output/meridians.json`
- Modify: `config/xlsx_to_json.py`
- Modify: `config/CONFIG.md`

规则：练气 `current_level=2..10`，副产物 4 级、制作台产物 1–4 级；筑基 `11..13`，副产物 7–8 级、制作台产物 5–8 级；金丹 `14..16`，副产物 10–12 级、制作台产物 9–12 级；元婴 `17..19`，副产物 13–16 级、制作台产物 13–16 级。设施奖励同步按练气4级、筑基8级、金丹12级、元婴16级逐段补齐，设施种类在筑基阶段完成解锁。

### Task 2: 应用动态订单过滤

**Files:**
- Modify: `server/src/engine/game_engine.ts`

加载 `order_pool.level_ranges`，在计算已解锁设施产出时同时检查来源类型、物品等级和当前修为等级；没有匹配境界规则时保持已有候选逻辑。

### Task 3: 验证

运行 worker 类型检查、JSON/Python 语法检查，并用 `tsx` 构造不同修为等级的状态，确认四个境界的候选等级集合符合配置，固定订单仍可生成。
