import AppKit
import Foundation
import Observation
import SwiftUI
import MailroomCore

public enum DataSourceMode: String, Sendable {
    case appleMail
    case demo
}

public struct HudItem: Identifiable {
    public var id: String { label }
    public let keys: [String]
    public let label: String
    public let disabled: Bool
    public let action: () -> Void
}

public struct PaletteCommand: Identifiable {
    public let id: String
    public let group: String
    public let title: String
    public let subtitle: String?
    public let keywords: String
    public let kbd: String?
    public let systemImage: String
    public let run: () -> Void
}

@MainActor
@Observable
public final class DeckViewModel {
    public private(set) var state = DeckState()
    public private(set) var accessStatus: MailAccessStatus
    public private(set) var sourceMode: DataSourceMode
    public var themePreference: ThemePreference {
        didSet {
            UserDefaults.standard.set(themePreference.rawValue, forKey: "mailroom-theme-pref")
        }
    }
    public var themeMode: ThemeMode {
        didSet {
            UserDefaults.standard.set(themeMode.rawValue, forKey: "mailroom-theme")
        }
    }
    public var sidebarCollapsed: Bool = false
    public var paletteOpen: Bool = false
    public var settingsOpen: Bool = false
    public let settings = SettingsShellState()
    public var preferPlainText: Bool = false
    public var showKeyboardHUD: Bool {
        didSet {
            UserDefaults.standard.set(showKeyboardHUD, forKey: "mailroom-show-hud")
        }
    }
    public var aiReasoningExpanded: Bool {
        didSet {
            UserDefaults.standard.set(aiReasoningExpanded, forKey: "mailroom-ai-expanded")
        }
    }
    public var inspectorRailOpen: Bool {
        didSet {
            UserDefaults.standard.set(inspectorRailOpen, forKey: "mailroom-inspector-rail")
        }
    }
    public private(set) var allowedRemoteImageIds: Set<MessageId> = []
    public private(set) var hydratingIds: Set<MessageId> = []
    public private(set) var nativeNoticeURL: String? = nil
    public private(set) var errorMessage: String? = nil
    public private(set) var isSyncing: Bool = false

    private var adapter: any MailAdapter
    private var watchTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var rescuingIds: Set<MessageId> = []
    private var attemptedHydrationIds: Set<MessageId> = []

    public init() {
        let systemDark = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if let savedPref = UserDefaults.standard.string(forKey: "mailroom-theme-pref"),
           let pref = ThemePreference(rawValue: savedPref) {
            self.themePreference = pref
            switch pref {
            case .light: self.themeMode = .light
            case .dark: self.themeMode = .dark
            case .system: self.themeMode = systemDark ? .dark : .light
            }
        } else if let saved = UserDefaults.standard.string(forKey: "mailroom-theme"),
                  let mode = ThemeMode(rawValue: saved) {
            self.themePreference = (mode == .dark) ? .dark : .light
            self.themeMode = mode
        } else {
            self.themePreference = .system
            self.themeMode = systemDark ? .dark : .light
        }

        if UserDefaults.standard.object(forKey: "mailroom-show-hud") != nil {
            self.showKeyboardHUD = UserDefaults.standard.bool(forKey: "mailroom-show-hud")
        } else {
            self.showKeyboardHUD = true
        }

        if UserDefaults.standard.object(forKey: "mailroom-ai-expanded") != nil {
            self.aiReasoningExpanded = UserDefaults.standard.bool(forKey: "mailroom-ai-expanded")
        } else {
            self.aiReasoningExpanded = true
        }
        self.inspectorRailOpen = UserDefaults.standard.bool(forKey: "mailroom-inspector-rail")

        let status = MailStoreEnvironment.checkAccess()
        self.accessStatus = status
        if case .ready = status, let live = try? AppleMailAdapter(maxInboxFetch: 100) {
            self.adapter = live
            self.sourceMode = .appleMail
        } else {
            self.adapter = MockMailAdapter()
            self.sourceMode = .demo
        }

        startWatchingAndLoad()
    }

    public var palette: DeckPalette {
        themeMode == .dark ? .dark : .light
    }

