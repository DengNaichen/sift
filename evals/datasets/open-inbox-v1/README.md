# `open-inbox-v1` 公开邮件分拣基准集

`open-inbox-v1` 是用于验证 Sift 邮件分类策略（4 动作 × Superhuman 7 类 + `review` 安全护栏）的公开分层收件箱基准集，共包含 **37 封**覆盖全部 8 个目标分类的真实形态邮件样本，不含任何私人邮箱数据，可直接随版本库公开分发与复现。

评测体系与命令行用法参见上层文档 [evals/README.md](../../README.md)。

## 文件清单

| 文件 | 说明 |
| --- | --- |
| [emails.json](emails.json) | 37 封标准化邮件样本（`open-01`–`open-37`），含正文提取、HTML 图片 `alt` 占位及附件/纯图预处理标记 |
| [gold-hydrogen-v1.json](gold-hydrogen-v1.json) | 由 `Gemini 4 Hydrogen (High)` 按策略规范独立生成的参考标注（含 `action`、`category` 与逐封理由） |
| [baseline-summary.json](baseline-summary.json) | `gemini-decision-1` + 本地确定性状态机（策略版本 `2026-11-15-sift-v1`）的聚合评测基线摘要 |

---

## 数据来源与开源许可

本数据集从 4 个公开语料库分层抽样合成，完整保留各样本的 `source_dataset`、`source_license`、`source_id` 与 `source_url` 元数据：

| 来源语料库 | 许可证 | 样本数 | 覆盖的邮件类型 |
| --- | --- | ---: | --- |
| [Apache SpamAssassin Public Mail Corpus](https://spamassassin.apache.org/old/publiccorpus/) | Public Corpus (Apache SpamAssassin Project) | 19 | 公共技术邮件列表讨论、科技新闻日报、B2B 陌生推销、群发招聘、零售促销、带补丁附件及纯图空壳邮件 |
| [resend/react-email Community Templates](https://github.com/resend/react-email/tree/canary/apps/demo/emails/Community) | MIT | 10 | 团队协作邀请、GitHub / Linear / Dropbox / Yelp 安全鉴权提醒、订单发货、App Store 收据、Google Play 政策通知、CodePen 周刊 |
| [weijianzhg/email-triage-action-seed](https://huggingface.co/datasets/weijianzhg/email-triage-action-seed) | Apache-2.0 | 4 | 企业紧急付款审批、生产故障升级、亲友聚会排期沟通、牙科预约确认记录 |
| [imnim/multiclass-email-classification](https://huggingface.co/datasets/imnim/multiclass-email-classification) | MIT | 4 | 在途岗位面试确认、账单到期催缴提醒、航班预订确认、零售夏季打折促销广告 |

---

## 参考标注分布（`Gemini 4 Hydrogen`）

参考标签由 `Gemini 4 Hydrogen (High)` 在默认偏好（`fyi=archive`、`security=keep`、`news=archive`、`pitch=trash`、`social=trash`、`marketing=trash`）下独立标注：

### 按分类（`category`）分布

| 分类 | 默认映射动作 | 样本数 | 代表样本 |
| --- | --- | ---: | --- |
| `respond` | `keep` | 6 | Vercel 团队邀请、大额电汇审批、面试排期确认、未付账单到期提醒、亲友排期、生产故障升级 |
| `fyi` | `archive` | 6 | 牙科预约确认、航班确认、Nike 发货通知、Apple 订阅收据、Google Play 政策澄清、Mailman 订阅记录 |
| `security` | `keep` | 5 | GitHub 新增 PAT 提醒、Yelp 登录通知、AWS 验证码、Dropbox 密码重置提醒、Linear 登录验证码 |
| `news` | `archive` | 5 | CNET 每日新闻、CodePen 每周挑战刊物、Wrox 开发者期刊、The Register 头条、CNET 安全资讯周刊 |
| `pitch` | `trash` | 4 | 陌生企业电话会议推销、群发招聘会推广（jobfair24）、SEO 建站推广、企业主机推销 |
| `social` | `trash` | 4 | `RPM-List`、`[ILUG]`、`Exmh-users` 等公共开源邮件列表成员讨论串（无附件、未点名本人） |
| `marketing` | `trash` | 4 | 零售夏季促销、CNET Shopper 导购折扣、消费品美白广告、独立旅游保险促销 |
| `review` | `review` | 3 | 未展开补丁附件（`open-15`）、纯图片广告残片（`open-22`）、仅含退订链接的空白正文（`open-30`） |
| **合计** | — | **37** | `keep`: 11 · `archive`: 11 · `trash`: 12 · `review`: 3 |

---

## 基线评测结果（`gemini-decision-1`）

使用 [email_classification_policy.json](../../email_classification_policy.json)（`2026-11-15-sift-v1`）与本地状态机 [email_rules.py](../../email_rules.py) 对全部 37 封样本执行单邮件单次请求实测（完整指标见 [baseline-summary.json](baseline-summary.json)）：

| 指标 | 结果 |
| --- | --- |
| 完成样本 / 错误数 | `37 / 37`（`errors: 0`） |
| 最终动作一致率（`final_action_agreement`） | **`36 / 37`（`97.30%`）** |
| 最终分类一致率（`final_category_agreement`） | **`36 / 37`（`97.30%`）** |
| 危险误删样本（`unsafe_trash_ids`） | **`[]`（`0` 封误删）** |
| 单封请求中位延迟（`observed_median_seconds`） | `1.0221 s` |
| 总输入 Token / 输出 Token | `223,506` / `0` |
| 按 `$0.10 / 1M` 输入单价折算成本 | `$0.022351`（约 `$0.00060 / 封`） |

### 唯一分歧说明（保守护栏拦截）

- **`open-07`（`Re: sylpheed-claws`）**：参考标签为 `trash / social`（`RPM-List` 公共邮件列表讨论），模型原始方向建议同样为 `trash / social`（`social_digest = 0.973`）。由于发件人以第一人称讨论维护与构建 RPM 软件包的细节，受保护话题 `topic_work` 得分为 `0.164`（略高于防误删保护门槛 `0.15`），本地状态机触发 `protection_conflict` 护栏，将其保守拦截为 `review / review`，确保宁可多一次人工确认也不误删潜在工作讨论。
