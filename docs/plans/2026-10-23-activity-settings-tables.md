# 活动6与7拆分专用配置表

爬天梯使用 `stair_climb.xlsx`，含 `settings` 与逐档 `rewards`；订单补给使用 `order_supply.xlsx` 的 `settings`。均以 `activity_id` 关联活动，分别导出同名JSON。活动表6、7的 `config` 清空，保留活动元数据与原数值。

服务端启动时按活动ID关联独立配置，构造内存活动定义供现有活动逻辑与客户端读取；客户端协议无需改动。缺失或重复配置、无效参数、排名奖励重叠或缺漏均报错。Excel与JSON双向脚本共享字段定义和校验，避免配置分叉。

验证覆盖原数值无损迁移、独立表参数修改影响积分/补给次数及数量、活动元数据变更生效、客户端下发配置、错误配置拒绝，以及爬天梯和订单补给回归。原活动JSON与Excel在活动1和行序上已有差异，本次各自保留，仅拆出6、7的参数。

已验证：完整Excel导出到临时目录成功，两张独立表与JSON一致；原活动JSON参数还原后与拆分前完全一致，原活动Excel除6、7的config清空外数值和样式保留；新表各工作表已渲染检查。`activity_settings_tables_smoke`、`stair_climb_smoke`、`order_supply_duplicate_actions_smoke`、`stamina_multiplier_smoke`通过。Worker项目编译命令通过（项目现有配置启用noCheck）。完整导表发现周天校验缺少defaultdict导入，已补齐；爬天梯回归的玩家升级为活动已解锁状态，路由订单改用当前订单池中的规范格式。

后续维护活动参数只修改对应独立Excel，执行`config/1_GenJson.bat`导出后重启服务端；Worker使用新JSON重新部署。活动名称、开关、起止时间与入口仍在activities.xlsx维护。
