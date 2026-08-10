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

---

## 仓库与发布状态（AI Agent 阅读）

本仓库已经初始化并托管在 GitHub：

- **仓库地址**：https://github.com/dxt6/FitLog （**Public**）
- **默认分支**：`main`
- **Remote**：`https://github.com/dxt6/FitLog.git`
- **Release**：`v1.0.0`，资产 `FitLog-v1.0.0-debug.apk`（debug 构建，仅供测试）

### 已经由 AI Agent 完成的工作

1. `git init` 并首次提交（28 个源文件：Kotlin 源码、`app/build.gradle.kts`、Gradle 配置、`README.md`、`需求文档.md` 等）。
2. 新增 `.gitignore`（Android 标准 + 排除 `app/build/`、`app/.gradle/`、`local.properties`、`*.keystore`/`*.jks` 等构建产物与机器相关文件，确保不漏传密钥和编译产物）。
3. 补上 `gradle/wrapper/gradle-wrapper.jar`（Gradle 8.6），使 clone 后 `./gradlew` 可直接构建。
4. 通过 GitHub REST API 创建仓库 `dxt6/FitLog` 并设为 Public。
5. 推送到 `main` 分支。
6. 创建 Release `v1.0.0` 并上传 debug APK 资产。

> 注意：当前 Release 中的 APK 是 **debug** 构建，仅用于自测，不能直接对外分发或上架。正式发布需生成 release 签名 APK 后替换/新增资产。

---

## 给 AI Agent / 协作者：如何向本机 GitHub 推送代码

本机环境有两点特殊约定，**任何需要联网（git push / GitHub API）的操作都必须遵守**：

### 1. 网络必须走本地代理

所有对外 HTTPS 请求需经本机 Clash 代理 `http://127.0.0.1:7897`。

- Git 推送前设置代理（推荐写进仓库级 git config，已设置过一次）：
  ```bash
  git config http.proxy  http://127.0.0.1:7897
  git config https.proxy http://127.0.0.1:7897
  ```
  或临时用环境变量：
  ```bash
  HTTPS_PROXY=http://127.0.0.1:7897 HTTP_PROXY=http://127.0.0.1:7897 git push
  ```
- 用 `curl` 访问 GitHub 时加 `-x http://127.0.0.1:7897`。

### 2. 凭据来自 Git Credential Manager（无需 PAT）

本机已用 **Git Credential Manager** 缓存了 GitHub 凭据（用户名 `dxt6`）。**不要**在 remote URL 里写 token，也无需向用户索要 PAT。

- 推送时直接 `git push`（GCM 会自动提供凭据）。
- 如需用 GitHub REST API（建仓库、建 Release、传资产），从 GCM 取缓存的 token：
  ```bash
  TOKEN=$(printf 'protocol=https\nhost=github.com\n' | git credential fill | awk -F= '/^password=/{print $2}')
  curl -sSL -x http://127.0.0.1:7897 -H "Authorization: Bearer $TOKEN" ...
  ```
- **绝对不要把 token 写进仓库、README 或任何会被提交的文件。**

### 3. 代理对部分域名会掐断隧道（重要坑）

`raw.githubusercontent.com` 和 `services.gradle.org` 的隧道会被代理中途断开（TLS 握手失败）。因此：

- 下载文件（如 Gradle 发行包）或拉取 raw 内容时，**不要**用 `raw.githubusercontent.com` 或 `services.gradle.org`；优先走 **GitHub Contents API**：`https://api.github.com/repos/<owner>/<repo>/contents/<path>?ref=<branch>`，返回 base64 `content` 再解码。
- GitHub API 操作一律走 `api.github.com`（REST）与 `uploads.github.com`（资产上传），这两个域名在代理下稳定可用。
- Gradle 依赖下载（`services.gradle.org`）若被掐断，改用其他镜像或从已缓存的 Gradle 发行包中提取 `gradle-wrapper.jar`。

### 4. 标准推送流程（提交后）

```bash
cd /path/to/健身app
git config http.proxy  http://127.0.0.1:7897
git config https.proxy http://127.0.0.1:7897
git add -A
git commit -m "你的提交说明"
git push origin main        # GCM 自动提供凭据
```

### 5. 发布新版本 / 更新 Release 资产

```bash
TOKEN=$(printf 'protocol=https\nhost=github.com\n' | git credential fill | awk -F= '/^password=/{print $2}')

# 创建 Release（已存在可跳过）
curl -sSL -x http://127.0.0.1:7897 -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/vnd.github+json" \
  -X POST https://api.github.com/repos/dxt6/FitLog/releases \
  -d '{"tag_name":"v1.1.0","name":"FitLog v1.1.0","body":"...","draft":false,"prerelease":false}'

# 上传资产（先取 release 的 upload_url，去掉 {name} 模板，拼 ?name=文件名）
# upload_url 形如 https://uploads.github.com/repos/dxt6/FitLog/releases/368036049/assets{?name,label}
curl -sSL -x http://127.0.0.1:7897 -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/vnd.android.package-archive" \
  --data-binary "@app/build/outputs/apk/release/app-release.apk" \
  "https://uploads.github.com/repos/dxt6/FitLog/releases/<id>/assets?name=FitLog-v1.1.0-release.apk"
```
