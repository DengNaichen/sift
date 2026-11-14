import AppKit
import Foundation
import Observation
import SwiftUI
import MailroomCore

public enum SettingsSection: String, CaseIterable, Identifiable, Sendable {
    case accounts
    case triage
    case ai
    case appearance
    case diagnostics

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .accounts: return "邮箱与连接"
        case .triage: return "分拣与护栏"
        case .ai: return "AI 分类引擎"
        case .appearance: return "阅读与外观"
        case .diagnostics: return "快捷键与诊断"
        }
    }

    public var iconName: String {
        switch self {
        case .accounts: return "envelope"
        case .triage: return "shield"
        case .ai: return "sparkles"
        case .appearance: return "sun.max"
        case .diagnostics: return "command"
        }
    }

    public var groupTitle: String {
        switch self {
        case .accounts, .triage, .ai:
            return "连接与分拣"
        case .appearance, .diagnostics:
            return "工作台"
        }
    }

    public var searchKeywords: String {
        switch self {
        case .accounts:
            return "account mail permission fda alias 邮箱 账户 权限 磁盘 别名 连接"
        case .triage:
            return "triage rule guardrail whitelist promo newsletter 分拣 护栏 推广 归档 废纸篓 白名单"
        case .ai:
            return "ai llm model gemini claude openai ollama api key threshold 模型 引擎 密钥 阈值 确信度"
        case .appearance:
            return "theme dark light plain html image hud 外观 主题 深色 浅色 纯文本 富文本 图片"
        case .diagnostics:
            return "shortcut keybind doctor cache eval 快捷键 诊断 缓存 自检 评测"
        }
    }
}

public enum AccountColorTone: String, CaseIterable, Sendable {
    case cobalt
    case sage
    case amber
    case coral

    public func color(in palette: DeckPalette) -> Color {
        switch self {
        case .cobalt: return palette.cobalt
        case .sage: return palette.sage
        case .amber: return palette.amber
        case .coral: return palette.coral
        }
    }

    public var next: AccountColorTone {
        let all = Self.allCases
        let idx = all.firstIndex(of: self) ?? 0
        return all[(idx + 1) % all.count]
    }
}

public struct SettingsAccountShellItem: Identifiable, Equatable, Sendable {
    public let id: String
    public var enabled: Bool
    public var tone: AccountColorTone
    public var label: String
    public var address: String
    public var archivePath: String
    public var trashPath: String
}

public enum TriageDispositionChoice: String, CaseIterable, Identifiable, Sendable {
    case inbox
    case archive
    case trash

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .inbox: return "待处理"
        case .archive: return "归档"
        case .trash: return "废纸篓"
        }
    }

    public var siftAction: SiftAction {
        switch self {
        case .inbox: return .keep
        case .archive: return .archive
        case .trash: return .trash
        }
    }

    public init(siftAction: SiftAction) {
        switch siftAction {
        case .keep, .review:
            self = .inbox
        case .archive:
            self = .archive
        case .trash:
            self = .trash
        }
    }
}

public struct TriageCategoryShellRow: Identifiable, Equatable, Sendable {
    public let category: SiftCategory
    public var id: String { category.rawValue }
    public let title: String
    public let allowedChoices: [TriageDispositionChoice]
    private var _choice: TriageDispositionChoice

    public var choice: TriageDispositionChoice {
        get { _choice }
        set {
            if allowedChoices.contains(newValue) {
                _choice = newValue
            }
        }
    }

    public init(
        category: SiftCategory,
        title: String? = nil,
        choice: TriageDispositionChoice
    ) {
        self.category = category
        self.title = title ?? category.settingsTitle
        let allowed = category.allowedPreferenceActions.map(TriageDispositionChoice.init(siftAction:))
        self.allowedChoices = allowed
        if allowed.contains(choice) {
            self._choice = choice
        } else {
            let fallbackAction = SiftPreferences.balancedDefault.action(for: category)
            self._choice = TriageDispositionChoice(siftAction: fallbackAction)
        }
    }
}

