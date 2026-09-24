# 双轨战令活动实施计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 为游戏增加限时双轨战令活动：完成订单获得战令积分，免费轨道始终可领取，消耗灵石解锁进阶轨道。

**Architecture:** 服务端以活动 ID 隔离保存积分、进阶解锁和各轨道领奖记录；只有服务端成功完成订单时才按配置发放战令积分。战令配置通过独立 JSON 表供 Godot 与服务端共同读取，领奖和解锁走用户串行化的服务端接口，客户端活动页仅展示状态和发起请求。

**Tech Stack:** Godot 4 / GDScript、TypeScript、现有 `GameEngine` 与 `game` 路由、JSON 配置、现有 `CloudService` 与 `UIManager`。

---

## 已确认的玩法规则

- 战令积分是 `tokens.json` 中配置的专用代币（token ID 5）；积分数值按战令活动 ID 分开持久化，不混入灵石余额，也不允许兑换或消耗。
- 每次服务端成功完成一笔灵脉订单，按订单配置价值换算战令积分：`floor(order.total_value * points_per_value)`；失败、重复提交和其他来源的奖励不产生积分。`points_per_value` 由 `game_config.json` 的战令常量控制。
- 免费轨道无需解锁。达到等级所需积分后，免费奖励可逐级领取。
- 消耗配置数量的灵石解锁本期进阶轨道；解锁后，对已达到条件的等级开放进阶奖励，避免玩家先完成订单、后解锁时损失进度。
- 进阶解锁和领取均由服务端校验、扣款/发奖、写入状态后再响应；重复请求不得重复扣费或领奖。
- 活动起止时间只配置在 `activities.json`，战令配置通过 `activity_id` 引用对应活动，不重复配置时间。
- 首期活动周期为一个月，配置为 2026 年 9 月 1 日至 9 月 30 日（北京时间），活动表已启用。
- 首期配置为 50 级；每级门槛递增 10 积分，免费线与进阶线每级各奖励 10 点体力；`game_config.json` 中的 `points_per_value` 为 0.1，进阶解锁成本为 500 灵石。
- 首期仅启用一个战令活动；玩家状态仍按活动 ID 保存，以便未来开新赛季时隔离积分与领奖记录。
- 活动结束立即停止加积分和进阶解锁；服务端自动结算并发放所有已达积分门槛、但尚未领取的奖励。免费轨道始终符合资格；进阶轨道仅在玩家已解锁时符合资格；未达到门槛的奖励不发放。
- 自动结算必须幂等：写入对应等级已领取状态与奖励，并持久化成功后才结束处理；重试不可重复发奖。

## 配置与状态草案

config/json_output/battle_pass.json 由服务端和 Godot 加载。首期只配置一个 pass，含 50 个等级；门槛依次为 10、20……500 积分，每级的免费与进阶奖励均暂定为 10 点体力。pass 配置包含 activity_id、points_token_id 和 tiers；积分倍率 0.1 与进阶线解锁价格 500 统一维护在 game_config.json 的 battle_pass 常量中。服务端读取订单 total_value 并使用 floor(order.total_value * points_per_value) 计算积分；非正价值或非正积分倍率不发积分。奖励沿用现有 RewardConfig 格式。起止时间与显示名只从 activities.json 读取；首期活动已启用，时间为北京时间 2026 年 9 月 1 日至 9 月 30 日，widget 指向 BattlePass。

玩家状态新增 `battle_pass_progress`，结构为 `{ [activityId]: { points, premium_unlocked, free_claimed_levels, premium_claimed_levels } }`。新存档初始化为空对象，旧存档通过惰性迁移补默认值。战令进度是代币余额的活动专用账本，不建立通用可花费代币系统。

## 实施任务

### Task 1：定义并加载战令配置

**Files:**
- Modify: `config/json_output/tokens.json`
- Create: `config/json_output/battle_pass.json`
- Modify: `autoload/ConfigDatabase.gd`
- Modify: `server/src/worker/config_data.ts`
- Modify: `server/src/engine/config_tables.ts`
- Modify: `config/CONFIG.md`
- Test: `server/tests/battle_pass_config_smoke.ts`

