import CoreFoundation
import Foundation

public enum PlistMetadataValue: Equatable, Hashable, Codable, Sendable {
    case int(Int64)
    case double(Double)
    case bool(Bool)
    case string(String)
    case date(Date)
    case data(Data)
    case array([PlistMetadataValue])
    case dictionary([String: PlistMetadataValue])
}

public struct ParsedEmlx: Equatable, Sendable {
    public let messageId: String?
    public let from: Sender?
    public let to: [Sender]
    public let subject: String?
    public let dateHeader: String?
    public let plainText: String
    public let attachments: [Attachment]
    public let hasListUnsubscribe: Bool
    public let hasListId: Bool
    public let isReply: Bool
    public let isAutoSubmitted: Bool
    public let unloadedHtmlImages: Int
    public let bodyRepresentation: String
    public let isBoilerplateStub: Bool
    public let bodyIsImageOnly: Bool
    public let isPartial: Bool
    public let isTruncated: Bool
    public let plistFlags: Int?
    public let plistMetadata: [String: PlistMetadataValue]
    public let htmlBody: String?
    public let hasRemoteImages: Bool

    public init(
        messageId: String?,
        from: Sender?,
        subject: String?,
        plainText: String,
        attachments: [Attachment],
        hasListUnsubscribe: Bool,
        hasListId: Bool,
        isReply: Bool,
        isAutoSubmitted: Bool,
        to: [Sender] = [],
        dateHeader: String? = nil,
        unloadedHtmlImages: Int = 0,
        bodyRepresentation: String = "empty",
        isBoilerplateStub: Bool = false,
        bodyIsImageOnly: Bool = false,
        isPartial: Bool = false,
        isTruncated: Bool = false,
        plistFlags: Int? = nil,
        plistMetadata: [String: PlistMetadataValue] = [:],
        htmlBody: String? = nil,
        hasRemoteImages: Bool = false
    ) {
        self.messageId = messageId
        self.from = from
        self.to = to
        self.subject = subject
        self.dateHeader = dateHeader
        self.plainText = plainText
        self.attachments = attachments
        self.hasListUnsubscribe = hasListUnsubscribe
        self.hasListId = hasListId
        self.isReply = isReply
        self.isAutoSubmitted = isAutoSubmitted
        self.unloadedHtmlImages = unloadedHtmlImages
        self.bodyRepresentation = bodyRepresentation
        self.isBoilerplateStub = isBoilerplateStub
        self.bodyIsImageOnly = bodyIsImageOnly
        self.isPartial = isPartial
        self.isTruncated = isTruncated
        self.plistFlags = plistFlags
        self.plistMetadata = plistMetadata
        self.htmlBody = htmlBody
        self.hasRemoteImages = hasRemoteImages
    }
}

public enum EmlxParser {
    /// 解析磁盘上的 `.emlx` 或 `.partial.emlx` 文件
    public static func parseFile(at url: URL) throws -> ParsedEmlx {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let isPartial = url.lastPathComponent.lowercased().hasSuffix(".partial.emlx")
        return parse(data: data, isPartial: isPartial)
    }

