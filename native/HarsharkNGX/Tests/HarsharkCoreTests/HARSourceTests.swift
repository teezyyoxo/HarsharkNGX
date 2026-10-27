import Foundation
import Testing
@testable import HarsharkCore

struct HARSourceTests {
    @Test func fileImportDefersBodiesAndSurvivesOriginalReplacement() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".har")
        defer { try? FileManager.default.removeItem(at: url) }
        let original = Data(#"{"log":{"entries":[{"request":{},"response":{"content":{"text":"hello 🌊\nworld","mimeType":"text/plain"}}}]}}"#.utf8)
        try original.write(to: url)
        let archive = try HARParser().read(from: url)
        let entry = try #require(archive.entries.first)
        guard case .deferred = entry.responseBody.capture else {
            Issue.record("File-backed body was eagerly decoded")
            return
        }
        try Data("changed".utf8).write(to: url)
        #expect(entry.responseBody.presentation() == .text("hello 🌊\nworld"))
        #expect(archive.source == original)
    }

    @Test(arguments: [#""\uD83C\uDF0A""#, #""a\"b\\c""#, #"[null,true,false,-1.23e+2]"#, #"{"a":[{"b":"utf8 café"}]}"#])
    func scannerMatchesFoundation(json: String) throws {
        let data = Data(json.utf8)
        let scanned = try HARJSONScanner(source: HARSource(data: data)).parse()
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(scanned == decoded)
    }

    @Test(arguments: [#""\uD800""#, #""\uDC00""#, #""\x00""#, "[1,]", "{\"a\":1,}", "true false", "01", "[", "{\"a\":}"])
    func scannerRejectsInvalidJSON(json: String) {
        #expect(throws: (any Error).self) {
            try HARJSONScanner(source: HARSource(data: Data(json.utf8))).parse()
        }
    }

    @Test func scannerRejectsInvalidUTF8InsideDeferredBody() {
        var data = Data(#"{"text":""#.utf8)
        data.append(contentsOf: [0xC0, 0x80])
        data.append(contentsOf: [34, 125])
        #expect(throws: (any Error).self) { try HARJSONScanner(source: HARSource(data: data)).parse() }
    }

    @Test func importsFileBeyondReferenceParserLimitWithoutDecodingBody() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".har")
        defer { try? FileManager.default.removeItem(at: url) }
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        try handle.write(contentsOf: Data(#"{"log":{"entries":[{"request":{},"response":{"content":{"text":""#.utf8))
        let chunk = Data(repeating: 65, count: 1_048_576)
        for _ in 0..<33 { try handle.write(contentsOf: chunk) }
        try handle.write(contentsOf: Data(#""}}}]}}"#.utf8))
        try handle.close()
        let archive = try HARParser().read(from: url)
        let entry = try #require(archive.entries.first)
        guard case .deferred(let reference, _) = entry.responseBody.capture else {
            Issue.record("Large body was eagerly decoded")
            return
        }
        #expect(reference.byteCount == 33 * 1_048_576 + 2)
        guard case .unavailable = entry.responseBody.presentation() else {
            Issue.record("Oversized body should have an explicit preview limit")
            return
        }
    }
}
