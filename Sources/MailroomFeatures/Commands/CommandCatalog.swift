import Foundation
import MailroomCore

public enum HudPriority: Int, Comparable, Equatable, Sendable {
    case secondary = 0
    case navigation = 1
    case core = 2

    public static func < (lhs: HudPriority, rhs: HudPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct HudItem: Identifiable, Equatable, Sendable {
    public var id: String { label }
    public let keys: [String]
    public let label: String
    public let disabled: Bool
    public let priority: HudPriority
    public let command: DeckCommand
}

public struct PaletteCommand: Identifiable, Equatable, Sendable {
    public let id: String
    public let group: String
    public let title: String
    public let subtitle: String?
    public let keywords: String
    public let kbd: String?
    public let systemImage: String
    public let command: DeckCommand
}

/// HUD 所需的最小上下文（只读取这些字段，避免 HUD 订阅无关状态）
public struct HudContext: Equatable, Sendable {
    public var activeRow: FolderRow?
    public var hasRows: Bool
    public var folder: FolderId
    public var canUndo: Bool
}

/// 命令面板所需的完整上下文快照
public struct PaletteContext: Sendable {
    public var activeRow: FolderRow?
    public var aiReasoningExpanded: Bool
    public var inspectorRailOpen: Bool
    public var preferPlainText: Bool
    public var allowedRemoteImageIds: Set<MessageId>
    public var accounts: [MailAccount]
    public var counts: [FolderId: Int]
    public var queue: [MailItem]
    public var handled: [HandledItem]
    public var sourceMode: DataSourceMode
    public var settingsOpen: Bool
    public var canUndo: Bool
    public var sidebarCollapsed: Bool
    public var themeMode: ThemeMode
}

/// 唯一的命令目录：根据上下文给出每个命令的可用性、标题、快捷键、图标与分组。纯函数。
public enum CommandCatalog {
    public static func hudItems(_ ctx: HudContext) -> [HudItem] {
        let inboxMode = ctx.folder.isInboxFolder
        let canActInbox: Bool = {
            if case .inbox = ctx.activeRow { return true }
            return false
        }()
        let canRescue: Bool = {
            if case .handled = ctx.activeRow { return true }
            return false
        }()

        var list: [HudItem] = [
            HudItem(keys: ["J", "K"], label: "切换", disabled: !ctx.hasRows, priority: .navigation, command: .moveFocus(1))
        ]
        if inboxMode {
            list.append(HudItem(keys: ["Space"], label: "归档", disabled: !canActInbox, priority: .core, command: .card(.archive, nil)))
            list.append(HudItem(keys: ["⇧K"], label: "保留", disabled: !canActInbox, priority: .core, command: .card(.keep, nil)))
            list.append(HudItem(keys: ["⌫"], label: "推广", disabled: !canActInbox, priority: .core, command: .card(.trash, nil)))
        } else if ctx.folder != .kept {
            list.append(HudItem(keys: ["R"], label: "拉回待处理", disabled: !canRescue, priority: .core, command: .rescueFocused))
        }
        list.append(HudItem(keys: ["↵"], label: "Mail", disabled: ctx.activeRow == nil, priority: .secondary, command: .openInNativeMail))
        if ctx.canUndo {
            list.append(HudItem(keys: ["Z"], label: "撤销", disabled: false, priority: .secondary, command: .undo))
        }
        list.append(HudItem(keys: ["⌘K"], label: "命令", disabled: false, priority: .secondary, command: .openPalette))
        return list
    }

    public static func paletteCommands(_ ctx: PaletteContext) -> [PaletteCommand] {
        var list: [PaletteCommand] = []

        if let row = ctx.activeRow {
            switch row {
            case .inbox(let mail):
                let sub = mail.subject
                list.append(PaletteCommand(id: "archive", group: "当前邮件", title: "阅毕归档", subtitle: sub, keywords: "archive 归档", kbd: "Space", systemImage: "archivebox", command: .card(.archive, mail.id)))
                list.append(PaletteCommand(id: "keep", group: "当前邮件", title: "重要保留", subtitle: sub, keywords: "flag keep 保留 标旗", kbd: "⇧K", systemImage: "flag", command: .card(.keep, mail.id)))
                list.append(PaletteCommand(id: "trash", group: "当前邮件", title: "判为推广并移入废纸篓", subtitle: sub, keywords: "trash delete 推广 废纸篓", kbd: "⌫", systemImage: "trash", command: .card(.trash, mail.id)))
                list.append(PaletteCommand(id: "native", group: "当前邮件", title: "在 Apple Mail 中打开", subtitle: nil, keywords: "open mail 打开", kbd: "↵", systemImage: "arrow.up.right", command: .openInNativeMail))
            case .handled(let item):
                list.append(PaletteCommand(id: "rescue", group: "当前邮件", title: "拉回待处理", subtitle: item.subject, keywords: "rescue 拉回", kbd: "R", systemImage: "arrow.uturn.backward", command: .rescueFocused))
                list.append(PaletteCommand(id: "native", group: "当前邮件", title: "在 Apple Mail 中打开", subtitle: nil, keywords: "open mail 打开", kbd: "↵", systemImage: "arrow.up.right", command: .openInNativeMail))
            case .kept(let mail):
                list.append(PaletteCommand(id: "native", group: "当前邮件", title: "在 Apple Mail 中打开", subtitle: mail.subject, keywords: "open mail 打开", kbd: "↵", systemImage: "arrow.up.right", command: .openInNativeMail))
            }
            list.append(
                PaletteCommand(
                    id: "toggle-ai-strip",
                    group: "当前邮件",
                    title: ctx.aiReasoningExpanded ? "收起正文顶部 AI 判据条" : "展开正文顶部 AI 判据条",
                    subtitle: nil,
                    keywords: "ai reason evidence 判据 引证 确信度",
                    kbd: "I",
                    systemImage: "sparkles",
                    command: .toggleAIReasoning
                )
            )
            list.append(
                PaletteCommand(
                    id: "toggle-inspector-rail",
                    group: "当前邮件",
                    title: ctx.inspectorRailOpen ? "关闭右侧洞察侧栏" : "打开右侧洞察侧栏",
                    subtitle: "查看校准确信度进度条、安全护栏与同线程历史往来",
                    keywords: "inspector rail sidebar 洞察栏 侧栏 线程",
                    kbd: "⇧I",
                    systemImage: "sidebar.right",
                    command: .toggleInspectorRail
                )
            )
            if row.content.htmlBody != nil {
                list.append(
                    PaletteCommand(
                        id: "toggle-body-format",
                        group: "当前邮件",
                        title: ctx.preferPlainText ? "切换到富文本排版视图" : "切换到纯文本视图",
                        subtitle: nil,
                        keywords: "html plain text 富文本 纯文本 排版",
                        kbd: nil,
                        systemImage: ctx.preferPlainText ? "richtext.page" : "doc.plaintext",
                        command: .toggleBodyFormat
                    )
                )
                if !ctx.preferPlainText && row.content.hasRemoteImages && !ctx.allowedRemoteImageIds.contains(row.id) {
                    list.append(
                        PaletteCommand(
                            id: "allow-remote-images",
                            group: "当前邮件",
                            title: "加载并显示当前邮件的远程图片",
                            subtitle: "仅对本封邮件放行外部图片资源",
                            keywords: "images remote 显示图片 远程图片",
                            kbd: nil,
                            systemImage: "photo",
                            command: .allowRemoteImages(row.id)
                        )
                    )
                }
            }
        }

        if ctx.accounts.count > 1 {
            list.append(PaletteCommand(id: "acc-all", group: "邮箱范围", title: "查看全部邮箱", subtitle: nil, keywords: "account all 全部邮箱", kbd: nil, systemImage: "tray", command: .setAccountScope(.all)))
            for acc in ctx.accounts {
                list.append(PaletteCommand(id: "acc-\(acc.id)", group: "邮箱范围", title: "只看「\(acc.label)」邮箱", subtitle: acc.address, keywords: "account \(acc.label) \(acc.address)", kbd: nil, systemImage: "envelope", command: .setAccountScope(.account(acc.id))))
            }
        }

        for def in FolderDef.all {
            let cnt = ctx.counts[def.id] ?? 0
            let icon = def.id == .trashed ? "trash" : def.id == .archived ? "archivebox" : def.id == .kept ? "flag" : "tray"
            list.append(PaletteCommand(id: "folder-\(def.id.rawValue)", group: "分拣夹", title: "前往：\(def.label)", subtitle: "\(cnt) 封", keywords: def.label, kbd: def.shortcut, systemImage: icon, command: .setFolder(def.id)))
        }

        for m in ctx.queue {
            list.append(PaletteCommand(
                id: "mail-\(m.id.rawValue)",
                group: "待你处理",
                title: m.subject,
                subtitle: "\(m.from.name) · \(m.account.label)",
                keywords: "\(m.from.address) \(m.account.address) \(m.meta.badge) \(m.meta.intent ?? "") \(m.plainText.prefix(300))",
                kbd: nil,
                systemImage: "envelope",
                command: .revealMail(m.id, in: .inbox)
            ))
        }

        for h in ctx.handled {
            list.append(PaletteCommand(
                id: "handled-\(h.id.rawValue)",
                group: "自动处理",
                title: h.subject,
                subtitle: "\(h.from.name) · \(h.category) · \(h.account.label)",
                keywords: "\(h.from.address) \(h.account.address) \(h.plainText.prefix(200))",
                kbd: nil,
                systemImage: "envelope.badge",
                command: .revealMail(h.id, in: h.disposition == .archived ? .archived : .trashed)
            ))
        }

        // 数据源与系统命令
        if ctx.sourceMode == .appleMail {
            list.append(PaletteCommand(id: "sync-now", group: "数据源", title: "立即重新同步 Apple Mail", subtitle: nil, keywords: "sync refresh 同步 刷新", kbd: "⌘R", systemImage: "arrow.clockwise", command: .syncNow))
            list.append(PaletteCommand(id: "switch-demo", group: "数据源", title: "切换到内置演示数据", subtitle: "不读写本机邮件，用于界面演示", keywords: "demo mock 演示", kbd: nil, systemImage: "sparkles", command: .switchToDemo))
        } else {
            list.append(PaletteCommand(id: "switch-live", group: "数据源", title: "接入本机 Apple Mail 真机收件箱", subtitle: "只读同步 Envelope Index + AppleEvent 写回", keywords: "apple mail live 真机 接入", kbd: nil, systemImage: "tray.full", command: .switchToLive))
            list.append(PaletteCommand(id: "sim", group: "演示", title: "模拟收到 3 封新邮件", subtitle: nil, keywords: "demo 模拟收到", kbd: nil, systemImage: "tray.and.arrow.down", command: .simulateIncoming))
            list.append(PaletteCommand(id: "reset", group: "演示", title: "重置演示数据", subtitle: nil, keywords: "demo reset 重置", kbd: nil, systemImage: "arrow.counterclockwise", command: .resetDemo))
        }

        for sec in SettingsSection.allCases {
            list.append(
                PaletteCommand(
                    id: "settings-\(sec.rawValue)",
                    group: "设置",
                    title: "设置：\(sec.title)",
                    subtitle: nil,
                    keywords: "settings 设置 \(sec.searchKeywords)",
                    kbd: sec == .accounts ? "⌘," : nil,
                    systemImage: sec.iconName,
                    command: .openSettings(sec)
                )
            )
        }
        if ctx.settingsOpen {
            list.insert(
                PaletteCommand(
                    id: "close-settings",
                    group: "设置",
                    title: "返回收件箱",
                    subtitle: nil,
                    keywords: "inbox back 返回 收件箱 关闭设置",
                    kbd: "esc",
                    systemImage: "arrow.left",
                    command: .closeSettings
                ),
                at: 0
            )
        }

        if ctx.canUndo {
            list.append(PaletteCommand(id: "undo", group: "系统", title: "撤销上一步", subtitle: nil, keywords: "undo 撤销", kbd: "Z", systemImage: "arrow.uturn.backward", command: .undo))
        }
        list.append(PaletteCommand(id: "sidebar", group: "系统", title: ctx.sidebarCollapsed ? "展开左侧边栏" : "收起左侧边栏", subtitle: nil, keywords: "sidebar 侧边栏", kbd: "[", systemImage: "sidebar.left", command: .toggleSidebar))
        list.append(PaletteCommand(id: "theme", group: "系统", title: ctx.themeMode == .dark ? "切换到浅色模式" : "切换到深色模式", subtitle: nil, keywords: "theme dark light 主题 深色 浅色", kbd: nil, systemImage: ctx.themeMode == .dark ? "sun.max" : "moon", command: .toggleTheme))

        return list
    }
}
