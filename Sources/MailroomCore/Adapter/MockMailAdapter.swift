import AppKit
import Foundation

public actor MockMailAdapter: MailAdapter {
    public nonisolated let sourceLabel: String = "演示数据"
    public nonisolated let supportsDemoControls: Bool = true

    private enum Mailbox { case inbox, archive, trash }
    private struct StoredState {
        var mailbox: Mailbox
        var flagged: Bool
        var read: Bool
    }

    private var deck: DeckSnapshot
    private var store: [MessageId: StoredState] = [:]
    private var incomingCursor = 0
    private var incomingSerial = 0

    public init(now: Date = Date()) {
        let initial = MockSeedData.seedDeck(now: now)
        self.deck = initial
        self.store = Self.buildStore(for: initial)
    }

    private static func buildStore(for deck: DeckSnapshot) -> [MessageId: StoredState] {
        var map: [MessageId: StoredState] = [:]
        for m in deck.queue {
            map[m.id] = StoredState(mailbox: .inbox, flagged: false, read: false)
        }
        for h in deck.handled {
            map[h.id] = StoredState(
                mailbox: h.disposition == .archived ? .archive : .trash,
                flagged: false,
                read: true
            )
        }
        return map
    }

    private func reindex() {
        store = Self.buildStore(for: deck)
    }

    public func fetchDeck() async throws -> DeckSnapshot {
        let filteredQueue = deck.queue.filter { m in
            guard let st = store[m.id] else { return false }
            return st.mailbox == .inbox && !st.read
        }
        let filteredHandled = deck.handled.filter { h in
            store[h.id]?.mailbox != .inbox
        }
        return DeckSnapshot(queue: filteredQueue, handled: filteredHandled)
    }

    public func archive(id: MessageId) async throws {
        store[id] = StoredState(mailbox: .archive, flagged: false, read: true)
    }

    public func flagImportant(id: MessageId) async throws {
        store[id] = StoredState(mailbox: .inbox, flagged: true, read: true)
    }

    public func moveToTrash(id: MessageId, reason: TrashReason) async throws {
        store[id] = StoredState(mailbox: .trash, flagged: false, read: true)
        if reason == .userPromo,
           let mail = deck.queue.first(where: { $0.id == id }),
           !deck.handled.contains(where: { $0.id == id }) {
            deck.handled.append(MailAdapterFunctions.toManualHandled(mail))
        }
    }

    public func restore(id: MessageId) async throws {
        store[id] = StoredState(mailbox: .inbox, flagged: false, read: false)
    }

    public func rescue(id: MessageId) async throws -> MailItem {
        guard let handled = deck.handled.first(where: { $0.id == id }) else {
            throw NSError(domain: "MockMailAdapter", code: 404, userInfo: [NSLocalizedDescriptionKey: "未找到邮件 \(id)"])
        }
        store[id] = StoredState(mailbox: .inbox, flagged: false, read: false)
        let card = MailAdapterFunctions.rescuedCard(from: handled)
        deck.queue.removeAll { $0.id == id }
        deck.queue.append(card)
        return card
    }

    public func openInNativeMail(id: MessageId) async throws -> String {
        MailAdapterFunctions.nativeMailURLString(for: id)
    }

    public func resetDemo() async throws {
        deck = MockSeedData.seedDeck(now: Date())
        incomingCursor = 0
        reindex()
    }

    public func simulateIncoming(count: Int) async throws -> [MailItem] {
        let now = Date()
        var added: [MailItem] = []
        let pool = MockSeedData.incomingPool
        for i in 0..<count {
            let tpl = pool[incomingCursor % pool.count]
            incomingCursor += 1
            incomingSerial += 1
            let id = MessageId("incoming-\(incomingSerial)-\(Int(now.timeIntervalSince1970))@mock.local")
            let content = MailContent(
                id: id,
                from: tpl.from,
                account: tpl.account,
                subject: tpl.subject,
                receivedAt: now.addingTimeInterval(TimeInterval(-i * 40)),
                plainText: tpl.plainText,
                attachments: tpl.attachments,
                isReadInMail: false
            )
            let item = MailItem(content: content, meta: tpl.meta)
            deck.queue.append(item)
            store[id] = StoredState(mailbox: .inbox, flagged: false, read: false)
            added.append(item)
        }
        return added
    }
}

public enum MockSeedData {
    public static let workAccount = MailAccount(id: "work", label: "工作", address: "lin@studio-north.cn")
    public static let personalAccount = MailAccount(id: "personal", label: "个人", address: "lin.personal@icloud.com")

