# Sift 邮件分拣评测套件（Evals）

本目录包含 Sift 邮件分类策略的独立评测工具、正交信号策略定义、本地确定性状态机以及公开基准集。所有脚本仅依赖 Python 3 标准库，与 Swift 应用运行时解耦，且以**严格只读**方式运行，不会修改任何邮箱数据。

## 目录结构

| 文件 / 目录 | 说明 |
| --- | --- |
| [email_classification_policy.json](email_classification_policy.json) | 策略定义：7 个内容话题、14 个正交 `noul` 问题提示词、保守阈值与默认用户偏好 |
| [email_rules.py](email_rules.py) | 本地确定性合成状态机：正文清洗、不可见字符剥离、样板残片识别、护栏保护与偏好映射 |
| [eval_gemini_emails.py](eval_gemini_emails.py) | 评测主程序：支持 `prepare`（整理导出数据）、`run`（单邮件单次调用 `gemini-decision-1`）与 `replay`（离线重放） |
| [try_gemini_decision.py](try_gemini_decision.py) | `gemini-decision-1` 最小连通性自检脚本 |
| [test_email_rules.py](test_email_rules.py) | 离线单元测试：覆盖 7 类分类、安全护栏、偏好切换、限流/网络重试与密钥脱敏 |
| [datasets/open-inbox-v1/README.md](datasets/open-inbox-v1/README.md) | 公开分层收件箱基准集（37 封邮件）、`Gemini 4 Hydrogen` 参考标注与基线评测结果 |
| `evals/runs/` | 单次评测产物目录（含原始 API 请求/响应，权限 `0600`，已由 `evals/.gitignore` 忽略） |
| `evals/local/` | 个人邮箱导出样本与私有标注存放目录（已由 `evals/.gitignore` 忽略，严禁入库） |

---

## 三层分类体系（3-Layer Taxonomy）

Sift 将「模型客观事实判断」与「本地安全护栏及个人偏好」彻底分离。每封邮件仅向 Google Gemini Decisions API（`gemini-decision-1`）发送 **1 次**请求，获取 14 个 `0~1` 之间的正交客观概率信号（7 个行为/形态信号 + 7 个内容话题信号），再由本地状态机合成三层结果：

### 1. 第一层：4 种执行动作（`ACTIONS`）

| 动作 | 含义 |
| --- | --- |
| `keep` | 留在收件箱，需要用户阅读、回复、决策或核验 |
| `archive` | 自动归档，移出收件箱但完整保留为可检索记录 |
| `trash` | 自动移入废纸篓（仅在无任何受保护信号且高置信命中可丢弃类别时触发） |
| `review` | 安全兜底态：正文/附件上下文不足，或删除偏好与受保护信号冲突时暂停自动处置，交由人工复核 |

### 2. 第二层：7 类 Superhuman 启发语义分类 + `review`（`CATEGORIES`）

| 分类 | 典型邮件形态 | 默认动作 | 允许配置的偏好动作 |
| --- | --- | --- | --- |
| `respond` | 需要本人回复、审批、付款、排期确认、接受团队协作邀请、处理故障或推进活跃面试 | `keep`（固定） | 固定为 `keep` |
| `fyi` | 与本人相关的被动记录（已付收据、物流通知、已确认预约/航班、平台政策澄清、账户订阅记录） | `archive` | `keep` / `archive`（禁止 `trash`） |
| `security` | 现有账户的独立安全与鉴权提醒（登录通知、一次性验证码/OTP、密码重置、API Key / Token 新增） | `keep` | `keep` / `archive`（禁止 `trash`） |
| `news` | 订阅制编辑部简报、行业新闻日报、技术期刊、产品更新日志与每周编程挑战刊物 | `archive` | `keep` / `archive` / `trash` |
| `pitch` | 陌生 B2B 商务推销（外包、建站、会议服务等）及无在途申请的群发招聘/职位推荐邮件 | `trash` | `keep` / `archive` / `trash` |
| `social` | 社交网络点赞/关注动态汇总，以及未点名本人处理的公共邮件列表/开源社区论坛讨论串 | `trash` | `keep` / `archive` / `trash` |
| `marketing` | 纯商业零售打折促销、优惠券、消费品与商旅广告传单 | `trash` | `keep` / `archive` / `trash` |
| `review` | 附件未展开、图片未加载、正文截断/空白退订残片，或信号落入灰区/护栏冲突 | `review`（固定） | 固定为 `review` |

当邮件进入 `review` 时，状态机会输出明确的 `review_reason`：
- `insufficient_context`：`has_attachments`、`truncated`、`body_is_image_only` 为真，正文为空白/退订样板残片，或 `context_sufficient < 0.85`。
- `uncertain_attention`：`needs_attention` 或（当 `security=keep` 时）`security_event` 落在 `(0.15, 0.75)` 灰区。
- `uncertain_disposal`：配置为 `trash` 的类别信号落在 `(0.25, 阈值)` 灰区，避免把边界资讯误删。
- `protection_conflict`：邮件命中 `trash` 偏好（或屏蔽发件人），但同时触发了受保护话题、历史记录信号或线程保护标记。

### 3. 第三层：7 个护栏与内容话题（`topics`）

话题分数（`topic_* >= 0.50` 时输出为展示标签）同时承担**防误删硬护栏**职责。凡标记为 `protect_from_trash: true` 的话题，只要概率达到保护门槛 `0.15`（或 `retain_record > 0.15`、邮件已加星 `starred`、同线程含本人发件 `sent_by_owner`、命中 `vip_senders`），状态机即强制置 `protected_from_trash = true`，拦截一切自动 `trash` 动作并转为 `review`（`protection_conflict`）：

