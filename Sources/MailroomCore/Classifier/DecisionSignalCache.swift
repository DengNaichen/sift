import CryptoKit
import Foundation

/// 持久化缓存 `gemini-decision-1` 返回的正交信号（`answers` JSON），
/// 以 `(message_id, content_sha256, policy_version)` 为复合主键。
/// 由于正交信号独立于用户 `SiftPreferences`，切换分拣偏好或预设可在内存中零网络请求即时重算。
public final class DecisionSignalCache: @unchecked Sendable {
    public let databasePath: String

    private let lock = NSLock()
    private let connection: SQLiteConnection

    public static func defaultDatabasePath() -> String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("MailroomDeck", isDirectory: true)
            .appendingPathComponent("classifier_decisions_v1.sqlite")
            .path
    }

    public static func computeContentSHA256(for canonicalInputJSON: String) -> String {
        let digest = SHA256.hash(data: Data(canonicalInputJSON.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public init(dbPath: String? = nil) throws {
        let resolvedPath = dbPath ?? Self.defaultDatabasePath()
        self.databasePath = resolvedPath
        let conn = try SQLiteConnection(readWritePath: resolvedPath)
        try conn.execute("""
            CREATE TABLE IF NOT EXISTS decision_signal_cache (
                message_id TEXT NOT NULL,
                content_sha256 TEXT NOT NULL,
                policy_version TEXT NOT NULL,
                answers_json TEXT NOT NULL,
                updated_at REAL NOT NULL,
                PRIMARY KEY (message_id, content_sha256, policy_version)
            );
        """)
        self.connection = conn
    }

    public func get(
        messageId: String,
        contentSHA256: String,
        policyVersion: String
    ) -> GeminiDecisionResponse? {
        lock.lock()
        defer { lock.unlock() }

        guard let answersJSON = (try? connection.query(
            """
            SELECT answers_json
            FROM decision_signal_cache
            WHERE message_id = ? AND content_sha256 = ? AND policy_version = ?
            LIMIT 1;
            """,
            bindings: [
                .text(messageId),
                .text(contentSHA256),
                .text(policyVersion),
            ],
            map: { $0.string(0) ?? "" }
        ))?.first,
              !answersJSON.isEmpty,
              let answers = try? JSONDecoder().decode([String: GeminiDecisionAnswer].self, from: Data(answersJSON.utf8)) else {
            return nil
        }
        return GeminiDecisionResponse(answers: answers)
    }

    public func put(
        messageId: String,
        contentSHA256: String,
        policyVersion: String,
        response: GeminiDecisionResponse,
        now: Date = Date()
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let answersData = try encoder.encode(response.answers)
        let answersJSON = String(decoding: answersData, as: UTF8.self)

        lock.lock()
        defer { lock.unlock() }

        try connection.execute(
            """
            INSERT OR REPLACE INTO decision_signal_cache (
                message_id, content_sha256, policy_version, answers_json, updated_at
            ) VALUES (?, ?, ?, ?, ?);
            """,
            bindings: [
                .text(messageId),
                .text(contentSHA256),
                .text(policyVersion),
                .text(answersJSON),
                .double(now.timeIntervalSince1970),
            ]
        )
    }

    public func clear() throws {
        lock.lock()
        defer { lock.unlock() }

        try connection.execute("DELETE FROM decision_signal_cache;")
        try? connection.execute("PRAGMA wal_checkpoint(TRUNCATE);")
        try? connection.execute("VACUUM;")
    }

    public func entryCount() -> Int {
        lock.lock()
        defer { lock.unlock() }

        let count = (try? connection.query("SELECT COUNT(*) FROM decision_signal_cache;") { $0.int64(0) })?.first ?? 0
        return Int(count)
    }

    public func databaseByteSize() -> Int64 {
        lock.lock()
        defer { lock.unlock() }

        return Self.fileTreeByteSize(forSQLitePath: databasePath)
    }

    public func formattedByteSize() -> String {
        Self.formatByteSize(databaseByteSize())
    }

    public static func fileTreeByteSize(forSQLitePath path: String) -> Int64 {
        let fm = FileManager.default
        var total: Int64 = 0
        for candidate in [path, path + "-wal", path + "-shm"] {
            if let attrs = try? fm.attributesOfItem(atPath: candidate),
               let size = attrs[.size] as? NSNumber {
                total += size.int64Value
            }
        }
        return total
    }

    public static func formatByteSize(_ bytes: Int64) -> String {
        if bytes <= 0 {
            return "0 KB"
        }
        return Attachment.formatBytes(Int(clamping: bytes))
    }
}
