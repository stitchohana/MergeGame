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

灵石矿脉（`25001–25016`）只产出可使用的 1 级灵石 `1601`，统一为 6 次发射、
12 小时（43200 秒）重置；普通灵矿（`15001–15016`）的三类产出权重统一为：
主矿材 50%、矿芯 25%、玉石 25%。同类产物内部仍按矿口等级保持原有分布。

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
| 8 | 灵石 | 获得灵石数量 |
| 9 | 卡包（CARD_PACK） | card_collection.packs 中的 pack_id |

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

周常任务不奖励经验：每日合成任务奖励 1 个卡包（奖励 ID `3/4/5`，分别为 1/2/3 星）；其余任务奖励 10 体力（奖励 ID `2`，`token=3`）。

---

## 5. rewards.json — 奖励配置表

| 字段 | 类型 | 说明 |
|------|------|------|
| `tokens` | array | token 奖励 `[{token, amount}]` |
| `items` | array | 物品奖励 `[{id, count}]` |

### Token 类型

| 值 | 含义 |
|----|------|
| 1 | 灵石 |
| 2 | 灵力 |
| 3 | 体力 |
| 4 | 经验 |
| 5 | 战令积分 |

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

配方 `ingredients` 只能引用 `type=0` 的普通物品，不能引用配方产物、
发射器或其他非普通物品。同一配方内的材料物品 ID 必须互不相同，
JSON 与 XLSX 双向转换时都会校验材料类型并拒绝重复材料。

全表任意两个配方的材料集合不能存在严格包含关系，即一个配方的全部材料
不能只是另一个配方的部分材料。同一制作台内也不能有材料集合完全相同的
两个配方；不同制作台可以复用相同材料组合。双向转换均会拒绝这些冲突。

制作时间由配方产物等级统一决定：

| 产物等级 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---------|---|---|---|---|---|---|---|---|
| 时间（分钟） | 1 | 3 | 5 | 10 | 20 | 30 | 45 | 60 |

| 产物等级 | 9 | 10 | 11 | 12 | 13 | 14 | 15 | 16 |
|---------|---|----|----|----|----|----|----|----|
| 时间（分钟） | 90 | 120 | 180 | 240 | 360 | 480 | 600 | 720 |

配置生成时会校验所有配方严格使用对应档位，最低 1 分钟，最高 12 小时。

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
| `cycle` | int | 周期 0=一次性 1=每日 2=每周 3=每月 |
| `widget` | string | 入口 widget 类名（可选） |
| `start_time` | string | 开始时间 ISO 格式（一次性活动） |
| `end_time` | string | 结束时间 ISO 格式（一次性活动） |
| `enabled` | bool | 可选，显式启停活动；未配置时沿用旧行为 |
| `config` | object | 活动专用参数；XLSX 中使用 JSON 字符串 |

### 订单补给（OrderSupply，活动 ID 7）

