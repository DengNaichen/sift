import Foundation
import MailroomCore

/// 左侧导航栏：品牌栏、多邮箱范围滤镜、分拣夹树与底部状态栏。
/// 无状态投影：只持有 `AppModel` 引用，读取经 Observation 穿透到各 Store。
@MainActor
struct SidebarViewModel {
    let app: AppModel
    private var deck: DeckStore { app.deck }

    // MARK: 邮箱范围

    var accounts: [MailAccount] { deck.accounts }
    var showsAccountTabs: Bool { deck.accounts.count > 1 }
    var isAllAccountsActive: Bool { deck.state.accountScope == .all }
    func isActive(account: MailAccount) -> Bool { deck.state.accountScope == .account(account.id) }
    var activeAccount: MailAccount? { deck.activeAccount }

    // MARK: 分拣夹

    var triageFolders: [FolderDef] { FolderDef.all.filter { $0.group == .triage } }
    var processedFolders: [FolderDef] { FolderDef.all.filter { $0.group == .processed } }
    func count(of folder: FolderId) -> Int { deck.counts[folder] ?? 0 }
    func isActive(folder: FolderId) -> Bool { deck.state.folder == folder }

    // MARK: 底部状态栏

    var isLiveSource: Bool { deck.sourceMode == .appleMail }
    var showsDemoControls: Bool { !isLiveSource && deck.supportsDemoControls }
    var savedMinutesText: String {
        "已省 \(MailFormatting.savedMinutes(count: deck.state.handled.count)) 分钟"
    }
    var sourceHelpText: String {
        isLiveSource
            ? "已连接 Apple Mail · 自动过滤 \(deck.state.handled.count) 封通知与推广"
            : "当前为演示数据模式（按 ⌘K 可切换数据源）"
    }
    var isDarkTheme: Bool { app.preferences.themeMode == .dark }

    // MARK: Intents

    func perform(_ command: DeckCommand) { app.perform(command) }
}
