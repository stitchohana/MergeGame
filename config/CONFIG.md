# 配置表说明

所有配置表位于 `config/json_output/`，由 `config/xlsx/` 中的 Excel 文件通过 `config/xlsx_to_json.py` 生成。

## 1. items.json — 物品表

### 通用字段

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | int | 唯一标识 |
| `name` | string | 物品名称 |
| `level` | int | 等级，同 group_id 内升级 |
| `group_id` | int | 合并组，同组同 id 可合并 |
| `icon` | string | 图标路径，空字符串用默认色块 |
| `describe` | string | 描述文本 |
| `type` | string | `regular` / `launcher` / `crafting`（加载时自动设置） |
| `value` | int | 吞噬需求订单价值（可选） |
| `sell_price` | int | 出售灵石价格（可选） |

### 发射器附加字段

| 字段 | 类型 | 说明 |
|------|------|------|
| `max_charges` | int | 最大生成次数 |
| `recharge_time` | int | CD 秒数 |
| `spawns` | array | 生成表 `[{id, weight}]`，weight 为权重 |
| `no_cost` | bool | true 时不消耗体力/灵力（可选） |

### 效果字段

| 字段 | 类型 | 说明 |
|------|------|------|
| `effect_type` | int | 效果枚举（见下方） |
| `effect_value` | int | 效果数值 |
| `atk` | int | 攻击力（仅飞剑/剑气） |

### EffectType 枚举

| 值 | 含义 | effect_value 含义 |
|----|------|-------------------|
| 0 | 无效果 | - |
| 1 | 攻击 | 攻击力加成 |
| 2 | 治疗 | 恢复 HP 量 |
| 3 | 修为经验 | 增加修为值 |
| 4 | 体力 | 恢复体力值 |
| 5 | 突破 | 突破境界 |
| 6 | 灵力恢复 | 恢复灵力值 |
| 7 | 发射剑气 | 消耗灵力，生成剑气到棋盘 |

---

## 2. cultivation.json — 修炼境界表

| 字段 | 类型 | 说明 |
|------|------|------|
| `name` | string | 境界名称 |
| `exp` | int | 升级所需经验 |
| `max_qi` | int | 灵力上限 |
| `atk` | int | 攻击力 |
| `breakthrough_pill` | int | 突破所需丹药 item id（可选） |

---

## 3. expedition.json — 探险表

### 怪物

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | int | 唯一标识 |
| `name` | string | 名称 |
| `hp` | int | 生命值 |
| `atk` | int | 攻击力（预留） |
| `accept_effect_ids` | int[] | 可接受的效果类型（effect_type 枚举值） |
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

| 字段 | 类型 | 说明 |
|------|------|------|
| `thresholds` | array | 阈值列表 `[{level, item_pool, count_min, count_max, acupoint_rewards, circulation_rewards}]` |

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
| `main` | array | 主棋盘初始摆放 `[{id, col, row}]` |
| `battle` | array | 战斗棋盘初始摆放 `[{id, col, row}]` |

---

## 12. home_meridians.json — 家园经脉

| 字段 | 类型 | 说明 |
|------|------|------|
| `stages` | array | 阶段列表 `[{name, acupoints, qi_cost, acupoint_rewards, circulation_rewards}]` |

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
