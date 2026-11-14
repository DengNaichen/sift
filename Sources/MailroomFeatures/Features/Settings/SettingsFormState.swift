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
}

public struct TriageCategoryShellRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public var choice: TriageDispositionChoice
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
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta"
        case .claude: return "https://api.anthropic.com/v1"
        case .openai: return "https://api.openai.com/v1"
        case .custom: return "https://your-gateway.example.com/v1"
        }
    }

    public var defaultModel: String {
        switch self {
        case .gemini: return "gemini-2.5-flash"
        case .claude: return "claude-haiku-4-5"
        case .openai: return "gpt-4o-mini"
        case .custom: return "deepseek-chat"
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

/// 设置页表单状态（暂不改动后端分类与存储逻辑，负责完整呈现交互形态）
@MainActor
@Observable
public final class SettingsFormState {
    public var activeSection: SettingsSection = .accounts

    // 1. 邮箱与连接
    public var syncLimit: Int = 100
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
            trashPath: "Deleted Messages"
        )
    ]
    public var customAliases: [String] = []
    public var aliasDraft: String = ""

    // 2. 分拣与护栏
    public var triageMatrix: [TriageCategoryShellRow] = [
        TriageCategoryShellRow(id: "otp", title: "验证码与登录安全码", choice: .archive),
        TriageCategoryShellRow(id: "shipping", title: "物流与派送通知", choice: .archive),
        TriageCategoryShellRow(id: "receipt", title: "常规收据与账单回执", choice: .archive),
        TriageCategoryShellRow(id: "social", title: "平台与社交通知", choice: .archive),
        TriageCategoryShellRow(id: "newsletter", title: "资讯订阅 Newsletter", choice: .trash),
        TriageCategoryShellRow(id: "promo", title: "营销与促销推广", choice: .trash)
    ]
    public var reviewIncompleteMails: Bool = true
    public var customProtectedEntries: [String] = []
    public var protectedDraft: String = ""

    // 3. AI 分类引擎
    public var engineMode: ClassifierEngineChoice = .hybrid
    public var provider: LLMProviderChoice = .gemini
    public var endpoint: String = LLMProviderChoice.gemini.defaultEndpoint
    public var apiKey: String = ""
    public var apiKeyRevealed: Bool = false
    public var modelName: String = LLMProviderChoice.gemini.defaultModel
    public var connectionTestStatus: String? = nil
    public var confidenceThreshold: Double = 90
    public var payloadScope: PayloadScopeChoice = .excerpt1500
    public var cacheDecisions: Bool = true

    // 4. 阅读与外观
    public var remoteImageChoice: RemoteImageChoice = .blockByDefault

    // 5. 诊断与缓存
    public var walStatusText: String = "WAL 正常"
    public var hitRateText: String = "99.4%"
    public var pendingLedgerText: String = "0"
    public var cacheSizeText: String = "14.2 MB"
    public var confirmingCacheRebuild: Bool = false
    public var transientBannerText: String? = nil

    private var seededFromLiveAccounts = false
    private var feedbackTask: Task<Void, Never>?

    public init() {}

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
        engineMode = mode
        if mode == .local {
            endpoint = "http://127.0.0.1:11434/v1"
            modelName = "qwen2.5:7b-instruct"
        } else if mode == .hybrid {
            endpoint = provider.defaultEndpoint
            modelName = provider.defaultModel
        }
    }

    public func selectProvider(_ newProvider: LLMProviderChoice) {
        provider = newProvider
        endpoint = newProvider.defaultEndpoint
        modelName = newProvider.defaultModel
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
        connectionTestStatus = "连接中…"
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 320_000_000)
            self?.connectionTestStatus = "✓ 240ms"
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self?.connectionTestStatus = nil
        }
    }

    public func confirmCacheRebuildPreview() {
        confirmingCacheRebuild = false
        cacheSizeText = "0.4 MB"
        showTransientFeedback("已触发重建预览（暂未接后端缓存清理）")
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
}
