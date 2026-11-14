import Foundation
import Testing
@testable import MailroomCore

@Suite("EmlxParser Preprocessing Hardening Tests")
struct EmlxPreprocessingTests {
    @Test("Strips all INVISIBLE_FILLER_RE scalars and collapses excessive blank lines")
    func invisibleFillersAndBlankLines() {
        let fillers = [
            "\u{00AD}", // soft hyphen
            "\u{034F}", // combining grapheme joiner
            "\u{2007}", // figure space
            "\u{200B}", "\u{200C}", "\u{200D}", "\u{200E}", "\u{200F}",
            "\u{202A}", "\u{202B}", "\u{202C}", "\u{202D}", "\u{202E}",
            "\u{2060}", "\u{2066}", "\u{2069}", "\u{206F}",
            "\u{FEFF}"
        ].joined()

        let raw = "Hello\(fillers)World\r\n \u{00A0} \r\n\t\r\n\r\nNext paragraph"
        let cleaned = EmlxParser.cleanBodyText(raw)
        #expect(cleaned == "HelloWorld\n\nNext paragraph")

        let normalized = EmlxParser.normalizePlainText("\r\n\r\n" + raw + "\r\n\r\n")
        #expect(normalized == "HelloWorld\n\nNext paragraph")
    }

    @Test("Extracts HTML text with image count, alt preservation, and hidden block removal")
    func htmlImageAltAndHiddenBlocks() {
        let html = """
        <html>
        <head>
            <title>Hidden Title</title>
            <style>.hidden { display: none; }</style>
            <script>var x = "<img src='ignored.png' alt='IgnoreMe'>";</script>
        </head>
        <body>
            <!-- <img src="commented.png" alt="CommentedOut"> -->
            <header><p>Header Greeting</p></header>
            <p>First line <img src="https://cdn.example.com/a.png" alt="Hero &amp; Banner"></p>
            <p>Second line <img src='https://cdn.example.com/pixel.gif' alt=''></p>
            <p>Third line <img src="https://cdn.example.com/b.png" alt="50% > Off" /></p>
            <p>Fourth line <img src="https://cdn.example.com/c.png" alt="&nbsp;"></p>
            <p>Fifth line <img src="https://cdn.example.com/d.png" alt=UnquotedAlt></p>
        </body>
        </html>
        """

        let extracted = EmlxParser.extractHtmlText(html)
        #expect(extracted.imageCount == 5)
        #expect(!extracted.text.contains("Hidden Title"))
        #expect(!extracted.text.contains("display: none"))
        #expect(!extracted.text.contains("IgnoreMe"))
        #expect(!extracted.text.contains("CommentedOut"))
        #expect(extracted.text.contains("Header Greeting"))
        #expect(extracted.text.contains("[image alt: Hero & Banner]"))
        #expect(extracted.text.contains("[image alt: 50% > Off]"))
        #expect(extracted.text.contains("[image alt: UnquotedAlt]"))
        #expect(!extracted.text.contains("[image alt: ]"))
    }

    @Test("Tracks bodyRepresentation for plain, html, and empty bodies")
    func bodyRepresentations() {
        let plainMime = """
        From: Alice <alice@example.com>\r
        Subject: Plain\r
        Content-Type: multipart/alternative; boundary="B1"\r
        \r
        --B1\r
        Content-Type: text/plain; charset="utf-8"\r
        \r
        Plain text body\r
        --B1\r
        Content-Type: text/html; charset="utf-8"\r
        \r
        <p>HTML body <img src="x.png" alt="Pic"></p>\r
        --B1--\r
        """
        let plainParsed = EmlxParser.parse(data: Data(plainMime.utf8))
        #expect(plainParsed.bodyRepresentation == "full_plain_text")
        #expect(plainParsed.unloadedHtmlImages == 0)
        #expect(plainParsed.plainText == "Plain text body")

        let htmlFallbackMime = """
        From: Alice <alice@example.com>\r
        Subject: HTML Fallback\r
        Content-Type: multipart/alternative; boundary="B2"\r
        \r
        --B2\r
        Content-Type: text/plain; charset="utf-8"\r
        \r
           \u{200B}  \r
        --B2\r
        Content-Type: text/html; charset="utf-8"\r
        \r
        <p>Welcome <img src="hero.png" alt="Hero"></p>\r
        --B2--\r
        """
        let htmlParsed = EmlxParser.parse(data: Data(htmlFallbackMime.utf8))
        #expect(htmlParsed.bodyRepresentation == "text_extracted_from_full_html_with_image_alt")
        #expect(htmlParsed.unloadedHtmlImages == 1)
        #expect(htmlParsed.plainText.contains("Welcome"))
        #expect(htmlParsed.plainText.contains("[image alt: Hero]"))

        let imageOnlyNoAltMime = """
        From: Promo <promo@example.com>\r
        Subject: Banner\r
        Content-Type: text/html; charset="utf-8"\r
        \r
        <html><body><img src="banner.jpg"></body></html>\r
        """
        let noAltParsed = EmlxParser.parse(data: Data(imageOnlyNoAltMime.utf8))
        #expect(noAltParsed.bodyRepresentation == "empty")
        #expect(noAltParsed.unloadedHtmlImages == 1)
        #expect(noAltParsed.plainText.isEmpty)
        #expect(noAltParsed.bodyIsImageOnly == true)
    }

