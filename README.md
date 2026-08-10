# 健身记录 App（FitLog）

一个 Android 原生（Kotlin + Jetpack Compose）的健身训练记录工具：按日期记录动作 / 每组重量 / 次数 / 左·右·双手 / RPE，并支持按动作名的间隔提醒、统计图表、JSON 导出导入。

## 功能

- **训练记录**：按日期（默认今天，可切任意天）记录；每天合并为一条；每个动作可加多组，每组单独设重量 / 次数 / 单双边 / RPE。
- **动作库**：内置常见动作（胸背腿肩手臂核心）+ 自定义增删改；支持搜索。
- **间隔提醒**：每个动作独立计时，超过设定阈值（默认 72 小时，可全局 + 单动作分别设置）发本地通知提醒。
- **统计**：最大重量 / 最大次数 / 估算 1RM / 总容量 / 重量趋势 / 容量柱状图 / RPE 趋势（Canvas 自绘）。
- **设置**：默认阈值、提醒总开关、单位（kg/lb）、通知权限、JSON 导出 / 导入（合并 / 覆盖）。
- **存储**：本地 Room 数据库，纯离线，无需登录。

## 如何运行

1. 用 **Android Studio**（Hedgehog / Iguana 及以上）打开本项目根目录（`健身app/`）。
2. 确保已安装 **Android SDK 34** 并同意许可证（`Settings > SDK Manager`）。
3. 首次打开若提示缺少 Gradle Wrapper，让 Android Studio 自动生成，或在项目根目录执行 `gradle wrapper`（需本机已装 Gradle）。
4. 连接设备或启动模拟器（minSdk 24 / Android 7.0），点击 Run。

> 本项目使用 Gradle 8.6 + AGP 8.4 + Kotlin 1.9.24 + Compose Compiler 1.5.14 + Room 2.6.1 + WorkManager 2.9.1。

## 目录结构

```
app/src/main/
  AndroidManifest.xml
  java/com/fitlog/app/
    FitnessApplication.kt        应用入口：初始化数据库、种子数据、调度提醒
    MainActivity.kt              Compose 入口 + 底部导航
    data/                       实体、DAO、数据库、仓库、种子、Graph
    ui/theme/                    Material3 主题
    ui/train/                    训练页（核心）
    ui/exercises/                动作库页
    ui/stats/                    统计页（含图表）
    ui/settings/                 设置页（阈值/提醒/导出导入）
    reminder/                    间隔提醒 Worker + 调度
    backup/                      JSON 备份序列化
    util/                        日期工具
```

## 说明

- 内置动作不可删除；自定义动作可删除（历史训练记录保留）。
- 提醒依赖系统通知权限（Android 13+ 需在设置页手动授予）。
- 导出/导入使用系统文件选择器（SAF），导出为 JSON，导入可选「合并」或「覆盖」。
