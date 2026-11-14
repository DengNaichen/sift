import Foundation
import Testing
@testable import MailroomCore
@testable import MailroomFeatures

/// 快捷键路由表：期望值逐条转录自重构前 `RootDeckView.installKeyboardShortcuts` 的 NSEvent 闭包。
@Suite("KeyRouter · shortcut table")
struct KeyRouterTests {
    typealias K = KeyRouter.KeyCode

    static let idle = KeyContext(paletteOpen: false, settingsOpen: false, isEditingText: false, activeRow: .inbox)

    static func ctx(
        palette: Bool = false,
        settings: Bool = false,
        peeking: Bool = false,
        editing: Bool = false,
        row: KeyContext.RowKind = .inbox
    ) -> KeyContext {
        KeyContext(paletteOpen: palette, settingsOpen: settings, sidebarPeeking: peeking, isEditingText: editing, activeRow: row)
    }

    static func key(_ chars: String?, code: UInt16 = 0, cmd: Bool = false, ctrl: Bool = false, opt: Bool = false, shift: Bool = false) -> KeyInput {
        KeyInput(keyCode: code, characters: chars, command: cmd, control: ctrl, option: opt, shift: shift)
    }

    struct Case: CustomTestStringConvertible, Sendable {
        let name: String
        let input: KeyInput
        let context: KeyContext
        let expected: KeyDecision
        var testDescription: String { name }
    }

