# GM 清理所有棋盘普通物品

- GM 面板新增“清理所有棋盘普通物品”，命令键 `clear_board_items`，无需数值参数。
- 服务端沿用 GM 鉴权、用户操作队列和状态持久化，一次处理当前棋盘及 `saved_grid`、`battle_grid` 缓存。共享数组只处理一次。
- 保留配置类型为发射器（1）、制作台（2），或具有发射器配置的物品；其位置、UID、材料、制作状态等数据保留。其余棋盘物品移除，包括不可移动的普通物品。储物袋与待领取奖励不属于棋盘，不清理。
- 返回 `removed_count` 与中文清理结果；发生移除时递增状态版本。客户端沿用拉取状态同步，并支持空棋盘结果。
- 验证包含主/战斗棋盘切换、缓存共享数组、重复执行、设施数据保留、鉴权与保存，以及 Godot GM 入口和空棋盘同步。
- 状态接口将“已有空主棋盘缓存”与“未初始化缓存”区分，避免清理后拉取状态重建初始物品。

验证结果：`GM_CLEAR_BOARD_ITEMS_SMOKE_OK`、Godot `GMClearBoardItemsSmoke`、既有 `gm_battle_pass_points_smoke` 和 `npm run worker:check` 通过。新增服务端测试覆盖 `/exec` 到保存再到 `/state` 的同步链路。tsx 的 esbuild 子进程被沙箱阻止，自动提权审批服务返回令牌权限 403；使用本地 TypeScript `transpileModule` 在同一 Node 进程运行测试通过。

额外执行的既有 `gm_grant_order_items_smoke` 在订单刷新数量断言失败（预期 7，当前配置返回 4），该测试未修改，本次不宣称通过。未部署或对实际玩家执行清理。