public enum ClassifierEngineChoice: String, CaseIterable, Identifiable, Sendable {
    case rules
    case hybrid
    case local

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .rules: return "本地规则"
        case .hybrid: return "混合流水线"
        case .local: return "本地模型"
        }
    }

    public var subtitle: String {
        switch self {
        case .rules: return "词典与信头确定性判别"
        case .hybrid: return "规则初筛 + 模型语义判别"
        case .local: return "Ollama / LM Studio"
        }
    }

    public var badgeText: String? {
        switch self {
        case .rules: return "离线"
        case .hybrid: return "默认"
        case .local: return nil
        }
    }

    public var siftEngineMode: SiftEngineMode {
        switch self {
        case .rules: return .rules
        case .hybrid: return .hybrid
        case .local: return .local
        }
    }
}

public enum LLMProviderChoice: String, CaseIterable, Identifiable, Sendable {
    case gemini
    case claude
    case openai
    case custom

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .gemini: return "Gemini"
        case .claude: return "Claude"
        case .openai: return "OpenAI"
        case .custom: return "自定义"
        }
    }

    public var defaultEndpoint: String {
        switch self {
        case .gemini: return GeminiDecisionsClient.defaultBaseEndpoint
        case .claude: return "https://api.anthropic.com/v1"
        case .openai: return "https://api.openai.com/v1"
        case .custom: return "https://your-gateway.example.com/v1"
        }
    }

    public var defaultModel: String {
        switch self {
        case .gemini: return GeminiDecisionsClient.defaultModel
        case .claude: return "claude-haiku-4-5"
        case .openai: return "gpt-4o-mini"
        case .custom: return "deepseek-chat"
        }
    }

    public var siftProviderKind: SiftProviderKind {
        switch self {
        case .gemini: return .gemini
        case .claude: return .claude
        case .openai: return .openai
        case .custom: return .custom
        }
    }
}

public enum PayloadScopeChoice: String, CaseIterable, Identifiable, Sendable {
    case excerpt1500
    case headerOnly

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .excerpt1500: return "前 1,500 字纯文本"
        case .headerOnly: return "仅主题与发件人"
        }
    }

    public var siftPayloadScope: SiftPayloadScope {
        switch self {
        case .excerpt1500: return .excerpt1500
        case .headerOnly: return .headerOnly
        }
    }
}

public enum RemoteImageChoice: String, CaseIterable, Identifiable, Sendable {
    case blockByDefault
    case alwaysLoad

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .blockByDefault: return "默认拦截"
        case .alwaysLoad: return "始终加载"
        }
    }
}

/// 设置页状态与实时持久化：
/// - 普通设置项持久化在注入的 `UserDefaults` 中
/// - `apiKey` 仅读写 `SecretStore`（生产环境为 macOS Keychain），严禁写入 `UserDefaults`
/// - 分拣偏好或 AI 引擎配置变更时实时通知共享分类器更新并在真机数据源下重同步
@MainActor
@Observable
public final class SettingsFormState {
    public enum StorageKey {
        public static let syncLimit = "sift.settings.syncLimit"
        public static let customAliases = "sift.settings.customAliases"
        public static let triagePreferences = "sift.settings.triagePreferences"
        public static let engineMode = "sift.settings.engineMode"
        public static let provider = "sift.settings.provider"
        public static let endpoint = "sift.settings.endpoint"
        public static let modelName = "sift.settings.modelName"
        public static let confidenceThreshold = "sift.settings.confidenceThreshold"
        public static let payloadScope = "sift.settings.payloadScope"
        public static let cacheDecisions = "sift.settings.cacheDecisions"
        public static let remoteImageChoice = "sift.settings.remoteImageChoice"
    }

    public var activeSection: SettingsSection = .accounts

    // MARK: - 1. 邮箱与连接

    public var syncLimit: Int {
        didSet {
            guard !isSuppressingCallbacks, syncLimit != oldValue else { return }
            defaults?.set(syncLimit, forKey: StorageKey.syncLimit)
            onLiveBridgeSettingsChanged?()
        }
    }
    public var automationVerifyStatus: String? = nil
    public var accountItems: [SettingsAccountShellItem] = [
        SettingsAccountShellItem(
            id: "work",
            enabled: true,
            tone: .cobalt,
            label: "工作",
            address: "work@company.com",
            archivePath: "[Gmail]/All Mail",
            trashPath: "[Gmail]/Trash"
        ),
        SettingsAccountShellItem(
            id: "personal",
            enabled: true,
            tone: .sage,
            label: "个人",
            address: "me@icloud.com",
            archivePath: "Archive",
            trashPath: "Trash"
        )
    ]
    public var customAliases: [String] {
        didSet {
            guard !isSuppressingCallbacks, customAliases != oldValue else { return }
            defaults?.set(customAliases, forKey: StorageKey.customAliases)
            onLiveBridgeSettingsChanged?()
        }
    }
    public var aliasDraft: String = ""