    public static func parse(data: Data, isPartial: Bool = false) -> ParsedEmlx {
        let sliced = sliceMimePayload(from: data)
        let (headers, bodySlice) = splitHeadersAndBody(sliced.mimePayload)
        let (plistFlags, plistMetadata) = parseTrailingPlist(sliced.trailingPlist)

        let rawMsgId = headers["message-id"]?.first
        let cleanMsgId = extractAngleToken(rawMsgId) ?? rawMsgId?.trimmingCharacters(in: .whitespacesAndNewlines)

        let decodedSubject = headers["subject"]?.first.map { decodeRFC2047($0) }
        let parsedFrom = headers["from"]?.first.map { parseAddressHeader($0) }
        let parsedTo = (headers["to"] ?? []).flatMap { parseAddressList($0) }
        let rawDate = headers["date"]?.first.map { decodeRFC2047($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        let dateHeader = (rawDate?.isEmpty == false) ? rawDate : nil

        let hasListUnsub = !(headers["list-unsubscribe"]?.first ?? "").isEmpty
        let hasListId = !(headers["list-id"]?.first ?? "").isEmpty
        let isReply = !(headers["in-reply-to"]?.first ?? "").isEmpty || !(headers["references"]?.first ?? "").isEmpty
        let autoSub = (headers["auto-submitted"]?.first ?? "").lowercased()
        let precedence = (headers["precedence"]?.first ?? "").lowercased()
        let isAuto = (!autoSub.isEmpty && autoSub != "no")
            || precedence == "bulk" || precedence == "list" || precedence == "junk"

        var plainCandidates: [String] = []
        var htmlCandidates: [String] = []
        var attachments: [Attachment] = []
        var inlineCidImages: [String: String] = [:]

        walkPart(
            headers: headers,
            body: bodySlice,
            plainCandidates: &plainCandidates,
            htmlCandidates: &htmlCandidates,
            attachments: &attachments,
            inlineCidImages: &inlineCidImages
        )

        let nonBlankHtml = htmlCandidates.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let resolvedHtml: String? = nonBlankHtml.first.map { rawHtml in
            resolveInlineCidReferences(in: rawHtml, cidMap: inlineCidImages)
        }
        let hasRemoteImages = resolvedHtml.map { containsRemoteImageResources($0) } ?? false

        // Precompute HTML text extraction when HTML exists so stub plain-text parts can fall back cleanly
        var htmlSelectedText: String?
        var htmlSelectedImages = 0
        var htmlFallbackImages = 0
        for html in nonBlankHtml {
            let extracted = extractHtmlText(html)
            htmlFallbackImages += extracted.imageCount
            let normalized = normalizePlainText(extracted.text)
            if !normalized.isEmpty {
                htmlSelectedText = normalized
                htmlSelectedImages = extracted.imageCount
                break
            }
        }

        let chosenText: String
        let unloadedHtmlImages: Int
        let bodyRepresentation: String

        let firstPlain = plainCandidates.map({ normalizePlainText($0) }).first(where: { !$0.isEmpty })
        let plainIsStub = firstPlain.map { substantiveBodyText($0).isEmpty } ?? true

        if let firstPlain, (!plainIsStub || htmlSelectedText == nil) {
            chosenText = firstPlain
            unloadedHtmlImages = 0
            bodyRepresentation = "full_plain_text"
        } else if !nonBlankHtml.isEmpty {
            if let text = htmlSelectedText {
                chosenText = text
                unloadedHtmlImages = htmlSelectedImages
                bodyRepresentation = "text_extracted_from_full_html_with_image_alt"
            } else {
                chosenText = ""
                unloadedHtmlImages = htmlFallbackImages
                bodyRepresentation = "empty"
            }
        } else {
            chosenText = ""
            unloadedHtmlImages = 0
            bodyRepresentation = "empty"
        }

        let substantive = substantiveBodyText(chosenText)
        let boilerplateStub = substantive.isEmpty
        let nonEmpty = !chosenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let imageOnly = (unloadedHtmlImages > 0 && substantive.count < 150) || (nonEmpty && boilerplateStub)

        return ParsedEmlx(
            messageId: cleanMsgId?.isEmpty == true ? nil : cleanMsgId,
            from: parsedFrom,
            subject: decodedSubject,
            plainText: chosenText,
            attachments: attachments,
            hasListUnsubscribe: hasListUnsub,
            hasListId: hasListId,
            isReply: isReply,
            isAutoSubmitted: isAuto,
            to: parsedTo,
            dateHeader: dateHeader,
            unloadedHtmlImages: unloadedHtmlImages,
            bodyRepresentation: bodyRepresentation,
            isBoilerplateStub: boilerplateStub,
            bodyIsImageOnly: imageOnly,
            isPartial: isPartial,
            isTruncated: sliced.isTruncated,
            plistFlags: plistFlags,
            plistMetadata: plistMetadata,
            htmlBody: resolvedHtml,
            hasRemoteImages: hasRemoteImages
        )
    }

    // MARK: - Byte-level .emlx framing & MIME splitting

    private struct SlicedEmlxPayload {
        let mimePayload: Data
        let trailingPlist: Data
        let isTruncated: Bool
    }

    private static func sliceMimePayload(from data: Data) -> SlicedEmlxPayload {
        guard !data.isEmpty else {
            return SlicedEmlxPayload(mimePayload: data, trailingPlist: Data(), isTruncated: false)
        }
        // 第 1 行若是十进制整数，代表紧随其后的 MIME 原文字节数
        let maxHeaderScan = data.index(data.startIndex, offsetBy: min(data.count, 32))
        if let newlineIdx = data[data.startIndex..<maxHeaderScan].firstIndex(of: UInt8(ascii: "\n")) {
            var lineEnd = newlineIdx
            if lineEnd > data.startIndex && data[data.index(before: lineEnd)] == UInt8(ascii: "\r") {
                lineEnd = data.index(before: lineEnd)
            }
            if let numStr = String(data: data[data.startIndex..<lineEnd], encoding: .ascii)?.trimmingCharacters(in: .whitespaces),
               let byteCount = Int(numStr), byteCount >= 0 {
                let mimeStart = data.index(after: newlineIdx)
                let available = data.distance(from: mimeStart, to: data.endIndex)
                if available < byteCount {
                    return SlicedEmlxPayload(
                        mimePayload: Data(data[mimeStart..<data.endIndex]),
                        trailingPlist: Data(),
                        isTruncated: true
                    )
                }
                let mimeEnd = data.index(mimeStart, offsetBy: byteCount)
                return SlicedEmlxPayload(
                    mimePayload: Data(data[mimeStart..<mimeEnd]),
                    trailingPlist: Data(data[mimeEnd..<data.endIndex]),
                    isTruncated: false
                )
            }
        }
        return SlicedEmlxPayload(mimePayload: data, trailingPlist: Data(), isTruncated: false)
    }

    private static func parseTrailingPlist(_ data: Data) -> (flags: Int?, metadata: [String: PlistMetadataValue]) {
        guard !data.isEmpty else { return (nil, [:]) }
        // Trim leading/trailing ASCII whitespace so trailing newlines don't affect parsing.
        guard let firstNonWS = data.firstIndex(where: { !isAsciiWhitespace($0) }),
              let lastNonWS = data.lastIndex(where: { !isAsciiWhitespace($0) }),
              firstNonWS <= lastNonWS else {
            return (nil, [:])
        }
        let trimmed = Data(data[firstNonWS...lastNonWS])
        guard let rawPlist = try? PropertyListSerialization.propertyList(from: trimmed, options: [], format: nil),
              let dict = rawPlist as? [String: Any] else {
            return (nil, [:])
        }
        var metadata: [String: PlistMetadataValue] = [:]
        metadata.reserveCapacity(dict.count)
        for (key, value) in dict {
            if let converted = convertPlistValue(value) {
                metadata[key] = converted
            }
        }
        let flags: Int?
        if case .int(let rawFlags) = metadata["flags"] {
            flags = Int(exactly: rawFlags)
        } else {
            flags = nil
        }
        return (flags, metadata)
    }

    private static func isAsciiWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
    }

    private static func convertPlistValue(_ value: Any) -> PlistMetadataValue? {
        if let str = value as? String {
            return .string(str)
        }
        if let date = value as? Date {
            return .date(date)
        }
        if let data = value as? Data {
            return .data(data)
        }
        if let num = value as? NSNumber {
            if CFGetTypeID(num) == CFBooleanGetTypeID() {
                return .bool(num.boolValue)
            }
            if CFNumberIsFloatType(num) {
                return .double(num.doubleValue)
            }
            return .int(num.int64Value)
        }
        if let arr = value as? [Any] {
            return .array(arr.compactMap(convertPlistValue))
        }
        if let dict = value as? [String: Any] {
            var out: [String: PlistMetadataValue] = [:]
            for (k, v) in dict {
                if let converted = convertPlistValue(v) {
                    out[k] = converted
                }
            }
            return .dictionary(out)
        }
        return nil
    }

    private static func splitHeadersAndBody(_ data: Data) -> ([String: [String]], Data) {
        var splitOffset: Int? = nil
        var separatorLen = 0
        data.withUnsafeBytes { rawBuf in
            guard let bytes = rawBuf.bindMemory(to: UInt8.self).baseAddress else { return }
            let count = rawBuf.count
            var i = 0
            while i + 1 < count {
                if bytes[i] == 13 && i + 3 < count && bytes[i + 1] == 10 && bytes[i + 2] == 13 && bytes[i + 3] == 10 {
                    splitOffset = i
                    separatorLen = 4
                    break
                }
                if bytes[i] == 10 && bytes[i + 1] == 10 {
                    splitOffset = i
                    separatorLen = 2
                    break
                }
                i += 1
            }
        }

        let headerData: Data
        let bodyData: Data
        if let offset = splitOffset {
            let s = data.startIndex + offset
            headerData = Data(data[..<s])
            bodyData = Data(data[(s + separatorLen)...])
        } else {
            headerData = data
            bodyData = Data()
        }

        let headerText = String(data: headerData, encoding: .isoLatin1) ?? String(decoding: headerData, as: UTF8.self)
        return (parseHeaderLines(headerText), bodyData)
    }

    private static func parseHeaderLines(_ rawHeaderBlock: String) -> [String: [String]] {
        let normalized = rawHeaderBlock.replacingOccurrences(of: "\r\n", with: "\n")
        var unfolded: [String] = []
        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            if let first = line.first, (first == " " || first == "\t"), !unfolded.isEmpty {
                unfolded[unfolded.count - 1] += " " + line.trimmingCharacters(in: .whitespaces)
            } else {
                unfolded.append(String(line))
            }
        }

        var map: [String: [String]] = [:]
        for line in unfolded {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let val = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            map[name, default: []].append(val)
        }
        return map
    }

