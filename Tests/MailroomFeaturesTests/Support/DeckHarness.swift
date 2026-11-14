import AppKit
import Foundation
import SwiftUI
import Testing
@testable import MailroomCore
@testable import MailroomFeatures

/// 特征测试的统一驱动面。重构过程中只允许改写本文件以适配新 API，
/// 金样（__Goldens__）与快照基线（__Snapshots__）保持不变即证明行为与视觉未变。
@MainActor
final class DeckHarness {
    let app: AppModel
    let defaults: UserDefaults
    private var deck: DeckStore { app.deck }
    private var prefs: PreferencesStore { app.preferences }

    init(defaults: UserDefaults = makeIsolatedDefaults(), systemIsDark: Bool = false) async {
        self.defaults = defaults
        self.app = AppModel(environment: makeTestEnvironment(defaults: defaults, systemIsDark: systemIsDark))
        let deck = self.app.deck
        await waitUntil { deck.state.phase == .ready }
    }

    // MARK: Intents

    func archive() { app.perform(.card(.archive, nil)) }
    func keep() { app.perform(.card(.keep, nil)) }
    func trash() { app.perform(.card(.trash, nil)) }
    func undo() { app.perform(.undo) }
    func setFolder(_ f: FolderId) { app.perform(.setFolder(f)) }
    func setScope(_ s: AccountScope) { app.perform(.setAccountScope(s)) }
    func moveFocus(_ d: Int) { app.perform(.moveFocus(d)) }
    func select(_ id: MessageId) { app.perform(.select(id)) }
    func rescueFocused() async {
        let before = deck.state.handled.count
        app.perform(.rescueFocused)
        let deck = self.deck
        await waitUntil { deck.state.handled.count < before }
    }
    func toggleAIReasoning() { app.perform(.toggleAIReasoning) }
    func toggleInspectorRail() { app.perform(.toggleInspectorRail) }
    func toggleBodyFormat() { app.perform(.toggleBodyFormat) }
    func allowRemoteImagesForFocused() { if let id = deck.state.focusId { app.perform(.allowRemoteImages(id)) } }
    func toggleSidebar() { app.perform(.toggleSidebar) }
    func toggleTheme() { app.perform(.toggleTheme) }
    func setThemePreference(_ p: ThemePreference) { prefs.setThemePreference(p) }
    func syncSystemColorScheme(_ s: ColorScheme) { prefs.syncSystemColorScheme(s) }
    func openSettings(_ s: SettingsSection? = nil) { app.perform(.openSettings(s)) }
    func closeSettings() { app.perform(.closeSettings) }
    func openPalette() { app.perform(.openPalette) }
    func setShowKeyboardHUD(_ v: Bool) { prefs.showKeyboardHUD = v }

    /// 执行命令面板中指定 id 的命令（模拟用户在面板中回车：先关面板再执行）
    func runPalette(_ id: String) {
        guard let cmd = app.paletteCommands.first(where: { $0.id == id }) else {
            fatalError("palette command \(id) not found")
        }
        app.perform(.closePalette)
        app.perform(cmd.command)
    }

    /// 点击 HUD 中指定 label 的按钮
    func tapHUD(_ label: String) {
        guard let item = app.hudItems.first(where: { $0.label == label }) else {
            fatalError("hud item \(label) not found")
        }
        app.perform(item.command)
    }

    // MARK: Observation

    var state: DeckState { deck.state }
    var paletteOpen: Bool { app.shell.paletteOpen }
    var settingsOpen: Bool { app.shell.settingsOpen }

    func dump() -> String {
        var out: [String] = []
        let s = deck.state
        out.append("[state]")
        out.append("phase=\(s.phase) folder=\(s.folder.rawValue) scope=\(s.accountScope) focus=\(s.focusId?.rawValue ?? "nil")")
        out.append("visible=\(deck.visibleRows.map(\.id.rawValue).joined(separator: ","))")
        out.append("activeIndex=\(deck.activeIndex.map(String.init) ?? "nil") activeAccount=\(deck.activeAccount?.id ?? "nil")")
        out.append("counts=\(FolderId.allCases.map { "\($0.rawValue):\(deck.counts[$0] ?? -1)" }.joined(separator: ","))")
        out.append("accounts=\(deck.accounts.map(\.id).joined(separator: ","))")
        out.append("read=\(s.readIds.map(\.rawValue).sorted().joined(separator: ","))")
        out.append("queue=\(s.queue.map(\.id.rawValue).joined(separator: ","))")
        out.append("kept=\(s.kept.map(\.id.rawValue).joined(separator: ","))")
        out.append("handled=\(s.handled.map { "\($0.id.rawValue)/\($0.disposition)/\($0.manual)" }.joined(separator: ","))")
        out.append("undo=\(s.undo.map(\.descriptionText).joined(separator: " | "))")
        out.append("toast=\(s.toast.map { "\($0.seq)/\($0.kind)/\($0.entry.descriptionText)" } ?? "nil") seq=\(s.seq)")
        out.append("tally=a\(s.tally.archived) k\(s.tally.kept) t\(s.tally.trashed) r\(s.tally.rescued)")
        out.append("[ui]")
        out.append("sidebarCollapsed=\(app.shell.sidebarCollapsed) paletteOpen=\(app.shell.paletteOpen) settingsOpen=\(app.shell.settingsOpen) section=\(app.settingsForm.activeSection.rawValue)")
        out.append("themePref=\(prefs.themePreference.rawValue) themeMode=\(prefs.themeMode.rawValue) colorScheme=\(String(describing: prefs.preferredColorScheme))")
        out.append("plain=\(prefs.preferPlainText) hud=\(prefs.showKeyboardHUD) ai=\(prefs.aiReasoningExpanded) rail=\(prefs.inspectorRailOpen)")
        out.append("allowedRemote=\(deck.allowedRemoteImageIds.map(\.rawValue).sorted().joined(separator: ","))")
        out.append("source=\(deck.sourceMode.rawValue) access=\(deck.accessStatus) demo=\(deck.supportsDemoControls) error=\(deck.errorMessage ?? "nil") notice=\(deck.nativeNoticeURL ?? "nil")")
        out.append("settingsAccounts=\(app.settingsForm.accountItems.map { "\($0.id):\($0.label):\($0.tone.rawValue):\($0.archivePath)" }.joined(separator: ","))")
        out.append("[hud]")
        for item in app.hudItems {
            out.append("\(item.keys.joined(separator: "+"))|\(item.label)|disabled=\(item.disabled)")
        }
        out.append("[palette]")
        for c in app.paletteCommands {
            out.append("\(c.id)|\(c.group)|\(c.title)|\(c.subtitle ?? "-")|\(c.kbd ?? "-")|\(c.systemImage)|\(c.keywords)")
        }
        out.append("[defaults]")
        for key in ["mailroom-theme-pref", "mailroom-theme", "mailroom-show-hud", "mailroom-ai-expanded", "mailroom-inspector-rail"] {
            out.append("\(key)=\(defaults.object(forKey: key).map { "\($0)" } ?? "nil")")
        }
        return out.joined(separator: "\n") + "\n"
    }

    // MARK: Rendering

    func rootView() -> AnyView {
        AnyView(
            RootThemeHostView(model: RootViewModel(app: app))
                .preferredColorScheme(prefs.preferredColorScheme)
        )
    }

    var isDark: Bool { prefs.themeMode == .dark }
}
