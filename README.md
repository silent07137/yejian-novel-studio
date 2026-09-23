# 页间 Native

页间是面向长篇创作的本地优先写作工具，使用 Flutter 原生渲染 Android 与 Windows 界面，不以网页或 WebView 作为应用主体。

当前源码是按《页间双端开发手册 v1.0》持续重做的 `0.4.0-dev.10` 开发版本，不是完成版。真实进度与未完成项见 [docs/IMPLEMENTATION_STATUS.md](docs/IMPLEMENTATION_STATUS.md)。

## 当前基础

- Android 状态栏、挖孔安全区、系统返回手势与底部手势区适配。
- 全局以书架为入口；个人资料和设置在顶部入口；进入作品后显示写作、设定、情节、导出四模块。
- 首次启动以创建作品为主操作，不要求先填写昵称。
- SQLite 本地主存储；项目、分卷、章节和结构化资料在事务内写入。
- 800ms 正文防抖保存、应用进入后台时立即落盘、实体修订号与冲突检测。
- 旧版 `library.json` 一次性迁移，源文件保留。详见 [docs/MIGRATION_NOTES.md](docs/MIGRATION_NOTES.md)。
- 正文默认字号 18、行距 1.7；支持配色、字号、行距和自定义字体基础设置。
- TXT 与 Markdown 按目录/导出开关生成；Android 可关联 `内部存储/Download/yejie`，或通过系统“创建文档”界面另存。
- 角色卡和世界观卡片支持详情、完整基础字段编辑；人物关系按稳定角色 ID 保存。

## 尚未完成

角色/世界观完整编辑、模板系统、真正独立的时间轴/思维导图/流程图、全局搜索、历史与回收站、六种成品导出、可校验工程 ZIP、百万字性能和 Android 实机验收仍在开发。旧 `.sns/.snss` 代码仅保留作历史迁移参考，不能视为已验证的完整工程格式。

## 开发环境

安装 Flutter stable 与 Android SDK，并确保 `flutter` 已加入 `PATH`：

```powershell
flutter doctor
flutter pub get
```

需要把 SDK 或缓存放到非系统盘时，可在本机设置 `ANDROID_HOME`、
`ANDROID_SDK_ROOT`、`PUB_CACHE` 和 `GRADLE_USER_HOME`。这些本机路径不要提交到仓库。

## 验证

```powershell
flutter analyze
flutter test
```

## Android 开发构建

```powershell
flutter build apk --debug
```

正式发布前仍需独立发行密钥、升级安装/迁移测试和实体设备验收。

## 仓库内容

- `lib/`：应用逻辑、数据层与界面。
- `test/`：数据和界面回归测试。
- `android/`、`windows/`：原生平台工程。
- `assets/`：随应用发布的资源。
- `docs/`：迁移说明、实现状态和构建记录。
- `installer/`、`tool/`：Windows 安装程序定义与构建脚本。

构建产物、测试截图、本机 SDK 路径、签名文件和环境变量文件均被忽略，不应提交。

## 许可证

本项目仅采用 GNU General Public License version 2（SPDX：`GPL-2.0-only`），不包含“或任何后续版本”条款。完整条款见 [LICENSE](LICENSE)。
