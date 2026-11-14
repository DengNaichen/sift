import AppKit
import Foundation
import SwiftUI
import MailroomCore

/// 组装入口注入的全部外部依赖。生产环境用 `.live`，测试 / Preview 用自定义实例。
@MainActor
public struct AppEnvironment {
    /// 探测本机 Apple Mail 本地库访问权限
    public var checkAccess: () -> MailAccessStatus
    /// 构造真机适配器（失败返回 nil，调用方回退演示数据）
    public var makeLiveAdapter: () -> (any MailAdapter)?
    /// 构造演示数据适配器
    public var makeDemoAdapter: () -> any MailAdapter
    /// 偏好持久化
    public var defaults: UserDefaults
    /// 当前系统外观是否为深色（NSApp.effectiveAppearance）
    public var systemIsDark: () -> Bool
    /// 打开「完全磁盘访问权限」系统设置
    public var openFullDiskAccessSettings: () -> Void
    /// 以 `.snappy(duration:)` 包裹状态变更；测试中可替换为直接执行
    public var animate: (_ snappyDuration: Double, _ body: () -> Void) -> Void
    /// 计时器睡眠（toast / notice 自动消失）
    public var sleep: @Sendable (_ nanoseconds: UInt64) async throws -> Void

    public init(
        checkAccess: @escaping () -> MailAccessStatus,
        makeLiveAdapter: @escaping () -> (any MailAdapter)?,
        makeDemoAdapter: @escaping () -> any MailAdapter,
        defaults: UserDefaults,
        systemIsDark: @escaping () -> Bool,
        openFullDiskAccessSettings: @escaping () -> Void,
        animate: @escaping (_ snappyDuration: Double, _ body: () -> Void) -> Void,
        sleep: @escaping @Sendable (_ nanoseconds: UInt64) async throws -> Void
    ) {
        self.checkAccess = checkAccess
        self.makeLiveAdapter = makeLiveAdapter
        self.makeDemoAdapter = makeDemoAdapter
        self.defaults = defaults
        self.systemIsDark = systemIsDark
        self.openFullDiskAccessSettings = openFullDiskAccessSettings
        self.animate = animate
        self.sleep = sleep
    }

    public static var live: AppEnvironment {
        AppEnvironment(
            checkAccess: { MailStoreEnvironment.checkAccess() },
            makeLiveAdapter: { try? AppleMailAdapter(maxInboxFetch: 100) },
            makeDemoAdapter: { MockMailAdapter() },
            defaults: .standard,
            systemIsDark: {
                NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            },
            openFullDiskAccessSettings: { MailStoreEnvironment.openFullDiskAccessSettings() },
            animate: { duration, body in
                withAnimation(.snappy(duration: duration), body)
            },
            sleep: { nanoseconds in
                try await Task.sleep(nanoseconds: nanoseconds)
            }
        )
    }
}
