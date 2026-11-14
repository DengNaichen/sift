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
    let vm: DeckViewModel
    let defaults: UserDefaults

    init(defaults: UserDefaults = makeIsolatedDefaults(), systemIsDark: Bool = false) async {
        self.defaults = defaults
        self.vm = DeckViewModel(environment: makeTestEnvironment(defaults: defaults, systemIsDark: systemIsDark))
        let vm = self.vm
        await waitUntil { vm.state.phase == .ready }
    }

    // MARK: Intents

    func archive() { vm.actOnCard(.archive) }
    func keep() { vm.actOnCard(.keep) }
    func trash() { vm.actOnCard(.trash) }
    func undo() { _ = vm.undo() }
    func setFolder(_ f: FolderId) { vm.setFolder(f) }
    func setScope(_ s: AccountScope) { vm.setAccountScope(s) }
    func moveFocus(_ d: Int) { vm.moveFocus(delta: d) }
    func select(_ id: MessageId) { vm.selectRow(id) }
    func rescueFocused() async {
        let before = vm.state.handled.count
        vm.rescueFocused()
        let vm = self.vm
        await waitUntil { vm.state.handled.count < before }
    }
    func toggleAIReasoning() { vm.toggleAIReasoning() }
    func toggleInspectorRail() { vm.toggleInspectorRail() }
    func toggleBodyFormat() { vm.toggleBodyFormat() }
    func allowRemoteImagesForFocused() { if let id = vm.state.focusId { vm.allowRemoteImages(for: id) } }
    func toggleSidebar() { vm.toggleSidebar() }
    func toggleTheme() { vm.toggleTheme() }
    func setThemePreference(_ p: ThemePreference) { vm.setThemePreference(p) }
    func syncSystemColorScheme(_ s: ColorScheme) { vm.syncSystemColorScheme(s) }
    func openSettings(_ s: SettingsSection? = nil) { vm.openSettings(s) }
    func closeSettings() { vm.closeSettings() }
    func openPalette() { vm.paletteOpen = true }
    func setShowKeyboardHUD(_ v: Bool) { vm.showKeyboardHUD = v }

    /// 执行命令面板中指定 id 的命令（模拟用户在面板中回车：先关面板再执行）
    func runPalette(_ id: String) {
        guard let cmd = vm.paletteCommands.first(where: { $0.id == id }) else {
            fatalError("palette command \(id) not found")
        }
        vm.paletteOpen = false
        cmd.run()
    }

    /// 点击 HUD 中指定 label 的按钮
    func tapHUD(_ label: String) {
        guard let item = vm.hudItems.first(where: { $0.label == label }) else {
            fatalError("hud item \(label) not found")
        }
        item.action()
    }

    // MARK: Observation

    var state: DeckState { vm.state }
    var paletteOpen: Bool { vm.paletteOpen }
    var settingsOpen: Bool { vm.settingsOpen }

    func dump() -> String {
        var out: [String] = []
        let s = vm.state
        out.append("[state]")
        out.append("phase=\(s.phase) folder=\(s.folder.rawValue) scope=\(s.accountScope) focus=\(s.focusId?.rawValue ?? "nil")")
        out.append("visible=\(vm.visibleRows.map(\.id.rawValue).joined(separator: ","))")
        out.append("activeIndex=\(vm.activeIndex.map(String.init) ?? "nil") activeAccount=\(vm.activeAccount?.id ?? "nil")")
        out.append("counts=\(FolderId.allCases.map { "\($0.rawValue):\(vm.counts[$0] ?? -1)" }.joined(separator: ","))")
        out.append("accounts=\(vm.accounts.map(\.id).joined(separator: ","))")
        out.append("read=\(s.readIds.map(\.rawValue).sorted().joined(separator: ","))")
        out.append("queue=\(s.queue.map(\.id.rawValue).joined(separator: ","))")
        out.append("kept=\(s.kept.map(\.id.rawValue).joined(separator: ","))")
        out.append("handled=\(s.handled.map { "\($0.id.rawValue)/\($0.disposition)/\($0.manual)" }.joined(separator: ","))")
        out.append("undo=\(s.undo.map(\.descriptionText).joined(separator: " | "))")
        out.append("toast=\(s.toast.map { "\($0.seq)/\($0.kind)/\($0.entry.descriptionText)" } ?? "nil") seq=\(s.seq)")
        out.append("tally=a\(s.tally.archived) k\(s.tally.kept) t\(s.tally.trashed) r\(s.tally.rescued)")
        out.append("[ui]")
        out.append("sidebarCollapsed=\(vm.sidebarCollapsed) paletteOpen=\(vm.paletteOpen) settingsOpen=\(vm.settingsOpen) section=\(vm.settings.activeSection.rawValue)")
        out.append("themePref=\(vm.themePreference.rawValue) themeMode=\(vm.themeMode.rawValue) colorScheme=\(String(describing: vm.preferredColorScheme))")
        out.append("plain=\(vm.preferPlainText) hud=\(vm.showKeyboardHUD) ai=\(vm.aiReasoningExpanded) rail=\(vm.inspectorRailOpen)")
        out.append("allowedRemote=\(vm.allowedRemoteImageIds.map(\.rawValue).sorted().joined(separator: ","))")
        out.append("source=\(vm.sourceMode.rawValue) access=\(vm.accessStatus) demo=\(vm.supportsDemoControls) error=\(vm.errorMessage ?? "nil") notice=\(vm.nativeNoticeURL ?? "nil")")
        out.append("settingsAccounts=\(vm.settings.accountItems.map { "\($0.id):\($0.label):\($0.tone.rawValue):\($0.archivePath)" }.joined(separator: ","))")
        out.append("[hud]")
        for item in vm.hudItems {
            out.append("\(item.keys.joined(separator: "+"))|\(item.label)|disabled=\(item.disabled)")
        }
        out.append("[palette]")
        for c in vm.paletteCommands {
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
            RootThemeHostView(vm: vm)
                .preferredColorScheme(vm.preferredColorScheme)
        )
    }

    var isDark: Bool { vm.themeMode == .dark }
}
