import Foundation
import SwiftUI
import Testing
@testable import MailroomCore
@testable import MailroomFeatures

@MainActor
private func makeApp(
    defaults: UserDefaults = makeIsolatedDefaults(),
    environment: ((inout AppEnvironment) -> Void)? = nil
) async -> AppModel {
    var env = makeTestEnvironment(defaults: defaults)
    environment?(&env)
    let app = AppModel(environment: env)
    await waitUntil { app.deck.state.phase == .ready }
    return app
}

@MainActor
@Suite("Feature ViewModels", .serialized)
struct FeatureViewModelTests {
    @Test("MailList rows carry selection, unread and account badge")
    func mailListRows() async {
        let app = await makeApp()
        let list = MailListViewModel(app: app)
        #expect(list.folderTitle == "全部待处理")
        #expect(list.rowCount == 5)
        #expect(list.rows.first?.selected == true)
        #expect(list.rows.filter(\.selected).count == 1)
        // 初始仅焦点邮件已读
        #expect(list.rows.filter { !$0.unread }.map(\.id) == [app.deck.state.focusId!])
        #expect(list.rows.allSatisfy { $0.showAccountBadge })

        app.perform(.setAccountScope(.account("work")))
        #expect(list.rows.allSatisfy { !$0.showAccountBadge })
        #expect(list.activeAccount?.id == "work")

        app.perform(.setFolder(.kept))
        #expect(list.isEmpty)
        #expect(list.emptyText == "当前列表为空")
    }

    @Test("Handled rows show handledAt; inbox rows prefer evidence excerpt")
    func rowModelDerivations() async {
        let app = await makeApp()
        app.perform(.setFolder(.archived))
        let row = MailListViewModel(app: app).rows[0]
        guard case .handled(let item) = row.row else {
            Issue.record("expected handled row"); return
        }
        #expect(row.timestamp == item.handledAt)
        #expect(row.timestampText == MailFormatting.formatTime(item.handledAt))
        #expect(!row.previewText.isEmpty)
    }

    @Test("ReadingPane banner, body mode and position")
    func readingPane() async {
        let app = await makeApp()
        let pane = ReadingPaneViewModel(app: app)
        #expect(pane.banner == .fullDiskAccessOnboarding)
        #expect(pane.positionText == "1 / 5")
        #expect(pane.showsTriageCapsule)
        #expect(!pane.canUndo)
        if let content = pane.content {
            #expect(pane.body(for: content) == .plain(content.plainText))
        }
        app.perform(.moveFocus(2))
        #expect(pane.positionText == "3 / 5")
    }

    @Test("ReadingPane HTML body honors plain-text preference and remote image permission")
    func readingPaneHTML() async throws {
        let app = await makeApp()
        let pane = ReadingPaneViewModel(app: app)
        let base = try #require(pane.content)
        let content = MailContent(
            id: base.id, from: base.from, account: base.account, subject: base.subject,
            receivedAt: base.receivedAt, plainText: base.plainText, attachments: base.attachments,
            htmlBody: "<p>hi <img src='https://x/y.png'></p>", hasRemoteImages: true
        )
        #expect(pane.body(for: content) == .html(content.htmlBody!, allowRemoteImages: false, showsPrivacyBar: true))
        app.perform(.allowRemoteImages(content.id))
        #expect(pane.body(for: content) == .html(content.htmlBody!, allowRemoteImages: true, showsPrivacyBar: false))
        app.perform(.toggleBodyFormat)
        #expect(pane.body(for: content) == .plain(content.plainText))
    }

    @Test("InboxZero stats follow the tally")
    func inboxZero() async {
        let app = await makeApp()
        app.perform(.card(.archive, nil))
        app.perform(.card(.keep, nil))
        app.perform(.card(.trash, nil))
        let zero = InboxZeroViewModel(app: app)
        #expect(zero.personalHandledCount == 3)
        #expect(zero.stats.map(\.1) == [1, 1, 1, app.deck.state.handled.count])
        #expect(zero.showsDemoControls)
        #expect(zero.canUndo)
    }

