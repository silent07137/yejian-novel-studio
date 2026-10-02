# Windows 与 Android Beta 发布说明

本项目使用 GitHub Actions 构建并发布双端 Beta。推送 `v0.4.0-dev.N` 标签后自动触发，也可手动指定已经推送的标签重试。工作流先执行静态分析与测试，再并行构建正式签名的 Android APK 和 Windows x64 MSI；两端全部成功且 SHA-256 校验通过后，才公开同一个 GitHub Pre-release。

## 1. 创建并保管发行密钥

发行密钥只应创建一次。以下命令中的路径可以放在空间充足、能够可靠备份的非项目目录：

```powershell
keytool -genkeypair -v `
  -keystore E:\YejianKeys\yejian-release.jks `
  -keyalg RSA `
  -keysize 4096 `
  -validity 10000 `
  -alias yejian
```

请离线备份 `.jks` 文件、别名和两个密码。丢失密钥后，后续构建将无法覆盖安装使用旧密钥签名的版本。

不要把密钥或密码提交到 Git，也不要把它们粘贴到 Issue、Actions 日志或聊天记录中。

## 2. 转换密钥为 Base64

在 PowerShell 中执行：

```powershell
$keyBytes = [System.IO.File]::ReadAllBytes('E:\YejianKeys\yejian-release.jks')
[Convert]::ToBase64String($keyBytes) | Set-Clipboard
```

剪贴板内容只用于下一步创建 GitHub Secret。

## 3. 配置 GitHub Actions Secrets

进入仓库：

`Settings → Secrets and variables → Actions → New repository secret`

依次创建：

| Secret | 内容 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | 上一步得到的 Base64 内容 |
| `ANDROID_KEYSTORE_PASSWORD` | 密钥库密码 |
| `ANDROID_KEY_ALIAS` | 密钥别名，示例为 `yejian` |
| `ANDROID_KEY_PASSWORD` | 别名对应的密钥密码 |

Secrets 只会在 Beta 工作流的签名步骤中注入，不会写入仓库。

## 4. 允许工作流创建 Release

进入：

`Settings → Actions → General → Workflow permissions`

如果发布步骤提示 403，请确认仓库允许工作流使用读写权限。只有最终发布任务申请 `contents: write`，用于创建 Release 和上传 APK / MSI；其他任务保持只读。

## 5. 发布当前预发布版

确认 `pubspec.yaml` 为 `0.4.0-dev.33+33`，更新“关于应用”的版本历史，并写好 `docs/releases/v0.4.0-dev.33.md`。提交后同时推送主分支与新标签：

```powershell
git tag -a v0.4.0-dev.33 -m "页间 0.4.0-dev.33 双端 Beta"
git push --atomic origin main v0.4.0-dev.33
```

在 Actions 中查看 `Windows & Android Beta`。发布任务会等待两个构建任务成功；先创建含双方安装包和校验文件的草稿，上传成功再公开。从 Releases 下载 APK / MSI，不要把 ZIP 格式的 Actions Artifact 当作安装包。

未创建 Release 的失败运行可以在 Actions 中重试；手动 `Run workflow` 时填已有标签。手动运行也检出该标签，而非直接使用最新 main，避免版本与代码不对应。已有 Release 不覆盖；若失败时留下草稿，先检查日志和草稿状态，再人工恢复发布，不要移动旧标签。

发布结果会被标记为 Pre-release，不会自动成为稳定版。

## 6. 发布下一开发版

每次需要让 Android 将新包识别为可升级版本，都必须提高 `pubspec.yaml` 中 `+` 后面的 `versionCode`。例如：

```yaml
version: 0.4.0-dev.34+34
```

然后提交并推送代码，再运行工作流，使用新标签：

```text
v0.4.0-dev.34
```

同时更新应用“关于应用”的版本显示与版本历史，并在 `docs/releases/<标签>.md` 写中文更新内容。工作流会把该文件直接用于预发布页面；缺少说明时停止发布。每个预发布版本使用独立的 `dev.N`，不再给同一个版本追加 `-beta.N`。旧的 `dev.11-beta.N` 标签保留为历史记录。同一个 Release 不重复发布，不覆盖旧包。MSI 根据开发版号生成递增的三段数字版本，文件名和界面仍保留完整的 `0.4.0-dev.N`。

## 工作流说明

- `.github/workflows/ci.yml`：推送到 `main` 或创建 Pull Request 时自动运行 `flutter analyze` 和 `flutter test`。
- `.github/workflows/android-beta.yml`：文件名保留兼容，显示名为 `Windows & Android Beta`；标签推送或手动运行，两个平台固定使用同一提交。
- Android 会检查四个签名 Secrets、APK 签名、正式包名与版本，拒绝发布独立本地测试包或 Android Debug 签名。
- Windows 使用托管 `windows-2025` 镜像的 WiX 3.14 构建 MSI；打包前检查 EXE 版本及禁止包含 `user-data`。
- Actions 页面中的每次运行都保留日志。两个平台的 Artifact 保存 14 天；正式 Beta 从 Releases 页面下载。Windows 尚未代码签名，可能显示未知发布者提示，安装升级仍需实体机器验收。
