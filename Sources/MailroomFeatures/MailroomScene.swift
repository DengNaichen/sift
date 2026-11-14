import AppKit
import SwiftUI
import MailroomCore

public struct MailroomScene: Scene {
    let vm: DeckViewModel

    public init(vm: DeckViewModel) {
        self.vm = vm
    }

    public var body: some Scene {
        WindowGroup("Mailroom Deck") {
            RootThemeHostView(vm: vm)
                .preferredColorScheme(vm.preferredColorScheme)
                .frame(minWidth: 880, minHeight: 560)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1220, height: 780)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(vm.settingsOpen ? "返回收件箱" : "设置…") {
                    vm.toggleSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(after: .newItem) {
                Button("搜索与命令…") {
                    vm.paletteOpen.toggle()
                }
                .keyboardShortcut("k", modifiers: .command)

                Button("同步 Apple Mail") {
                    Task { await vm.reloadSnapshot(initial: false) }
                }
                .keyboardShortcut("r", modifiers: .command)

                Button(vm.sidebarCollapsed ? "展开左侧边栏" : "收起左侧边栏") {
                    vm.toggleSidebar()
                }
                .keyboardShortcut("\\", modifiers: .command)
                .disabled(vm.settingsOpen)
            }
        }
    }
}

struct RootThemeHostView: View {
    @Environment(\.colorScheme) private var systemColorScheme
    let vm: DeckViewModel

    var body: some View {
        RootDeckView(vm: vm)
            .environment(\.palette, vm.palette)
            .onChange(of: systemColorScheme, initial: true) { _, newScheme in
                vm.syncSystemColorScheme(newScheme)
            }
    }
}

struct RootDeckView: View {
    @Environment(\.palette) private var p
    let vm: DeckViewModel
    @State private var keyMonitorInstalled = false

    private var showLeftSidebar: Bool {
        vm.settingsOpen || !vm.sidebarCollapsed
    }

    var body: some View {
        ZStack(alignment: .top) {
            HStack(alignment: .top, spacing: 0) {
                Group {
                    if vm.settingsOpen {
                        SettingsSidebarView(vm: vm)
                    } else {
                        SidebarView(vm: vm)
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
                    if vm.settingsOpen {
                        SettingsWorkspaceView(vm: vm)
                    } else {
                        HStack(alignment: .top, spacing: 0) {
                            MailListView(vm: vm)
                            ReadingPaneView(vm: vm)
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

            if let noticeURL = vm.nativeNoticeURL {
                NativeNoticeBanner(url: noticeURL)
                    .padding(.top, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if vm.paletteOpen {
                CommandPaletteView(commands: vm.paletteCommands) {
                    vm.paletteOpen = false
                }
                .transition(.opacity)
            }
        }
        .onAppear {
            guard !keyMonitorInstalled else { return }
            keyMonitorInstalled = true
            installKeyboardShortcuts()
        }
    }

    private func installKeyboardShortcuts() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let hasCmd = flags.contains(.command)
            let hasCtrl = flags.contains(.control)
            let hasOpt = flags.contains(.option)
            let hasShift = flags.contains(.shift)

            // ⌘, 随时开关设置台
            if hasCmd && !hasOpt && !hasCtrl && !hasShift && event.charactersIgnoringModifiers == "," {
                vm.paletteOpen = false
                vm.toggleSettings()
                return nil
            }
            // ⌘K 随时开关命令面板
            if hasCmd && !hasOpt && !hasCtrl && event.charactersIgnoringModifiers?.lowercased() == "k" {
                vm.paletteOpen.toggle()
                return nil
            }
            // ⌘\ 切换侧边栏
            if hasCmd && event.charactersIgnoringModifiers == "\\" {
                vm.toggleSidebar()
                return nil
            }

            // 命令面板打开或正在文本输入（如搜索框 / 拼音候选）时屏蔽单键快捷键
            if vm.paletteOpen {
                if event.keyCode == 53 { // Escape
                    vm.paletteOpen = false
                    return nil
                }
                return event
            }

            // 设置台打开时：Esc 退出设置（若聚焦输入框则先移交焦点），并屏蔽收件箱单键归档/删除热键
            if vm.settingsOpen {
                if event.keyCode == 53 { // Escape
                    if let responder = NSApp.keyWindow?.firstResponder as? NSTextView,
                       responder.isEditable {
                        NSApp.keyWindow?.makeFirstResponder(nil)
                        return nil
                    }
                    vm.closeSettings()
                    return nil
                }
                return event
            }
            if hasCmd || hasCtrl || hasOpt {
                return event
            }
            if let responder = NSApp.keyWindow?.firstResponder as? NSTextView,
               responder.isEditable {
                return event
            }

            let keyCode = event.keyCode
            let chars = event.charactersIgnoringModifiers ?? ""

            // 方向键与删除/回车
            switch keyCode {
            case 125: // DownArrow
                vm.moveFocus(delta: 1)
                return nil
            case 126: // UpArrow
                vm.moveFocus(delta: -1)
                return nil
            case 36, 76: // Return / Enter
                if vm.activeRow != nil {
                    vm.openFocusedInNativeMail()
                    return nil
                }
            case 51, 117: // Backspace / Forward Delete
                if case .inbox = vm.activeRow {
                    vm.actOnCard(.trash)
                    return nil
                }
            case 49: // Space
                if case .inbox = vm.activeRow {
                    vm.actOnCard(.archive)
                    return nil
                }
            default:
                break
            }

            if hasShift && chars.lowercased() == "k" {
                if case .inbox = vm.activeRow {
                    vm.actOnCard(.keep)
                    return nil
                }
            }

            if hasShift && chars.lowercased() == "i" {
                vm.toggleInspectorRail()
                return nil
            }

            switch chars {
            case "j":
                vm.moveFocus(delta: 1)
                return nil
            case "k":
                vm.moveFocus(delta: -1)
                return nil
            case "1":
                vm.setFolder(.inbox)
                return nil
            case "2":
                vm.setFolder(.archived)
                return nil
            case "3":
                vm.setFolder(.trashed)
                return nil
            case "[":
                vm.toggleSidebar()
                return nil
            case "i", "I":
                if vm.activeRow != nil {
                    vm.toggleAIReasoning()
                    return nil
                }
            case "z", "Z":
                _ = vm.undo()
                return nil
            case "r", "R":
                if case .handled = vm.activeRow {
                    vm.rescueFocused()
                    return nil
                }
            default:
                break
            }

            return event
        }
    }
}
