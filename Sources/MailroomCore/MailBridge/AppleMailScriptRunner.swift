import AppKit
import Foundation

public enum AppleMailScriptError: Error, LocalizedError, Equatable, Sendable {
    case executionFailed(String)
    case messageNotFound(String)
    case mailboxNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .executionFailed(let msg): return "Apple Mail 操作失败: \(msg)"
        case .messageNotFound(let id): return "在 Apple Mail 中未找到目标邮件 (\(id))"
        case .mailboxNotFound(let mailbox): return "在 Apple Mail 中未找到目标邮箱 (\(mailbox))"
        }
    }
}

/// Abstract executor for Mail.app mutations so production runs AppleEvents and tests run 100% offline.
public protocol AppleMailExecutor: Sendable {
    func ensureMailRunningSilently() async
    func moveMessage(
        accountUUID: String,
        sourceMailboxes: [String],
        destinationMailbox: String,
        createDestinationIfMissing: Bool,
        rowId: Int64?,
        rfcMessageId: String,
        markRead: Bool?,
        markFlagged: Bool?
    ) async throws
    func updateFlags(
        accountUUID: String,
        mailboxes: [String],
        rowId: Int64?,
        rfcMessageId: String,
        markRead: Bool?,
        markFlagged: Bool?
    ) async throws
    func openMessageWindow(
        accountUUID: String,
        mailboxes: [String],
        rowId: Int64?,
        rfcMessageId: String
    ) async throws
    func fetchMessageSource(
        accountUUID: String,
        mailboxes: [String],
        rowId: Int64?,
        rfcMessageId: String
    ) async throws -> String
}

public extension AppleMailExecutor {
    func moveMessage(
        accountUUID: String,
        sourceMailbox: String,
        destinationMailbox: String,
        createDestinationIfMissing: Bool = false,
        rowId: Int64?,
        rfcMessageId: String,
        markRead: Bool? = nil,
        markFlagged: Bool? = nil
    ) async throws {
        try await moveMessage(
            accountUUID: accountUUID,
            sourceMailboxes: [sourceMailbox],
            destinationMailbox: destinationMailbox,
            createDestinationIfMissing: createDestinationIfMissing,
            rowId: rowId,
            rfcMessageId: rfcMessageId,
            markRead: markRead,
            markFlagged: markFlagged
        )
    }

    func updateFlags(
        accountUUID: String,
        mailbox: String,
        rowId: Int64?,
        rfcMessageId: String,
        markRead: Bool? = nil,
        markFlagged: Bool? = nil
    ) async throws {
        try await updateFlags(
            accountUUID: accountUUID,
            mailboxes: [mailbox],
            rowId: rowId,
            rfcMessageId: rfcMessageId,
            markRead: markRead,
            markFlagged: markFlagged
        )
    }

    func openMessageWindow(
        accountUUID: String,
        mailbox: String,
        rowId: Int64?,
        rfcMessageId: String
    ) async throws {
        try await openMessageWindow(
            accountUUID: accountUUID,
            mailboxes: [mailbox],
            rowId: rowId,
            rfcMessageId: rfcMessageId
        )
    }

    func fetchMessageSource(
        accountUUID: String,
        mailbox: String,
        rowId: Int64?,
        rfcMessageId: String
    ) async throws -> String {
        try await fetchMessageSource(
            accountUUID: accountUUID,
            mailboxes: [mailbox],
            rowId: rowId,
            rfcMessageId: rfcMessageId
        )
    }
}

/// Pure AppleScript generator & compile-verifier for Mail.app operations across Gmail, Exchange, iCloud, and IMAP.
public enum AppleMailScriptBuilder: Sendable {
    private static let gmailAllMailNames: Set<String> = [
        "[gmail]/all mail",
        "[gmail]/所有邮件",
        "[google mail]/all mail"
    ]

    private static let protectedSystemMailboxes: Set<String> = [
        "inbox",
        "收件箱",
        "[gmail]",
        "[google mail]"
    ]