**Steps:**
1. 先检查现有 token ID，新增战令积分元数据并选用无冲突 ID；新增一份示例战令配置，数值作为配置字段，不在逻辑中硬编码。
2. 将 `battlePass` 加入服务端 `GameConfigTables` 和 `gameConfigTables`；在 `ConfigDatabase` 中加载该 JSON 并提供按活动 ID 查询的方法。
3. 为配置增加校验：首期仅一个启用战令、活动 ID 必须存在且不在战令表重复、活动表是唯一时间来源、积分代币存在、全局 `points_per_value` 为正数、解锁成本和等级门槛非负、等级唯一且递增、奖励结构有效。
4. 编写配置 smoke test，验证加载、查询、冲突/无效值拒绝；运行 `cd server && npm run build` 和该 smoke test。

### Task 2：服务端状态与订单积分

**Files:**
- Modify: `server/src/storage/interface.ts`
- Modify: `server/src/engine/game_engine.ts`
- Modify: `server/src/routes/game.ts`
- Test: `server/tests/battle_pass_order_points_smoke.ts`

**Steps:**
1. 给 `GameState` 添加可选 `battle_pass_progress` 类型；新存档创建空映射，`getOrCreateState` 为旧存档惰性迁移。
2. 在 `completeMeridianAcupoint` 成功路径中，订单已通过校验并确定当前有效战令后，按 `floor(order.total_value * points_per_value)` 增加配置代币；不得在订单失败、已完成订单或非战令活动期间发放。
3. 仅在 `activities.json` 的活动有效时间内发放积分；按活动 ID 累加，单个订单只结算一次。把最新积分/可用等级状态纳入订单完成响应和游戏状态响应。
4. 测试不同订单价值按比例/取整加分、低价值取整为 0、错误订单不加分、重复完成不加分、活动未开始/过期不加分、并行串行队列下积分单次结算及存档持久化。
5. 运行 `cd server && npm run build` 和 `npx tsx tests/battle_pass_order_points_smoke.ts`。

### Task 3：进阶解锁、轨道领奖与结束自动结算

**Files:**
- Modify: `server/src/routes/game.ts`
- Modify: `server/src/engine/game_engine.ts`
- Modify: `server/src/storage/interface.ts`
- Test: `server/tests/battle_pass_claim_smoke.ts`

**Steps:**
1. 新增解锁接口，例如 `POST /api/game/battle_pass/unlock`，参数为活动 ID；活动时间只从 `activities.json` 判断，在有效期内验证 pass、验证灵石余额、扣除配置成本、置 `premium_unlocked` 并一次性保存。
2. 已解锁时以幂等响应返回，不再次扣灵石；余额不足、活动过期或 ID 无效时不改变任何状态。
3. 新增领奖接口，例如 `POST /api/game/battle_pass/claim`，参数为活动 ID、等级、轨道；校验积分门槛、免费/进阶权限、奖励定义和是否已领取，再应用奖励并记录领取状态。
4. 免费轨道无需解锁；进阶轨道必须已解锁。重复领奖不能重复发奖；项目队列保证同用户操作串行，状态保存成功后才确认。
5. 新增 `settleExpiredBattlePassRewards(state)` 幂等结算：活动达到 `activities.json` 结束时间后，自动应用所有已达积分门槛的未领取免费奖励；玩家已解锁进阶线时也自动应用对应进阶奖励。复用 `applyRewards`，物品按现有规则进入 `pending_rewards`。
6. 在获取/创建状态路径及状态接口调用结束结算；若有发奖或领奖标记变化，先保存玩家状态再返回。到期活动不可再加分、解锁或手动领取；若到期结算保存失败，不返回“已结算”结果，并确保后续请求可安全重试。
7. 响应返回完整战令进度、灵石余额和现有 `pending_rewards`/货币奖励字段，保证客户端刷新一致。
8. 覆盖合法领取、积分不足、未解锁进阶领取、重复领取、重复解锁、余额不足、活动到期自动领两轨已达成奖励、未达成奖励不领、未解锁进阶奖励不领、结算重试不重复发奖和物品奖励进待领取区等测试；运行服务端构建与 smoke test。

### Task 4：同步状态及客户端请求

**Files:**
- Modify: `autoload/GameState.gd`
- Modify: `autoload/SaveManager.gd`
- Modify: `autoload/CloudService.gd`
- Modify: `autoload/ConfigDatabase.gd`
- Test: `tests/battle_pass_state_smoke.gd`

