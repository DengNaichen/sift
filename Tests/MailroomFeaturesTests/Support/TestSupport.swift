import AppKit
import Foundation
import Testing
@testable import MailroomCore
@testable import MailroomFeatures

/// 固定时刻：早于任何真实运行时间一年以上，`MailFormatting.formatTime` 恒输出「M月D日」，保证快照与金样稳定。
let fixtureNow = Date(timeIntervalSince1970: 1_736_913_600) // 2025-01-15 12:00 +08:00

@MainActor
func makeTestEnvironment(
    defaults: UserDefaults,
    access: MailAccessStatus = .fullDiskAccessRequired(expectedPath: "/Users/test/Library/Mail/V10/MailData/Envelope Index"),
    systemIsDark: Bool = false
) -> AppEnvironment {
    AppEnvironment(
        checkAccess: { access },
        makeLiveAdapter: { nil },
        makeDemoAdapter: { MockMailAdapter(now: fixtureNow) },
        defaults: defaults,
        systemIsDark: { systemIsDark },
        openFullDiskAccessSettings: {},
        animate: { _, body in body() },
        sleep: { nanoseconds in try await Task.sleep(nanoseconds: nanoseconds) }
    )
}

func makeIsolatedDefaults(_ name: String = UUID().uuidString) -> UserDefaults {
    let suite = "mailroom-tests-\(name)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

/// 轮询等待异步副作用落地（adapter 调用、初次加载）。
@MainActor
func waitUntil(
    timeout: TimeInterval = 3,
    _ sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: @MainActor () -> Bool
) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline {
            Issue.record("waitUntil timed out", sourceLocation: sourceLocation)
            return
        }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
}

// MARK: - Golden files

enum Golden {
    static var directory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("__Goldens__", isDirectory: true)
    }

    static var isRecording: Bool {
        ProcessInfo.processInfo.environment["RECORD_GOLDENS"] == "1"
    }

    /// 首次运行（或 RECORD_GOLDENS=1）录制；之后逐行比对。
    static func assertMatches(
        _ actual: String,
        named name: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let url = directory.appendingPathComponent("\(name).txt")
        let fm = FileManager.default
        if isRecording || !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
            try? actual.write(to: url, atomically: true, encoding: .utf8)
            return
        }
        let expected = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        if expected != actual {
            let expectedLines = expected.components(separatedBy: "\n")
            let actualLines = actual.components(separatedBy: "\n")
            var report: [String] = []
            for i in 0..<max(expectedLines.count, actualLines.count) {
                let e = i < expectedLines.count ? expectedLines[i] : "<missing>"
                let a = i < actualLines.count ? actualLines[i] : "<missing>"
                if e != a {
                    report.append("line \(i + 1):\n  - \(e)\n  + \(a)")
                    if report.count >= 12 { break }
                }
            }
            Issue.record("Golden '\(name)' mismatch:\n\(report.joined(separator: "\n"))", sourceLocation: sourceLocation)
        }
    }
}
