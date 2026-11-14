import Foundation
import SwiftUI
import MailroomCore

/// 设置台（侧栏 + 五个分区）。表单字段在 `form`（可直接绑定），
/// 连接、外观等真实生效的设置通过本 ViewModel 读写对应 Store。
@MainActor
struct SettingsViewModel {
    let app: AppModel
    private var deck: DeckStore { app.deck }
    private var preferences: PreferencesStore { app.preferences }

    var form: SettingsFormState { app.settingsForm }

    // MARK: 连接

    var isLiveSource: Bool { deck.sourceMode == .appleMail }
    var sourceModeKey: String { deck.sourceMode.rawValue }

    var isFullDiskAccessReady: Bool {
        if case .ready = deck.accessStatus { return true }
        return false
    }

    var liveAccounts: [MailAccount] { deck.accounts }

    /// 本人地址：优先真实账户，其次表单中的账户占位
    var lockedPrimaryAddresses: [String] {
        let live = deck.accounts.map(\.address).filter { !$0.isEmpty }
        if !live.isEmpty { return live }
        return form.accountItems.map(\.address).filter { !$0.isEmpty }
    }

    func selectSource(_ key: String) {
        if key == DataSourceMode.appleMail.rawValue {
            app.perform(.switchToLive)
        } else {
            app.perform(.switchToDemo)
        }
    }

    func syncAccounts(_ accounts: [MailAccount]) {
        form.syncAccountsIfNeeded(from: accounts)
    }

    // MARK: 外观

    var themePreference: ThemePreference { preferences.themePreference }
    func setThemePreference(_ pref: ThemePreference) { preferences.setThemePreference(pref) }

    var preferPlainText: Bool { preferences.preferPlainText }
    func setPreferPlainText(_ value: Bool) { preferences.preferPlainText = value }

    var showKeyboardHUD: Binding<Bool> {
        let preferences = self.preferences
        return Binding(get: { preferences.showKeyboardHUD }, set: { preferences.showKeyboardHUD = $0 })
    }

    var aiReasoningExpanded: Binding<Bool> {
        let preferences = self.preferences
        return Binding(get: { preferences.aiReasoningExpanded }, set: { preferences.aiReasoningExpanded = $0 })
    }

    // MARK: Intents

    func perform(_ command: DeckCommand) { app.perform(command) }
}
