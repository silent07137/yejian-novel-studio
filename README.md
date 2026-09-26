<p align="center">
  <img src="assets/branding/launcher_icon_1024.png" width="128" alt="页间应用图标">
</p>

<h1 align="center">页间</h1>

<p align="center">
  本地优先、以作品为中心的长篇小说写作工具
</p>

<p align="center">
  Android · Windows · Flutter · GPL-2.0-only
</p>

> [!IMPORTANT]
> 页间目前处于 `0.4.0-dev.20` 开发阶段，功能、界面和数据格式仍可能调整。
> 当前 APK 仅用于开发测试，不建议作为唯一写作环境保存重要作品。

## 项目简介

页间面向中文长篇小说创作。应用以书架作为入口，每部作品拥有独立的章节、角色、世界观和情节资料，避免不同作品之间的数据相互混杂。

应用主体使用 Flutter 原生渲染，不以网页或 WebView 作为编辑器。作品数据默认保存在本地 SQLite 数据库中，不要求登录账号，也不会自动上传正文。

## 当前功能

### 书架与作品

- 以书架作为主界面，支持创建、编辑和删除作品。
- 独立作品主页，展示封面、简介、字数、章节数和分卷目录。
- 分卷、章节的新建、编辑、状态管理与多选删除。
- 每本书独立提供“写作、设定、情节、导出”工作区。

### 写作

- 正文自动保存，并在应用进入后台时立即落盘。
- 章节修订号与冲突检测，降低旧内容覆盖新内容的风险。
- 可对选中的正文添加待修改标注，或关联伏笔、灵感；标注支持定位、改备注与删除。
- 段落菜单可切换首行缩进和行距；TXT、Markdown 可分别导出。
- 支持字号、行距、配色、明暗模式和自定义字体基础设置。
- 中文写作默认使用无衬线体和适合正文阅读的排版参数。

### 设定与情节

- 角色卡、世界观条目与自定义字段基础编辑。
- 人物关系使用稳定角色 ID 保存。
- 多时间线、思维导图和流程图共用作品内事件数据。
- 时间线支持多轨展示；画布支持缩放和平移。

### 导出与迁移

- 支持 TXT 与 Markdown 导出，以及单书 `.sns`、多书 `.snss` 工程导入导出。
- Android 可通过系统文件界面另存，或关联导出目录。
- 支持旧版 `library.json` 的一次性迁移，并保留源文件。
- 工程文件仅在主动导出时生成；导入前预览，遇到已有作品需明确确认替换。格式说明见 [工程文件规范](docs/PROJECT_FORMAT.md)。

### 移动端适配

- 适配 Android 状态栏、挖孔安全区和底部手势区域。
- 支持系统返回手势。
- 全局悬浮胶囊导航在上滑时收起、下滑时显示。
- 设置页提供个人信息、应用设置和关于应用入口。

## 开发状态

| 模块 | 状态 | 说明 |
| --- | --- | --- |
| Android | 开发验证 | 已在 Android 15 Pixel 7 AVD 完成安装、冷启动、基础导航和数据恢复测试 |
| Windows | 实验性支持 | 保留桌面工程与 MSI 构建脚本，当前开发重点是 Android |
| 本地存储 | 已接通 | SQLite 事务、修订号、迁移和软删除基础数据层已实现 |
| 角色与世界观 | 开发中 | 基础编辑可用，模板、标签库、草稿与恢复界面仍需完善 |
| 情节三视图 | 开发中 | 时间线、思维导图和流程图可交互，布局持久化与连线编辑尚未完成 |
| 成品导出 | 部分可用 | TXT、Markdown 与 `.sns/.snss` 工程文件可用；EPUB、DOCX、PDF 尚未完成 |

更细的实现证据和未完成项见 [实现状态](docs/IMPLEMENTATION_STATUS.md)，旧数据升级说明见 [迁移文档](docs/MIGRATION_NOTES.md)。

## 获取与构建

### 环境要求

- Flutter stable
- Dart SDK（随 Flutter 提供）
- Android Studio 或 Android SDK
- Windows 桌面构建需要 Visual Studio 的“使用 C++ 的桌面开发”工作负载

