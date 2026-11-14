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

/// 三栏分栏工作台布局：左侧原生毛玻璃边栏（206pt + 1pt 通顶分割线）+ 右侧通顶铺满工作区（列表 + 阅读区，或设置工作区）+ 顶层浮层
struct RootDeckView: View {
    @Environment(\.palette) private var p
    let model: RootViewModel
    @State private var keyMonitorInstalled = false
    @State private var isHoveringLeftEdge = false
    @State private var isHoveringPeekDrawer = false
    @State private var peekShowTask: Task<Void, Never>?
    @State private var peekHideTask: Task<Void, Never>?

    private var showLeftSidebar: Bool { model.showLeftSidebar }
    private var canPeekSidebar: Bool { model.canPeekSidebar }
    private static let sidebarWidth: CGFloat = 206
    private static let mailListWidth: CGFloat = 352

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 窗口底层：左侧 206pt 原生毛玻璃透底，右侧实心 p.paper 通顶铺满，无任何错位拼缝
            HStack(spacing: 0) {
                ZStack {
                    WindowSidebarBackdrop(mode: p.mode)
                    p.canvas.opacity(p.mode == .dark ? 0.24 : 0.18)
                }
                .frame(width: showLeftSidebar ? Self.sidebarWidth : 0)
                .clipped()

                p.paper
            }
            .ignoresSafeArea()

            HStack(alignment: .top, spacing: 0) {
                Group {
                    if model.settingsOpen {
                        SettingsSidebarView(model: model.settings)
                    } else {
                        SidebarView(model: model.sidebar, isPeek: false)
                    }
                }
                .padding(.top, 4)
                .frame(width: Self.sidebarWidth)
                .frame(maxHeight: .infinity, alignment: .top)
                .frame(width: showLeftSidebar ? Self.sidebarWidth : 0, alignment: .trailing)
                .clipped()
                .opacity(showLeftSidebar ? 1 : 0)
                .allowsHitTesting(showLeftSidebar)
                .accessibilityHidden(!showLeftSidebar)

                // Apple 原生 SplitView 右侧工作区：无圆角无外边距，直接贴紧分割线通顶铺满
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
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .blur(radius: model.paletteOpen ? 5 : 0)
            .allowsHitTesting(!model.paletteOpen)
            .animation(.easeOut(duration: 0.16), value: model.paletteOpen)

            splitDividersOverlay
                .blur(radius: model.paletteOpen ? 5 : 0)
                .animation(.easeOut(duration: 0.16), value: model.paletteOpen)

            peekSidebarOverlay
                .blur(radius: model.paletteOpen ? 5 : 0)
                .allowsHitTesting(!model.paletteOpen)
                .animation(.easeOut(duration: 0.16), value: model.paletteOpen)

            if let noticeURL = model.nativeNoticeURL {
                NativeNoticeBanner(url: noticeURL)
                    .padding(.top, 16)
                    .frame(maxWidth: .infinity, alignment: .center)
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
        .onChange(of: model.sidebarCollapsed) { _, collapsed in
            if !collapsed {
                dismissPeekImmediately()
            }
        }
        .onChange(of: model.settingsOpen) { _, open in
            if open {
                dismissPeekImmediately()
            }
        }
        .onChange(of: model.paletteOpen) { _, open in
            if open {
                dismissPeekImmediately()
            }
        }
        .onChange(of: model.sidebarPeeking) { _, peeking in
            if !peeking {
                peekShowTask?.cancel()
                peekHideTask?.cancel()
                isHoveringLeftEdge = false
                isHoveringPeekDrawer = false
            }
        }
        .onAppear {
            guard !keyMonitorInstalled else { return }
            keyMonitorInstalled = true
            KeyboardShortcutMonitor.install(app: model.app)
        }
    }

    @ViewBuilder
    private var splitDividersOverlay: some View {
        HStack(spacing: 0) {
            if showLeftSidebar {
                Color.clear.frame(width: Self.sidebarWidth - 1)
                Rectangle()
                    .fill(p.lineStrong)
                    .frame(width: 1)
            }
            if !model.settingsOpen {
                Color.clear.frame(width: Self.mailListWidth - 1)
                Rectangle()
                    .fill(p.line)
                    .frame(width: 1)
            }
            Spacer(minLength: 0)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var peekSidebarOverlay: some View {
        ZStack(alignment: .topLeading) {
            if canPeekSidebar {
                Color.clear
                    .frame(width: 8)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        onLeftEdgeHoverChanged(hovering)
                    }
                    .padding(.top, 48)
            }

            if model.sidebarPeeking && canPeekSidebar {
                SidebarView(
                    model: model.sidebar,
                    isPeek: true,
                    onDismissPeek: {
                        dismissPeekImmediately()
                    }
                )
                .deckGlassRect(cornerRadius: 16)
                .shadow(color: .black.opacity(p.mode == .dark ? 0.36 : 0.12), radius: 22, x: 4, y: 8)
                .onHover { hovering in
                    onPeekDrawerHoverChanged(hovering)
                }
                .padding(.leading, 10)
                .padding(.top, 38)
                .padding(.bottom, 12)
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.spring(response: 0.25, dampingFraction: 0.86), value: model.sidebarPeeking)
    }

    private func onLeftEdgeHoverChanged(_ hovering: Bool) {
        isHoveringLeftEdge = hovering
        if hovering {
            peekHideTask?.cancel()
            guard canPeekSidebar, !model.sidebarPeeking else { return }
            peekShowTask?.cancel()
            peekShowTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(90))
                guard !Task.isCancelled, isHoveringLeftEdge, canPeekSidebar else { return }
                withAnimation(.spring(response: 0.26, dampingFraction: 0.84)) {
                    model.perform(.setSidebarPeeking(true))
                }
            }
        } else {
            peekShowTask?.cancel()
            schedulePeekDismissIfNeeded()
        }
    }

    private func onPeekDrawerHoverChanged(_ hovering: Bool) {
        isHoveringPeekDrawer = hovering
        if hovering {
            peekHideTask?.cancel()
        } else {
            schedulePeekDismissIfNeeded()
        }
    }

    private func schedulePeekDismissIfNeeded() {
        guard !isHoveringLeftEdge, !isHoveringPeekDrawer else { return }
        peekHideTask?.cancel()
        peekHideTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled, !isHoveringLeftEdge, !isHoveringPeekDrawer else { return }
            withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                model.perform(.setSidebarPeeking(false))
            }
        }
    }

    private func dismissPeekImmediately() {
        peekShowTask?.cancel()
        peekHideTask?.cancel()
        isHoveringLeftEdge = false
        isHoveringPeekDrawer = false
        withAnimation(.snappy(duration: 0.18)) {
            model.perform(.setSidebarPeeking(false))
        }
    }
}
