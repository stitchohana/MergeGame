# 配置表说明

所有配置表位于 `config/json_output/`，由 `config/xlsx/` 中的 Excel 文件通过 `config/xlsx_to_json.py` 生成。

## 1. items.json — 物品表

### ItemType 枚举

| 值 | 含义 | 说明 |
|----|------|------|
| 0 | REGULAR | 常规合并物品 |
| 1 | LAUNCHER | 发射器，双击生成物品 |
| 2 | CRAFTING | 制作台，拖入材料合成 |
| 4 | RECIPE_PRODUCT | 制作产物（丹药、阵法、飞剑等） |
| 5 | EFFECT | 效果道具（剑气、回复药等） |

### 通用字段

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | int | 唯一标识 |
| `name` | string | 物品名称 |
| `level` | int | 等级，同 group_id 内升级；`type=4` 配方产物取所需材料的最大等级 |
| `group_id` | int | 合并组，同组同 id 可合并 |
| `icon` | string | 图标路径，空字符串用默认色块 |
| `describe` | string | 描述文本 |
| `type` | int | ItemType 枚举值 |
| `value` | int | 价值 / 攻击力加成（可选） |
| `sell_price` | int | 出售灵石价格（可选） |

### 发射器字段（type=1 或任意 type 配置后即可生效）

发射能力由 `spawns` + `max_charges` 字段决定，不依赖 `type`。任何类型的物品只要配置了这两项即具备发射器行为。

| 字段 | 类型 | 说明 |
|------|------|------|
| `max_charges` | int | 最大生成次数 |
| `recharge_time` | int | CD 秒数，≤0 时耗尽消失 |
| `spawns` | array | 随机生成表 `[{id, weight}]`，weight 为权重 |
| `fixed_spawns` | int[] | 固定顺序生成（替代 spawns，可选） |
| `no_cost` | bool | true 时不消耗体力/灵力（可选） |

### 效果字段（type=5 或 type=4 可配置）

效果字段统一维护在 `items.xlsx` 的 `items_effect` 工作表中。`items_recipe_product`
只维护配方产物本体及发射器字段，不再包含 `effect_type`、`effect_value` 两列；导出时
会按 `id` 将 `type=4` 的效果配置合并回对应配方产物。

| 字段 | 类型 | 说明 |
|------|------|------|
| `effect_type` | int | 效果枚举（见下方） |
| `effect_value` | int | 效果数值 |
| `atk` | int | 物品自身攻击力（可选） |

### EffectType 枚举

| 值 | 含义 | effect_value 含义 |
|----|------|-------------------|
| 0 | 无效果 | - |
| 1 | 攻击 | 伤害倍率（剑气） |
| 2 | 治疗 | 恢复 HP 量 |
| 3 | 修为经验 | 增加修为值 |
| 4 | 体力 | 恢复体力值 |
| 5 | 突破 | 突破境界 |
| 6 | 灵力恢复 | 恢复灵力值 |
| 7 | 攻击力加成 | 飞剑等，value=ATK 加成量 |

### 飞剑（type=4 + effect_type=7）配置示例

飞剑同时是发射器和攻击力加成来源：

```json
{
  "id": 28001,
  "name": "铁木剑",
  "type": 4,
  "value": 1,
  "effect_type": 7,
  "max_charges": 5,
  "recharge_time": 60,
  "spawns": [{"id": 15101, "weight": 100}]
}
```

**机制**：飞剑双击发射剑气（effect_type=1 道具），生成时剑气记录 `atk_base = 境界atk + 飞剑value`。使用剑气攻击时，伤害 = `atk_base × 剑气effect_value`。剑气没有 `atk_base` 时无法造成伤害。

---

## 2. cultivation.json — 修炼境界表