    // MARK: - 2. 分拣与护栏（Superhuman 7 类模型：respond 锁定收件箱 + 6 类可调矩阵）

    public var triageMatrix: [TriageCategoryShellRow] {
        didSet {
            guard !isSuppressingCallbacks else { return }
            let sanitizedRows = Self.makeMatrixRows(from: Self.preferencesFromMatrix(
                rows: triageMatrix,
                reviewIncompleteMails: reviewIncompleteMails,
                vipSenders: customProtectedEntries,
                blockedSenders: customBlockedEntries
            ))
            if sanitizedRows != triageMatrix {
                withCallbacksSuppressed {
                    triageMatrix = sanitizedRows
                }
            }
            if triageMatrix != oldValue {
                persistTriagePreferences()
                notifyClassifierConfigurationChanged()
            }
        }
    }
    public var reviewIncompleteMails: Bool {
        didSet {
            guard !isSuppressingCallbacks, reviewIncompleteMails != oldValue else { return }
            persistTriagePreferences()
            notifyClassifierConfigurationChanged()
        }
    }
    public var customProtectedEntries: [String] {
        didSet {
            guard !isSuppressingCallbacks, customProtectedEntries != oldValue else { return }
            persistTriagePreferences()
            notifyClassifierConfigurationChanged()
        }
    }
    public var protectedDraft: String = ""

    public var customBlockedEntries: [String] {
        didSet {
            guard !isSuppressingCallbacks, customBlockedEntries != oldValue else { return }
            persistTriagePreferences()
            notifyClassifierConfigurationChanged()
        }
    }
    public var blockedDraft: String = ""

    public var vipSenders: [String] {
        get { customProtectedEntries }
        set { customProtectedEntries = newValue }
    }

    public var blockedSenders: [String] {
        get { customBlockedEntries }
        set { customBlockedEntries = newValue }
    }

    // MARK: - 3. AI 分类引擎

    public var engineMode: ClassifierEngineChoice {
        didSet {
            guard !isSuppressingCallbacks, engineMode != oldValue else { return }
            defaults?.set(engineMode.rawValue, forKey: StorageKey.engineMode)
            resetConnectionFeedback()
            notifyClassifierConfigurationChanged()
        }
    }
    public var provider: LLMProviderChoice {
        didSet {
            guard !isSuppressingCallbacks, provider != oldValue else { return }
            defaults?.set(provider.rawValue, forKey: StorageKey.provider)
            resetConnectionFeedback()
            notifyClassifierConfigurationChanged()
        }
    }
    public var endpoint: String {
        didSet {
            guard !isSuppressingCallbacks, endpoint != oldValue else { return }
            defaults?.set(endpoint, forKey: StorageKey.endpoint)
            resetConnectionFeedback()
            notifyClassifierConfigurationChanged()
        }
    }
    public var apiKey: String {
        didSet {
            guard !isSuppressingCallbacks, apiKey != oldValue else { return }
            persistAPIKeyToSecretStore(apiKey, for: provider)
            resetConnectionFeedback()
            notifyClassifierConfigurationChanged()
        }
    }
    public var apiKeyRevealed: Bool = false
    public var modelName: String {
        didSet {
            guard !isSuppressingCallbacks, modelName != oldValue else { return }
            defaults?.set(modelName, forKey: StorageKey.modelName)
            resetConnectionFeedback()
            notifyClassifierConfigurationChanged()
        }
    }
    public var connectionTestStatus: String? = nil
    public var connectionTestError: String? = nil
    public var confidenceThreshold: Double {
        didSet {
            guard !isSuppressingCallbacks else { return }
            let clamped = Self.clampConfidenceThreshold(confidenceThreshold)
            if clamped != confidenceThreshold {
                withCallbacksSuppressed {
                    confidenceThreshold = clamped
                }
            }
            guard confidenceThreshold != oldValue else { return }
            defaults?.set(confidenceThreshold, forKey: StorageKey.confidenceThreshold)
            notifyClassifierConfigurationChanged()
        }
    }
    public var payloadScope: PayloadScopeChoice {
        didSet {
            guard !isSuppressingCallbacks, payloadScope != oldValue else { return }
            defaults?.set(payloadScope.rawValue, forKey: StorageKey.payloadScope)
            notifyClassifierConfigurationChanged()
        }
    }
    public var cacheDecisions: Bool {
        didSet {
            guard !isSuppressingCallbacks, cacheDecisions != oldValue else { return }
            defaults?.set(cacheDecisions, forKey: StorageKey.cacheDecisions)
            notifyClassifierConfigurationChanged()
        }
    }

