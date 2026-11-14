# 版本更新记录

> 每个版本条目均为中英双版：先完整中文版，分隔线后为逐条对应的英文翻译。

### v1.6.6+166 - 2026-11-14

**锁屏恢复与发信可靠性修复（1.6.6）**

🚪 **锁屏卡死与启动**
- 修复部分机型锁屏恢复后卡在「加载通知记录」的长时间无界等待：
  连接隔离（`singleInstance: false`）让各引擎各持一条 SQLite 连接、不再排别人的悬挂事务；
  锁冲突退化为有界的 `busy_timeout`（客户端报错而非无限等）；计划内关闭引擎连接；
  启动页逐步有界步骤（单步 30s 超时），卡死时给出「重启应用」出口
- 路由关掉自动切备后，失败只进重试、绝不碰备用通道（此前偶发切备后又触发主备同时发）
- 传输层异常统一兜住转 `transportError`，不再冒泡到页面；可恢复失败自动重试一次（500ms 延迟）
- `runNow` 发送前先 cancel 上一次 debounce Timer，锁屏恢复后避免重复触发
- 发送失败 `transportError` 弹层加「重试」按钮

📋 **历史页**
- 历史页三个 Tab 统一选择态，幻念消息支持直接导出

---

**Wake-from-lock & send reliability (1.6.6)**

**Splash-screen hang & startup**
- Fixed the long unbounded wait stuck on "loading notification record" after waking from lock on some devices:
  connection isolation (`singleInstance: false`) gives each engine its own SQLite connection instead of queuing behind a hung peer;
  lock contention becomes a bounded `busy_timeout` (client sees an error instead of waiting forever);
  engines close their connections cleanly; the splash screen now runs each startup step with a 30 s budget
  and offers a "restart app" exit when one step hangs
- After the auto-failover toggle was removed, routing no longer touches fallback channels — failed deliveries retry on primary only
- Transport-layer exceptions are caught and translated to `transportError` instead of bubbling up to the page;
  recoverable failures get one automatic retry (500 ms delay)
- `runNow` cancels the previous debounce timer before sending, preventing duplicate sends after waking from lock
- The `transportError` dialog on failed sends now has a Retry button

**History page**
- Unified selection mode across all three history tabs; Fnthink messages can be exported directly

### v1.6.5+165 - 2026-11-08

**幻念收件与通道可靠性升级（1.6.5）**

🔔 **幻念收件**
- 收件改为常驻引擎：通知到达即转发，锁屏也可持续接收（开启「锁屏持续接收」时）
- 心跳跟随收货循环起停；网关异常按 5→15→30→60 秒退避，5xx 自动降级为短轮询
- 网关错误码翻成人话；门铃重连退避上限按前后台分档；配对提交接受 202 受理
- 转发/收件/发出的时间显示到秒；「本轮跳过」不再显示成失败；远程执行历史补报错说明入口

🛡️ **通道与送达**
- 新增失败重放队列与通道失败分诊：失败按通道类型自动重排，状态页能看到「最近一次失败」
- 新增一键全链路自检；送达格补上 httpCode、尝试次数与耗时
- Webhook 支持自定义请求头与请求方法，并能识别自家幻念端点
- 历史快照只包含本轮实际路由到的通道

🎛️ **规则引擎**
- 新增设备状态条件（电量、网络类型）进规则词表；推送模板新增 %battery% / %network%

🧩 **稳定性修复**
- 修复关闭软件后卡在启动屏、一直不进首页的问题（安全存储读不出来时有界失败，给出说明与重试）
- 修复停止监听后状态栏仍残留「正在监听通知」
- 修复部分机型升级后偏好设置读取失败导致的功能异常
- 数据库打不开时不再一律按损坏处理；旧库备份可校验并恢复
- 首页历史入口改名为「历史记录」；大版本升级首启弹一次更新说明；应用选择器支持快速选择

⚠️ **升级注意**
- 覆盖升级保留全部设置与历史
- 服务端指标（/metrics）与协议计数需部署服务端后生效

---

**Smarter receiving and channel reliability (1.6.5)**

**Fnthink receiving**
- The receiver now runs as a resident engine: notifications are forwarded on arrival, and receiving continues while the screen is locked (when "keep receiving while locked" is on)
- Heartbeats follow the receive loop; on gateway trouble the app backs off 5→15→30→60 s and falls back to short polling on 5xx
- Gateway error codes are translated into plain language; reconnect backoff ceilings differ in foreground/background; pairing accepts 202
- Times in forwarded/inbox/outbox history show seconds; "skipped this round" no longer looks like a failure; remote-execution history gained an error-explanation entry

**Channels and delivery**
- New failed-delivery replay queue with per-channel triage; the status page shows the "last failure"
- One-tap end-to-end self-check; delivery cells now record httpCode, attempt count and elapsed time
- Webhooks support custom request headers and HTTP methods, and recognise the built-in Fnthink endpoint
- History snapshots only include channels actually routed this round

**Rule engine**
- Device-state conditions (battery level, network type) join the rule vocabulary; templates add %battery% / %network%

**Stability fixes**
- Fixed the app hanging on the splash screen after being closed (secure-storage failures now fail within a bounded time with an explanation and retry)
- Fixed the persistent "listening for notifications" notification remaining after monitoring is stopped
- Fixed preference-read failures on some devices after upgrading
- A database that fails to open is no longer treated as corrupt by default; legacy backups can be verified and restored
- The home history entry is now labelled "History"; major upgrades show a one-time what's-new note on first launch; app pickers gained quick selection

**Upgrade notes**
- Overlay upgrades keep all settings and history
- Server metrics (/metrics) and protocol counters take effect after the server is deployed

### v1.6.4+164 - 2026-10-29

**稳定性修复：数据库不再被误锁、实时唤醒判定更准（1.6.4）**

数据库
- 修复升级后数据库一直打不开、历史与回执写不进去的问题；原库保留，不再被误判为损坏
- 后台事务挂住时，下次打开会先回滚，不再永久锁死

实时唤醒
- 心跳被中间层吞掉时，先降级为短轮询并每 5 分钟重探，不再每 50 秒断开重连
- 门铃健康时收件卡显示「实时唤醒已连接 · 兜底每 N 秒」，不再显示成每 5 分钟才收一次
- 后台进程被杀后，接手间隔恢复为 60 秒

投递
- 服务端：响应未写到设备就立即退回队列，不再等 180 秒（需服务端部署后生效）

升级注意
- 覆盖升级保留全部设置与历史
- 实时唤醒的即时性由门铃负责；关闭接收或未同意中转时不会建立连接

---

**Stability fixes: database no longer locks itself out, smarter real-time wake-up (1.6.4)**

**Database**
- Fixed the database failing to open after an upgrade, which blocked history and receipts; the original file is kept and no longer misread as corrupt
- A dangling background transaction is rolled back on the next open instead of locking the database forever

**Real-time wake-up**
- When heartbeats are swallowed by an intermediary, the app degrades to short polling and re-probes every 5 minutes instead of reconnecting every 50 seconds
- While the wake-up channel is healthy, the receiving card shows "Real-time wake-up connected · fallback every N s" instead of looking like a 5-minute poll
- After the process is killed, the background hand-off returns to 60 seconds

**Delivery**
- Server: a response that never reaches the device is requeued immediately instead of waiting 180 seconds (takes effect after server deployment)

**Upgrade notes**
- Overlay upgrades preserve all settings and history
- Real-time promptness depends on the wake-up channel; no connection is opened while receiving is off or relay consent is not given

### v1.6.3+163 - 2026-10-27

**后台收货与稳定性修复（1.6.3）**

🔔 **后台收货**：
- 锁屏且「锁屏持续接收」开启时保持 CPU 唤醒；实时唤醒断流会在 50 秒内被发现并自动重连，锁屏消息到达更稳定
- 接收页新增「锁屏持续接收（更耗电）」开关（默认开），可关闭以省电
- 接收页自检新增：上次闹钟触发、后台任务结果、上次收取、上次实时唤醒字节、屏幕与唤醒锁状态

🛡️ **安全与数据**：
- 关闭监听后，来电与短信不再转发；新增「仅转发电话与短信」独立开关（默认关）
- 数据库打不开时不再一律当作损坏改名重建：只有确认损坏才进入恢复流程，其它错误明确报错并提供「重试」，历史不再被误清空
- 数据库重建时先失效旧通道镜像并暂停发送，避免按旧配置误发

🎨 **界面**：
- 统一弹窗、取消色、卡片阴影、底栏形态、输入框与开关等细节
- 修复规则说明、优先级标签、入口行前景色与重复添加入口等视觉问题

⚠️ **升级注意**：
- 覆盖升级保留全部设置；「仅转发电话与短信」默认关，不改变现有行为
- 「锁屏持续接收」默认开；关闭后锁屏收货可能延迟

---

**Background delivery and reliability fixes (1.6.3)**

🔔 **Background receiving**:
- While the screen is off and "keep receiving while locked" is on, the CPU stays awake; a silent real-time channel is detected within 50 seconds and reconnected, so lock-screen delivery is steadier
- New "keep receiving while locked (more battery)" switch in the receiving page, on by default; turn it off to save power
- The receiving self-check now shows the last alarm, background task result, last poll, last real-time byte and screen/wake-lock state

🛡️ **Safety and data**:
- Turning monitoring off now stops call and SMS forwarding; a separate "forward calls and SMS only" switch (off by default) is available
- An unopenable database is no longer treated as corrupt and renamed: only confirmed corruption enters recovery, other errors are reported with a Retry action, so history is not silently wiped
- When a database is rebuilt, old channel mirrors are invalidated and sending is paused to prevent stale-config sends

🎨 **UI**:
- Unified dialogs, cancel colour, card shadows, bottom bar, inputs and switches
- Fixed rule notes, priority labels, entry-row foreground colour and duplicate add-entry visuals

⚠️ **Upgrade notes**:
- Overlay upgrades preserve all settings; "forward calls and SMS only" is off by default and changes no existing behaviour
- "Keep receiving while locked" is on by default; turning it off may delay lock-screen delivery

### v1.6.2+162 - 2026-10-25

**收取节奏自动化与后台保活（1.6.2）**

🔔 **后台收取**：
- 空闲时改用长轮询，服务端有货即返回；新增实时唤醒通道，锁屏后台也能尽快收到
- 实时唤醒健康时不再常驻唤醒锁，空闲请求与耗电明显下降
- 被系统回收或划掉最近任务后 1 秒自动尝试重启；保活引导新增「允许关联启动」

⚙️ **设置简化**：
- 移除「收取间隔」滑杆：节奏由长轮询 / 实时唤醒自动决定，不再需要手动设置
- 旧备份里的这一档仍可恢复，但不再影响收取

⚠️ **升级注意**：
- 覆盖升级保留全部设置；旧版本选过的收取间隔不再生效
- 实时唤醒需要最新服务端；旧服务端会自动退回长轮询，不影响收消息

---

**Automatic receiving cadence and background delivery (1.6.2)**

🔔 **Background receiving**:
- Idle receiving now uses long polling, returning as soon as the server has mail; a real-time wake-up channel keeps messages arriving promptly behind a locked screen
- No permanent wake lock while the wake-up channel is healthy — idle requests and battery use drop noticeably
- If the system reclaims the service or you swipe the task away, it automatically attempts a restart after 1 second; the keep-alive guide now includes "allow associated start"

⚙️ **Simpler settings**:
- The poll-interval slider is gone: cadence is decided automatically by long polling / the real-time wake-up channel
- An old backup can still restore that setting, but it no longer affects receiving

⚠️ **Upgrade notes**:
- Overlay upgrades preserve all settings; a previously chosen poll interval no longer takes effect
- The real-time wake-up channel needs the latest server; older servers fall back to long polling automatically, so delivery still works

### v1.6.1+161 - 2026-10-24

**幻念推送与配对体验修复（1.6.1）**

🔗 **配对与权限**：
- 配对时只确认“同意/拒绝”，逐项权限移到设备详情页，按组折叠后再细调
- 配对口令失败可重试，界面标明已使用、已失效、已过期，并可直接重新生成
- 删除本地口令不会影响已经配对成功的设备与已授予的权限

📨 **幻念推送内容**：
- 消息向 webhook 看齐：带应用名、消息标题与正文
- 收件列表与系统通知的发送人可显示备注名、设备名或两者，改备注后立即跟随

🔔 **收件通知**：
- 新增通知自检：逐项检查锁屏显示、声音、震动、悬浮通知与渠道级别
- 按 MIUI / ColorOS / HarmonyOS / 原生给出对应路径，可一键跳到系统设置并发测试通知
- 渠道被降级时可手动重建高优先级渠道

🛠️ **稳定性修复**：
- 修复长锁屏/后台时幻念消息收不到、发送端一直显示“发送中”的问题
- 修复“监听开着但暂停推送”被显示成发送中、并误切备用通道的问题
- 双通道同时开启时，历史记录不再只显示 webhook 一条
- 修复冷启动重复登记导致的“注册被限流”：不再显示十几小时等待，也不再把它画成常设收取间隔
- 修复聚合推送行无法点击：现在可点开查看这一组扇出的成员
- 配对成功但对端状态 404 时，改为明确提示“服务器缺少状态读口”，不再只显示 404

🧩 **更新与连接**：
- 在线更新界面更紧凑：完整更新日志可折叠，服务器选择页压缩留白
- 大陆站与海外站各用各的 CDN：大陆 `cdn.fnthink.com`、海外 `cdn2.fnthink.top`
- 当所选更新档位与实际下载主机不一致时，界面会给出提示

⚠️ **升级注意**：
- 覆盖升级保留全部设置；配对关系与已授予权限不受口令删除影响
- 幻念身份私钥与两类口令仍不进备份，换机后需重建端点并重新配对

---

**Fnthink Push and pairing experience fixes (1.6.1)**

🔗 **Pairing and permissions**:
- Pairing now asks only approve/deny; per-item permissions moved to the device detail page, grouped and collapsible
- A pairing code can be retried after a failed attempt; used, expired and invalid states are shown, with a regenerate action
- Removing a local pairing code does not affect already-paired devices or granted permissions

📨 **Fnthink message content**:
- Messages now match webhook content: app name, message title and body
- The sender in the inbox and system notification can show the alias, the device name, or both; alias changes apply immediately

🔔 **Inbox notifications**:
- New notification self-check for lock-screen visibility, sound, vibration, heads-up and channel importance
- Per-OEM paths for MIUI / ColorOS / HarmonyOS / stock Android, with one-tap system settings and a test notification
- A downgraded channel can be rebuilt at high importance on demand

🛠️ **Reliability fixes**:
- Fixed missing Fnthink messages after long lock-screen/background periods and the stuck “sending” state
- Fixed “listening but paused” being shown as sending and incorrectly switching to the backup channel
- History now shows both channels when webhook and Fnthink are enabled together
- Fixed repeated registration on cold start that led to “registration rate-limited”: no more 12-hour waits, and the backoff is no longer shown as the normal poll interval
- Merged-push rows are now tappable and list the members of that group
- A 404 peer status now says the server is missing the presence readout instead of showing a bare 404

🧩 **Updates and connectivity**:
- The online update UI is more compact: the full changelog is collapsible and the server page has less empty space
- Mainland and overseas update sites now use their own CDNs: `cdn.fnthink.com` and `cdn2.fnthink.top`
- A warning appears when the selected update region does not match the actual download host

⚠️ **Upgrade notes**:
- Overlay upgrades preserve all settings; pairing relationships and granted permissions survive pairing-code removal
- Fnthink identity keys and both kinds of secrets are still excluded from backups, so rebuild the endpoint and pair again after moving devices

### v1.6.0+160 - 2026-10-22

**幻念推送 + 远程控制 + 通道体系重构 + 全局体验统一（1.6.0 大版本）**

🛰️ **幻念推送（新）**：
- 两台设备配对后直接投递：无第三方账号、无平台转发；每条消息由发送方私钥签名、接收方验签，服务端只存投递元数据不存正文
- 配对分三步：扫码或口令 → 对方确认 → 逐条授权；授权清单存在被投的那台设备上，可随时撤销
- 新增「幻念推送」页：接收开关、立即收取、收取间隔、在线状态与「上次收取 X 秒前」、收件箱与发送历史
- 收到通知后可转发给已配对设备或已有 webhook 通道；转发结果进入推送历史
- 后台保活：精确闹钟 + WorkManager；被系统杀掉后下一轮仍能取回离线消息

🎛️ **远程控制（新）**：
- 由已配对设备下发指令，按 L2（应用动作）/ L3（系统设置）分档，逐项授权
- 每次执行前有可撤销的延时窗口；执行结果两段回执，失败与取消分开显示
- L3 需高级密钥或 TOTP；连续失败自动降级，不静默改系统设置

🧩 **通道体系**：
- 三族通道统一成「列表页 → 单通道详情页」；主/备通道与自动降级，历史里标出「本次走了备用」
- 新增通道健康探测、通道状态页、设备状态快照；「仅测试」与「测试并保存」拆开
- 幻念推送作为第四族接入转发与主备路由；删除一律二次确认

🎨 **体验与 UI**：
- 底部导航改为 首页 / 通知引擎 / 更多；全应用 Cupertino 化
- 通知引擎覆盖电量、温度、亮度、网络、设备状态；新增规则测试器与试跑
- 推送历史新增「全部」档、送达状态、通道详情与单通道重发
- 页面内长说明统一收进带边界文本框；可点击的纯文字全部换成真正的按钮或行内动作
- 收取间隔开放为 5–60 秒；应用筛选与远程触发筛选页的无权限提示可直接点击授权

⚠️ **升级注意**：
- 升级保留设备名、规则、通道、关键词、阈值、主题、语言等全部设置
- 幻念身份私钥与两类口令不进备份：换机后需重建端点并重新配对
- 从 1.5.76 升级会自动迁移数据库；回退到旧版本可能读不到新表，升级前建议先导出一份备份
- 后台保活受厂商限制，部分机型仍需在系统设置里允许自启动/后台运行

🔧 **工程（对用户不可见）**：
- Flutter 3.47.7 / Dart 3.13.5、AGP 9.4.1、Gradle 9.8.2、Kotlin 2.4.21
- 依赖批次升级、CI 发版闸门与格式/静态检查收口

---

**Fnthink Push + remote control + channel system rework + global experience unification (1.6.0)**

🛰️ **Fnthink Push (new)**:
- Two paired devices deliver messages directly — no third-party account and no platform relay; every message is signed by the sender and verified by the receiver, and the server stores delivery metadata only, never the body
- Pairing takes three steps: code/link → approval on the other device → per-item grants; the grant list lives on the receiving device and can be revoked at any time
- New "Fnthink Push" page: receive switch, fetch now, poll interval, online state with "last fetched X seconds ago", inbox and send history
- A received notification can be forwarded to a paired device or an existing webhook channel; the result shows up in push history
- Background keep-alive: exact alarm + WorkManager; after the process is killed, the next round still fetches queued messages

🎛️ **Remote control (new)**:
- Commands come from a paired device and are split into L2 (app actions) and L3 (system settings), granted item by item
- Every execution has a cancellable delay window; results return as two-stage receipts, with failure and cancellation shown separately
- L3 requires either a high-level key or TOTP; repeated failures trip a circuit breaker, and system settings are never changed silently

🧩 **Channel system**:
- All three channel families now share "list page → single-channel detail page"; primary/backup channels fail over automatically and history marks "went via backup"
- New channel health probes, channel status page and device snapshot; "test only" and "test & save" are separate actions
- Fnthink Push joins forwarding and primary/backup routing as the fourth family; every deletion asks for confirmation

🎨 **Experience and UI**:
- Bottom navigation is now Home / Notification Engine / More; the whole app uses Cupertino widgets
- Notification Engine covers battery, temperature, brightness, network and device state; new rule tester and trial run
- Push history gains an "All" tab, delivery status, channel details and per-channel resend
- Long in-page notes are wrapped in bordered boxes; plain-text click targets are replaced with real buttons or inline actions
- Poll interval is configurable from 5–60 s; the no-permission prompt on the app/remote-trigger filter pages is directly tappable

⚠️ **Upgrade notes**:
- Device name, rules, channels, keywords, thresholds, theme and language are all preserved
- Fnthink identity keys and both kinds of secrets are not included in backups: after moving to a new device you must rebuild the endpoint and pair again
- Upgrading from 1.5.76 migrates the database automatically; downgrading may not read the new tables, so export a backup before upgrading
- Background keep-alive is still constrained by vendors; some ROMs require allowing autostart/background running in system settings

🔧 **Engineering (invisible to users)**:
- Flutter 3.47.7 / Dart 3.13.5, AGP 9.4.1, Gradle 9.8.2, Kotlin 2.4.21
- Dependency batch upgrades, CI release gates and format/static checks

### v1.5.76+116 - 2026-09-27

**导航重构 + 三族通道统一 + 通知引擎落地（亮度/网络/温度）+ 主备路由 + 备份补齐**

🧭 **导航与页面结构（改动最大的一处可见变化）**：
- 底部导航从两个 tab 改为**首页 / 通知引擎 / 更多**三段，电量、温度、设备状态告警收进「通知引擎」
- 「规则约束」入口移入「更多」页，并去掉与相邻分组撞色撞图标的问题
- 三族通道（Webhook 机器人 / 邮件 / 自建应用）统一成**列表页 → 单通道详情页**两页形状：
  列表页负责整族动作（复制、启停、删除），详情页只管一条，改一条不会动到另一条
- 新增「通道状态」详情页：三族分组展示、最近一次成功/失败看得见，且带密钥的整条 URL 不再上屏
- 新增「设备状态」分组与快照详情页（型号 / 系统 / 网络 / 电量 / 温度 / 存储 / 内存 / 亮度 / 运行时长），
  并可一键把这份快照推送到自己的通道 —— 读不到的项会明写「这台设备读不到」，不留一片空白
- 卡片长按动作表（历史记录 / 通道 / 规则）收成一个共用组件，三处的菜单形状与滚动行为一致
- 所有删除一律二次确认，且确认写在真正执行删除的那一处

📡 **送达状态与通道配置**：
- 首页通道卡与通道状态页共用同一份健康度缓存与时效口径，不再各算各的
- 「仅测试」与「测试并保存」拆成两个动作：只测不写库，但测试结论照样冒到首页徽标
- 必填项校验改为**点名缺哪个字段**并拒绝保存
- 修复自建应用通道的名称保存后消失
- 三族通道补上非侵入健康探测（应用族只换 token、邮件族只握手），进页自动刷新状态，不发真消息
- **主备路由**：每条通道可设「主」或「备」，主渠道失败时自动改走备用渠道；
  推送历史里会标出这一条**本次走了备用**
- 消息格式档位、模板变量名单、默认主题/正文抄本全部收成一份来源（页面、数据库、原生读同一份）

⚙️ **通知引擎（电量 / 温度 / 设备状态告警）**：
- 电量与温度的判定链抽成同一个引擎（阈值、迟滞、冷却、去重、文案模板只有一份），
  规则改存加密数据库，不再依赖两份镜像
- **亮度与网络成为新的触发维度**：可配「亮度低于某值」「断网时」「联网时」三类规则
- 温度规则新增「试一次」：点了就在原生那份引擎里真跑一遍，弹层里看到的标题/正文
  就是真会推出去的那一份（不会吃掉真实告警的冷却）
