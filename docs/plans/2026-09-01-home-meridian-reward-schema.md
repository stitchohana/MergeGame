# 家园经脉奖励结构迁移计划

## 目标

移除穴位设施奖励和全局生产奖励表，将设施奖励统一放入阶段周天奖励；初始教程设施直接由初始棋盘提供；把 `circulation_exp` 改为 `circulation_reward`，同时保留穴位经验/体力和周天经验/体力的进度预算。周天扩展为 666 个，每个周天发放两个按境界递增等级的设施，突破只发放 1 级灵石矿。

## 实施步骤

1. 修改 `home_meridians.xlsx` 导出/反向导出逻辑：删除 `acupoint_rewards` 列，将 `circulation_exp` 列改为 `circulation_reward`，增加 `cultivation_level` 列，并把两个设施项目写进每个阶段的周天奖励。
2. 将凡人阶段原有的三个教程设施加入 `initial_setup.xlsx`/`initial_setup.json`，并让穴位奖励由 `acupoint_exp` 统一生成，不再读取穴位奖励配置。
3. 删除 `home_meridians.json` 顶层 `production_rewards`、`production_reward_rules`，让服务端只读取阶段的 `circulation_reward` 并在周天完成时发放经验和设施。
4. 更新客户端奖励预览、配置文档和余额同步脚本，移除旧字段引用。
5. 重新生成 JSON，按境界约束设施等级和依赖顺序，构造服务端冒烟校验，运行 TypeScript 构建和 Godot 解析检查。

## 验收

- home meridian workbook header 为 `cultivation_level, name, acupoints, qi_cost, acupoint_exp, circulation_reward`。
- 每个阶段 JSON 无 `acupoint_rewards`，有包含 token 4 经验、token 3 体力的 `circulation_reward`。
- home JSON 无全局生产奖励表；共 666 个周天，每个周天恰好两个非矿设施奖励。
- 13 个设施族群在练气期内全部出现，设施等级上限按练气 4、筑基 8、金丹 12、元婴 16 执行。
- 前 19 个突破奖励各发放一个 `25001` 1 级灵石矿，突破奖励不再额外发放设施。
- 初始棋盘包含 12001、17001、16001 教程设施，且服务端周天完成仍发放相应阶段设施。
- 凡人和练气期每个周天均为 4 个穴位；前期按层级降低单穴位消耗与经验，凡人总经验 12，低于练气一层的 48。