    public static func isGmailAllMailPath(_ path: String) -> Bool {
        gmailAllMailNames.contains(path.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    /// Normalizes candidate source mailboxes in priority order.
    /// When archiving to Gmail's `[Gmail]/All Mail`, a caller that only knew the physical SQLite
    /// mailbox (`[Gmail]/All Mail`) would otherwise skip `move` because `source == destination`.
    /// Prepending `INBOX` ensures Mail.app finds the message in `INBOX` first and strips the `INBOX` label.
    public static func normalizedSourceMailboxes(
        _ sourceMailboxes: [String],
        destinationMailbox: String? = nil
    ) -> [String] {
        var ordered: [String] = []
        var seen: Set<String> = []

        func appendUnique(_ raw: String) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let key = trimmed.lowercased()
            if seen.insert(key).inserted {
                ordered.append(trimmed)
            }
        }

        if let destinationMailbox, isGmailAllMailPath(destinationMailbox) {
            let hasInbox = sourceMailboxes.contains {
                let lower = $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return lower == "inbox" || lower == "收件箱"
            }
            if !hasInbox {
                appendUnique("INBOX")
            }
        }

        for mb in sourceMailboxes {
            appendUnique(mb)
        }
        return ordered
    }

    public static func buildMoveScript(
        accountUUID: String,
        sourceMailboxes: [String],
        destinationMailbox: String,
        createDestinationIfMissing: Bool,
        rowId: Int64?,
        rfcMessageId: String,
        markRead: Bool?,
        markFlagged: Bool?
    ) -> String {
        let candidates = normalizedSourceMailboxes(sourceMailboxes, destinationMailbox: destinationMailbox)
        let lookupBlock = buildMultiMailboxLookupClause(
            candidates: candidates,
            rowId: rowId,
            rfcMessageId: rfcMessageId
        )
        let destinationBlock = buildDestinationMailboxClause(
            destinationMailbox: destinationMailbox,
            createIfMissing: createDestinationIfMissing
        )
        let mutations = buildFlagMutationLines(markRead: markRead, markFlagged: markFlagged)

        return """
        tell application "Mail"
            set acc to account id "\(escapeAS(accountUUID))"
            \(lookupBlock)
            \(destinationBlock)
            \(mutations)
            if matchedBoxPath is not "\(escapeAS(destinationMailbox))" then
                move msg to dstBox
            end if
            return "ok"
        end tell
        """
    }

    public static func buildUpdateFlagsScript(
        accountUUID: String,
        mailboxes: [String],
        rowId: Int64?,
        rfcMessageId: String,
        markRead: Bool?,
        markFlagged: Bool?
    ) -> String {
        let candidates = normalizedSourceMailboxes(mailboxes)
        let lookupBlock = buildMultiMailboxLookupClause(
            candidates: candidates,
            rowId: rowId,
            rfcMessageId: rfcMessageId
        )
        let mutations = buildFlagMutationLines(markRead: markRead, markFlagged: markFlagged)

        return """
        tell application "Mail"
            set acc to account id "\(escapeAS(accountUUID))"
            \(lookupBlock)
            \(mutations)
            return "ok"
        end tell
        """
    }

    public static func buildOpenMessageScript(
        accountUUID: String,
        mailboxes: [String],
        rowId: Int64?,
        rfcMessageId: String
    ) -> String {
        let candidates = normalizedSourceMailboxes(mailboxes)
        let lookupBlock = buildMultiMailboxLookupClause(
            candidates: candidates,
            rowId: rowId,
            rfcMessageId: rfcMessageId
        )

        return """
        tell application "Mail"
            set acc to account id "\(escapeAS(accountUUID))"
            \(lookupBlock)
            open msg
            activate
            return "ok"
        end tell
        """
    }

    public static func buildFetchSourceScript(
        accountUUID: String,
        mailboxes: [String],
        rowId: Int64?,
        rfcMessageId: String
    ) -> String {
        let candidates = normalizedSourceMailboxes(mailboxes)
        let lookupBlock = buildMultiMailboxLookupClause(
            candidates: candidates,
            rowId: rowId,
            rfcMessageId: rfcMessageId
        )

        return """
        tell application "Mail"
            set acc to account id "\(escapeAS(accountUUID))"
            \(lookupBlock)
            set wasReadBefore to read status of msg
            set rawSrc to source of msg
            if (read status of msg) is not wasReadBefore then
                set read status of msg to wasReadBefore
            end if
            return rawSrc
        end tell
        """
    }

    /// Compiles AppleScript syntax without executing any AppleEvents.
    public static func compileCheck(_ source: String) -> Result<Void, AppleMailScriptError> {
        guard let appleScript = NSAppleScript(source: source) else {
            return .failure(.executionFailed("无法初始化 AppleScript"))
        }
        var compileError: NSDictionary?
        if appleScript.compileAndReturnError(&compileError) {
            return .success(())
        }
        let msg = (compileError?[NSAppleScript.errorMessage] as? String)
            ?? compileError?.description
            ?? "未知编译错误"
        return .failure(.executionFailed("AppleScript 编译失败: \(msg)"))
    }

    // MARK: - Clause Builders

    private static func buildMultiMailboxLookupClause(
        candidates: [String],
        rowId: Int64?,
        rfcMessageId: String
    ) -> String {
        let effectiveCandidates = candidates.isEmpty ? ["INBOX"] : candidates
        let cleanMid = normalizeMessageId(rfcMessageId)
        let escapedMid = escapeAS(cleanMid)
        let bracketedMid = escapeAS("<\(cleanMid)>")

        var blocks: [String] = [
            "set matchedBoxPath to \"\"",
            "set msg to missing value"
        ]

        for path in effectiveCandidates {
            let resolveCandidate = buildResolveMailboxVariableClause(
                varName: "candidateBox",
                path: path
            )
            var searchLines: [String] = []
            if let rowId {
                searchLines.append("set matched to (messages of candidateBox whose id is \(rowId))")
                if !cleanMid.isEmpty {
                    searchLines.append("if (count of matched) is 0 then")
                    searchLines.append("    set matched to (messages of candidateBox whose message id is \"\(escapedMid)\")")
                    searchLines.append("end if")
                    searchLines.append("if (count of matched) is 0 then")
                    searchLines.append("    set matched to (messages of candidateBox whose message id is \"\(bracketedMid)\")")
                    searchLines.append("end if")
                }
            } else if !cleanMid.isEmpty {
                searchLines.append("set matched to (messages of candidateBox whose message id is \"\(escapedMid)\")")
                searchLines.append("if (count of matched) is 0 then")
                searchLines.append("    set matched to (messages of candidateBox whose message id is \"\(bracketedMid)\")")
                searchLines.append("end if")
            } else {
                searchLines.append("set matched to {}")
            }

            let searchBody = searchLines.joined(separator: "\n                ")
            blocks.append("""
            if msg is missing value then
                \(resolveCandidate)
                if candidateBox is not missing value then
                    \(searchBody)
                    if (count of matched) > 0 then
                        set msg to item 1 of matched
                        set matchedBoxPath to "\(escapeAS(path))"
                    end if
                end if
            end if
            """)
        }

        blocks.append("""
        if msg is missing value then
            error "MESSAGE_NOT_FOUND"
        end if
        """)
        return blocks.joined(separator: "\n    ")
    }

    private static func buildDestinationMailboxClause(
        destinationMailbox: String,
        createIfMissing: Bool
    ) -> String {
        let resolveClause = buildResolveMailboxVariableClause(varName: "dstBox", path: destinationMailbox)
        let segments = splitMailboxSegments(destinationMailbox)
        let canCreate = createIfMissing
            && !segments.isEmpty
            && !isGmailAllMailPath(destinationMailbox)
            && !protectedSystemMailboxes.contains(segments[0].lowercased())

        var createClause = ""
        if canCreate {
            var createSteps: [String] = ["set curBox to acc"]
            for seg in segments {
                let escSeg = escapeAS(seg)
                createSteps.append("""
                if not (exists (mailbox "\(escSeg)" of curBox)) then
                    make new mailbox with properties {name:"\(escSeg)"} at curBox
                end if
                set curBox to mailbox "\(escSeg)" of curBox
                """)
            }
            createSteps.append("set dstBox to curBox")
            createClause = """
            if dstBox is missing value then
                \(createSteps.joined(separator: "\n        "))
            end if
            """
        }

        return """
        \(resolveClause)
        \(createClause)
        if dstBox is missing value then
            error "MAILBOX_NOT_FOUND:\(escapeAS(destinationMailbox))"
        end if
        """
    }

    private static func buildResolveMailboxVariableClause(varName: String, path: String) -> String {
        let escapedPath = escapeAS(path)
        let segments = splitMailboxSegments(path)
        if segments.count <= 1 {
            return """
            set \(varName) to missing value
            if exists (mailbox "\(escapedPath)" of acc) then
                set \(varName) to mailbox "\(escapedPath)" of acc
            end if
            """
        }

        // Support both flat ("Parent/Child") and nested ("Child" of "Parent") Mail.app mailbox specifiers.
        var nestedCheck = "set \(varName) to curBox"
        for seg in segments.reversed() {
            let escSeg = escapeAS(seg)
            nestedCheck = """
            if exists (mailbox "\(escSeg)" of curBox) then
                set curBox to mailbox "\(escSeg)" of curBox
                \(nestedCheck)
            end if
            """
        }

        return """
        set \(varName) to missing value
        if exists (mailbox "\(escapedPath)" of acc) then
            set \(varName) to mailbox "\(escapedPath)" of acc
        else
            set curBox to acc
            \(nestedCheck)
        end if
        """
    }

    private static func buildFlagMutationLines(markRead: Bool?, markFlagged: Bool?) -> String {
        var lines: [String] = []
        if let markRead {
            lines.append("set read status of msg to \(markRead ? "true" : "false")")
        }
        if let markFlagged {
            lines.append("set flagged status of msg to \(markFlagged ? "true" : "false")")
        }
        return lines.joined(separator: "\n    ")
    }

    private static func splitMailboxSegments(_ path: String) -> [String] {
        path.split(separator: "/").map(String.init).filter { !$0.isEmpty }
    }

    private static func normalizeMessageId(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("<") { trimmed.removeFirst() }
        if trimmed.hasSuffix(">") { trimmed.removeLast() }
        return trimmed
    }

    public static func escapeAS(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

/// 串行执行针对 `com.apple.mail` 的精准 AppleEvent（按 Account UUID + Mailbox Path + 整数 ROWID O(1) 定位）。
public actor AppleMailScriptRunner: AppleMailExecutor {
    public typealias EnsureRunningHook = @Sendable () async -> Void
    public typealias RawScriptEvaluator = @Sendable (_ source: String, _ messageIdHint: String) throws -> String

    private let maxRetries: Int
    private let retryDelayNanoseconds: UInt64
    private let ensureRunningHook: EnsureRunningHook?
    private let rawScriptEvaluator: RawScriptEvaluator?

    public init(
        maxRetries: Int = 2,
        retryDelayNanoseconds: UInt64 = 250_000_000,
        ensureRunningHook: EnsureRunningHook? = nil,
        rawScriptEvaluator: RawScriptEvaluator? = nil
    ) {
        self.maxRetries = max(0, maxRetries)
        self.retryDelayNanoseconds = retryDelayNanoseconds
        self.ensureRunningHook = ensureRunningHook
        self.rawScriptEvaluator = rawScriptEvaluator
    }

    public func ensureMailRunningSilently() async {
        if let ensureRunningHook {
            await ensureRunningHook()
            return
        }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.mail")
        guard running.isEmpty else { return }
        let mailURL = URL(fileURLWithPath: "/System/Applications/Mail.app")
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.hides = true
        _ = try? await NSWorkspace.shared.openApplication(at: mailURL, configuration: config)
        try? await Task.sleep(nanoseconds: 900_000_000)
    }

    public func moveMessage(
        accountUUID: String,
        sourceMailboxes: [String],
        destinationMailbox: String,
        createDestinationIfMissing: Bool = false,
        rowId: Int64?,
        rfcMessageId: String,
        markRead: Bool?,
        markFlagged: Bool?
    ) async throws {
        await ensureMailRunningSilently()
        let script = AppleMailScriptBuilder.buildMoveScript(
            accountUUID: accountUUID,
            sourceMailboxes: sourceMailboxes,
            destinationMailbox: destinationMailbox,
            createDestinationIfMissing: createDestinationIfMissing,
            rowId: rowId,
            rfcMessageId: rfcMessageId,
            markRead: markRead,
            markFlagged: markFlagged
        )
        _ = try await executeWithRetries(script, messageIdHint: rfcMessageId)
    }

    public func updateFlags(
        accountUUID: String,
        mailboxes: [String],
        rowId: Int64?,
        rfcMessageId: String,
        markRead: Bool?,
        markFlagged: Bool?
    ) async throws {
        await ensureMailRunningSilently()
        let script = AppleMailScriptBuilder.buildUpdateFlagsScript(
            accountUUID: accountUUID,
            mailboxes: mailboxes,
            rowId: rowId,
            rfcMessageId: rfcMessageId,
            markRead: markRead,
            markFlagged: markFlagged
        )
        _ = try await executeWithRetries(script, messageIdHint: rfcMessageId)
    }

    public func openMessageWindow(
        accountUUID: String,
        mailboxes: [String],
        rowId: Int64?,
        rfcMessageId: String
    ) async throws {
        await ensureMailRunningSilently()
        let script = AppleMailScriptBuilder.buildOpenMessageScript(
            accountUUID: accountUUID,
            mailboxes: mailboxes,
            rowId: rowId,
            rfcMessageId: rfcMessageId
        )
        _ = try await executeWithRetries(script, messageIdHint: rfcMessageId)
    }

    public func fetchMessageSource(
        accountUUID: String,
        mailboxes: [String],
        rowId: Int64?,
        rfcMessageId: String
    ) async throws -> String {
        await ensureMailRunningSilently()
        let script = AppleMailScriptBuilder.buildFetchSourceScript(
            accountUUID: accountUUID,
            mailboxes: mailboxes,
            rowId: rowId,
            rfcMessageId: rfcMessageId
        )
        return try await executeWithRetries(script, messageIdHint: rfcMessageId)
    }

    // MARK: - Execution & Retry

    private func executeWithRetries(_ source: String, messageIdHint: String) async throws -> String {
        var attempt = 0
        while true {
            do {
                if let rawScriptEvaluator {
                    return try rawScriptEvaluator(source, messageIdHint)
                }
                return try runAppleScript(source, messageIdHint: messageIdHint)
            } catch let error as AppleMailScriptError {
                guard shouldRetry(error), attempt < maxRetries else {
                    throw error
                }
                attempt += 1
                if retryDelayNanoseconds > 0 {
                    try? await Task.sleep(nanoseconds: retryDelayNanoseconds * UInt64(attempt))
                }
            }
        }
    }

    private func shouldRetry(_ error: AppleMailScriptError) -> Bool {
        switch error {
        case .messageNotFound, .mailboxNotFound:
            return false
        case .executionFailed(let msg):
            // Compile/initialization failures are deterministic; runtime AppleEvent timeouts/busy states can be retried.
            if msg.contains("编译失败") || msg.contains("无法初始化") {
                return false
            }
            return true
        }
    }

    private func runAppleScript(_ source: String, messageIdHint: String) throws -> String {
        if case .failure(let compileErr) = AppleMailScriptBuilder.compileCheck(source) {
            throw compileErr
        }
        guard let appleScript = NSAppleScript(source: source) else {
            throw AppleMailScriptError.executionFailed("无法初始化 AppleScript")
        }
        var errorDict: NSDictionary?
        let descriptor = appleScript.executeAndReturnError(&errorDict)
        if let errorDict {
            throw Self.mapExecutionError(errorDict, messageIdHint: messageIdHint)
        }
        return descriptor.stringValue ?? ""
    }

    public static func mapExecutionError(_ errorDict: NSDictionary, messageIdHint: String) -> AppleMailScriptError {
        let msg = (errorDict[NSAppleScript.errorMessage] as? String) ?? errorDict.description
        return mapExecutionErrorMessage(msg, messageIdHint: messageIdHint)
    }

    public static func mapExecutionErrorMessage(_ msg: String, messageIdHint: String) -> AppleMailScriptError {
        if msg.contains("MESSAGE_NOT_FOUND") {
            return .messageNotFound(messageIdHint)
        }
        if let range = msg.range(of: "MAILBOX_NOT_FOUND:") {
            let tail = String(msg[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return .mailboxNotFound(tail)
        }
        return .executionFailed(msg)
    }
}

/// Offline test double that captures operations and generated AppleScripts without touching Mail.app.
public actor MockAppleMailExecutor: AppleMailExecutor {
    public enum OperationKind: String, Sendable, Equatable {
        case ensureRunning
        case moveMessage
        case updateFlags
        case openMessageWindow
        case fetchMessageSource
    }

    public struct RecordedInvocation: Sendable, Equatable {
        public let kind: OperationKind
        public let accountUUID: String
        public let sourceMailboxes: [String]
        public let destinationMailbox: String?
        public let createDestinationIfMissing: Bool
        public let rowId: Int64?
        public let rfcMessageId: String
        public let markRead: Bool?
        public let markFlagged: Bool?
        public let generatedScript: String?

        public init(
            kind: OperationKind,
            accountUUID: String,
            sourceMailboxes: [String],
            destinationMailbox: String?,
            createDestinationIfMissing: Bool,
            rowId: Int64?,
            rfcMessageId: String,
            markRead: Bool?,
            markFlagged: Bool?,
            generatedScript: String?
        ) {
            self.kind = kind
            self.accountUUID = accountUUID
            self.sourceMailboxes = sourceMailboxes
            self.destinationMailbox = destinationMailbox
            self.createDestinationIfMissing = createDestinationIfMissing
            self.rowId = rowId
            self.rfcMessageId = rfcMessageId
            self.markRead = markRead
            self.markFlagged = markFlagged
            self.generatedScript = generatedScript
        }
    }

    public private(set) var invocations: [RecordedInvocation] = []
    public private(set) var ensureRunningCount: Int = 0
    private var queuedErrors: [Error] = []
    private var mockedMessageSources: [String: String] = [:]
    private let verifyScriptSyntax: Bool

    public init(verifyScriptSyntax: Bool = true) {
        self.verifyScriptSyntax = verifyScriptSyntax
    }

    public func enqueueError(_ error: Error) {
        queuedErrors.append(error)
    }

    public func setMockMessageSource(_ rawMime: String, for rfcMessageId: String) {
        var clean = rfcMessageId.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("<") { clean.removeFirst() }
        if clean.hasSuffix(">") { clean.removeLast() }
        mockedMessageSources[clean] = rawMime
        mockedMessageSources[rfcMessageId] = rawMime
    }

    public func reset() {
        invocations.removeAll()
        ensureRunningCount = 0
        queuedErrors.removeAll()
        mockedMessageSources.removeAll()
    }

    public func ensureMailRunningSilently() async {
        ensureRunningCount += 1
        invocations.append(
            RecordedInvocation(
                kind: .ensureRunning,
                accountUUID: "",
                sourceMailboxes: [],
                destinationMailbox: nil,
                createDestinationIfMissing: false,
                rowId: nil,
                rfcMessageId: "",
                markRead: nil,
                markFlagged: nil,
                generatedScript: nil
            )
        )
    }

    public func moveMessage(
        accountUUID: String,
        sourceMailboxes: [String],
        destinationMailbox: String,
        createDestinationIfMissing: Bool,
        rowId: Int64?,
        rfcMessageId: String,
        markRead: Bool?,
        markFlagged: Bool?
    ) async throws {
        let script = AppleMailScriptBuilder.buildMoveScript(
            accountUUID: accountUUID,
            sourceMailboxes: sourceMailboxes,
            destinationMailbox: destinationMailbox,
            createDestinationIfMissing: createDestinationIfMissing,
            rowId: rowId,
            rfcMessageId: rfcMessageId,
            markRead: markRead,
            markFlagged: markFlagged
        )
        if verifyScriptSyntax, case .failure(let err) = AppleMailScriptBuilder.compileCheck(script) {
            throw err
        }
        invocations.append(
            RecordedInvocation(
                kind: .moveMessage,
                accountUUID: accountUUID,
                sourceMailboxes: AppleMailScriptBuilder.normalizedSourceMailboxes(
                    sourceMailboxes,
                    destinationMailbox: destinationMailbox
                ),
                destinationMailbox: destinationMailbox,
                createDestinationIfMissing: createDestinationIfMissing,
                rowId: rowId,
                rfcMessageId: rfcMessageId,
                markRead: markRead,
                markFlagged: markFlagged,
                generatedScript: script
            )
        )
        if !queuedErrors.isEmpty {
            throw queuedErrors.removeFirst()
        }
    }

    public func updateFlags(
        accountUUID: String,
        mailboxes: [String],
        rowId: Int64?,
        rfcMessageId: String,
        markRead: Bool?,
        markFlagged: Bool?
    ) async throws {
        let script = AppleMailScriptBuilder.buildUpdateFlagsScript(
            accountUUID: accountUUID,
            mailboxes: mailboxes,
            rowId: rowId,
            rfcMessageId: rfcMessageId,
            markRead: markRead,
            markFlagged: markFlagged
        )
        if verifyScriptSyntax, case .failure(let err) = AppleMailScriptBuilder.compileCheck(script) {
            throw err
        }
        invocations.append(
            RecordedInvocation(
                kind: .updateFlags,
                accountUUID: accountUUID,
                sourceMailboxes: AppleMailScriptBuilder.normalizedSourceMailboxes(mailboxes),
                destinationMailbox: nil,
                createDestinationIfMissing: false,
                rowId: rowId,
                rfcMessageId: rfcMessageId,
                markRead: markRead,
                markFlagged: markFlagged,
                generatedScript: script
            )
        )
        if !queuedErrors.isEmpty {
            throw queuedErrors.removeFirst()
        }
    }

    public func openMessageWindow(
        accountUUID: String,
        mailboxes: [String],
        rowId: Int64?,
        rfcMessageId: String
    ) async throws {
        let script = AppleMailScriptBuilder.buildOpenMessageScript(
            accountUUID: accountUUID,
            mailboxes: mailboxes,
            rowId: rowId,
            rfcMessageId: rfcMessageId
        )
        if verifyScriptSyntax, case .failure(let err) = AppleMailScriptBuilder.compileCheck(script) {
            throw err
        }
        invocations.append(
            RecordedInvocation(
                kind: .openMessageWindow,
                accountUUID: accountUUID,
                sourceMailboxes: AppleMailScriptBuilder.normalizedSourceMailboxes(mailboxes),
                destinationMailbox: nil,
                createDestinationIfMissing: false,
                rowId: rowId,
                rfcMessageId: rfcMessageId,
                markRead: nil,
                markFlagged: nil,
                generatedScript: script
            )
        )
        if !queuedErrors.isEmpty {
            throw queuedErrors.removeFirst()
        }
    }

    public func fetchMessageSource(
        accountUUID: String,
        mailboxes: [String],
        rowId: Int64?,
        rfcMessageId: String
    ) async throws -> String {
        let script = AppleMailScriptBuilder.buildFetchSourceScript(
            accountUUID: accountUUID,
            mailboxes: mailboxes,
            rowId: rowId,
            rfcMessageId: rfcMessageId
        )
        if verifyScriptSyntax, case .failure(let err) = AppleMailScriptBuilder.compileCheck(script) {
            throw err
        }
        invocations.append(
            RecordedInvocation(
                kind: .fetchMessageSource,
                accountUUID: accountUUID,
                sourceMailboxes: AppleMailScriptBuilder.normalizedSourceMailboxes(mailboxes),
                destinationMailbox: nil,
                createDestinationIfMissing: false,
                rowId: rowId,
                rfcMessageId: rfcMessageId,
                markRead: nil,
                markFlagged: nil,
                generatedScript: script
            )
        )
        if !queuedErrors.isEmpty {
            throw queuedErrors.removeFirst()
        }
        var clean = rfcMessageId.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("<") { clean.removeFirst() }
        if clean.hasSuffix(">") { clean.removeLast() }
        if let hit = mockedMessageSources[rfcMessageId] ?? mockedMessageSources[clean] {
            return hit
        }
        throw AppleMailScriptError.messageNotFound(rfcMessageId)
    }
}
