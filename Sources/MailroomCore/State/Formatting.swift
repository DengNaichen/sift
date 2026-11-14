import Foundation

public enum Excerpt {
    /// 只有逐字出现在原文里的 evidence 才算数；否则视为没有。
    public static func evidenceOf(_ mail: MailItem) -> String? {
        guard let raw = mail.meta.evidence?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              mail.plainText.contains(raw) else {
            return nil
        }
        return raw
    }

    /// 正文开头的原文片段：跳过「您好，」这类称呼行，合并空白，不做任何改写。
    public static func openingLines(_ plainText: String, maxLength: Int = 140) -> String {
        let lines = plainText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let bodyLines: ArraySlice<String>
        if let first = lines.first,
           first.count <= 10,
           let lastChar = first.last,
           ["，", ",", ":", "："].contains(lastChar) {
            bodyLines = lines.dropFirst()
        } else {
            bodyLines = lines[...]
        }

        let joined = bodyLines
            .joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard joined.count > maxLength else { return joined }
        let idx = joined.index(joined.startIndex, offsetBy: maxLength)
        return String(joined[..<idx]) + "…"
    }
}

public enum MailFormatting {
    /// 今天 → `08:42`；昨天 → `昨天 22:10`；更早 → `11月9日`
    public static func formatTime(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let startNow = calendar.startOfDay(for: now)
        let startTarget = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: startTarget, to: startNow).day ?? 0

        let hm = String(
            format: "%02d:%02d",
            calendar.component(.hour, from: date),
            calendar.component(.minute, from: date)
        )
        if days <= 0 {
            return hm
        } else if days == 1 {
            return "昨天 \(hm)"
        } else {
            let m = calendar.component(.month, from: date)
            let d = calendar.component(.day, from: date)
            return "\(m)月\(d)日"
        }
    }

    public static func formatPercent(_ value: Double) -> String {
        "\(Int((value * 100.0).rounded()))%"
    }

    /// 按每封 30 秒的平均处理时长折算节省分钟数
    public static func savedMinutes(count: Int) -> Int {
        Int((Double(count) * 30.0 / 60.0).rounded())
    }
}
