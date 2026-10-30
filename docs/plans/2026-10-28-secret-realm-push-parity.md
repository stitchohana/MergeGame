# 秘境拖拽与主棋盘对齐

主棋盘落点处理优先同级合成，无法合成时对可移动目标执行挤开：先从目标按四邻 BFS 寻找现有空格，满盘再使用源格交换。固定目标只有满足合成条件时可接受拖入。同级满级可移动物品不能升级，但可以挤开。

秘境补齐上述处理，寻空格以屏幕右、左、下、上为同距优先顺序（世界行号向上递增，因此垂直方向反转），跳过迷雾、怪物、离屏位置。挤开不揭雾、不升级、不触发合成掉落，保持实例 UID、等级及锁定状态。

客户端主棋盘与秘境共用通用四邻寻空格函数和 0.15 秒移动动画；服务端主棋盘与秘境共用对应寻空格函数。现有手势控制、合成判断及 GridItem 动效继续复用。秘境保留奖励溢出确认、怪物逐件提交、暂存点击投放及权威请求期间禁止重复操作。

验证覆盖主棋盘/秘境寻空格一致、已有空格优先源格、满盘交换、满级挤开、固定拒绝、同级固定合成、无揭雾和掉落、失败恢复与重试、真实指针及联网操作。

验证结果：

- 服务端 `secret_realm_push_smoke`、`secret_realm_smoke`、`secret_realm_merge_space_smoke`、`golden_finger_smoke` 通过。
- Godot `SecretRealmPushUISmoke`、`BoardDragReuseSmoke`、`SecretRealmUISmoke` 通过。
- 本地真实 HTTP fixture 下 `SecretRealmPushOnlineSmoke`、`SecretRealmCombatOnlineSmoke` 通过，覆盖指针拖拽、满盘交换、固定合成、已有空格挤开和怪物逐件提交。
- Worker 配置的 TypeScript 编译检查通过（项目配置启用 noCheck，不代表全量严格类型检查）。

保留差异：主棋盘支持乐观操作队列，秘境等待权威请求以保护掉落预览及怪物提交；秘境普通空格移动直接落位，挤开和交换复用共享滑动动画。