常驻活动，使用 `cycle=0`，不配置开始、结束时间。入口位于棋盘订单列表上方。
`config.target_count=5` 表示累计 5 次可领取，`config.reward_count=3` 表示每次奖励 3 个低级合成材料。
发射器成功直接生成或合成出当前未完成订单需要的一个物品，或成功开始制作订单直接要求的成品，每次累计 1 次。
制作以配方产物 ID 与订单要求精确匹配，不递归匹配配方材料；制作订单物品的子材料不计数（除非该材料本身也被当前订单直接要求）。
同一次生成或合成即使匹配多个订单也只计 1 次；生成按实际产物匹配，倍数不额外增加次数，重复请求不重复累计。
无需凑齐或提交订单，提交订单、投入制作材料、制作完成、取出成品和领奖放入棋盘均不计数。
奖励按当前境界阶段选择基础材料等级：练气前、中、后期分别使用 1、2、3 级；筑基、金丹、元婴分别使用 5–7、9–11、13–15 级。制作成品按配方递归拆解为普通材料，再替换为对应材料合成链的境界等级，不直接发放制作成品或超出当前阶段的高级材料。没有缺少的物品时按当前订单选材，没有可用订单材料时按当前可生成的订单池选材。多个材料种类轮流发放，直接放入主棋盘空格；空位不足的部分进入物品暂存区。
选材优先按全部未完成订单的数量计算真实材料缺口，扣除棋盘可移动物品、储物道具内物品、储物袋、普通暂存奖励，以及未开始制作台内的材料；正在制作或已完成的成品计入可用数量，其已消耗材料不重复计算。普通材料还会向下拆分合成需求，已有足够低级材料可合成所需材料时不视为缺失。同一库存物品只抵扣一次，已提交订单和突破占位订单不参与计算。仅从有缺口的材料链发放；所有材料足够或全部订单物品已制作完成时，回退到当前订单材料链。
成功领取时，主棋盘全部正在制作的工作台立即变为可取出状态，保留原配方与成品；无额外灵石消耗，不自动取出，也不增加活动次数。未开始制作和已完成的工作台保持原状态。
领取成功后，棋盘补给物品从活动入口依次飞入目标格；每个飞行持续 0.45 秒，物品间隔 0.14 秒，落地后显示棋盘物品。动画期间暂时阻止操作，离开页面时清理动画并恢复操作；进入暂存区的物品不占用棋盘飞行目标。
进度达到目标后停止累计，成功领取后归零重新计数；棋盘完全没有空位时，全部奖励进入暂存区。
进度及领取轮次保存于服务端存档，重新登录后继续累计。

### 爬天梯（StairClimb，活动 ID 6）

配置源为 `config/xlsx/activities.xlsx` 的 `activities` 工作表，导出到 `config/json_output/activities.json`。
本期为北京时间 **2026-10-08 00:00 至 2026-10-11 00:00**，持续 72 小时。

| config 参数 | 当前值 | 说明 |
| --- | --- | --- |
| `group_size` | 20 | 每组总人数，真人不足由机器人补齐 |
| `order_points_ratio` | 0.1 | 每价值单位获得的积分，可独立调节 |
| `bot_order_value` | 100 | 机器人每次模拟订单的价值，使用同一积分比例 |
| `bot_min_minutes` / `bot_max_minutes` | 30 / 90 | 每个机器人随机固定的订单间隔（分钟） |
| `rewards` | 11 档 | 每档包含 `min_rank`、`max_rank`、`stamina`、`spirit_stones` |

每单积分为 `max(1, floor(物品总价值 × order_points_ratio))`；价值为零的订单不加分。
物品总价值由服务端按实际交付物品的 `value` 求和，同一物品多件逐件累计，不采用客户端或存档中的订单价值。
例如交付两个价值 116 的物品，总价值 232，本期增加 **23 分**。

第 1 名奖励 300 体力、3000 灵石；第 2～10 名每降一名减少 25 体力、250 灵石，
第 10 名为 75 体力、750 灵石；第 11～20 名统一为 50 体力、500 灵石。
所有数值都可通过 `rewards` 配置。排名按积分降序、达到当前分数的时间升序、入组随机顺序比较。

同境界按入组时的具体 `cultivation.current_level` 匹配（如练气三层）。成员随机选取且分组后固定，突破、重连和服务重启不换组。
机器人从入组开始累计，到截止时间停止。结束后留 30 秒结算缓冲，冻结最终榜单，定时分批给真人自动发奖；离线玩家也会到账，登录可补发。
奖励与领取标记在同一存档提交，避免重复发奖；奖励体力可超过自然恢复上限。参赛者结束后仍可从入口查看结算。

部署 D1 时须先应用 `server/migrations/0002_stair_climb.sql`，再部署服务端与客户端。当前服务支持一个爬天梯配置；下一期调整起止时间前须先完成本期全部发奖。


## 9. battle_pass.json — 战令配置

战令等级和奖励只维护在 battle_pass.json；积分倍率与进阶线解锁价格维护在
game_config.json 的 `battle_pass.points_per_value` 和 `battle_pass.premium_unlock_cost`；活动标题与起止时间只维护在
activities.json。activity_id 必须关联活动表；月循环战令使用 `cycle=3`，按中国标准时间
自然月刷新，且不需要配置起止时间。战令积分按活动独立保存，不作为可消耗货币结算；每月刷新时
积分、领取记录和进阶线解锁状态都会重置。