    private static func minutesAgo(_ now: Date, _ minutes: Double) -> Date {
        now.addingTimeInterval(-minutes * 60.0)
    }

    public static func seedDeck(now: Date) -> DeckSnapshot {
        let queue: [MailItem] = [
            MailItem(
                content: MailContent(
                    id: "CAH7x9k2Lq@mail.gmail.com",
                    from: Sender(name: "林晓", address: "linxiao@studio-north.cn"),
                    account: workAccount,
                    subject: "周四下午能一起过下 Q1 定价页改版吗？",
                    receivedAt: minutesAgo(now, 26),
                    plainText: """
                    嗨，

                    上周你提的「把年付折扣做成默认选项」我跟 Mia 聊过了，她觉得可以先在定价页上做个 A/B。

                    想约你半小时一起过一下新的线框稿，顺便定一下文案口径：
                    - 周四 15:00–15:30
                    - 或者周五 10:00 之后都行

                    你回我哪个时段方便就好，我来发会议邀请。线框稿我先放在 Figma 的「Pricing v3」页里了。

                    林晓
                    """,
                    attachments: []
                ),
                meta: DecisionMeta(
                    kind: .human,
                    badge: "真人来信",
                    confidence: 0.99,
                    intent: "需回复",
                    evidence: "你回我哪个时段方便就好，我来发会议邀请。"
                )
            ),
            MailItem(
                content: MailContent(
                    id: "20261112.policy.8812@notify.driftbox.io",
                    from: Sender(name: "Driftbox 团队", address: "hello@notify.driftbox.io"),
                    account: personalAccount,
                    subject: "Driftbox 秋季产品周报：协作白板、离线模式与更多",
                    receivedAt: minutesAgo(now, 74),
                    plainText: """
                    Driftbox 秋季产品周报

                    1. 协作白板正式上线
                    现在可以在任意文件夹中创建白板，并邀请最多 10 位协作者实时编辑。

                    2. 离线模式改进
                    桌面端现在会智能缓存你最近打开的 200 个文件。

                    3. 全新的移动端分享面板
                    一键生成带有效期的分享链接。

                    4. 免费版方案调整
                    为了持续提供稳定的服务，自 2026 年 12 月 15 日起，免费版的存储空间将从 10 GB 调整为 2 GB。超出部分的文件将保留为只读状态 60 天，之后可能被移除。升级至 Plus（¥18/月）可保留全部空间。

                    感谢你一直以来的支持。
                    Driftbox 团队

                    退订此类邮件
                    """,
                    attachments: []
                ),
                meta: DecisionMeta(
                    kind: .policy,
                    badge: "条款/额度变更",
                    confidence: 0.93,
                    intent: "需决定",
                    evidence: "自 2026 年 12 月 15 日起，免费版的存储空间将从 10 GB 调整为 2 GB。"
                )
            ),
            MailItem(
                content: MailContent(
                    id: "contract-v3-0b71@hengzhi-law.com",
                    from: Sender(name: "周律师 · 恒致律所", address: "zhou.yi@hengzhi-law.com"),
                    account: workAccount,
                    subject: "【待确认】2027 年度设计服务合同（第三版）",
                    receivedAt: minutesAgo(now, 138),
                    plainText: """
                    您好，

                    附件是甲方法务回传的第三版合同及修订对照表，主要变动如下：

                    1. 第 7.2 条付款节点：首付款比例由 40% 调整为 30%，尾款由验收后 15 个工作日内支付调整为 30 个工作日内支付。
                    2. 第 11 条知识产权：新增「乙方可将项目成果用于作品集展示，但需在项目上线 6 个月后」。
                    3. 其余条款无实质变动。

                    我们的意见：第 7.2 条对您现金流有一定影响，建议争取首付 35%。如无异议，请于本周五（11 月 14 日）前回复确认，我们将安排电子签署。

                    周毅
                    恒致律师事务所
                    """,
                    attachments: [
                        Attachment(name: "设计服务合同_2027_v3.pdf", size: "1.2 MB", kind: .pdf),
                        Attachment(name: "修订对照表.pdf", size: "286 KB", kind: .pdf)
                    ]
                ),
                meta: DecisionMeta(
                    kind: .contract,
                    badge: "合同 · 含附件",
                    confidence: 0.97,
                    intent: "需确认",
                    evidence: "如无异议，请于本周五（11 月 14 日）前回复确认，我们将安排电子签署。"
                )
            ),
            MailItem(
                content: MailContent(
                    id: "stmt-202611-3391@cmbchina.com",
                    from: Sender(name: "招商银行信用卡", address: "ccsvc@message.cmbchina.com"),
                    account: personalAccount,
                    subject: "您的 11 月信用卡电子账单",
                    receivedAt: minutesAgo(now, 312),
                    plainText: """
                    尊敬的客户：

                    您 11 月账单已出。
                    本期应还金额：¥8,432.17
                    最低还款额：¥843.22
                    到期还款日：2026 年 11 月 25 日

                    本期主要交易：
                    11/03  AMAZON WEB SERVICES  USD 289.40  折合 ¥2,084.61
                    11/06  美团外卖  ¥68.50
                    11/09  中国国航  ¥2,940.00
                    ……

                    温馨提示：境外交易可能产生货币转换费。
                    """,
                    attachments: []
                ),
                meta: DecisionMeta(
                    kind: .billing,
                    badge: "账单异动",
                    confidence: 0.88,
                    intent: "需核对",
                    evidence: "11/03  AMAZON WEB SERVICES  USD 289.40  折合 ¥2,084.61"
                )
            ),
            MailItem(
                content: MailContent(
                    id: "invite-aips-2026-77a1@events.huodongxing.com",
                    from: Sender(name: "王瑶 via 活动行", address: "noreply@events.huodongxing.com"),
                    account: workAccount,
                    subject: "邀请函｜2026 AI 产品峰会 · 闭门圆桌（深圳）",
                    receivedAt: minutesAgo(now, 540),
                    plainText: """
                    Hi，

                    我是王瑶，今年负责 AI 产品峰会闭门圆桌的嘉宾邀请。上次在杭州的 Design Day 跟你聊过「AI 时代的收件箱」，印象很深。

                    圆桌主题：「把注意力还给用户：AI 原生工具的克制设计」
                    时间：12 月 3 日（周三）14:00–17:00
                    地点：深圳南山 · 科兴科学园
                    规模：约 20 人，不对外售票

                    这是你的专属嘉宾码：AIPS-VIP-3K7Q（含当晚晚宴）

                    如果方便，请在 11 月 20 日前通过下方链接确认。

                    王瑶
                    ——
                    本邮件由活动行代发 · 退订
                    """,
                    attachments: []
                ),
                meta: DecisionMeta(
                    kind: .uncertain,
                    badge: "待你拍板",
                    confidence: 0.76
                )
            )
        ]

        func makeHandled(
            _ id: String, _ acc: MailAccount, _ name: String, _ addr: String,
            _ subject: String, _ body: String, _ disp: Disposition,
            _ cat: String, _ prob: Double, _ ago: Double
        ) -> HandledItem {
            HandledItem(
                content: MailContent(
                    id: MessageId(id),
                    from: Sender(name: name, address: addr),
                    account: acc,
                    subject: subject,
                    receivedAt: minutesAgo(now, ago + 1),
                    plainText: body,
                    attachments: [],
                    isReadInMail: true
                ),
                disposition: disp,
                category: cat,
                probability: prob,
                handledAt: minutesAgo(now, ago)
            )
        }

        let handled: [HandledItem] = [
            makeHandled("otp-839201@github.com", workAccount, "GitHub", "noreply@github.com", "[GitHub] Please verify your device", "Hey there!\n\nA sign in attempt requires further verification because we did not recognize your device.\n\nVerification code: 839201\n\nThanks,\nThe GitHub Team", .archived, "验证码", 0.99, 2),
            makeHandled("sf-SF1428833901276@sf-express.com", personalAccount, "顺丰速运", "noreply@sf-express.com", "您的快件正在派送中", "您好，您的快件 SF1428833901276 正在派送中，派送员：张师傅，电话 138****2210。\n\n如需改约派送时间，请在顺丰速运小程序中操作。", .archived, "物流通知", 0.98, 48),
            makeHandled("invoice-2026-11-cf@billing.cloudflare.com", workAccount, "Cloudflare", "billing@cloudflare.com", "Your Cloudflare invoice for November 2026", "Hi,\n\nYour invoice for November 2026 is now available.\n\nWorkers Paid — $20.00\nTotal charged to Visa •••• 4417: $20.00", .archived, "账单通知", 0.97, 95),
            makeHandled("renewal-notice-7781@linear.app", workAccount, "Linear", "billing@linear.app", "Your Linear plan renews on Nov 19", "Hi,\n\nThis is a reminder that your Linear Standard plan (12 seats) will renew on November 19, 2026 for $96.00.\n\nNo action is needed if you would like to continue.", .archived, "账单通知", 0.93, 410),
            makeHandled("jd-1111-return@newsletter.jd.com", personalAccount, "京东", "newsletter@jd.com", "双 11 返场最后 48 小时｜Apple 产品至高立减 1500", "你关注的 AirPods Pro 再降 ¥200，叠加 PLUS 会员券再减 ¥100。\n\n活动截至 11 月 14 日 23:59。\n\n退订", .trashed, "营销推广", 0.99, 12),
            makeHandled("li-digest-2026-11-12@linkedin.com", workAccount, "LinkedIn", "messages-noreply@linkedin.com", "本周有 12 人查看了你的个人资料", "看看都有谁在关注你——升级 Premium 解锁完整名单。\n\n退订", .trashed, "社交通知", 0.96, 31),
            makeHandled("ctrip-fare-8812@ctrip.com", personalAccount, "携程旅行", "promo@ctrip.com", "上海 → 东京 ¥1,280 起，元旦机票早鸟开抢", "你搜索过的航线有新低价，限时 3 天。\n\n退订", .trashed, "营销推广", 0.97, 58),
            makeHandled("medium-daily-1112@medium.com", workAccount, "Medium Daily Digest", "noreply@medium.com", "The Quiet Death of the Inbox — and 5 more stories", "Stories from Design, Productivity and AI, picked for you.\n\nUnsubscribe", .trashed, "资讯订阅", 0.94, 83),
            makeHandled("sbux-reward-55@starbucks.com.cn", personalAccount, "星巴克", "rewards@starbucks.com.cn", "你的「星」礼包已到账，本周饮品买一赠一", "会员专享：周五前任意大杯饮品买一赠一。\n\n退订", .trashed, "营销推广", 0.98, 126),
            makeHandled("uniqlo-hk-2026w@uniqlo.cn", personalAccount, "优衣库", "news@uniqlo.cn", "新品上市 | HEATTECH 极暖系列，入冬必备", "本周限定价 ¥79 起，会员额外 95 折。\n\n退订", .trashed, "营销推广", 0.99, 190),
        ]

        return DeckSnapshot(queue: queue, handled: handled)
    }

