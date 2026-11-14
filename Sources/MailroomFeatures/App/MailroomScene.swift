import AppKit
import SwiftUI
import MailroomCore

/// 应用场景：窗口与菜单栏命令。可执行目标只需 `MailroomScene(app:)`。
public struct MailroomScene: Scene {
    let app: AppModel

    public init(app: AppModel) {
        self.app = app
    }

    private var model: RootViewModel { RootViewModel(app: app) }

    public var body: some Scene {
        WindowGroup("Mailroom Deck") {
            RootThemeHostView(model: model)
                .preferredColorScheme(model.preferredColorScheme)
                .frame(minWidth: 880, minHeight: 560)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1220, height: 780)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(model.settingsOpen ? "返回收件箱" : "设置…") {
                    model.perform(.toggleSettings)
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(after: .newItem) {
                Button("搜索与命令…") {
                    model.perform(.togglePalette)
                }
                .keyboardShortcut("k", modifiers: .command)

                Button("同步 Apple Mail") {
                    model.perform(.syncNow)
                }
                .keyboardShortcut("r", modifiers: .command)

                Button(model.sidebarCollapsed ? "展开左侧边栏" : "收起左侧边栏") {
                    model.perform(.toggleSidebar)
                }
                .keyboardShortcut("\\", modifiers: .command)
                .disabled(model.settingsOpen)
            }
        }
    }
}

/// 注入主题调色板，并把窗口外观变化回传给偏好（仅「跟随系统」时生效）
struct RootThemeHostView: View {
    @Environment(\.colorScheme) private var systemColorScheme
    let model: RootViewModel

    var body: some View {
        RootDeckView(model: model)
            .environment(\.palette, model.palette)
            .onChange(of: systemColorScheme, initial: true) { _, newScheme in
                model.syncSystemColorScheme(newScheme)
            }
    }
}

/// 三栏工作台布局：左侧导航（或设置导航）+ 内嵌纸页（列表 + 阅读区，或设置工作区）+ 顶层浮层
struct RootDeckView: View {
    @Environment(\.palette) private var p
    let model: RootViewModel
    @State private var keyMonitorInstalled = false

    private var showLeftSidebar: Bool { model.showLeftSidebar }

    var body: some View {
        ZStack(alignment: .top) {
            HStack(alignment: .top, spacing: 0) {
                Group {
                    if model.settingsOpen {
                        SettingsSidebarView(model: model.settings)
                    } else {
                        SidebarView(model: model.sidebar)
                    }
                }
                .padding(.top, 6)
                .frame(width: 206)
                .frame(maxHeight: .infinity, alignment: .top)
                .frame(width: showLeftSidebar ? 206 : 0, alignment: .trailing)
                .clipped()
                .opacity(showLeftSidebar ? 1 : 0)
                .allowsHitTesting(showLeftSidebar)
                .accessibilityHidden(!showLeftSidebar)

                // Linear 式内嵌工作台纸页（顶部间距恒定为 6pt，收起/展开侧边栏或进入设置时原地切换）
                Group {
                    if model.settingsOpen {
                        SettingsWorkspaceView(model: model.settings)
                    } else {
                        HStack(alignment: .top, spacing: 0) {
                            MailListView(model: model.mailList)
                            ReadingPaneView(model: model.readingPane)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(p.paper)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(p.line, lineWidth: 1)
                )
                .shadow(color: .black.opacity(p.mode == .dark ? 0.35 : 0.035), radius: 3, y: 1)
                .padding(.top, 6)
                .padding(.bottom, 6)
                .padding(.trailing, 6)
                .padding(.leading, showLeftSidebar ? 0 : 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(p.canvas.ignoresSafeArea())

            if let noticeURL = model.nativeNoticeURL {
                NativeNoticeBanner(url: noticeURL)
                    .padding(.top, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if model.paletteOpen {
                CommandPaletteView(
                    commands: model.paletteCommands,
                    onClose: { model.perform(.closePalette) },
                    onRun: model.perform
                )
                .transition(.opacity)
            }
        }
        .onAppear {
            guard !keyMonitorInstalled else { return }
            keyMonitorInstalled = true
            KeyboardShortcutMonitor.install(app: model.app)
        }
    }
}
