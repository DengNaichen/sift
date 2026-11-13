import {
  asMessageId,
  type DeckSnapshot,
  type HandledItem,
  type MailAccount,
  type MailItem,
} from './mailAdapter'

export const ACCOUNTS = {
  work: {
    id: 'work',
    label: '工作',
    address: 'lin@studio-north.cn',
  },
  personal: {
    id: 'personal',
    label: '个人',
    address: 'lin.personal@icloud.com',
  },
} satisfies Record<string, MailAccount>

const MIN = 60_000
const at = (now: number, minutesAgo: number) => new Date(now - minutesAgo * MIN).toISOString()

/** 主舞台：5 张代表性的待拍板邮件 */
function seedQueue(now: number): MailItem[] {
  return [
    {
      id: asMessageId('CAH7x9k2Lq@mail.gmail.com'),
      from: { name: '林晓', address: 'linxiao@studio-north.cn' },
      account: ACCOUNTS.work,
      subject: '周四下午能一起过下 Q1 定价页改版吗？',
      receivedAt: at(now, 26),
      attachments: [],
      plainText: `嗨，

上周你提的「把年付折扣做成默认选项」我跟 Mia 聊过了，她觉得可以先在定价页上做个 A/B。

想约你半小时一起过一下新的线框稿，顺便定一下文案口径：
- 周四 15:00–15:30
- 或者周五 10:00 之后都行

你回我哪个时段方便就好，我来发会议邀请。线框稿我先放在 Figma 的「Pricing v3」页里了。

林晓`,
      meta: {
        kind: 'human',
        badge: '真人来信',
        intent: '需回复',
        evidence: '你回我哪个时段方便就好，我来发会议邀请。',
        confidence: 0.99,
      },
    },
    {
      id: asMessageId('20261112.policy.8812@notify.driftbox.io'),
      from: { name: 'Driftbox 团队', address: 'hello@notify.driftbox.io' },
      account: ACCOUNTS.personal,
      subject: 'Driftbox 秋季产品周报：协作白板、离线模式与更多',
      receivedAt: at(now, 74),
      attachments: [],
      plainText: `Driftbox 秋季产品周报

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

退订此类邮件`,
      meta: {
        kind: 'policy',
        badge: '条款/额度变更',
        intent: '需决定',
        evidence: '自 2026 年 12 月 15 日起，免费版的存储空间将从 10 GB 调整为 2 GB。',
        confidence: 0.93,
      },
    },
    {
      id: asMessageId('contract-v3-0b71@hengzhi-law.com'),
      from: { name: '周律师 · 恒致律所', address: 'zhou.yi@hengzhi-law.com' },
      account: ACCOUNTS.work,
      subject: '【待确认】2027 年度设计服务合同（第三版）',
      receivedAt: at(now, 138),
      attachments: [
        { name: '设计服务合同_2027_v3.pdf', size: '1.2 MB', kind: 'pdf' },
        { name: '修订对照表.pdf', size: '286 KB', kind: 'pdf' },
      ],
      plainText: `您好，

附件是甲方法务回传的第三版合同及修订对照表，主要变动如下：

1. 第 7.2 条付款节点：首付款比例由 40% 调整为 30%，尾款由验收后 15 个工作日内支付调整为 30 个工作日内支付。
2. 第 11 条知识产权：新增「乙方可将项目成果用于作品集展示，但需在项目上线 6 个月后」。
3. 其余条款无实质变动。

我们的意见：第 7.2 条对您现金流有一定影响，建议争取首付 35%。如无异议，请于本周五（11 月 14 日）前回复确认，我们将安排电子签署。

周毅
恒致律师事务所`,
      meta: {
        kind: 'contract',
        badge: '合同 · 含附件',
        intent: '需确认',
        evidence: '如无异议，请于本周五（11 月 14 日）前回复确认，我们将安排电子签署。',
        confidence: 0.97,
      },
    },
    {
      id: asMessageId('stmt-202611-3391@cmbchina.com'),
      from: { name: '招商银行信用卡', address: 'ccsvc@message.cmbchina.com' },
      account: ACCOUNTS.personal,
      subject: '您的 11 月信用卡电子账单',
      receivedAt: at(now, 312),
      attachments: [],
      plainText: `尊敬的客户：

您 11 月账单已出。
本期应还金额：¥8,432.17
最低还款额：¥843.22
到期还款日：2026 年 11 月 25 日

本期主要交易：
11/03  AMAZON WEB SERVICES  USD 289.40  折合 ¥2,084.61
11/06  美团外卖  ¥68.50
11/09  中国国航  ¥2,940.00
……

温馨提示：境外交易可能产生货币转换费。`,
      meta: {
        kind: 'billing',
        badge: '账单异动',
        intent: '需核对',
        evidence: '11/03  AMAZON WEB SERVICES  USD 289.40  折合 ¥2,084.61',
        confidence: 0.88,
      },
    },
    {
      id: asMessageId('invite-aips-2026-77a1@events.huodongxing.com'),
      from: { name: '王瑶 via 活动行', address: 'noreply@events.huodongxing.com' },
      account: ACCOUNTS.work,
      subject: '邀请函｜2026 AI 产品峰会 · 闭门圆桌（深圳）',
      receivedAt: at(now, 540),
      attachments: [],
      plainText: `Hi，

我是王瑶，今年负责 AI 产品峰会闭门圆桌的嘉宾邀请。上次在杭州的 Design Day 跟你聊过「AI 时代的收件箱」，印象很深。

圆桌主题：「把注意力还给用户：AI 原生工具的克制设计」
时间：12 月 3 日（周三）14:00–17:00
地点：深圳南山 · 科兴科学园
规模：约 20 人，不对外售票

这是你的专属嘉宾码：AIPS-VIP-3K7Q（含当晚晚宴）

如果方便，请在 11 月 20 日前通过下方链接确认。

王瑶
——
本邮件由活动行代发 · 退订`,
      meta: {
        kind: 'uncertain',
        badge: '待你拍板',
        confidence: 0.76,
      },
    },
  ]
}

