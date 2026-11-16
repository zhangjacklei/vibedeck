# vibedeck · Apple TV 遥控器（A2540）→ Mac 控制台

应用名：**vibedeck**（产物 `vibedeck.app`，可执行文件 `vibedeck`）
来源：[lauschue/Remotastic](https://github.com/lauschue/Remotastic)（MIT）。把 Apple TV 遥控器
变成 Mac 的触控板 + 可编程快捷键面板 + 语音输入设备。

遥控器按真机产品图**逐项像素测量**后矢量绘制：
机身 369×1404 px（宽高比 3.805）、圆盘直径 0.875×机身宽且中心在 0.211 高度、
返回/播放/静音直径 0.090×机身高（x=0.285，y=0.380/0.486/0.593）、
TV 0.347×0.090（x=0.701，**圆形**，与其他按键同直径）、音量 0.336×0.198（中心 0.701,0.540）、
电源 0.205 直径（0.804,0.050）、麦克风孔 (0.500,0.050)、
侧边语音键位于右边缘、中心高度 0.211、高度 0.108×机身高。

## 这一版新增了什么

### 1. 可视化控制台（CleanMyMac X 风格）
- 侧边栏四个页面：**概览 / 按键映射 / 语音输入 / 关于**
- 遥控器**按真机照片重绘**：银色铝机身、黑色大圆盘（四向小圆点 + 内圈）、黑色圆形返回/播放/静音键、
  TV 圆角方块、音量胶囊摇杆、右上电源键与顶部麦克风孔
- 直接**点图上的按键**（电源、静音、返回、TV、四向圆环、中心点按、播放/暂停、音量、语音键）
  右侧立即出现该键的功能选择，不再需要在菜单里翻二级目录
- 卡片式布局、柔和阴影、统一强调色；选中按键在图上高亮描边

### 2. 按键映射升级
原来只有 13 个固定动作，现在支持：
- **任意键盘快捷键**（`cmd+shift+p`、`ctrl+c`、`return`、`escape`…）
- **输入文本**、**运行 shell 命令**
- **打开 App**：不再手填，点「选择 App…」弹出系统应用列表（自动扫描 /Applications、/System/Applications、
  工具目录与 ~/Applications，共 120+ 个），支持搜索、显示图标，写入 bundle id
- 媒体键、鼠标左/右键、滚动、调度中心、**按住语音输入**
- 默认值面向 vibe coding：播放/暂停→回车、返回→Esc、TV→调度中心、语音键→按住说话
- 旧版菜单里保存的映射会自动迁移，不会丢

### 3. 语音输入（麦克风可选）
- 遥控器 **Siri 键按住说话 → 松手自动粘贴**到当前光标处（可在语音页关掉自动粘贴）
- 识别用系统 `SFSpeechRecognizer`（中文普通话/台湾、英文、日文；优先离线识别）
- 屏幕底部浮出实时转写条，显示音量与已识别文字
- 麦克风在「语音输入」页可选：**跟随系统默认**，或任意已接入的输入设备
  （若遥控器麦克风没有出现在列表里，说明 macOS 未把它暴露为输入设备，选 Mac 麦克风即可）

### 4. 工程侧
- 固定本地自签身份 `A2540 Vibe Deck Dev` 签名：重新编译后系统授权依然有效
- 启动时自动登记 TCC（辅助功能 / 输入监控）并给出授权引导
- 日志统一写 `/tmp/remotastic.log`（权限状态、按键命中、未知键码、识别结果）
- 未知 HID 按键会记录一次 `❓ 未知按键 page=0x..:0x...`，便于补全键码

## 身份与授权（重要）

- Bundle ID：`dev.vibedeck.a2540`，显示名 `vibedeck`，签名身份 `A2540 Vibe Deck Dev`（本地自签）。
- **不要在系统设置里勾选旧条目**：历史版本叫 `A2540 Vibe Deck` / `Remotastic`（bundle id `dev.vibedeck.a2540` 之外），
  勾了它们对当前进程无效 —— 这正是"设置里开着但 App 说未授权"的根因。
- 首次运行会在两个弹窗里请求授权：**输入监控**（点「允许」）、**辅助功能**（点「打开系统设置」并勾选 vibedeck）。
  授权后**切回 App 窗口即自动重新接管遥控器**，不需要重启。
- 自检：`./vibedeck.app/Contents/MacOS/vibedeck --selftest`（24 项，覆盖键码/映射/快捷键/应用清单/设备/持久化）。

## 语音浮窗（HUD）与深色模式

- 浮窗：右上角 320×56 小条，**永不成为 key/main 窗口**（不抢输入焦点）、鼠标事件穿透、
  识别结束自动淡出（0.4s 看门狗兜底），可在「语音输入」页用「显示实时转写浮窗」关闭。
- 界面固定浅色：`NSApp.appearance = .aqua` + 根视图 `.environment(\.colorScheme, .light)`，
  避免系统深色模式下出现"白卡片 + 白字"。
- 语音识别仅在 `.app` 内启动（从 shell 直接跑二进制时 TCC 会 abort，已加保护）。

## 构建 / 运行

```bash
cd /path/to/vibedeck
./build.sh              # swiftc 编译（macOS 12+）→ 产物 ./vibedeck
./create_app_bundle.sh  # 打包 vibedeck.app + 固定身份签名
open vibedeck.app       # 菜单栏出现遥控器图标，同时弹出控制台
```

调试参数：`open vibedeck.app --args --page voice`（可选 overview / buttons / voice / about），
`--voice-test 6` 做无界面语音自检。

命令行自检：

```bash
./Remotastic.app/Contents/MacOS/Remotastic --voice-test 6   # 语音链路自检（看 /tmp/remotastic.log）
```

## 使用

| 操作 | 效果 |
|---|---|
| 触控板按住滑动 | 移动鼠标指针 |
| 触控板轻点 | 左键单击 |
| 按住 0.25s 后滑动 | 拖拽 |
| 边缘旋转 / 双指 | 滚动 |
| 播放/暂停 | 回车（提交 prompt） |
| 返回 ‹ | Esc（中断） |
| TV | 调度中心 |
| 语音键按住说话 | 实时转写，松手粘贴 |

菜单栏图标 → **打开设置面板…**（⌘,）可随时回到控制台。

## 已知限制

- 触控板使用私有 `MultitouchSupport` 框架，macOS 大版本升级后可能失效
- 电源键由 `loginwindow` 先接管，应用层收不到（界面中仅作展示）
- 圆环四向（0x0C/0x42–0x45）的方向对应基于本机实测，若上下左右颠倒可在
  `RemoteInputHandler.identifyButton` 里对调
- 媒体键仍可能同时触发系统行为（设备以独占方式打开，多数情况已被拦截）

## 选型记录

| 项目 | 许可 | A2540(0x0314) | 说明 |
|---|---|---|---|
| **Remotastic** | MIT | 需 1 行补丁（已打） | 代码量小、纯 `swiftc` 构建、触控板能力完整 |
| SiriRemoteForge | GPLv3 | 仅 3 代(0x0315) | 功能最全但设备不匹配 |
| HyperVibe | MIT | 仅验证 1 代(0x266) | 面向 Claude Code 的单键工作流 |
| RemotePilot | 专有 | 支持 | 闭源，只有二进制，无法本地改 |

## v1.2 · 版本可核对 + 窗口显示修复（2026-11-13 22:34）

问题：用户截图出现白色大浮层、文字极淡，且无法判断跑的是不是最新构建。

排查结论：
- `CFBundleVersion` 恒为 `1.0`、侧边栏写死 "v1.1"，重建 bundle 后界面上完全看不出版本差异；
  `pgrep`/`lsof` 证实旧进程一直在跑。
- 白色大浮层是旧版实时转写 HUD。新版 HUD 已是右上角 320×64 深色小条，本次进一步把
  `showHUD` 默认改为 `false`（换 key `voice.showHUD.v2`，避免旧偏好把浮窗带回来）。
- `LSUIElement`(.accessory) 应用 `NSApp.activate` 不生效，设置窗口被其它 App 完整盖住，
  看起来像"没启动 / 还是旧界面"。`show()` 现在临时 `window.level = .floating` +
  `orderFrontRegardless()`，1s 后恢复 `.normal`。

改动：
- 新增 `BuildInfo.swift`；`create_app_bundle.sh` 生成 `v1.2 (build YYYYMMDD-HHMMSS)`，
  写入 `CFBundleVersion` 与 `Contents/Resources/BuildStamp.txt`。
- 侧边栏 / 菜单栏 / 关于页 / 启动日志 / `--diag` 显示同一个 build 号；`--diag` 从 CLI
  运行时会提示权限结果属于「终端」身份，不代表 `.app`。
- 主窗口、App 选择 popover 固定浅色，HUD 固定深色；删除启动时重复的
  `CGRequestListenEventAccess()`（只请求一次），概览页补充 bundle id 与"关→开刷新授权"指引。

验证：`--selftest` 24 项 ALL PASS；`codesign --verify --deep --strict` 通过；重启后日志
`📦 vibedeck v1.2 · 20261113-223414`，截图 `screenshots/version-fixed.png` 显示窗口前置、
文字清晰、侧边栏版本号可见、遥控器 `A1B2C3D4E5F6` 已连接。

遗留：GUI 进程 `CGPreflightListenEventAccess()` 仍为 false，而 app 包内 CLI 为 true
（TCC 按负责进程判定，shell 读到的是终端的授权）。遥控器 HID 路径已连接并接管按键。
如需统一：系统设置 ▸ 输入监控里把 vibedeck 开关关→开一次，必要时移除后重新添加。

## 快捷键：任意按键 / 组合 / 录制（2026-11-13 23:00）

用户问「只能选预设那几个快捷键吗」。原实现里输入框本来就是自由文本，那一排只是
常用预设一键填入，但界面没说清楚，且键名写法有限。本次做成真正可自定义：

- `KeySender` 新增 `normalize()` / `validate()` / `nameByCode`，支持：
  - 单键 `j`、`esc`、`f5`、`space`、`up`、`→`
  - 任意组合 `cmd+shift+p`、`ctrl+alt+right`、`fn+f5`
  - 符号写法 `⌘⇧P`、`⌃C`、`⌥⎋`
  - 别名 `command/control/option/alt/enter/del/pgup/arrowleft/plus` 等
  - 多组连续动作 `cmd+c, cmd+v`（也支持 `;`、中文逗号、`|`）
  - 注意 `→` 是右方向键，**不能**当多组分隔符
- `send()` 现在按组依次发送（组间 70ms），无效键名会写日志并跳过，不再默默失败。
- 新增 `ShortcutRecorder.swift`：点「录制按键」后直接按实体键盘，从 `NSEvent.keyCode`
  反查键名 + `modifierFlags` 组合出字符串回填。只监听本 App 的本地事件，不需要输入监控
  授权；单独 Esc 也照常录制，取消用界面按钮。被系统占用的全局快捷键（⌘Tab / ⌘Space）
  录不到，属系统限制。
- 界面：录制按钮、实时合法性校验（未知键名橙色提示 / 「识别为 ⌘⇧P」绿色预览）、
  用法说明、「常用」标签明确预设定位；`--select <button>` 启动参数可直接打开某个键。

验证：`--selftest` 从 24 项扩到 **36 项 ALL PASS**（含符号写法、三修饰键、未知键拦截、
方向键不冲突、录制 ⌘⇧P 与单独 Esc）。

## 省电功能实测修复（2026-11-15）

用户反馈「菜单栏暂停接管 / 一键断开遥控器 / 闲置自动休眠」实测不可用。根因四条：

1. **一键断开走错 API**：A2540 是 BLE HID，`system_profiler` 的 `device_connected` 能看到
   `A1B2C3D4E5F6` (Service: BLE)，但 `IOBluetoothDevice.pairedDevices()` /
   `configuredDevices` / `connectedDevices` 都**不含**它；按地址 `deviceWithAddressString:`
   构造的对象 `isConnected=false`。旧代码只在 pairedDevices 里找，永远返回「没有找到已配对
   的遥控器」。→ 改为 `connectedRemotes()` 读 system_profiler JSON + 多入口枚举 +
   `Result.status` 如实区分 disconnected / notFound / unsupported / failed。
   **结论：macOS 不向第三方 App 暴露可断开的系统级 BLE HID 连接**。按钮改名为
   「睡前一键释放」，作用是立即释放资源让遥控器自行深睡；彻底断开仍需系统设置手动操作。
2. **60 秒唤醒抑制**：`disconnectRemote()` 固定设 `arrivalWakeSuppressedUntil = now+60`，
   把用户按任意键后设备重新枚举一并挡掉 → 暂停后按不动。改为仅在精确断开**成功**时
   抑制 3 秒；`noteActivity` 无条件恢复。
3. **RemoteDetector 计数错误**：用 `vendor:product` 作唯一 key，但一台 A2540 有 7 个
   HID 接口共享该 key；任一接口移除就把 count 归零并回调 `nil`，清空刚恢复的
   `RemoteInputHandler.devices`。→ 改为按 `ObjectIdentifier` 逐接口跟踪，全部移除才回调 nil。
4. **自检没覆盖硬件接线**：旧自检只测纯函数状态机，`releaseHardware/restoreHardware`
   为空也能全过。→ 注入 mock 回调断言钩子被调用；新增 `--power-test` 在真实 app 进程里
   检查硬件状态字符串。

其它：媒体键事件作为第三条唤醒路径；`start()` 记录初始活动时间；设置页与菜单栏新增
「立即测试休眠」，不必等 10 分钟；`--diag` 输出省电状态与 BLE HID 判定。

验证：编译 0 warning、`--selftest` **57 项 ALL PASS**、`--power-test` 真实进程
`POWER-TEST PASS`（暂停后「HID 被动 / 触控板已停」→ 恢复后「HID 独占（7 接口）/
触控板运行中」）、`codesign --verify --deep --strict` 通过；截图
`screenshots/power-fixed.png`。

已知限制：`--power-test` 无法模拟物理按键唤醒（需真人按遥控器）；BLE HID 精确断开属
平台限制，非本项目可解决。

## v1.2 · 20261116-165503 — 两页连接状态统一

用户反馈「省电与休眠页的遥控器连接状态与概览页不一致」。确认属实：概览页主卡片读
`ConnectionMonitor.isConnected` 显示「遥控器已连接/等待遥控器连接」，省电页主卡片只读
`PowerManager.isSuspended` 显示「正在接管遥控器」，底部又自行拼接状态字符串；侧边栏直接读
单例但无 `@ObservedObject` 订阅。同一台遥控器在两页被描述成不同状态。

修复：连接状态收敛到 `ConnectionMonitor` 单一真相源，新增共用计算属性 `statusText` /
`statusDetail` / `statusSymbol` / `connectionLine`；概览页、省电页主卡片和侧边栏全部改用这组
属性。`update(connected:true, name:nil)` 时回退为「Siri Remote」，不再残留「等待遥控器…」；
省电页副标题只描述接管/省电状态，未连接时复用 `monitor.statusDetail` 保证与概览页逐字同源。

自检：新增 7 项连接状态一致性断言（未连接/已连接/无名设备/图标共用），`--selftest`
**64 项 ALL PASS**；编译 0 warning，`codesign --verify --deep --strict` 通过；截图
`screenshots/overview-consistent.png` 与 `screenshots/power-consistent.png` 两页主标题均为
「等待遥控器连接」。

## v1.2 · 20261116-172324 — 按测试报告做开发侧优化

依据 `TEST_REPORT.md` 的 4 项待改进点逐项处理：

1. **CLI 语音测试崩溃（报告 4.3）**：`--voice-test` 在任何语音对象初始化前检查
   `AppIdentity.isAppBundle`，裸二进制直接打印原因并 `exit(2)`；增加 20 秒授权超时兜底。
   实测 `exit=2`、无 SIGABRT。
2. **权限状态显示（报告 4.1 / 4.2、NOTES 遗留项）**：
   - 新增 `PermissionCenter.swift` 作为唯一权限真相源。输入监控同时做
     `CGPreflightListenEventAccess()` 与真实 listen-only tap 探测；任一可用即视为已授权，
     并在诊断里保留 `preflight` / `监听通道` 原始值。
   - 本进程探测不到时不再武断显示「未授权」，改为三态标签「未确认」+ 明确下一步；
     GUI 与 `--diag` 显示同一份文案与原始探测值。
   - 语音授权拆成「麦克风」「语音识别」两项独立状态 chip，各自跳对应系统设置页；
     概览页副文案也显示缺哪一项。`重新检测` 一次刷新权限/HID/蓝牙/语音。
   - TCC 状态在同一进程内缓存，只有用户主动请求授权或点重新检测才失效重读。
     修复了「窗口出现时连续读 TCC → SIGABRT（崩溃报告 kTCCServiceSpeechRecognition）」。
3. **未连接可诊断性（报告第 5 节）**：`ConnectionMonitor` 新增蓝牙可见名探测与
   `detail(connected:deviceName:bluetoothNames:)` 纯函数；未连接但蓝牙可见时提示
   「系统蓝牙可见 xxx，但 HID 尚未接管：请按遥控器任意键唤醒」，不再只说「检查系统蓝牙」。
4. **平台限制保持如实反馈**：遥控器麦克风、BLE HID 无法第三方精确断开均未伪装成功。

自检从 64 项扩到 **76 项 ALL PASS**（新增 app 身份、监听通道实测、三态标签、
语音缺项文案、未连接蓝牙引导等断言）；编译 0 warning；`codesign --verify --deep --strict`
通过；`--power-test` 真实进程 PASS；`--diag` 输出权限原始探测值。
GUI 三页截图：`screenshots/dev-fix-overview.png`、`dev-fix-voice.png`、`dev-fix-power.png`。

**仍未覆盖**：真机按键端到端、触控板指针、休眠唤醒、Siri 键语音触发与耗电实测
（需遥控器连接后补测）。语音识别 TCC 状态在不同启动方式下仍会返回 0/3 波动，
现在界面能精确指出是哪一项、并给出可执行的重新检测入口，不再误报为代码缺陷。

## 可复用分发包（2026-11-16 17:50，build `20261116-174924`）

目标：脱离当前项目目录和本机 keychain，在另一台 Mac 上开箱即用。

- **Universal 二进制**：`./build.sh universal` 分别编译 arm64 / x86_64 后用
  `lipo -create` 合并；已验证 `lipo -info` 为 `x86_64 arm64`。
  已实测 x86_64 交叉编译通过（含 MultitouchSupport 私有框架）。
- **自包含资源**：`assets/make_icon.swift` 用 CoreGraphics 绘制遥控器风格图标，
  经 `sips` + `iconutil` 生成 `assets/vibedeck.icns`（10 个尺寸）并打入
  `Contents/Resources/`；此前 bundle 完全没有图标，Finder 显示通用图标的问题已解决。
- **签名可迁移**：`create_app_bundle.sh` 默认 ad-hoc 签名，不再依赖本机
  `vibedeck.keychain-db` 里的固定自签身份；可用 `VIBEDECK_SIGN_IDENTITY` 指定
  自己的 Developer ID。`BuildStamp.txt` 不再写入本机路径。
- **清理上游残留**：`TouchHandler.swift` 的 debug 日志路径从上游作者的
  本机绝对路径改为 `/tmp/vibedeck-debug.log`。
- **一键安装**：`package_release.sh` 产出 `dist/` 下的
  `vibedeck.app`、`install.command`（清 quarantine + 备份旧版 + 复制到
  /Applications + 启动）、`README-install.txt`，以及
  `vibedeck-macOS-universal.dmg` / `.zip`。文件名用 ASCII，避免跨机器中文名乱码。
- **异机模拟验证**：把 ZIP 解压到 `/tmp/vibedeck-fresh-mac`，清 quarantine 后：
  `lipo -info` 双架构、`codesign --verify --deep --strict` 通过、
  `--selftest` 76/76 PASS、`--diag` 正常、`--power-test` PASS、
  安装脚本 `bash -n` 通过；`open` 启动后窗口与菜单栏图标
  （NSStatusItem 38×24）均正常，无崩溃。
  新路径下 TCC 权限显示未授权是预期行为（新机器需要按说明授权一次）。

当前构建：`v1.2 · 20261116-174924`。
