# Grant Order Items GM Command Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 新增一条 GM 命令，将当前未完成订单列表所需的全部道具下发到待领取奖励队列。

**Architecture:** GM 路由从服务端权威状态的 `meridian_acupoints` 读取未完成订单，展开每条订单的 `item_ids`，为每个有效道具生成独立 UID 后写入 `pending_rewards`。Godot GM 面板只增加命令入口，执行成功后继续复用现有 `fetch_state()` 同步奖励队列。

**Tech Stack:** TypeScript、Godot 4 GDScript/TSCN、现有 Worker 类型检查与 `tsx`。

---

### Task 1: 实现服务端 GM 命令

**Files:**
- Modify: `server/src/routes/gm.ts`

**Step 1: 添加 `grant_order_items` 分支**

遍历 `state.meridian_acupoints || []`，跳过 `completed === true` 的订单；对每个 `item_ids` 元素做整数与物品配置校验，然后追加：

```ts
state.pending_rewards.push({
  uid: engine._nextUid(state),
  id: itemId,
  name: itemDef.name ?? `#${itemId}`,
});
```

返回实际下发总数和按物品 ID 汇总的数量；没有可下发道具时返回 `no_order_items`。

**Step 2: 更新未知命令提示**

将 `grant_order_items` 加入 `unknown_cmd` 返回的 `cmds` 数组。

### Task 2: 增加 Godot GM 面板入口

**Files:**
- Modify: `scenes/ui/other/GMPanel.tscn`
- Modify: `scenes/ui/other/GMPanel.gd`

**Step 1: 添加选项**

在 `CmdOption` 末尾添加“下发订单道具”，并把 `item_count` 增加到 10。

**Step 2: 映射命令**

选中新增索引时提交 `grant_order_items`；该命令不读取数值输入。

### Task 3: 验证

**Files:**
- Verify: `server/src/routes/gm.ts`
- Verify: `scenes/ui/other/GMPanel.gd`
- Verify: `scenes/ui/other/GMPanel.tscn`

**Step 1: 服务端类型检查**

Run: `npm.cmd run worker:check`

Expected: TypeScript 编译通过。

**Step 2: 路由行为冒烟测试**

使用内存状态构造多个订单（包含已完成订单和重复道具），调用 GM 路由后确认：仅未完成订单被展开、重复数量保留、每项 UID 唯一、状态被保存。

**Step 3: Godot 语法检查**

Run: `godot --headless --path . --editor --quit`

Expected: 项目可无界面加载且新增 GDScript/TSCN 无解析错误。
