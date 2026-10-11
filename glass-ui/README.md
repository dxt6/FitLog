# FitLog · Apple Liquid Glass UI（实验分支）

把 FitLog 的界面用 **Apple Liquid Glass（苹果液态玻璃）** 风格重做，作为官方 Compose 版之外的一个 WebView 壳实现。

> 说明：原项目是 Android 原生（Kotlin + Jetpack Compose）。本目录是一个**独立的 web 前端 + 极简 WebView 壳**，用于快速验证玻璃质感的 UI 方案，不影响原有 `app/` Compose 代码。

## 目录

```
glass-ui/
├── web/                       # 纯前端（零依赖原生 HTML/CSS/JS）
│   ├── index.html
│   ├── styles.css
│   └── app.js
└── android/                   # WebView 壳工程（无 Gradle，手工打包）
    ├── app/src/main/          # Manifest / MainActivity / res / assets
    └── build_apk.sh           # 一键打包 APK
```

## 功能（对齐原版数据模型）

动作 / 训练日 / 组（重量 · 次数 · 单双边 · RPE），四个 Tab：**训练 / 动作库 / 统计 / 设置**。

- 训练：日期切换、动作卡片、逐组录入、当日容量统计
- 动作库：肌群筛选 + 搜索 + 自定义动作增删
- 统计：PR 卡（最大重量 / 最大次数 / 估算 1RM-Epley / 累计容量）、Canvas 自绘趋势图
- 设置：阈值、提醒、单位、API Key、JSON 导出/导入
- 数据存 `localStorage`，纯离线

## 玻璃实现要点

- **背景是静态的**：纯 `radial-gradient` 光斑（不用 `filter: blur`、不做动画、不用 `mix-blend-mode`——这三者是移动端性能杀手）。
- **轻量玻璃**：半透明叠色 + 描边 + 高光，列表卡片不各自开 `backdrop-filter`。
- **真·毛玻璃**只留给弹层（`backdrop-filter`）；`position:fixed` 的导航栏等一律用半透明实心，避免滚动时每帧重采样。
- 顶栏按钮：`🌗` 明暗背景、`🔮` 液态折射（SVG `feDisplacementMap` 位移贴图，较耗性能，默认关）、`⚡` 性能模式（一键关掉全部毛玻璃与背景光斑）。

## 打包 APK

```bash
bash glass-ui/android/build_apk.sh
# 产物：glass-ui/android/build/FitLog-glass.apk
```

> 该脚本不依赖 Gradle，直接用 Android SDK 的 `aapt2` + `d8` + `zipalign` + `apksigner` 手工出包。
> 需要：Android SDK（build-tools 34、platform-34）、JDK 17。
> 注意：manifest 必须声明 `<uses-sdk android:minSdkVersion="24" android:targetSdkVersion="34"/>` 且开启
> `android:hardwareAccelerated="true"`，否则整个 App（含 WebView）会退化为 CPU 软件渲染。

## 备注

- APK 与签名文件按仓库 `.gitignore` 规则不入库，请用脚本本地构建。
- 语音录入按钮目前是**演示**（写入示例组），未接真实 ASR/LLM。