    public var preferredColorScheme: ColorScheme? {
        switch themePreference {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    public var visibleRows: [FolderRow] { state.visibleRows }
    public var counts: [FolderId: Int] { state.folderCounts }
    public var accounts: [MailAccount] { state.accounts }

    public var activeIndex: Int? {
        guard let focusId = state.focusId else { return nil }
        return visibleRows.firstIndex(where: { $0.id == focusId })
    }

    public var activeRow: FolderRow? {
        guard let idx = activeIndex else { return nil }
        return visibleRows[idx]
    }

    public var activeAccount: MailAccount? {
        guard case .account(let id) = state.accountScope else { return nil }
        return accounts.first { $0.id == id }
    }

    public var supportsDemoControls: Bool {
        adapter.supportsDemoControls
    }

    // MARK: - Data Loading & Switching

    public func startWatchingAndLoad() {
        watchTask?.cancel()
        let currentAdapter = self.adapter
        Task {
            await reloadSnapshot(initial: true)
        }
        watchTask = Task { [weak self] in
            for await _ in currentAdapter.externalChanges() {
                guard !Task.isCancelled, let self else { break }
                await self.reloadSnapshot(initial: false)
            }
        }
    }

    public func reloadSnapshot(initial: Bool = false) async {
        isSyncing = true
        defer { isSyncing = false }
        do {
            let snapshot = try await adapter.fetchDeck()
            if initial {
                apply(.loaded(snapshot))
            } else {
                apply(.externalSynced(snapshot))
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func recheckAccessAndSwitchToAppleMail() {
        let status = MailStoreEnvironment.checkAccess()
        self.accessStatus = status
        switch status {
        case .ready:
            if let live = try? AppleMailAdapter(maxInboxFetch: 100) {
                self.adapter = live
                self.sourceMode = .appleMail
                self.errorMessage = nil
                self.attemptedHydrationIds.removeAll()
                self.hydratingIds.removeAll()
                startWatchingAndLoad()
            }
        case .fullDiskAccessRequired:
            self.errorMessage = "尚未获得「完全磁盘访问权限」，请在系统设置中勾选本应用后再试。"
        case .mailStoreNotFound:
            self.errorMessage = "未检测到本机 Apple Mail 本地邮箱目录（请先登录一次系统邮件应用）。"
        }
    }

    public func switchToDemoMode() {
        self.adapter = MockMailAdapter()
        self.sourceMode = .demo
        self.errorMessage = nil
        self.attemptedHydrationIds.removeAll()
        self.hydratingIds.removeAll()
        startWatchingAndLoad()
    }

    public func dismissError() {
        errorMessage = nil
    }

    // MARK: - Dispatch & Actions

    public func apply(_ event: DeckEvent) {
        let prevToastSeq = state.toast?.seq
        withAnimation(.snappy(duration: 0.2)) {
            state = DeckReducer.reduce(state, event)
        }
        if let toast = state.toast, toast.seq != prevToastSeq {
            scheduleToastExpiry(toast)
        }
    }

    private func scheduleToastExpiry(_ toast: DeckToast) {
        toastTask?.cancel()
        let delayNs: UInt64 = (toast.kind == .done) ? 5_000_000_000 : 1_600_000_000
        let seq = toast.seq
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delayNs)
            guard !Task.isCancelled else { return }
            self?.apply(.toastExpired(seq))
        }
    }

    public func setFolder(_ folder: FolderId) {
        apply(.folder(folder))
    }

    public func setAccountScope(_ scope: AccountScope) {
        apply(.accountScope(scope))
    }

    public func selectRow(_ id: MessageId) {
        apply(.focus(id))
    }

    public func moveFocus(delta: Int) {
        apply(.moveFocus(delta))
    }

    public func toggleSidebar() {
        guard !settingsOpen else { return }
        withAnimation(.snappy(duration: 0.2)) {
            sidebarCollapsed.toggle()
        }
    }

    public func openSettings(_ section: SettingsSection? = nil) {
        if let section {
            settings.activeSection = section
        }
        settings.syncAccountsIfNeeded(from: accounts)
        withAnimation(.snappy(duration: 0.18)) {
            settingsOpen = true
        }
    }

    public func closeSettings() {
        withAnimation(.snappy(duration: 0.18)) {
            settingsOpen = false
        }
    }

    public func toggleSettings() {
        if settingsOpen {
            closeSettings()
        } else {
            openSettings()
        }
    }

    public func setThemePreference(_ pref: ThemePreference) {
        themePreference = pref
        switch pref {
        case .light:
            themeMode = .light
        case .dark:
            themeMode = .dark
        case .system:
            let isDark = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            themeMode = isDark ? .dark : .light
        }
    }

    public func syncSystemColorScheme(_ scheme: ColorScheme) {
        guard themePreference == .system else { return }
        let resolved: ThemeMode = (scheme == .dark) ? .dark : .light
        if themeMode != resolved {
            themeMode = resolved
        }
    }

    public func toggleTheme() {
        setThemePreference(themeMode == .dark ? .light : .dark)
    }

    public func toggleBodyFormat() {
        withAnimation(.snappy(duration: 0.16)) {
            preferPlainText.toggle()
        }
    }

    public func toggleAIReasoning() {
        withAnimation(.snappy(duration: 0.18)) {
            if inspectorRailOpen {
                inspectorRailOpen = false
            } else {
                aiReasoningExpanded.toggle()
            }
        }
    }

    public func toggleInspectorRail() {
        withAnimation(.snappy(duration: 0.18)) {
            inspectorRailOpen.toggle()
        }
    }

    public func allowRemoteImages(for id: MessageId) {
        withAnimation(.snappy(duration: 0.16)) {
            _ = allowedRemoteImageIds.insert(id)
        }
    }

    public func hydrateIfNeeded(for content: MailContent?) {
        guard let content, (content.isPartial || content.isTruncated) else { return }
        let id = content.id
        guard !attemptedHydrationIds.contains(id) else { return }
        attemptedHydrationIds.insert(id)
        hydratingIds.insert(id)

        let currentAdapter = self.adapter
        Task {
            defer {
                self.hydratingIds.remove(id)
            }
            if let hydrated = try? await currentAdapter.hydrateMessage(id: id) {
                self.apply(.hydrated(hydrated))
            }
        }
    }

    public func actOnCard(_ action: CardAction, id: MessageId? = nil) {
        guard let targetId = id ?? state.focusId,
              state.queue.contains(where: { $0.id == targetId }) else {
            return
        }
        apply(.card(id: targetId, action: action, now: Date()))
        let currentAdapter = self.adapter
        Task {
            do {
                switch action {
                case .archive:
                    try await currentAdapter.archive(id: targetId)
                case .keep:
                    try await currentAdapter.flagImportant(id: targetId)
                case .trash:
                    try await currentAdapter.moveToTrash(id: targetId, reason: .userPromo)
                }
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    public func rescueFocused() {
        guard case .handled(let item) = activeRow else { return }
        rescueRow(item.id)
    }

    public func rescueRow(_ id: MessageId) {
        guard state.handled.contains(where: { $0.id == id }) else { return }
        guard !rescuingIds.contains(id) else { return }
        rescuingIds.insert(id)
        let currentAdapter = self.adapter
        Task {
            defer { rescuingIds.remove(id) }
            do {
                let rescuedMail = try await currentAdapter.rescue(id: id)
                apply(.rescued(rescuedMail))
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    @discardableResult
    public func undo() -> Bool {
        guard let entry = state.undo.last else { return false }
        apply(.undo)
        let currentAdapter = self.adapter
        Task {
            do {
                switch entry {
                case .card(_, let mail, _, _):
                    try await currentAdapter.restore(id: mail.id)
                case .rescue(let item, let mail, _):
                    if item.disposition == .archived {
                        try await currentAdapter.archive(id: mail.id)
                    } else {
                        try await currentAdapter.moveToTrash(id: mail.id, reason: item.manual ? .userPromo : .autoPromo)
                    }
                }
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
        return true
    }

    public func openFocusedInNativeMail() {
        guard let row = activeRow else { return }
        let id = row.id
        let currentAdapter = self.adapter
        let isDemo = (sourceMode == .demo)
        Task {
            do {
                let url = try await currentAdapter.openInNativeMail(id: id)
                if isDemo {
                    showNativeNotice(url: url)
                }
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func showNativeNotice(url: String) {
        noticeTask?.cancel()
        withAnimation(.snappy(duration: 0.2)) {
            nativeNoticeURL = url
        }
        noticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.snappy(duration: 0.2)) {
                self?.nativeNoticeURL = nil
            }
        }
    }

    public func simulateIncoming() async {
        guard adapter.supportsDemoControls else { return }
        if let mails = try? await adapter.simulateIncoming(count: 3), !mails.isEmpty {
            apply(.incoming(mails))
        }
    }

    public func resetDemo() async {
        guard adapter.supportsDemoControls else { return }
        try? await adapter.resetDemo()
        await reloadSnapshot(initial: true)
    }

    // MARK: - HUD & Command Palette Builders

    public var hudItems: [HudItem] {
        let hasRows = !visibleRows.isEmpty
        let inboxMode = state.folder.isInboxFolder
        let canActInbox: Bool = {
            if case .inbox = activeRow { return true }
            return false
        }()
        let canRescue: Bool = {
            if case .handled = activeRow { return true }
            return false
        }()

        var list: [HudItem] = [
            HudItem(keys: ["J", "K"], label: "切换", disabled: !hasRows) { [weak self] in
                self?.moveFocus(delta: 1)
            }
        ]
        if inboxMode {
            list.append(HudItem(keys: ["Space"], label: "归档", disabled: !canActInbox) { [weak self] in
                self?.actOnCard(.archive)
            })
            list.append(HudItem(keys: ["⇧K"], label: "保留", disabled: !canActInbox) { [weak self] in
                self?.actOnCard(.keep)
            })
            list.append(HudItem(keys: ["⌫"], label: "推广", disabled: !canActInbox) { [weak self] in
                self?.actOnCard(.trash)
            })
        } else if state.folder != .kept {
            list.append(HudItem(keys: ["R"], label: "拉回待处理", disabled: !canRescue) { [weak self] in
                self?.rescueFocused()
            })
        }
        list.append(HudItem(keys: ["I"], label: "判据", disabled: activeRow == nil) { [weak self] in
            self?.toggleAIReasoning()
        })
        list.append(HudItem(keys: ["↵"], label: "Mail", disabled: activeRow == nil) { [weak self] in
            self?.openFocusedInNativeMail()
        })
        list.append(HudItem(keys: ["Z"], label: "撤销", disabled: state.undo.isEmpty) { [weak self] in
            _ = self?.undo()
        })
        list.append(HudItem(keys: ["⌘K"], label: "命令", disabled: false) { [weak self] in
            self?.paletteOpen = true
        })
        return list
    }

    public var paletteCommands: [PaletteCommand] {
        var list: [PaletteCommand] = []

        if let row = activeRow {
            switch row {
            case .inbox(let mail):
                let sub = mail.subject
                list.append(PaletteCommand(id: "archive", group: "当前邮件", title: "阅毕归档", subtitle: sub, keywords: "archive 归档", kbd: "Space", systemImage: "archivebox") { [weak self] in self?.actOnCard(.archive, id: mail.id) })
                list.append(PaletteCommand(id: "keep", group: "当前邮件", title: "重要保留", subtitle: sub, keywords: "flag keep 保留 标旗", kbd: "⇧K", systemImage: "flag") { [weak self] in self?.actOnCard(.keep, id: mail.id) })
                list.append(PaletteCommand(id: "trash", group: "当前邮件", title: "判为推广并移入废纸篓", subtitle: sub, keywords: "trash delete 推广 废纸篓", kbd: "⌫", systemImage: "trash") { [weak self] in self?.actOnCard(.trash, id: mail.id) })
                list.append(PaletteCommand(id: "native", group: "当前邮件", title: "在 Apple Mail 中打开", subtitle: nil, keywords: "open mail 打开", kbd: "↵", systemImage: "arrow.up.right") { [weak self] in self?.openFocusedInNativeMail() })
            case .handled(let item):
                list.append(PaletteCommand(id: "rescue", group: "当前邮件", title: "拉回待处理", subtitle: item.subject, keywords: "rescue 拉回", kbd: "R", systemImage: "arrow.uturn.backward") { [weak self] in self?.rescueFocused() })
                list.append(PaletteCommand(id: "native", group: "当前邮件", title: "在 Apple Mail 中打开", subtitle: nil, keywords: "open mail 打开", kbd: "↵", systemImage: "arrow.up.right") { [weak self] in self?.openFocusedInNativeMail() })
            case .kept(let mail):
                list.append(PaletteCommand(id: "native", group: "当前邮件", title: "在 Apple Mail 中打开", subtitle: mail.subject, keywords: "open mail 打开", kbd: "↵", systemImage: "arrow.up.right") { [weak self] in self?.openFocusedInNativeMail() })
            }
            list.append(
                PaletteCommand(
                    id: "toggle-ai-strip",
                    group: "当前邮件",
                    title: aiReasoningExpanded ? "收起正文顶部 AI 判据条" : "展开正文顶部 AI 判据条",
                    subtitle: nil,
                    keywords: "ai reason evidence 判据 引证 确信度",
                    kbd: "I",
                    systemImage: "sparkles"
                ) { [weak self] in
                    self?.toggleAIReasoning()
                }
            )
            list.append(
                PaletteCommand(
                    id: "toggle-inspector-rail",
                    group: "当前邮件",
                    title: inspectorRailOpen ? "关闭右侧洞察侧栏" : "打开右侧洞察侧栏",
                    subtitle: "查看校准确信度进度条、安全护栏与同线程历史往来",
                    keywords: "inspector rail sidebar 洞察栏 侧栏 线程",
                    kbd: "⇧I",
                    systemImage: "sidebar.right"
                ) { [weak self] in
                    self?.toggleInspectorRail()
                }
            )
            if row.content.htmlBody != nil {
                list.append(
                    PaletteCommand(
                        id: "toggle-body-format",
                        group: "当前邮件",
                        title: preferPlainText ? "切换到富文本排版视图" : "切换到纯文本视图",
                        subtitle: nil,
                        keywords: "html plain text 富文本 纯文本 排版",
                        kbd: nil,
                        systemImage: preferPlainText ? "richtext.page" : "doc.plaintext"
                    ) { [weak self] in
                        self?.toggleBodyFormat()
                    }
                )
                if !preferPlainText && row.content.hasRemoteImages && !allowedRemoteImageIds.contains(row.id) {
                    let rowId = row.id
                    list.append(
                        PaletteCommand(
                            id: "allow-remote-images",
                            group: "当前邮件",
                            title: "加载并显示当前邮件的远程图片",
                            subtitle: "仅对本封邮件放行外部图片资源",
                            keywords: "images remote 显示图片 远程图片",
                            kbd: nil,
                            systemImage: "photo"
                        ) { [weak self] in
                            self?.allowRemoteImages(for: rowId)
                        }
                    )
                }
            }
        }

        if accounts.count > 1 {
            list.append(PaletteCommand(id: "acc-all", group: "邮箱范围", title: "查看全部邮箱", subtitle: nil, keywords: "account all 全部邮箱", kbd: nil, systemImage: "tray") { [weak self] in self?.setAccountScope(.all) })
            for acc in accounts {
                list.append(PaletteCommand(id: "acc-\(acc.id)", group: "邮箱范围", title: "只看「\(acc.label)」邮箱", subtitle: acc.address, keywords: "account \(acc.label) \(acc.address)", kbd: nil, systemImage: "envelope") { [weak self] in self?.setAccountScope(.account(acc.id)) })
            }
        }

        for def in FolderDef.all {
            let cnt = counts[def.id] ?? 0
            let icon = def.id == .trashed ? "trash" : def.id == .archived ? "archivebox" : def.id == .kept ? "flag" : "tray"
            list.append(PaletteCommand(id: "folder-\(def.id.rawValue)", group: "分拣夹", title: "前往：\(def.label)", subtitle: "\(cnt) 封", keywords: def.label, kbd: def.shortcut, systemImage: icon) { [weak self] in self?.setFolder(def.id) })
        }

        for m in state.queue {
            list.append(PaletteCommand(
                id: "mail-\(m.id.rawValue)",
                group: "待你处理",
                title: m.subject,
                subtitle: "\(m.from.name) · \(m.account.label)",
                keywords: "\(m.from.address) \(m.account.address) \(m.meta.badge) \(m.meta.intent ?? "") \(m.plainText.prefix(300))",
                kbd: nil,
                systemImage: "envelope"
            ) { [weak self] in
                self?.setAccountScope(.all)
                self?.setFolder(.inbox)
                self?.selectRow(m.id)
            })
        }

        for h in state.handled {
            list.append(PaletteCommand(
                id: "handled-\(h.id.rawValue)",
                group: "自动处理",
                title: h.subject,
                subtitle: "\(h.from.name) · \(h.category) · \(h.account.label)",
                keywords: "\(h.from.address) \(h.account.address) \(h.plainText.prefix(200))",
                kbd: nil,
                systemImage: "envelope.badge"
            ) { [weak self] in
                self?.setAccountScope(.all)
                self?.setFolder(h.disposition == .archived ? .archived : .trashed)
                self?.selectRow(h.id)
            })
        }

        // 数据源与系统命令
        if sourceMode == .appleMail {
            list.append(PaletteCommand(id: "sync-now", group: "数据源", title: "立即重新同步 Apple Mail", subtitle: nil, keywords: "sync refresh 同步 刷新", kbd: "⌘R", systemImage: "arrow.clockwise") { [weak self] in
                guard let self else { return }
                Task { await self.reloadSnapshot(initial: false) }
            })
            list.append(PaletteCommand(id: "switch-demo", group: "数据源", title: "切换到内置演示数据", subtitle: "不读写本机邮件，用于界面演示", keywords: "demo mock 演示", kbd: nil, systemImage: "sparkles") { [weak self] in
                self?.switchToDemoMode()
            })
        } else {
            list.append(PaletteCommand(id: "switch-live", group: "数据源", title: "接入本机 Apple Mail 真机收件箱", subtitle: "只读同步 Envelope Index + AppleEvent 写回", keywords: "apple mail live 真机 接入", kbd: nil, systemImage: "tray.full") { [weak self] in
                self?.recheckAccessAndSwitchToAppleMail()
            })
            list.append(PaletteCommand(id: "sim", group: "演示", title: "模拟收到 3 封新邮件", subtitle: nil, keywords: "demo 模拟收到", kbd: nil, systemImage: "tray.and.arrow.down") { [weak self] in
                guard let self else { return }
                Task { await self.simulateIncoming() }
            })
            list.append(PaletteCommand(id: "reset", group: "演示", title: "重置演示数据", subtitle: nil, keywords: "demo reset 重置", kbd: nil, systemImage: "arrow.counterclockwise") { [weak self] in
                guard let self else { return }
                Task { await self.resetDemo() }
            })
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
                    systemImage: sec.iconName
                ) { [weak self] in
                    self?.openSettings(sec)
                }
            )
        }
        if settingsOpen {
            list.insert(
                PaletteCommand(
                    id: "close-settings",
                    group: "设置",
                    title: "返回收件箱",
                    subtitle: nil,
                    keywords: "inbox back 返回 收件箱 关闭设置",
                    kbd: "esc",
                    systemImage: "arrow.left"
                ) { [weak self] in
                    self?.closeSettings()
                },
                at: 0
            )
        }

        if !state.undo.isEmpty {
            list.append(PaletteCommand(id: "undo", group: "系统", title: "撤销上一步", subtitle: nil, keywords: "undo 撤销", kbd: "Z", systemImage: "arrow.uturn.backward") { [weak self] in _ = self?.undo() })
        }
        list.append(PaletteCommand(id: "sidebar", group: "系统", title: sidebarCollapsed ? "展开左侧边栏" : "收起左侧边栏", subtitle: nil, keywords: "sidebar 侧边栏", kbd: "[", systemImage: "sidebar.left") { [weak self] in self?.toggleSidebar() })
        list.append(PaletteCommand(id: "theme", group: "系统", title: themeMode == .dark ? "切换到浅色模式" : "切换到深色模式", subtitle: nil, keywords: "theme dark light 主题 深色 浅色", kbd: nil, systemImage: themeMode == .dark ? "sun.max" : "moon") { [weak self] in self?.toggleTheme() })

        return list
    }
}