type Row = [
  id: string,
  account: MailAccount,
  name: string,
  address: string,
  subject: string,
  body: string,
  category: string,
  probability: number,
  minutesAgo: number,
]

const toHandled =
  (now: number, disposition: HandledItem['disposition']) =>
  ([id, account, name, address, subject, body, category, probability, ago]: Row): HandledItem => ({
    id: asMessageId(id),
    from: { name, address },
    account,
    subject,
    receivedAt: at(now, ago + 1),
    plainText: body,
    attachments: [],
    disposition,
    category,
    probability,
    handledAt: at(now, ago),
  })

/** 自动处理：通知类直接归档，推广类移入废纸篓 */
function seedHandled(now: number): HandledItem[] {
  const archived: Row[] = [
    ['otp-839201@github.com', ACCOUNTS.work, 'GitHub', 'noreply@github.com', '[GitHub] Please verify your device', 'Hey there!\n\nA sign in attempt requires further verification because we did not recognize your device. To complete the sign in, enter the verification code on the unrecognized device.\n\nVerification code: 839201\n\nIf you did not attempt to sign in to your account, your password may be compromised.\n\nThanks,\nThe GitHub Team', '验证码', 0.99, 2],
    ['sf-SF1428833901276@sf-express.com', ACCOUNTS.personal, '顺丰速运', 'noreply@sf-express.com', '您的快件正在派送中', '您好，您的快件 SF1428833901276 正在派送中，派送员：张师傅，电话 138****2210。\n\n如需改约派送时间，请在顺丰速运小程序中操作。', '物流通知', 0.98, 48],
    ['invoice-2026-11-cf@billing.cloudflare.com', ACCOUNTS.work, 'Cloudflare', 'billing@cloudflare.com', 'Your Cloudflare invoice for November 2026', 'Hi,\n\nYour invoice for November 2026 is now available.\n\nWorkers Paid — $20.00\nTotal charged to Visa •••• 4417: $20.00\n\nYou can view and download your invoice from the Billing section of the dashboard.', '账单通知', 0.97, 95],
    ['renewal-notice-7781@linear.app', ACCOUNTS.work, 'Linear', 'billing@linear.app', 'Your Linear plan renews on Nov 19', 'Hi,\n\nThis is a reminder that your Linear Standard plan (12 seats) will renew on November 19, 2026 for $96.00.\n\nNo action is needed if you would like to continue.', '账单通知', 0.93, 410],
  ]
  const trashed: Row[] = [
    ['jd-1111-return@newsletter.jd.com', ACCOUNTS.personal, '京东', 'newsletter@jd.com', '双 11 返场最后 48 小时｜Apple 产品至高立减 1500', '你关注的 AirPods Pro 再降 ¥200，叠加 PLUS 会员券再减 ¥100。\n\n活动截至 11 月 14 日 23:59。\n\n退订', '营销推广', 0.99, 12],
    ['li-digest-2026-11-12@linkedin.com', ACCOUNTS.work, 'LinkedIn', 'messages-noreply@linkedin.com', '本周有 12 人查看了你的个人资料', '看看都有谁在关注你——升级 Premium 解锁完整名单。\n\n退订', '社交通知', 0.96, 31],
    ['ctrip-fare-8812@ctrip.com', ACCOUNTS.personal, '携程旅行', 'promo@ctrip.com', '上海 → 东京 ¥1,280 起，元旦机票早鸟开抢', '你搜索过的航线有新低价，限时 3 天。\n\n退订', '营销推广', 0.97, 58],
    ['medium-daily-1112@medium.com', ACCOUNTS.work, 'Medium Daily Digest', 'noreply@medium.com', 'The Quiet Death of the Inbox — and 5 more stories', 'Stories from Design, Productivity and AI, picked for you.\n\nUnsubscribe', '资讯订阅', 0.94, 83],
    ['sbux-reward-55@starbucks.com.cn', ACCOUNTS.personal, '星巴克', 'rewards@starbucks.com.cn', '你的「星」礼包已到账，本周饮品买一赠一', '会员专享：周五前任意大杯饮品买一赠一。\n\n退订', '营销推广', 0.98, 126],
    ['uniqlo-hk-2026w@uniqlo.cn', ACCOUNTS.personal, '优衣库', 'news@uniqlo.cn', '新品上市 | HEATTECH 极暖系列，入冬必备', '本周限定价 ¥79 起，会员额外 95 折。\n\n退订', '营销推广', 0.99, 190],
    ['geekbang-webinar-0912@geekbang.org', ACCOUNTS.work, '极客时间', 'event@geekbang.org', '直播预约｜大模型应用落地的 7 个误区', '本周四 20:00，前 500 名预约赠送电子书。\n\n退订', '营销推广', 0.91, 247],
    ['ph-daily-20261112@producthunt.com', ACCOUNTS.work, 'Product Hunt Daily', 'hello@digest.producthunt.com', '🏆 Top 5 today: Inbox agents are back', 'Today’s winners include three AI email clients and a calendar that schedules itself.\n\nUnsubscribe', '资讯订阅', 0.95, 305],
  ]
  return [...archived.map(toHandled(now, 'archived')), ...trashed.map(toHandled(now, 'trashed'))]
}