    @Test("Sidebar exposes folder counts, scope and footer controls")
    func sidebar() async {
        let app = await makeApp()
        let sidebar = SidebarViewModel(app: app)
        #expect(sidebar.showsAccountTabs)
        #expect(sidebar.isAllAccountsActive)
        #expect(sidebar.triageFolders.map(\.id) == [.inbox, .inboxHuman, .inboxStakes, .inboxUncertain])
        #expect(sidebar.processedFolders.map(\.id) == [.kept, .archived, .trashed])
        #expect(sidebar.count(of: .inbox) == 5)
        #expect(sidebar.isActive(folder: .inbox))
        #expect(!sidebar.isLiveSource)
        #expect(sidebar.showsDemoControls)
        #expect(!sidebar.isDarkTheme)
    }

    @Test("Settings source selection and locked addresses")
    func settings() async {
        let app = await makeApp()
        let settings = SettingsViewModel(app: app)
        #expect(settings.sourceModeKey == "demo")
        #expect(!settings.isFullDiskAccessReady)
        #expect(settings.lockedPrimaryAddresses == app.deck.accounts.map(\.address))
        settings.selectSource("appleMail") // 无权限 → 留在演示数据并提示
        #expect(app.deck.sourceMode == .demo)
        #expect(app.deck.errorMessage == "尚未获得「完全磁盘访问权限」，请在系统设置中勾选本应用后再试。")
        settings.showKeyboardHUD.wrappedValue = false
        #expect(app.preferences.showKeyboardHUD == false)
    }

    @Test("Root view model lays out sidebar visibility and peek state")
    func root() async {
        let app = await makeApp()
        let root = RootViewModel(app: app)
        #expect(root.showLeftSidebar)
        #expect(!root.canPeekSidebar)
        app.perform(.toggleSidebar)
        #expect(!root.showLeftSidebar)
        #expect(root.canPeekSidebar)
        app.perform(.setSidebarPeeking(true))
        #expect(root.sidebarPeeking)
        app.perform(.openSettings(nil))
        #expect(!root.sidebarPeeking) // 打开设置立即收起 Peek 抽屉
        #expect(root.showLeftSidebar) // 设置台始终显示左栏导航
        app.perform(.toggleSidebar) // 设置打开时无效
        #expect(app.shell.sidebarCollapsed)
    }
}

@Suite("CommandPaletteViewModel")
@MainActor
struct CommandPaletteViewModelTests {
    private func cmd(_ id: String, group: String, title: String, keywords: String = "") -> PaletteCommand {
        PaletteCommand(id: id, group: group, title: title, subtitle: nil, keywords: keywords, kbd: nil, systemImage: "x", command: .undo)
    }

    @Test func filterMatchesTitleKeywordsAndGroupCaseInsensitively() {
        let list = [
            cmd("a", group: "系统", title: "撤销上一步", keywords: "undo"),
            cmd("b", group: "设置", title: "设置：外观", keywords: "Theme"),
            cmd("c", group: "分拣夹", title: "前往：废纸篓"),
        ]
        #expect(CommandPaletteViewModel.filter(list, query: "").map(\.id) == ["a", "b", "c"])
        #expect(CommandPaletteViewModel.filter(list, query: "  UNDO ").map(\.id) == ["a"])
        #expect(CommandPaletteViewModel.filter(list, query: "theme").map(\.id) == ["b"])
        #expect(CommandPaletteViewModel.filter(list, query: "分拣").map(\.id) == ["c"])
        #expect(CommandPaletteViewModel.filter(list, query: "zzz").isEmpty)
    }

    @Test func selectionClampsAndResetsOnQueryChange() {
        let model = CommandPaletteViewModel()
        let list = [cmd("a", group: "g", title: "A"), cmd("b", group: "g", title: "B")]
        model.moveDown(count: list.count)
        model.moveDown(count: list.count)
        model.moveDown(count: list.count)
        #expect(model.activeIndex == 1)
        #expect(model.activeCommand(in: list)?.id == "b")
        model.moveUp(); model.moveUp()
        #expect(model.activeIndex == 0)
        model.moveDown(count: list.count)
        model.query = "b"
        #expect(model.activeIndex == 0)
        #expect(model.activeCommand(in: []) == nil)
    }