    // MARK: - Multipart & Part Decoding

    private static func walkPart(
        headers: [String: [String]],
        body: Data,
        plainCandidates: inout [String],
        htmlCandidates: inout [String],
        attachments: inout [Attachment],
        inlineCidImages: inout [String: String]
    ) {
        let contentTypeRaw = headers["content-type"]?.first ?? "text/plain; charset=utf-8"
        let (mimeType, ctParams) = parseHeaderParams(contentTypeRaw)
        let dispRaw = headers["content-disposition"]?.first ?? ""
        let (dispType, dispParams) = parseHeaderParams(dispRaw)
        let transferEncoding = (headers["content-transfer-encoding"]?.first ?? "7bit")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if mimeType.hasPrefix("multipart/") {
            if let boundary = ctParams["boundary"], !boundary.isEmpty {
                let subparts = splitMultipart(body: body, boundary: boundary)
                for sub in subparts {
                    let (subHeaders, subBody) = splitHeadersAndBody(sub)
                    walkPart(
                        headers: subHeaders,
                        body: subBody,
                        plainCandidates: &plainCandidates,
                        htmlCandidates: &htmlCandidates,
                        attachments: &attachments,
                        inlineCidImages: &inlineCidImages
                    )
                }
            }
            return
        }

        // Capture inline Content-ID images (`cid:...`) as data: URIs for native HTML rendering
        let rawContentId = headers["content-id"]?.first
        let cleanContentId = (extractAngleToken(rawContentId) ?? rawContentId?.trimmingCharacters(in: .whitespacesAndNewlines))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let cid = cleanContentId, !cid.isEmpty, mimeType.hasPrefix("image/") {
            let decodedImg = decodeTransfer(body: body, encoding: transferEncoding)
            if !decodedImg.isEmpty && decodedImg.count <= 8 * 1024 * 1024 {
                let dataURI = "data:\(mimeType);base64,\(decodedImg.base64EncodedString())"
                inlineCidImages[cid.lowercased()] = dataURI
            }
            if dispType == "inline" || dispType.isEmpty {
                return
            }
        }

        let filename = resolveFilename(dispParams: dispParams, ctParams: ctParams)
        let isExplicitAttachment = dispType == "attachment"
            || (filename != nil && dispType != "inline" && !mimeType.hasPrefix("text/"))
            || (filename != nil && !mimeType.hasPrefix("text/") && !mimeType.hasPrefix("image/"))

        if isExplicitAttachment || (filename != nil && !mimeType.hasPrefix("text/")) {
            let decodedBytes = approxDecodedByteCount(body: body, transferEncoding: transferEncoding, declaredSize: dispParams["size"])
            let attName = filename ?? "附件"
            attachments.append(
                Attachment(
                    name: attName,
                    size: Attachment.formatBytes(decodedBytes),
                    kind: AttachmentKind.infer(filename: attName, mimeType: mimeType)
                )
            )
            return
        }

        if mimeType == "text/plain" || mimeType == "text/html" {
            let decodedData = decodeTransfer(body: body, encoding: transferEncoding)
            let text = decodeCharset(data: decodedData, charset: ctParams["charset"])
            if mimeType == "text/plain" {
                plainCandidates.append(text)
            } else {
                htmlCandidates.append(text)
            }
        }
    }

