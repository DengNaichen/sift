import Foundation
import MailroomCore

/// 工作台内所有可由用户触发的意图。键盘、HUD、命令面板、菜单栏与界面按钮全部归一到这里，
/// 再由 `AppModel.perform(_:)` 统一执行。值类型、可比较 —— 因此 HUD / 面板 / 快捷键路由均可直接断言。
public enum DeckCommand: Hashable, Sendable {
    // 焦点与导航
    case moveFocus(Int)
    case select(MessageId)
    case setFolder(FolderId)
    case setAccountScope(AccountScope)
    /// 命令面板跳转到某封邮件：切回全部邮箱 → 切到所在分拣夹 → 聚焦
    case revealMail(MessageId, in: FolderId)

    // 拍板与撤销
    /// `nil` 表示当前焦点邮件
    case card(CardAction, MessageId?)
    case rescueFocused
    case rescue(MessageId)
    case undo
    case openInNativeMail

    // 阅读
    case toggleAIReasoning
    case toggleInspectorRail
    case toggleBodyFormat
    case allowRemoteImages(MessageId)

    // 数据源
    case syncNow
    case switchToLive
    case switchToDemo
    case simulateIncoming
    case resetDemo
    case dismissError
    case openFullDiskAccessSettings

    // 工作台外壳
    case toggleSidebar
    case toggleTheme
    case openPalette
    case closePalette
    case togglePalette
    case openSettings(SettingsSection?)
    case closeSettings
    case toggleSettings
}
