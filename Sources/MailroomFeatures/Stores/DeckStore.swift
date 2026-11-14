import Foundation
import Observation
import MailroomCore

public enum DataSourceMode: String, Sendable {
    case appleMail
    case demo
}

/// 邮件数据与副作用的唯一持有者：
/// - 状态迁移全部委托给纯函数 `DeckReducer`
/// - 负责数据源选择 / 切换、外部变化监听、乐观更新后的 adapter 写回、正文补全与 toast / notice 计时
/// 不依赖任何视图框架；动画通过注入的 `animate` 钩子施加。
@MainActor
@Observable
public final class DeckStore {
    public private(set) var state = DeckState()
    public private(set) var accessStatus: MailAccessStatus
    public private(set) var sourceMode: DataSourceMode
    /// 本次会话中用户放行了远程图片的邮件
    public private(set) var allowedRemoteImageIds: Set<MessageId> = []
    public private(set) var hydratingIds: Set<MessageId> = []
    public private(set) var nativeNoticeURL: String? = nil
    public private(set) var errorMessage: String? = nil
    public private(set) var isSyncing: Bool = false

    private var adapter: any MailAdapter

    @ObservationIgnored private let environment: AppEnvironment
    @ObservationIgnored private var latestClassifierConfiguration: SiftClassifierConfiguration
    @ObservationIgnored private var watchTask: Task<Void, Never>?
    @ObservationIgnored private var resyncTask: Task<Void, Never>?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var rescuingIds: Set<MessageId> = []
    @ObservationIgnored private var attemptedHydrationIds: Set<MessageId> = []

    public init(
        environment: AppEnvironment,
        initialClassifierConfiguration: SiftClassifierConfiguration = SiftClassifierConfiguration()
    ) {
        self.environment = environment
        self.latestClassifierConfiguration = initialClassifierConfiguration
        environment.updateClassifierConfiguration(initialClassifierConfiguration)
        let status = environment.checkAccess()
        self.accessStatus = status
        if case .ready = status, let live = environment.makeLiveAdapter() {
            self.adapter = live
            self.sourceMode = .appleMail
        } else {
            self.adapter = environment.makeDemoAdapter()
            self.sourceMode = .demo
        }
        startWatchingAndLoad()
    }

    // MARK: - Derived

    public var visibleRows: [FolderRow] { state.visibleRows }
    public var counts: [FolderId: Int] { state.folderCounts }
    public var accounts: [MailAccount] { state.accounts }
    public var canUndo: Bool { !state.undo.isEmpty }

    public var activeIndex: Int? {
        guard let focusId = state.focusId else { return nil }
        return visibleRows.firstIndex(where: { $0.id == focusId })
    }

    public var activeRow: FolderRow? {
        guard let idx = activeIndex else { return nil }
        return visibleRows[idx]
    }

    public var activeAccount: MailAccount? {
        guard case .account(let id) = state.accountScope else { return nil }
        return accounts.first { $0.id == id }
    }

    public var supportsDemoControls: Bool {
        adapter.supportsDemoControls
    }

    // MARK: - Data Loading & Switching

    public func startWatchingAndLoad() {
        watchTask?.cancel()
        let currentAdapter = self.adapter
        Task {
            await reloadSnapshot(initial: true)
        }
        watchTask = Task { [weak self] in
            for await _ in currentAdapter.externalChanges() {
                guard !Task.isCancelled, let self else { break }
                await self.reloadSnapshot(initial: false)
            }
        }
    }

    public func reloadSnapshot(initial: Bool = false) async {
        isSyncing = true
        defer { isSyncing = false }
        do {
            if let appleAdapter = adapter as? AppleMailAdapter {
                await appleAdapter.updateClassifierConfiguration(latestClassifierConfiguration)
            }
            let snapshot = try await adapter.fetchDeck()
            guard !Task.isCancelled else { return }
            if initial {
                apply(.loaded(snapshot))
            } else {
                apply(.externalSynced(snapshot))
            }
        } catch is CancellationError {
            return
        } catch {
            if !Task.isCancelled {
                errorMessage = error.localizedDescription
            }
        }
    }

