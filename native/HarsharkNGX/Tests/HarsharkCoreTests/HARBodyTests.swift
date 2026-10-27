import Foundation
import Testing
@testable import HarsharkCore

struct HARBodyTests {
    private func body(_ fields: [String: JSONValue]) -> HARBody {
        HARBody(blob: .object(fields))
    }

    private func encoded(_ bytes: Data, mime: String = "text/plain") -> HARBody {
        body(["text": .string(bytes.base64EncodedString()), "encoding": .string("base64"), "mimeType": .string(mime)])
    }

    @Test func missingNullAndEmptyRemainDistinct() {
        #expect(HARBody(blob: nil).capture == .missing)
        #expect(body([:]).presentation() == .missing)
        #expect(body(["text": .null]).capture == .null)
        #expect(body(["text": .string("")]).presentation() == .empty)
        #expect(body(["text": .string(" \n")]).presentation() == .text(" \n"))
        #expect(body(["size": .number(0)]).presentation() == .missing)
    }

    @Test func parameterOnlyRequestDoesNotInventBody() {
        let parameters: JSONValue = .array([.object(["name": .string("a"), "value": .string("b")])])
        let value = body(["params": parameters])
        #expect(value.parameters == parameters)
        #expect(value.presentation() == .missing)
    }

    @Test func malformedMetadataIsExplicit() {
        #expect(body(["text": .number(42)]).capture == .malformed("Body text is not a string."))
        #expect(body(["text": .string("abc"), "encoding": .bool(true)]).capture == .malformed("Body encoding is not a string."))
    }

    @Test func base64IsLazyAndStrict() {
        let value = body(["text": .string("aGVsbG8="), "encoding": .string("base64")])
        #expect(value.capture == .encoded("aGVsbG8=", encoding: "base64"))
        #expect(value.presentation() == .text("hello"))
        #expect(body(["text": .string("!!!!"), "encoding": .string("base64")]).presentation() == .malformed("Body contains invalid base64."))
        #expect(body(["text": .string("aGVs\nbG8=\r\n"), "encoding": .string("base64")]).presentation() == .text("hello"))
        #expect(body(["text": .string(""), "encoding": .string("base64")]).presentation() == .empty)
    }

    @Test func unknownEncodingIsNotShownAsDecodedText() {
        #expect(body(["text": .string("abc"), "encoding": .string("gzip")]).presentation() == .unsupported("Unsupported HAR body encoding: gzip."))
    }

    @Test func unicodeTextIsNotReinterpretedUsingHTTPCharset() {
        #expect(body(["text": .string("café"), "mimeType": .string("text/plain; charset=us-ascii")]).presentation() == .text("café"))
    }

    @Test func utf16IsDecodedBeforeBinaryHeuristics() {
        #expect(encoded(Data([0xFF, 0xFE, 0x48, 0, 0x69, 0])).presentation() == .text("Hi"))
        #expect(encoded(Data([0x48, 0, 0x69, 0]), mime: "text/plain; charset=\"UTF-16LE\"").presentation() == .text("Hi"))
    }

    @Test func charsetErrorsAndBinaryAreExplicit() {
        #expect(encoded(Data([0x63, 0x61, 0x66, 0xE9]), mime: "text/plain; charset=iso-8859-1").presentation() == .text("café"))
        #expect(encoded(Data([0xFF]), mime: "text/plain; charset=utf-8").presentation() == .malformed("Body bytes are invalid for the selected character encoding."))
        #expect(encoded(Data([65]), mime: "text/plain; charset=unknown").presentation() == .unsupported("Unsupported character encoding: unknown."))
        #expect(encoded(Data([0, 1, 2]), mime: "image/png").presentation() == .binary(byteCount: 3, mimeType: "image/png"))
    }

    @Test func malformedJSONBodyIsPreserved() {
        #expect(body(["text": .string("{broken"), "mimeType": .string("application/json")]).presentation() == .text("{broken"))
    }

    @Test func previewLimitDoesNotDiscardCapture() {
        let value = body(["text": .string("hello")])
        #expect(value.presentation(maximumEncodedBytes: 4) == .unavailable("Body exceeds the current preview limit; original content is retained."))
        #expect(value.capture == .text("hello"))
        #expect(value.presentation(maximumEncodedBytes: 5) == .text("hello"))
    }
}