    @Test("Detects boilerplate stubs and image-only bodies matching personal-v6")
    func boilerplateAndImageOnlyDetection() {
        #expect(EmlxParser.isBoilerplateStub("Unsubscribe | Privacy Policy | View in browser | Online version"))
        #expect(EmlxParser.isBoilerplateStub("如不想收到此类邮件，点击退订 https://example.com/unsub [image alt: Logo]"))
        #expect(!EmlxParser.isBoilerplateStub("Meeting moved to 3pm tomorrow. Unsubscribe"))

        let stubMime = """
        From: Brand <news@example.com>\r
        Subject: Newsletter\r
        Content-Type: text/plain; charset="utf-8"\r
        \r
        View in browser: https://example.com/view | Privacy Policy | Click to Unsubscribe\r
        """
        let stubParsed = EmlxParser.parse(data: Data(stubMime.utf8))
        #expect(stubParsed.isBoilerplateStub == false) // "Click to" remains substantive
        #expect(stubParsed.bodyIsImageOnly == false)

        let pureBoilerplateMime = """
        From: Brand <news@example.com>\r
        Subject: Newsletter\r
        Content-Type: text/plain; charset="utf-8"\r
        \r
        View in browser | https://example.com/view | Privacy Policy | Unsubscribe\r
        """
        let pureStub = EmlxParser.parse(data: Data(pureBoilerplateMime.utf8))
        #expect(pureStub.isBoilerplateStub == true)
        #expect(pureStub.bodyIsImageOnly == true)

        let shortWithImagesAndLongUrl = """
        From: Brand <news@example.com>\r
        Subject: Sale\r
        Content-Type: text/html; charset="utf-8"\r
        \r
        <p><img src="a.jpg" alt="Big Promotional Hero Image With Long Alt Text"></p>
        <p>Shop today! https://tracking.example.com/very/long/url/with/many/query/params?a=1234567890&b=abcdefghij&c=klmnopqrstuvwxyz</p>
        """
        let shortImgParsed = EmlxParser.parse(data: Data(shortWithImagesAndLongUrl.utf8))
        #expect(shortImgParsed.unloadedHtmlImages == 1)
        #expect(shortImgParsed.isBoilerplateStub == false)
        #expect(shortImgParsed.bodyIsImageOnly == true)

        let longProse = String(repeating: "Detailed project update and quarterly engineering notes. ", count: 5)
        let richHtml = """
        From: Team <team@example.com>\r
        Subject: Update\r
        Content-Type: text/html; charset="utf-8"\r
        \r
        <p><img src="logo.png" alt="Logo"></p><p>\(longProse)</p>
        """
        let richParsed = EmlxParser.parse(data: Data(richHtml.utf8))
        #expect(richParsed.unloadedHtmlImages == 1)
        #expect(richParsed.isBoilerplateStub == false)
        #expect(richParsed.bodyIsImageOnly == false)

        let completelyEmptyMime = """
        From: Empty <empty@example.com>\r
        Subject: Empty\r
        Content-Type: text/plain; charset="utf-8"\r
        \r
        \r
        """
        let emptyParsed = EmlxParser.parse(data: Data(completelyEmptyMime.utf8))
        #expect(emptyParsed.bodyRepresentation == "empty")
        #expect(emptyParsed.isBoilerplateStub == true)
        #expect(emptyParsed.bodyIsImageOnly == false)
    }

