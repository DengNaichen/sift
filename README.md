# Mailroom Deck

AI 原生个人邮件工作台的纯前端三栏交互外壳。不连后端，所有数据经 `MailAdapter` 接口读写。

```bash
npm install
npm run dev      # http://localhost:5173
npm run build    # 类型检查 + 生产构建
```

## 三栏结构

| 区域 | 组件 | 作用 |
| --- | --- | --- |
| 第 1 栏（分拣导航栏） | `src/components/Sidebar.tsx` | 顶部收件邮箱范围滤镜（全部 / 单账户）、搜索入口、按注意力与处置结果组织的分拣夹 |
| 第 2 栏（高密度邮件列表） | `src/components/MailList.tsx` | 固定高度分割线行，展示发件人、收件邮箱微标、分类胶囊与触发原句 `evidence`，切换焦点不跳动 |
| 第 3 栏（操作栏 + 原文阅读区） | `src/components/ReadingPane.tsx` | 顶部统一拍板工具栏、完整信头（含发件人与收件邮箱地址）、原文及 `evidence` 高亮 |
| 数据契约与演示数据 | `src/adapter/` | `MailAdapter` 接口（含 `MailAccount` 身份字段）与内存版 `MockMailAdapter` |
| 状态管理 | `src/state/` | 纯 reducer（文件夹/账户过滤、焦点维护、撤销栈、会话计数） |

## 数据边界

后端是只做判断的 System 1 分类模型，不生成文字。界面上的每一处内容只来自两类来源：

1. 邮件原始字段：发件人、收件邮箱（`account`）、主题、正文、附件；
2. 分类器输出：类别标签、校准概率，以及可选的意图标签 `intent`、触发判定的原句 `evidence`。

`evidence` 必须逐字出现在正文里，否则界面当作没有。没有 `evidence` 时，列表显示正文开头。

替换为 Apple Mail 本机桥接：实现 `MailAdapter`，在 `src/main.tsx` 里换掉 `new MockMailAdapter()`。
`DemoControls`（重置 / 模拟新邮件）是可选能力，真实实现可以不提供，界面会自动隐藏对应按钮。

## 快捷键

| 键 | 动作 |
| --- | --- |
| `J` / `K`（或 ↓ / ↑） | 切换焦点邮件 |
| `Space` | 阅毕归档（待处理视图） |
| `⇧K` | 重要保留（待处理视图） |
| `⌫` | 判为推广并移入废纸篓（待处理视图） |
| `R` | 把当前自动处理的邮件拉回待处理 |
| `↵` | 在 Apple Mail 中打开（`message://`） |
| `Z` | 撤销上一步（栈式，可连续撤销） |
| `1` / `2` / `3` | 切换「全部待处理」/「已自动归档」/「废纸篓」 |
| `[`（或 `⌘\`） | 折叠 / 展开左侧边栏 |
| `⌘K` | 搜索邮件、切换邮箱范围或执行命令 |

在输入框中打字时，单键快捷键会被屏蔽。
