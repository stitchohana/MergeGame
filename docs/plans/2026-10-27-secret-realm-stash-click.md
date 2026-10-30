> 2026-10-28 更新：暂存改为单格队首显示并支持连续点击、独立并行飞行；本文中分页与飞行期间阻断暂存点击的描述已由 `2026-10-28-secret-realm-stash-burst.md` 替代。棋盘拖拽仍保留动画锁定。

# Secret Realm Stash Click Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 点击秘境暂存物品飞入已揭雾空格，暂存不再支持拖拽。

**Architecture:** 沿用 `place` 服务端事务与 UID/版本/防重处理。客户端释放点击时选择视口中的第一个可用空格，用同一 `GridItem` 组件播放 0.35 秒飞入；快速回包延后至动画结束再刷新。棋盘拖拽继续复用 `BoardDragController`。

**Tech Stack:** Godot 4.6、GDScript、现有本地 HTTP 测试服务。

---

### Task 1: 点击与拖拽入口

修改 `scenes/ui/activity/SecretRealmCell.gd` 和 `SecretRealmPanel.gd`：暂存始终不提供拖拽载荷，棋盘不接收暂存拖入。按下暂存时仍记录手势，只有未超过拖拽阈值且在同一格释放才提交；选择已揭雾、无物品、无怪物的空格。满盘提示且不提交。固定属性原样提交与显示。

### Task 2: 飞入与生命周期

在 `SecretRealmPanel.gd` 的现有表现事务中创建 `GridItem` 飞入节点，使用主棋盘相同的 0.35 秒三次缓动。动画期间禁止操作、分页和刷新；快回包延后刷新；失败和关闭取消 Tween 并清理飞入节点，保持权威存档。更新操作说明。

### Task 3: 回归验证

更新 `tests/secret_realm_ui_smoke.gd`，覆盖暂存拒绝拖拽、满盘不提交、点击与拖动区分、飞入快回包、失败恢复与关闭清理。

更新 `server/tests/secret_realm_http_fixture.ts`、`tests/secret_realm_online_smoke.gd`：真实点击暂存后再从棋盘拖拽合成；保持棋盘高阶合成损失预览/取消/确认的覆盖。

运行 Godot `SecretRealmUISmoke.tscn`、`SecretRealmOnlineSmoke.tscn` 和 `BoardDragReuseSmoke.tscn`，要求退出码 0。联网测试使用隔离存储，验证每次放置只提交一次、UID 与固定属性保留。最后同步 `config/CONFIG.md` 的操作说明。

## 验证结果

已完成：暂存两端均拒绝拖拽载荷，点击选择空格后沿用服务端 `place`。保留固定标记与黑色等级文字，0.35 秒飞入支持快速回包延后刷新、失败恢复、关闭清理。

`SecretRealmUISmoke` 通过：满盘不提交、滑动回原位不误投放、忽略迷雾/怪物格、网络失败、动画位移与固定属性、快回包和中途关闭。使用 OpenGL 渲染并检查飞入中间帧，界面说明和动画节点正常。

`SecretRealmOnlineSmoke` 通过：真实 HTTP/鉴权/内存存档，共 15 次提交，覆盖点击飞入、连点/分页拦截、固定属性与 UID 保留、投放后四条链棋盘合成及高阶合成损失预览/取消/确认。`BoardDragReuseSmoke` 通过，主棋盘起拖、跟手、回弹、固定源限制与合成请求不受影响。未修改服务端玩法规则或配置表，未部署。
