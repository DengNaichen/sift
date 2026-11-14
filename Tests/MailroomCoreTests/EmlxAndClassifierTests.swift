import Foundation
import Testing
@testable import MailroomCore

@Suite("EmlxParser & RuleBasedClassifier Tests")
struct EmlxAndClassifierTests {
    @Test("Parses .emlx byte-count framing, RFC2047 UTF-8 chunks, HTML body and PDF attachment")
    func parseSyntheticEmlx() {
        let mime = """
        Message-ID: <test-991@studio-north.cn>\r
        From: =?UTF-8?B?5ZGo5b6L5biI?= <zhou@hengzhi.com>\r
        Subject: =?UTF-8?B?44CQ5b6F56Gu6K6k44CRMjAyNyDlkIjlkIw=?=\r
        List-Unsubscribe: <mailto:unsub@hengzhi.com>\r
        Content-Type: multipart/mixed; boundary="BOUND_1"\r
        \r
        --BOUND_1\r
        Content-Type: text/html; charset="utf-8"\r
        Content-Transfer-Encoding: quoted-printable\r
        \r
        <html><head><style>body{color:red}</style></head><body><p>您好，</p><p>请于本周五前回复确认合同签署。</p></body></html>\r
        --BOUND_1\r
        Content-Type: application/pdf; name="contract_v3.pdf"\r
        Content-Disposition: attachment; filename="contract_v3.pdf"; size=1258291\r
        Content-Transfer-Encoding: base64\r
        \r
        JVBERi0xLjQK\r
        --BOUND_1--\r

        """
        let mimeBytes = Data(mime.utf8)
        var emlx = Data("\(mimeBytes.count)\n".utf8)
        emlx.append(mimeBytes)
        emlx.append(Data("<?xml version=\"1.0\"?><plist><dict></dict></plist>".utf8))

        let parsed = EmlxParser.parse(data: emlx)
        #expect(parsed.messageId == "test-991@studio-north.cn")
        #expect(parsed.from?.name == "周律师")
        #expect(parsed.from?.address == "zhou@hengzhi.com")
        #expect(parsed.subject == "【待确认】2027 合同")
        #expect(parsed.hasListUnsubscribe == true)
        #expect(parsed.plainText.contains("请于本周五前回复确认合同签署。"))
        #expect(!parsed.plainText.contains("color:red"))
        #expect(parsed.attachments.count == 1)
        #expect(parsed.attachments.first?.kind == .pdf)
        #expect(parsed.attachments.first?.size == "1.2 MB")

        let content = MailContent(
            id: MessageId(parsed.messageId!),
            from: parsed.from!,
            account: MockSeedData.workAccount,
            subject: parsed.subject!,
            receivedAt: Date(),
            plainText: parsed.plainText,
            attachments: parsed.attachments
        )
        let outcome = RuleBasedClassifier().classify(
            RawMailSignals(content: content, hasListUnsubscribe: parsed.hasListUnsubscribe)
        )
        if case .triage(let meta) = outcome {
            #expect(meta.kind == .contract)
            #expect(meta.evidence != nil)
            #expect(content.plainText.contains(meta.evidence!))
        } else {
            Issue.record("Expected contract triage override despite List-Unsubscribe")
        }
    }
}
