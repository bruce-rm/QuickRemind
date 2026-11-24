# 速记 (QuickRemind)

一个**离线可用、直接读写系统「提醒事项」**的极简 iOS App。输入一句中文，自动识别日期、时间、重复规则、优先级，一键存入系统提醒事项并按点响铃。

## 核心特性

| 能力 | 说明 |
|---|---|
| 系统级同步 | 基于 EventKit，数据直接写入「提醒事项」App 的 iCloud 数据库，Mac/iPad/Watch 自动同步 |
| 本地语义解析 | 纯 Swift 正则引擎，**完全离线**，不调用任何 AI/API，隐私零外泄 |
| 闹钟提醒 | 每条带时间的提醒自动挂 `EKAlarm`，到点响铃；另可加 5 分钟预通知 |
| 紧急标记 | "紧急"关键词 → 高优先级，可被系统「紧急」智能列表筛选 |
| 重复规则 | 每天 / 每周几 / 每月 / 每年，直接写入 EventKit 重复规则 |
| 零依赖 | 无第三方库、无网络请求、无需后端 |

## 支持的输入示例

```
明天下午三点交报告          → 明天 15:00
后天上午10点开会            → 后天 10:00
今晚8点打电话给妈妈          → 今晚 20:00
明早八点半晨跑              → 明天 08:30
30分钟后吃药               → 30 分钟后
两小时后交表               → 2 小时后
下周一 9:00 项目评审        → 下周一 09:00
这周五下午交方案            → 本周五 15:00
12月25日 上午10点 送礼物    → 12/25 10:00
每天 7点半 晨跑            → 每天 07:30 重复
每周一三五 9点 健身         → 每周一三五 09:00 重复
紧急 明天交税              → 明天 + 高优先级
交电费!!! 明天             → 明天 + 高优先级
明天 #工作 对齐需求         → 明天 + 标签"工作"
```

解析器已通过 19 个单元测试 + Python 对照验证（见下方"验证记录"）。

## 编译安装

### 环境要求
- Mac + Xcode 26（或 Xcode 16+，项目兼容 iOS 17+）
- 一台 iPhone 用于真机测试（模拟器也能跑，但提醒事项权限在模拟器上行为有限）
- 免费 Apple ID 即可（个人开发者签名，7 天有效期；付费账号 1 年）

### 步骤

1. 把整个 `QuickRemind` 文件夹拷到 Mac 上
2. 双击 `QuickRemind.xcodeproj` 打开（工程文件已生成好，**不需要** XcodeGen）
3. 选择 Target `QuickRemind` → Signing & Capabilities：
   - 勾选 "Automatically manage signing"
   - Team 选你的 Apple ID
   - Bundle Identifier 改成唯一的，比如 `com.你的名字.quickremind`
4. 选择你的 iPhone 作为运行目标，点 ▶️ 运行
5. 首次启动会请求「提醒事项」和「通知」权限，点**允许**
6. 首次创建「紧急」闹钟时会请求闹钟权限（AlarmKit，iOS 26+），点**允许**

> entitlements 文件是空的，不需要任何特殊权限。Xcode 需要 26 及以上版本才能编译全屏闹钟；
> 用旧版 Xcode 也能编译，代码会自动跳过 AlarmKit，闹钟退化为普通 EKAlarm 响铃。

### 生成 IPA 文件

IPA 必须由 **macOS + Xcode** 编译产出，Windows / Linux 上没有可用的 iOS 编译链，所以无法在当前环境直接生成。但已经配好了两条路径：

**方式 A：GitHub Actions 云端编译（不需要 Mac，推荐）**

1. 把整个 `QuickRemind` 目录推到你自己的 GitHub 仓库（公开或私有均可）
2. 打开仓库的 **Actions** → 左侧选 **构建速记 IPA** → 点 **Run workflow**，签名方式保持 `unsigned`
3. 运行结束后，在本次运行的页面底部 **Artifacts** 下载 `QuickRemind-IPA.zip`，解压得到 `QuickRemind-unsigned.ipa`

