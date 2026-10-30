> 2026-10-28 约定更新：本文中的旧存档/旧格式兼容、历史回填和增量数据库迁移方案已废止。仅支持当前结构；新库统一使用 `server/schema.sql`，功能首次解锁与正常周期结算仍保留。

# 储物袋参与持有物品判断：实施与审计

目标：订单可提交、缺失、勾选、配方推荐、来源发现均基于棋盘与储物袋；服务端校验和扣除一致。物理空位、拖拽坐标、点击生成及制作台操作仍使用棋盘坐标。

1. GridManager 提供统一持有物品集合和数量，带来源、UID、位置；主棋盘未加载时使用缓存，转移期间按 UID 去重。
2. GameScreen 订单统计、勾选、成品/材料缺失、制作状态、动画源接入统一集合。储物袋变化触发刷新。提交响应恢复储物袋，保留数量和容量。
3. ItemDetailPanel 的配方推荐和材料缺失计数，以及 RecipePopup / RecipeSourcePopup / CraftPathView 的制作台、发射器、发现判断统一包含储物袋。
4. 服务端订单提交先完整匹配棋盘+储物袋实例，再一次性扣除；失败不部分扣除，重复 ID 按份数计，响应返回储物袋。
5. 复查突破、订单补给、生产设施可用池、发现、任务/活动判断与同步；储物袋保留物品实例元数据，避免存入后丢失制作材料、冷却或攻击信息。
6. 回归测试：仅储物袋、混合来源、重复 ID 不足/足够、固定棋盘物品、满棋盘提交、存取即时刷新、失败不扣物品、旧存档、制作推荐、来源提示、元数据与棋盘空位隔离。

审计范围：autoload/、scenes/、scripts/ 中的持有物品/物理网格调用；server/src/engine/ 与 routes/ 中 state.grid / state.pouch 访问。验证结果完成后补充于下。

## 完成范围

- `GridManager.get_inventory_items()` / `get_inventory_item_counts()`：棋盘与储物袋统一集合，按有效 UID 去重，旧数字格式按独立槽位计数。来源视图在战斗棋盘打开时使用主棋盘缓存。离开主棋盘时保存包含 UID、制作、充能、仓库和攻击数据的当前缓存。
- GameScreen：订单可提交、排序、按份数勾选、成品缺失、制作中标记及材料提示均统计储物袋。储物袋更新触发合并刷新。提交动画从储物袋入口飞出，确认响应同步储物袋及主棋盘缓存。
- ItemDetailPanel、RecipePopup、RecipeSourcePopup、CraftPathView：配方推荐、制作材料数量、已有成品、当前持有制作台/发射器和发现判断包括储物袋，储物袋变化刷新打开的视图。实际制作台中的材料完整性仍以已经放入的材料判断。
- 服务端订单提交跨来源匹配完整数量，再扣除具体实例；固定物品不可提交，满棋盘可直接消耗储物袋，失败不部分扣除，响应包含储物袋及容量。请求重放规则保留。
- 服务端随机订单生产池、订单补给缺失和发射器订单优先权使用统一持有集合。突破原有逻辑已支持储物袋，混合来源回归通过。任务/活动进度按事件计数，无另一个持有物品条件入口。
- 储物袋存取保留实例全部元数据；存放的制作台和发射器继续按服务端时间推进制作及充能，取出返回完整实例和更新后的冷却时间。
- 空棋盘是有效存档，读取状态/切换棋盘不会重新生成初始物品。

保留物理网格语义的调用已检查：空位/容量、位置与 UID 查找、拖动/合并/移动、可合并判断、实际生成、制作台点击/放入/取出、棋盘仓库操作、使用物品、出售/删除、棋盘可视节点、主棋盘发射器批次刷新和活动奖励落点。这些操作需要物品位于真实棋盘，储物袋物品需先取出；仅持有统计、订单提交和突破材料可跨来源。

## 验证

- 新增 `server/tests/pouch_inventory_smoke.ts`：纯储物袋、混合来源、重复 ID/UID、固定物品、旧存档、满棋盘、灵力已满/数量不足/请求错误不扣除、重复请求、持久化失败、重新读取、生产池/补给、制作/充能/攻击/仓库数据和空棋盘切换。
- 新增 `tests/PouchInventoryUISmoke.tscn`：可提交与重复勾选即时刷新、转移去重、储物袋动画来源、配方推荐与缺失标记、制作台/发射器来源、主棋盘缓存、取出元数据、订单确认后储物袋同步、物理格子数不变。
- 服务端专项与既有回归通过：pouch_capacity、breakthrough_items、order_supply、order_supply_actions、item_discovery、meridian_order_batch、order_recipe_probability、battle_pass_order_points；`npm run worker:check` 通过（仓库配置启用了 noCheck，该检查不等同完整 TypeScript 类型检查）。
- Godot 通过：新专项、InitialOrderFocus、ItemDetailGhostOutput、ItemDetailRecipeSource、PouchCapacityUI、BreakthroughItemsUI、StairClimbOrderReward。
- 新专项在渲染模式正常退出（退出码 0）。加入订单确认和场景清理验证后，headless 模式断言全部通过，但在进程关闭时 Godot 4.6.1 出现 signal 11；保留 `.codex_tmp/pouch_inventory_ui.log` 和正常渲染运行的 `.codex_tmp/pouch_inventory_visual.log`，不把 headless 关闭崩溃当作完整通过。
- 扩展回归的两个失败已记录：RequirementPriority 第 149 行要求重建后滚动位置恰好等于滚动条 max_value；CraftingHint 第 50 行要求 27081 的配方依赖 81，但当前配置的配方 32 已仅使用普通材料 5002/9004。这两处断言执行时尚未调用本次修改的储物袋统计/勾选逻辑；未修改相关滚动逻辑或配方配置。

本次未部署远端服务；线上订单结算需同步发布服务端更新。
