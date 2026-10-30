# 秘境提交图标与攻击掉落动画 Implementation Plan

**Goal:** 怪物格上方按已提交件数显示飞剑和剑气，集齐后播放攻击、消失、掉落动画。

**Architecture:** `SecretRealmCell.gd` 根据服务端 submitted 和物品定义绘制逐件图标。`SecretRealmEffects.gd` 作为纯 Control 表现层，在确认结算后依次演出攻击、怪物消失、所有新增掉落的散落弹出；服务端结算返回精确的掉落实例、推进前坐标及暂存标记，并随防重回执保存用于重试。`SecretRealmPanel.gd` 按 request_id 匹配演出，结束后再显示权威视图并推进地图。失败不播放成功演出，关闭清理 Tween。

**Tech Stack:** Godot 4 GDScript、TextureRect、Tween，沿用现有飞剑/剑气/资源 SVG，TypeScript 在现有发奖分支记录动画数据，不改消耗与奖励数值。

### Task 1: 提交显示

- 修改 `scenes/ui/activity/SecretRealmCell.gd`，增加可查询的逐件小图标层，按需求顺序排列，飞剑六把及剑气一份可换行，显示黑色等级文字，迷雾不显示。
- `SecretRealmPanel.gd` 注入物品定义；部分提交确认后立即恢复图标，最终提交补齐图标后演出。
- 新增 `tests/SecretRealmEffectsUISmoke.tscn` / `tests/secret_realm_effects_ui_smoke.gd` 验证数量、类型、重开和迷雾。

### Task 2: 攻击与掉落演出

- 新建 `scenes/ui/activity/SecretRealmEffects.gd`，飞剑与剑气从提交栏汇聚攻击、闪光、怪物淡出缩小；每个新增掉落沿弧线散落并弹入，暂存溢出奖励飞向暂存栏。
- 修改 `server/src/engine/secret_realm.ts`，从实际 grant 收集动画数据，预览、丢失奖励不返回可播放事件；回执重放返回同一份 manifest。`autoload/CloudService.gd` 仅转发秘境事件字典。
- Panel 在服务器确认后演出；合成产物不误判为掉落，移动、预置揭雾和失败不播放掉落。演出期间阻止重复操作、延迟视图刷新，结束后应用最新权威视图，Boss 再推进。
- 测试合成多掉落、战斗完整顺序、Boss 推进、暂存奖励、UID 去重、失败回滚及关闭清理。

### Task 3: 回归和视觉检查

- Godot headless 运行 EffectsUISmoke、SecretRealmUISmoke、SecretRealmPushUISmoke。
- 本地 HTTP fixture 运行 SecretRealmCombatOnlineSmoke 与 SecretRealmOnlineSmoke，覆盖真实指针提交、重开、击败和合成奖励。
- 尽可能捕获动画帧检查视觉及显示边界；更新 `config/CONFIG.md` 和本文件验证结果。不提交、部署或改动数值配置。

## 验证结果

- `SECRET_REALM_EFFECTS_SMOKE_OK`：实际发放与事件一致，隐藏预置物品、只读预览、丢失奖励不误报，部分/完整提交、暂存溢出、Boss 推进前位置、回执重放通过。
- `SECRET_REALM_EFFECTS_UI_SMOKE_OK`：逐件图标与换行、剑气图标、迷雾遮挡、存档恢复、攻击→消失→掉落顺序、固定/暂存掉落、重复回包、失败恢复、Boss 延后滚动、关闭清理通过。
- `SECRET_REALM_UI_SMOKE_OK`、`SECRET_REALM_PUSH_UI_SMOKE_OK`、服务端 `secret_realm_smoke` 和 `SECRET_REALM_MERGE_SPACE_SMOKE_OK` 回归通过。
- `SECRET_REALM_ONLINE_SMOKE_OK`：本地认证 HTTP 下 15 次真实指针操作，包括合成空间确认、取消/确认、暂存飞入与连续点击拦截，通过。
- `SECRET_REALM_COMBAT_ONLINE_SMOKE_OK`：本地认证 HTTP 下逐件提交、重开恢复、拒收、击败与 Boss 推进通过；增强检查实际图标和三个演出阶段、全部 12 件奖励动画。
- Worker 配置编译检查通过（项目配置为 noCheck，不代表全量严格类型检查）。
- 用 Vulkan 实际渲染并检查 `.codex_tmp/realm-effects-submitted.png`、`realm-effects-attack.png`、`realm-effects-drops.png`；修正新图标的等级显示为整数。

未部署。服务端应重启或重新部署以返回新事件；消耗、奖励与地图数值均未调整。

后续调整：掉落演出统一提速为 2 倍，包括逐件间隔、显现、弧线散落、落地弹入及飞入暂存的淡出，整体等待由 0.72 秒缩短为 0.36 秒。攻击和怪物消失时长不变，动画期间继续禁止拖拽。