    // MARK: - 4. 阅读与外观

    public var remoteImageChoice: RemoteImageChoice {
        didSet {
            guard !isSuppressingCallbacks, remoteImageChoice != oldValue else { return }
            defaults?.set(remoteImageChoice.rawValue, forKey: StorageKey.remoteImageChoice)
        }
    }

    // MARK: - 5. 诊断与缓存

    public var walStatusText: String = "WAL 正常"
    public var hitRateText: String = "99.4%"
    public var pendingLedgerText: String = "0"
    public var cacheSizeText: String
    public var confirmingCacheRebuild: Bool = false
    public var transientBannerText: String? = nil

    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let secretStore: (any SecretStore)?
    @ObservationIgnored private let testAIConnectionAction: (@Sendable (_ endpoint: String, _ model: String, _ apiKey: String) async throws -> Double)?
    @ObservationIgnored var onClassifierConfigurationChanged: ((SiftClassifierConfiguration) -> Void)?
    @ObservationIgnored var onLiveBridgeSettingsChanged: (() -> Void)?
    @ObservationIgnored var onRebuildCaches: (() async throws -> String)?
    @ObservationIgnored var onQueryCacheSizeText: (() -> String)?

    @ObservationIgnored private var isSuppressingCallbacks = false
    @ObservationIgnored private var seededFromLiveAccounts = false
    @ObservationIgnored private var feedbackTask: Task<Void, Never>?
    @ObservationIgnored private var connectionTestTask: Task<Void, Never>?

    public init(
        defaults: UserDefaults? = nil,
        secretStore: (any SecretStore)? = nil,
        initialCacheSizeText: String = "14.2 MB",
        testAIConnection: (@Sendable (_ endpoint: String, _ model: String, _ apiKey: String) async throws -> Double)? = nil
    ) {
        self.defaults = defaults
        self.secretStore = secretStore
        self.testAIConnectionAction = testAIConnection
        self.isSuppressingCallbacks = true

        // 修正默认个人账户 trashPath 保持与金样兼容（注意 dump 只输出 archivePath）
        self.accountItems = [
            SettingsAccountShellItem(
                id: "work",
                enabled: true,
                tone: .cobalt,
                label: "工作",
                address: "work@company.com",
                archivePath: "[Gmail]/All Mail",
                trashPath: "[Gmail]/Trash"
            ),
            SettingsAccountShellItem(
                id: "personal",
                enabled: true,
                tone: .sage,
                label: "个人",
                address: "me@icloud.com",
                archivePath: "Archive",
                trashPath: "Deleted Messages"
            )
        ]

        let loadedSyncLimit = defaults.map(Self.loadPersistedSyncLimit(defaults:)) ?? 100
        let loadedAliases = defaults.map(Self.loadPersistedCustomAliases(defaults:)) ?? []
        let loadedPrefs = defaults.map(Self.loadPersistedTriagePreferences(defaults:)) ?? .balancedDefault
        let loadedEngine = Self.loadPersistedEngineMode(defaults: defaults)
        let loadedProvider = Self.loadPersistedProvider(defaults: defaults)
        let loadedEndpoint = Self.loadPersistedEndpoint(defaults: defaults, engineMode: loadedEngine, provider: loadedProvider)
        let loadedModel = Self.loadPersistedModelName(defaults: defaults, engineMode: loadedEngine, provider: loadedProvider)
        let loadedThreshold = Self.loadPersistedConfidenceThreshold(defaults: defaults)
        let loadedPayloadScope = Self.loadPersistedPayloadScope(defaults: defaults)
        let loadedCacheDecisions = Self.loadPersistedCacheDecisions(defaults: defaults)
        let loadedRemoteImage = Self.loadPersistedRemoteImageChoice(defaults: defaults)
        let loadedAPIKey = Self.readAPIKey(from: secretStore, for: loadedProvider)

        self.syncLimit = loadedSyncLimit
        self.customAliases = loadedAliases
        self.triageMatrix = Self.makeMatrixRows(from: loadedPrefs)
        self.reviewIncompleteMails = loadedPrefs.reviewIncompleteMails
        self.customProtectedEntries = loadedPrefs.vipSenders
        self.customBlockedEntries = loadedPrefs.blockedSenders
        self.engineMode = loadedEngine
        self.provider = loadedProvider
        self.endpoint = loadedEndpoint
        self.apiKey = loadedAPIKey
        self.modelName = loadedModel
        self.confidenceThreshold = loadedThreshold
        self.payloadScope = loadedPayloadScope
        self.cacheDecisions = loadedCacheDecisions
        self.remoteImageChoice = loadedRemoteImage
        self.cacheSizeText = initialCacheSizeText

        self.isSuppressingCallbacks = false
    }

