import Foundation
import Observation

/// 工作台外壳的瞬时界面状态（不持久化）。变更入口统一在 `AppModel.perform(_:)`。
@MainActor
@Observable
public final class ShellState {
    public internal(set) var sidebarCollapsed: Bool = false
    public internal(set) var sidebarPeeking: Bool = false
    public internal(set) var paletteOpen: Bool = false
    public internal(set) var settingsOpen: Bool = false

    public init() {}
}
