import Foundation
import MailroomCore

private func printUsage(toStderr: Bool = false) {
    let usage = """
    Usage:
      mailroom-bridge doctor [--limit <n>] [--json]
      mailroom-bridge export-eval [--limit <n>] --output <path> [--force]

    Subcommands:
      doctor       Inspect ~/Library/Mail/V* read-only (accounts, mailbox roles, WAL mode, latency, .emlx hit rate).
                   Redacts account email addresses and never prints subjects, sender names, or bodies.
      export-eval  Export up to <n> Inbox messages to an eval_gemini_emails.py-compatible JSON file (mode 0600).
    """
    if toStderr {
        FileHandle.standardError.write(Data((usage + "\n").utf8))
    } else {
        print(usage)
    }
}

private func fail(_ message: String, code: Int32 = 2) -> Never {
    FileHandle.standardError.write(Data(("error: \(message)\n").utf8))
    exit(code)
}

private func runDoctor(args: [String]) {
    var limit = 40
    var jsonOutput = false
    var i = 0
    while i < args.count {
        let arg = args[i]
        switch arg {
        case "--limit":
            i += 1
            guard i < args.count, let parsed = Int(args[i]), parsed > 0 else {
                fail("--limit requires a positive integer")
            }
            limit = parsed
        case "--json":
            jsonOutput = true
        case "-h", "--help":
            printUsage()
            exit(0)
        default:
            fail("unknown option for doctor: \(arg)")
        }
        i += 1
    }

    let report = BridgeDoctorReport.inspect(limit: limit)
    if jsonOutput {
        do {
            print(try report.renderJSON(pretty: true))
        } catch {
            fail("failed to encode doctor JSON: \(error.localizedDescription)", code: 1)
        }
    } else {
        print(report.renderText())
    }
}

private func runExportEval(args: [String]) {
    var limit = 20
    var outputPath: String?
    var force = false
    var i = 0
    while i < args.count {
        let arg = args[i]
        switch arg {
        case "--limit":
            i += 1
            guard i < args.count, let parsed = Int(args[i]), parsed > 0 else {
                fail("--limit requires a positive integer")
            }
            limit = parsed
        case "--output", "-o":
            i += 1
            guard i < args.count, !args[i].isEmpty else {
                fail("--output requires a file path")
            }
            outputPath = args[i]
        case "--force":
            force = true
        case "-h", "--help":
            printUsage()
            exit(0)
        default:
            fail("unknown option for export-eval: \(arg)")
        }
        i += 1
    }

    guard let rawOutput = outputPath else {
        fail("export-eval requires --output <path>")
    }
    let expandedPath = (rawOutput as NSString).expandingTildeInPath
    let outputURL = URL(fileURLWithPath: expandedPath)

    do {
        let doc = try EvalDatasetExporter.exportDataset(limit: limit)
        try EvalDatasetExporter.writeDataset(doc, to: outputURL, force: force)
        let totalBodyChars = doc.samples.reduce(0) { $0 + $1.email.body.count }
        let summary: [String: Any] = [
            "dataset": outputURL.path,
            "count": doc.samples.count,
            "body_characters": totalBodyChars
        ]
        if let jsonData = try? JSONSerialization.data(withJSONObject: summary, options: [.sortedKeys]),
           let jsonLine = String(data: jsonData, encoding: .utf8) {
            print(jsonLine)
        } else {
            print("exported \(doc.samples.count) samples to \(outputURL.path)")
        }
    } catch {
        fail(error.localizedDescription, code: 1)
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let subcommand = arguments.first else {
    printUsage(toStderr: true)
    exit(2)
}

switch subcommand {
case "doctor":
    runDoctor(args: Array(arguments.dropFirst()))
case "export-eval":
    runExportEval(args: Array(arguments.dropFirst()))
case "-h", "--help", "help":
    printUsage()
    exit(0)
default:
    printUsage(toStderr: true)
    fail("unknown subcommand: \(subcommand)")
}