- 新增「设备态告警也接受关键词/规则约束」开关，**默认关闭**（开启后亮度、网络告警同样受过滤约束）
- 界面上的「规则引擎」统一改名为**「规则约束」**；修复编辑规则时界面把生效的配置抹掉
- 修复温度规则页保存不刷新、开关回弹

🛰️ **备份与离线缓存**：
- 温度族与设备状态族**进备份/恢复**：换机后这两类规则不再静默消失
- 离线缓存超过 500 条时不再静默丢最旧：丢弃条数会随记录一起交付，
  并在推送历史页顶部提示一次（提示条不是历史记录，关掉即走）

🔒 **兼容与升级**：
- 覆盖升级自检跑通：旧版本上配好的电量/温度规则，覆盖安装后逐项一致（数据库 v11 → v13）
- 并存期仍在做影子比对（新引擎只记账不发送），切换要等差异清零
- 设备名、规则、通道、关键词、阈值、主题、语言等设置在升级后原样保留

⚠️ **升级注意**：
- 通道的主/备角色是新增字段，老通道默认为「主」，行为与升级前一致
- 温度与设备状态规则改存数据库（v13）：若升级后回退到 v1.5.75 或更早版本，这两族新配的规则读不到
- 「设备态告警也接受约束」默认关；打开后设备状态告警会被关键词与应用过滤挡下

🔧 **代码结构（对用户不可见）**：
- 三族发送扇出收口为唯一入口；通道描述符、字段校验、健康度、编解码各收敛为单一实现点
- 发版闸门加了一道硬检查：在模拟器上逐页点击 + 备份导出导入往返，按现场拆成四条独立用例
  并逐条独立运行，某一节挂住时只重试那一条；影子差异条数随发版报告一起打印

---

**Navigation rework + unified channel pages + notification engine (brightness / network / temperature) + primary-backup routing + backup coverage**

🧭 **Navigation and page structure (the biggest visible change)**:
- The bottom bar moves from two tabs to **Home / Notification Engine / More**; battery, temperature and
  device-state alerts now live under "Notification Engine"
- The "Rule Constraints" entry moves into the "More" page and no longer collides with the neighbouring
  group's colour and icon
- All three channel families (webhook bots / email / self-built apps) share one **list page → single-channel
  detail page** shape: the list handles family-wide actions (copy, enable, delete), the detail page edits one
  channel and never touches the others
- New "Channel status" detail page: three families grouped, last success/failure visible, and a full URL that
  carries a key is no longer rendered on screen
- New "Device state" group and snapshot page (model / OS / network / battery / temperature / storage / memory /
  brightness / uptime) with one tap to push that snapshot to your own channels — dimensions this device cannot
  read are labelled "not readable on this device" instead of staying blank
- Long-press action sheets (history record / channel / rule) are now one shared component, so the menu shape
  and scrolling behaviour match in all three places
- Every deletion asks for confirmation, written at the place that actually performs the delete

📡 **Delivery status and channel configuration**:
- The home channel card and the channel status page share one health store and one freshness rule
- "Test only" and "Test & save" are now two actions: testing alone writes nothing, yet its verdict still
  bubbles up to the home badge
- Required-field validation now names the missing field and refuses to save
- Fixed: the name of a self-built app channel disappeared after saving
- All three families gained non-intrusive health probes (app families only exchange a token, email only
  handshakes); pages refresh their status on entry without sending a real message
- **Primary / backup routing**: every channel can be marked primary or backup; when the primary fails the
  message is resent through a backup one, and the push history marks that record as **"went via backup"**
- Message-format options, the template-variable list and the default subject/body templates each collapse
  into a single source that the UI, the database and native code all read

⚙️ **Notification engine (battery / temperature / device-state alerts)**:
- Battery and temperature judging now run through one engine (threshold, hysteresis, cooldown, dedupe and
  message templates exist once); rules moved into the encrypted database instead of two mirrored copies
- **Brightness and network become new triggers**: rules for "brightness below a value", "on disconnect" and
  "on reconnect" can be configured in the UI
