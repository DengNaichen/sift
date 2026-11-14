---
name: release
description: >-
  发布 Sift macOS 应用到 GitHub Releases，处理版本号递增、v* 标签推送、GitHub Actions 签名与 Apple 公证跟踪，以及 Developer ID 证书与 notarytool 故障排查。当用户要求发版、打 tag、升级版本号或排查发布流水线时使用。
---

# Sift macOS Release

正式产物（`arm64`、最低系统 macOS 26、Bundle ID `NaichengDeng.Sift`、Hardened Runtime、Apple 公证 + Stapled DMG）统一由 GitHub Actions 的 [macos-release.yml](../../../.github/workflows/macos-release.yml) 在云端构建并发布到 `DengNaichen/sift` Releases。

- 所有发布专用脚本收纳在本 skill 的 [`scripts/`](scripts) 下（从仓库根目录调用路径为 `./.agents/skills/release/scripts/...`）。
- 只修改文档、脚本或准备代码时，**不要**推送 `v*` 标签或触发线上发布。

## 执行前检查（Pre-flight）

1. **明确版本号**：确认目标语义化版本 `X.Y.Z`（未指定时先询问用户）。Build 号固定由公式 `MAJOR * 1_000_000 + MINOR * 1_000 + PATCH` 计算，必须严格单调递增。
2. **确认分支与 CI 状态**：
   - 在主 checkout 确认当前处于干净的 `main` 分支，且与 `origin/main` 完全同步（`git fetch origin main`）；不要从任务 worktree 强切 `main`。
   - 检查最新 `main` 的 [CI](../../../.github/workflows/ci.yml) 是否通过：`gh run list -R DengNaichen/sift --workflow ci.yml --limit 3`。
   - 检查本地与远端均不存在同名标签 `refs/tags/vX.Y.Z`（若已存在则核查对应 Release 状态，严禁覆盖或强推标签）。
3. **Apple 公证网关连通性预检（可选）**：
   - 若本机钥匙串已存有公证 profile（如 `sift-notary` 或 `stet-notary`），可先运行 `xcrun notarytool history --keychain-profile <profile>` 确认未触发 Apple 开发者协议更新拦截（`HTTP 403`）。

## 正式发布步骤

1. **更新版本并推送 `vX.Y.Z` 标签**（须在用户明确要求发版后执行）：
   先查看 [bump-version.sh](scripts/bump-version.sh)，然后在仓库根目录运行：
   ```zsh
   ./.agents/skills/release/scripts/bump-version.sh X.Y.Z
   ```
   - 若 [Config/Info.plist](../../../Config/Info.plist) 版本低于 `X.Y.Z`，脚本会自动更新 `CFBundleShortVersionString` 与 `CFBundleVersion`、提交并推送 `main`，随后创建并推送 `vX.Y.Z` 标签。
   - 若 `Config/Info.plist` 已处于 `X.Y.Z` 且标签尚未创建（例如首次发布该版本），脚本会跳过空提交并直接打标推送。
2. **跟踪 `macOS Release` 工作流直至完成**：
   ```zsh
   gh run list -R DengNaichen/sift --workflow macos-release.yml --limit 3
   gh run watch <run-id> -R DengNaichen/sift --exit-status --compact
   ```
3. **核验真实线上产物**：
   ```zsh
   gh release view vX.Y.Z -R DengNaichen/sift --json name,tagName,url,isDraft,isPrerelease,assets
   ```
   确认 `isDraft: false`、`Sift-vX.Y.Z.dmg` 的 `state` 为 `uploaded`，向用户汇报版本号、构建 commit、Actions Run 链接及 Release / DMG 下载直链。

## 手动草稿预发布（`workflow_dispatch`）

仅在需要验证云端签名公证链路、但不想打正式 git tag 时使用（需用户授权）：

```zsh
gh workflow run macos-release.yml -R DengNaichen/sift -f git_ref=main -f release_tag=vX.Y.Z-rc1
```

注意目标 `git_ref` 中 [Config/Info.plist](../../../Config/Info.plist) 的版本仍须匹配 `X.Y.Z`。该模式会使用 `production` 环境构建并公证 DMG，但创建的 GitHub Release 为 `draft=true`、`prerelease=true`、`latest=false`。

## 脚本索引与故障排查

| 脚本 | 职责 |
| --- | --- |
| [bump-version.sh](scripts/bump-version.sh) | 校验干净 `main` 与唯一 tag，计算整数 Build 号写入 `Config/Info.plist`，推送 `main` 与 `v*` tag |
| [setup-notarytool-profile.sh](scripts/setup-notarytool-profile.sh) | 将 `APPLE_ID`、`APPLE_TEAM_ID`、`APP_SPECIFIC_PASSWORD` 存入钥匙串 `sift-notary` 并校验 |
| [release-macos-github.sh](scripts/release-macos-github.sh) | 校验 tag 与版本一致，调用 [build-app.sh](../../../scripts/build-app.sh) 编译并做 `Developer ID` 签名、打 DMG、`notarytool` 公证及 `stapler` 钉票据 |
| [publish-github-release.sh](scripts/publish-github-release.sh) | 调用 `gh release` 创建或更新 Release、生成 Release Notes 并上传 DMG |

### GitHub `production` 环境凭据清单

| 类型 | 名称 | 说明 |
| --- | --- | --- |
| Variable | `DEVELOPER_ID_APPLICATION` | `Developer ID Application: Naicheng Deng (67BL3M4FPS)` |
| Secret | `DEVELOPER_ID_APPLICATION_P12_BASE64` | 单行 Base64 编码的 Developer ID `.p12`（含私钥） |
| Secret | `DEVELOPER_ID_APPLICATION_P12_PASSWORD` | `.p12` 导出保护密码 |
| Secret | `APPLE_ID` | Apple Developer 账号邮箱 |
| Secret | `APPLE_TEAM_ID` | `67BL3M4FPS` |
| Secret | `APP_SPECIFIC_PASSWORD` | Apple ID 生成的 App 专用密码 |

更新 `.p12` 证书时（从 Xcode → `Settings… → Accounts → Manage Certificates…` 右键 `Developer ID Application` 导出到 `/tmp/dev-id.p12`）：

```zsh
P12_FILE="/tmp/dev-id.p12"
read -rs 'P12_PASS?请输入 .p12 导出密码: '; echo
base64 -i "$P12_FILE" | tr -d '\n' | gh secret set DEVELOPER_ID_APPLICATION_P12_BASE64 -R DengNaichen/sift -e production
printf '%s' "$P12_PASS" | gh secret set DEVELOPER_ID_APPLICATION_P12_PASSWORD -R DengNaichen/sift -e production
rm -f "$P12_FILE" && unset P12_PASS
```

### 常见故障处理

- **`Store Notarytool Credentials` 报 `HTTP 403: A required agreement is missing or has expired`**：
  Apple Developer 后台有新版协议待签署。请用户登录 `https://developer.apple.com/account`（必要时一并检查 `https://appstoreconnect.apple.com/business`）点击同意。苹果公证网关有约 2～10 分钟同步缓存延迟，生效后直接执行 `gh run rerun <run-id> -R DengNaichen/sift` 重跑原任务即可，**不要删除或重写已推送的 tag**。
- **公证失败（`Notarization failed with status: Invalid`）**：
  工作流会自动拉取 `notary-log.json` 并打包进 Actions Run Artifacts，下载查看具体未通过检查的文件、签名时间戳或 Hardened Runtime 配置。