| 字段 | 类型 | 说明 |
|------|------|------|
| passes | array | 战令活动定义，首期仅支持配置一个 |
| activity_id | int | 关联的活动 ID |
| points_token_id | int | tokens.json 中的战令积分 token ID，仅用于显示元数据 |
| tiers | array | 按等级递增的奖励门槛和免费/进阶奖励 |
| level | int | 战令等级 |
| required_points | int | 领取该等级奖励需要的累计积分 |
| free_rewards / premium_rewards | object | 使用现有奖励格式：tokens 数组配置 token 与 amount，items 数组配置 id 与 count |

首期配置暂定为 50 级、每级 10 积分；两条轨道奇数级各奖励 10 体力，偶数级各奖励 1 个 1 星卡包（道具 1701），领取后进入物品暂存区。
订单积分倍率由 `game_config.json` 统一配置为 0.1，进阶线解锁价格统一配置为 500 灵石。
首期战令已启用，按 `cycle=3` 每月循环开放。

---

## 10. meridians.json — 经脉表

订单候选由当前棋盘上的发射器和制作台计算，固定包含主产物、副产物与配方产物三类。
系统从 `spawns` 与 `recipes` 递归计算真正可制作的订单物品；发射器内产出权重较低
的产物链视为副产物。
随机订单每个物品位置先按 `game_config.orders.recipe_product_probability`
选择配方产物池或普通物品池（含副产物），再在池内按已有来源权重抽取。
当前配方产物概率为 80%，普通物品为 20%。任一池为空或本批已抽完时，
从另一池继续抽取，因此候选不足时整批配方产物占比可能低于 80%。
同一批订单不重复抽取同一物品，固定引导订单与突破订单不使用此概率。
`order_level_ranges` 对应 `meridians.xlsx` 的 `order_level_ranges` 工作表，按
`cultivation.current_level` 配置主产物与配方产物的等级范围；副产物沿用配方产物范围。
固定引导订单直接使用 `fixed_orders`，不经过等级过滤，`order_count` 以 XLSX 为准。
`fixed_orders` 的紧凑形式是“一个对象一波”：`{item_ids:[...]}` 中的每个 ID
对应该波的一个订单，当前波次全部完成后才会显示下一波。XLSX 中可写成每行一波的
`item_ids:{5003,5004,6001}`。需要表达单个订单包含多个物品时，仍可使用旧的嵌套
订单数组与 `item_ids` 配置。
例如：`[{"item_ids":[5003,5004,6001]},{"item_ids":[9003,9004,10001]}]`。
固定订单对象也可提供显式 `rewards`；配置了 `rewards` 时，
服务端直接发放该奖励，不再按订单物品价值进行倍率换算。
普通订单使用奖励 219，订单 `total_value` 按 1:1 转换为灵气；周天灵气消耗按当前订单池最大价值重新标定。

| 字段 | 类型 | 说明 |
|------|------|------|
| `order_level_ranges` | array | 订单等级区间，来源为 `order_level_ranges` 工作表 |
| `thresholds` | array | 阈值列表 `[{stage, count_min, count_max, acupoint_rewards, order_count, fixed_orders}]`；`fixed_orders` 可为 `{item_ids:[...]}` 波次对象数组或旧嵌套订单数组 |

配方产物的 `level` 在导出时按配方依赖树计算，取所需材料的最大等级；循环依赖、缺失配方或无效原料会生成空等级，订单筛选时不会进入有等级限制的候选池。

---

## 11. game_config.json — 游戏参数

| 字段 | 类型 | 说明 |
|------|------|------|
| `stamina.max` | int | 体力上限 |
| `stamina.spawn_cost` | int | 生成消耗 |
| `stamina.regen_interval` | int | 恢复间隔（秒） |
| `stamina.regen_amount` | int | 每次恢复量 |
| `reset_hour` | int | 每日重置时间（小时，本地时间） |
| `battle_pass.premium_unlock_cost` | int | 解锁战令进阶线所需灵石 |
| `battle_pass.points_per_value` | number | 订单价值积分倍率，积分为 floor(total_value * points_per_value) |
| `orders.recipe_product_probability` | number | 每个随机订单物品位置选择配方产物的概率，0–1，当前 0.8；缺省或无效值使用 0.8，超出范围时限制为 0–1 |