    // MARK: - Derived Sift Configuration & Presets

    public var siftPreferences: SiftPreferences {
        Self.preferencesFromMatrix(
            rows: triageMatrix,
            reviewIncompleteMails: reviewIncompleteMails,
            vipSenders: customProtectedEntries,
            blockedSenders: customBlockedEntries
        )
    }

    public var activePreset: SiftPreset? {
        siftPreferences.matchingPreset
    }

    public var classifierConfiguration: SiftClassifierConfiguration {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return SiftClassifierConfiguration(
            engineMode: engineMode.siftEngineMode,
            provider: provider.siftProviderKind,
            endpoint: endpoint,
            model: modelName,
            confidenceGate: confidenceThreshold / 100.0,
            payloadScope: payloadScope.siftPayloadScope,
            cacheDecisions: cacheDecisions,
            preferences: siftPreferences,
            apiKeyOverride: trimmedKey.isEmpty ? nil : trimmedKey
        )
    }

    public func disposition(for category: SiftCategory) -> TriageDispositionChoice {
        if let row = triageMatrix.first(where: { $0.category == category }) {
            return row.choice
        }
        return TriageDispositionChoice(siftAction: siftPreferences.action(for: category))
    }

    @discardableResult
    public func setDisposition(_ choice: TriageDispositionChoice, for category: SiftCategory) -> Bool {
        guard category.allowedPreferenceActions.contains(choice.siftAction),
              let idx = triageMatrix.firstIndex(where: { $0.category == category }) else {
            return false
        }
        guard triageMatrix[idx].choice != choice else { return true }
        withCallbacksSuppressed {
            triageMatrix[idx].choice = choice
        }
        persistTriagePreferences()
        notifyClassifierConfigurationChanged()
        return true
    }

    public func applyPreset(_ preset: SiftPreset) {
        let updated = siftPreferences.applyingPreset(preset)
        let newRows = Self.makeMatrixRows(from: updated)
        guard newRows != triageMatrix else { return }
        withCallbacksSuppressed {
            triageMatrix = newRows
        }
        persistTriagePreferences()
        notifyClassifierConfigurationChanged()
    }

    // MARK: - Accounts & Chips

    public func syncAccountsIfNeeded(from accounts: [MailAccount]) {
        guard !accounts.isEmpty else { return }
        let existingById = Dictionary(uniqueKeysWithValues: accountItems.map { ($0.id, $0) })
        let tones = AccountColorTone.allCases
        self.accountItems = accounts.enumerated().map { index, acc in
            if let prev = existingById[acc.id] {
                return SettingsAccountShellItem(
                    id: acc.id,
                    enabled: prev.enabled,
                    tone: prev.tone,
                    label: seededFromLiveAccounts ? prev.label : acc.label,
                    address: acc.address,
                    archivePath: prev.archivePath,
                    trashPath: prev.trashPath
                )
            }
            let inferredGmail = acc.address.lowercased().hasSuffix("@gmail.com")
            let defaultTone: AccountColorTone = acc.id == "work" ? .cobalt : (acc.id == "personal" ? .sage : tones[index % tones.count])
            return SettingsAccountShellItem(
                id: acc.id,
                enabled: true,
                tone: defaultTone,
                label: acc.label,
                address: acc.address,
                archivePath: inferredGmail ? "[Gmail]/All Mail" : "Archive",
                trashPath: inferredGmail ? "[Gmail]/Trash" : "Trash"
            )
        }
        seededFromLiveAccounts = true
    }

