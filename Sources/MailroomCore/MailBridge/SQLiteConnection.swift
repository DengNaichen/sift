import Foundation
import SQLite3

private let SQLITE_TRANSIENT_DESTRUCTOR = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum SQLiteError: Error, LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)

    public var errorDescription: String? {
        switch self {
        case .openFailed(let m): return "SQLite 打开失败: \(m)"
        case .prepareFailed(let m): return "SQLite 预编译失败: \(m)"
        case .stepFailed(let m): return "SQLite 执行失败: \(m)"
        }
    }
}

public final class SQLiteConnection {
    private var db: OpaquePointer?

    public init(readOnlyPath path: String) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        let rc = sqlite3_open_v2(path, &handle, flags, nil)
        guard rc == SQLITE_OK, let handle else {
            let msg = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "code \(rc)"
            if let handle { sqlite3_close(handle) }
            throw SQLiteError.openFailed("\(path) (\(msg))")
        }
        self.db = handle
        sqlite3_busy_timeout(handle, 2500)
        _ = try? execute("PRAGMA query_only = ON;")
    }

    public init(readWritePath path: String) throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX
        let rc = sqlite3_open_v2(path, &handle, flags, nil)
        guard rc == SQLITE_OK, let handle else {
            let msg = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "code \(rc)"
            if let handle { sqlite3_close(handle) }
            throw SQLiteError.openFailed("\(path) (\(msg))")
        }
        self.db = handle
        sqlite3_busy_timeout(handle, 3000)
        try execute("PRAGMA journal_mode = WAL;")
        try execute("PRAGMA synchronous = NORMAL;")
    }

    deinit {
        if let db {
            sqlite3_close_v2(db)
        }
    }

    public func execute(_ sql: String, bindings: [SQLiteValue] = []) throws {
        let stmt = try prepare(sql, bindings: bindings)
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else {
            throw SQLiteError.stepFailed(lastErrorMessage())
        }
    }

    public func query<T>(
        _ sql: String,
        bindings: [SQLiteValue] = [],
        map: (SQLiteRow) -> T
    ) throws -> [T] {
        let stmt = try prepare(sql, bindings: bindings)
        defer { sqlite3_finalize(stmt) }

        var results: [T] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW {
                results.append(map(SQLiteRow(stmt: stmt)))
            } else if rc == SQLITE_DONE {
                break
            } else {
                throw SQLiteError.stepFailed(lastErrorMessage())
            }
        }
        return results
    }

    private func prepare(_ sql: String, bindings: [SQLiteValue]) throws -> OpaquePointer {
        guard let db else { throw SQLiteError.openFailed("Closed handle") }
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK, let stmt else {
            throw SQLiteError.prepareFailed("\(lastErrorMessage()) | SQL: \(sql)")
        }
        for (idx, value) in bindings.enumerated() {
            let pos = Int32(idx + 1)
            switch value {
            case .null:
                sqlite3_bind_null(stmt, pos)
            case .int(let v):
                sqlite3_bind_int64(stmt, pos, v)
            case .double(let v):
                sqlite3_bind_double(stmt, pos, v)
            case .text(let s):
                sqlite3_bind_text(stmt, pos, s, -1, SQLITE_TRANSIENT_DESTRUCTOR)
            }
        }
        return stmt
    }

    private func lastErrorMessage() -> String {
        guard let db, let cStr = sqlite3_errmsg(db) else { return "Unknown SQLite error" }
        return String(cString: cStr)
    }
}

public enum SQLiteValue: Sendable {
    case null
    case int(Int64)
    case double(Double)
    case text(String)
}

public struct SQLiteRow {
    fileprivate let stmt: OpaquePointer

    public func int64(_ col: Int32) -> Int64 {
        sqlite3_column_int64(stmt, col)
    }

    public func optionalInt64(_ col: Int32) -> Int64? {
        sqlite3_column_type(stmt, col) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, col)
    }

    public func double(_ col: Int32) -> Double {
        sqlite3_column_double(stmt, col)
    }

    public func string(_ col: Int32) -> String? {
        guard sqlite3_column_type(stmt, col) != SQLITE_NULL,
              let ptr = sqlite3_column_text(stmt, col) else {
            return nil
        }
        return String(cString: ptr)
    }
}