---

## 12. initial_setup.json — 初始棋盘

| 字段 | 类型 | 说明 |
|------|------|------|
| `main.items` | array | 主棋盘初始摆放 `[{id, col, row, immovable?}]` |
| `battle.items` | array | 战斗棋盘初始摆放（可选，缺省时 battle 为空棋盘） |

---

## 13. home_meridians.json — 家园经脉

设施奖励直接配置在对应阶段的 `circulation_reward.items` 中，完成整个周天时一次发放；
不再维护全局生产奖励表。初始棋盘不再直接摆放三个可移动教程设施，设施统一随周天进度发放。
激活穴位只发放 15 点体力，不再发放经验；原穴位经验已并入阶段的 `circulation_reward`，
完成整个周天时统一发放。当前配置共有
556 个周天。凡人两个周天分别发放 1、2 个教程设施，练气一层为 3 个周天，
之后每层练气增加 1 个周天，筑基及以后沿用原周天数量。练气期起每个周天固定发放
2 个非灵石矿设施；减少的周天不向后补齐，设施奖励按新的周天数量重新提升等级，
保证练气期结束时的设施最终等级不变。凡人第 2 周天另发放 10 灵石。

为平滑前期节奏，凡人和练气期每个周天固定 4 个穴位。凡人每个穴位消耗 5 点灵气，
两轮周天合计消耗 40 点；首阶段七个固定引导订单按 1:1 产出 65 点灵气，保留更多缓冲。
练气期及以后按当前境界订单池的平均订单价值标定：练气一层约需 4 单完成一个周天，
后续随境界逐步提高。目标订单数仅用于离线反推现有 `qi_cost`，不会新增运行时配置字段。
凡人境界总经验为 12，低于练气一层的 48。

设施奖励按境界逐步提高等级：凡人发放 1 级，练气期不超过 4 级，筑基期不超过 8 级，
金丹期不超过 12 级，元婴及以后不超过 16 级。练气期只轮换苗圃、泉眼、药圃、矿口、
炼丹炉和炼器室；筑基前期新增兽栏和酒坊，筑基中期新增灵木园和符桌，筑基后期新增
书架、灵潭和阵室。筑基期首次开放的设施从 1 级开始递进，全部设施均可在元婴期获得
16 级奖励。周天顺序先发放生产设施，再发放至少已有一个可制作配方的制作台。
所有突破（前 19 个境界）统一通过 `rewards.json` 发放 1 个 1 级灵石矿 `25001`。
突破奖励则通过 `cultivation.json` 的
`breakthrough_reward_id` 指向 `rewards.json`；突破消耗物品由 `breakthrough_items` 配置。

制作台的配方依赖会递归解析到发射器族群。配置顺序必须满足：制作台首次发放前，
至少一个配方所需的生产设施已在初始棋盘或更早的周天奖励中开放；同一周天内同时
配置的发射器不视为“已先发放”。后续境界可继续开放该制作台高级配方依赖的生产线。
转换脚本会自动校验这条规则；凡人第三周天的固定炼丹炉奖励继续作为新手引导例外。

| 字段 | 类型 | 说明 |
|------|------|------|
| `stages` | array | 阶段列表 `[{cultivation_level, name, acupoints, qi_cost, circulation_reward}]` |
| `circulation_reward` | object/number | 整个周天完成时发放的奖励，包含周天经验、体力、灵石和设施 `items`；凡人两个周天分别为1、2件设施，其余为2件；每个周天另配置1个4星卡包（1704） |

配置生成时会校验每个境界解锁的全部周天经验总和恰好等于该境界的突破经验要求
（新手引导首阶段除外）。

---

## 14. shop.json — 商店表

| 字段 | 类型 | 说明 |
|------|------|------|
| `items` | array | `[{id, price}]` 商店出售的物品 |

---

## 15. server.json — 服务端配置

客户端 `HTTPRequest` 连接地址。

