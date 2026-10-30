# 秘境移除重试按钮与状态冲突重新登录

取消秘境“重试操作”按钮及回调。服务器明确返回 `state_conflict` 时，所有游戏接口统一退出当前会话，复用 Main 的 kicked 导航和 LoginScreen 的设备自动登录，读取服务器完整存档后进入主页。

CloudService 的 `force_relogin()` 去重处理同一退出流程：立刻停止秘境输入，清除 token、旧请求队列、活动请求缓存和版本号，取消正在进行的 HTTPRequest；旧查询回包不会恢复在线或覆盖新会话状态。退出通知延迟到本次响应处理结束，防止新登录请求被旧响应处理误清理。Main 清理页面与弹窗，并等待已有场景切换结束，保证登录后的主页切换不会被旧加载标记吞掉。

秘境已提交结算但发生网络、解析、保存失败等无法确认结果时，也返回自动登录读取服务器存档，不重新提交旧操作。普通业务拒绝继续提示；未提交结算的预览网络失败允许重新拖动。登录成功后如权威存档加载失败，保留登录页，禁止用旧状态进入离线游戏。无服务端存档修改及数据迁移。

验证：

- `SecretRealmReloginSmoke.tscn` 配合 `server/tests/secret_realm_http_fixture.ts --relogin`：真实 HTTP 409 → 关闭秘境 → 自动设备登录 → 完整存档恢复；同时验证旧 mutation 队列清理、旧查询取消、重复退出去重、预览/批量请求冲突、未知结算结果和普通业务拒绝。
- 联网测试故意令首次重新登录后的存档读取失败，验证停留登录页，重新登录成功后才恢复主页。
- `SecretRealmUISmoke`、`SecretRealmStashBurstSmoke`、`SecretRealmMergeDragSmoke`、`SecretRealmEffectsUISmoke` 通过，覆盖无重试按钮、连续暂存投放、合并期间拖拽及战斗动画。