| 字段 | 类型 | 说明 |
|------|------|------|
| `name` | string | 境界名称 |
| `exp` | int | 升级所需经验 |
| `max_qi` | int | 灵力上限 |
| `atk` | int | 攻击力 |
| `breakthrough_items` | array | 突破所需物品，XLSX 中用 `item_id:count;item_id:count` 配置（可选） |
| `breakthrough_reward_id` | int | 突破成功后发放的 reward id（可选） |

---

## 3. expedition.json — 探险表

### 怪物

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | int | 唯一标识 |
| `name` | string | 名称 |
| `hp` | int | 生命值 |
| `atk` | int | 攻击力（预留） |
| `accept_effect_types` | int[] | 可接受的效果类型（effect_type 枚举值） |
| `loot` | int[] | 掉落物品 id 列表 |
| `describe` | string | 描述 |

### 地图

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | int | 地图 ID |
| `name` | string | 名称 |
| `stages` | array | 关卡列表 |

### 关卡

| 字段 | 类型 | 说明 |
|------|------|------|
| `monsters` | array | 小怪 `[{monster_id, count}]` |
| `boss` | object | Boss `{monster_id}` |

---

## 4. quests.json — 任务表

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | int | 任务 ID |
| `type` | int | 任务类型（1=合并 2=生成 3=制作 4=出售 5=战斗...） |
| `name` | string | 名称 |
| `description` | string | 描述 |
| `target_count` | int | 目标次数 |
| `rewards` | int/Dict | 奖励配置 ID 或内联奖励 |
| `auto_reward` | bool | 是否自动发放 |
| `reset_cycle` | int | 重置周期 0=不重置 1=每日 2=每周 |

---

## 5. rewards.json — 奖励配置表

| 字段 | 类型 | 说明 |
|------|------|------|
| `tokens` | array | token 奖励 `[{token, amount}]` |
| `items` | array | 物品奖励 `[{id, count}]` |

### Token 类型

| 值 | 含义 |
|----|------|
| 1 | 经验 |
| 2 | 灵力 |
| 3 | 体力 |
| 4 | 灵石 |

---

## 6. recipes.json — 制作配方表

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | int | 配方 ID |
| `name` | string | 名称 |
| `ingredients` | int[] | 所需材料 item id 列表 |
| `result` | int | 产出 item id |
| `craft_time` | int | 制作时间（秒） |
| `crafting_level` | int | 所需制作等级 |

---

## 7. weekly_tasks.json — 周常任务表

| 字段 | 类型 | 说明 |
|------|------|------|
| `activity_id` | int | 关联的活动 ID（activities.json） |
| `daily_quests` | int[][] | 7 天 × N 个任务 ID |

---

## 8. activities.json — 活动表

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | int | 活动 ID |
| `name` | string | 名称 |
| `cycle` | int | 周期 0=一次性 1=每日 2=每周 |
| `widget` | string | 入口 widget 类名（可选） |
| `start_time` | string | 开始时间 ISO 格式（一次性活动） |
| `end_time` | string | 结束时间 ISO 格式（一次性活动） |

---

## 9. meridians.json — 经脉表

订单候选由顶层 `order_pool` 控制：`sources` 支持主产物 `items_regular`、副产物
`items_byproduct` 与配方产物 `items_recipe_product`。系统根据当前棋盘上的发射器
和制作台，从其 `spawns` 与 `recipes` 递归计算真正可制作的订单物品。发射器内按
产物链汇总权重，低于最高权重的产物链视为副产物。
`level_ranges` 按 `cultivation.current_level` 分别配置三类物品等级范围：练气为主产物
4级、副产物1–4级、配方产物1–4级；筑基为7–8级、5–8级、5–8级；金丹为
10–12级、9–12级、9–12级；元婴均为13–16级。副产物等级范围与配方产物保持一致。
固定引导订单仍优先使用 `fixed_orders` 或 `fixed_order_batches`，不经过等级过滤。
新手固定订单可在每条 `{item_ids, rewards}` 中提供显式奖励；配置了 `rewards` 时，
服务端直接发放该奖励，不再按订单物品价值进行倍率换算。

