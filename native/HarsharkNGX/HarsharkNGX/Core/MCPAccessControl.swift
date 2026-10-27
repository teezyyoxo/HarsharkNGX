import Foundation

/// Shared by the sandboxed app and client-launched stdio servers.
nonisolated public struct MCPAccessControl: Sendable {
    public struct State: Codable, Equatable, Sendable {
        public let enabled: Bool
        public let revision: UUID?
    }

    private let directory: URL

    public init(sessionDirectory: URL) {
        directory = sessionDirectory
    }

    public func read() throws -> State {
        let url = directory.appendingPathComponent(".mcp-access.json")
        do {
            return try JSONDecoder().decode(State.self, from: Data(contentsOf: url))
        } catch CocoaError.fileReadNoSuchFile {
            // Preserve existing client access until the user chooses a setting.
            return State(enabled: true, revision: nil)
        }
    }

    public func setEnabled(_ enabled: Bool) throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let state = State(enabled: enabled, revision: UUID())
        let url = directory.appendingPathComponent(".mcp-access.json")
        try JSONEncoder().encode(state).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