    @Test("Detects .partial.emlx, truncated byte counts, and parses trailing Apple Mail XML plist")
    func partialTruncatedAndPlist() throws {
        let mime = """
        Message-ID: <partial-42@example.com>\r
        From: Sender <sender@example.com>\r
        Subject: Partial Mail\r
        Content-Type: text/plain; charset="utf-8"\r
        \r
        First chunk available locally.\r
        """
        let mimeBytes = Data(mime.utf8)
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>conversation-id</key>
            <integer>987654</integer>
            <key>flags</key>
            <integer>8590195713</integer>
            <key>remote-id</key>
            <string>4201</string>
            <key>is-junk</key>
            <false/>
        </dict>
        </plist>
        """

        var emlx = Data("\(mimeBytes.count)\n".utf8)
        emlx.append(mimeBytes)
        emlx.append(Data(plist.utf8))

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("emlx-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let partialURL = tempDir.appendingPathComponent("42.partial.emlx")
        try emlx.write(to: partialURL)

        let partialParsed = try EmlxParser.parseFile(at: partialURL)
        #expect(partialParsed.isPartial == true)
        #expect(partialParsed.isTruncated == false)
        #expect(partialParsed.plistFlags == 8_590_195_713)
        #expect(partialParsed.plistMetadata["conversation-id"] == .int(987_654))
        #expect(partialParsed.plistMetadata["remote-id"] == .string("4201"))
        #expect(partialParsed.plistMetadata["is-junk"] == .bool(false))

        let fullURL = tempDir.appendingPathComponent("42.emlx")
        try emlx.write(to: fullURL)
        let fullParsed = try EmlxParser.parseFile(at: fullURL)
        #expect(fullParsed.isPartial == false)
        #expect(fullParsed.isTruncated == false)
        #expect(fullParsed.plistFlags == 8_590_195_713)

        // Truncated payload: declared byte count exceeds available bytes
        var truncatedEmlx = Data("\(mimeBytes.count + 500)\n".utf8)
        truncatedEmlx.append(mimeBytes)
        let truncatedParsed = EmlxParser.parse(data: truncatedEmlx)
        #expect(truncatedParsed.isTruncated == true)
        #expect(truncatedParsed.plistFlags == nil)
        #expect(truncatedParsed.plistMetadata.isEmpty)
        #expect(truncatedParsed.plainText == "First chunk available locally.")

        // Corrupted trailing plist should not crash or fail parsing
        var badPlistEmlx = Data("\(mimeBytes.count)\n".utf8)
        badPlistEmlx.append(mimeBytes)
        badPlistEmlx.append(Data("<plist><broken".utf8))
        let badPlistParsed = EmlxParser.parse(data: badPlistEmlx)
        #expect(badPlistParsed.isTruncated == false)
        #expect(badPlistParsed.plistFlags == nil)
        #expect(badPlistParsed.plistMetadata.isEmpty)
        #expect(badPlistParsed.plainText == "First chunk available locally.")
    }

    @Test("Extracts multiple To recipients (including quoted commas & RFC2047) and Date header")
    func toRecipientsAndDateHeader() {
        let mime = """
        Message-ID: <hdr-1@example.com>\r
        From: =?UTF-8?B?5byg5LiJ?= <zhang@example.com>\r
        To: "Doe, Jane" <jane@example.com>, =?UTF-8?B?5p2O5Zub?= <li@example.com>, ops@example.com\r
        To: audit@example.com\r
        Date: Fri, 13 Nov 2026 10:15:30 +0800\r
        Subject: Multi-recipient check\r
        Content-Type: text/plain; charset="utf-8"\r
        \r
        Hello team.\r
        """
        let parsed = EmlxParser.parse(data: Data(mime.utf8))
        #expect(parsed.to.count == 4)
        #expect(parsed.to[0] == Sender(name: "Doe, Jane", address: "jane@example.com"))
        #expect(parsed.to[1] == Sender(name: "李四", address: "li@example.com"))
        #expect(parsed.to[2] == Sender(name: "ops", address: "ops@example.com"))
        #expect(parsed.to[3] == Sender(name: "audit", address: "audit@example.com"))
        #expect(parsed.dateHeader == "Fri, 13 Nov 2026 10:15:30 +0800")

        // Backwards-compatible legacy init keeps compiling with defaulted new parameters
        let legacy = ParsedEmlx(
            messageId: "id",
            from: nil,
            subject: nil,
            plainText: "",
            attachments: [],
            hasListUnsubscribe: false,
            hasListId: false,
            isReply: false,
            isAutoSubmitted: false
        )
        #expect(legacy.to.isEmpty)
        #expect(legacy.dateHeader == nil)
        #expect(legacy.bodyRepresentation == "empty")
    }

    @Test("Resolves inline cid: images to data URIs, detects remote images, and falls back from boilerplate plain-text stubs")
    func richHtmlCidResolutionRemoteImagesAndBoilerplateFallback() {
        // 1x1 PNG base64
        let pngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        let mimeWithCidAndStubPlain = """
        Message-ID: <rich-cid-1@example.com>\r
        From: Design Weekly <newsletter@example.com>\r
        Subject: Issue #48\r
        MIME-Version: 1.0\r
        Content-Type: multipart/related; boundary="rel-bound"\r
        \r
        --rel-bound\r
        Content-Type: multipart/alternative; boundary="alt-bound"\r
        \r
        --alt-bound\r
        Content-Type: text/plain; charset="utf-8"\r
        \r
        View in browser: https://example.com/view/48\r
        Unsubscribe: https://example.com/unsub\r
        --alt-bound\r
        Content-Type: text/html; charset="utf-8"\r
        \r
        <html><body><h1>Design Systems in Swift</h1><p>Full article body rendered with inline diagram and remote hero.</p><img src="cid:diagram-01@example.com" alt="Architecture Diagram"><img src="https://cdn.example.com/pixel.gif" width="1" height="1"></body></html>\r
        --alt-bound--\r
        --rel-bound\r
        Content-Type: image/png; name="diagram.png"\r
        Content-Transfer-Encoding: base64\r
        Content-ID: <diagram-01@example.com>\r
        Content-Disposition: inline; filename="diagram.png"\r
        \r
        \(pngBase64)\r
        --rel-bound--\r
        """

        let parsed = EmlxParser.parse(data: Data(mimeWithCidAndStubPlain.utf8))
        let html = parsed.htmlBody ?? ""
        #expect(html.contains("data:image/png;base64,\(pngBase64)"))
        #expect(!html.contains("cid:diagram-01@example.com"))
        #expect(parsed.hasRemoteImages == true)
        // Inline cid image should not appear as a separate downloadable file attachment
        #expect(parsed.attachments.isEmpty)
        // Stub plain-text ("View in browser / Unsubscribe") should fall back to substantive HTML text
        #expect(parsed.plainText.contains("Design Systems in Swift"))
        #expect(parsed.plainText.contains("Full article body rendered with inline diagram"))
        #expect(parsed.bodyRepresentation == "text_extracted_from_full_html_with_image_alt")

        // HTML with only inline data URI and no http(s) image should report hasRemoteImages == false
        let localOnlyMime = """
        From: Colleague <colleague@example.com>\r
        Subject: Local screenshot\r
        MIME-Version: 1.0\r
        Content-Type: multipart/related; boundary="b1"\r
        \r
        --b1\r
        Content-Type: text/html; charset="utf-8"\r
        \r
        <div><p>Here is the chart:</p><img src='cid:chart99'></div>\r
        --b1\r
        Content-Type: image/png\r
        Content-Transfer-Encoding: base64\r
        Content-ID: <chart99>\r
        \r
        \(pngBase64)\r
        --b1--\r
        """
        let localParsed = EmlxParser.parse(data: Data(localOnlyMime.utf8))
        #expect(localParsed.htmlBody?.contains("data:image/png;base64,") == true)
        #expect(localParsed.hasRemoteImages == false)
    }
}