| 字段 | 类型 | 说明 |
|------|------|------|
配方产物的 `level` 在导出时按配方依赖树计算，取所需材料的最大等级；循环依赖、缺失配方或无效原料会生成空等级，订单筛选时不会进入有等级限制的候选池。

| `thresholds` | array | 阈值列表 `[{stage, count_min, count_max, acupoint_rewards, order_count, fixed_orders, fixed_order_batches}]`，不再配置 `item_pool` |

---

## 10. game_config.json — 游戏参数

| 字段 | 类型 | 说明 |
|------|------|------|
| `stamina.max` | int | 体力上限 |
| `stamina.spawn_cost` | int | 生成消耗 |
| `stamina.regen_interval` | int | 恢复间隔（秒） |
| `stamina.regen_amount` | int | 每次恢复量 |
| `reset_hour` | int | 每日重置时间（小时，本地时间） |

---

## 11. initial_setup.json — 初始棋盘

| 字段 | 类型 | 说明 |
|------|------|------|
| `main.items` | array | 主棋盘初始摆放 `[{id, col, row, immovable?}]` |
| `battle.items` | array | 战斗棋盘初始摆放（可选，缺省时 battle 为空棋盘） |

---

## 12. home_meridians.json — 家园经脉

`production_rewards` 用 `{stage, index, items}` 配置生产设施奖励，其中 `stage`
与 `index` 均为从 0 开始的下标。默认奖励时机是穴位完成；设置
`timing: "circulation"` 时，奖励会合并到该阶段的 `circulation_rewards`，在整个周天完成时发放。
`production_reward_rules` 可用 `facility_prefixes`、`levels`、`count` 批量配置设施
链奖励，并用 `timing` 区分穴位或周天完成。穴位奖励按“基础材料与炼丹台 → 核心材料线
与对应制作台 → 已有生产线的高等级设施”分阶段投放；灵木园/灵潭发射器不进入前期教程，
改由后续周天循环奖励逐步引入，灵脉发射器则在首个循环奖励中只发放一个 1 级起点。
新手引导首阶段的源表奖励保持不变。
教程后的发射器首次出现时，同批或此前奖励必须已有能消耗其产物的制作台；练气一层
首先补齐教程书架所需的兽栏与演阵台，再逐条开放后续生产链。
教程后的周天奖励每次最多合并三类设施，继续降低单次记忆负担。
突破奖励则通过 `cultivation.json` 的
`breakthrough_reward_id` 指向 `rewards.json`；突破消耗物品由 `breakthrough_items` 配置。

| 字段 | 类型 | 说明 |
|------|------|------|
| `stages` | array | 阶段列表 `[{name, acupoints, qi_cost, acupoint_rewards, circulation_rewards}]` |
| `acupoint_rewards` | number/object/array | 单个奖励配置会应用到所有穴位；数组时按穴位下标逐点发放奖励 |
| `circulation_rewards` | number/object | 整个周天完成时发放的奖励；设施链奖励会合并到这里 |

`acupoint_rewards` 使用数字时必须是 `rewards.json` 中存在的奖励 ID；留空则由
`acupoint_exp` 生成内联经验奖励。配置生成时会校验每个境界解锁的全部周天经验总和
恰好等于该境界的突破经验要求（新手引导首阶段除外）。

---

## 13. shop.json — 商店表

| 字段 | 类型 | 说明 |
|------|------|------|
| `items` | array | `[{id, price}]` 商店出售的物品 |

---

## 14. server.json — 服务端配置

客户端 `HTTPRequest` 连接地址。

| 字段 | 类型 | 说明 |
|------|------|------|
| `host` | string | 服务器地址 |
| `port` | int | 端口 |

---

## 验证方式

1. 修改 `config/xlsx/` 中的 Excel 文件
2. 运行 `python config/xlsx_to_json.py` 重新生成 `json_output/` 下的 JSON
3. 重启服务器 `cd server && npm run dev`
4. 启动 Godot 客户端测试
