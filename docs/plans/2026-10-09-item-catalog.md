> 2026-10-28 约定更新：本文中的旧存档/旧格式兼容、历史回填和增量数据库迁移方案已废止。仅支持当前结构；新库统一使用 `server/schema.sql`，功能首次解锁与正常周期结算仍保留。

# 物品图鉴 Implementation Plan

**Goal:** 首页增加图鉴入口，按物品类型浏览，首次解锁后每件物品领取一次 1 体力。

**Architecture:** 复用 crafted_item_ids 作为获得历史；新增 item_catalog_claimed_ids 持久化领取记录。服务器校验、结算、保存成功后返回，重复请求返回已领取结果而不重复加体力。界面使用 BasePopup 和 Control 节点。

**Tech Stack:** Godot 4 / GDScript；TypeScript Worker Router；现有 JSON 状态存储。

1. 服务端：扩展 GameState；添加领取引擎方法和 POST /api/game/item_catalog/claim；完整状态包含领取历史。旧存档缺字段时视为空。
2. 客户端：GameState 增加领取历史和更新信号；CloudService 注册领取接口、请求互斥和错误处理，按存储版本同步历史。
3. 界面：HomeScreen 增加固定图鉴按钮和待领计数；图鉴五个页签由物品配置生成、按组/等级/ID排序。未解锁问号，待领体力图标，已领物品图标。保持滚动位置、拦截滚动误点击，失败允许重试。
4. 验证：服务端测试覆盖未解锁/非法请求、首次奖励、重复/并发、保存失败、重载及旧存档；Godot 测试覆盖首页入口、分类、三态、成功/失败及弹窗关闭；运行类型检查、Godot 导入检查和相关发现回归测试；截图检查布局。

命令：server 中 npm run worker:check 和 npx tsx tests/item_catalog_smoke.ts；Godot --headless --path . --editor --quit；Godot --headless --path . tests/ItemCatalogUISmoke.tscn。

## 验证结果

- worker:check、item_catalog_smoke、服务端物品发现和体力奖励回归测试通过。
- Godot 图鉴 UI 和物品发现测试通过，覆盖实际按钮提交、重复请求拦截和滚动防误领。
- Godot 4.6.1 使用 --rendering-method gl_compatibility 完成编辑器导入、无界面测试及实际渲染截图检查。初次默认渲染的无界面运行在退出时发生引擎 signal 11；兼容模式正常退出。
- 项目默认 Mobile/Vulkan 的实际窗口渲染也完成图鉴 UI 测试与截图，退出码 0。
- 截图：.codex_tmp/item_catalog_ui.png、.codex_tmp/item_catalog_home.png。
- 配置中 28 个物品 ID 重复；图鉴采用最终生效定义，每个 ID 仅展示一项，共 777 项。分类/等级空值使用 ConfigDatabase._coerce_int 转换。
- 领取接口需要随新版服务端启动或部署；本任务未部署远端服务。
