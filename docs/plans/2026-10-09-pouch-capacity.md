# Pouch Capacity Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 储物袋默认开放 7 格，使用灵石逐格解锁，费用逐次递增且数值可配置。

**Architecture:** 服务端保存 pouch_capacity 并计算权威解锁价格；每次解锁请求带 expected_capacity，重复或过时请求不会重复扣费。客户端仅展示服务端容量和价格，存满时不移除棋盘物品。旧存档容量至少覆盖原有物品数量，不丢失物品。

**Tech Stack:** Godot 4 / GDScript、TypeScript Worker、JSON 状态、game_config.xlsx → JSON。

---

### Task 1: 可配置容量与费用
- 修改 config/xlsx/game_config.xlsx 和 config/json_output/game_config.json：pouch.initial_slots=7、unlock_cost_base=100、unlock_cost_increment=50。
- 更新 config/CONFIG.md，说明第 n 次付费解锁为 base + (n-1) × increment。
- 保留配置表现有数据和样式，确认导出键值一致。

### Task 2: 权威存储与解锁
- 修改 server/src/storage/interface.ts、server/src/engine/game_engine.ts、server/src/routes/game.ts。
- 新存档初始化容量，旧存档迁移容量；存入前检查满格；解锁校验余额和 expected_capacity，再同一次持久化扣费和扩容。
- 状态和存取响应包含 pouch_capacity / pouch_next_unlock_cost。
- server/tests/pouch_capacity_smoke.ts 覆盖满格、递增费用、余额不足、旧存档、重复请求、存档失败及重载。

### Task 3: 客户端与界面
- 修改 autoload/CloudService.gd、autoload/StoragePouch.gd、autoload/SaveManager.gd。
- 修改 scenes/ui/main/PouchPopup.gd / .tscn、PouchDropZone.gd 和 scenes/grid/GridView.gd。
- 展示已用/总容量、空格与下一格解锁按钮；请求期间防止重复提交，失败显示中文提示并恢复状态。
- 物品列表使用滚动容器支持持续扩容。

### Task 4: 验证
- 执行服务端容量/路由烟测与 npm run worker:check。
- 执行 Godot 储物袋 UI 烟测，验证 7 空格、价格、更新、按钮防连点。
- 生成并检查弹窗截图；确认修改未覆盖工作区已有变更。