    public struct IncomingTemplate: Sendable {
        public let from: Sender
        public let account: MailAccount
        public let subject: String
        public let attachments: [Attachment]
        public let plainText: String
        public let meta: DecisionMeta
    }

    public static let incomingPool: [IncomingTemplate] = [
        IncomingTemplate(
            from: Sender(name: "妈妈", address: "liu.hongmei@163.com"),
            account: personalAccount,
            subject: "周末回家吃饭吗？",
            attachments: [Attachment(name: "体检报告_2026.pdf", size: "2.3 MB", kind: .pdf)],
            plainText: "周六你爸生日，你姐一家都回来。你要是能回来，我就多买条鱼。\n\n另外你上次说的那个体检报告，我放在附件里了，你帮我看看那个甲状腺的数是不是高了。\n\n妈",
            meta: DecisionMeta(kind: .human, badge: "真人来信", confidence: 0.99, intent: "需回复", evidence: "周六你爸生日，你姐一家都回来。")
        ),
        IncomingTemplate(
            from: Sender(name: "Vercel", address: "notifications@vercel.com"),
            account: workAccount,
            subject: "Your team has used 82% of included Edge Requests",
            attachments: [],
            plainText: "Hi,\n\nYour team \"studio-north\" has used 82% of the included Edge Requests for the current billing cycle (ends Nov 30).\n\nAt the current rate, you will exceed the included amount around Nov 21. Additional usage is billed at $2 per 1M requests.\n\n— The Vercel Team",
            meta: DecisionMeta(kind: .policy, badge: "额度预警", confidence: 0.91, evidence: "At the current rate, you will exceed the included amount around Nov 21.")
        ),
        IncomingTemplate(
            from: Sender(name: "陈默", address: "chenmo@studio-north.cn"),
            account: workAccount,
            subject: "Re: 首页插画外包报价",
            attachments: [Attachment(name: "报价单_插画_v2.xlsx", size: "42 KB", kind: .sheet)],
            plainText: "收到，我跟对方又压了一轮价：\n\n- 原报价 ¥28,000（6 张）\n- 新报价 ¥23,500（6 张 + 1 张 Banner 延展）\n\n对方要求下周一前定下来，不然要排到 1 月了。你看行的话我就回复对方签了。\n\n陈默",
            meta: DecisionMeta(kind: .human, badge: "真人来信", confidence: 0.98, intent: "需确认", evidence: "对方要求下周一前定下来，不然要排到 1 月了。")
        )
    ]
}