**方式 B：有 Mac，本地一条命令**

```bash
cd QuickRemind
chmod +x build_ipa.sh
./build_ipa.sh
```

产出 `QuickRemind-unsigned.ipa`。

**把未签名 IPA 装到 iPhone**

未签名 IPA 不能像 App Store 应用那样直接安装，需要用工具重签：

- **Windows**：装 [Sideloadly](https://sideloadly.io/)，把 IPA 拖进去，填 Apple ID（免费即可），点 Start
- **Mac**：用 AltStore 同样流程

免费 Apple ID 签出来有效期 **7 天**，到期要重签；付费开发者账号（¥688/年）可签 **1 年**。

**生成带签名的 IPA（TestFlight / 长期安装）**

先在仓库 **Settings → Secrets and variables → Actions** 里加 5 个 Secret：

| Secret | 内容 |
|---|---|
| `CERT_P12_BASE64` | 开发证书 p12 的 base64：`base64 -i Certificates.p12 \| tr -d '\n'` |
| `CERT_PASSWORD` | p12 导入密码 |
| `PROVISIONING_PROFILE_BASE64` | 开发描述文件的 base64 |
| `DEVELOPMENT_TEAM` | Apple Developer Team ID |
| `PROVISIONING_PROFILE_NAME` | 描述文件名称（不是文件名） |

描述文件要绑定 `com.quickremind.app`。如果你改了 Bundle ID，记得同步改工作流里 `provisioningProfiles` 的 key。然后 **Run workflow** 选 `development`，下载的 IPA 就是已签名的。

> 这两个 IPA 用的都是**空 entitlements 文件**（`QuickRemind.unsigned.entitlements`），刻意排除了拿不到审批的 AlarmKit 权限。闹钟仍走 `EKAlarm` + 本地通知，功能不受影响。

### 闹钟的两种形态

| 类型 | 触发条件 | 效果 | 实现 |
|---|---|---|---|
| 普通闹钟 | 所有带时间的事项 | 到点响铃（遵循静音/专注设置） | EventKit `EKAlarm` + 5 分钟预提醒通知 |
| 全屏闹钟 | 紧急事项（含"紧急"关键词）+ 有明确时刻，iOS 26+ | 全屏铃声，穿透静音与专注，锁屏/灵动岛/Apple Watch | AlarmKit，首次使用请求用户授权 |

**AlarmKit 不需要向苹果申请 entitlement**——iOS 26 起对全部开发者开放，只需 `NSAlarmKitUsageDescription`（已在 Info.plist）+ 运行时授权。之前"个人开发者拿不到"的说法是把 AlarmKit 和 Critical Alerts 搞混了，已修正。代码用 `#if canImport(AlarmKit)` 保护，旧版 Xcode 无该 SDK 时会自动跳过，不影响编译。

### App 能给提醒事项打上原生"紧急"标记吗？

**不能，iOS 26 和 27 都不行。** EventKit 的 `EKReminder` 不暴露 urgent 属性，快捷指令在 iOS 27 的"新建提醒事项"里虽然加了 Urgent 开关，但第三方 App 无法通过 API 调用它。App 写的"紧急"是**高优先级代理**（priority=1），能被高优先级智能列表筛出，但不等于系统原生紧急。原生紧急只能在提醒事项 App 内手动开启。

如果确实需要 App 写出原生紧急，唯一可行路径是：在 iOS 27 上预建一个带 Urgent 开关的快捷指令，App 通过官方 URL scheme `shortcuts://run-shortcut?name=...` 调用它——代价是会跳出 App 一次。

## 项目结构

```
QuickRemind/
├── QuickRemind.xcodeproj/
│   ├── project.pbxproj                     # 可直接打开的工程文件
│   └── xcshareddata/xcschemes/             # 共享 scheme（供命令行构建用）
├── .github/workflows/build-ipa.yml         # GitHub Actions 云端编译 IPA
├── build_ipa.sh                            # Mac 本地一键打 IPA
├── project.yml                             # XcodeGen 配置（可选，用于重新生成工程）
├── generate_xcodeproj.py                   # 工程文件生成脚本（一般不需要运行）
├── verify_parser_logic.py                  # 解析器逻辑离线验证脚本（开发用）
├── QuickRemind/
│   ├── QuickRemindApp.swift                # App 入口 + 权限申请
│   ├── Info.plist                          # 权限声明（NSAlarmKitUsageDescription 等）
│   ├── QuickRemind.entitlements            # 空权限文件（AlarmKit 无需 entitlement）
│   ├── QuickRemind.unsigned.entitlements   # 打 IPA 用的空 entitlements
│   ├── Models/
│   │   └── ParseResult.swift               # 解析结果 + 重复规则数据模型
│   ├── Services/
│   │   ├── NaturalLanguageParser.swift     # 核心：中文语义解析引擎（573 行）
│   │   ├── ReminderStore.swift             # EventKit 读写 + 权限 + 紧急标记
│   │   ├── AlarmService.swift              # 本地通知（5分钟预提醒）
│   │   └── AlarmKitService.swift           # 全屏闹钟（iOS 26+，紧急事项触发）
│   └── Views/
│       ├── ContentView.swift               # 主界面：输入 + 筛选 + 列表
│       ├── ParsePreview.swift              # 解析结果预览（可切换清单）
│       ├── ReminderRow.swift               # 提醒行（完成 / 滑动设紧急）
│       └── SettingsView.swift              # 设置 + 语法说明
└── QuickRemindTests/
    └── NaturalLanguageParserTests.swift    # 19 个解析单元测试
```

## 验证记录

### 语义解析器测试（19/19 通过）

在 Windows 上用 Python 复刻了 Swift 解析器的核心算法，跑了 19 个用例全部通过：

```
PASS 明天下午三点交报告     → 交报告 | 2026-11-24 15:00
PASS 今晚8点打电话给妈妈    → 打电话给妈妈 | 2026-11-23 20:00
PASS 两小时后交表          → 交表 | 2026-11-23 14:00
PASS 下周一 9:00 周会      → 周会 | 2026-11-30 09:00
PASS 每周一三五 9点 健身    → 健身 | 每周二四六 重复
PASS 紧急 明天交税         → 交税 | 优先级=1
...
```

重新验证：`python3 verify_parser_logic.py`

### 工程完整性检查

- pbxproj 对象引用：51 个 ID，无悬空引用
- 11 个 Swift 文件括号平衡检查：全部通过

## 已知限制

1. **EventKit 不暴露 iOS 26 的"紧急"布尔属性**。App 用 `priority = 1`（高优先级）作为替代，可被系统"紧急"智能列表筛选，但不会触发 AlarmKit 全屏闹钟。要真正的全屏闹钟需申请 AlarmKit entitlement。
2. **语义解析是规则式的**，只覆盖常见中文表达。复杂句式（如"下个月最后一个周五"）暂不支持，会在预览里显示不完整结果，可手动在提醒事项 App 里修正。
3. **周期规则的首次触发时间**：若指定时刻已过，自动顺延到下一个周期，界面上会显示实际日期。
4. **iOS 17+ 才能用完整权限 API**；iOS 16 及更低版本不支持（项目 deployment target 设为 17.0）。

## 后续可扩展

- 接入 Siri Shortcuts / App Intents，实现"嘿 Siri，速记明天开会"
- 添加桌面小组件，一键快速输入
- 支持自然语言中的地点识别（`EKStructuredLocation`）
- 支持自然语言解析失败时调用本地小模型兜底

## 许可证

个人使用，随意修改。
