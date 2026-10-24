# FitLog iOS 版

安卓版 FitLog（Kotlin + Jetpack Compose）的 **原生 iOS 移植版**（SwiftUI），功能对齐，数据格式互通。

> 注意：iOS 项目只能在 **Mac + Xcode** 上编译运行。本工程在本仓库的 Windows 机器上生成，
> 拿到任意一台 Mac 上打开即可（无需安装任何第三方依赖）。

## 环境要求

- macOS 13+（Ventura），Xcode 15 及以上（Swift Charts 需要 iOS 16 SDK）
- 部署目标：iOS 16.0；iPhone / iPad 通用

## 如何运行

1. 把本仓库同步到 Mac（`git clone https://github.com/dxt6/FitLog.git` 或直接拷贝 `FitLog-iOS/` 目录）。
2. 双击打开 `FitLog-iOS/FitLog.xcodeproj`。
3. 选中 `FitLog` target → **Signing & Capabilities** → Team 选择你自己的 Apple ID（免费个人账号即可真机运行）。
4. 选择模拟器（iPhone 任意机型）或连接真机，⌘R 运行。

> 真机运行麦克风/通知权限按系统弹窗允许即可；模拟器不支持 BGTaskScheduler 后台提醒（不影响其他功能）。

## 功能（与安卓版一一对应）

- **训练记录**：按日期记录；每天合并为一条；月历视图（练过的日期有标记）；每个动作多组，每组重量 / 次数 / 单双边（左·右·双手）/ RPE / 备注，重量自动预填上一组。
- **动作库**：内置 28 个常见动作（胸/背/腿/肩/手臂/核心，id 与安卓版一致）+ 自定义增删改；搜索。
- **间隔提醒**：超过阈值（默认 72h）未练某动作发本地通知；全局开关 + 全局阈值 + 单动作开关/阈值。iOS 用 BGTaskScheduler 后台刷新 + 回前台即时检查实现（iOS 后台调度比 Android 的 WorkManager 严格，以回前台检查为主）。
- **统计**：最大重量 / 最大次数 / 估算 1RM（Epley）/ 总容量 / 重量趋势折线 / 容量柱状 / RPE 趋势（Swift Charts）。
- **设置**：默认阈值、提醒总开关、单位 kg/lb（仅显示换算，存储恒为 kg）、硅基流动 API Key、JSON 导出（系统分享）/ 导入（合并 / 覆盖）、语音草稿查看与删除。
- **语音录入**：训练页「按住说话」，AVAudioRecorder 录 16kHz 单声道 WAV → 硅基流动 ASR（SenseVoiceSmall）转写 → LLM（Qwen3-8B，json_object）结构化解析 → 自动写入当天记录；解析失败原文存草稿；动作名按「精确 → 别名 → 包含 → 建自定义」解析。

## 与安卓版数据互通

- 备份 JSON 字段与安卓版 Gson 输出完全一致：**安卓导出的备份可以在 iOS 版导入，反之亦然**（设置 → 数据备份）。
- 两端 SQLite 表结构一致（但数据库文件本身不共享，各自本地存储）。

## 目录结构

```
FitLog-iOS/
  FitLog.xcodeproj/          Xcode 工程（手写 pbxproj，无第三方依赖）
  FitLog/
    FitLogApp.swift           App 入口：单例容器、底部 Tab、scenePhase 里调度提醒
    Models.swift              全部实体（与 Room 实体字段一致，Codable 兼容安卓 JSON）
    Database.swift            SQLite3 C API 轻封装（串行队列，建表与 Room schema 一致）
    Repository.swift          全部业务逻辑（对应安卓 DAO + Repository）
    BuiltInExercises.swift    内置动作种子数据（id 与安卓版一致）
    AppConfig.swift           硅基流动配置
    DateUtils.swift           日期工具（纯 Calendar 计算，周一对齐月历）
    AppStore.swift            全局设置 ObservableObject
    Components.swift          公共组件/格式化
    TrainView.swift           训练页（月历 + 语音条 + 动作卡片 + 各编辑弹窗）
    ExerciseLibraryView.swift 动作库页（增删改 + 单动作提醒设置）
    StatsView.swift           统计页（Swift Charts 折线/柱状）
    SettingsView.swift        设置页（导出导入 / API Key / 草稿）
    VoiceRecorder.swift       WAV 录音器（16k/单声道/16bit，60s 上限）
    SiliconFlowClient.swift   硅基流动 ASR + LLM 客户端（multipart / json 解析）
    VoiceViewModel.swift      语音录入状态机
    ReminderManager.swift     间隔提醒（BGTask + 本地通知）
    Info.plist                麦克风权限 / BGTask 标识 / 后台模式
    Assets.xcassets           图标（蓝色哑铃）+ 主题色（与安卓版 #1976D2 一致）
```

## 与安卓版的差异说明

| 项 | 安卓版 | iOS 版 |
|---|---|---|
| 图表 | Compose Canvas 自绘 | Swift Charts（系统框架） |
| 后台提醒 | WorkManager 每 6 小时（可靠） | BGTaskScheduler（系统配额，不保证准时）+ 回前台即查 |
| 录音 | AudioRecord PCM→WAV 手工拼头 | AVAudioRecorder 直写 WAV |
| 数据库 | Room | SQLite3 C API（同一 schema） |
| lb 单位 | 设置存了但界面未换算 | 界面实际换算显示（存储仍 kg） |