    public func selectEngine(_ mode: ClassifierEngineChoice) {
        guard mode != engineMode
            || (mode == .local && endpoint != "http://127.0.0.1:11434/v1")
            || (mode == .hybrid && endpoint == "http://127.0.0.1:11434/v1") else {
            return
        }
        withCallbacksSuppressed {
            engineMode = mode
            if mode == .local {
                endpoint = "http://127.0.0.1:11434/v1"
                modelName = "qwen2.5:7b-instruct"
            } else if mode == .hybrid {
                endpoint = provider.defaultEndpoint
                modelName = provider.defaultModel
            }
        }
        defaults?.set(engineMode.rawValue, forKey: StorageKey.engineMode)
        defaults?.set(endpoint, forKey: StorageKey.endpoint)
        defaults?.set(modelName, forKey: StorageKey.modelName)
        resetConnectionFeedback()
        notifyClassifierConfigurationChanged()
    }

    public func selectProvider(_ newProvider: LLMProviderChoice) {
        let providerChanged = (newProvider != provider)
        withCallbacksSuppressed {
            provider = newProvider
            endpoint = newProvider.defaultEndpoint
            modelName = newProvider.defaultModel
            if providerChanged, let secretStore {
                let providerKey = SiftSecretKey.apiKey(for: newProvider.rawValue)
                let savedForProvider = (try? secretStore.readSecret(key: providerKey)) ?? ""
                apiKey = savedForProvider
            }
        }
        defaults?.set(provider.rawValue, forKey: StorageKey.provider)
        defaults?.set(endpoint, forKey: StorageKey.endpoint)
        defaults?.set(modelName, forKey: StorageKey.modelName)
        if providerChanged {
            try? secretStore?.writeSecret(key: SiftSecretKey.classifierAPIKey, value: apiKey)
        }
        resetConnectionFeedback()
        notifyClassifierConfigurationChanged()
    }

    public func submitAliasDraft() {
        let trimmed = aliasDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !customAliases.contains(trimmed) {
            customAliases.append(trimmed)
        }
        aliasDraft = ""
    }

    public func removeAlias(at index: Int) {
        guard customAliases.indices.contains(index) else { return }
        customAliases.remove(at: index)
    }

    public func submitProtectedDraft() {
        let trimmed = protectedDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !customProtectedEntries.contains(trimmed) {
            customProtectedEntries.append(trimmed)
        }
        protectedDraft = ""
    }

    public func removeProtectedEntry(at index: Int) {
        guard customProtectedEntries.indices.contains(index) else { return }
        customProtectedEntries.remove(at: index)
    }

    public func submitBlockedDraft() {
        let trimmed = blockedDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !customBlockedEntries.contains(trimmed) {
            customBlockedEntries.append(trimmed)
        }
        blockedDraft = ""
    }

    public func removeBlockedEntry(at index: Int) {
        guard customBlockedEntries.indices.contains(index) else { return }
        customBlockedEntries.remove(at: index)
    }

    // MARK: - Connection Test & Diagnostics

