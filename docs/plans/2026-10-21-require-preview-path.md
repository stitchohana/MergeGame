# 配方预览与 require 路径一致性修复

用户日志中，制作台 UID 4635（青砖丹灶，2,7）已存入青禾米，预览为配方 32（青禾米＋玉壶露，产物 27081）。require 算法却因优先选择较少泉水材料的替代配方，选中了配方 81（青禾米＋青纹石），导致棋盘玉壶露未显示 require，点击材料提示入口也以 `source_has_no_require_badge` 拒绝。

`GameScreen._refresh_required_indicators()` 现在每次刷新只构建一次全棋盘制作台配方分配，并将已分配配方传入订单材料收集及递归依赖展开。存在制作台分配时，require 跟随同一配方；没有分配时保留原有回退选择规则。全棋盘配方去重逻辑保持有效。日志新增 `selection_rule: board_recipe_assignment`，且刷新快照复用实际用于标记的分配结果。

日志回放夹具 `tests/fixtures/require_preview_path_trace.json` 保留相关订单、制作台 UID、已存材料、棋盘位置与储物袋状态，排除已被覆盖的无关订单及其制作台。回归覆盖：已存青禾米、空台放入前、通过真实服务放入后、其他制作台储存同类泉水、补齐材料、制作中、待取出和递归依赖。空台详情面板按现有行为不显示产物槽，分配与材料目标提示仍需匹配配方 32。

验证通过（Godot 4.6.1 headless，均检查成功标记及无脚本错误/断言失败）：

- RequirePreviewPathTraceSmoke
- CraftMaterialReservationSmoke
- CraftHintRecipeConsistencySmoke
- CraftHintWaterTraceSmoke
- ForgeRecipePreviewDedupSmoke
- CraftHintCoveredProductsSmoke
- CraftingHintSmoke

问题修复后已按用户要求移除 `[RequireTrace]` 临时诊断日志、快照构造与工具脚本，保留配方一致性修复及日志回放回归测试。运行环境既有根证书读取提示与本次修改无关。
