# Android Beta 发布说明

本项目使用 GitHub Actions 手动构建并发布 Android Beta。工作流会先执行静态分析和全部测试，然后使用固定的 Android 发行密钥签名 APK，生成 SHA-256，最后创建 GitHub Pre-release。

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

如果发布步骤提示 403，请确认仓库允许工作流使用读写权限。工作流本身只申请 `contents: write`，用于创建标签、Release 和上传 APK。

## 5. 发布 dev.11 Beta

1. 确认 `main` 分支已经包含准备发布的代码。
2. 打开仓库的 `Actions` 页面。
3. 在左侧选择 `Android Beta`。
4. 点击 `Run workflow`。
5. 选择 `main`，标签填写 `v0.4.0-dev.11-beta.1`。
6. 再次点击 `Run workflow`。
7. 等待 Analyze、Test、Build 和 Publish 全部通过。
8. 在仓库 `Releases` 页面下载 APK，并核对附带的 `.sha256` 文件。

发布结果会被标记为 Pre-release，不会自动成为稳定版。

## 6. 发布下一版 Beta

每次需要让 Android 将新包识别为可升级版本，都必须提高 `pubspec.yaml` 中 `+` 后面的 `versionCode`。例如：

```yaml
version: 0.4.0-dev.11+14
```

然后提交并推送代码，再运行工作流，使用新标签：

```text
v0.4.0-dev.11-beta.2
```

同一个标签不能重复发布。工作流遇到已经存在的标签或 Release 会停止，不会覆盖旧包。

## 工作流说明

- `.github/workflows/ci.yml`：推送到 `main` 或创建 Pull Request 时自动运行 `flutter analyze` 和 `flutter test`。
- `.github/workflows/android-beta.yml`：只允许从 Actions 页面手动运行；检查标签与应用版本一致，测试通过并验证正式签名后创建 Beta Release。
- Actions 页面中的每次运行都保留步骤日志。APK 还会作为临时 Artifact 保存 14 天；正式 Beta 应从 Releases 页面下载。
