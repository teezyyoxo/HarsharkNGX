import Foundation

nonisolated public enum HARBodyCapture: Sendable, Equatable {
    case missing
    case null
    case empty
    case text(String)
    case encoded(String, encoding: String)
    case deferred(HARTextReference, encoding: String?)
    case malformed(String)
}

nonisolated public enum HARBodyPresentation: Sendable, Equatable {
    case text(String)
    case empty
    case missing
    case unavailable(String)
    case unsupported(String)
    case malformed(String)
    case binary(byteCount: Int, mimeType: String?)
}

nonisolated public struct HARBody: Sendable {
    public let capture: HARBodyCapture
    public let mimeType: String?
    public let declaredSize: Double?
    public let parameters: JSONValue?

    public init(blob: JSONValue?) {
        let object = blob?.object
        mimeType = object?["mimeType"]?.string
        declaredSize = object?["size"]?.number
        parameters = object?["params"]
        guard let blob else {
            capture = .missing
            return
        }
        guard case .object = blob else {
            capture = blob == .null ? .null : .malformed("Body metadata is not an object.")
            return
        }
        guard let textValue = object?["text"] else {
            capture = .missing
            return
        }
        if case .deferredString(let reference) = textValue {
            if let encodingValue = object?["encoding"], encodingValue.string == nil {
                capture = .malformed("Body encoding is not a string.")
            } else {
                capture = .deferred(reference, encoding: object?["encoding"]?.string)
            }
            return
        }
        guard let text = textValue.string else {
            capture = textValue == .null ? .null : .malformed("Body text is not a string.")
            return
        }
        if let encodingValue = object?["encoding"], encodingValue.string == nil {
            capture = .malformed("Body encoding is not a string.")
            return
        }
        let encoding = object?["encoding"]?.string?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if !encoding.isEmpty {
            capture = .encoded(text, encoding: encoding)
        } else {
            capture = text.isEmpty ? .empty : .text(text)
        }
    }

    /// Resolves only on demand. Limits avoid allocating a decoded copy of an oversized payload.
    public func presentation(maximumEncodedBytes: Int = 2 * 1_048_576) -> HARBodyPresentation {
        switch capture {
        case .deferred(let reference, let encoding):
            guard reference.byteCount <= max(0, maximumEncodedBytes) else {
                return .unavailable("Body exceeds the current preview limit; use Export Body to save the complete payload.")
            }
            do {
                let text = try reference.text()
                var object: [String: JSONValue] = ["text": .string(text)]
                if let encoding { object["encoding"] = .string(encoding) }
                if let mimeType { object["mimeType"] = .string(mimeType) }
                return HARBody(blob: .object(object)).presentation(maximumEncodedBytes: maximumEncodedBytes)
            } catch { return .malformed("Captured body text could not be decoded.") }
        case .missing: return .missing
        case .null: return .unavailable("The capture explicitly contains null body text or metadata.")
        case .empty: return .empty
        case .malformed(let reason): return .malformed(reason)
        case .text(let text):
            guard text.utf8.count <= max(0, maximumEncodedBytes) else {
                return .unavailable("Body exceeds the current preview limit; original content is retained.")
            }
            // HAR text is already Unicode; an HTTP charset must not be applied to it again.
            return .text(text)
        case .encoded(let text, let encoding):
            guard encoding == "base64" else {
                return .unsupported("Unsupported HAR body encoding: \(encoding).")
            }
            guard text.utf8.count <= max(0, maximumEncodedBytes) else {
                return .unavailable("Encoded body exceeds the current preview limit; original content is retained.")
            }
            // Permit ASCII layout whitespace, but never discard arbitrary invalid base64 characters.
            let normalized = text.utf8.filter { ![UInt8(9), 10, 13, 32].contains($0) }
            guard let bytes = Data(base64Encoded: Data(normalized)) else {
                return .malformed("Body contains invalid base64.")
            }
            guard !bytes.isEmpty else { return .empty }
            return decode(bytes)
        }
    }

    private func decode(_ bytes: Data) -> HARBodyPresentation {
        let mediaType = mimeType?.split(separator: ";", maxSplits: 1).first?
            .trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        let binaryPrefixes = ["image/", "audio/", "video/", "font/"]
        if binaryPrefixes.contains(where: mediaType.hasPrefix)
            || ["application/octet-stream", "application/pdf", "application/protobuf"].contains(mediaType) {
            return .binary(byteCount: bytes.count, mimeType: mimeType)
        }

        let encoding: String.Encoding
        if bytes.starts(with: [0xFF, 0xFE]) || bytes.starts(with: [0xFE, 0xFF]) {
            encoding = .utf16
        } else if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            guard let value = String(data: bytes.dropFirst(3), encoding: .utf8) else {
                return .malformed("Body is not valid UTF-8.")
            }
            return .text(value)
        } else if let charset {
            switch charset {
            case "utf-8", "utf8": encoding = .utf8
            case "utf-16", "utf16": encoding = .utf16
            case "utf-16le": encoding = .utf16LittleEndian
            case "utf-16be": encoding = .utf16BigEndian
            case "iso-8859-1", "latin1": encoding = .isoLatin1
            case "windows-1252": encoding = .windowsCP1252
            case "us-ascii", "ascii": encoding = .ascii
            default: return .unsupported("Unsupported character encoding: \(charset).")
            }
        } else {
            if bytes.prefix(8192).contains(0) {
                return .binary(byteCount: bytes.count, mimeType: mimeType)
            }
            encoding = .utf8
        }
        guard let text = String(data: bytes, encoding: encoding) else {
            return .malformed("Body bytes are invalid for the selected character encoding.")
        }
        return .text(text)
    }

    private var charset: String? {
        for parameter in (mimeType ?? "").split(separator: ";").dropFirst() {
            let pair = parameter.split(separator: "=", maxSplits: 1)
            if pair.count == 2, pair[0].trimmingCharacters(in: .whitespaces).lowercased() == "charset" {
                return pair[1].trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'")).lowercased()
            }
        }
        return nil
    }
}
