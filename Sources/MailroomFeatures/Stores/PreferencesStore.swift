import Foundation
import Observation
import SwiftUI

public enum ThemePreference: String, CaseIterable, Sendable {
    case system
    case light
    case dark
}

/// 跨重启持久化的界面偏好。主题只有一个可写真相（`themePreference`），`themeMode` 由偏好 + 系统外观推导。
@MainActor
@Observable
public final class PreferencesStore {
    enum Key {
        static let themePreference = "mailroom-theme-pref"
        /// 旧版本键：仍按原逻辑同步写入（见 README「已知问题」）
        static let legacyThemeMode = "mailroom-theme"
        static let showKeyboardHUD = "mailroom-show-hud"
        static let aiReasoningExpanded = "mailroom-ai-expanded"
        static let inspectorRailOpen = "mailroom-inspector-rail"
    }

    public private(set) var themePreference: ThemePreference {
        didSet { defaults.set(themePreference.rawValue, forKey: Key.themePreference) }
    }
    /// 最近一次观测到的系统外观（仅在 `.system` 偏好下参与推导）
    private var systemIsDark: Bool

    public var showKeyboardHUD: Bool {
        didSet { defaults.set(showKeyboardHUD, forKey: Key.showKeyboardHUD) }
    }
    public var aiReasoningExpanded: Bool {
        didSet { defaults.set(aiReasoningExpanded, forKey: Key.aiReasoningExpanded) }
    }
    public var inspectorRailOpen: Bool {
        didSet { defaults.set(inspectorRailOpen, forKey: Key.inspectorRailOpen) }
    }
    /// 会话级：正文优先纯文本（不持久化）
    public var preferPlainText: Bool = false

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let probeSystemIsDark: () -> Bool

    public init(defaults: UserDefaults, systemIsDark: @escaping () -> Bool) {
        self.defaults = defaults
        self.probeSystemIsDark = systemIsDark
        let systemDark = systemIsDark()
        if let savedPref = defaults.string(forKey: Key.themePreference),
           let pref = ThemePreference(rawValue: savedPref) {
            self.themePreference = pref
            self.systemIsDark = systemDark
        } else if let saved = defaults.string(forKey: Key.legacyThemeMode),
                  let mode = ThemeMode(rawValue: saved) {
            self.themePreference = (mode == .dark) ? .dark : .light
            self.systemIsDark = systemDark
        } else {
            self.themePreference = .system
            self.systemIsDark = systemDark
        }

        if defaults.object(forKey: Key.showKeyboardHUD) != nil {
            self.showKeyboardHUD = defaults.bool(forKey: Key.showKeyboardHUD)
        } else {
            self.showKeyboardHUD = true
        }
        if defaults.object(forKey: Key.aiReasoningExpanded) != nil {
            self.aiReasoningExpanded = defaults.bool(forKey: Key.aiReasoningExpanded)
        } else {
            self.aiReasoningExpanded = true
        }
        self.inspectorRailOpen = defaults.bool(forKey: Key.inspectorRailOpen)
    }

    // MARK: Derived

    public var themeMode: ThemeMode {
        switch themePreference {
        case .light: return .light
        case .dark: return .dark
        case .system: return systemIsDark ? .dark : .light
        }
    }

    public var palette: DeckPalette {
        themeMode == .dark ? .dark : .light
    }

    public var preferredColorScheme: ColorScheme? {
        switch themePreference {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    // MARK: Intents

    public func setThemePreference(_ pref: ThemePreference) {
        if pref == .system {
            systemIsDark = probeSystemIsDark()
        }
        themePreference = pref
        persistResolvedMode()
    }

    /// 只在「跟随系统」时响应窗口外观变化（显式浅/深色时窗口外观被 preferredColorScheme 覆盖，不可信）
    public func syncSystemColorScheme(_ scheme: ColorScheme) {
        guard themePreference == .system else { return }
        let resolved: ThemeMode = (scheme == .dark) ? .dark : .light
        if themeMode != resolved {
            systemIsDark = (resolved == .dark)
            persistResolvedMode()
        }
    }

    public func toggleTheme() {
        setThemePreference(themeMode == .dark ? .light : .dark)
    }

    private func persistResolvedMode() {
        defaults.set(themeMode.rawValue, forKey: Key.legacyThemeMode)
    }
}