    private static let cidReferenceRegex: NSRegularExpression = {
        // Matches cid:token inside HTML attributes or CSS url(cid:...)
        try! NSRegularExpression(pattern: #"cid:([^"'\s)>]+)"#, options: [.caseInsensitive])
    }()

    private static let remoteImageResourceRegex: NSRegularExpression = {
        // Detects remote http(s) images, picture sources, or CSS background-image URLs
        let pattern = #"(?:<img\b[^>]*\b(?:src|srcset)\s*=\s*["']?\s*https?://|<source\b[^>]*\bsrcset\s*=\s*["']?\s*https?://|background(?:-image)?\s*[:=]\s*[^;>]*https?://)"#
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    public static func resolveInlineCidReferences(in html: String, cidMap: [String: String]) -> String {
        guard !cidMap.isEmpty else { return html }
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = cidReferenceRegex.matches(in: html, options: [], range: nsRange)
        guard !matches.isEmpty else { return html }

        var result = html
        for match in matches.reversed() {
            guard match.numberOfRanges >= 2,
                  let fullRange = Range(match.range(at: 0), in: result),
                  let tokenRange = Range(match.range(at: 1), in: result) else {
                continue
            }
            let rawToken = String(result[tokenRange])
            let decodedToken = (rawToken.removingPercentEncoding ?? rawToken).lowercased()
            if let dataURI = cidMap[decodedToken] ?? cidMap[rawToken.lowercased()] {
                result.replaceSubrange(fullRange, with: dataURI)
            }
        }
        return result
    }

    public static func containsRemoteImageResources(_ html: String) -> Bool {
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        return remoteImageResourceRegex.firstMatch(in: html, options: [], range: nsRange) != nil
    }

    private static func splitMultipart(body: Data, boundary: String) -> [Data] {
        guard let marker = "--\(boundary)".data(using: .utf8), !marker.isEmpty else { return [] }
        var parts: [Data] = []
        var searchRange = body.startIndex..<body.endIndex
        var currentPartStart: Data.Index? = nil

        while let found = body.range(of: marker, options: [], in: searchRange) {
            if let start = currentPartStart {
                var end = found.lowerBound
                if end > start && body[body.index(before: end)] == UInt8(ascii: "\n") {
                    end = body.index(before: end)
                    if end > start && body[body.index(before: end)] == UInt8(ascii: "\r") {
                        end = body.index(before: end)
                    }
                }
                if start < end {
                    parts.append(Data(body[start..<end]))
                }
            }

            var afterMarker = found.upperBound
            // Check `--` closing boundary
            if afterMarker + 2 <= body.endIndex,
               body[afterMarker] == UInt8(ascii: "-"),
               body[afterMarker + 1] == UInt8(ascii: "-") {
                break
            }
            // Skip trailing spaces and CRLF/LF on boundary line
            while afterMarker < body.endIndex && (body[afterMarker] == UInt8(ascii: " ") || body[afterMarker] == UInt8(ascii: "\t")) {
                afterMarker += 1
            }
            if afterMarker < body.endIndex && body[afterMarker] == UInt8(ascii: "\r") {
                afterMarker += 1
            }
            if afterMarker < body.endIndex && body[afterMarker] == UInt8(ascii: "\n") {
                afterMarker += 1
            }

            currentPartStart = afterMarker
            searchRange = afterMarker..<body.endIndex
        }
        return parts
    }

    private static func approxDecodedByteCount(body: Data, transferEncoding: String, declaredSize: String?) -> Int {
        if let s = declaredSize, let n = Int(s), n > 0 { return n }
        if transferEncoding == "base64" {
            return max(1, (body.count * 3) / 4)
        }
        return max(1, body.count)
    }

    private static func decodeTransfer(body: Data, encoding: String) -> Data {
        switch encoding {
        case "base64":
            if let decoded = Data(base64Encoded: body, options: [.ignoreUnknownCharacters]) {
                return decoded
            }
            return body
        case "quoted-printable":
            return decodeQuotedPrintable(body, underscoreAsSpace: false)
        default:
            return body
        }
    }

    private static func decodeQuotedPrintable(_ data: Data, underscoreAsSpace: Bool) -> Data {
        var out = Data()
        out.reserveCapacity(data.count)
        data.withUnsafeBytes { rawBuf in
            guard let bytes = rawBuf.bindMemory(to: UInt8.self).baseAddress else { return }
            let count = rawBuf.count
            var i = 0
            while i < count {
                let b = bytes[i]
                if underscoreAsSpace && b == UInt8(ascii: "_") {
                    out.append(UInt8(ascii: " "))
                    i += 1
                } else if b == UInt8(ascii: "=") {
                    if i + 1 < count && bytes[i + 1] == UInt8(ascii: "\n") {
                        i += 2
                        continue
                    }
                    if i + 2 < count && bytes[i + 1] == UInt8(ascii: "\r") && bytes[i + 2] == UInt8(ascii: "\n") {
                        i += 3
                        continue
                    }
                    if i + 2 < count,
                       let hi = hexVal(bytes[i + 1]),
                       let lo = hexVal(bytes[i + 2]) {
                        out.append((hi << 4) | lo)
                        i += 3
                        continue
                    }
                    out.append(b)
                    i += 1
                } else {
                    out.append(b)
                    i += 1
                }
            }
        }
        return out
    }

    private static func hexVal(_ byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return byte - UInt8(ascii: "0")
        case UInt8(ascii: "A")...UInt8(ascii: "F"): return byte - UInt8(ascii: "A") + 10
        case UInt8(ascii: "a")...UInt8(ascii: "f"): return byte - UInt8(ascii: "a") + 10
        default: return nil
        }
    }

    // MARK: - Charset & RFC 2047 / 2231 Decoding

    public static func decodeCharset(data: Data, charset: String?) -> String {
        guard !data.isEmpty else { return "" }
        if let cs = charset?.trimmingCharacters(in: CharacterSet(charactersIn: "\"' ")).lowercased(), !cs.isEmpty {
            if cs == "utf-8" || cs == "utf8" {
                return String(decoding: data, as: UTF8.self)
            }
            let cfEnc = CFStringConvertIANACharSetNameToEncoding(cs as CFString)
            if cfEnc != kCFStringEncodingInvalidId {
                let nsEnc = CFStringConvertEncodingToNSStringEncoding(cfEnc)
                if let str = String(data: data, encoding: String.Encoding(rawValue: nsEnc)) {
                    return str
                }
            }
            // GB2312 邮件正文中常夹带 GBK/GB18030 扩展字符，使用 GB18030 超集兜底
            if cs.contains("gb") {
                let gb18030 = CFStringConvertEncodingToNSStringEncoding(
                    CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
                )
                if let str = String(data: data, encoding: String.Encoding(rawValue: gb18030)) {
                    return str
                }
            }
        }
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        let gb18030 = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
        if let gb = String(data: data, encoding: String.Encoding(rawValue: gb18030)) {
            return gb
        }
        return String(data: data, encoding: .isoLatin1) ?? String(decoding: data, as: UTF8.self)
    }

    public static func decodeRFC2047(_ input: String) -> String {
        guard input.contains("=?") else { return input }
        let pattern = #"=\?([^?]+)\?([bBqQ])\?([^?]*)\?="#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return input }
        let ns = input as NSString
        let matches = regex.matches(in: input, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return input }

        var result = ""
        var cursor = 0
        var pendingCharset: String? = nil
        var pendingBytes = Data()

        func flushPending() {
            guard !pendingBytes.isEmpty else { return }
            result += decodeCharset(data: pendingBytes, charset: pendingCharset)
            pendingBytes.removeAll(keepingCapacity: true)
            pendingCharset = nil
        }

        for match in matches {
            let betweenRange = NSRange(location: cursor, length: match.range.location - cursor)
            let between = ns.substring(with: betweenRange)
            if !pendingBytes.isEmpty {
                if !between.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    flushPending()
                    result += between
                }
            } else {
                result += between
            }

            let charset = ns.substring(with: match.range(at: 1)).lowercased()
            let mode = ns.substring(with: match.range(at: 2)).lowercased()
            let payload = ns.substring(with: match.range(at: 3))

            let chunk: Data
            if mode == "b" {
                chunk = Data(base64Encoded: payload, options: [.ignoreUnknownCharacters]) ?? Data(payload.utf8)
            } else {
                chunk = decodeQuotedPrintable(Data(payload.utf8), underscoreAsSpace: true)
            }

            if let curCs = pendingCharset, curCs != charset {
                flushPending()
            }
            pendingCharset = charset
            pendingBytes.append(chunk)
            cursor = match.range.location + match.range.length
        }

        flushPending()
        if cursor < ns.length {
            result += ns.substring(from: cursor)
        }
        return result
    }