先检查环境并安装依赖：

```powershell
flutter doctor
flutter pub get
```

本机 SDK、缓存目录和签名信息不应写入仓库。需要把缓存放到其他磁盘时，可以在本机设置：

- `ANDROID_HOME`
- `ANDROID_SDK_ROOT`
- `PUB_CACHE`
- `GRADLE_USER_HOME`

### 代码验证

```powershell
flutter analyze
flutter test
```

当前自动测试覆盖 SQLite 事务、数据迁移、章节管理、模板字段、时间线关系、工程文件往返与主要移动端导航流程。

### 构建 Android APK

开发构建：

```powershell
flutter build apk --debug
```

Release 构建：

```powershell
flutter build apk --release
```

正式分发前必须配置并妥善保存独立的 Android 发行密钥，同时执行升级安装、备份恢复和实体设备测试。

### 构建 Windows

```powershell
flutter config --enable-windows-desktop
flutter build windows --release
```

Windows MSI 脚本位于 `tool/build_windows_msi.ps1`。该流程仍处于实验阶段，发布前需要重新核对版本号、升级策略和签名。

## GitHub Actions 与 Beta 发布

- `CI`：推送到 `main` 或创建 Pull Request 时自动运行 `flutter analyze` 和 `flutter test`。
- `Android Beta`：从 Actions 页面手动触发，使用仓库 Secrets 中的发行密钥构建签名 APK，并创建 GitHub Pre-release。

预发布标签直接使用应用版本，例如 `v0.4.0-dev.20`；下一版递增为 `v0.4.0-dev.21`，不再在同一开发版本后追加 `-beta.N`。发布前须填写对应的中文更新说明 `docs/releases/<标签>.md`，工作流会直接用该文件创建预发布页面。

首次发布前需要创建并备份 Android 发行密钥，再配置四个仓库 Secrets。完整步骤见 [Android Beta 发布说明](docs/RELEASING.md)。

## 数据与隐私

- 作品、正文、角色、世界观和情节资料默认保存在设备本地。
- 应用不要求登录账号。
- 应用不会自动上传作品，也没有内置遥测或广告 SDK。
- 数据只会在用户主动导出、分享文件或打开外部项目链接时离开应用。`.sns/.snss` 包含作品全文及作者信息，请勿随意公开。
- 卸载、清除应用数据或设备损坏都可能导致本地内容丢失；请定期导出工程文件并在其他设备保留副本。

## 目录结构

```text
android/      Android 原生工程与系统文件接口
assets/       应用图标等随包资源
docs/         实现状态、迁移说明和历史构建记录
installer/    Windows MSI 定义
lib/          Flutter 应用、数据层、状态管理和界面
test/         数据层与界面回归测试
tool/         本地构建辅助脚本
windows/      Windows 桌面工程
```

构建产物、模拟器截图、本机 SDK 路径、环境变量文件、数据库和签名材料均通过 `.gitignore` 排除。

## 路线图

- [ ] 完成角色与世界观模板、自定义字段和标签系统
- [ ] 完善时间线排序、节点拖拽、连线编辑与布局持久化
- [ ] 增加全局搜索、历史记录和完整回收恢复流程
- [ ] 完成 EPUB、DOCX、PDF 与工程备份的跨设备实机验收
- [ ] 完成百万字性能、无障碍和多尺寸屏幕测试
- [ ] 完成 Android 实机矩阵、正式签名与升级迁移验收
- [ ] 完成 Windows 桌面交互与 MSI 发布流程

## 参与开发

欢迎通过 Issue 提交可复现的问题、交互建议或数据安全问题。提交代码前请至少运行：

```powershell
flutter analyze
flutter test
```

请勿提交个人作品、数据库、签名密钥、本机路径、账号令牌或构建产物。

## 许可证

页间仅以 [GNU General Public License version 2](LICENSE) 发布，对应 SPDX 标识：

```text
GPL-2.0-only
```

这里的“仅”表示不包含“或任何后续版本”条款。