    static let cases: [Case] = [
        // 全局组合键：任何上下文都生效
        Case(name: "⌘, closes palette then toggles settings", input: key(",", cmd: true), context: ctx(palette: true), expected: .consume([.closePalette, .toggleSettings])),
        Case(name: "⌘, works while editing text", input: key(",", cmd: true), context: ctx(settings: true, editing: true), expected: .consume([.closePalette, .toggleSettings])),
        Case(name: "⇧⌘, is not settings", input: key(",", cmd: true, shift: true), context: ctx(), expected: .passThrough),
        Case(name: "⌘K toggles palette", input: key("k", cmd: true), context: ctx(), expected: .consume([.togglePalette])),
        Case(name: "⇧⌘K also toggles palette", input: key("K", cmd: true, shift: true), context: ctx(settings: true), expected: .consume([.togglePalette])),
        Case(name: "⌥⌘K passes through", input: key("k", cmd: true, opt: true), context: ctx(), expected: .passThrough),
        Case(name: "⌘\\ toggles sidebar even in palette", input: key("\\", cmd: true), context: ctx(palette: true), expected: .consume([.toggleSidebar])),

        // 命令面板打开
        Case(name: "palette: Esc closes", input: key("\u{1b}", code: K.escape), context: ctx(palette: true), expected: .consume([.closePalette])),
        Case(name: "palette: j passes to text field", input: key("j"), context: ctx(palette: true), expected: .passThrough),
        Case(name: "palette: Space passes", input: key(" ", code: K.space), context: ctx(palette: true), expected: .passThrough),

        // 设置台打开
        Case(name: "settings: Esc closes settings", input: key("\u{1b}", code: K.escape), context: ctx(settings: true), expected: .consume([.closeSettings])),
        Case(name: "settings: Esc while editing resigns focus first", input: key("\u{1b}", code: K.escape), context: ctx(settings: true, editing: true), expected: .resignFirstResponder),
        Case(name: "settings: Space blocked from archiving", input: key(" ", code: K.space), context: ctx(settings: true), expected: .passThrough),
        Case(name: "settings: z blocked", input: key("z"), context: ctx(settings: true), expected: .passThrough),

        // 修饰键 / 文本输入
        Case(name: "⌃j passes", input: key("j", ctrl: true), context: ctx(), expected: .passThrough),
        Case(name: "⌥z passes", input: key("z", opt: true), context: ctx(), expected: .passThrough),
        Case(name: "⌘Z passes (system undo)", input: key("z", cmd: true), context: ctx(), expected: .passThrough),
        Case(name: "editing text: j passes", input: key("j"), context: ctx(editing: true), expected: .passThrough),
        Case(name: "editing text: Esc passes outside settings", input: key("\u{1b}", code: K.escape), context: ctx(editing: true), expected: .passThrough),
        Case(name: "peek sidebar: Esc dismisses peek", input: key("\u{1b}", code: K.escape), context: ctx(peeking: true), expected: .consume([.setSidebarPeeking(false)])),

        // 方向键
        Case(name: "↓ moves down", input: key("\u{F701}", code: K.downArrow), context: ctx(row: .none), expected: .consume([.moveFocus(1)])),
        Case(name: "↑ moves up", input: key("\u{F700}", code: K.upArrow), context: ctx(row: .handled), expected: .consume([.moveFocus(-1)])),

        // 回车
        Case(name: "Return opens in Mail", input: key("\r", code: K.returnKey), context: ctx(row: .kept), expected: .consume([.openInNativeMail])),
        Case(name: "Enter opens in Mail", input: key("\u{3}", code: K.enter), context: ctx(row: .handled), expected: .consume([.openInNativeMail])),
        Case(name: "Return without focus passes", input: key("\r", code: K.returnKey), context: ctx(row: .none), expected: .passThrough),

        // 删除 / 空格（仅收件箱行）
        Case(name: "⌫ trashes inbox row", input: key("\u{7f}", code: K.backspace), context: ctx(row: .inbox), expected: .consume([.card(.trash, nil)])),
        Case(name: "⌦ trashes inbox row", input: key("\u{F728}", code: K.forwardDelete), context: ctx(row: .inbox), expected: .consume([.card(.trash, nil)])),
        Case(name: "⌫ on handled row passes", input: key("\u{7f}", code: K.backspace), context: ctx(row: .handled), expected: .passThrough),
        Case(name: "Space archives inbox row", input: key(" ", code: K.space), context: ctx(row: .inbox), expected: .consume([.card(.archive, nil)])),
        Case(name: "Space on kept row passes", input: key(" ", code: K.space), context: ctx(row: .kept), expected: .passThrough),

        // Shift 组合
        Case(name: "⇧K keeps inbox row", input: key("K", shift: true), context: ctx(row: .inbox), expected: .consume([.card(.keep, nil)])),
        Case(name: "⇧K on handled row passes (no lowercase k match)", input: key("K", shift: true), context: ctx(row: .handled), expected: .passThrough),
        Case(name: "⇧I toggles inspector rail even without focus", input: key("I", shift: true), context: ctx(row: .none), expected: .consume([.toggleInspectorRail])),

        // 单字符
        Case(name: "j moves down", input: key("j"), context: ctx(row: .none), expected: .consume([.moveFocus(1)])),
        Case(name: "k moves up", input: key("k"), context: ctx(row: .none), expected: .consume([.moveFocus(-1)])),
        Case(name: "1 → inbox", input: key("1"), context: ctx(), expected: .consume([.setFolder(.inbox)])),
        Case(name: "2 → archived", input: key("2"), context: ctx(), expected: .consume([.setFolder(.archived)])),
        Case(name: "3 → trashed", input: key("3"), context: ctx(), expected: .consume([.setFolder(.trashed)])),
        Case(name: "4 passes", input: key("4"), context: ctx(), expected: .passThrough),
        Case(name: "[ toggles sidebar", input: key("["), context: ctx(), expected: .consume([.toggleSidebar])),
        Case(name: "i toggles AI reasoning", input: key("i"), context: ctx(row: .kept), expected: .consume([.toggleAIReasoning])),
        Case(name: "i without focus passes", input: key("i"), context: ctx(row: .none), expected: .passThrough),
        Case(name: "z undoes even with empty context", input: key("z"), context: ctx(row: .none), expected: .consume([.undo])),
        Case(name: "Z (caps lock) undoes", input: key("Z"), context: ctx(), expected: .consume([.undo])),
        Case(name: "r rescues handled row", input: key("r"), context: ctx(row: .handled), expected: .consume([.rescueFocused])),
        Case(name: "R rescues handled row", input: key("R"), context: ctx(row: .handled), expected: .consume([.rescueFocused])),
        Case(name: "r on inbox row passes", input: key("r"), context: ctx(row: .inbox), expected: .passThrough),
        Case(name: "nil characters pass", input: key(nil, code: 999), context: ctx(), expected: .passThrough),
    ]

    @Test(arguments: cases)
    func route(_ c: Case) {
        #expect(KeyRouter.route(c.input, c.context) == c.expected)
    }
}