| 字段 | 类型 | 说明 |
|------|------|------|
| `host` | string | 服务器地址 |
| `port` | int | 端口 |

---

## 16. card_collection.json — 万象仙册集卡活动

源表为 `config/xlsx/card_collection.xlsx`，包含 `collections`、`card_sets`、`cards`、`packs`、`source_rewards` 五个工作表。活动开关和起止时间仍在 `activities` 表维护，入口 widget 为 `CardCollection`。当前为常驻活动 ID 5、收藏 ID 1。

| 数据段 | 字段与规则 |
| --- | --- |
| collections | collection_id、activity_id、name；不同收藏 ID 的卡片和领奖进度独立 |
| card_sets | set_id、collection_id、name、rewards（JSON，体力 token=3、灵石 token=1） |
| cards | card_id、set_id、name、star（1–5）、icon（可留空，显示文字卡面） |
| packs | pack_id、collection_id、name、star（1–5）、icon、card_count（1–100）、normal_weights（JSON 数组，按 1–5 星顺序） |
| source_rewards | collection_id、source_type（order/circulation）、source_id（留空匹配默认）、min_value、pack_id、count、enabled |

**同星保底：** n 星卡包第一卡位必出一张恰好 n 星卡片，计入 `card_count`。其他卡位按 `normal_weights` 抽星级，同星卡等概率，允许重复。总张数为 1 时仅抽保底槽。所有可抽星级必须有有效卡片，服务端启动时校验。

初始调试配置：1–5 星卡包分别 2/3/4/5/6 张，其余槽权重均为 `[55,28,12,4,1]`。三组卡片各 5 张；成功开包后检测完整卡组，自动发放对应的 300/500/800 体力和 1000/2000/3000 灵石，无需手动领取。重复卡保留数量，发奖不消耗卡片，每组一次，由永久 `claimed_sets` 标记防止重复发放。旧存档中已集齐但未领奖的卡组，在下一次成功开包时自动结算。

自动发奖成功后弹出“卡组集齐奖励”，展示集齐卡组名称与已到账奖励图标、数量。一键全开集齐多组时合并为一个提示；关闭提示可继续查看开包结果。提前关闭开包界面不影响到账提示，同一会话的重复响应不重复弹窗，查看上次开包结果也不触发新弹窗。

合成本身不直接发放卡包；合成只会推进 `MERGE` 类型任务。仅当任务奖励 `items` 配置了卡包效果道具时才发放，未配置则不发放。手动领奖任务达标后仅变为可领取，点击领取时才发放卡包；自动领奖任务达标时随原奖励发放卡包。不再根据任务目标数量额外赠送卡包。

卡包在 `items.xlsx/items_effect` 配置：`type=5`、`effect_type=9`、`effect_value=pack_id`。道具 ID `1701–1705` 对应 1–5 星卡包（pack_id `1–5`）；每种卡包必须对应唯一效果道具，服务端启动时校验。任务的 `rewards` 指向奖励表，在该奖励行的 `items` 中添加如 `[{"id":1703,"count":1}]` 即奖励一个 3 星卡包。Excel 的 `items(id:count)` 对应填写 `1703:1`。

周常任务每一天的合成任务（1001、1006、1011、1016、1021、1026、1031）分别奖励1、2、3、1、2、3、1星卡包各1个。使用奖励ID 3/4/5，均保留原100经验；其他任务仍使用原奖励。达标后必须手动领取。

产出规则按达到的最高 `min_value` 档位发放一次；指定 `source_id` 优先于默认规则，指定规则 `enabled=false` 可以禁止该来源发包。

| 来源 | min_value 的含义 | 当前档位（每次一个卡包） |
| --- | --- | --- |
| order | 成功订单的 total_value | 0→1星，200→2星，600→3星 |

订单 `source_id` 默认为0，按最高符合档位发放1包：价值低于200为1星、200–599为2星、600及以上为3星。订单奖励区域仅显示图标和数量，不显示星级文字，提交接口的 `rewards.items` 包含实际卡包奖励。

