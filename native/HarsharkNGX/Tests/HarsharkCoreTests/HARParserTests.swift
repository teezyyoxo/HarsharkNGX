import Foundation
import Testing
@testable import HarsharkCore

struct HARParserTests {
    @Test func emptyArchiveIsValid() throws {
        let archive = try HARParser().parse(Data(#"{"log":{"entries":[]}}"#.utf8))
        #expect(archive.entries.isEmpty)
    }

    @Test(arguments: ["{}", "null", "[]", #"{"log":null}"#, #"{"log":{"entries":null}}"#])
    func rejectsNonHARStructures(json: String) {
        #expect(throws: HARImportError.self) {
            try HARParser().parse(Data(json.utf8))
        }
    }

    @Test func reportsInvalidEntryPath() {
        #expect(throws: HARImportError.invalidStructure(path: "log.entries[0].response", expected: "an object")) {
            try HARParser().parse(Data(#"{"log":{"entries":[{"request":{},"response":null}]}}"#.utf8))
        }
    }

    @Test func rejectsMalformedJSON() {
        #expect(throws: HARImportError.invalidJSON) {
            try HARParser().parse(Data("{broken".utf8))
        }
    }

    @Test func preservesSourceAndExporterFields() throws {
        let source = Data(#"{"log":{"_capture":"custom","entries":[{"request":{"url":"https://example.test/a","method":"POST","httpVersion":"HTTP/2"},"response":{"status":200,"content":{"text":"{}","mimeType":"application/json"}},"time":-1,"_custom":{"secret":"retained"}}]}}"#.utf8)
        let sessionID = UUID()
        let archive = try HARParser().parse(source, sessionID: sessionID)
        let entry = try #require(archive.entries.first)
        #expect(archive.source == source)
        #expect(entry.id == HAREntryID(sessionID: sessionID, ordinal: 0))
        #expect(entry.httpVersion == "HTTP/2")
        #expect(entry.status == 200)
        #expect(entry.durationMilliseconds == nil)
        #expect(entry.raw["_custom"]?.object?["secret"]?.string == "retained")
        #expect(entry.responseBody.presentation() == .text("{}"))
    }

    @Test func identitiesAreStableWithinSessionAndDistinctAcrossSessions() throws {
        let data = Data(#"{"log":{"entries":[{"request":{},"response":{}},{"request":{},"response":{}}]}}"#.utf8)
        let first = try HARParser().parse(data)
        let reload = try HARParser().parse(data, sessionID: first.sessionID)
        let other = try HARParser().parse(data)
        #expect(first.entries.map(\.id) == reload.entries.map(\.id))
        #expect(first.entries[0].id != first.entries[1].id)
        #expect(first.entries[0].id != other.entries[0].id)
    }

    @Test func oversizedInputHasExplicitLimitError() {
        let input = Data(repeating: 32, count: HARParser.maximumInputBytes + 1)
        #expect(throws: HARImportError.inputTooLarge(limit: HARParser.maximumInputBytes)) {
            try HARParser().parse(input)
        }
    }

    @Test func readsFileAndReleasesHandle() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".har")
        defer { try? FileManager.default.removeItem(at: url) }
        let data = Data(#"{"log":{"entries":[]}}"#.utf8)
        try data.write(to: url)
        #expect(try HARParser().read(from: url).source == data)
    }

    @Test func cancelledImportDoesNotPublishArchive() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try HARParser().parse(Data(#"{"log":{"entries":[]}}"#.utf8))
        }
        do {
            _ = try await task.value
            Issue.record("A cancelled parser must not produce an archive")
        } catch {
            #expect(error is CancellationError)
        }
    }
}
