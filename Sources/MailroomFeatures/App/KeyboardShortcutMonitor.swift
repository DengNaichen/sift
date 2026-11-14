import AppKit
import MailroomCore

/// AppKit 胶水层：把 `NSEvent` 适配为 `KeyInput`，交给纯函数 `KeyRouter`（经 `AppModel.routeKey`）决策后执行。
@MainActor
enum KeyboardShortcutMonitor {
    static func install(app: AppModel) {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let input = KeyInput(
                keyCode: event.keyCode,
                characters: event.charactersIgnoringModifiers,
                command: flags.contains(.command),
                control: flags.contains(.control),
                option: flags.contains(.option),
                shift: flags.contains(.shift)
            )
            let isEditingText: Bool = {
                guard let responder = NSApp.keyWindow?.firstResponder as? NSTextView else { return false }
                return responder.isEditable
            }()

            switch app.routeKey(input, isEditingText: isEditingText) {
            case .passThrough:
                return event
            case .consume(let commands):
                for command in commands {
                    app.perform(command)
                }
                return nil
            case .resignFirstResponder:
                NSApp.keyWindow?.makeFirstResponder(nil)
                return nil
            }
        }
    }
}