    @Test func groupHeadersOnlyAtGroupBoundaries() {
        let list = [cmd("a", group: "x", title: "A"), cmd("b", group: "x", title: "B"), cmd("c", group: "y", title: "C")]
        #expect((0..<3).map { CommandPaletteViewModel.showsGroupHeader(at: $0, in: list) } == [true, false, true])
    }
}

@Suite("PreferencesStore")
@MainActor
struct PreferencesStoreTests {
    @Test func themeModeIsDerivedFromPreferenceAndSystem() {
        var systemDark = false
        let prefs = PreferencesStore(defaults: makeIsolatedDefaults(), systemIsDark: { systemDark })
        #expect(prefs.themePreference == .system)
        #expect(prefs.themeMode == .light)
        prefs.syncSystemColorScheme(.dark)
        #expect(prefs.themeMode == .dark)
        prefs.setThemePreference(.light)
        prefs.syncSystemColorScheme(.dark)
        #expect(prefs.themeMode == .light) // 显式偏好不受窗口外观影响
        systemDark = true
        prefs.setThemePreference(.system) // 切回跟随系统时重新探测
        #expect(prefs.themeMode == .dark)
        #expect(prefs.preferredColorScheme == nil)
        prefs.toggleTheme()
        #expect(prefs.themePreference == .light)
        #expect(prefs.preferredColorScheme == .light)
    }
}

/// 写回 adapter 失败的替身：读路径委托给演示数据。
private actor FailingWriteAdapter: MailAdapter {
    struct WriteFailed: LocalizedError {
        var errorDescription: String? { "写回失败（测试）" }
    }
    private let inner = MockMailAdapter(now: fixtureNow)
    nonisolated var sourceLabel: String { "failing" }
    func fetchDeck() async throws -> DeckSnapshot { try await inner.fetchDeck() }
    func archive(id: MessageId) async throws { throw WriteFailed() }
    func flagImportant(id: MessageId) async throws { throw WriteFailed() }
    func moveToTrash(id: MessageId, reason: TrashReason) async throws { throw WriteFailed() }
    func restore(id: MessageId) async throws { throw WriteFailed() }
    func rescue(id: MessageId) async throws -> MailItem { throw WriteFailed() }
    func openInNativeMail(id: MessageId) async throws -> String { throw WriteFailed() }
}

/// 已知问题：重构刻意保持原行为，这里用测试把它们钉住，修复时应当先改这些断言。
@MainActor
@Suite("Known issues (preserved by the refactor)", .serialized)
struct KnownIssueTests {
    @Test("Optimistic triage is not rolled back when the adapter write fails")
    func optimisticUpdateWithoutRollback() async {
        let app = await makeApp { env in
            env.makeDemoAdapter = { FailingWriteAdapter() }
        }
        let target = app.deck.state.focusId!
        app.perform(.card(.archive, nil))
        await waitUntil { app.deck.errorMessage != nil }
        #expect(app.deck.errorMessage == "写回失败（测试）")
        // 本地仍认为已归档：界面与真实邮箱不一致
        #expect(!app.deck.state.queue.contains { $0.id == target })
        #expect(app.deck.state.tally.archived == 1)
    }

    @Test("Resolved theme is written to the legacy key, so a fresh 'system' user is pinned on next launch")
    func legacyThemeKeyPinsResolvedMode() async {
        let defaults = makeIsolatedDefaults()
        do {
            let prefs = PreferencesStore(defaults: defaults, systemIsDark: { false })
            prefs.syncSystemColorScheme(.dark) // 首次启动时窗口回报深色
        }
        let next = PreferencesStore(defaults: defaults, systemIsDark: { false })
        #expect(next.themePreference == .dark) // 期望应为 .system
    }
}