export function seedDeck(now: number): DeckSnapshot {
  return { queue: seedQueue(now), handled: seedHandled(now) }
}

type IncomingTemplate = Omit<MailItem, 'id' | 'receivedAt'>

/** 「模拟收到新邮件」按顺序轮流投递 */
export const incomingPool: IncomingTemplate[] = [
  {
    from: { name: '妈妈', address: 'liu.hongmei@163.com' },
    account: ACCOUNTS.personal,
    subject: '周末回家吃饭吗？',
    attachments: [{ name: '体检报告_2026.pdf', size: '2.3 MB', kind: 'pdf' }],
    plainText: `周六你爸生日，你姐一家都回来。你要是能回来，我就多买条鱼。

另外你上次说的那个体检报告，我放在附件里了，你帮我看看那个甲状腺的数是不是高了。

妈`,
    meta: {
      kind: 'human',
      badge: '真人来信',
      intent: '需回复',
      evidence: '周六你爸生日，你姐一家都回来。',
      confidence: 0.99,
    },
  },
  {
    from: { name: 'Vercel', address: 'notifications@vercel.com' },
    account: ACCOUNTS.work,
    subject: 'Your team has used 82% of included Edge Requests',
    attachments: [],
    plainText: `Hi,

Your team "studio-north" has used 82% of the included Edge Requests for the current billing cycle (ends Nov 30).

At the current rate, you will exceed the included amount around Nov 21. Additional usage is billed at $2 per 1M requests.

— The Vercel Team`,
    meta: {
      kind: 'policy',
      badge: '额度预警',
      evidence: 'At the current rate, you will exceed the included amount around Nov 21.',
      confidence: 0.91,
    },
  },
  {
    from: { name: '陈默', address: 'chenmo@studio-north.cn' },
    account: ACCOUNTS.work,
    subject: 'Re: 首页插画外包报价',
    attachments: [{ name: '报价单_插画_v2.xlsx', size: '42 KB', kind: 'sheet' }],
    plainText: `收到，我跟对方又压了一轮价：

- 原报价 ¥28,000（6 张）
- 新报价 ¥23,500（6 张 + 1 张 Banner 延展）

对方要求下周一前定下来，不然要排到 1 月了。你看行的话我就回复对方签了。

陈默`,
    meta: {
      kind: 'human',
      badge: '真人来信',
      intent: '需确认',
      evidence: '对方要求下周一前定下来，不然要排到 1 月了。',
      confidence: 0.98,
    },
  },
  {
    from: { name: '物业服务中心', address: 'service@vanke-wy.com' },
    account: ACCOUNTS.personal,
    subject: '关于 12 月起调整物业服务费标准的公示',
    attachments: [{ name: '收费标准公示.pdf', size: '540 KB', kind: 'pdf' }],
    plainText: `各位业主：

经业主大会表决通过，自 2026 年 12 月 1 日起，住宅物业服务费由 ¥3.2/㎡·月 调整为 ¥3.8/㎡·月。

如有疑问请于 11 月 25 日前联系物业服务中心。`,
    meta: {
      kind: 'uncertain',
      badge: '待你拍板',
      evidence: '住宅物业服务费由 ¥3.2/㎡·月 调整为 ¥3.8/㎡·月。',
      confidence: 0.81,
    },
  },
  {
    from: { name: 'Apple', address: 'no_reply@email.apple.com' },
    account: ACCOUNTS.personal,
    subject: '你的 iCloud+ 订阅价格即将调整',
    attachments: [],
    plainText: `你好，

自 2027 年 1 月 1 日起，你的 iCloud+ 200GB 方案价格将从 ¥21/月 调整为 ¥25/月。

如不希望继续订阅，你可以随时在设置中取消。`,
    meta: {
      kind: 'policy',
      badge: '涨价提醒',
      intent: '需决定',
      evidence: '你的 iCloud+ 200GB 方案价格将从 ¥21/月 调整为 ¥25/月。',
      confidence: 0.95,
    },
  },
  {
    from: { name: 'Sarah Kim', address: 'sarah@northwind.design' },
    account: ACCOUNTS.work,
    subject: 'Quick intro — design systems collab?',
    attachments: [],
    plainText: `Hi there,

Jason from Figma suggested I reach out. We're putting together a small working group on design tokens for CJK typography and would love your take.

Would a 30-min call next week work? Happy to adapt to Shanghai time.

Best,
Sarah`,
    meta: {
      kind: 'uncertain',
      badge: '待你拍板',
      confidence: 0.72,
    },
  },
]