| 话题键 | 中文标签 | `protect_from_trash` | 覆盖范围 |
| --- | --- | --- | --- |
| `work` | 工作沟通 | `true` | 同事/客户/合作方往来、团队协作邀请、本人项目/仓库运维告警、在途求职面试 |
| `finance` | 财务交易 | `true` | 账单、发票、收据、订单/预订确认、物流、退款、银行结单、税务与合同 |
| `account_security` | 账户安全 | `true` | 登录/MFA 提醒、密钥变更、OAuth 授权、账户配额/停用通知、现有账户条款更新 |
| `personal` | 私人事务 | `true` | 亲友私信、医疗/法律/政务/学校及个人预约事务 |
| `newsletter` | 订阅资讯 | `false` | 定期订阅刊物、新闻摘要、社区邮件列表与职位推荐简报 |
| `product` | 产品服务 | `false` | 软件/硬件功能发布、更新日志、上手指南与技术教程 |
| `marketing` | 营销活动 | `false` | 零售折扣、优惠券、付费升级推广、陌生商务推销与赞助广告 |

---

## 偏好切换（`preferences`）与离线重放

模型提示词只询问客观属性，个人分拣偏好集中在 [email_classification_policy.json](email_classification_policy.json) 的 `preferences` 字段中：

```json
{
  "preferences": {
    "fyi": "archive",
    "security": "keep",
    "news": "archive",
    "pitch": "trash",
    "social": "trash",
    "marketing": "trash",
    "vip_senders": [],
    "blocked_senders": []
  }
}
```

- **零 API 成本切换模式**：例如求职期间希望保留猎头与职位推荐（将 `"pitch"` 设为 `"archive"` 或 `"keep"`），或希望自动归档常规登录提醒（将 `"security"` 设为 `"archive"`），无需修改问题提示词或重新请求 API。
- **使用 `replay` 验证新策略/新偏好**：
  ```bash
  python3 evals/eval_gemini_emails.py replay \
    --results evals/runs/open-inbox-v1-run01/results.json \
    --dataset evals/datasets/open-inbox-v1/emails.json \
    --gold evals/datasets/open-inbox-v1/gold-hydrogen-v1.json \
    --policy evals/email_classification_policy.json \
    --output evals/runs/open-inbox-v1-replay
  ```
- **安全约束**：`load_policy()` 会在加载阶段拒绝将 `fyi` 或 `security` 设为 `"trash"`，防止配置失误导致账单回执或验证码被自动删除。

---

## 运行离线单元测试

单元测试不访问网络、不读取真实邮箱，验证状态机分支、偏好切换、截断/空壳识别、429/网络瞬断重试与 API Key 脱敏：

```bash
python3 -m unittest discover -s evals -p 'test_*.py' -v
```

---

## 运行公开基准集（`open-inbox-v1`）

1. **配置 API Key**（切勿提交或打印密钥）：
   在仓库根目录 `.env`（或任意受保护的外部 `.env` 文件）中配置：
   ```dotenv
   gemini_decision_api_key=YOUR_API_KEY
   ```
   也可通过环境变量 `GEMINI_API_KEY` 传入。可先运行最小自检确认连通性：
   ```bash
   python3 evals/try_gemini_decision.py
   ```

2. **执行完整基准评测**：
   ```bash
   python3 evals/eval_gemini_emails.py run \
     --dataset evals/datasets/open-inbox-v1/emails.json \
     --gold evals/datasets/open-inbox-v1/gold-hydrogen-v1.json \
     --interval 2.0 \
     --max-tpm 42000 \
     --output evals/runs/open-inbox-v1-run01
   ```
   若使用外部 `.env` 文件，追加 `--env-file /path/to/.env`。运行结束后，`evals/runs/open-inbox-v1-run01/` 下会生成 `summary.json`、`report.md` 与 `results.json`；公开版本库仅跟踪聚合摘要 [baseline-summary.json](datasets/open-inbox-v1/baseline-summary.json)。

---

## 导出个人 Apple Mail 样本到 `evals/local/`

如需在个人真实收件箱上验证分拣效果，请使用仓库内置的只读桥接 CLI 将邮件导出到受 `.gitignore` 忽略的 `evals/local/` 目录：

1. **确认磁盘访问权限与邮箱状态**（脱敏输出，不打印任何邮件主题、发件人姓名或正文）：
   ```bash
   swift run mailroom-bridge doctor --limit 40
   ```

2. **只读导出收件箱样本**（自动附带同线程最近最多 12 条历史对话、`sent_by_owner` / `starred` 保护位与附件/纯图标记，输出文件权限强制为 `0600`）：
   ```bash
   mkdir -p evals/local
   swift run mailroom-bridge export-eval \
     --limit 30 \
     --output evals/local/inbox.private.json \
     --force
   ```

3. **准备私有参考标签并运行评测**：
   在 `evals/local/gold.private.json` 中为导出的 `email-01`..`email-30` 标注期望的 `action` 与 `category`，随后运行：
   ```bash
   python3 evals/eval_gemini_emails.py run \
     --dataset evals/local/inbox.private.json \
     --gold evals/local/gold.private.json \
     --interval 2.0 \
     --max-tpm 42000 \
     --output evals/runs/local-inbox-run01
   ```

> **隐私安全提示**：`evals/local/`、`evals/runs/`、`*.private.json` 与根目录 `*eval*.json` 均已列入 `.gitignore`。请勿使用 `git add -f` 强制提交任何个人邮件样本或原始 API 响应。
