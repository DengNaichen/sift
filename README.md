# Mailroom Deck

100% 纯原生 Swift / SwiftUI 实现的 macOS 三栏个人邮件分拣工作台，直接双向对接系统「邮件（Apple Mail）」。

## 快速启动

### 方式 1：终端直接运行（继承当前终端的磁盘访问权限，最快体验真机邮箱）

如果你使用的终端（Terminal / iTerm2 / Herdr）已开启「完全磁盘访问权限」，直接运行即可秒连本机 Apple Mail：

```bash
swift test
swift run MailroomApp
```

### 方式 2：打包独立 `Mailroom.app`（支持 Xcode 签名与独立权限管理）

```bash
./scripts/build-app.sh
open dist/Mailroom.app
```

首次运行独立 `.app` 时：
1. 若尚未授予磁盘权限，应用会自动以内置演示数据启动，并在顶部显示引导条，点击 **「打开系统设置」** 在「隐私与安全性 → 完全磁盘访问权限」中勾选 `Mailroom.app`，随后点 **「重新连接」** 即可切换至真实邮箱。
2. 首次按下 `Space`（归档）、`⇧K`（插旗保留）或 `⌫`（移入废纸篓）时，系统会弹出一次「允许 Mailroom 控制“邮件”」授权框，点允许即可。

*(提示：也可以直接用 Xcode 打开根目录 `Package.swift`，配置你的开发团队签名后按 `⌘R` 运行，开发期反复编译不会丢失 TCC 权限。)*

## 架构与模块划分

| 模块 | 路径 | 说明 |
| --- | --- | --- |
| 领域模型与 `MailAdapter` 协议 | `Sources/MailroomCore/Models/MailModels.swift` | 邮件、分拣夹、分类元数据与操作契约，包含 `to`、`sentByOwner`、`conversation` 与正文完整性标记 |
| 纯函数状态机与多步 Undo 栈 | `Sources/MailroomCore/State/DeckState.swift` | 分拣夹、多邮箱范围滤镜、焦点推进、增量外部同步与撤销栈 |
| `.emlx` 解析器与 HTML 清洗 | `Sources/MailroomCore/MailBridge/EmlxParser.swift` | 零外部依赖解析 `.emlx`/`.partial.emlx`、RFC 2047 多字符集、不可见填充字符剥离、图片/样板占位检测与截断标记 |
| 对话线程上下文解析 | `Sources/MailroomCore/MailBridge/ConversationResolver.swift` | 毫秒级批量解析同线程历史消息、`sentByOwnerInThread` 与 `hasFlaggedInThread` 保护信号 |
| 持久化变更账本与 AppleScript 执行器 | `Sources/MailroomCore/MailBridge/MutationLedger.swift` & `AppleMailScriptRunner.swift` | SQLite 持久化操作账本、跨重启 Undo 追踪、`FSEvents` 回声闪烁抑制，以及兼容 Gmail `INBOX`+`[Gmail]/All Mail` 标签语义的可测试 `AppleMailExecutor` |
| Apple Mail 双向桥 | `Sources/MailroomCore/MailBridge/AppleMailAdapter.swift` | 只读查询 `Envelope Index`（`parsed_emlx_v2` 本地缓存）+ `FSEvents` 实时监听 + 安全读写协调 |
| 可插拔分类器层与安全守门 | `Sources/MailroomCore/Classifier/MailClassifier.swift` | 定义 `MailClassifier` 协议与 `ClassificationInput`；`RuleBasedClassifier` 强制执行已插旗保留、不完整/纯图/样板正文归为 `uncertain`，以及本人发件/已插旗线程禁止自动删除 |
| 只读诊断与评测导出工具 | `Sources/MailroomCore/MailBridge/EvalSampleExporter.swift` & `Sources/MailroomBridgeCLI/main.swift` | `mailroom-bridge doctor`（脱敏诊断账户语义、`WAL`、`分片命中率`）与 `export-eval`（导出权限为 `0600` 的评测 JSON） |
| 原生三栏界面 | `Sources/MailroomApp/` | 建筑感中性灰阶浅/深色主题、无框悬浮滚动条、三栏纸页布局、原句高亮自动滚动、底部快捷键 HUD 与 `⌘K` 全局命令面板 |

## 诊断与评测导出 CLI（只读）

```bash
# 仅读取 ~/Library/Mail/V* 与 Accounts4.sqlite（已脱敏，不打印主题/发件人/正文）
swift run mailroom-bridge doctor --limit 40

# 导出收件箱样本用于离线分类评测（生成 0600 权限 JSON，勿提交至版本库）
swift run mailroom-bridge export-eval --limit 20 --output /tmp/mailroom-eval.json --force
```

## 快捷键

| 键 | 动作 |
| --- | --- |
| `J` / `K`（或 ↓ / ↑） | 切换焦点邮件 |
| `Space` | 阅毕归档（待处理视图） |
| `⇧K` | 重要保留（待处理视图） |
| `⌫` | 判为推广并移入废纸篓（待处理视图） |
| `R` | 把当前自动处理的邮件拉回待处理 |
| `↵` | 在 Apple Mail 中打开 |
| `Z` | 撤销上一步（栈式，可连续撤销） |
| `1` / `2` / `3` | 切换「全部待处理」/「已自动归档」/「废纸篓」 |
| `[`（或 `⌘\`） | 折叠 / 展开左侧边栏 |
| `⌘K` | 搜索邮件、切换邮箱范围或执行命令 |