    public func triggerAutomationPreview() {
        automationVerifyStatus = "验证中…"
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 280_000_000)
            self?.automationVerifyStatus = "✓ 已就绪"
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            self?.automationVerifyStatus = nil
        }
    }

    public func triggerConnectionPreview() {
        connectionTestTask?.cancel()
        connectionTestTask = Task { @MainActor [weak self] in
            await self?.testConnection()
        }
    }

    public func testConnection() async {
        connectionTestStatus = "连接中…"
        connectionTestError = nil

        let currentEndpoint = endpoint
        let currentModel = modelName
        let currentKey = apiKey

        guard let testAction = testAIConnectionAction else {
            connectionTestStatus = "✓ 240ms"
            return
        }

        do {
            let latencyMs = try await testAction(currentEndpoint, currentModel, currentKey)
            guard !Task.isCancelled else { return }
            let roundedMs = max(1, Int(latencyMs.rounded()))
            connectionTestStatus = "✓ \(roundedMs)ms"
            connectionTestError = nil
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            let safeError = GeminiDecisionsClient.redact(error.localizedDescription, apiKey: currentKey)
            connectionTestStatus = "✕ 失败"
            connectionTestError = safeError
        }
    }

    public func refreshDiagnostics(silent: Bool = false) {
        if let query = onQueryCacheSizeText {
            cacheSizeText = query()
        }
        if !silent {
            showTransientFeedback("已完成本地索引与缓存自检")
        }
    }

    public func confirmCacheRebuild() {
        Task { @MainActor [weak self] in
            await self?.rebuildCache()
        }
    }

    public func confirmCacheRebuildPreview() {
        confirmCacheRebuild()
    }

    public func rebuildCache() async {
        confirmingCacheRebuild = false
        if let onRebuildCaches {
            do {
                let updatedSize = try await onRebuildCaches()
                cacheSizeText = updatedSize
                showTransientFeedback("已清空并重建本地解析与分类缓存")
            } catch {
                showTransientFeedback("重建缓存失败：\(error.localizedDescription)")
            }
        } else {
            cacheSizeText = "0 KB"
            showTransientFeedback("已清空本地缓存")
        }
    }

    public func showTransientFeedback(_ message: String) {
        feedbackTask?.cancel()
        withAnimation(.snappy(duration: 0.16)) {
            transientBannerText = message
        }
        feedbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.snappy(duration: 0.16)) {
                self?.transientBannerText = nil
            }
        }
    }

    // MARK: - Static Persistence Loaders

    public static func loadPersistedSyncLimit(defaults: UserDefaults) -> Int {
        guard defaults.object(forKey: StorageKey.syncLimit) != nil else { return 100 }
        let saved = defaults.integer(forKey: StorageKey.syncLimit)
        return [50, 100, 200, 500].contains(saved) ? saved : 100
    }

    public static func loadPersistedCustomAliases(defaults: UserDefaults) -> [String] {
        (defaults.stringArray(forKey: StorageKey.customAliases) ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    public static func loadPersistedTriagePreferences(defaults: UserDefaults) -> SiftPreferences {
        guard let data = defaults.data(forKey: StorageKey.triagePreferences),
              let decoded = try? JSONDecoder().decode(SiftPreferences.self, from: data) else {
            return .balancedDefault
        }
        return decoded.sanitized()
    }

    public static func loadPersistedClassifierConfiguration(
        defaults: UserDefaults,
        secretStore: any SecretStore
    ) -> SiftClassifierConfiguration {
        let engine = loadPersistedEngineMode(defaults: defaults)
        let provider = loadPersistedProvider(defaults: defaults)
        let endpoint = loadPersistedEndpoint(defaults: defaults, engineMode: engine, provider: provider)
        let model = loadPersistedModelName(defaults: defaults, engineMode: engine, provider: provider)
        let threshold = loadPersistedConfidenceThreshold(defaults: defaults)
        let payloadScope = loadPersistedPayloadScope(defaults: defaults)
        let cacheDecisions = loadPersistedCacheDecisions(defaults: defaults)
        let preferences = loadPersistedTriagePreferences(defaults: defaults)
        let apiKey = readAPIKey(from: secretStore, for: provider)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        return SiftClassifierConfiguration(
            engineMode: engine.siftEngineMode,
            provider: provider.siftProviderKind,
            endpoint: endpoint,
            model: model,
            confidenceGate: threshold / 100.0,
            payloadScope: payloadScope.siftPayloadScope,
            cacheDecisions: cacheDecisions,
            preferences: preferences,
            apiKeyOverride: trimmedKey.isEmpty ? nil : trimmedKey
        )
    }

    // MARK: - Private Helpers

    private static func makeMatrixRows(from preferences: SiftPreferences) -> [TriageCategoryShellRow] {
        let sanitized = preferences.sanitized()
        return SiftCategory.configurableCategories.map { category in
            TriageCategoryShellRow(
                category: category,
                title: category.settingsTitle,
                choice: TriageDispositionChoice(siftAction: sanitized.action(for: category))
            )
        }
    }

    private static func preferencesFromMatrix(
        rows: [TriageCategoryShellRow],
        reviewIncompleteMails: Bool,
        vipSenders: [String],
        blockedSenders: [String]
    ) -> SiftPreferences {
        var prefs = SiftPreferences(
            vipSenders: vipSenders,
            blockedSenders: blockedSenders,
            reviewIncompleteMails: reviewIncompleteMails
        )
        for row in rows {
            _ = prefs.setAction(row.choice.siftAction, for: row.category)
        }
        return prefs.sanitized()
    }

    private static func clampConfidenceThreshold(_ value: Double) -> Double {
        guard value.isFinite else { return 90 }
        return min(98, max(80, value.rounded()))
    }

    private static func loadPersistedEngineMode(defaults: UserDefaults?) -> ClassifierEngineChoice {
        guard let raw = defaults?.string(forKey: StorageKey.engineMode),
              let mode = ClassifierEngineChoice(rawValue: raw) else {
            return .hybrid
        }
        return mode
    }

    private static func loadPersistedProvider(defaults: UserDefaults?) -> LLMProviderChoice {
        guard let raw = defaults?.string(forKey: StorageKey.provider),
              let provider = LLMProviderChoice(rawValue: raw) else {
            return .gemini
        }
        return provider
    }

    private static func loadPersistedEndpoint(
        defaults: UserDefaults?,
        engineMode: ClassifierEngineChoice,
        provider: LLMProviderChoice
    ) -> String {
        if let saved = defaults?.string(forKey: StorageKey.endpoint),
           !saved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return saved
        }
        return engineMode == .local ? "http://127.0.0.1:11434/v1" : provider.defaultEndpoint
    }

    private static func loadPersistedModelName(
        defaults: UserDefaults?,
        engineMode: ClassifierEngineChoice,
        provider: LLMProviderChoice
    ) -> String {
        if let saved = defaults?.string(forKey: StorageKey.modelName),
           !saved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return saved
        }
        return engineMode == .local ? "qwen2.5:7b-instruct" : provider.defaultModel
    }

    private static func loadPersistedConfidenceThreshold(defaults: UserDefaults?) -> Double {
        guard let defaults, defaults.object(forKey: StorageKey.confidenceThreshold) != nil else {
            return 90
        }
        return clampConfidenceThreshold(defaults.double(forKey: StorageKey.confidenceThreshold))
    }

    private static func loadPersistedPayloadScope(defaults: UserDefaults?) -> PayloadScopeChoice {
        guard let raw = defaults?.string(forKey: StorageKey.payloadScope),
              let scope = PayloadScopeChoice(rawValue: raw) else {
            return .excerpt1500
        }
        return scope
    }

    private static func loadPersistedCacheDecisions(defaults: UserDefaults?) -> Bool {
        guard let defaults, defaults.object(forKey: StorageKey.cacheDecisions) != nil else {
            return true
        }
        return defaults.bool(forKey: StorageKey.cacheDecisions)
    }

    private static func loadPersistedRemoteImageChoice(defaults: UserDefaults?) -> RemoteImageChoice {
        guard let raw = defaults?.string(forKey: StorageKey.remoteImageChoice),
              let choice = RemoteImageChoice(rawValue: raw) else {
            return .blockByDefault
        }
        return choice
    }

    private static func readAPIKey(from secretStore: (any SecretStore)?, for provider: LLMProviderChoice) -> String {
        guard let secretStore else { return "" }
        let providerKey = SiftSecretKey.apiKey(for: provider.rawValue)
        if let specific = try? secretStore.readSecret(key: providerKey),
           !specific.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return specific
        }
        if let shared = try? secretStore.readSecret(key: SiftSecretKey.classifierAPIKey),
           !shared.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return shared
        }
        return ""
    }

    private func persistTriagePreferences() {
        guard let defaults,
              let encoded = try? JSONEncoder().encode(siftPreferences) else {
            return
        }
        defaults.set(encoded, forKey: StorageKey.triagePreferences)
    }

    private func persistAPIKeyToSecretStore(_ value: String, for provider: LLMProviderChoice) {
        guard let secretStore else { return }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        try? secretStore.writeSecret(key: SiftSecretKey.apiKey(for: provider.rawValue), value: trimmed)
        try? secretStore.writeSecret(key: SiftSecretKey.classifierAPIKey, value: trimmed)
    }

    private func resetConnectionFeedback() {
        connectionTestStatus = nil
        connectionTestError = nil
    }

    private func notifyClassifierConfigurationChanged() {
        onClassifierConfigurationChanged?(classifierConfiguration)
    }

    private func withCallbacksSuppressed(_ body: () -> Void) {
        let wasSuppressing = isSuppressingCallbacks
        isSuppressingCallbacks = true
        defer { isSuppressingCallbacks = wasSuppressing }
        body()
    }
}
