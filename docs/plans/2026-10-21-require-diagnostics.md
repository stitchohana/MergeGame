# 配方提示与 require 标记诊断日志

状态：问题修复后已按用户要求移除临时日志及 RequireDiagnostics 工具。以下内容仅保留排查记录。

默认启用临时诊断，统一前缀 `[RequireTrace]`，输出至 Godot 控制台与标准运行日志。包含递增序号、运行毫秒数及 JSON 数据，同一事件/物品状态不变时不重复打印。可将 `scripts/utils/RequireDiagnostics.gd` 的 `enabled` 改为 false 关闭。

- `require_recipe_choice`：require 算法的候选配方、泉水材料数、缺失材料数、选中配方。
- `dependency_reserved`：材料因已存入支持配方的制作台而不再标记。
- `require_refresh`：订单原始结构、各目标的成品覆盖和材料占用、完整 require ID 集合、棋盘各物品 UID/位置/标记请求值/实际可见值、节点是否缺失、全棋盘制作台配方分配及储物袋物品。
- `detail_recipe_preview` / `detail_output_shown`：详情面板实际选中配方、显示产物、展示原因、已存材料及制作台分配。
- `material_hint_gate`：点击/拖动材料时是否因没有 require 标记而提前停止提示。
- `material_hint_assignments` / `table_material_acceptance`：带当前材料过滤的制作台配方分配、每台接受或拒绝该材料的原因。

复现时保留出现异常前、放入泉水后两段 `[RequireTrace]` 日志；物品/配方 ID、制作台 UID 可跨事件关联。重点比较 `detail_recipe_preview.selected_recipe` 与 `require_recipe_choice.selected`，以及 `require_refresh.targets.reserved_materials` 和 `board_badges.reason`。本次仅增加日志，不改变配方选择或标记规则。

验证：Godot `CraftHintRecipeConsistencySmoke`、`CraftMaterialReservationSmoke`、`ForgeRecipePreviewDedupSmoke` 均通过，实际输出包含配方选择、材料占用、标记状态、详情产物和材料入口日志。检查无脚本错误；运行环境仍有既有根证书读取提示。
