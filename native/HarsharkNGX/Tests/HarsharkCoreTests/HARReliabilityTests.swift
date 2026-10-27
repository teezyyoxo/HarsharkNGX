import Foundation
import Testing
@testable import HarsharkCore

struct HARReliabilityTests {
    @Test func redactedSummaryOmitsSecretsAndDoesNotAlterOriginal() throws {
        let source = Data(#"{"log":{"entries":[{"request":{"method":"POST","url":"https://user:password@example.test/private?token=secret#secret","headers":[{"name":"Authorization","value":"secret"}],"cookies":[{"name":"session","value":"secret"}],"postData":{"text":"secret"}},"response":{"status":200,"content":{"text":"secret","size":6,"mimeType":"text/plain"},"_private":"secret"},"_token":"secret","time":12}]}}"#.utf8)
        let archive = try HARParser().parse(source)
        let data = try HARSanitizer.summaryData(archive)
        let text = String(decoding: data, as: UTF8.self)
        for secret in ["secret", "password", "private", "Authorization", "_token"] {
            #expect(!text.contains(secret))
        }
        let exported = try HARParser().parse(data)
        #expect(exported.entries.first?.url == "https://example.test")
        #expect(exported.entries.first?.responseBody.capture == .missing)
        #expect(archive.source == source)
        #expect(archive.entries.first?.responseBody.presentation() == .text("secret"))
    }

    @Test func previewLimitDoesNotHideARecoverableBody() {
        let body = HARBody(blob: .object(["text": .string("{\"ok\":true}")]))
        let limited = HARFormatter.bodyDetail(body, pretty: true, maximumBodyBytes: 2)
        #expect(limited.text.isEmpty)
        #expect(!limited.notice.isEmpty)
        let full = HARFormatter.bodyDetail(body, pretty: true, maximumBodyBytes: 1024)
        #expect(full.text.contains("true"))
        #expect(full.syntax == "json")
    }

    @Test func mappedSourceLivesUntilLastBodyReferenceIsReleased() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".har")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"log":{"entries":[{"request":{},"response":{"content":{"text":"marker"}}}]}}"#.utf8).write(to: url)
        var archive: HARArchive? = try HARParser().read(from: url)
        weak var backing = archive?.backing
        var body: HARBody? = archive?.entries.first?.responseBody
        archive = nil
        #expect(backing != nil)
        #expect(body?.presentation() == .text("marker"))
        body = nil
        #expect(backing == nil)
    }
}
