import Foundation

/// 与 AppKit 解耦的按键输入（由 `NSEvent` 适配而来）
public struct KeyInput: Equatable, Sendable {
    public var keyCode: UInt16
    /// `charactersIgnoringModifiers`（注意：Shift 仍会生效，如 ⇧K → "K"）
    public var characters: String?
    public var command: Bool
    public var control: Bool
    public var option: Bool
    public var shift: Bool

    public init(keyCode: UInt16, characters: String?, command: Bool = false, control: Bool = false, option: Bool = false, shift: Bool = false) {
        self.keyCode = keyCode
        self.characters = characters
        self.command = command
        self.control = control
        self.option = option
        self.shift = shift
    }
}

/// 路由所需的界面上下文
public struct KeyContext: Equatable, Sendable {
    public enum RowKind: Equatable, Sendable {
        case none
        case inbox
        case kept
        case handled
    }

    public var paletteOpen: Bool
    public var settingsOpen: Bool
    public var sidebarPeeking: Bool
    /// 第一响应者是否为可编辑文本视图（搜索框、拼音候选等）
    public var isEditingText: Bool
    public var activeRow: RowKind

    public init(
        paletteOpen: Bool,
        settingsOpen: Bool,
        sidebarPeeking: Bool = false,
        isEditingText: Bool,
        activeRow: RowKind
    ) {
        self.paletteOpen = paletteOpen
        self.settingsOpen = settingsOpen
        self.sidebarPeeking = sidebarPeeking
        self.isEditingText = isEditingText
        self.activeRow = activeRow
    }
}

public enum KeyDecision: Equatable, Sendable {
    /// 不处理，交还系统继续分发
    case passThrough
    /// 吞掉事件并依次执行命令
    case consume([DeckCommand])
    /// 吞掉事件并让输入框交出焦点
    case resignFirstResponder
}

/// 全局键盘快捷键路由表。纯函数：同一输入与上下文恒得同一决定。
public enum KeyRouter {
    public enum KeyCode {
        public static let escape: UInt16 = 53
        public static let downArrow: UInt16 = 125
        public static let upArrow: UInt16 = 126
        public static let returnKey: UInt16 = 36
        public static let enter: UInt16 = 76
        public static let backspace: UInt16 = 51
        public static let forwardDelete: UInt16 = 117
        public static let space: UInt16 = 49
    }

    public static func route(_ key: KeyInput, _ ctx: KeyContext) -> KeyDecision {
        let chars = key.characters

        // ⌘, 随时开关设置台
        if key.command && !key.option && !key.control && !key.shift && chars == "," {
            return .consume([.closePalette, .toggleSettings])
        }
        // ⌘K 随时开关命令面板
        if key.command && !key.option && !key.control && chars?.lowercased() == "k" {
            return .consume([.togglePalette])
        }
        // ⌘\ 切换侧边栏
        if key.command && chars == "\\" {
            return .consume([.toggleSidebar])
        }

        // 命令面板打开时屏蔽单键快捷键
        if ctx.paletteOpen {
            if key.keyCode == KeyCode.escape {
                return .consume([.closePalette])
            }
            return .passThrough
        }

        // 设置台打开时：Esc 退出设置（若聚焦输入框则先移交焦点），并屏蔽收件箱单键热键
        if ctx.settingsOpen {
            if key.keyCode == KeyCode.escape {
                if ctx.isEditingText {
                    return .resignFirstResponder
                }
                return .consume([.closeSettings])
            }
            return .passThrough
        }
        if key.command || key.control || key.option {
            return .passThrough
        }
        if ctx.isEditingText {
            return .passThrough
        }

        let text = chars ?? ""

        // 方向键与删除/回车（条件不满足时继续向下匹配字符）
        switch key.keyCode {
        case KeyCode.escape:
            if ctx.sidebarPeeking {
                return .consume([.setSidebarPeeking(false)])
            }
        case KeyCode.downArrow:
            return .consume([.moveFocus(1)])
        case KeyCode.upArrow:
            return .consume([.moveFocus(-1)])
        case KeyCode.returnKey, KeyCode.enter:
            if ctx.activeRow != .none {
                return .consume([.openInNativeMail])
            }
        case KeyCode.backspace, KeyCode.forwardDelete:
            if ctx.activeRow == .inbox {
                return .consume([.card(.trash, nil)])
            }
        case KeyCode.space:
            if ctx.activeRow == .inbox {
                return .consume([.card(.archive, nil)])
            }
        default:
            break
        }

        if key.shift && text.lowercased() == "k" {
            if ctx.activeRow == .inbox {
                return .consume([.card(.keep, nil)])
            }
        }

        if key.shift && text.lowercased() == "i" {
            return .consume([.toggleInspectorRail])
        }

        switch text {
        case "j":
            return .consume([.moveFocus(1)])
        case "k":
            return .consume([.moveFocus(-1)])
        case "1":
            return .consume([.setFolder(.inbox)])
        case "2":
            return .consume([.setFolder(.archived)])
        case "3":
            return .consume([.setFolder(.trashed)])
        case "[":
            return .consume([.toggleSidebar])
        case "i", "I":
            if ctx.activeRow != .none {
                return .consume([.toggleAIReasoning])
            }
        case "z", "Z":
            return .consume([.undo])
        case "r", "R":
            if ctx.activeRow == .handled {
                return .consume([.rescueFocused])
            }
        default:
            break
        }

        return .passThrough
    }
}