**Steps:**
1. 在 `GameState` 增加战令状态缓存与状态变更信号；由登录恢复及每次 `state_loaded` 同步活动定义、积分、已解锁状态和领取列表。
2. 在 `CloudService` 注册 unlock/claim 请求 endpoint、提交方法、成功/失败信号；成功响应时同步进度、灵石、 pending rewards。
3. 订单完成回包更新对应战令活动积分，避免等待额外状态请求；失败回包不改本地已确认进度。
4. 测试旧存档缺省、新状态反序列化、订单响应同步、解锁/领奖成功与拒绝响应恢复。

### Task 5：Home 活动入口与双轨战令界面

**Files:**
- Modify: `scenes/ui/activity/HomeActivityCard.gd`
- Modify: `scenes/ui/activity/HomeActivityCard.tscn`
- Create: `scenes/ui/activity/BattlePassPanel.gd`
- Create: `scenes/ui/activity/BattlePassPanel.tscn`
- Create: `scenes/ui/activity/BattlePassTier.gd`
- Create: `scenes/ui/activity/BattlePassTier.tscn`
- Test: `tests/battle_pass_ui_smoke.gd`

**Steps:**
1. 在活动表中只启用首期这一项战令，并配置 `widget` 为 `BattlePass`；Home 活动卡点击后打开战令面板。
2. 面板展示活动名/活动表配置的截止时间、积分代币图标与余额、等级进度、免费/进阶双列奖励轨道、已领/可领/未解锁状态。
3. 活动进行中，达标免费奖励显示领取按钮；进阶轨道未解锁时显示灵石价格和解锁确认，已解锁后逐级显示领奖按钮。活动结束后显示结束态及自动结算结果，不再出现手动领取/解锁入口。
4. 请求等待期间禁用对应操作，成功后使用服务端返回状态刷新；失败时恢复按钮并提示余额不足/活动结束/奖励已领等可读信息。
5. 复用现有 `WeeklyRewardIcon` 或 `RewardSlot` 展示 token/item 奖励；长等级列表可滚动，避免遮挡 Home 两侧列表。
6. 验证触屏尺寸、长活动名、空状态、活动结束状态、服务端拒绝和滚动；Godot 可用时运行 `godot --headless --path . --editor --quit` 及 `tests/battle_pass_ui_smoke.gd`。

### Task 6：配置表生成与交付回归

**Files:**
- Modify: `config/CONFIG.md`
- Modify: `server/dist/worker/config_data.js`（仅若项目要求提交编译产物）
- Test: `server/tests/battle_pass_config_smoke.ts`
- Test: `server/tests/battle_pass_order_points_smoke.ts`
- Test: `server/tests/battle_pass_claim_smoke.ts`

**Steps:**
1. 活动起止时间只维护于 `activities.json` 对应工作簿；战令配置工作簿不再保存第二份时间字段。确认活动表与战令等级/积分倍率文档一致。
2. 运行全部战令服务端 smoke test、`cd server && npm run build`、`git diff --check`。
3. 手动验证完整闭环：按订单价值加积分 → 免费奖励领取 → 灵石解锁 → 领取进阶奖励 → 活动结束后自动发放所有已达标未领奖励 → 重启/重新登录不重复发奖。

## 验收标准

- 只有服务端确认的订单完成可增加当前有效战令的积分，客户端无法伪造积分或领奖。
- 战令积分使用 token 配置的图标与名称展示，按赛季隔离且不与灵石/其他代币混算。
- 免费轨道始终可用；进阶轨道只能通过服务端扣除配置灵石解锁一次。
- 解锁后能领取已达积分等级的进阶奖励；两条轨道的领奖记录独立，重复请求不会重复发奖。
- 活动时间只由 `activities.json` 控制；结束后停止加积分和解锁，并自动领取已达标但未领取的奖励，重复结算不重复发放。
- 状态重载、断线重试和旧玩家存档迁移后数据一致。

## 配置阶段待填写

- 首期活动配置为 2026 年 9 月 1 日至 9 月 30 日，活动表启用；其他暂定数值已落入战令配置或 game_config 常量。结算公式固定为 floor(order.total_value * points_per_value)，不在代码中硬编码平衡数值。
