import Foundation
import SwiftUI
import MailroomCore

/// 根布局：决定显示收件箱还是设置台、浮层开关，并为子区域投影各自的 ViewModel。
@MainActor
struct RootViewModel {
    let app: AppModel

    var settingsOpen: Bool { app.shell.settingsOpen }
    var sidebarCollapsed: Bool { app.shell.sidebarCollapsed }
    var sidebarPeeking: Bool { app.shell.sidebarPeeking }
    var paletteOpen: Bool { app.shell.paletteOpen }
    /// 设置台打开时左栏恒显示（作为设置导航）
    var showLeftSidebar: Bool { app.shell.settingsOpen || !app.shell.sidebarCollapsed }
    var canPeekSidebar: Bool { app.shell.sidebarCollapsed && !app.shell.settingsOpen && !app.shell.paletteOpen }
    var nativeNoticeURL: String? { app.deck.nativeNoticeURL }
    var paletteCommands: [PaletteCommand] { app.paletteCommands }

    var palette: DeckPalette { app.preferences.palette }
    var preferredColorScheme: ColorScheme? { app.preferences.preferredColorScheme }
    func syncSystemColorScheme(_ scheme: ColorScheme) { app.preferences.syncSystemColorScheme(scheme) }

    var sidebar: SidebarViewModel { SidebarViewModel(app: app) }
    var mailList: MailListViewModel { MailListViewModel(app: app) }
    var readingPane: ReadingPaneViewModel { ReadingPaneViewModel(app: app) }
    var settings: SettingsViewModel { SettingsViewModel(app: app) }

    func perform(_ command: DeckCommand) { app.perform(command) }
}
