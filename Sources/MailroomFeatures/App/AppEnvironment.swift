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
    /// 偏好持久化（严禁存储 API Key）
    public var defaults: UserDefaults
    /// 敏感凭据存储（生产环境走 macOS Keychain，测试环境走内存）
    public var secretStore: any SecretStore
    /// 当前系统外观是否为深色（NSApp.effectiveAppearance）
    public var systemIsDark: () -> Bool
    /// 打开「完全磁盘访问权限」系统设置
    public var openFullDiskAccessSettings: () -> Void
    /// 热更新共享分类器的配置与用户分拣偏好
    public var updateClassifierConfiguration: (SiftClassifierConfiguration) -> Void
    /// 实测决策模型端点连通性与往返延迟（毫秒）
    public var testAIConnection: @Sendable (_ endpoint: String, _ model: String, _ apiKey: String) async throws -> Double
    /// 清空并重建分类器正交信号缓存
    public var rebuildClassifierCache: () async throws -> Void
    /// 读取本地缓存体积文本（供诊断页展示）
    public var classifierCacheSizeText: () -> String
    /// 以 `.snappy(duration:)` 包裹状态变更；测试中可替换为直接执行
    public var animate: (_ snappyDuration: Double, _ body: () -> Void) -> Void
    /// 计时器睡眠（toast / notice 自动消失）
    public var sleep: @Sendable (_ nanoseconds: UInt64) async throws -> Void

    public init(
        checkAccess: @escaping () -> MailAccessStatus,
        makeLiveAdapter: @escaping () -> (any MailAdapter)?,
        makeDemoAdapter: @escaping () -> any MailAdapter,
        defaults: UserDefaults,
        secretStore: any SecretStore = InMemorySecretStore(),
        systemIsDark: @escaping () -> Bool,
        openFullDiskAccessSettings: @escaping () -> Void,
        updateClassifierConfiguration: @escaping (SiftClassifierConfiguration) -> Void = { _ in },
        testAIConnection: @escaping @Sendable (_ endpoint: String, _ model: String, _ apiKey: String) async throws -> Double = { _, _, apiKey in
            if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw GeminiDecisionsError.missingAPIKey
            }
            return 240.0
        },
        rebuildClassifierCache: @escaping () async throws -> Void = {},
        classifierCacheSizeText: @escaping () -> String = { "14.2 MB" },
        animate: @escaping (_ snappyDuration: Double, _ body: () -> Void) -> Void,
        sleep: @escaping @Sendable (_ nanoseconds: UInt64) async throws -> Void
    ) {
        self.checkAccess = checkAccess
        self.makeLiveAdapter = makeLiveAdapter
        self.makeDemoAdapter = makeDemoAdapter
        self.defaults = defaults
        self.secretStore = secretStore
        self.systemIsDark = systemIsDark
        self.openFullDiskAccessSettings = openFullDiskAccessSettings
        self.updateClassifierConfiguration = updateClassifierConfiguration
        self.testAIConnection = testAIConnection
        self.rebuildClassifierCache = rebuildClassifierCache
        self.classifierCacheSizeText = classifierCacheSizeText
        self.animate = animate
        self.sleep = sleep
    }

    public static var live: AppEnvironment {
        let defaults = UserDefaults.standard
        let secretStore = KeychainSecretStore()
        let signalCache = try? DecisionSignalCache()
        let initialConfig = SettingsFormState.loadPersistedClassifierConfiguration(
            defaults: defaults,
            secretStore: secretStore
        )
        let client = GeminiDecisionsClient()
        let sharedClassifier = HybridMailClassifier(
            configuration: initialConfig,
            client: client,
            signalCache: signalCache,
            secretStore: secretStore
        )

        return AppEnvironment(
            checkAccess: { MailStoreEnvironment.checkAccess() },
            makeLiveAdapter: {
                let syncLimit = SettingsFormState.loadPersistedSyncLimit(defaults: defaults)
                let aliases = SettingsFormState.loadPersistedCustomAliases(defaults: defaults)
                return try? AppleMailAdapter(
                    classifier: sharedClassifier,
                    maxInboxFetch: syncLimit,
                    ownerAddresses: Set(aliases)
                )
            },
            makeDemoAdapter: { MockMailAdapter() },
            defaults: defaults,
            secretStore: secretStore,
            systemIsDark: {
                NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            },
            openFullDiskAccessSettings: { MailStoreEnvironment.openFullDiskAccessSettings() },
            updateClassifierConfiguration: { config in
                sharedClassifier.updateConfiguration(config)
            },
            testAIConnection: { endpoint, model, apiKey in
                try await client.testConnection(endpoint: endpoint, model: model, apiKey: apiKey)
            },
            rebuildClassifierCache: {
                try sharedClassifier.clearCache()
            },
            classifierCacheSizeText: {
                let signalBytes = sharedClassifier.cacheByteSize()
                let parsedBytes = DecisionSignalCache.fileTreeByteSize(
                    forSQLitePath: AppleMailAdapter.defaultCacheDBPath()
                )
                return DecisionSignalCache.formatByteSize(signalBytes + parsedBytes)
            },
            animate: { duration, body in
                withAnimation(.snappy(duration: duration), body)
            },
            sleep: { nanoseconds in
                try await Task.sleep(nanoseconds: nanoseconds)
            }
        )
    }
}
