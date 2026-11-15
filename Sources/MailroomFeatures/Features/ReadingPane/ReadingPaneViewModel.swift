import Foundation
import MailroomCore

/// 右栏阅读区：顶部提示条、正文呈现模式、悬浮工具栏、底部 toast 与快捷键 HUD。
@MainActor
struct ReadingPaneViewModel {
    let app: AppModel
    private var deck: DeckStore { app.deck }

    enum Banner: Equatable {
        case none
        /// 演示模式且缺少完全磁盘访问权限：引导授权
        case fullDiskAccessOnboarding
        case error(String)
    }

    enum Body: Equatable {
        /// 富文本正文；`showsPrivacyBar` 为远程图片被拦截时的提示条
        case html(String, allowRemoteImages: Bool, showsPrivacyBar: Bool)
        case plain(String)
    }

    var banner: Banner {
        if case .fullDiskAccessRequired = deck.accessStatus, deck.sourceMode == .demo {
            return .fullDiskAccessOnboarding
        } else if let err = deck.errorMessage {
            return .error(err)
        }
        return .none
    }

    var activeRow: FolderRow? { deck.activeRow }
    var content: MailContent? { activeRow?.content }

    func isHydrating(_ id: MessageId) -> Bool { deck.hydratingIds.contains(id) }

    func body(for content: MailContent) -> Body {
        if let html = content.htmlBody, !html.isEmpty, !app.preferences.preferPlainText {
            let allowed = app.settingsForm.remoteImageChoice == .alwaysLoad || deck.allowedRemoteImageIds.contains(content.id)
            return .html(html, allowRemoteImages: allowed, showsPrivacyBar: content.hasRemoteImages && !allowed)
        }
        return .plain(content.plainText)
    }

    var themeMode: ThemeMode { app.preferences.themeMode }

    /// 顶部「n / N」位置胶囊
    var positionText: String? {
        guard let idx = deck.activeIndex else { return nil }
        return "\(idx + 1) / \(deck.visibleRows.count)"
    }

    var showsTriageCapsule: Bool { activeRow != nil || deck.canUndo }
    var canUndo: Bool { deck.canUndo }
    var isInboxFolder: Bool { deck.state.folder.isInboxFolder }

    // MARK: 底部浮层

    var toast: DeckToast? { deck.state.toast }
    var showsKeyboardHUD: Bool { app.preferences.showKeyboardHUD }
    var hudItems: [HudItem] { app.hudItems }

    var inboxZero: InboxZeroViewModel { InboxZeroViewModel(app: app) }

    // MARK: Intents

    func hydrateIfNeeded(_ content: MailContent?) { deck.hydrateIfNeeded(for: content) }
    func perform(_ command: DeckCommand) { app.perform(command) }
}

/// 收件箱清零卡片
@MainActor
struct InboxZeroViewModel {
    let app: AppModel
    private var deck: DeckStore { app.deck }

    var personalHandledCount: Int {
        let t = deck.state.tally
        return t.archived + t.kept + t.trashed
    }

    var stats: [(String, Int)] {
        let t = deck.state.tally
        return [
            ("阅毕归档", t.archived),
            ("重要保留", t.kept),
            ("判为推广", t.trashed),
            ("AI 自动挡下", deck.state.handled.count)
        ]
    }

    var isLiveSource: Bool { deck.sourceMode == .appleMail }
    var showsDemoControls: Bool { !isLiveSource && deck.supportsDemoControls }
    var canUndo: Bool { deck.canUndo }

    func perform(_ command: DeckCommand) { app.perform(command) }
}
