import Foundation
import Testing
@testable import MailroomCore
@testable import MailroomFeatures

/// 特征测试：锁定重构前 DeckViewModel 的可观察行为（状态、HUD、命令面板、偏好持久化）。
@MainActor
@Suite("Characterization · behavior goldens", .serialized)
struct CharacterizationTests {
    @Test("Initial demo load")
    func initialLoad() async {
        let h = await DeckHarness()
        Golden.assertMatches(h.dump(), named: "01-initial")
    }

    @Test("Archive / keep / trash then multi-step undo")
    func triageAndUndo() async {
        let h = await DeckHarness()
        h.archive()
        Golden.assertMatches(h.dump(), named: "02a-after-archive")
        h.keep()
        Golden.assertMatches(h.dump(), named: "02b-after-keep")
        h.trash()
        Golden.assertMatches(h.dump(), named: "02c-after-trash")
        h.undo()
        Golden.assertMatches(h.dump(), named: "02d-after-undo1")
        h.undo()
        h.undo()
        Golden.assertMatches(h.dump(), named: "02e-after-undo3")
        h.undo() // 空栈，无副作用
        Golden.assertMatches(h.dump(), named: "02e-after-undo3")
    }

    @Test("Handled folder: focus movement and rescue, then undo rescue")
    func rescueFlow() async {
        let h = await DeckHarness()
        h.setFolder(.archived)
        h.moveFocus(1)
        h.moveFocus(1)
        h.moveFocus(-1)
        Golden.assertMatches(h.dump(), named: "03a-archived-focus")
        await h.rescueFocused()
        Golden.assertMatches(h.dump(), named: "03b-after-rescue")
        h.undo()
        Golden.assertMatches(h.dump(), named: "03c-after-undo-rescue")
        h.setFolder(.trashed)
        Golden.assertMatches(h.dump(), named: "03d-trashed")
        h.setFolder(.kept)
        Golden.assertMatches(h.dump(), named: "03e-kept-empty")
    }

    @Test("Account scope and sub folders")
    func scopes() async {
        let h = await DeckHarness()
        let second = h.state.accounts.last!.id
        h.setScope(.account(second))
        Golden.assertMatches(h.dump(), named: "04a-scope-second")
        h.setFolder(.inboxHuman)
        Golden.assertMatches(h.dump(), named: "04b-scope-second-human")
        h.setScope(.all)
        h.setFolder(.inboxStakes)
        Golden.assertMatches(h.dump(), named: "04c-stakes")
        h.setFolder(.inboxUncertain)
        Golden.assertMatches(h.dump(), named: "04d-uncertain")
    }

    @Test("Chrome toggles, theme and persisted preferences")
    func toggles() async {
        let h = await DeckHarness()
        h.toggleAIReasoning()
        Golden.assertMatches(h.dump(), named: "05a-ai-collapsed")
        h.toggleInspectorRail()
        h.toggleAIReasoning() // 侧栏打开时：关闭侧栏而非切换判据条
        Golden.assertMatches(h.dump(), named: "05b-rail-closed-by-ai")
        h.toggleBodyFormat()
        h.allowRemoteImagesForFocused()
        h.toggleSidebar()
        h.toggleTheme()
        h.setShowKeyboardHUD(false)
        Golden.assertMatches(h.dump(), named: "05c-misc-toggles")
        h.setThemePreference(.system)
        h.syncSystemColorScheme(.dark)
        Golden.assertMatches(h.dump(), named: "05d-system-dark")
        h.setThemePreference(.light)
        h.syncSystemColorScheme(.dark) // 非 system 偏好时忽略
        Golden.assertMatches(h.dump(), named: "05e-light-ignores-system")
    }

    @Test("Settings open/close, sidebar locked while settings open")
    func settings() async {
        let h = await DeckHarness()
        h.openSettings(.ai)
        Golden.assertMatches(h.dump(), named: "06a-settings-ai")
        h.toggleSidebar() // 设置打开时无效
        Golden.assertMatches(h.dump(), named: "06a-settings-ai")
        h.runPalette("close-settings")
        Golden.assertMatches(h.dump(), named: "06b-settings-closed")
        h.openSettings()
        Golden.assertMatches(h.dump(), named: "06c-settings-reopened-same-section")
    }

    @Test("Palette & HUD driven commands")
    func paletteAndHud() async {
        let h = await DeckHarness()
        let target = h.state.handled.first { $0.disposition == .trashed }!.id
        h.runPalette("handled-\(target.rawValue)")
        Golden.assertMatches(h.dump(), named: "07a-palette-reveal-handled")
        h.runPalette("folder-inbox")
        h.tapHUD("切换")
        h.tapHUD("归档")
        Golden.assertMatches(h.dump(), named: "07b-hud-move-archive")
        h.tapHUD("撤销")
        h.runPalette("sidebar")
        h.runPalette("theme")
        Golden.assertMatches(h.dump(), named: "07c-palette-sidebar-theme")
        h.tapHUD("命令")
        Golden.assertMatches(h.dump(), named: "07d-hud-opens-palette")
    }

    @Test("Inbox zero after clearing the queue")
    func inboxZero() async {
        let h = await DeckHarness()
        while !h.state.queue.isEmpty {
            h.archive()
        }
        Golden.assertMatches(h.dump(), named: "08-inbox-zero")
    }

    @Test("Persisted preferences are restored on next launch")
    func persistence() async {
        let defaults = makeIsolatedDefaults()
        do {
            let h = await DeckHarness(defaults: defaults)
            h.setThemePreference(.dark)
            h.setShowKeyboardHUD(false)
            h.toggleAIReasoning()
            h.toggleInspectorRail()
        }
        let h2 = await DeckHarness(defaults: defaults)
        Golden.assertMatches(h2.dump(), named: "09a-restored")

        let legacy = makeIsolatedDefaults()
        legacy.set("dark", forKey: "mailroom-theme")
        let h3 = await DeckHarness(defaults: legacy)
        Golden.assertMatches(h3.dump(), named: "09b-legacy-theme-key")

        let fresh = makeIsolatedDefaults()
        let h4 = await DeckHarness(defaults: fresh, systemIsDark: true)
        Golden.assertMatches(h4.dump(), named: "09c-fresh-system-dark")
    }
}