任务和周天不使用 `source_rewards` 自动赠包。556个周天均在 `home_meridians.circulation_reward.items` 明确配置 `1704:1`，随完成奖励展示和结算，不再额外按周天阶段发3–5星包。任务奖励每周期只领一次，已领取的历史任务不补发。活动停用时暂停订单来源发包、开包和卡组自动发奖，保留存档；显式配置在任务/周天中的卡包仍进入暂存区，待活动开放后开启。

卡包奖励直接进入物品暂存区 `pending_rewards`：每个卡包具有唯一 `uid`，`id` 为效果道具 ID，并携带 `kind="card_pack"`、`collection_id`、`pack_id`、`name`、`icon`。普通奖励省略 `kind` 或使用 `item`。历史暂存卡包保留原 UID 和元数据，因此仍按 `kind` 判断，不依赖旧 `id`。卡包不进入棋盘，不参与物品发现与生产设施解锁。

活动页仅展示卡册及卡组奖励，不展示卡包库存或数量角标。点击暂存区队首卡包进入独立开启界面，支持仅开选中 UID 或一键全开暂存区全部卡包（包括被普通物品隔开的卡包）；普通物品保持原有顺序。每包分别执行同星保底，批量结果按卡片合并展示本次获得数量、新卡标记与持有数量。全开包含停用活动或未知配置卡包时整体拒绝，保留全部物品。

`POST /api/game/card_collection/open` 接收 `collection_id`、`pack_uid`、`open_all`（布尔值）、`request_id`、`expected_opened_count`。选中 UID 是全开的重放保护锚点；每次在副本上计算，卡包消耗、卡片、卡组发奖标记、体力、灵石和回执一起保存成功后才响应。单包和全开均检查所有开放收藏的未发奖完整卡组，合并发放奖励。响应携带 `pending_rewards`、`storage_revision` 和最新收藏进度；有卡组发奖时还包含 `completed_sets`（collection_id、set_id）和 `rewards`，用于显示奖励到账。重试只恢复原结果，不重复发奖。客户端按修订号过滤旧响应。旧存档的 `progress.packs` 在读取时一次性迁移为暂存卡包并保存，原计数清零；不补发历史任务奖励。原 `/card_collection/claim` 接口仅保留兼容，当前客户端不再提供卡组领奖按钮。

仅转换集卡表可运行 `python config/xlsx_to_json.py --only-card-collection`；反向同步可运行 `python config/json_to_xlsx.py --only-card-collection`。常规全量转换也包含此表。

## 验证方式

### 储物袋容量与解锁费用

在 `game_config.xlsx` 的 `game_config` 工作表中配置以下参数，导出到 `game_config.json/pouch`：

| 参数 | 默认值 | 含义 |
| --- | --- | --- |
| `pouch.initial_slots` | 7 | 新玩家初始可用格数 |
| `pouch.unlock_cost_base` | 100 | 第一次解锁 1 格的灵石费用 |
| `pouch.unlock_cost_increment` | 50 | 每次解锁增加的灵石费用 |

参数均为正整数。第 n 次付费解锁费用为 `unlock_cost_base + (n - 1) * unlock_cost_increment`，默认依次为 100、150、200……灵石；每次增加 1 格。修改配置并重新导出后需重启服务端（Worker 需重新部署）。已解锁容量和付费解锁次数永久保存，取出物品不降低下一次费用。

旧存档首次读取时容量取初始格数与已有物品数量的较大值，旧物品不删除，也不补扣灵石；下一次付费解锁从起始费用计费。满格存入由服务端拒绝，原棋盘物品保留。解锁请求携带 `expected_capacity`，同一容量的重复请求不会重复扣费。

1. 修改 `config/xlsx/` 中的 Excel 文件
2. 若需要按当前订单池重算订单灵气与周天消耗，先运行 `node config/rebalance_order_qi.mjs`
3. 运行 `python config/xlsx_to_json.py` 重新生成 `json_output/` 下的 JSON
   （转换时会校验发射器→制作台的依赖顺序；需要重建周天奖励时运行
   `python config/expand_home_meridians.py`，历史命令
   `python config/optimize_facility_rewards.py` 会转发到该生成器）
4. 重启服务器 `cd server && npm run dev`
5. 启动 Godot 客户端测试
