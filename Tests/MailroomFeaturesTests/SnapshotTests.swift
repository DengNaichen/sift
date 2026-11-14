import Foundation
import Testing
@testable import MailroomCore
@testable import MailroomFeatures

/// 视觉基线：重构前录制，重构后逐像素比对。
@MainActor
@Suite("Characterization · visual snapshots", .serialized)
struct SnapshotTests {
    private func snap(_ h: DeckHarness, _ name: String, sourceLocation: SourceLocation = #_sourceLocation) async {
        await Snapshot.assertMatches(h.rootView(), dark: h.isDark, named: name, sourceLocation: sourceLocation)
    }

    private func darkDefaults() -> UserDefaults {
        let d = makeIsolatedDefaults()
        d.set("dark", forKey: "mailroom-theme-pref")
        return d
    }

    @Test func inboxLight() async {
        let h = await DeckHarness()
        await snap(h, "inbox-light")
    }

    @Test func inboxDark() async {
        let h = await DeckHarness(defaults: darkDefaults())
        await snap(h, "inbox-dark")
    }

    @Test func afterArchiveToast() async {
        let h = await DeckHarness()
        h.archive()
        await snap(h, "after-archive-toast")
    }

    @Test func archivedFolderFocused() async {
        let h = await DeckHarness()
        h.setFolder(.archived)
        h.moveFocus(2)
        await snap(h, "archived-focused")
    }

    @Test func keptFolder() async {
        let h = await DeckHarness()
        h.keep()
        h.setFolder(.kept)
        await snap(h, "kept-folder")
    }

    @Test func sidebarCollapsed() async {
        let h = await DeckHarness()
        h.toggleSidebar()
        await snap(h, "sidebar-collapsed")
    }

    @Test func scopedToSecondAccount() async {
        let h = await DeckHarness()
        h.setScope(.account(h.state.accounts.last!.id))
        await snap(h, "scope-second-account")
    }

    @Test func inboxZero() async {
        let h = await DeckHarness()
        while !h.state.queue.isEmpty { h.archive() }
        await snap(h, "inbox-zero")
    }

    @Test func emptyTrashedFolderDark() async {
        let h = await DeckHarness(defaults: darkDefaults())
        h.setFolder(.kept)
        await snap(h, "kept-empty-dark")
    }

    @Test func hudHidden() async {
        let h = await DeckHarness()
        h.setShowKeyboardHUD(false)
        await snap(h, "hud-hidden")
    }

    @Test(arguments: SettingsSection.allCases)
    func settingsSection(_ section: SettingsSection) async {
        let h = await DeckHarness()
        h.openSettings(section)
        await snap(h, "settings-\(section.rawValue)")
    }

    @Test func settingsAppearanceDark() async {
        let h = await DeckHarness(defaults: darkDefaults())
        h.openSettings(.appearance)
        await snap(h, "settings-appearance-dark")
    }
}