    public func updateClassifierConfiguration(_ configuration: SiftClassifierConfiguration) {
        latestClassifierConfiguration = configuration
        environment.updateClassifierConfiguration(configuration)

        resyncTask?.cancel()
        guard sourceMode == .appleMail else { return }

        resyncTask = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            if let appleAdapter = self.adapter as? AppleMailAdapter {
                await appleAdapter.updateClassifierConfiguration(configuration)
            }
            guard !Task.isCancelled else { return }
            await self.reloadSnapshot(initial: false)
        }
    }

    public func refreshLiveAdapterForBridgeSettingsChange() {
        guard sourceMode == .appleMail else { return }
        environment.updateClassifierConfiguration(latestClassifierConfiguration)
        if let live = environment.makeLiveAdapter() {
            resyncTask?.cancel()
            self.adapter = live
            self.attemptedHydrationIds.removeAll()
            self.hydratingIds.removeAll()
            startWatchingAndLoad()
        }
    }

    public func rebuildCaches() async throws -> String {
        try await environment.rebuildClassifierCache()
        if let appleAdapter = adapter as? AppleMailAdapter {
            try await appleAdapter.clearCaches(includeParsedMailCache: true)
        }
        if sourceMode == .appleMail {
            await reloadSnapshot(initial: false)
        }
        return environment.classifierCacheSizeText()
    }

    public func recheckAccessAndSwitchToAppleMail() {
        environment.updateClassifierConfiguration(latestClassifierConfiguration)
        let status = environment.checkAccess()
        self.accessStatus = status
        switch status {
        case .ready:
            if let live = environment.makeLiveAdapter() {
                self.adapter = live
                self.sourceMode = .appleMail
                self.errorMessage = nil
                self.attemptedHydrationIds.removeAll()
                self.hydratingIds.removeAll()
                startWatchingAndLoad()
            }
        case .fullDiskAccessRequired:
            self.errorMessage = "尚未获得「完全磁盘访问权限」，请在系统设置中勾选本应用后再试。"
        case .mailStoreNotFound:
            self.errorMessage = "未检测到本机 Apple Mail 本地邮箱目录（请先登录一次系统邮件应用）。"
        }
    }

    public func switchToDemoMode() {
        self.adapter = environment.makeDemoAdapter()
        self.sourceMode = .demo
        self.errorMessage = nil
        self.attemptedHydrationIds.removeAll()
        self.hydratingIds.removeAll()
        startWatchingAndLoad()
    }

    public func dismissError() {
        errorMessage = nil
    }

    // MARK: - Reducer dispatch

    public func apply(_ event: DeckEvent) {
        let prevToastSeq = state.toast?.seq
        environment.animate(0.2) {
            state = DeckReducer.reduce(state, event)
        }
        if let toast = state.toast, toast.seq != prevToastSeq {
            scheduleToastExpiry(toast)
        }
    }

    private func scheduleToastExpiry(_ toast: DeckToast) {
        toastTask?.cancel()
        let delayNs: UInt64 = (toast.kind == .done) ? 5_000_000_000 : 1_600_000_000
        let seq = toast.seq
        let sleep = environment.sleep
        toastTask = Task { [weak self] in
            try? await sleep(delayNs)
            guard !Task.isCancelled else { return }
            self?.apply(.toastExpired(seq))
        }
    }

    public func setFolder(_ folder: FolderId) {
        apply(.folder(folder))
    }

    public func setAccountScope(_ scope: AccountScope) {
        apply(.accountScope(scope))
    }

    public func selectRow(_ id: MessageId) {
        apply(.focus(id))
    }

    public func moveFocus(delta: Int) {
        apply(.moveFocus(delta))
    }

    // MARK: - Reading

    public func allowRemoteImages(for id: MessageId) {
        environment.animate(0.16) {
            _ = allowedRemoteImageIds.insert(id)
        }
    }

    public func hydrateIfNeeded(for content: MailContent?) {
        guard let content, (content.isPartial || content.isTruncated) else { return }
        let id = content.id
        guard !attemptedHydrationIds.contains(id) else { return }
        attemptedHydrationIds.insert(id)
        hydratingIds.insert(id)

        let currentAdapter = self.adapter
        Task {
            defer {
                self.hydratingIds.remove(id)
            }
            if let hydrated = try? await currentAdapter.hydrateMessage(id: id) {
                self.apply(.hydrated(hydrated))
            }
        }
    }

    // MARK: - Triage side effects (optimistic reducer update, then adapter write-back)

    public func act(_ action: CardAction, id: MessageId? = nil) {
        guard let targetId = id ?? state.focusId,
              state.queue.contains(where: { $0.id == targetId }) else {
            return
        }
        apply(.card(id: targetId, action: action, now: Date()))
        let currentAdapter = self.adapter
        Task {
            do {
                switch action {
                case .archive:
                    try await currentAdapter.archive(id: targetId)
                case .keep:
                    try await currentAdapter.flagImportant(id: targetId)
                case .trash:
                    try await currentAdapter.moveToTrash(id: targetId, reason: .userPromo)
                }
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    public func rescueFocused() {
        guard case .handled(let item) = activeRow else { return }
        rescueRow(item.id)
    }

    public func rescueRow(_ id: MessageId) {
        guard state.handled.contains(where: { $0.id == id }) else { return }
        guard !rescuingIds.contains(id) else { return }
        rescuingIds.insert(id)
        let currentAdapter = self.adapter
        Task {
            defer { rescuingIds.remove(id) }
            do {
                let rescuedMail = try await currentAdapter.rescue(id: id)
                apply(.rescued(rescuedMail))
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    @discardableResult
    public func undo() -> Bool {
        guard let entry = state.undo.last else { return false }
        apply(.undo)
        let currentAdapter = self.adapter
        Task {
            do {
                switch entry {
                case .card(_, let mail, _, _):
                    try await currentAdapter.restore(id: mail.id)
                case .rescue(let item, let mail, _):
                    if item.disposition == .archived {
                        try await currentAdapter.archive(id: mail.id)
                    } else {
                        try await currentAdapter.moveToTrash(id: mail.id, reason: item.manual ? .userPromo : .autoPromo)
                    }
                }
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
        return true
    }

    public func openFocusedInNativeMail() {
        guard let row = activeRow else { return }
        let id = row.id
        let currentAdapter = self.adapter
        let isDemo = (sourceMode == .demo)
        Task {
            do {
                let url = try await currentAdapter.openInNativeMail(id: id)
                if isDemo {
                    showNativeNotice(url: url)
                }
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func showNativeNotice(url: String) {
        noticeTask?.cancel()
        environment.animate(0.2) {
            nativeNoticeURL = url
        }
        let sleep = environment.sleep
        let animate = environment.animate
        noticeTask = Task { [weak self] in
            try? await sleep(2_600_000_000)
            guard !Task.isCancelled else { return }
            animate(0.2) {
                self?.nativeNoticeURL = nil
            }
        }
    }

    // MARK: - Demo controls

    public func simulateIncoming() async {
        guard adapter.supportsDemoControls else { return }
        if let mails = try? await adapter.simulateIncoming(count: 3), !mails.isEmpty {
            apply(.incoming(mails))
        }
    }

    public func resetDemo() async {
        guard adapter.supportsDemoControls else { return }
        try? await adapter.resetDemo()
        await reloadSnapshot(initial: true)
    }
}