- Temperature rules gained a "try once" action: it really evaluates in the native engine, and the title/body
  shown in the sheet is exactly what would be pushed (it does not consume a real alert's cooldown)
- New "device-state alerts also respect keyword/rule constraints" switch, **off by default** (turning it on
  filters brightness and network alerts as well)
- The user-facing name "rule engine" is renamed to **"Rule Constraints"**; editing a rule no longer wipes the
  effective configuration in the UI
- Fixed: the temperature rule page not refreshing after save, and its switch bouncing back

🛰️ **Backup and offline cache**:
- Temperature and device-state rule families are now **included in backup/restore**, so they no longer vanish
  silently after moving to another device
- An offline cache beyond 500 notifications no longer drops the oldest in silence: the dropped count is
  delivered together with the records and shown once at the top of the push history (the notice is not a
  history record and disappears once dismissed)

🔒 **Compatibility and upgrade**:
- The overlay-upgrade self-check passes: battery/temperature rules configured on the old build come out
  item-for-item identical after an in-place upgrade (database v11 → v13)
- The coexistence period still runs shadow evaluation (the new engine only records, never sends); switching
  the main path awaits a zero diff
- Device name, rules, channels, keywords, thresholds, theme and language settings are preserved on upgrade

⚠️ **Upgrade notes**:
- Primary/backup role is a new field; existing channels default to "primary" and behave as before
- Temperature and device-state rules now live in the database (v13): if you downgrade to v1.5.75 or earlier
  after upgrading, rules newly configured in these two families will not be readable
- "Device-state alerts also respect constraints" is off by default; enabling it subjects those alerts to the
  keyword and app filters too

🔧 **Code structure (invisible to users)**:
- Channel fan-out has a single entry point; descriptors, field validation, health and codecs each converge
  into one implementation
- The release gate adds a hard check: page-by-page tapping plus a real backup export/import round trip on an
  emulator, split into four independent cases each run in its own process, with a single retry only for the
  case that hangs; the shadow-diff count is printed into the release report

### v1.5.75+115 - 2026-09-24

**送达状态判定修正 + 备份恢复兼容 + 应用列表权限三态 + 通道表单统一**

📡 **推送送达状态（多项误判修复）**：
- 自建 / 私有化部署的通道不再被按 URL 猜成「通用 Webhook」：Grafana、Gotify、自建 ntfy 等按你在应用里选定的类型判定返回内容
- 私有部署的自建应用通道返回 `errcode` 时不再被误报为「已送达」（原来错误响应也会打成功徽标）
- 飞书 token 过期（以 `code=` 返回错误码的形式）现在能正确识别并触发自动换票重试
- 首页通道状态不再出现中英双键导致的徽标重复 / 永远「发送中」：送达记录改用与界面语言无关的稳定键
- 同一类型的多个通道不再重复写同一条送达状态（例如两个企微机器人原来会产生两个相同徽标）
- 通道健康度（最近一次成功 / 失败）三族共用一份缓存与时效口径，邮件通道不再单独走一套

🛰️ **备份与恢复（重要修复）**：
- 修复**导入备份后打不开 Webhook 设置页**的问题（旧备份或数据库回读的数据形状不一致会让页面直接抛异常）
- 修复恢复后通道类型丢失（一堆通道全变成「通用 Webhook」）
- 修复恢复备份时**静默丢弃**自建 `http://` 通道：校验只允许 https，而原生发送两种都收，现在两种都保留
- 保存时缺少协议头的地址（如 `ntfy.sh/topic`）会**点名是第几行**不合法并拒绝保存，不再静默存下无法发送的配置
- 恢复过程中某一项失败不再中断整批：会明确提示「部分类别失败 / 跳过 N 项」并列出失败类别（原来只显示"完成"）
- 兼容 v1.5.73 及更早版本的备份：规则、关键词、应用筛选等字段容忍历史形状（如 0/1 表示开关），不再整条报错

🔒 **应用列表权限（隐私）**：
- 系统拒绝「访问应用列表」后，不再通过桌面查询绕过限制读取已安装应用
- 权限页改为三态显示（已授予 / 未授予 / 仅部分可见），且权限被拒时立即清空本机应用列表缓存

🧩 **通道表单统一**：
- Slack / Discord / Gotify / ntfy / Server酱 / PushPlus 六类不再显示对它们无效的「消息格式 / 自定义模板」项
- 自建应用通道必填项改为保存前拦截并点名缺哪个字段；成员 / 接收者一类字段留空时按官方默认值处理
- 六个第三方平台的接入说明文案定稿（原来复用企业微信文案）
- 通道名去掉内部前缀，统一显示为可读名称（通用一类显示「通用 Webhook」）

🎨 **界面细节**：
- 修复历史页、规则页、应用通道页等底部弹层**点击水波纹被底色遮住**的问题（同一类问题在开发模式下会直接抛渲染告警）

⚠️ **升级注意**：
- 本次包含一次**单向**的送达记录键迁移（数据库 v10 → v11）。升级后若回退到 v1.5.74 或更早版本，历史记录里的通道会显示成内部键且送达状态丢失。**升级前建议先到「备份与恢复」导出一份备份。**
- 常规设置（规则、通道、关键词、阈值、主题、语言等）不受影响，覆盖安装后原样保留。

🩹 **启动与生命周期**：
- 修复主页面在异步装配过程中被销毁时抛 `setState() called after dispose()` 的问题 —— 该异常会被外层 catch 吞掉，**连带跳过首启引导与延迟启动前台服务那一段**（表现为进入首页后部分启动动作没跑）
- 同类写法新增了一道机器守卫（只降不升），防止再出现「await 之后不判存活就刷新界面」

🔧 **代码结构（对用户不可见）**：
- 通道相关的判定、编解码、聚合、健康度、URL 校验各收敛为单一实现点，双端通道类型表由契约测试锁定
- 新增发版硬闸门：在模拟器上逐页点击 + 备份导出导入往返，任一步失败即禁止发版

---

**Delivery-status corrections + backup restore compatibility + app-list permission states + unified channel forms**

📡 **Push delivery status (several mis-verdicts fixed)**:
- Self-hosted / privately deployed channels are no longer guessed as "Generic Webhook" from the URL: Grafana, Gotify, self-hosted ntfy etc. are now evaluated with the type you selected in the app
- A privately deployed app channel returning `errcode` is no longer reported as delivered (error responses used to get a success badge)
- Expired Feishu/Lark tokens (errors returned as `code=`) are now recognized and trigger automatic token refresh and retry
- The channel status page no longer shows duplicate badges or a permanent "sending" state caused by language-dependent keys: delivery records now use stable keys independent of the UI language
- Multiple channels of the same type no longer write the same delivery status twice (two WeCom bots used to produce two identical badges)
- Channel health (last success / failure) now shares one store and one freshness rule across all three families; email no longer runs on its own

🛰️ **Backup and restore (important fixes)**:
- Fixed the Webhook settings page **failing to open after importing a backup** (shapes coming from old backups or from the database used to throw during page init)
- Fixed channel types being lost after restore (everything collapsing into "Generic Webhook")
- Fixed self-hosted `http://` channels being **silently dropped** on restore: validation only accepted https while the native sender accepts both; both are now kept
- When saving, an address without a scheme (e.g. `ntfy.sh/topic`) is now rejected **by row number** instead of being stored as unsendable configuration
- A failure in one restore category no longer aborts the whole restore: it now reports "some categories failed / N items skipped" and lists which ones (it used to just say "done")
- Backups made by v1.5.73 and earlier are tolerated: rules, keywords and app-filter fields accept historical shapes (e.g. 0/1 for switches) instead of erroring out

🔒 **App-list permission (privacy)**:
- After the OS denies "access to installed apps", the app no longer bypasses the restriction via launcher queries
- The permission page now shows three states (granted / denied / partially visible), and the local app-list cache is cleared immediately when access is denied

🧩 **Unified channel forms**:
- Slack / Discord / Gotify / ntfy / ServerChan / PushPlus no longer show "message format / custom template" options that never applied to them
- Required fields on self-built app channels are validated before saving and name the missing field; recipient-style fields fall back to official defaults when left empty
- Onboarding hints for the six third-party platforms were finalized (they previously reused the WeCom wording)
- Channel names lose their internal prefixes and show readable names (the generic family reads "Generic Webhook")

🎨 **UI details**:
- Fixed bottom sheets on the history, rule and app-channel pages **hiding the tap ripple** behind their own background color (the same condition raises a rendering warning in debug builds)

⚠️ **Upgrade notes**:
- This release contains a **one-way** delivery-key migration (database v10 → v11). If you later downgrade to v1.5.74 or earlier, channels in history rows will show internal keys and their delivery status will be lost. **Export a backup from "Backup & restore" before upgrading.**
- Regular settings (rules, channels, keywords, thresholds, theme, language, etc.) are unaffected and survive an in-place upgrade.

🩹 **Startup and lifecycle**:
- Fixed `setState() called after dispose()` on the main page when it is destroyed mid-way through its asynchronous assembly chain — the exception was swallowed by an outer catch and **skipped the first-launch guidance and the delayed foreground-service start** (visible as some startup actions never running)
- Added a machine guard (shrink-only) that counts "setState after await without a mounted check", so the pattern cannot spread further

🔧 **Code structure (not user visible)**:
- Verdict logic, encoding, aggregation, health and URL validation for channels each collapsed into a single implementation point, with the cross-platform channel type table locked by contract tests
- Added a hard release gate: page-by-page clicking plus a real backup export/import round trip on an emulator; any failure blocks the release

---

### v1.5.74+113 - 2026-09-21

**温度推送入口补全 + 更多页通道状态显示 + 分享按钮词条修复**

🌡️ **温度推送入口**：
- 「更多」页新增**温度推送**独立入口（此前温度规则页只能从电量页跳转），副标题直陈「电池 / 设备 / 屏幕温度阈值推送」
- 自建应用通道条目改为显示实际状态：**已配置 N 个 · 启用 M 个**（未配置时显示「未配置」），不再只有一句固定说明

📄 **分享按钮词条修复**：
- 修复 v1.5.74+112 文本选择菜单接入时**遗漏 share 按钮的词条映射**导致「分享」按钮显示为空白的缺陷（中英两版均补齐）

🔧 **代码结构**：
- 主页面动作逻辑（跳转/弹窗/系统交互）从 `main_page.dart` 抽到 `main_page_actions.dart`，主文件回归组装职责
- 移除主页面多余的 `setState` 调用（build 期触发状态更新导致的无效重建与告警）

---

**Temperature entry in More page + app channel status display + share button label fix**

🌡️ **Temperature push entry**:
- Added a dedicated **temperature push** entry on the "More" page (previously the temperature rule page was only reachable from the battery page); subtitle states "battery / device / screen temperature threshold push"
- Self-built app channel row now shows real state: **N configured · M enabled** (or "not configured"), instead of a static hint

📄 **Share button label fix**:
- Fixed the blank "Share" button caused by a missing i18n mapping for the share action in the v1.5.74+112 text-selection menu rollout (both zh and en)

🔧 **Code structure**:
- Extracted page actions (navigation / dialogs / system interaction) from `main_page.dart` into `main_page_actions.dart`, leaving the main file as composition only
- Removed a redundant `setState` on the main page that caused an invalid rebuild during build phase

---

### v1.5.74+112 - 2026-09-21

**温度推送 + 应用通道分层展示 + 文本菜单多机型适配 + 弹窗风格统一**

🌡️ **手机温度推送（新功能）**：
- 新增电池温度 / 设备整体温度 / 屏幕温度三维度独立规则，自定义阈值触发推送
- 电池温度来自 BatteryManager（精确 0.1℃）；设备整体取最热温区；屏幕温度探测式支持
- 触发后 30 分钟冷却防温度波动重复推送；与电量推送同源同轮询（联动不冲突）

🏢 **自建应用通道分层展示 + 表单校验**：
- 设置页改为分层展示：总列表页仅显示通道名称、类型、连接状态，点击进入详情页编辑
- 保存前校验必填字段（名称 / API 地址不能为空），未填写完整禁止保存并提示
- 保存成功后自动发起连接测试，结果通过状态徽标展示
- 修复首页推送状态页自建应用通道名称和类型显示空白的问题

📄 **文本选择菜单多机型适配**：
- 36 处文本组件的菜单按钮文案（复制/剪切/粘贴/全选/分享）统一改为应用内词条
- 彻底消除厂商 ROM 上菜单按钮显示英文或空白的问题

🎨 **弹窗风格统一**：
- 全部确认弹窗统一为 iOS 分割线按钮布局（cardBg + 圆角 14 + destructive 红色删除）
- 新增温度推送独立设置页（TemperaturePage），与电池推送同级独立入口

🔧 **其他改进**：
- 常驻通知状态机优化（开始/停止/进程终止/自启动保活/权限缺失 5 场景显隐统一）
- 历史页右上角收纳为「更多」菜单；备份扩展至 12 类；token 解析崩溃防护

**Temperature push + app channel layered UI + text menu adaptation + dialog style unification**

🌡️ **Device Temperature Push (New)**:
- Battery / device overall / screen temperature — three independent rule dimensions with custom threshold triggers
- Battery temp from BatteryManager (precise 0.1°C); device overall from hottest thermal zone; screen temp detection-based
- 30-minute cooldown after trigger prevents fluctuation re-pushes; shares polling source with battery push (no conflict)

🏢 **App Channel Layered UI + Form Validation**:
- Settings page now layered: list page shows channel name, type and connection status only; tap to enter detail editing
- Required-field validation before save (name / API URL cannot be empty), blocked with prompt if incomplete
- Auto connection test fires after successful save, results shown via status badge
- Fixed blank channel name and type on home page push status for self-built app channels

📄 **Text Selection Menu Multi-Device Adaptation**:
- Menu button labels (copy/cut/paste/select all/share) for all 36 text components unified to app-localized strings
- Completely eliminates blank or English labels on vendor ROMs

🎨 **Dialog Style Unification**:
- All confirm dialogs unified to iOS divider button layout (cardBg + radius 14 + destructive red delete)
- New standalone TemperaturePage with same-level entry as battery push

🔧 **Other Improvements**:
- Notification state machine optimization (start/stop/process kill/keep-alive/permission missing — 5 scenarios unified show/hide)
- History page top-right consolidated into "More" menu; backup expanded to 12 types; token parse crash protection

---

### v1.5.73+110 - 2026-09-19

**企业微信自建应用通道 + 规则模板库 + 送达统计仪表盘 + 通道健康探测**

📡 **企业微信自建应用通道（新，通道总数 13）**：
- 支持企业微信**自建应用**推送（区别于群机器人）：两阶段请求（gettoken 换 access_token → message/send），支持指定接收人（touser，默认 @all）与 text / markdown 消息格式。
- **token 智能管理**：access_token 内存缓存 + 过期前 5 分钟提前刷新，并发推送只换取一次；服务端返回 40014/42001（token 失效）时自动清缓存换新 token 重试一次。
- 配置方式：通道类型选「企业微信自建应用」→ 填写 corpid、agentid 与 corpsecret（密钥字段）→ 可选填写接收人；正文上限 2048 字节自动截断。
- 数据库升级至 v9（新增通道扩展配置字段，老数据无损升级）。

📚 **规则模板库（新功能）**：
- 内置 5 套预设模板：验证码优先推送 / 营销广告拦截 / 夜间免打扰 / 社交消息聚合（60 秒窗口满 5 条提前）/ 白名单关键词直通，一键导入。
- 规则卡片新增「存为模板」：把自定义规则保存为个人模板（同名覆盖），随时复用。
- 模板导入导出：支持导出 `.json` 文件分享；导出时可设置口令（AES-256 加密，与配置备份同源算法），导入自动识别明文/加密格式。

📊 **送达统计仪表盘（统计页新增「送达健康」）**：
- **通道成功率排行**：各通道推送数 / 成功数（绿 / 橙 / 红分级），一眼看出哪个通道出问题。
- **失败原因 TOP**：按 HTTP 状态码聚类（502 / 429 / 网络失败等），定位共性问题。
- **高峰时段分布**：24 小时通知量柱状图，了解消息节奏。
- 支持近 7 天 / 近 30 天切换，数据来自送达日志与通知记录聚合。

💚 **通道健康探测**：
- Webhook 设置页自动对启用通道做轻量连通探测（默认 6 小时刷新一次），通道卡片显示「✓ 连通 · 延迟 · 探测时间」徽标，通道挂了第一时间发现，不再等推送失败才知道。

🛠 **其他**：
- 规则测试器、应用选择等页面体验细节优化。
- 🔁 **重建说明（+109 → +110）**：构建后修复两处问题并纳入本包——① 企业微信自建应用多通道 token 缓存改为按凭据分 key（多通道互不驱逐、失效仅定向清除该凭据）；② 通道扩展配置 extra_config 的 JSON 编码统一上移至服务层（DB 行契约不变）。

---

📡 **WeCom Self-built App Channel (new, 13 channels total)**:
- Push via WeCom **self-built apps** (distinct from group robots): two-phase requests (gettoken for access_token → message/send), targeted recipients (touser, default @all), and text / markdown formats.
- **Smart token management**: access_token cached in memory with refresh 5 minutes before expiry; concurrent pushes fetch only once; on 40014/42001 (token expired) the cache is cleared and the send retried once with a fresh token.
- Setup: pick "WeCom App" channel type → fill in corpid, agentid and corpsecret (secret field) → optionally set recipients; content over 2048 bytes is auto-truncated.
- Database upgraded to v9 (new channel-extension field; lossless upgrade for existing data).

📚 **Rule Template Library (new)**:
- Five built-in presets: verification-code priority / marketing-block / night do-not-disturb / social-message aggregation (60s window, flush at 5) / whitelist-keyword express — one-tap import.
- "Save as Template" on rule cards: keep custom rules as personal templates (same name overwrites) for reuse anytime.
- Import/export: share templates as a `.json` file; optionally set a password on export (AES-256, same algorithm as config backup); import auto-detects plain/encrypted.

📊 **Delivery Health Dashboard (new section in stats)**:
- **Channel success-rate ranking**: pushes vs successes per channel (green / orange / red), so a failing channel is obvious at a glance.
- **Top failure reasons**: clustered by HTTP status (502 / 429 / network failures) to spot common problems.
- **Peak-hours distribution**: 24-hour bar chart of notification volume.
- Toggle between last 7 / 30 days; data aggregated from delivery logs and notification records.

💚 **Channel Health Probe**:
- The webhook settings page now light-probes enabled channels (refreshed every 6 hours by default); each channel card shows a "✓ reachable · latency · probe time" badge, so a broken channel is caught immediately instead of after failed pushes.

🛠 **Other**:
- Minor UX polish across the rule tester and app pickers.
- 🔁 **Rebuild note (+109 → +110)**: two post-build fixes are included in this package — ① the WeCom App multi-channel token cache is now keyed per credential (no cross-eviction, targeted invalidation only); ② the extra_config JSON encoding is unified in the service layer (DB row contract unchanged).

### v1.5.72+108 - 2026-09-14

**规则适用应用选择：快速选择分组 + 空表问题修复**

🧭 **适用应用「快速选择」分组（新功能）**：
- 规则编辑页的「选择适用应用」新增顶部快速选择区：自动识别手机上**已安装**的主流通讯与邮箱类应用，未安装的不显示。
- 通讯区聚合呈现：系统短信组件（信息 / 短信存储）合并为一行「短信」，系统电话组件（拨号器 / 通话界面 / 电话服务）合并为一行「电话」，避免出现用户无法理解的系统组件名；微信、QQ、企业微信、飞书、钉钉、Telegram、X、WhatsApp、Messenger、LINE、Signal、Discord、Slack 等第三方应用逐行显示。
- 邮箱区：Gmail、Outlook、QQ 邮箱、网易邮箱、Samsung Email、Yahoo Mail、Proton Mail、Spark、Thunderbird 等已安装的邮箱应用。
- 短信 / 电话聚合行支持一键整组开关，状态三态显示（全部适用 / 全部排除 / 部分适用）；其余应用归入下方「其他应用」。
- 全选 / 清空 / 反选现在覆盖快速选择与其他应用的全部可见项，搜索关键字对快速选择区同步生效。

🐛 **修复**：
- 修复规则引擎「选择适用应用」页面应用列表恒为空（显示「没有找到应用」）的问题：根因是 MethodChannel 返回的列表以无类型变量接收后做泛型转换，触发隐式类型转换异常，缓存与全量加载均静默失败；右上角「更新软件列表」手动刷新同因失效，一并修复。新增回归测试锁定正确的列表接收写法。

---


**Rule "applicable apps" picker: Quick Select group + empty-list fix**

🧭 **"Quick Select" group for applicable apps (new)**:
- The "Select Applicable Apps" page in rule editing now has a Quick Select area at the top: it automatically detects mainstream messaging and email apps **installed** on the phone — uninstalled ones are never shown.
- The Messaging section is aggregated: system SMS components (Messages app / SMS storage) are merged into a single "SMS" row, and system phone components (dialer / in-call UI / phone service) into a single "Phone" row, avoiding system component names users can't recognize. Third-party apps such as WeChat, QQ, WeCom, Feishu/Lark, DingTalk, Telegram, X, WhatsApp, Messenger, LINE, Signal, Discord, and Slack are listed individually.
- The Email section lists installed email apps: Gmail, Outlook, QQ Mail, NetEase Mail, Samsung Email, Yahoo Mail, Proton Mail, Spark, Thunderbird, and more.
- The SMS / Phone rows toggle the whole group in one tap with a three-state indicator (all applied / all excluded / partially applied); all other apps go under "Other Apps" below.
- Select All / Deselect All / Invert now cover every visible item across Quick Select and Other Apps, and search keywords filter the Quick Select area as well.

🐛 **Fixes**:
- Fixed the rule engine "Select Applicable Apps" page always showing an empty list ("No apps found"): the MethodChannel result was received in an untyped variable and then generically converted, triggering an implicit cast exception so both cached and full loads failed silently; the top-right "Refresh" action failed for the same reason and is fixed too. Regression tests now lock in the correct list-decoding pattern.

### v1.5.71+107 - 2026-09-13

**通道扩展（ntfy / Gotify / Slack / Discord）+ 历史快捷屏蔽与适用应用选择页修复**

📡 **通道扩展（新功能）**：
- 新增 4 个推送通道，全部经 ChannelRegistry 描述符表接入（golden 快照与完整性守卫同步扩充）：
  - **ntfy**：header 模式（标题走 HTTP Header，正文即消息文本），支持官方 ntfy.sh 与自建服务器；可选访问令牌（Bearer）。
  - **Gotify**：向自建服务器推送，应用 Token 走密钥字段（不进 URL 明文与日志）；缺失时提前失败并明确提示。
  - **Slack**：Incoming Webhook 直发，URL 即凭据无需签名。
  - **Discord**：Webhook 直发，正文上限 2000 字符自动截断；429 限流按 retry_after 识别。
- **自建服务器支持**：ntfy.sh 官方地址可自动识别；自建服务器 host 不可枚举，手动选择通道类型后保存/发送/测试全链路生效，识别提示区尊重手动选择（不再误显示「通用 Webhook」）。

🐛 **历史快捷屏蔽修复（真机反馈）**：
- 修复「全部推送」模式（白名单为空）下长按屏蔽的两处缺陷：菜单误提示「该应用当前已不在推送范围」（实际正在推送）、点击屏蔽实际不生效（从空名单移除等于无操作）。
- 现点击后切换为黑名单模式并屏蔽目标应用，**其余应用推送行为完全不变**；菜单打开前强制刷新过滤配置，消除冷启动未加载导致的误判。

🧭 **规则「适用应用」选择页对齐应用筛选页**：
- 新增已选/未选分组（有排除时「适用 N」置顶 +「已排除 N」）、全选（全部适用）/ 全不适用 / 反选快捷操作、AppBar 强制重扫按钮（Flyme 等机型扫描不全时可直接重扫补全）。

🛠️ **工程**：
- 发版脚本 release_local.sh 补 sha256 回填（四架构校验值与 CDN 侧闭环）与 README 徽章/update.md 缺项显式检查。
- 服务端 Express 升级 5.x（qs moderate 漏洞清零，25 个契约测试回归通过）。

---


📡 **Channel expansion (new)**:
- Four new push channels, all wired through the ChannelRegistry descriptor table (golden snapshots and completeness guards extended):
  - **ntfy**: header mode (title via HTTP header, body is the message text); official ntfy.sh and self-hosted servers supported; optional Bearer access token.
  - **Gotify**: push to self-hosted servers; the application token lives in the secret field (never in URLs or logs); fails fast with a clear message when missing.
  - **Slack**: direct Incoming Webhook posting; the URL itself is the credential, no signing needed.
  - **Discord**: Webhook posting with 2000-char content truncation; 429 rate limits honored via retry_after.
- **Self-hosted servers**: ntfy.sh is auto-detected; self-hosted hosts cannot be enumerated — pick the channel type manually and the whole chain (save / send / test) respects it, and the URL hint no longer misleadingly shows "Generic Webhook".

🐛 **History quick-block fixes (device feedback)**:
- Fixed two defects of long-press blocking under "push everything" mode (empty allowlist): the menu misleadingly claimed "not in push scope" for apps that *were* being pushed, and tapping had no effect (removing from an empty list is a no-op).
- Tapping now switches to blocklist mode and blocks the target app while **other apps keep pushing exactly as before**; the filter config is force-refreshed before the menu opens, eliminating cold-start misjudgment.

🧭 **Rule "applicable apps" picker aligned with the app-filter page**:
- Applied/Excluded grouping (Applied N pinned, Excluded N below), select-all / deselect-all / invert quick actions, and an AppBar force-rescan button (directly benefits the Flyme scan-completeness fix).

🛠️ **Engineering**:
- release_local.sh now backfills sha256 (closing the loop with CDN-side verification) and explicitly checks for missing README badges / update.md entries.
- Server upgraded to Express 5.x (qs moderate vulnerability eliminated; all 25 contract tests pass).

### v1.5.70+106 - 2026-09-11

**真机反馈修复 + 界面统一**

🛠️ **问题修复（真机反馈）**：
- 修复规则「适用应用」选择页在部分机型上反复提示无权限、无法显示应用列表的问题（权限判定与扫描结果解耦，与应用筛选页行为一致）。
- 修复长按屏蔽菜单在部分场景误显示「该应用已不在推送范围，无需操作」的误导提示——现按实际推送链路给出准确状态（本应用自身通知由电量规则控制等）。

🎨 **界面统一（体验优化）**：
- 通知详情改为底部弹层展示（详情/送达日志/屏蔽操作一体化）。
- 推送历史右上角图标收纳为「更多」菜单（批量补推/导出/归档路径/清空记录）。
- 全部确认弹窗统一为 iOS 风格分割线按钮布局；导出确认等弹窗补齐多语言。

**Device feedback fixes + UI consistency**

🛠️ **Fixes (device feedback)**:
- Fixed the rule "applicable apps" picker repeatedly claiming no permission and showing an empty list on some devices (permission verdict decoupled from scan result, consistent with the app-filter page).
- Fixed the long-press block menu misleadingly showing "not in push scope, no action needed" in some cases — the subtitle now reflects the actual push path.

🎨 **UI consistency (improvements)**:
- Notification details now open as a bottom sheet (details / delivery logs / block actions in one place).
- History page top-bar icons consolidated into a "more" menu (batch re-push / export / archive path / clear).
- All confirmation dialogs unified to iOS-style divider buttons; export dialogs now fully localized.

### v1.5.69+104 - 2026-09-11

**规则测试器 + 推送可靠性大版本（漏通知修复 / 批量补推 / 聚合深化）**

🧪 **规则测试器（新功能）**：
- 规则列表页新增「规则测试器」：输入模拟通知（应用选择器 + 标题/内容/优先级），实时展示完整命中链路——过滤结果 → 命中规则明细 → 最终动作（含聚合窗口、提前触发条数、会话分组），排查规则问题不再靠猜。

📵 **锁屏后台漏通知修复（问题修复）**：
- 修复长时间锁屏/后台后偶发漏通知的问题：系统回收进程期间到达的通知事件会永久丢失，且通知仍留在通知栏却永远不会被补读。现服务启动时按持久化水位自动补扫通知栏中仍驻留的未处理通知（最长回溯 6 小时，双水位防重复）。
- 划掉最近任务后主动排程服务重启，减小监听空窗。
- 短信通知栏兜底链路的分发作用域收敛，避免进程回收时丢失。

📤 **失败记录批量补推（新功能）**：
- 推送历史页新增「批量补推」：筛选失败记录后可多选（默认全选失败项）并一键重新推送，带二次确认与进度反馈；顺带修复了全量搜索打开的旧记录无法补推的问题。

📦 **聚合深化（新功能）**：
- 聚合动作新增「满 N 条提前推送」：达到设定条数立即发出，无需等窗口到点。
- 新增「按会话分组」：同一应用不同联系人/群的分开聚合，不再混在一条里。
- 聚合推送自定义模板支持新变量 `%count%`（条数）与 `%titles%`（成员标题摘要）。

🚨 **Bark 通道判定修复（问题修复）**：
- 修复 Bark 推送业务失败（如参数错误 400、路径错误 404）被误标为「推送成功」的问题，失败现在会如实显示；限流（429）按可重试处理。

💾 **备份范围补齐（新功能）**：
- 配置备份从 7 类扩展到 11 类：新增电池规则与电量开关、设备名、主题/语言；旧备份文件仍可正常恢复。
- 备份格式升级为 v2（向后兼容 v1）。

🛠️ **稳定性（问题修复）**：
- 推送失败自动重试：网络恢复或服务重启时自动重发最近失败的推送（加密存储、最多 3 次、24 小时内）。
- 权限判定修复：部分机型上「读取应用列表」权限误报已授权的问题根治。
- 诊断日志改为运行时开关（关于页连点版本号 7 次开启），排查问题无需重新安装。
- 修复sha256 传输层校验（下载完成后、安装前校验安装包完整性，防 CDN 传输损坏）。
- 历史记录新增快捷屏蔽：长按即可屏蔽该应用或含此内容的通知。

**Rule tester + push reliability release (missed-notification fix / batch re-push / merge deepening)**

🧪 **Rule Tester (new)**:
- New "Rule Tester" on the rule list page: enter a simulated notification (app picker + title/content/priority) and see the full trace in real time — filter result → matched rule details → final action (merge window, early-flush count, conversation grouping). No more guessing why a rule did or didn't fire.

📵 **Missed-notification fix for locked screen & background (fixes)**:
- Fixed occasional missed notifications after long screen-off/background periods: events arriving while the OS had recycled the process were lost forever, even though the notification was still sitting in the shade. The service now automatically re-scans still-visible notifications on startup using a persisted watermark (up to 6 hours back, dual watermark prevents duplicates).
- Schedules a service restart 1 second after the user removes the app from Recents, shrinking the listener gap.
- The SMS notification-fallback path now uses a properly managed coroutine scope.

📤 **Batch re-push for failed records (new)**:
- Push history adds "Batch re-push": filter failed records, multi-select (failed items pre-selected), and re-push in one tap with confirmation and progress feedback. Also fixed old records opened from full-history search being silently skipped on re-push.

📦 **Merge deepening (new)**:
- Merge action supports "flush early at N items": push as soon as the group reaches the configured count, without waiting for the window.
- New "group by conversation": same app but different contacts/groups aggregate separately.
- Custom merge templates support new variables `%count%` (item count) and `%titles%` (member title digest).

🚨 **Bark delivery-status fix (fixes)**:
- Fixed Bark business failures (e.g. 400 bad request, 404 wrong path) being mislabeled as "push success"; failures now show truthfully, and 429 rate limits are retried.

💾 **Backup scope completed (new)**:
- Config backup expanded from 7 to 11 categories: battery rules & switch, device name, theme/language; old backup files remain restorable.
- Backup format upgraded to v2 (backward compatible with v1).

🛠️ **Stability (fixes)**:
- Auto-retry for failed pushes: on network recovery or service restart, recently failed pushes are resent (encrypted storage, up to 3 attempts within 24 hours).
- Root-fixed a false "granted" report for the Query All Packages permission on some ROMs.
- Diagnostic logs are now a runtime switch (tap the version number 7 times on the About page) — no reinstall needed for troubleshooting.
- Added sha256 transport-layer verification (integrity checked after download, before install; protects against CDN corruption).
- Push history adds quick block actions: long-press to block the app or notifications containing this content.

### v1.5.68+103 - 2026-09-11

**聚合推送双根因修复 + 规则引擎适用应用与优先级增强**

🛠️ **聚合推送两大根因修复（问题修复）**：
- 修复聚合推送在部分设备上完全不生效的核心问题：规则配置在同步到系统通知引擎时丢失了条件数据，导致引擎收到的规则为空、所有通知都直接推送。现已完整修复，规则真正生效。
- 修复合并推送后成员记录卡在「发送中」的问题：同一应用连发的消息会产生相同的记录标识，导致只有最后一条被更新。现每条消息独立标识，合并推送后所有成员都会如实标注真实送达状态。
- 顺带修复同一消息记录在数据库中互相覆盖的隐患。

📦 **聚合行为优化（体验优化）**：
- 聚合窗口期内只收到一条消息时，不再以「合并推送」形式发出，而是直接按普通推送立即展示原始内容。
- 合并窗口时长确认可在规则编辑中自定义（默认 60 秒，最小 5 秒）。

🧠 **规则引擎增强（新功能）**：
- 新增规则级「适用应用」：每条规则可单独排除不适用的应用，默认适用于全部应用；支持一键全选，系统短信与电话分组固定在列表顶部。
- 规则优先级支持自定义输入：快捷档位（0/10/50/100/200/500）之外，可直接输入 0-500 的任意整数。

🖥️ **系统体验（问题修复）**：
- 关闭 Android 16 预见式返回动画，返回手势恢复为经典即时返回行为。

**Merged-push double root-cause fixes + rule engine app scope & priority enhancements**

🛠️ **Two root-cause fixes for merged push (fixes)**:
- Fixed the core issue where merged push never took effect on some devices: rule conditions were lost while being synced to the native notification engine, so the engine received an empty rule table and every notification was pushed directly. Fully fixed — rules now really take effect.
- Fixed member records stuck at "Sending" after a merged push: rapid messages from the same app produced identical record IDs, so only the last record got updated. Each message now has a unique ID, and all members are faithfully labeled with their real delivery status after the merge.
- Also fixed a hidden issue where same-ID records silently overwrote each other in the database.

📦 **Aggregation behavior improvements (improvements)**:
- When only one message arrives during the aggregation window, it is no longer delivered as a "merged push" — it is sent immediately as a normal push with the original content.
- Confirmed the merge window duration is configurable in rule editing (60s by default, 5s minimum).

🧠 **Rule engine enhancements (new)**:
- New rule-level "Applicable Apps": each rule can exclude specific apps, and applies to all apps by default; one-tap select-all, with system SMS & phone groups pinned to the top of the list.
- Rule priority now supports custom input: besides quick presets (0/10/50/100/200/500), any integer between 0 and 500 can be entered.

🖥️ **System experience (fix)**:
- Disabled the Android 16 predictive back animation; the back gesture returns to the classic instant-back behavior.

### v1.5.67+102 - 2026-09-10

**应用通知聚合落地 + 聚合推送可靠性修复 + 备份说明重写**

📦 **应用通知聚合（新功能）**：
- 新增预制「应用通知聚合」规则，默认开启：同一应用的通知在 60 秒窗口内自动合并为一条推送，窗口结束统一发出，显著减少高频消息轰炸。
- 规则条件支持 `*` 通配符匹配任意应用包名，一次配置即可对所有应用生效。
- 修复默认规则未下发导致预制规则不生效的问题：首次安装会写入全部预制规则，老版本升级会自动补齐缺失项（不会覆盖您手动关闭的规则）。

🛠️ **聚合推送可靠性（问题修复）**：
- 修复聚合推送失败时，成员记录被误标记为「已合并推送」的严重问题，现如实回传真实送达结果与失败原因——不会再出现「显示已推送但实际没收到」的情况。
- 修复历史聚合兜底推送因未注入通道配置而从未真正发出的问题，聚合兜底与到点推送现共用同一套实现。
- 优化聚合推送内部流程，避免推送时前台界面卡顿。
- 无论聚合推送成功或失败，成员通知内容都会先完整保存到推送历史，不会因聚合而丢失。

🔐 **备份与恢复说明（体验优化）**：
- 重写备份与恢复的中英文说明文案，清晰说明备份包含的内容、数据限制与加密特性。
- 恢复时补充密码提示与操作指引，避免忘记密码导致恢复失败。

⚡ **应用列表（体验优化）**：
- 为应用列表增加 24 小时缓存，日常打开应用过滤页无需重新全量扫描，加载更快。
- 下拉刷新会强制重新扫描，确保新安装的应用立即可见。

🌐 **界面语言（问题修复）**：
- 修复系统语言与 App 界面语言不一致的问题：冷启动时会将 App 当前语言同步到系统侧，最近任务、桌面图标名称与前台通知标题显示更一致。

**App notification aggregation + merged-push reliability fixes + rewritten backup docs**

📦 **App notification aggregation (new)**:
- New built-in "App Notification Aggregation" rule, enabled by default: notifications from the same app are merged into a single push within a 60-second window and sent together when it ends, greatly reducing message floods.
- Rule conditions support the `*` wildcard to match any app package name, so one rule covers every app.
- Fixed built-in rules not taking effect because they were never propagated to the native side: a fresh install now writes all built-in rules, and upgrades automatically fill in any missing ones (rules you turned off manually are never overwritten).

🛠️ **Merged-push reliability (fixes)**:
- Fixed a serious issue where member records were wrongly marked as "Delivered as merged push" when the merged push had failed — the real delivery result and failure reason are now reported faithfully, so you will no longer see "pushed" while nothing was actually delivered.
- Fixed the historical fallback push for aggregated groups never actually sending because channel configuration was not injected; the fallback and the scheduled flush now share one implementation.
- Optimized the internal merged-push flow to avoid UI stutter while pushing.
- Whether a merged push succeeds or fails, each member notification's content is saved to push history first, so nothing is ever lost due to aggregation.

🔐 **Backup & restore docs (improvement)**:
- Rewrote the Chinese and English backup/restore descriptions to clearly explain what a backup contains, its limits, and its encryption properties.
- Added password hints and step-by-step guidance during restore to avoid failures caused by a forgotten password.

⚡ **App list (improvement)**:
- Added a 24-hour cache for the app list: opening the app filter page day to day no longer triggers a full rescan, so it loads faster.
- Pull-to-refresh forces a fresh scan so newly installed apps appear right away.

🌐 **UI language (fix)**:
- Fixed a mismatch between the system language and the app's interface language: on cold start the app's current language is now synced to the native side, so the recents card, launcher icon label, and foreground notification title stay consistent.

### v1.5.66+101 - 2026-09-08

**历史全量搜索筛选 + 聚合推送 + 取消历史保存上限**

🔍 **推送历史搜索与筛选（新功能）**：
- 取消 500 条保存上限：全部推送历史完整保存于数据库，历史页可滚动浏览全部记录，不再只保留最近 500 条。
- 新增筛选面板：支持按日 / 时间段（今天 / 昨天 / 最近 7 天 / 最近 30 天 / 自定义日期范围）、应用名、包名、送达状态（全部 / 仅成功 / 仅失败）组合筛选后再搜索，也可单独按时间段或某一天查看历史。
- 全量历史搜索：搜索覆盖数据库全部记录（此前仅限最近 500 条），采用 SQLite 粗筛 + 应用内送达状态精筛，结果分页加载，标题栏显示结果条数，可一键清除筛选。
- 修复历史记录从数据库加载时时间字段丢失的问题，按时间排序与筛选更准确。

📦 **聚合推送（新功能）**：
- 规则引擎「合并推送」动作正式生效：同一应用的通知在窗口期内合并为一条推送，窗口结束后统一发出，减少高频消息轰炸。
- 合并窗口秒数可在规则编辑中自定义（默认 60 秒，最小 5 秒）。
- 聚合期间前台通知栏实时展示待合并通知列表（含剩余时间），窗口结束自动恢复。
- 成员通知的历史记录在合并推送后自动标记为「已合并推送」；聚合汇总记录显示真实送达状态。
- 与延迟/定时推送完全隔离（独立队列与闹钟），同时配置时延迟优先，互不干扰。

**Full history search & filters + merged push + no more history cap**

🔍 **Push history search & filters (new)**:
- The 500-record storage cap is removed: all push history is fully saved in the database, and the history page lets you scroll through every record instead of only the latest 500.
- New filter panel: filter by day / time range (Today / Yesterday / Last 7 Days / Last 30 Days / custom date range), app name, package name, and delivery status (All / Success only / Failed only), then search — or just browse history by a time range or a single day.
- Full-history search: search now covers the entire database (previously only the latest 500 records), using SQLite pre-filtering plus in-app delivery-status refinement, with paginated results, a result count in the title bar, and one-tap filter clearing.
- Fixed the loss of the time field when records were loaded from the database, making time-based sorting and filtering more accurate.

📦 **Merged push (new)**:
- The rule engine's "Merge Push" action now takes effect: notifications from the same app are merged into a single push within a window and sent together when it ends, reducing message floods.
- The merge window in seconds is configurable in the rule editor (default 60, minimum 5).
- While merging, the foreground notification shows the pending notifications in real time (with countdown), and restores automatically once the window ends.
- Member records are automatically marked as "Delivered as merged push" in history; the merged summary record shows the real delivery status.
- Fully isolated from delayed/scheduled push (separate queue and alarm); when both are configured, delay takes precedence.

### v1.5.65+100 - 2026-09-07

**飞书签名修复 + 渠道名语言适配 + 小米强杀后监听恢复**

🐛 **飞书推送签名修复（重要）**：
- 飞书自定义机器人的签名算法与钉钉不同（`sign = base64(HMAC-SHA256(key=时间戳+"\n"+密钥, data=空))`），此前误用钉钉算法（key=密钥、data=时间戳串），开启「签名校验」的飞书机器人推送必失败（错误码 19021 Sign match fail），现按官方算法修正。
- 全渠道 payload 逐项对照官方 API 复核：企业微信 / 钉钉 / 飞书 / Telegram / Bark / Server酱 / PushPlus / 通用共 8 类、通知 / 短信 / 电话 / 电量 4 类消息的 JSON 结构与必填字段均符合规范。

🌍 **渠道名跟随软件语言**：
- 首页通道状态、通知记录送达标签、测试结果中的渠道名不再固定中文：英文界面显示 WeCom / Feishu / DingTalk / ServerChan 官方名，中文界面保持企业微信 / 飞书 / Server酱。
- 邮件通道与拦截标签同步双语：邮件 / Email、过滤拦截 / Blocked；历史记录渠道品牌色双语识别（英文标签下品牌色不丢失）。

🔧 **小米等 ROM 强杀后监听自动恢复**：
- 进程被强杀（滑掉最近任务）后，系统对通知监听服务的自动重绑可能被 ROM 拦截（小米未授予自启动权限时必现），表现为重开 App 也收不到任何通知。现在启动 5 秒后检测监听连接状态，未连接则通过「组件禁用→启用」强制系统重新绑定，重绑后自动补扫断线期间的通知。

**Feishu signing fix + localized channel names + listener recovery after force-kill on Xiaomi**

🐛 **Feishu signing fix (important)**:
- Feishu custom-bot signing differs from DingTalk (`sign = base64(HMAC-SHA256(key=timestamp+"\n"+secret, data=empty))`). The previous implementation mistakenly used the DingTalk algorithm (key=secret, data=timestamp string), so Feishu bots with signature verification enabled always failed (error 19021 Sign match fail). Now fixed per the official algorithm.
- All channel payloads re-verified against official APIs: 8 channel types (WeCom / DingTalk / Feishu / Telegram / Bark / ServerChan / PushPlus / Generic) × 4 message categories (notification / SMS / call / battery) — JSON structures and required fields all conform to spec.

🌍 **Channel names follow the app language**:
- Channel names in the home-page channel status, delivery labels, and test results are no longer fixed Chinese: the English UI shows official names (WeCom / Feishu / DingTalk / ServerChan) while the Chinese UI keeps 企业微信 / 飞书 / Server酱.
- The email channel and interception labels are bilingual as well: 邮件 / Email, 过滤拦截 / Blocked; channel brand colors in history recognize both languages (brand colors are no longer lost under English labels).

🔧 **Automatic listener recovery after force-kill on Xiaomi and similar ROMs**:
- After the process is force-killed (swiped away from Recents), the system's automatic rebind of the notification listener may be blocked by the ROM (always reproducible on Xiaomi without auto-start permission), leaving the app deaf even after reopening. The app now checks the listener connection 5 seconds after launch and, if disconnected, forces a system rebind by toggling the service component disabled→enabled, followed by an automatic catch-up scan of notifications posted during the gap.

### v1.5.64+99 - 2026-09-06

**配置备份与恢复（新功能）**

💾 **配置备份与恢复（P1）**：
- 新增「备份与恢复」页（更多 → 关于更新区块）：一键将全部配置加密导出为 `.nbackup` 文件，换机 / 重装后选文件 + 输入口令即可完整还原。
- **加密方案**：AES-256-GCM 认证加密（密文篡改即解密失败），口令经 PBKDF2-HMAC-SHA256 派生（210000 次迭代 + 每次备份随机 16 字节盐），口令不落盘、不参与云同步。
- **文件头自描述**：`.nbackup` 头部携带格式版本与 KDF 参数（算法 / 迭代次数 / 盐），解密按文件头参数派生，向前兼容参数演进；结构校验在输入口令前完成，非法文件直接拒绝。
- **备份内容**：Webhook 通道（含签名密钥）、邮件通道（含授权码）、通知规则、短信监听设置、应用过滤与黑白名单关键词；不含通知历史与送达日志。
- **冲突策略**：恢复时检测现有配置——无配置直接恢复；有配置时三选：覆盖全部 / 仅导入空缺项（跳过已有类别）/ 取消，避免误覆盖。
- **字段级校验**：非 https 的 Webhook 地址自动跳过并计数提示，与原生保存链路的安全要求一致。
- 恢复走既有保存链路（加密库 + 原生同步），后台推送即时生效。
- 新增 14 个单元测试：加密往返 / 文件头参数 / 随机盐与 nonce / 错误口令与篡改检测 / 容器结构校验 / https 过滤。
- 依赖修复：`file_picker` 升级至 8.3.7 并在 Gradle 层对其强制 compileSdk 37（修复与 `flutter_plugin_android_lifecycle` 的 AAR 元数据校验失败）。

**Config Backup & Restore (New Feature)**

💾 **Config Backup & Restore (P1)**:
- New "Backup & Restore" page (More → About section): one-tap encrypted export of all configs as a `.nbackup` file — pick the file and enter your passphrase to fully restore after switching or reinstalling the device.
- **Encryption**: AES-256-GCM authenticated encryption (any ciphertext tampering fails decryption); passphrase derived via PBKDF2-HMAC-SHA256 (210,000 iterations + a random 16-byte salt per backup). The passphrase is never stored or synced to the cloud.
- **Self-describing header**: the `.nbackup` header carries the format version and KDF parameters (algorithm / iterations / salt); decryption derives the key from header parameters, forward-compatible with parameter evolution. Structural validation runs before the passphrase is entered — invalid files are rejected immediately.
- **Backup contents**: Webhook channels (incl. signing secrets), email channels (incl. app passwords), notification rules, SMS monitoring settings, app filter and blacklist/whitelist keywords. Excludes notification history and delivery logs.
- **Conflict strategy**: existing configs are detected on restore — none: restore directly; some: choose one of three — Overwrite all / Fill gaps only (skip non-empty categories) / Cancel, preventing accidental overwrite.
- **Field-level validation**: non-https Webhook URLs are skipped automatically with a count hint, consistent with the native save-path security requirement.
- Restore goes through the existing save pipeline (encrypted database + native sync), so background push takes effect immediately.
- 14 new unit tests: encrypt/decrypt round-trip / header parameters / random salt & nonce / wrong passphrase & tamper detection / container validation (5 branches) / https filtering.
- Dependency fix: `file_picker` upgraded to 8.3.7 with a Gradle-level compileSdk 37 override for the plugin (fixes the AAR metadata check failure against `flutter_plugin_android_lifecycle`).

### v1.5.63+98 - 2026-09-06

**短信监听设置中心 + 桌面小组件全新升级 + 卡槽过滤双链路**

📱 **短信监听设置中心（新页面）**：
- 新增短信监听设置页：监听短信总开关 / 「监听验证码」开关 / 监听卡选择（全部卡 / 仅卡1 / 仅卡2）三大项集中管理。
- **单卡设备灰化（需求 1）**：原生新增 `getSimCardCount`（优先 `SubscriptionManager.activeSubscriptionInfoList` 活跃卡数，无权限/异常时回退 `TelephonyManager.activeModemCount`/`phoneCount` 硬件卡槽数）；单卡设备监听卡选项整体置灰，副标题提示「当前设备仅有一张SIM卡，无需选择」，总开关与验证码开关不受影响。

🧭 **卡槽过滤双链路生效**：
- 新增 `SmsMonitorGate` 纯函数闸门（监听开关 / 验证码开关 / 卡槽过滤统一判定，11 例单测），短信广播、短信库兜底、来电三条链路共用。
- 卡槽过滤同时作用于短信与电话：识别出且不属于所选卡的来电直接忽略，并修复跨卡状态串扰（含状态机防护）。
- 推送正文底部新增 SIM 信息行（中英双语：「卡1，运营商：中国移动」/ "SIM 1, Carrier: China Mobile"）。

📱 **桌面小组件全新升级（需求 2）**：
- **规范化**：两份 appwidget-provider 新增 `description` 与 `previewImage`/`previewLayout`（Android 12+ 系统添加弹窗展示预览与说明）；receiver label 本地化（新增 values/strings.xml 中文 + values-en 英文）；清理 `PushToggleWidgetProvider` 旧 pin 死代码。
- **添加体验**：`requestPinWidget` 先 `isRequestPinAppWidgetSupported` 预检，不支持的桌面直接返回明确失败；新增 `isPinWidgetSupported` 查询方法；添加失败自动弹出当前品牌分步引导对话框；引导页按设备厂商识别（小米/华为/OPPO/vivo/三星/类原生）将当前品牌置顶并加「当前设备」徽标。
- **视觉美化**：2×2 与 4×2 布局重设计（标题 / 状态圆环 / 提示胶囊 / 当日计数分层，间距字号触控区优化，拉伸区间自适应）；drawable 全面重做（细腻渐变圆角卡片 + 描边、推送中绿/已暂停红状态圆环、提示胶囊），明暗桌面均可读；预览图与新设计一致；运行时文案仍走 I18n 覆盖。

🧹 **其他**：
- 应用筛选页重构：已选/未选分组展示、无权限引导优化；通知页与推送历史展示小改。
- 官网/后台版本号动态化：index.html 版本号、下载链接与文件大小改为运行时从版本接口获取（GitHub Releases 兜底），admin 后台页脚动态显示线上最新版本；**常规发版不再需要更新这两个页面**。
- 测试扩充：Dart 新增 SMS 设置页/服务/widget 引导页/应用筛选页等 22 例（总数 189），原生新增 `SmsMonitorGateTest` 11 例（总数 90）。

### v1.5.62+97 - 2026-09-06

**合规与可靠性：崩溃上报开关 + 双端规则引擎对齐 + 送达日志落地**

🔐 **崩溃上报合规改造（重点）**：
- **根因**：README 主打「数据零上传」，但 Bugly 此前无条件初始化，崩溃堆栈/设备信息会出网，存在 PIPL 合规风险。
- **修复**：Bugly 默认关闭——冷启动不再初始化 SDK、不出网；仅当用户在「更多 → 崩溃上报」开关开启（视为同意）后才初始化并开始上报（`MainActivity.maybeInitCrashReport` + `initCrashReport` MethodChannel，幂等）。
- 关闭开关后因 SDK 无反初始化能力，下次冷启动完全生效（开关处有提示）。
- 隐私披露全面同步：README 中/英、应用内隐私政策页（中/英）、首次启动弹窗、SECURITY 中/英、官网均改为「默认关闭、同意后开启、可随时关闭」表述。

🧭 **双端规则引擎归一化对齐**：
- **根因**：Kotlin `FilterEngine.normalize` 做全角转半角 + 空白折叠 + 条件值 trim，Dart 端只做 `toLowerCase`，同一规则在 Flutter 预览与原生实际执行时匹配结果可能不同。
- **修复**：Dart 端新增 `normalizeForMatch` 逐行复刻原生归一化，并补齐「非包名空值条件不匹配」语义。
- 新增 **34 条双端黄金用例**（`test/fixtures/rule_engine_golden.json` 与 android 测试资源同步副本）：全角/半角、空白折叠、大小写、正反向包含、优先级、正则（含非法与超长拒绝）、空值条件、AND/OR 分组，Dart 与 Kotlin 消费同一批用例防止再漂移。

📋 **webhook_delivery_log 送达日志落地**：
- 该表（DB v5）此前建表后全链路无写入。现送达链路（WebhookSender → DeliveryNotifier → DeliveryResultStore/广播）补传 `channelUrl`，Flutter `updateDelivery` 在终态（success/failed，paused 不落）写入送达日志（含 HTTP 状态码），写入时自动清理 30 天前旧记录防膨胀。

📦 **导出统一走数据库**：
- 删除无人调用的 `exportRecords` 双轨实现，`buildExportJson` 成为唯一导出并改为直读数据库全量（此前只导出内存 500 条），字段统一为 `recordCount`。

🔐 **权限收敛**：
- 移除 `MANAGE_EXTERNAL_STORAGE`（全代码零使用：导出走 DownloadManager 与 app-specific 目录）；README 补充分发策略说明（含短信/安装包权限不面向 Google Play，走自有渠道）。

🧪 **测试扩充**：
- 新增原生单测 65 例：`WebhookPayloadBuilderTest`(15) / `WebhookResponseParserTest`(23) / `TemplateEngineTest`(15) / `FilterEngineTest`(11) / `RuleEngineTest`(黄金用例)，原生测试总数 73。

🛠 **服务端与文档**：
- `express` 升级 `^4.21.2`（修复 low 漏洞，lock 4.22.2 + body-parser 1.20.6）。
- server README 新增「部署边界」：限流/会话为内存 + JSON 落盘仅支持单实例，多副本需外置 Redis/SQLite。
- README 修正过期文案：IP 封锁「3 次/240 小时」→「5 次/1 小时」、otplib `^12` → `^13`；版本一致性脚本扩展覆盖文档（otplib 版本与封禁参数）。
- 证书固定澄清「默认未启用」并新增轮换 runbook（`docs/cert_rotation_runbook.md`）；MainActivity 拆分/UI ViewModel 化/l10n ARB 迁移的重构方案见 `docs/refactor-plan.md`。

### v1.5.61+96 - 2026-08-29

**修复：短信读取可靠性 + 验证码提取 + 构建工具链**

🐛 **短信读取修复（重点）**
- **根因**：短信此前只有 `SMS_RECEIVED` 广播单一链路（通知监听对短信应用一律跳过），广播一旦因国产 ROM 限制 / Doze / 进程回收而丢失，短信即永久丢失且无法恢复；且 `SmsReceiver` 未用 `goAsync()`，异步推送常在进程被回收时中断。
- **新增兜底链路**：`SmsObserver`（短信库 ContentObserver）监听 `content://sms/inbox`，按 `_id` 增量捕获广播漏掉的短信；注册时以当前最新短信为基线，不会补推历史短信；未授予 READ_SMS 时自动跳过注册。
- **统一入口**：新增 `SmsDispatcher`，广播与兜底两链路共用同一套过滤、去重、历史缓存与推送逻辑。
- **跨链路去重**：按「发送方 + 正文 + 秒级时间戳」指纹在 120 秒窗口内去重，两条链路不会重复推送。
- **僵尸窗口修复**：`NetworkClient` 在服务销毁后置为 inactive，而短信广播仍会唤醒进程，此前这类短信会被静默丢弃，现由 `SmsDispatcher` 兜底激活。

📩 **验证码专项**
- 修复数据短信 / WAP Push 因 `messageBody` 为空被整条丢弃的问题，现回退读取用户数据区。
- 长短信分段解析改为逐段独立 try-catch，单段解析异常不再导致整条丢失。
- 新增验证码提取 `extractCode`：仅在正文出现验证码语义词时提取，且码位右侧不得紧跟数字，避免把手机号 / 订单号误判为验证码；结果通过 payload 的 `verificationCode` / `code` 字段下发。
- 新增 8 个单元测试覆盖提取与防误提取边界（含英文短信用例）。

🔧 **构建工具链**
- 修复 `gradlew` 无法启动（`ClassNotFoundException: GradleWrapperMain`）：wrapper jar 实为 2015 年 Gradle 2.x 产物（class 版本 Java 5），与声明的 Gradle 9.5.0 不匹配，已重新生成配套 wrapper 并保留国内镜像源。

### v1.5.60+95 - 2026-08-23

**修复：推送历史偶发一直显示「推送中」 + 精确闹钟权限兼容**

🐛 **推送历史状态修复**：
- **根因**：送达结果链路依赖 MainActivity 存活（动态广播接收器 + 其持有的 MethodChannel）。滑掉最近任务或系统回收 Activity 后，推送完成的结果广播无人接收，记录永远停在「发送中」。
- **修复**：送达结果持久化队列（DeliveryResultStore）+ 启动 / 回前台时补偿拉取（`drainDeliveryResults`）。广播实时链路不变，Activity 销毁期间的结果由队列兜底，下次加载记录或回前台时一次性补齐，覆盖 Webhook / 邮件 / 短信 / 电话全部通道。

🐛 **精确闹钟权限 Intent 兼容**：
- Android 12~13 的 `ACTION_REQUEST_SCHEDULE_EXACT_ALARM` 去除可选的 data 参数（官方标记 Optional）。部分 ROM（尤其国产）Settings 组件不匹配带 data 的 Intent，导致授权弹窗无法打开；不带 data 时系统默认取调用者包名，并保留 Activity 未找到时的应用详情页兜底。

### v1.5.60 - 2026-08-23

**精确闹钟开关 + 国产 ROM 保活引导 + 邮件通道增强 + 安全与健壮性加固**

⏰ **精确闹钟开关（B1）**：
- 新增可选「精确闹钟」开关（默认关闭，保持权限最小化）：开启后延迟/定时推送在深度 Doze 下也可准点触发（`setExactAndAllowWhileIdle`）。
- Android 12~13 开启时自动弹系统授权对话框；Android 14+ 跳应用详情页引导手动授权。
- 未授权时自动降级为非精确闹钟，功能不中断，不阻塞使用。

🔋 **国产 ROM 保活引导卡片（B2）**：
- 权限设置页新增保活引导：省电无限制 / 自启动 / 任务锁定 / 通知使用权四步卡片，识别 MIUI/HyperOS/ColorOS/EMUI 等 ROM 一键跳转对应厂商省电设置页。

📱 **锁屏验证码兜底（B3）**：
- 锁屏脱敏正文（验证码显示 `******`）检测后，转发文案替换为「验证码内容被锁屏隐藏，请解锁后查看」，不再向各通道发送无意义星号。

📧 **邮件通道增强（D1）**：
- 临时性失败（网络超时 / 连接失败 / SSL 握手 / 421 临时故障）自动重试 1 次（2 秒退避）。
- 错误分类细化：认证失败 / 地址错误 / 被拒收等配置类问题直接提示，失败原因经历史记录内联显示（与测试邮件共用同一分类逻辑）。

⬇️ **检查更新 403 优化（A1）**：
- 更新检查被 CDN（Cloudflare Bot Fight Mode）拦截时自动指数退避重试 1 次；仍失败则提示「被 CDN 拦截，请稍后重试」而非笼统网络错误。

🔒 **安全与健壮性加固**：
- **正则规则保护（E1）**：规则/关键词正则超过 200 字符直接拒绝，防止灾难性回溯阻塞监听服务。
- **竞态与异常加固（E2）**：推送计数跨日重置同步化、通道配置 volatile 发布（copy-on-write）、协程未捕获异常兜底记录日志。
- **证书固定框架就绪（C1）**：证书 pin 支持构建时注入（`--dart-define=CERT_PINS`），默认关闭，开启后 Release 版强制校验服务器证书。
- **原生配置加密桥接（C2）**：Webhook secret 等原生端明文存储迁移至 EncryptedSharedPreferences，与 Flutter 端加密存储同源。

🧪 **测试补充（E3）**：
- 新增跨零点时间区间命中/未命中、超长正则拒绝、边界长度正则可用等 4 个用例，测试总数 123。

### v1.5.59 - 2026-08-23

**漏通知修复 + 推送历史状态增强（暂停/失败原因/现在推送）**

🐛 **漏通知修复**：
- **通知去重误判**：去重键加入通知 tag 维度，同一应用用相同通知 ID + 不同 tag 发多条常驻通知不再被误判重复而漏读。
- **记录 ID 冲突覆盖**：历史记录 ID 改为全局唯一（包名+tag+通知ID），微信/QQ 等不同应用相同通知 ID 不再互相覆盖导致漏记录。
- **会话类通知正文为空被跳过**：微信/QQ/Telegram 等正文仅存在 MessagingStyle 中的通知，补充内容兜底链（大文本→正文→MessagingStyle 最后一条消息→多行文本→ticker→副标题），不再因正文为空整条漏读。
- **监听断开无感知**：通知使用权被系统回收后静默漏读，新增监听状态检测，断开时前台通知显示「监听已断开 · 可能漏读通知」警告。

📋 **推送历史状态增强**：
- 新增「用户暂停推送」状态：推送暂停期间收到的消息在历史记录中显示该状态（橙色），与"推送失败"明确区分。
- 新增「现在推送」按钮：暂停期间未实际发送的消息，可在历史记录中一键手动补推（webhook + 邮件，绕过暂停开关）。
- 推送失败原因内联显示：因网络或其他问题导致推送失败时，失败原因（如 HTTP 502 / 限流提示等）直接显示在记录中，无需长按查看。

### v1.5.58 - 2026-08-15

**隐私政策全面重写 + 更新下载三源回退 + 界面国际化补全**

🔒 **隐私政策全面重写**：
- 应用内隐私政策页扩展为 11 个章节：新增「信息共享与披露」「儿童隐私」「您的权利」「联系我们」等，全部按当前功能（规则引擎 / 定时延迟推送 / 电池监控 / 应用过滤 / 桌面小部件）实际数据收集情况撰写。
- 明确数据收集边界：仅通知文本 / 应用包名 / 电池电量 / 自建规则，均仅在本地处理；明确 Bugly 崩溃统计最小采集（不收集设备隐私数据）。
- 首次启动隐私弹窗文案同步更新，双语（中/英）一致；更新日期标注 2026年8月15日。

⬇️ **更新下载三源回退 + 失败诊断**：
- 下载源调整为三个（按设备 ABI 自动匹配）：CDN（cdn2.fnthink.top）→ GitHub 国内加速镜像（xget.fnthink.top）→ GitHub 官方直链（github.com），任一失败自动切换下一源，消除「概率 404」。
- 下载失败时输出完整诊断日志：HTTP 状态码、content-type、content-length、重定向 location、server 头、系统下载器失败码（reason 可读文案）。

🌐 **界面国际化补全 + iOS 主题风格统一**：
- 规则管理页 / 规则编辑页 / 关键词过滤页全部文案接入中英文国际化（此前仅部分页面双语）。
- 规则编辑页下拉菜单（优先级 / 条件类型 / 逻辑运算符 / 动作类型）改为 iOS 主题风格选择器，深色模式适配；排查并统一全库其他下拉菜单（历史页清除记录菜单同步改造）。

🐛 **修复**：
- **多条延迟推送只有第一条按时触发**：延迟推送队列闹钟一次性，到点推完首条后未重排下一条，导致后续延迟通知要等新通知入队或服务重启才补推；修复为到点批量取到期项后自动重排剩余闹钟。
- **Doze 说明**：定时/延迟推送在深度 Doze 下可能有分钟级延迟（维护窗口约 9~15 分钟一次投递）。

### v1.5.57 - 2026-08-14

**桌面小部件全新升级 + 更新下载改系统下载器**

🪟 **桌面小部件全新升级**：
- **2×2 样式重做**：左上角标题「通知推送助手」+ 中央圆形状态（推送=绿色 / 暂停=红色）+ 底部「点击暂停/恢复推送」提示，文案跟随中英文语言切换。
- **新增 4×2 横条规格**：左上角标题 + 左半圆形状态 + 右半「当日已推送通知数量」（原生侧独立持久化，跨天自动重置），桌面小部件列表可分别添加两种规格。
- **自适应尺寸**：2×2 拉伸至 4×2 时布局自动切换（读取当前宽度，≥220dp 用宽布局），无需重新添加。
- **一键添加**：推送开关页新增「一键添加 2×2 / 4×2 小部件」按钮，Android 8.0+ 通过 requestPinAppWidget 弹出系统确认框直接添加到桌面，免去手动长按拖拽。
- **品牌适配**：两种规格独立注册 + 自适应尺寸 + requestPinAppWidget，覆盖小米/华为/OPPO/vivo/三星等主流 Launcher。

⬇️ **更新下载改系统下载器（DownloadManager）**：
- **免存储权限**：移除下载前的「所有文件访问」权限申请，下载到公共 `Download/FnthinkNotice` 目录，隐私声明更干净、上架风险更低。
- **后台不中断**：下载由系统进程执行，应用被杀/切后台不中断；通知栏自动显示下载进度（各品牌系统下载器接管，符合用户习惯）。
- 应用内保留进度条（轮询系统进度同步显示）；安装优先 open_filex 打开，本地路径不可用时回退系统安装器（content uri）。

🐛 **修复**：
- **规则优先级/条件下拉菜单深色模式适配**：补充 dropdownColor / iconEnabledColor，深色主题下不再白底刺眼。
- **更新检查 HTTP 403**：根因是 Dart 默认 User-Agent 被 Cloudflare Bot Fight 拦截，改为浏览器风格 UA 后恢复正常。

### v1.5.56 - 2026-08-14

**优先级分级 + 定时/延迟推送 + 渠道类型英文翻译**

🔔 **通知优先级分级**：原生通知链路接入规则引擎（RuleEngine），提取系统通知优先级（高/中/低），支持按「通知优先级」条件匹配规则；规则动作真正生效——静默忽略 / 仅记录 / 延迟推送 / 立即推送按命中规则执行（此前仅 UI 配置、原生未执行）。
⏰ **定时/延迟推送**：新增 DelayedPushManager（SharedPreferences 持久化队列 + AlarmManager 定时唤醒，进程被杀/重启自动恢复）；规则编辑器为「延迟推送」动作新增参数配置（延迟秒数 / 定时时间 HH:mm），到点后自动补推 webhook 与邮件，历史记录先显示待送达、到点后更新为已送达。
🏷️ **渠道类型英文翻译**：Webhook 设置页渠道类型名称、选择弹窗、签名提示、消息格式标签全部接入国际化，英文界面不再显示中文。
🖥️ **最近任务页语言同步修复**：语言切换（含跟随系统弹窗）完整同步原生桌面应用名，App 中文界面时最近任务页正确显示「通知推送助手」而非旧英文名。

### v1.5.55 - 2026-08-14

**Server酱 / PushPlus 渠道 + 桌面小部件一键启停推送**

🔗 **Server酱 / PushPlus 渠道**：新增两个国内推送平台。Server酱走 POST form 提交（`application/x-www-form-urlencoded`，title/desp 放请求体，避免含验证码/短信正文的内容进入 URL 被代理或日志留存），PushPlus 从 URL query 提取 token 注入 body 后 POST JSON；host 精确匹配自动识别（sctapi.ftqq.com / www.pushplus.plus、pushplus.plus），与 Telegram/Bark 相同使用平台自身鉴权（SendKey/Token），无需签名密钥；响应按平台返回码判定成功（Server酱 code==0、PushPlus code==200）。
🪟 **桌面小部件「推送开关」**：桌面一键开启/暂停推送服务（2×2 格），复用 PushToggleManager 启停机制，点击整卡切换状态并同步刷新前台通知按钮；更多页新增引导入口，按国内外各品牌（小米/华为/OPPO/vivo/三星/原生等）提供手动添加路径说明。

### v1.5.54 - 2026-08-14

**服务端模块化拆分 + HTTP 契约测试 + Webhook 保存链路测试**

🏗️ **服务端模块化拆分**：`server.js` 由 1249 行单文件按职责拆分为 `lib/` 分层（`store.js` 存储持久化 / `otp.js` TOTP 封装 / `middleware.js` 中间件 / `routes/auth.js`+`routes/version.js` 路由 / `app.js` 组装），入口文件仅保留启动与优雅关闭；`app` 独立导出，测试可直接 require 发起真实 HTTP 请求。
🧪 **服务端 HTTP 契约测试**：`auth.test.js` 由纯逻辑验证重写为真实 HTTP 请求测试（supertest 直连 app，25 个用例），覆盖安全头（CSP/nosniff/无 X-Powered-By）、会话（注销吊销/过期）、版本配置保存链路（POST 落盘 → GET 读回）、TOTP 全流程（setup/enable/OTP 与恢复码登录/恢复码一次性消费）、IP 封锁（第 5 次失败 403 + 公开接口豁免）。
🔗 **Webhook 保存链路测试**：Flutter 端新增 `WebhookChannelStore` 抽象层 + `WebhookService` 构造注入（默认仍走 SQLCipher 加密库），测试覆盖「UI 通道 → DB 行 → 原生同步」完整链路：`setWebhookChannels` 全量下发（含 url/secret/类型/启用状态）、`setWebhookUrls` 仅下发启用通道 URL、DB 行标准化与历史 `"null"` 脏数据过滤。
⚙️ **Jest ESM 兼容**：otplib 依赖链 `@scure/base` / `@noble/hashes` 为纯 ESM 包（Node ≥22 可运行、Jest 默认无法解析），新增 `babel.config.js` + `transformIgnorePatterns` 白名单，服务端测试可正常运行。

### v1.5.53 - 2026-08-12

**短信/电话重复推送修复 + Telegram/Bark 渠道 + 更多页改版 + admin 登录修复**

📱 **短信/电话重复推送修复**：同一短信/电话此前会被通知栏监听和广播接收器同时捕获，产生两条记录（一条有 SIM 卡信息、一条无）。现排除通知栏对短信/电话应用的监听，由 SmsReceiver / PhoneCallReceiver 独占处理，确保每条短信/电话只产生一条带 SIM 卡信息的记录。
📶 **双卡 SIM 识别增强**：SimInfoHelper 新增默认语音 SIM 回退策略（双卡场景下 PHONE_STATE 广播不携带 subscriptionId 时，用系统默认语音通话 SIM 推断）。
🔗 **Telegram / Bark 渠道**：新增 Telegram Bot 和 Bark 推送渠道，host 精确匹配自动识别（api.telegram.org / api.day.app），无需手动选择类型。
⚙️ **Webhook 渠道类型插件化**：Kotlin/Dart 两端 host 匹配规则统一为配置化列表（PLATFORM_RULES），新增平台只需追加一行；修复两端匹配规则不一致（Dart 端从 endsWith/contains 改为精确匹配）。
📋 **更多页改版**：推送通道（Webhook / 邮件）与过滤规则（应用筛选 / 关键词 / 规则引擎）拆分为两个独立分组，信息层次更清晰。
🔐 **admin.html 登录修复**：2FA 验证码输入后无响应问题修复；新增加载状态反馈、回车键支持、非 JSON 响应容错。
🛡️ **服务端持久化加固**：writeJsonFile 改为原子写入（tmp + rename），防止崩溃产生截断文件；登录成功后立即持久化会话。
📢 **飞书 markdown 降级提示**：飞书 + markdown 格式组合时显示橙色提示条，告知用户将降级为纯文本发送。

### v1.5.52 - 2026-08-12

**推送记录统计统一 + 逐条送达状态 + 短信/电话送达回传**

📊 **推送记录统计统一**：首页/更多页/状态栏推送记录共用数据库同一数据源，状态栏当日计数与今日记录实时同步，三处统计不再各算各的。
✅ **逐条送达状态**：首页推送记录逐条标注各通道送达状态（推送成功 / 推送失败 / 发送中），按企业微信/飞书/钉钉官方返回码判定，失败原因一目了然。
📶 **短信/电话送达回传**：短信/电话通道送达结果实时回传，送达状态即时生效。
🐛 **修复**：企业微信通道类型标签不一致导致送达状态无法更新。

### v1.5.51 - 2026-08-11

**3 项修复：小米超级岛常驻 + Webhook 无法推送 + URL 类型识别**

🏝️ **修复小米超级岛常驻**：移除前台通知的 `EXTRA_REQUEST_PROMOTED_ONGOING`（Android 16 Live Update 实时更新提升）请求——该标志会让常驻通知在 HyperOS 上以「超级岛」常驻胶囊显示；前台通知改归类 `CATEGORY_SERVICE`，各品牌（小米/华为/荣耀/vivo/OPPO）灵动岛对服务类常驻通知默认不上岛，仅保留通知栏展示。
📮 **修复 Webhook 始终无法推送**：`setWebhookChannels` 用 `JSONObject(Map)` 序列化时，未配置的 `secret`/`message_template` 的 null 值被转成字符串 `"null"`，原生端误以为配置了签名密钥 → 错误签名被平台拒绝，导致"历史显示已推送但实际未送达"。修复：原生序列化跳过 null 字段 + ConfigManager 读取端将 `"null"` 视为未配置 + Dart 持久化层过滤历史脏数据。
🔍 **Webhook 类型识别增强**：`WebhookChannel.detectTypeFromUrl` 改用 Dart `Uri.parse` 提取 host（更健壮，支持端口/凭据边界）+ 支持域名变体识别（`weixin.qq.com` / `dingtalk.com` / `larksuite.com` 等），修复 6 个 CI 单元测试断言失败。

### v1.5.50 - 2026-08-11

**P2：推送模板引擎 + 一键暂停推送 + 平台类型精确识别**

📝 **推送模板引擎**：新增 `TemplateEngine.kt`，支持 text/markdown/json/xml 四种消息格式，变量占位符（`%appName%` `%title%` `%content%` 等 14 个）自动替换；企微/钉钉/飞书按平台原生 msgtype 包裹 payload，通用 webhook 直接发送渲染后 body 并自动设置 Content-Type；JSON/XML 模板自动转义。每个通道独立配置格式与模板，数据库升级至 v6 新增 `message_format` / `message_template` 字段。
⏸️ **前台通知一键暂停/恢复推送**：新增 `PushToggleManager`（三级状态机 RUNNING/PAUSED/STOPPED + SharedPreferences 持久化）与 `PushToggleActionReceiver`；前台通知显示「暂停推送」/「恢复推送」Action 按钮，点击切换状态后通过 `ACTION_REFRESH_FOREGROUND` 刷新通知文案与按钮；`NetworkClient` 发送前检查 `isPushActive()`，暂停期间监听继续、通知仍记录历史但跳过 webhook 发送。
🎯 **Webhook 平台类型 host 精确匹配**：`WebhookPayloadBuilder.detectType` 由 `url.contains()` 子串匹配改为 `extractHost()` 提取小写 host 后精确相等比较（`qyapi.weixin.qq.com` / `oapi.dingtalk.com` / `open.feishu.cn` / `open.larksuite.com`），消除 `weixin.qq.com` 等误判；Dart 端 `WebhookChannel.detectTypeFromUrl` 同步对齐，与 DB `channel_type` 优先级配合。
🌐 **前台通知国际化**：前台服务通知文案（标题/监听状态/暂停状态/Action 按钮）接入 `I18n` 中英双语，英文模式下状态栏通知不再显示中文。

### v1.5.49 - 2026-07-29

**双卡识别 + 多项修复 + 签名全方案 + 动态桌面名**

📱 **短信/电话双卡识别**：新增 `SimInfoHelper.kt`，通过 `SubscriptionManager` 获取 SIM 卡槽位（卡1/卡2）和运营商名称；短信/电话推送时自动标注；Webhook 推送同步附加 SIM 信息。
🔐 **APK 签名全方案**：`build.gradle.kts` 启用 V1 (JAR) + V2 (APK全文件) + V3 (密钥轮换) 三种签名方案，证书指纹不变。
🖥️ **动态桌面名**：语言切换时自动更新桌面/最近任务应用名（中文=通知推送助手 / English=NoticeTransmit，工作量：34 个 activity-alias + MethodChannel + 集合函数）。
🐛 **6 项修复**：SMTP 通道测试通过但首页仍显示异常（测试结果持久化到 SharedPreferences）；语言选择弹窗中英图标关联性强化（中文=毛笔、英文=拼写→中文=translate/文、英文=g_translate/En）；推送历史 24:00 归档（WorkManager 0.6.0 + 前台兜底 + 幂等标志）；锁屏消息不记历史（`notificationReceiver` 移到 `onCreate()` 注册）；`version.json` 下载 URL 缺版本号目录；`English` key 导致 i18n.js 翻译污染。
🎨 **体验优化**：语言弹窗图标风格与其他一致（实色背景+白色图标）、选中项加粗+蓝色 check；弹窗统一圆角。
🏗️ **架构改进**：`server.js` 限流/会话内存状态文件持久化（rate_limit.json→sessions.json + 优雅关闭 SIGTERM）；CI 版本一致性检查脚本 `check_version_consistency.sh`；README 修复 `base.md` 断链；清理热更新原生代码残留（4文件）+ hotfix_example/ 目录删除。

### v1.5.48 - 2026-07-27

**多语言国际化 + 单架构纯净包 + Flutter 规范落定**

🌐 **多语言国际化**：全应用 120+ 处硬编码中文字符串全部迁移至 `AppLocalizations` l10n 体系（中/英双语）；底部 Tab、首页推送通道、更多页栏目、应用图标修改页、应用筛选页、推送统计页、隐私政策页全部完成；平台品牌名统一使用英文（WeCom / DingTalk / Feishu）；新增 `locale_service.dart` 语言持久化与 `LocaleProvider` 状态管理。
📦 **单架构 APK 纯净**：修复 `build.gradle.kts` ndk abiFilters 检测逻辑，单架构包只含一种 `.so`（arm64 → 25.2 MB / arm32 → 21.3 MB / x86_64 → 27.1 MB），不再混入其他架构的第三方库，体积更小、分发更精准。
📐 **Flutter 规范落定**：全项目 `dart format` 通过，`flutter analyze` zero errors（仅 info 级提示）；标准发版流程新增步骤 2.1（format 验证）+ 步骤 6.1–6.4（构建阶段必须设置 `FLUTTER_TARGET_PLATFORM` 环境变量）。

### v1.5.47 - 2026-07-27

**SMTP 修复 + 数据迁移 + 推送历史增强**

🔧 **SMTP 修复**：测试邮件失败原因细化至 12 种异常码；修复退出设置页后密码丢失问题；保存按钮改为"测试并保存"自动验证；Release APK javax.mail 被 R8 混淆破坏修复（新增 ProGuard keep 规则）。
🔄 **数据迁移**：WebhookService / EmailService 新增 `_migrateFromLegacyStorage()`，升级后自动将旧存储中的配置迁移至加密 SQLCipher。
🏷 **Webhook 通道名**：支持自定义通道名；修复历史数据 url→type 自动识别（企微/钉钉/飞书）；首页显示通道类型·通道名。
📊 **推送历史增强**：多级清除选项（今日/最近N条/全部）+ 每日 24:00 自动归档 `history-YYYY-MM-DD.json`。
💾 **后台通知防丢失**：原生端缓存未送达记录，Flutter 恢复时批量导入。
🐛 **修复**：下载闪退（异步 IO）；管理后台热更新 JS 崩溃 + 二步验证登录循环；首页 SMTP 未测试时显示红点异常。

### v1.5.46 - 2026-07-27

**SMTP 邮件推送 + 渠道追踪 + 持久化加固**

📧 **新增—SMTP 邮件通道**：完整 SMTP 邮件转发功能（SSL/STARTTLS），支持主题/正文模板变量（%appName% %title% %content% 等 11 个），6 组预制主题模板 + 5 组预制正文模板，编辑页右上角测试发送按钮（含详细失败原因反馈）。
🏷 **新增—推送渠道追踪**：推送历史每行显示渠道标签（webhook:企业微信/飞书/钉钉 + 邮件 + 颜色区分），未配置通道时提示"未配置推送通道"；首页新增"当前推送通道"状态卡片，服务运行时实时展示。
🔐 **加固—配置持久化**：Email / Webhook 通道配置从 flutter_secure_storage + SharedPreferences 迁移至 AES-256 加密 SQLCipher 数据库（新增 email_channels / webhook_channels 表），修复密码在 MIUI 设备重启后丢失问题。
🗄 **加固—通知记录渠道**：NotificationRecord 新增 channels 字段，每条通知自动记录启用的推送渠道。
🐛 **修复—前台服务超时**：`BootReceiver.startForegroundService()` → `startService()`，API 34+ 使用 SPECIAL_USE 类型，消除 `ForegroundServiceDidNotStopInTimeException` 崩溃。
🐛 **修复—体验优化**：首次启动不弹出通知权限引导 + 服务默认停止；启动服务时先检测权限；隐私弹窗二次确认 + 样式统一；应用列表权限误检修复（canQueryAllPackages）。
🐛 **修复—代码质量**：MethodChannel 统一为 AppChannels.notification（4 文件）；移除 ~67 行死代码（stopOldService / isNotificationServiceRunning / sendToWebhooks / saveNotificationRecord 等）；回退版本号集中为常量；print → debugPrint；SSL 证书固定文档化。
📝 **文档**：全项目 markdown 中英双版同步 + base.md v1.20 + SSL 证书固定操作指南。

### v1.5.45 - 2026-07-24

**代码清理 + R8混淆启用 + 文档全面同步**

🔥 **代码清理**：彻底移除热更新废弃代码（`update_manager.dart` / `update_service.dart` / `main_page.dart` / `server.js` 中约 250 行死代码），移除 `archive` 依赖包。
🔐 **安全加固**：启用 R8 代码混淆与资源压缩（`isMinifyEnabled = true`、`isShrinkResources = true`），APK 体积 28.1MB → 24.4MB（-13.2%），补充 Bugly / SQLCipher keep 规则。
🔧 **优化**：SmsReceiver 优先级 `Integer.MAX_VALUE` → `999`，降低对系统短信应用影响；添加 `dart_code_metrics` 静态分析。
🧪 **测试**：新增 27 个单元测试用例（FilterService 15 例 / DatabaseHelper 3 例 / server.js 认证 11 例 / Widget 2 例），测试总数 73 → 95。
📝 **文档**：markdown 文档全面中英双版同步（README / SECURITY / CONTRIBUTING / CODE_OF_CONDUCT / ISSUE_TEMPLATE）；README 许可证声明统一为 MIT；移除所有 `(build XX)` 版本号后缀显示；base.md 校准至 v1.19。

### v1.5.44 - 2026-07-19

**发布签名安全加固 + 电量规则交互优化 + 贡献规范完善**

🔐 **安全加固**：APK 发布签名改为「源码零密钥」——移除 `build.gradle.kts` 中硬编码的 keystore 密码与绝对路径，改由本地 `android/key.properties`（已 gitignore）或 CI GitHub Secrets 注入；二者皆缺时主动抛 `GradleException` 中止构建，杜绝密钥明文入仓。
👉 **交互优化**：电量规则左滑删除由整块滑出改为 iOS 风格固定宽度红色删除按钮（`flutter_slidable` 替换 `Dismissible`，`extentRatio: 0.28`）。
📝 **文档**：CONTRIBUTING（中/英）新增 §7.1 Android 发布签名密钥规范，并修正 `.env` 已被 gitignore 的说明。

### v1.5.43 - 2026-07-19

**隐私合规 + 品牌完善 + 网站优化**

🛡️ 隐私合规：全项目 Bugly 最小收集原则声明 | 🚫 热更新功能移除 | 🌐 网站图标/翻译/徽章全面优化 | 🔧 电量左滑/每日重置/暗色图标/CI修复 | 📁 下载目录改为 Download/FnthinkNotice

### v1.5.42 - 2026-07-19

**Live Update + 隐私政策 + Cupertino 品牌统一 + 趋势图表优化**

🆕 **新功能**
- Android Live Update 实时通知：前台服务显示已推送通知数量，通知栏顶部优先展示
- 首次启动隐私政策弹窗：同意进入应用，不同意退出

🎨 **UI 优化**
- 全项目品牌统一：「iOS 风格」→「Cupertino 设计语言」
- 推送统计页「近7天趋势」改为横向进度条列表，日期+进度条+数量，直观易读

🌐 **网页更新**
- 官网 index.html 新增中英文切换（`i18n.js`），navbar、hero、features 等全内容双语支持
- 管理后台 admin.html 同步添加语言切换

📝 **文档**
- server 目录新增英文部署文档（`README-en.md`、`GITHUB_PAGES-en.md`）
- README 添加 GitHub Pages 部署网址
- base.md 五更新流程：步骤13改为「视情更新所有 markdown 文档」

### v1.5.41 - 2026-07-19

**数据库迁移修复 + 部署模式扩展 + 隐私政策更新 + AGP 升级**

🔧 **AGP 升级**
- AGP 9.0.1 → 9.3.0（2026年7月最新稳定版），同时 Gradle 9.4.1 → 9.5.0 以满足最低要求

🐛 **Bug 修复**
- 修复 v1.5.40 更新后推送历史和推送统计消失：新增 `_migrateOldDatabaseIfNeeded()` 方法，检测旧明文 `notice_transmit.db` 存在时自动读取全部通知记录和待重试队列，导入新加密数据库，迁移完成后删除旧文件

📝 **隐私政策更新**
- 数据存储与安全章节全面重写：补充 AES-256 加密、AndroidKeyStore 密钥保护、Webhook 加密存储、HTTPS 强制、SSL 证书固定、权限最小化（20→17）等安全措施说明
- 最后更新日期更新为 2026年7月19日

🚀 **部署模式扩展**
- 客户端 `update_manager.dart`：新增 API→静态 JSON 双模式自动回退机制
  - `checkUpdate()`：先请求 `/api/version/check`（服务器模式），失败后回退 `/api/version.json`（静态模式），客户端本地版本对比
  - `checkHotfix()`：同理 `/api/hotfix/check` → `/api/hotfix.json`
  - 新增 `_compareVersions()` 客户端版本对比方法
- GitHub Actions `deploy-pages.yml`：自动部署 `server/public/` + `server/data/` 到 GitHub Pages
- 部署指南 `server/GITHUB_PAGES.md`：零运维静态部署方案

🔧 **文档**
- `README.md` / `README-en.md`：更新服务端技术栈与部署章节，补充两种部署模式
- `base.md`：同步文档版本和应用版本，更新代码审查历史

### v1.5.40 - 2026-07-17

**安全审计全面修复（重大安全更新）**

🔐 **网络安全**
- 移除 `android:usesCleartextTraffic="true"`，新建 `network_security_config.xml` 强制全站 HTTPS
- 4 个 HTTP 客户端 (2×Kotlin OkHttp + 2×Dart http) 添加 SSL 证书固定基础设施，待填入证书指纹即可激活
- 管理后台 Token 改经 `x-admin-token` Header 传递，不再出现在 URL 查询参数和日志中
- 服务端添加安全 HTTP 头: `X-Content-Type-Options` / `X-Frame-Options` / `Referrer-Policy` / `Cache-Control`

🔐 **数据安全**
- Webhook URL（含钉钉/企微/飞书认证 key）从 SharedPreferences 明文迁移到 `flutter_secure_storage` (AndroidKeyStore 加密)
- SQLite 数据库 `sqflite` → `sqflite_sqlcipher`: 通知记录、webhook URL、待重试队列全部 AES-256 加密，密钥存入 AndroidKeyStore
- 旧明文数据库文件首次启动自动清理

🔐 **Android 安全加固**
- 权限最小化: 20→17 项 (移除未使用的 `CHANGE_WIFI_STATE` / `ACCESS_WIFI_STATE` / `CHANGE_NETWORK_STATE`)
- `android:allowBackup` → `false`，防止通知数据通过云备份泄露
- 应用内广播接收器 `RECEIVER_EXPORTED` → `RECEIVER_NOT_EXPORTED`，防止外部伪造通知数据

🔐 **其他修复**
- 生产环境日志脱敏: webhook URL 和响应体仅 debug 模式输出；服务端启动不打印安全状态
- 通知导出: 新增确认对话框 + 导出文件内嵌敏感数据警告
- 服务端 `otplib` v12 → v13 升级
- `.gitignore` 新增 `server/data/*.json`（版本/热修复/二步验证配置）
- 服务端 API 添加字段级输入验证 (`validateVersionConfig` / `validateHotfixConfig`)

### v1.5.39 - 2026-07-17

**息屏电量通知修复（Bug 修复）**
- 🔧 `NotificationMonitorService.kt`：新增 `ACTION_BATTERY_ALARM` + `scheduleBatteryAlarm()`，用 `AlarmManager.setAndAllowWhileIdle(RTC_WAKEUP)`（API≥23，非精确闹钟，无需 `SCHEDULE_EXACT_ALARM` 权限）在 Doze 维护窗口定时唤醒设备执行电量检查，修复息屏/锁屏后电量降到阈值不推送的问题
- 🔧 闹钟触发时短暂持 `PARTIAL_WAKE_LOCK` 跑 `checkBatteryAndNotify()` 并自动排程下一次；`cancelBatteryAlarm()` 在关闭监听 / `onDestroy` 时取消；亮屏走原 Handler 轮询，息屏由闹钟兜底，跨越阈值守卫防重复
- 🔧 上一轮已加的 `ACTION_POWER_CONNECTED/DISCONNECTED` 监听保证息屏插拔充电可靠推送

**启动闪退修复（Bug 修复）**
- 🐛 `NotificationMonitorService.kt`：`batteryChangedReceiver.onReceive` 整段包裹 `try/catch` + `finally` 释放唤醒锁。此前接收器内 `checkBatteryAndNotify()` / `sendNotification()` 若抛未捕获异常，系统会直接杀掉整个进程，表现为「打开即闪退」；现任何异常均被捕获并记录日志，绝不杀进程。`startBatteryMonitoring()` 内的 `registerReceiver` / `scheduleBatteryAlarm()` 也加保护，避免 `onCreate` 抛异常
- 🐛 `battery_page.dart`：将 `rule['id'] as String` 等 6 处危险强转改为 `as String? ?? ''`，防止电量规则缺 `id` 时构建页面抛 `CastError` 崩溃

**电池优化引导（改进）**
- 🆕 `battery_page.dart`：新增 `_maybePromptBatteryOptimization()`，首次启用总开关 / 任一规则 / 新增规则时，若未豁免电池优化则弹出引导对话框，点「去设置」拉起系统页；只提示一次（SharedPreferences `battery_opt_prompt_shown`）。`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` 权限与原生 `requestBatteryOptimization()` 本已具备，此前从未在启用电量通知时触发

**管理后台界面优化（改进）**
- 🔧 `server/public/admin.html`：界面全面美化（响应式适配移动端、按钮微交互、卡片阴影、状态过渡、登录入场动画、JSON 框滚动、底部版本页脚），恢复码区新增「复制全部」按钮；仅改样式与少量 HTML/JS，未动任何 API 与元素 id

### v1.5.38 - 2026-07-17

**可选应用图标扩展（新功能）**
- 🆕 `icon_service.dart`：在原「蓝色 / 紫色」基础上扩展为 16 种常用颜色图标（蓝、青、蓝绿、薄荷、绿、黄、橙、红、粉、玫红、紫、靛、棕、灰、石墨、黑）+ 默认图标，共 17 个
- 🆕 `icon_picker_tile.dart`：选择图标时展示「真实模样」的图标预览（真实铃铛字形 + 对应底色），不再统一替换为小铃铛占位
- 🔧 原始图标由「经典蓝铃」更名为「默认图标」
- ✅ Dart 端图标 key 与原生 `ICON_ALIASES` 别名一一对齐（17 项）

**全量代码审计与 Bug 修复（质量）**
- 🔧 `battery_page.dart`：`_buildRuleTile` 对规则字段的硬转换（`as String/int/bool`）改为空安全，避免旧数据缺字段时电量页崩溃
- 🔒 `update_manager.dart`：`applyHotfix` 解压热更新 ZIP 时新增目录穿越（zip-slip）防护，拒绝含 `..`/绝对路径的条目
- 🔧 `NetworkClient.kt`：`isActive` 原在 `destroy()` 后永久置 false，服务同进程重建后 webhook 静默失效；新增 `activate()` 并在服务 `onCreate` 重新激活
- 🔧 `PhoneCallReceiver.kt`：`CALL_STATE_IDLE` 分支补清 `lastIncomingNumber`，避免复用上次来电号码误发「通话结束」
- 🔧 `main_page.dart`：移除 `_openRuleListPage` 中规则的重复保存（`RuleListPage` 内部已持久化）
- 🔧 `webhook_settings_page.dart`：`_testWebhook` 对原生返回结果改为空安全转换
- 🔧 `rule_edit_page.dart`：条件弹窗改用持久化 `TextEditingController` 并在 `dispose` 释放，修复中文中途编辑光标跳尾与控制器泄漏
- 🔧 `stats_page.dart`：统计计数全部改为空安全转换，柱状图高度增加除零/NaN 防护，分割线颜色改用主题色（深色模式适配）

**服务端健壮性与安全加固（server.js）**
- 🔧 `compareVersions`：对 undefined/非数字版本号（如 `1.5.0-beta`）容错，修复缺失 version 参数时崩溃
- 🔒 CORS 由全放行改为按 `ALLOWED_ORIGINS` 白名单控制（默认放行无 Origin 的原生请求）
- 🔒 `ENCRYPTION_KEY` 增加 64 位十六进制格式校验，非法则忽略并告警
- 🔧 新增会话定期清理，避免内存无上限增长
- 🔒 管理接口 POST（version/hotfix）增加请求体对象校验，拒绝畸形负载
- 🔧 `trust proxy` 支持通过 `TRUST_PROXY` 环境变量配置

**文档**
- 🔧 `README.md` / `README-en.md`：移除「数据重启后丢失」排错条目（该问题已修复，不再适用）

### v1.5.37 - 2026-07-17

**电量条件通知修复（Bug 修复）**
- 🔧 `BatteryMonitor.kt`：`checkBatteryAndNotify` 原 `when(rule.type)` 只识别 `below/above/exact`，与 Dart 侧的 `level_below/level_above/level_equals` 完全不匹配 → 任何电量条件都永不通知；现已识别全部 5 种类型
- 🔧 `BatteryMonitor.kt`：`parseBatteryRules` 原从错误字段 `threshold` 读取阈值（应为 Dart 的 `value`）→ 阈值永远为 0；现改读 `value`
- 🆕 充电（`charging`）/ 放电（`discharging`）规则此前在原生侧从未实现，现已支持（状态跳变触发）
- 🔧 电量类条件改用「由不满足→满足」的跨越触发，避免轮询/广播重复推送；首次调用仅记录基准、不误报

**电量通知总开关生效（连带修复）**
- 🔧 `MainActivity.kt`：`setBatterySetting` 增加 `notifyServiceConfigChanged()`，保存总开关后通知后台服务立即重载
- 🔧 `NotificationMonitorService.kt`：`loadConfig()` 读取 `battery_notify_enabled` 并在 `batteryMonitor.setEnabled()` 中应用；关闭总开关后原生不再推送电量通知
- 🆕 `ConfigManager.kt`：新增 `getBatteryNotifyEnabled()`

**底部提示条行为优化**
- 🔧 `main_page.dart`：新增 `_showInfo()`，信息类提示（如「当前已是最新版本」）时长从约 4s 缩短为 2s，且弹出前先收起上一条
- 🔧 `main_page.dart`：新增 `_pushPage()`，跳转子页面（历史 / 权限 / 应用筛选 / 关键词 / Webhook / 规则列表 / 隐私政策）及底部 tab 切换时，当前提示条立即消失

### v1.5.36 - 2026-07-17

**应用筛选体验优化（改进1）**
- 🆕 `app_filter_page.dart`：新增「反选」按钮，一键反转当前列表中的应用选择状态，配合已有的「全选 / 清空」更高效地调整通知范围

**主题与提示色修复（改进2）**
- 🔧 `app_theme.dart`：新增 `snackBarTheme`，统一底部提示（SnackBar，如「当前已是最新版本」）的背景与文字颜色跟随主题，修复浅色模式显示深色、深色模式显示浅色的反转问题

**可选应用图标（新功能）**
- 🆕 `res/`：新增「蓝色」「紫色」两套备选启动图标（白色铃铛 + 纯色圆角底），并生成对应多密度资源与 adaptive-icon
- 🆕 `AndroidManifest.xml`：将 LAUNCHER 入口迁移到 `.LauncherDefault` 等 `activity-alias`，同一时刻仅启用一个
- 🔧 `MainActivity.kt`：新增 `changeLauncherIcon` / `getLauncherIcon`，通过 `PackageManager.setComponentEnabledSetting` 运行时切换启动图标
- 🆕 `icon_service.dart` / `icon_picker_tile.dart` / `more_page.dart`：在「更多 → 外观设置 → 应用图标」中提供图标选择界面（经典蓝铃 / 蓝色 / 紫色）

### v1.5.35 - 2026-07-17

**黑名单/白名单/应用过滤实时生效（改进1）**
- 🔧 `MainActivity.kt`：新增 `notifyServiceConfigChanged()`，在黑名单、白名单、应用筛选、Webhook 通道/URL、设备名、电量规则等配置保存后，通过 `startService(ACTION_UPDATE_CONFIG)` 通知后台 `NotificationMonitorService` 立即重载配置
- 🔧 `MainActivity.kt`：`setBlacklistKeywords`/`setWhitelistKeywords`/`setEnabledPackages`/`setWebhookChannels`/`setWebhookUrls`/`setDeviceName`/`setBatteryRules` 均调用配置热更新通知
- ✅ 效果：删除黑名单词、调整应用筛选后无需重启软件即可生效

**推送历史持久化与准确性修复（改进2）**
- 🔧 `NotificationService.loadRecords()`：移除从原生 SharedPreferences 读取记录的不可靠逻辑，改为先迁移原生临时记录到 SQLite，再从 SQLite 加载，关闭应用后历史不丢失
- 🔧 `database_helper.dart`：`migrateFromSharedPreferences()` 使用 `ConflictAlgorithm.ignore`，避免原生稀疏缓存覆盖应用内已存在的完整记录
- 🔧 `NotificationMonitorService.kt`：`onNotificationPosted()` 仅在 `shouldNotify()` 通过后才调用 `webhookSender.sendNotification()`，历史只记录实际被推送的通知
- 🔧 `WebhookSender.kt`：`saveNotificationRecord()` 补充 `subText` 字段，记录信息更完整
- ✅ 效果：推送历史真实反映实际推送内容，重启应用后记录仍然存在

### v1.5.34 - 2026-07-17

**通知读取权限解耦（改进1）**
- 🔧 `NotificationMonitorService.kt`：新增 `ACTION_SET_MONITORING`/`monitoringEnabled` 与持久化开关 `flutter.monitoring_enabled`，`onNotificationPosted` 根据开关门控转发，不再依赖组件启停
- 🔧 `NotificationMonitorService.kt`：`onCreate` 始终调用 `startForegroundService`（满足 5 秒内 `startForeground` 约束），并通过 `applyMonitoringState()` 应用开关状态
- 🔧 `NotificationMonitorService.kt`：新增 `readMonitoringEnabled()`/`applyMonitoringState()`/`stopForegroundCompat()`
- 🔧 `MainActivity.kt`：`isServiceRunning` 改为返回持久化开关 `isMonitoringEnabled()`；`start/stopNotificationListener` 改为设置开关并下发 `ACTION_SET_MONITORING`，不再禁用监听器组件
- 🔧 `MainActivity.kt`：`toggleNotificationListenerService()` 改为仅启用组件（自愈历史禁用），`onCreate` 启动时自动修复被禁用的监听器组件
- ✅ 效果：通知读取权限能否申请与是否开启监听服务无关；关闭监听后不再被系统撤销权限，状态显示与实际权限一致

**推送统计软件名修复（改进2）**
- 🔧 `database_helper.dart`：`getNotificationStats()` SQL 增加列别名 `app_name AS appName, package_name AS packageName`，修复 Dart 端读取 camelCase 键永远为 null 的问题
- 🔧 `stats_page.dart`：读取 `appName`，为空时回退 `packageName`，再回退「未知」

**在线更新优化（改进3）**
- 🔧 `update_manager.dart`：新增 `storagePermissionGranted()`/`requestStoragePermission()`/`resolveDownloadDir()`，安装包统一下载到 `/storage/emulated/0/Download/fnthink.notice`
- 🔧 `update_manager.dart`：`downloadApk()` 下载前先申请存储权限，下载成功后 `_recordPendingApk()` 记录安装包路径与目标版本
- 🔧 `update_manager.dart`：`installApk()` 移除脆弱的 5 分钟定时删除，改为 `init()` 启动时 `_cleanupInstalledApk()` 按版本比对自动删除旧安装包
- 🔧 `update_service.dart`：透传 `storagePermissionGranted()`/`requestStoragePermission()`
- 🔧 `main_page.dart`：`_startDownloadUpdate()` 改为异步，先经 `_ensureStoragePermissionForUpdate()` 检测并引导授予存储权限
- 🔧 `AndroidManifest.xml`：新增 `WRITE_EXTERNAL_STORAGE`(maxSdk28)/`READ_EXTERNAL_STORAGE`(maxSdk32)/`MANAGE_EXTERNAL_STORAGE` 权限声明

### v1.5.33 - 2026-07-15

**设置状态实时更新**
- 🔧 `main_page.dart`：修复深色模式切换后界面不立即刷新的问题，添加 `setState()` 调用
- 🔧 `permission_settings_page.dart`：添加 `didChangeDependencies()` 生命周期方法，页面重新显示时自动刷新权限状态

**权限申请优化**
- 🔧 `permission_service.dart`：短信、电话权限改为使用 `permission_handler` 库弹窗直接申请，不再跳转系统设置
- 🔧 `permission_service.dart`：权限请求结果实时更新本地状态

**推送统计优化**
- 🔧 `database_helper.dart`：`getNotificationStats()` 查询增加 `package_name` 字段，用于应用名解析
- 🔧 `stats_page.dart`：新增 `_getAppName()` 方法，通过包名查询真实应用名称
- 🔧 `stats_page.dart`：使用解析后的应用名显示，修复显示「未知」的问题
- 🔧 `MainActivity.kt`：新增 `getAppNameByPackage()` MethodChannel 方法，支持 Flutter 端查询应用名称

**通知权限判断优化**
- 🔧 `MainActivity.kt`：`isNotificationListenerPermissionGranted()` 改用系统 API `enabledListenerPackages` 检查权限，而非检查服务连接状态
- 🔧 `MainActivity.kt`：解决关闭后台后权限状态显示错误的问题

**代码优化（架构级重构）**

**问题1：移除死代码，修复数据持久化双轨制**
- 🗑️ `state/app_state.dart`：删除死代码文件，`AppState` 已无任何引用，与各 Service 层维护独立数据副本导致数据不一致
- 🔧 `di/service_locator.dart`：移除 `AppState` 的注册，所有状态由各 Service 管理
- 🔧 `database/database_helper.dart`：`migrateFromSharedPreferences()` 读取键名从 `'records'` 改为 `'notification_records'`，修复迁移逻辑永远不会执行的问题
- 🔧 `database/database_helper.dart`：迁移时同时兼容 camelCase 和 snake_case 键名

**问题2：统一 MethodChannel 声明**
- 📄 `services/platform_channel.dart`：新建统一通道声明文件，定义 `AppChannels.notification`
- 🔧 `services/webhook_service.dart`、`services/battery_service.dart`、`services/notification_service.dart`、`services/filter_service.dart`、`services/device_info_service.dart`、`services/permission_service.dart`：使用统一通道
- 🔧 `pages/main_page.dart`、`pages/app_filter_page.dart`、`pages/stats_page.dart`、`pages/webhook_settings_page.dart`：使用统一通道
- 🔧 `update_manager.dart`：使用统一通道

**问题3：修复数据库表字段与模型类不匹配**
- 🔧 `database/database_helper.dart`：数据库版本从 2 升级到 3，新增 `sub_text` 列
- 🔧 `database/database_helper.dart`：`onUpgrade()` 添加 `ALTER TABLE` 迁移逻辑
- 🔧 `database/database_helper.dart`：`insertNotification()` 支持 camelCase 和 snake_case 键名映射，添加 `sub_text` 字段处理
- 🔧 `services/notification_service.dart`：`addRecord()` 使用 `NotificationRecord.toMap()` 标准方法

**问题4：规则引擎运算符优先级支持**
- 🔧 `services/filter_service.dart`：`evaluateRule()` 重构为支持 AND 优先于 OR 的优先级逻辑，使用分组计算替代线性计算
- 🔧 `services/filter_service.dart`：空条件时返回 `false`（不匹配任何通知），明确行为

**问题5：Timer 生命周期保护**
- 🔧 `services/battery_service.dart`：添加 `_isDisposed` 标志，Timer 回调中检查生命周期状态，`dispose()` 方法取消定时器
- 🔧 `services/retry_service.dart`：Timer 回调中检查 `_isRunning` 状态，防止服务已停止时继续执行

**问题6：滑动手势冲突修复**
- 🗑️ `pages/battery_page.dart`：删除自定义 `Slideable` 组件
- 🔧 `pages/battery_page.dart`：使用 Flutter 内置 `Dismissible` 组件替代，支持左滑删除并带确认弹窗

**问题7：异常日志输出完善**
- 🔧 `services/battery_service.dart`：添加 `debugPrint` 日志输出（设置推送开关、规则同步、获取电池状态失败）
- 🔧 `services/webhook_service.dart`：添加 `debugPrint` 日志输出（保存通道、同步启用URL失败）
- 🔧 `services/filter_service.dart`：添加 `debugPrint` 日志输出（保存启用包、黑名单、白名单、通知规则失败）

**问题8：颜色主题统一**
- 🔧 `theme/app_colors.dart`：添加静态常量 `blue`、`green`、`red`、`orange`、`purple`、`cyan`、`yellow`
- 🔧 13 个页面文件：将硬编码颜色值替换为 `AppColors.blue`、`AppColors.green`、`AppColors.red` 等

**问题9：版本号同步**
- 🔧 `update_manager.dart`：默认版本号与 `pubspec.yaml` 同步为 `1.5.33` / build `67`

**问题10：依赖注入重复调用修复**
- 🔧 `pages/splash_page.dart`：移除 `setupLocator()` 调用（已在 `main.dart` 中初始化）

**问题11：飞书域名匹配完善**
- 🔧 `models/webhook_channel.dart`：`detectTypeFromUrl()` 添加 `larksuite.com` 域名匹配，并转为小写比较

**问题12：签名密钥安全**
- 🔧 `android/app/build.gradle.kts`：移除硬编码的签名密钥密码，改用环境变量配置
- 🔧 `.gitignore`：添加 `*.jks` 和 `*.keystore` 规则

**问题13：线程可见性优化**
- 🔧 `NotificationMonitorService.kt`：`webhookUrls`、`deviceName`、`isConnected` 添加 `@Volatile` 注解
- 🔧 `MainActivity.kt`：`PrefsHelper.webhookUrls`、`PrefsHelper.deviceName` 添加 `@Volatile` 注解
- 🔧 `BatteryMonitor.kt`：`lastNotifiedLevel`、`deviceName` 添加 `@Volatile` 注解

**问题14：NetworkClient 恢复能力**
- 🔧 `NetworkClient.kt`：`destroy()` 使用标志位控制协程启动，而非取消 SupervisorJob

**问题15：协程生命周期管理**
- 🔧 `MainActivity.kt`：`testWebhook()` 使用 Activity 级别协程作用域，`onDestroy()` 时取消

**问题16：线程安全保护**
- 🔧 `NotificationProcessor.kt`：`notifiedKeys` 使用 `Collections.synchronizedSet()` 包装

**问题17：配置缓存优化**
- 🔧 `NotificationMonitorService.kt`：`ConfigSnapshot` 缓存到成员变量，仅在 `loadConfig()` 时更新

**问题18：清单文件清理**
- 🔧 `AndroidManifest.xml`：移除不必要的 `largeHeap="true"` 和 `persistent="true"` 属性

**问题19：权限精简**
- 🔧 `AndroidManifest.xml`：移除未使用的权限（`SYSTEM_ALERT_WINDOW`、`DISABLE_KEYGUARD`、`READ_CALL_LOG`、`ANSWER_PHONE_CALLS`）

**问题20：代码混淆规则就绪**
- 🔧 `proguard-rules.pro`：创建 ProGuard/R8 混淆规则文件
- 🔧 `build.gradle.kts`：`release` 构建保持 `isMinifyEnabled = false`、`isShrinkResources = false`（混淆与资源压缩默认关闭，规则文件就绪后可按需开启）

**问题21：资源管理优化**
- 🔧 `ConfigManager.kt`：`loadHotfixConfig()` 使用 Kotlin `use` 扩展自动管理流资源

**问题22：代码去重**
- 🔧 `PhoneCallReceiver.kt`：提取 `sendCallWebhook()` 公共方法，消除三个 webhook 发送方法的重复代码

**问题23：重试逻辑优化**
- 🔧 `NetworkClient.kt`：关闭 OkHttp 自动重试，仅使用自定义重试逻辑，避免双重重试

**问题24：会话 ID 安全**
- 🔧 `server/server.js`：`generateSessionId()` 使用 `crypto.randomUUID()` 替代 `Math.random()`

**问题25：Token 传输安全**
- 🔧 `server/server.js`：`authMiddleware` 仅接受 Header 传递的 Token，移除 URL 参数支持

**问题26：敏感数据加密**
- 🔧 `server/server.js`：TOTP secret 使用 AES-256-GCM 加密存储；恢复码使用 bcrypt 哈希存储

**问题27：全局错误处理**
- 🔧 `server/server.js`：添加全局异步错误处理中间件，返回 JSON 格式错误响应

**问题28：IP 信任配置**
- 🔧 `server/server.js`：配置 `trust proxy`，`getClientIp()` 使用 `req.ip` 获取真实 IP

**问题29：请求体大小限制**
- 🔧 `server/server.js`：`express.json()` 添加 `limit: '1mb'` 限制

**问题31：.gitignore 完善**
- 🔧 `.gitignore`：添加 `.env`、`install_dir/`、`server/data/blocked_ips.json`、`server/data/failed_attempts.json` 等规则

**问题32：分析规则扩展**
- 🔧 `analysis_options.yaml`：扩展 linter 规则集（`avoid_unnecessary_containers`、`avoid_empty_else`、`prefer_const_declarations`、`require_trailing_commas`、`avoid_web_libraries_in_flutter`）

**问题33：CI 测试优化**
- 🔧 `.github/workflows/build-apk.yml`：简化单元测试步骤，移除冗余的错误处理逻辑

**问题34：Gradle 配置说明**
- 🔧 `android/gradle.properties`：保留 `android.newDsl=false` 和 `android.builtInKotlin=false`，配合 `settings.gradle.kts` 中显式声明的 `org.jetbrains.kotlin.android` 2.3.20 KGP 插件，确保原生插件编译稳定


---

### v1.5.32 - 2026-07-14

**[紧急] 推送服务问题修复**
- 🔧 `notification_service.dart`：移除 `FlutterForegroundTask` 依赖，改用直接操作 Android 原生服务，消除双通知冲突
- 🔧 `MainActivity.kt`：删除 `onResume()` 中的 `stopOldService()` 调用，这是「测试通过但不推送通知」的根本原因（每次打开应用都会停止监听服务）
- 🔧 `MainActivity.kt`：`stopNotificationListener()` 改用 `setComponentEnabledSetting(DISABLED)` 替代 `stopService()`，正确管理 NotificationListenerService 生命周期
- 🔧 `AndroidManifest.xml`：删除 `flutter_foreground_task` 相关服务声明
- 🔧 `pubspec.yaml`：移除 `flutter_foreground_task` 依赖

**[关键] 数据持久化修复（重启后数据消失）**
- 🔧 `main.dart`：修复 `SplashPage` 回调为空函数的问题，将 `_initialized` 拆分为 `_themeInitialized` 和 `_servicesInitialized`，确保服务初始化流程完整执行，解决重启后所有配置丢失的问题
- 🔧 `filter_service.dart`：`saveEnabledPackages()`、`saveBlacklistKeywords()`、`saveWhitelistKeywords()` 同时保存到 SharedPreferences，之前只通过 MethodChannel 同步到原生，导致重启后数据丢失
- 🔧 `filter_service.dart`：`loadSettings()` 在 MethodChannel 失败时从 SharedPreferences 读取数据作为备用
- 🔧 `WebhookSender.kt`：`saveNotificationRecord()` 方法改为 public，确保 NotificationMonitorService 可调用保存通知记录
- 🔧 `WebhookSender.kt`：使用 `FlutterSharedPreferences` 文件和 `flutter.notification_records` 键，与 Flutter 端保持一致，解决推送历史不显示的问题
- 🔧 `ConfigManager.kt`：`KEY_WEBHOOK_URLS` 从 `flutter.webhook_urls` 改为 `flutter.webhook_channels`，并修改 `getWebhookUrls()` 解析完整的 channel 对象，解决 Webhook 配置不生效的问题

**[关键] 版本号显示修复**
- 🔧 `update_manager.dart`：默认版本号设置为 `1.5.32/66`，确保 MethodChannel 获取失败时显示正确版本号

**[关键] 推送历史修复**
- 🔧 `NotificationMonitorService.kt`：将 `sendBroadcast()` 和 `saveNotificationRecord()` 移到 `shouldNotify()` 过滤检查之前，确保所有通知都能记录到推送历史，而不仅仅是通过过滤的通知

**权限申请优化**
- 🔧 `permission_service.dart`：通知访问权限和允许通知权限分开管理（新增 `notificationListenerGranted`、`postNotificationGranted`）
- 🔧 `MainActivity.kt`：新增 `isPostNotificationPermissionGranted()` 和 `requestPostNotificationPermission()` 方法（Android 13+ POST_NOTIFICATIONS 权限）
- 🔧 `permission_settings_page.dart`：新增「允许通知」权限项，非必要权限增加详细用途说明
- 🔧 `main_page.dart`：返回权限设置页面后自动刷新权限状态和服务运行状态
- 🔧 `main_page.dart`：首次打开应用时，若未开启通知访问权限则弹窗引导

**在线更新优化**
- 🔧 `update_manager.dart`：安装包存储路径改为 `Download/fnthink.notice` 目录，通过 MethodChannel 调用原生获取（兼容 Android 10+ 分区存储）
- 🔧 `update_manager.dart`：下载前检测存储权限，未授予时抛出明确错误
- 🔧 `update_manager.dart`：安装后 5 分钟自动删除安装包，同时保留旧安装包清理逻辑
- 🔧 `MainActivity.kt`：新增 `getDownloadDirectory()` 方法获取公共下载目录

**代码质量改进（Flutter 端）**
- 🔧 `notification_service.dart`：`print()` → `debugPrint()`，Release 模式自动优化
- 🔧 `notification_service.dart`：移除 `_saveRecords()` 中 SharedPreferences 双重存储，仅保留 SQLite
- 🔧 `filter_service.dart`：删除冗余的 `import 'dart:core'`
- 🔧 `permission_service.dart`：抽取通用 `_requestPermission()` 方法，消除 9 个重复 try-catch 模板
- 🔧 `app_theme.dart`：抽取 `_buildTheme()` 公共方法，消除 light/dark 主题 90% 重复代码
- 🔧 `app_colors.dart`：删除重复的 `pageBg()` 方法，统一使用 `bgColor()`
- 🔧 `device_info_service.dart`：移除冗余的 `device_info_plus` 调用，仅保留 native 调用获取设备信息
- 🔧 `main.dart`：`MyApp` 已迁移到当前文件，DI 失败时显示错误界面并阻止启动
- 🔧 `battery_rule.dart` / `notification_rule.dart` / `webhook_channel.dart`：所有 enum 的 `fromValue()` 方法添加未知值警告日志
- 🔧 `webhook_channel.dart`：ID 默认值从时间戳改为 UUID，避免同一毫秒内创建多个 channel 导致 ID 冲突
- 🔧 `database_helper.dart`：新增 `pending_notifications` 表，支持待重试通知的 SQLite 存储
- 🔧 `retry_service.dart`：待重试通知从 SharedPreferences 迁移到 SQLite，提高数据可靠性
- 🔧 新增 `theme_service.dart`：主题模式管理服务，支持 DI 方式获取和修改主题

**代码质量改进（Android 原生端）**
- 🔧 `MainActivity.kt`：删除重复的 `when` 分支（`requestXiaomiAutoStart`、`requestMeizuBackground` 各注册了两次）
- 🔧 `NotificationMonitorService.kt`：移除 `companion object` 中未使用的变量（`enabledPackages`、`blacklistKeywords`、`whitelistKeywords`），`onNotificationPosted()` 实际使用 `ConfigSnapshot` 重新读取的值
- 🔧 `NotificationMonitorService.kt`：魔法数字 `0x40000000` 改为命名常量 `ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC`
- 🔧 `NotificationProcessor.kt`：`notifiedKeys` 超限时改为 LRU 淘汰策略，不再全量清除
- 🔧 `NotificationProcessor.kt`：精简 `getFriendlyAppName()` 硬编码（从 80+ 个精简到 15 个核心应用），优先使用 hotfix 配置
- 🔧 `NotificationProcessor.kt`：删除 `resolveRealAppName()` 中未使用的 `content` 参数
- 🔧 `WebhookSender.kt`：添加协程作用域生命周期管理，Service 销毁时取消所有协程
- 🔧 `WebhookSender.kt` / `SmsReceiver.kt` / `PhoneCallReceiver.kt`：`Thread.sleep()` 改为 `delay()`，避免阻塞 IO 线程
- 🔧 `BatteryMonitor.kt`：`getBatteryInfo()` 返回 `null` 时跳过检查，不再降级为 `level=0` 导致误报
- 🔧 `SmsReceiver.kt` / `PhoneCallReceiver.kt`：统一通过 `ConfigManager` 读取配置，消除两套配置读取逻辑
- 🔧 新增 `NetworkClient.kt`：抽取公共网络请求和重试逻辑，消除 `WebhookSender`、`SmsReceiver`、`PhoneCallReceiver` 中的重复代码
- 🔧 `PhoneCallReceiver.kt`：`companion object` 中可变状态变量（`lastState`、`lastIncomingNumber`、`callStartTime`）添加 `@Volatile` 注解，确保线程安全

**代码质量改进（服务端）**
- 🔧 `server.js`：`ADMIN_TOKEN_HASH` 未配置时拒绝启动，不再回退到硬编码值，提高安全性
- 🔧 `server.js`：`failedAttempts` 失败计数从内存对象改为文件持久化存储（`failed_attempts.json`），服务重启后不再丢失
- 🔧 `server.js`：新增请求速率限制中间件，普通接口每分钟最多 60 次请求，认证接口每分钟最多 5 次

**代码质量改进（页面层）**
- 🔧 `more_page.dart`：通过 `GetIt` 注入 `UpdateService` 替代直接访问 `AppUpdateManager.instance` 单例，保持 DI 一致性
- 🔧 `history_page.dart`：添加 `_searchController.dispose()` 方法，防止内存泄漏

**测试体系改进**
- 🔧 `widget_test.dart`：替换为实际项目测试，覆盖 `NotificationRecord`、`BatteryRule`、`WebhookChannel` 模型的序列化、反序列化、copyWith 等核心功能
- ✅ 所有 73 个测试用例通过

**CI/CD 与工程化改进**
- 🔧 `.github/workflows/build-apk.yml`：新增 Android 单元测试步骤（`./gradlew testReleaseUnitTest`）
- ✅ `crash_log.txt` 已在 `.gitignore` 中

---

### v1.5.31 - 2026-07-13

**Bug修复与稳定性提升**
- 修复Android 14+前台服务启动崩溃问题（MissingForegroundServiceTypeException）
- 修复规则列表页面标签栏溢出问题（RenderFlex overflowed）
- 重构启动流程，添加全局异常捕获（runZonedGuarded + FlutterError.onError）
- 优化启动页，避免首帧阻塞导致白屏
- 服务端二步验证支持恢复码功能
- 添加IP封锁机制（10分钟内输错3次验证码封锁240小时）
- Token验证升级为bcrypt哈希验证
- ⚠️ 本版本设置为强制更新版本

**代码审查发现（待修复）**
- 📋 `app_state.dart` 死代码（347行，无任何引用）
- 📋 `update_manager.dart` 与 `update_service.dart` 功能重叠
- 📋 9处 MethodChannel 重复定义（建议创建共享常量）
- 📋 `main_page.dart` 仍为1284行（建议拆分 Tab 和对话框）

---

### v1.5.30 - 2026-07-13

**架构重构与安全加固**
- 服务端API添加Token鉴权保护（x-admin-token头）
- 删除crash_log.txt文件并确保已在.gitignore中
- 创建AppState全局状态管理（ChangeNotifier），为后续代码拆分打下基础
- 拆分main_page.dart为7个独立Service（WebhookService、BatteryService等）
- 拆分NotificationMonitorService.kt为多个独立模块（NotificationProcessor、BatteryMonitor等）
- 引入get_it依赖注入框架
- 迁移通知记录到SQLite数据库
- 添加推送失败重试机制
- 规则引擎支持时间条件和正则表达式
- 修复所有flutter analyze警告
- 添加49个单元测试用例
- ⚠️ 本版本设置为强制更新版本

---

### v1.5.29 - 2026-07-09

**功能修复与优化**
- 修复电量规则删除按钮显示问题：仅左滑时显示删除按钮，正常状态下完全隐藏
- 实现规则引擎优先级功能：规则编辑页面支持设置优先级（默认/低/中/高/最高），规则按优先级排序执行
- 代码格式优化

---

### v1.5.28 - 2026-07-09

**代码架构优化**
- main.dart代码拆分：将5866行代码拆分为9个独立页面文件
- 创建 pages/main_page.dart、notification_page.dart、battery_page.dart、more_page.dart、webhook_settings_page.dart、app_filter_page.dart、keywords_page.dart、history_page.dart、permission_settings_page.dart
- 删除main.dart中的重复代码，保持入口文件简洁
- base.md添加iOS风格UI强制规范

---

### v1.5.27 - 2026-07-09

**更新优化与体验增强**
- 更新检测逻辑优化：未上传APK时自动从GitHub下载（加速域名 xget.fnthink.top）
- 电量规则增加左滑删除和长按删除功能
- 规则引擎页增加第一次进入引导说明
- UI风格统一为iOS风格（卡片、圆角、主题色）
- base.md文档重新整理，已完成内容归档到对应章节
- 五更新流程规范优化

---

### v1.5.26 - 2026-07-09

**图标美化与性能优化**
- 图标主体缩小至24%，视觉效果更协调
- 新增深色模式图标适配，系统深色模式下自动切换图标背景色
- 关于页图标替换为软件图标
- 仅保留arm64位库，减小APK体积
- 电量通知规则页、白黑名单页样式适配iOS风格
- 电池通知规则支持低于/等于/高于某值三种条件
- 优化通知列表渲染性能，解决卡顿问题
- 代码格式化与分析优化

---

### v1.5.25 - 2026-07-09

**规则引擎可视化**
- 新增规则引擎可视化配置功能
- 创建规则模型类：NotificationRule、Condition、RuleAction、ConditionType、ActionType、LogicOperator
- 规则列表页：支持添加、编辑、删除规则，显示规则条件和动作摘要
- 规则编辑页：可视化条件配置（IF）、可视化动作配置（THEN）
- 条件类型：应用包名、标题包含/不包含、内容包含/不包含、通知优先级、时间范围、正则表达式
- 动作类型：推送通知、静默忽略、延迟推送、合并推送、仅记录
- 默认规则：验证码短信优先推送、营销广告拦截、夜间免打扰
- 修复 NotificationRecord 模型使用问题，统一使用对象属性访问而非 Map 操作
- 修复 DropdownButtonFormField 中 value 属性已弃用问题，改用 initialValue

---

### v1.5.24 - 2026-07-08

**五更新流程 & 插件升级**
- 将更新流程统一命名为「五更新」，新增 `dart format lib/` 步骤，确保代码格式一致
- 更新 `device_info_plus` 到 v13.2.0，支持 Built-in Kotlin
- 更新 `package_info_plus` 到 v10.2.0，支持 Built-in Kotlin
- 修复 `flutter_foreground_task` 9.2.2 的 `onDestroy` 方法签名问题
- 更新 README 常见问题与排错章节
- 更新 base.md 技术文档
- 更新 README-en.md 英文文档

---

### v1.5.23 - 2026-07-02

**隐私政策 & 代码架构优化**
- 新增隐私政策页面，详细说明数据采集与隐私保护
- README 增加隐私说明章节，明确 Bugly 仅收集崩溃数据
- 代码拆分第一阶段：建立模块化目录结构
  - models/：通知记录、电池规则、Webhook 渠道模型
  - theme/：颜色主题、主题配置
  - pages/：开屏页、隐私政策页
  - services/、state/、widgets/ 目录预留
- 引入 provider 状态管理库，为后续状态管理做准备

---

### v1.5.22 - 2026-07-02

**电池监控优化 & 架构精简**
- 修复电池状态监控通知不稳定的问题：增加 60 秒主动轮询，确保后台/锁屏时也能检测到状态变化
- 原生库仅保留 arm64-v8a 架构，减小 APK 体积
- 接入腾讯 Bugly 崩溃统计，便于快速定位线上问题
- 新增 GitHub Actions CI/CD 工作流（代码检查 + 自动构建）
- 完善 base.md 技术文档，增加详细的路线图规划

---

### v1.5.21 - 2026-07-02

**接入 Bugly 崩溃统计**
- 接入腾讯 Bugly SDK，自动收集应用崩溃信息
- 支持崩溃信息自动上报，便于快速定位和修复问题

---

### v1.5.20 - 2026-07-02

**体验优化**
- 去除 Android 原生启动页 logo，避免启动过渡更自然
- 深色模式选项增加对应图标
- 优化 启动服务时机
- README 补充版本要求说明

---

### v1.5.19 - 2026-07-02

**冷启动闪退修复**
- 修复冷启动时前台服务启动超时导致的闪退
- 优化服务启动时序，确保 startForeground 优先执行
- 延迟自启服务启动时机，避免与主进程初始化冲突

---

### v1.5.18 - 2026-07-01

**电量通知自定义 & 冷启动修复**
- 电量通知条件支持完全自定义（充电/断开/指定电量等）
- 支持添加、编辑、删除通知规则
- 开屏时长优化为 666ms
- 修复冷启动闪退问题

---

### v1.5.17 - 2026-07-01

**代码健壮性优化**
- 应用列表权限请求增加异常捕获
- 优化权限跳转代码结构

---

### v1.5.16 - 2026-07-01

**权限请求体验优化与 Bug 修复**
- 短信/电话权限改为系统弹窗一键授权
- 新增权限请求结果实时回调
- 修复应用列表权限跳转错误页面问题

---

### v1.5.15 - 2026-07-01

**稳定性优化与细节调整**
- 开屏页面时间优化为 1 秒
- 权限跳转兜底逻辑完善
- 品牌适配细节优化

---

### v1.5.14 - 2026-07-01

**开屏页、首页改版、权限体系与品牌适配全面升级**
- 全新开屏页面
  • 展示时长 1 秒，淡入淡出过渡
  • 居中显示应用图标 + 软件名称
  • 底部显示「幻念团队」品牌标识
  • 自动适配浅色/深色模式
- 首页全新改版
  • 极简设计：中间圆形服务控制按钮
  • 绿色运行中 / 红色未启动，状态一目了然
  • 下方设置权限设置、推送历史快捷入口
  • 权限设置从首页移除，独立为二级页面
- 权限设置独立页面
  • 权限分为三组：必要权限、厂商后台设置、非必要权限
  • 必要权限：通知访问、电池优化（带「必要」标签）
  • 厂商后台设置：根据设备品牌自动显示对应项
  • 非必要权限：短信增强、来电监听、应用列表查询
  • 所有权限均显示开启状态，未开启可点击跳转设置
  • 权限跳转兜底：无法跳转到指定权限时，自动跳转到应用详情页
- 设备品牌适配大幅扩展
  • 小米/红米/POCO/黑鲨
  • 华为/荣耀
  • OPPO/一加/真我
  • vivo/iQOO
  • 魅族
  • 三星
  • 原生 Android（Pixel/摩托罗拉/诺基亚）
- 热更新自动下载改为后台静默
  • 自动检测到热更新后静默下载安装
  • 用户无感知，不打断使用
  • 手动检查更新时仍会显示进度

---

### v1.5.13 - 2026-07-01

**开屏Logo、权限引导与深色模式优化**
- 新增开屏 Logo
  • 应用启动时显示应用图标居中展示
  • 浅色模式：白色背景 + 应用图标
  • 深色模式：黑色背景 + 应用图标
  • 自动跟随系统主题切换
- 权限引导全面升级
  • 所有权限项点击先展示说明弹窗
  • 每个权限都有详细用途说明
  • 配套分步操作指引
  • 「稍后再说」/「去开启」双按钮交互
- 涉及权限：通知访问、电池优化、小米自启动、魅族后台
- 深色模式选择器新增图标
  • 跟随系统：自动图标 + 灰色
  • 浅色模式：太阳图标 + 橙色
  • 深色模式：月亮图标 + 紫色
  • 图标带圆角背景，视觉更精致

---

### v1.5.12 - 2026-07-01

**关于页面与版权信息优化**
- 关于对话框全新设计
  • 图标替换为应用 Logo（app_icon.png）
  • 添加圆角与阴影效果，更精致美观
  • 精简介绍内容，突出核心功能定位
- 更多页底部新增版权信息
  • 显示 © 幻念团队 fnthinklevi
  • 三级文字颜色，低调不突兀
- 新增 assets/app_icon.png 资源声明
- 关于页介绍文案调整为：监听通知栏消息，通过 Webhook 推送至企业微信、钉钉、飞书等平台

---

### v1.5.11 - 2026-07-01

**应用筛选功能全面优化**
- 新增应用列表权限检测与引导
  • 进入应用筛选页面前先检测读取应用列表权限
  • 无权限时展示友好的权限引导页面
  • 一键跳转到系统设置开启权限
- 新增应用列表缓存机制
  • 读取应用列表后自动保存缓存
  • 下次进入页面先展示缓存列表，无需等待
  • 大幅提升页面打开速度
- 新增后台刷新与动态加载
  • 展示缓存列表的同时后台静默刷新
  • 检测到新应用时自动动态更新列表
  • 用户无感知，体验流畅
- Android 端新增 QUERY_ALL_PACKAGES 权限声明
- 新增应用列表缓存读写方法（getCachedInstalledApps / saveInstalledAppsCache）
- 新增权限检测方法（canQueryAllPackages / requestQueryAllPackagesPermission）
- 三更新升级为四更新：新增 README 视情更新项（含 README-en.md）

---

### v1.5.10 - 2026-06-30

**SnackBar深色模式适配与主题系统完善**
- 新增 snackBarTheme 全局主题配置
  • 浅色模式：白色卡片背景 + 黑色文字
  • 深色模式：深灰卡片背景 + 白色文字
  • 浮动式设计，圆角12px，带阴影
- 所有 SnackBar 自动适配深色模式：
  • "当前已是最新版本"提示
  • "请在设置中开启通知访问权限"提示
  • 下载失败、热更新状态等所有提示
  • Webhook 配置保存提示
  • 应用列表加载失败提示
  • 历史记录清空、分享等操作提示
- 主题系统进一步完善，组件级覆盖更全面
- 本版本设为强制更新版本

---

### v1.5.9 - 2026-06-30

**主题系统重构 - 为深色模式打造坚实地基**
- 全新主题系统架构：基于 Flutter ThemeExtension
  • 创建 AppThemeColors 类，继承 ThemeExtension<AppThemeColors>
  • 统一管理浅色/深色两套完整配色方案
  • 支持主题色平滑过渡动画（lerp）
- 完整的语义化颜色体系：
  • 背景色、卡片色、分隔线色
  • 三级文字颜色（主标题/次级/三级）
  • 输入框背景色
  • 8种系统颜色：蓝、绿、橙、红、紫、青、黄
- 浅色主题：iOS 风格浅色配色
- 深色主题：纯黑背景 + 深灰卡片（OLED 友好）
- 新增全局主题配置：
  • inputDecorationTheme：统一输入框样式
  • dialogTheme：统一对话框样式
- AppColors 工具类全面升级：
  • 通过 AppColors.of(context) 获取当前主题配色
  • 所有颜色方法自动适配深浅模式
  • 新增系统颜色便捷方法（systemBlue、systemGreen 等）
- 后续新模块只需调用 AppColors.xxx(context) 即可自动适配深色模式
- 本版本设为强制更新版本

---

### v1.5.8 - 2026-06-30

**深色模式深度优化与Bug修复**
- 彻底修复深色模式切换后更多页不刷新的问题
  • 采用 ValueNotifier + ValueListenableBuilder 方案
  • MainPage 监听主题变化自动重建
  • 切换主题后所有页面立即更新，无需切换标签页
- 全面修复对话框深色模式适配
  • 更新对话框：版本信息、更新内容背景、文字颜色
  • 下载进度对话框：进度条背景色适配
  • 关于对话框：背景色、文字颜色适配
  • 设备名称对话框：输入框、按钮颜色适配
  • 主题选择对话框：背景色、文字颜色适配
  • 清空历史确认对话框：背景色适配
  • 历史记录详情对话框：背景色适配
- 修复其他遗漏的白色块
  • 关键词页 TabBar 未选中文字颜色
  • 应用筛选页清空按钮文字颜色
- 强制更新版本设置为 1.5.4（build 37）

---

### v1.5.7 - 2026-06-30

**深色模式全面适配与修复**
- 修复深色模式切换后更多页不刷新的问题（添加 ValueKey 强制重建）
- 新增 AppColors 工具类，统一管理深色/浅色模式颜色
- 全面适配所有页面深色模式：
  • 通知页：运行状态、权限设置、服务控制、支持的通知类型等
  • 电量页：提醒设置、通知类型卡片等
  • 更多页：外观设置、推送设置、设备、关于与更新等
  • Webhook设置页：通道列表、输入框、添加按钮等
  • 历史记录页：搜索框、记录列表、详情对话框等
  • 关键词过滤页：白名单/黑名单标签、输入框、列表等
  • 应用筛选页：搜索框、应用列表等
- 深色模式配色：纯黑背景、深灰卡片、适配的文字和分隔线颜色
- 强制更新版本设置为 1.5.4（build 37）

---

### v1.5.6 - 2026-06-30

**深色模式适配**
- 新增深色模式支持：浅色、深色、跟随系统三种模式
- 更多页增加"外观设置"分组，包含深色模式设置项
- 点击深色模式选项弹出选择对话框，可切换三种模式
- 主题设置持久化保存到 SharedPreferences，重启后保留设置
- MyApp 改为 StatefulWidget，提供全局主题切换能力
- 提供完整的深色主题配色：背景、卡片、导航栏、分割线等全面适配
- 强制更新版本设置为 1.5.4（build 37）

---

### v1.5.5 - 2026-06-30

**ANR 修复：应用无响应问题**
- 修复更新后首次打开应用出现"软件无反应，是否结束运行"的问题
- 根本原因：NotificationMonitorService.onCreate() 在主线程执行耗时操作（加载配置、读取热更新文件、设备名文件I/O）
- 解决方案：将 loadConfigFromPrefs() 和 loadHotfixConfig() 移到 IO 线程异步执行
- 优化服务启动流程：先启动前台服务和注册广播，再后台加载配置
- 确保服务快速响应，不阻塞主线程

---

### v1.5.4 - 2026-06-30

**设备名持久化彻底修复**
- 修复更多页设备名在软件更新后仍重置为默认值的问题
- 根本原因：Flutter端_getDeviceInfo()与_loadAllSettings()存在竞态条件，前者可能先生成默认值并写入文件，覆盖文件中已有的正确值
- 解决方案：统一设备名初始化入口，全部交由原生端getDeviceName处理
- 移除Flutter端_getDeviceInfo()中的默认设备名生成逻辑
- 原生端getDeviceName在文件和SharedPreferences都为空时，自动生成默认设备名并保存
- Flutter端_loadAllSettings优先从原生端获取设备名，失败时才回退到SharedPreferences

---

### v1.5.3 - 2026-06-30

**下载进度条修复**
- 修复下载更新时进度条一直显示0%的问题
- 根本原因：showDialog 中的 StatefulBuilder 有独立状态管理，外部 setState 不会触发 dialog 重建
- 解决方案：改用 ValueNotifier + ValueListenableBuilder 驱动 dialog 内进度条更新
- 进度更新不再依赖 widget 树，ValueNotifier 直接通知 ValueListenableBuilder 刷新UI

---

### v1.5.2 - 2026-06-30

**设备名持久化修复**
- 修复软件更新后设备名恢复默认值的问题
- 设备名采用文件持久化方案：保存到应用私有目录的 device_name.txt
- 双重保障：同时保存到 SharedPreferences 和文件，优先从文件读取
- 覆盖所有读取场景：NotificationMonitorService、MainActivity、SmsReceiver、PhoneCallReceiver
- 文件存储在 Context.filesDir 下，应用更新时数据保留不丢失

---

### v1.5.1 - 2026-06-30

**热更新包整理优化 + 下载进度修复**
- 修复下载更新进度条一直显示0%的问题：优先使用 version.json/hotfix.json 中已知的文件大小，不再依赖 CDN 的 content-length 头
- 移除不可靠的 HTTP HEAD 请求获取文件大小方式，改为直接使用服务器返回的 fileSize 字段
- 热更新包整理优化：app_names.json 按应用类别重新组织，去除重复项，结构清晰
- 热更新包整理优化：notification_types.json 按分类维度重新组织，去除重复规则
- 热更新包 v3 发布：应用名称映射覆盖 400+ 款主流应用，按厂商/类别分组
- 热更新包 v3 发布：通知类型分类规则覆盖 200+ 关键词，按功能维度分组
- 版本号命名规则调整：采用三段式 A.B.C，小版本更新 C 递增（0-99），大版本更新 B+1

---

### v1.5.0 - 2026-06-29

**热更新功能正式接入**
- 应用名称映射表支持热更新：新增应用无需发版，通过热更新包即可识别
- 通知类型识别规则支持热更新：灵活调整通知分类规则
- 热更新优先级：热更新配置 > 内置配置，热更新配置生效后立即覆盖
- 热更新应用后无需重启，通过广播通知服务立即重载配置
- 热更新包结构：`app_names.json`（应用名称映射）+ `notification_types.json`（通知类型映射）
- 热更新包存放路径：`https://cdn2.fnthink.top/app/notice/hot/notice1.x.x.zip`

---

### v1.4.6 - 2026-06-29

**CDN 下载优化：更新包和热重载包迁移至 CDN**
- APK 安装包下载地址迁移至 CDN：`https://cdn2.fnthink.top/app/notice/update/notice1.x.x.apk`
- 热重载包下载地址迁移至 CDN：`https://cdn2.fnthink.top/app/notice/hot/notice1.x.x.zip`
- 版本检查接口返回完整 CDN 下载地址，客户端直接使用
- 客户端下载逻辑已支持绝对 URL，自动识别 CDN 地址并正确下载
- 服务器端 version.json 和 hotfix.json 配置已更新为 CDN 地址

---

### v1.4.5 - 2026-06-29

**设备名持久化优化：更新后不再恢复默认**
- 修复应用更新后设备名恢复默认的问题
- 设备名由 Android 端统一管理持久化，Flutter 端启动时从原生端同步
- 优先级：Android 原生存储 > Flutter 本地存储 > 系统默认值
- 通知监听服务启动时，如无保存的设备名则自动用品牌+型号生成默认值并保存
- 确保用户修改的设备名在版本更新后完整继承

---

### v1.4.4 - 2026-06-29

**魅族推送精准识别 + 服务稳定性修复**
- 修复魅族推送应用名称识别：从 channelId (`mzpush_oripacname_xxx`) 提取原始包名，精准识别小红书等应用
- 优化小米/华为推送 channelId 解析逻辑，通用包名提取策略
- 修复 NotificationMonitorService 前台服务崩溃问题
- 新增通知通道创建（Android 8.0+），确保前台服务正常运行
- onListenerConnected 中再次调用 startForeground，提高服务稳定性
- 关键日志级别从 DEBUG 提升到 INFO，确保魅族等国产手机可见
- 新增"收到通知"日志，包含 packageName、channelId、notificationId

---

### v1.4.3 - 2026-06-29

**国产厂商推送适配优化**
- 新增厂商推送服务识别：小米推送、华为推送、魅族推送、OPPO推送、vivo推送等
- 新增 `resolveRealAppName` 函数：针对厂商推送通知，多策略提取真实应用名称
- 策略1：从厂商推送自定义 extras 字段提取应用名/包名
- 策略2：从通知 subText 提取应用名称
- 策略3：从通知 channelId 解析应用包名
- 策略4：从标题括号/冒号前缀提取应用名（如【小红书】xxx）
- 策略5：兜底使用标题前几个字作为应用名
- 优化 `getAppNameByPackage`：优先使用系统应用标签，可疑时才用友好名称覆盖
- 重写 `getFriendlyAppName`：全部 startsWith 精确匹配，避免宽泛匹配误判
- 优化通知类型检测：支持通过应用名称识别类型（适配厂商推送场景）
- 新增详细调试日志：厂商推送通知打印所有 extras 字段，方便排查
- 历史记录详情弹窗：标题显示应用名称，iOS 风格优化

---

### v1.4.2 - 2026-06-29

**通知应用名称显示优化**
- 修复第三方应用通知显示"系统推送服务"的问题，正确显示应用名称（如小红书、拼多多、快手等）
- 历史记录列表优化：非内置类型通知显示应用名称首字而非"通"字，更易识别
- 应用名称获取逻辑优化：优先使用友好名称映射，确保显示简洁清晰的中文名
- 新增 30+ 常用应用友好名称映射：拼多多、高德地图、百度地图、各类输入法等
- 推送服务类通知归类为 system 类型，避免与正常应用通知混淆
- 应用图标颜色根据应用名称生成稳定配色，同一应用始终显示同色

---

### v1.4.1 - 2026-06-29

**子页面与弹窗 iOS 风格统一**
- 应用筛选页重构：iOS 分组列表样式，搜索栏采用 iOS 系统灰色背景，全选/清空按钮胶囊化
- 关键词过滤页重构：Tab 栏 iOS 风格配色，黑白名单图标彩色圆角背景，删除按钮红色胶囊
- 历史记录页优化：列表项统一 iOS 分组圆角，分隔线缩进对齐图标右侧
- 设备名称弹窗：输入框 iOS 圆角边框样式，按钮文字蓝色系统色
- 关于弹窗：顶部应用图标圆角展示，版本号灰色小字，布局居中对齐
- 更新弹窗：重要更新红色标签，更新内容灰色背景卡片，按钮横向三列排列
- 下载进度弹窗：进度条圆角蓝色，百分比大字显示，取消按钮红色
- 统一所有子页面背景色 #F2F2F7，导航栏透明无底色
- 修复 Switch 组件 deprecated API 警告

---

### v1.4.0 - 2026-06-28

**UI 全面重构，iOS 风格**
- 整体视觉风格全面升级为 iOS 系统软件风格
- 采用 iOS 系统色板：主色 #007AFF、绿色 #34C759、橙色 #FF9500、红色 #FF3B30
- 背景色采用 iOS 标准浅灰 #F2F2F7，卡片纯白无阴影
- 所有页面采用 iOS 分组列表样式（Inset Grouped）
- 分组标题使用小号灰色文字，统一间距规范

**通知页重构**
- 页面标题简化为「通知」，居中显示
- 运行状态、权限设置、服务控制、支持类型、历史记录五大分组
- 权限项改为带彩色图标的列表项，状态显示在副标题
- 服务控制按钮改为居中蓝色文字样式，更简洁
- 支持的通知类型采用圆角胶囊标签，iOS 系统配色

**电量页重构**
- 页面标题简化为「电量」，居中显示
- 顶部大字号电量数字展示，iOS 细体字重
- 充电状态文字使用灰色次级文字样式
- 提醒设置和通知类型分为两个独立分组
- 开关采用 iOS 风格绿色滑块，带彩色图标背景

**更多页重构**
- 推送设置、设备、关于与更新三大分组
- 所有菜单项统一采用彩色圆角图标 + 标题 + 副标题 + 右箭头样式
- 检查更新项右侧显示加载状态，无多余按钮
- 页面底部居中显示版本号，灰色小字

**Webhook 配置页重构**
- 保存按钮移到导航栏右侧，iOS 标准操作位置
- 通道列表采用分组卡片样式，每个通道独立区块
- 添加通道按钮单独一个卡片，居中蓝色文字
- URL 输入框改为 iOS 样式圆角边框
- 测试按钮改为文字按钮，更轻盈
- 类型提示卡片去掉边框，纯浅色背景
- 底部说明采用圆点列表样式

**底部导航栏**
- 背景改为半透明白色，iOS 磨砂效果风格
- 选中色 #007AFF，未选中色 #8E8E93
- 取消 Material 3 巨型指示器，更精致

---

### v1.3.0 - 2026-06-28

**界面大重构**
- 底部导航第三页由「设置」改名为「更多」，页面结构全面优化
- 「更多」页采用分组列表式布局，分为三大模块：
  - **推送设置**：Webhook 推送通道、应用筛选、关键词过滤
  - **设备**：设备名称
  - **关于与更新**：检查更新、关于
- 每个菜单项添加彩色图标，视觉更清晰，功能一目了然
- 页面底部显示当前版本号，方便查看

**Webhook 配置独立化**
- Webhook 推送通道从设置页抽离为独立二级页面
- 新页面标题「Webhook 推送通道」，返回即可回到更多页
- 页面底部新增说明卡片，列出使用要点：
  - 支持同时配置多个 Webhook 通道，每个通道可独立开关
  - 自动识别企业微信、钉钉、飞书等平台格式
  - 新添加的通道默认启用
- 保存逻辑优化：保存后直接返回上一页并提示结果

**交互体验优化**
- 更多页 Webhook 菜单项副标题显示「已配置 N 个通道 · 启用 M 个」，状态一目了然
- 应用筛选和关键词过滤也有对应的状态副标题
- 检查更新按钮副标题显示「点击检查新版本」或「正在检查...」
- 整体界面更有层次感，信息分组清晰，操作路径明确

---

### v1.2.4 - 2026-06-28

**UI 优化**
- 更新对话框增加滚动视图：更新内容较多时可上下滚动查看，避免内容超出屏幕
- 删除设置页"检查更新"按钮下方的内容版本显示，界面更简洁

---

### v1.2.3 - 2026-06-28

**Bug 修复**
- 修复更新服务器地址被旧版本数据覆盖的问题：之前版本如果用户设置过错误的服务器地址（如 shsj.dd），新版本会继续使用旧地址导致连接失败
- 服务器地址改为代码内硬编码常量 `https://notice.fnthink.top`，不再从 SharedPreferences 读取，彻底避免旧数据残留问题
- 修复检查更新失败时的错误提示：现在显示具体错误原因（如 DNS 解析失败、连接超时等），方便问题排查

**体验优化**
- 手动检查更新增加 500ms 最小等待时间，确保用户能看到加载状态，避免因请求太快导致用户感觉没反应
- 网络请求超时时间从 10 秒增加到 15 秒，适配网络较慢的情况
- 增加详细的 Debug 日志：请求地址、响应状态码、响应数据等都会输出到控制台

**代码优化**
- 删除不再使用的 `setServerUrl` 方法和 `_prefsKeyUpdateUrl` 常量
- 删除 SettingsPage 中 `updateServerUrl`、`onSaveUpdateServerUrl` 等冗余参数
- 删除 `_updateServerUrl` 状态变量和 `_saveUpdateServerUrl` 方法
- 简化空值判断逻辑，代码更简洁

---

### v1.2.2 - 2026-06-28

**Bug 修复**
- 修复关于页版本号硬编码问题：改为动态读取，和 pubspec.yaml 版本号保持一致
- 修复检查更新逻辑错误：之前网络连接失败时会错误显示"当前已是最新版本"，现在正确显示"检查更新失败"提示
- 修复服务器地址为空字符串时默认值不生效的 bug：旧版本如果用户清空过服务器地址，新版本会自动恢复为默认地址 https://notice.fnthink.top

**体验优化**
- 优化检查更新交互：点击"检查更新"后至少显示 500ms 加载状态，避免因请求太快导致用户感觉没反应
- 设置页更新模块简化：只保留检查更新按钮，移除服务器地址和自动更新开关（自动更新默认开启）
- 更新对话框优化：重要更新增加红色"重要"标签和提示文字，视觉上更明显

**服务端优化**
- version.json 新增 `appName` 字段，软件命名规则为 `notice` + 版本号（如 `notice1.2.2`）
- APK 下载文件名统一为 `notice` + 版本号格式
- 服务端接口返回数据增加 `appName` 字段
- 修改 version.json 后无需重启服务，立即生效（每次请求重新读取文件）

---

### v1.2.1 - 2026-06-28

**通知体验优化**
- 推送前缀使用具体应用名：企业微信、钉钉、飞书推送时，消息前缀显示具体应用名称（如"【小红书】"、"【知乎】"），不再使用笼统的"【系统通知】"或"【通知】"
- 新增 40+ 常见应用包名映射：小红书、知乎、美团、大众点评、饿了么、滴滴出行、优酷、爱奇艺、腾讯视频、芒果TV、网易邮箱、QQ邮箱、Gmail、Chrome 浏览器、各种系统应用等
- 优化应用名获取逻辑：优先从系统 PackageManager 获取真实应用名，获取失败时才使用友好名称映射
- 修复通知类型误判：`detectNotificationType` 中 `system` 类型判断更精准，只有真正的系统界面和设置应用才归类为 system，第三方应用不会被误判
- 优化电池通知类型：充电提醒、电量充满、低电量提醒使用更友好的前缀文字

**附带的小版本更新汇总（v1.2.0.1 ~ v1.2.0.3）**
- v1.2.0.1：代码质量优化，修复 12 个警告和代码规范问题
- v1.2.0.2：服务端配置调整，默认端口 3456，默认服务器地址 https://notice.fnthink.top，重写部署文档
- v1.2.0.3：更新体验优化，设置页简化为单按钮，热更新自动下载应用，版本更新弹窗区分一般/重要更新

---

### v1.2.0 - 2026-06-28

**新功能**
- 新增在线更新功能：支持启动自动检测、每天定时检测更新
- 新增强制更新机制：服务端可配置强制更新，用户不更新无法继续使用
- 新增 APK 在线下载与安装：点击更新后自动下载并触发安装
- 新增热更新功能：支持下载热更新资源包，无需重新安装 APK
- 新增内容版本号：独立于 APK 版本号，用于热更新版本对比，避免热更新后重复触发在线更新
- 设置页新增更新模块：检查更新按钮、自动更新开关、更新服务器地址配置

**服务端**
- 新增 Node.js + Express 更新服务，位于 `server/` 目录
- 提供版本检查、热更新检查、文件下载接口
- 提供版本配置管理接口（获取/更新版本配置）
- 支持强制更新、最低版本限制等配置
- 详细部署说明见 `server/README.md`

---

### v1.2.0.1 - 2026-06-28

**代码质量优化**
- 修复 `_isDownloading` 字段未使用警告：在下载开始前增加重复点击判断，防止重复触发下载
- 修复 `curly_braces_in_flow_control_structures` 代码规范问题：if 语句增加大括号包裹
- 修复 `_setNativeWebhookUrls` 未使用警告：将直接调用改为复用封装方法，提高代码可维护性
- 修复 8 处 `use_build_context_synchronously` 警告：所有异步回调中使用 `BuildContext` 前增加 `mounted` 守卫，避免页面销毁后访问 context 导致崩溃
- 移除 `update_manager.dart` 中未使用的 `shouldAutoCheck()` 方法和 `prefs` 变量
- `flutter analyze` 检查结果：No issues found

---

### v1.2.0.2 - 2026-06-28

**服务端配置调整**
- 服务端默认端口从 3000 改为 3456
- 客户端默认更新服务器地址设为 `https://notice.fnthink.top`
- 重写 `server/README.md` 部署文档：
  - 新增「快速开始」新手向教程，6 步从环境准备到发布第一个更新
  - 新增 4 种生产环境部署方案：PM2 守护进程、Nginx 反向代理 + HTTPS、Docker 部署、Systemd 系统服务
  - 新增安全加固建议、常见问题 FAQ、客户端配置说明
  - 文档结构分层设计，兼顾新手快速上手和专业运维需求

---

### v1.2.0.3 - 2026-06-28

**更新体验优化**
- 设置页更新模块简化：只保留「检查更新」按钮，移除服务器地址显示和自动更新开关
- 热更新逻辑优化：检测到热更新后自动下载并应用，不弹窗询问，通过 SnackBar 提示进度和结果
- 版本更新弹窗优化：
  - 一般更新：标题「发现新版本」，提供「忽略此版本 / 稍后再说 / 立即更新」三个按钮
  - 重要更新（强制更新）：标题增加红色「重要」标签，底部增加红色提示文字，仅提供「立即更新」按钮，对话框不可关闭
- 统一更新检测逻辑：自动更新和手动点击更新共用 `_performUpdateCheck()` 方法，逻辑完全一致，仅触发时机不同
  - 自动更新触发节点：APP 启动时、每天定时（24小时间隔）
  - 手动更新：用户点击「检查更新」按钮，强制刷新不受间隔限制
- 自动更新策略：非强制更新且用户已忽略该版本时，不弹窗打扰用户

---

### v1.1.7 - 2026-06-28

**功能优化**
- 修复电量检测页面更新不及时问题：添加 30 秒定时刷新机制，同时支持原生端电量变化实时回调通知 Flutter 端更新 UI
- 电量设置实时同步到原生端：修改电量通知开关时通过 MethodChannel 立即同步到原生 SharedPreferences，确保后台服务使用最新配置
- 优化电量通知后台推送：`NotificationMonitorService` 电量变化时发送广播，`MainActivity` 接收后转发给 Flutter 端，实现前后端电量状态同步

---

### v1.1.6 - 2026-06-28

**安全修复**
- 修复锁屏通知点击绕过锁屏的安全漏洞：移除 MainActivity 的 `showWhenLocked` 和 `turnScreenOn` 属性，确保在锁屏状态下点击通知必须先解锁才能进入应用

---

### v1.1.5 - 2026-06-29

**Bug 修复**
- 修复清除后台后 webhook 地址显示丢失问题：`SettingsPage` 添加 `didUpdateWidget` 回调，当父 widget 传递新的 webhook 数据时同步更新输入框控制器，解决 `IndexStack` 页面状态保持导致 UI 不刷新的问题
- 增强数据一致性：从原生端加载 webhook 配置成功后，同步更新 Flutter 本地 SharedPreferences，确保双端数据一致

---

### v1.1.4 - 2026-06-29

**Bug 修复**
- 修复锁屏通知点击绕过锁屏的安全问题：添加 KeyguardManager 锁屏状态校验
- 修复 webhook 地址持久化问题：原生端 `setWebhookChannels` 使用 `commit()` 同步写入磁盘，确保数据立即落盘
- Flutter 端改为优先从原生端读取 webhook 配置，通过 MethodChannel 保证数据一致性

---

### v1.1.3 - 2026-06-28

**Bug 修复**
- 修复 webhook 地址概率丢失问题：原生服务启动时优先读取新格式 `flutter.webhook_channels`，确保与 Flutter 端数据一致
- 修复锁屏通知双击打开双实例问题：launchMode 改为 `singleTask`，移除 `taskAffinity=""`，确保全局只有一个 Activity 实例

---

### v1.1.2 - 2026-06-28

**新增功能**
- Webhook 通道支持启用/禁用开关：每个通道可单独控制是否启用，新增通道默认启用
- 设置数据持久化优化：Webhook 配置从旧版本自动迁移并保留到新版本

**Bug 修复**
- 修复新版本安装后旧版本后台任务残留问题：启动时自动停止旧服务

**其他改进**
- Webhook 数据结构从纯 URL 列表升级为包含 URL 和启用状态的对象列表

---

### v1.1.1 - 2026-06-26

**新增功能**
- 应用筛选：读取已安装应用列表，用户可选择需要推送通知的应用
- 关键词黑白名单：
  - 白名单：通知内容匹配关键词则强制推送（优先级最高）
  - 黑名单：通知内容匹配关键词则不推送
- 设置页新增"应用筛选"和"关键词过滤"入口

**Bug 修复**
- 持续通知（Ongoing）去重：同一条正在进行中的通知只推送第一次
- 过滤本应用自己的通知：前台服务保活通知不再被推送

**过滤优先级**
白名单关键词 → 包名白名单 → 黑名单关键词

---

### v1.1.0 - 2026-06-26

**Bug 修复**
- 修复启动灰屏问题：`late final` 变量在 `build()` 中重复赋值导致崩溃

---

### v1.0.9 - 2026-06-26

**新增功能**
- 替换应用图标为蓝色铃铛造型
- 支持 Adaptive Icon（自适应图标）

---

### v1.0.8 - 2026-06-26

**新增功能**
- 底部导航栏三页面：
  - 通知页：权限设置、服务控制、历史记录入口
  - 电量页：电量状态显示、四种提醒开关
  - 设置页：Webhook 配置、设备名称、关于
- 电量通知功能：
  - 开始充电提醒
  - 电量充满提醒
  - 低于 30% 提醒
  - 低于 20% 提醒
- 通知应用名称动态获取（使用 PackageManager）

---

### v1.0.7 - 2026-06-26

**新增功能**
- Webhook 多通道配置，支持同时推送多个地址
- 每个通道独立测试按钮
- 自动识别 Webhook 类型（企业微信/钉钉/飞书/通用）

**其他改动**
- 关闭 R8 代码混淆

---

### v1.0.6 - 2026-06-26

**新增功能**
- 历史通知记录持久化（原生 SharedPreferences）
- App 启动时从原生端同步历史记录

**其他改动**
- 开启 R8 代码混淆和资源压缩

---

### v1.0.5 - 2026-06-26

**优化改进**
- 通知应用名称改用 PackageManager 动态获取（适配所有应用）
- 保留硬编码映射作为 fallback

---

### v1.0.4 - 2026-06-26

**新增功能**
- Webhook 推送统一改为 text 文本格式（兼容企业微信等平台）
- 新增历史推送记录页面
  - JSON 格式本地存储
  - 支持搜索和详情查看
  - 支持导出到应用目录
  - 支持清空记录
  - 最多保存 500 条

---

### v1.0.3 及更早

- 基础通知监听功能
- Webhook 推送功能
- 微信/QQ/短信/来电等类型识别
- 前台服务保活
- 小米/魅族特殊权限适配
- 设备名称自定义
- 开机自启动