    private static func parseHeaderParams(_ headerValue: String) -> (String, [String: String]) {
        let segments = headerValue.split(separator: ";", omittingEmptySubsequences: true)
        guard let first = segments.first else { return ("", [:]) }
        let mainType = first.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var params: [String: String] = [:]
        for seg in segments.dropFirst() {
            guard let eq = seg.firstIndex(of: "=") else { continue }
            let key = seg[..<eq].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            var val = seg[seg.index(after: eq)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if val.hasPrefix("\"") && val.hasSuffix("\"") && val.count >= 2 {
                val.removeFirst()
                val.removeLast()
            }
            params[key] = val
        }
        return (mainType, params)
    }

    private static func resolveFilename(dispParams: [String: String], ctParams: [String: String]) -> String? {
        if let star = dispParams["filename*"] ?? ctParams["name*"] {
            return decodeRFC2231(star)
        }
        if let raw = dispParams["filename"] ?? ctParams["name"], !raw.isEmpty {
            return decodeRFC2047(raw)
        }
        // RFC 2231 continuations: filename*0 / filename*1
        let continuations = dispParams
            .filter { $0.key.hasPrefix("filename*") }
            .sorted { $0.key < $1.key }
        if !continuations.isEmpty {
            let combined = continuations.map(\.value).joined()
            return decodeRFC2231(combined)
        }
        return nil
    }

    private static func decodeRFC2231(_ value: String) -> String {
        if let firstQuote = value.firstIndex(of: "'"),
           let secondQuote = value[value.index(after: firstQuote)...].firstIndex(of: "'") {
            let charset = String(value[..<firstQuote])
            let encoded = String(value[value.index(after: secondQuote)...])
            if let unescaped = encoded.removingPercentEncoding {
                return unescaped
            }
            let bytes = percentDecodeBytes(encoded)
            return decodeCharset(data: bytes, charset: charset)
        }
        return decodeRFC2047(value.removingPercentEncoding ?? value)
    }

    private static func percentDecodeBytes(_ s: String) -> Data {
        var out = Data()
        let utf8 = Array(s.utf8)
        var i = 0
        while i < utf8.count {
            if utf8[i] == UInt8(ascii: "%"), i + 2 < utf8.count,
               let hi = hexVal(utf8[i + 1]), let lo = hexVal(utf8[i + 2]) {
                out.append((hi << 4) | lo)
                i += 3
            } else {
                out.append(utf8[i])
                i += 1
            }
        }
        return out
    }

    public static func parseAddressHeader(_ raw: String) -> Sender {
        let decoded = decodeRFC2047(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        if let lt = decoded.lastIndex(of: "<"),
           let gt = decoded[lt...].firstIndex(of: ">"),
           lt < gt {
            let addr = decoded[decoded.index(after: lt)..<gt].trimmingCharacters(in: .whitespacesAndNewlines)
            var name = decoded[..<lt].trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'"))
            if name.isEmpty {
                name = addr.components(separatedBy: "@").first ?? addr
            }
            return Sender(name: name, address: addr)
        }
        let clean = decoded.trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'<>"))
        let local = clean.components(separatedBy: "@").first ?? clean
        return Sender(name: local.isEmpty ? "未知发件人" : local, address: clean)
    }

    public static func parseAddressList(_ raw: String) -> [Sender] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var segments: [String] = []
        var current = ""
        var inQuotes = false
        var escaped = false
        var angleDepth = 0

        for ch in trimmed {
            if escaped {
                current.append(ch)
                escaped = false
                continue
            }
            if ch == "\\" && inQuotes {
                current.append(ch)
                escaped = true
                continue
            }
            if ch == "\"" {
                inQuotes.toggle()
                current.append(ch)
                continue
            }
            if !inQuotes {
                if ch == "<" {
                    angleDepth += 1
                } else if ch == ">" && angleDepth > 0 {
                    angleDepth -= 1
                } else if ch == "," && angleDepth == 0 {
                    segments.append(current)
                    current.removeAll(keepingCapacity: true)
                    continue
                }
            }
            current.append(ch)
        }
        if !current.isEmpty {
            segments.append(current)
        }

        return segments.compactMap { seg in
            let part = seg.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !part.isEmpty else { return nil }
            let sender = parseAddressHeader(part)
            return sender.address.isEmpty ? nil : sender
        }
    }

    private static func extractAngleToken(_ raw: String?) -> String? {
        guard let raw else { return nil }
        if let lt = raw.firstIndex(of: "<"),
           let gt = raw[lt...].firstIndex(of: ">"),
           lt < gt {
            return String(raw[raw.index(after: lt)..<gt]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    // MARK: - Deterministic HTML -> Plain Text (Background-Thread Safe)

    public static func htmlToPlainText(_ html: String) -> String {
        extractHtmlText(html).text
    }

    public static func extractHtmlText(_ html: String) -> (text: String, imageCount: Int) {
        var s = html
        // Remove comments and hidden blocks (script, style, head, noscript, svg, title)
        let blockRemovals = [
            #"<!--[\s\S]*?-->"#,
            #"(?is)<(script|style|head|noscript|svg|title)(?=\s|>|/)[^>]*>[\s\S]*?</\1>"#,
            // Guard against truncated HTML leaving an unclosed <script>/<style>/<noscript>/<svg>/<title>
            #"(?is)<(script|style|noscript|svg|title)(?=\s|>|/)[^>]*>[\s\S]*$"#
        ]
        for pat in blockRemovals {
            s = s.replacingOccurrences(of: pat, with: "", options: .regularExpression)
        }

        // Count <img> tags and preserve non-empty alt attributes as [image alt: <alt>]
        var imageCount = 0
        if let imgRegex = try? NSRegularExpression(pattern: #"(?is)<img(?=\s|>|/)((?:[^>"']|"[^"]*"|'[^']*')*)>"#) {
            let altRegex = try? NSRegularExpression(pattern: #"(?is)(?:^|\s)alt\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))"#)
            let ns = s as NSString
            let matches = imgRegex.matches(in: s, range: NSRange(location: 0, length: ns.length))
            imageCount = matches.count
            if !matches.isEmpty {
                let mutable = NSMutableString(string: s)
                for match in matches.reversed() {
                    let attrs = match.range(at: 1).location != NSNotFound ? ns.substring(with: match.range(at: 1)) : ""
                    var replacement = ""
                    if let altRegex {
                        let attrsNS = attrs as NSString
                        if let altMatch = altRegex.firstMatch(in: attrs, range: NSRange(location: 0, length: attrsNS.length)) {
                            let rawAlt: String
                            if altMatch.range(at: 1).location != NSNotFound {
                                rawAlt = attrsNS.substring(with: altMatch.range(at: 1))
                            } else if altMatch.range(at: 2).location != NSNotFound {
                                rawAlt = attrsNS.substring(with: altMatch.range(at: 2))
                            } else if altMatch.range(at: 3).location != NSNotFound {
                                rawAlt = attrsNS.substring(with: altMatch.range(at: 3))
                            } else {
                                rawAlt = ""
                            }
                            let decodedCheck = stripInvisibleFiller(decodeHTMLEntities(rawAlt))
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            if !decodedCheck.isEmpty {
                                let safeAlt = rawAlt
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                    .replacingOccurrences(of: "<", with: "&lt;")
                                replacement = " [image alt: \(safeAlt)] "
                            }
                        }
                    }
                    mutable.replaceCharacters(in: match.range, with: replacement)
                }
                s = mutable as String
            }
        }

        // Convert list items and line/block breaks
        s = s.replacingOccurrences(of: #"(?i)<li[^>]*>"#, with: "\n• ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(
            of: #"(?i)</?(p|div|tr|table|section|article|header|footer|blockquote|h[1-6]|ul|ol|hr)[^>]*>"#,
            with: "\n",
            options: .regularExpression
        )
        s = s.replacingOccurrences(of: #"(?i)</td\s*>"#, with: "  ", options: .regularExpression)
        // Strip remaining tags
        s = s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        return (decodeHTMLEntities(s), imageCount)
    }

    private static func decodeHTMLEntities(_ input: String) -> String {
        guard input.contains("&") else { return input }
        var s = input
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#160;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&mdash;", with: "—")
            .replacingOccurrences(of: "&ndash;", with: "–")
            .replacingOccurrences(of: "&bull;", with: "•")
            .replacingOccurrences(of: "&copy;", with: "©")
            .replacingOccurrences(of: "&shy;", with: "\u{00AD}")
            .replacingOccurrences(of: "&zwnj;", with: "")
            .replacingOccurrences(of: "&zwj;", with: "")

        if let numRegex = try? NSRegularExpression(pattern: #"&#(x?[0-9a-fA-F]+);"#) {
            let ns = s as NSString
            let matches = numRegex.matches(in: s, range: NSRange(location: 0, length: ns.length)).reversed()
            for m in matches {
                let codeStr = ns.substring(with: m.range(at: 1))
                let scalarVal: UInt32?
                if codeStr.lowercased().hasPrefix("x") {
                    scalarVal = UInt32(codeStr.dropFirst(), radix: 16)
                } else {
                    scalarVal = UInt32(codeStr, radix: 10)
                }
                if let v = scalarVal, let scalar = UnicodeScalar(v) {
                    s = (s as NSString).replacingCharacters(in: m.range, with: String(scalar))
                }
            }
        }
        return s
    }

    // MARK: - Body Cleaning & Boilerplate Detection (personal-v6 semantics)

    private static func isInvisibleFiller(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x00AD, // Soft hyphen
             0x034F, // Combining grapheme joiner
             0x2007, // Figure space
             0x200B...0x200F, // ZWSP..RLM
             0x202A...0x202E, // LRE..RLO
             0x2060...0x206F, // Word joiner..Nominal digit shapes
             0xFEFF: // BOM / ZWNBSP
            return true
        default:
            return false
        }
    }

    private static func stripInvisibleFiller(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.reserveCapacity(text.unicodeScalars.count)
        for scalar in text.unicodeScalars where !isInvisibleFiller(scalar) {
            scalars.append(scalar)
        }
        return String(scalars)
    }

    /// Strips invisible Unicode filler characters (`INVISIBLE_FILLER_RE`) and collapses excessive blank lines (`clean_body_text`).
    public static func cleanBodyText(_ text: String) -> String {
        let cleaned = stripInvisibleFiller(text)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return cleaned.replacingOccurrences(
            of: "\n[ \t\u{00A0}]*\n(?:[ \t\u{00A0}]*\n)+",
            with: "\n\n",
            options: .regularExpression
        )
    }

    private static let boilerplatePattern =
        #"\[image alt:[^\]]*\]|https?://\S+|(?:如不想收到此类邮件[,，\s]*点击退订|点击退订|退订|unsubscribe|privacy policy|view in browser|online version)"#

    private static func substantiveBodyText(_ body: String) -> String {
        let cleaned = cleanBodyText(body)
        let withoutBoilerplate = cleaned.replacingOccurrences(
            of: boilerplatePattern,
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        return withoutBoilerplate.replacingOccurrences(
            of: #"[\s|.,;:!?()<>—\-_/\\]+"#,
            with: "",
            options: .regularExpression
        )
    }

    public static func isBoilerplateStub(_ body: String) -> Bool {
        substantiveBodyText(body).isEmpty
    }

    public static func normalizePlainText(_ text: String) -> String {
        let unix = cleanBodyText(text)
            .replacingOccurrences(of: "\u{00A0}", with: " ")

        var cleanedLines: [String] = []
        var blankRun = 0
        for rawLine in unix.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.replacingOccurrences(of: #"[ \t]+$"#, with: "", options: .regularExpression)
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                blankRun += 1
                if blankRun <= 1 && !cleanedLines.isEmpty {
                    cleanedLines.append("")
                }
            } else {
                blankRun = 0
                cleanedLines.append(line)
            }
        }
        while cleanedLines.last == "" {
            cleanedLines.removeLast()
        }
        return cleanedLines.joined(separator: "\n").precomposedStringWithCanonicalMapping
    }
}
