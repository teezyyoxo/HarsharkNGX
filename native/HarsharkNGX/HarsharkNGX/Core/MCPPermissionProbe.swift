import Foundation

/// Checks only HarsharkNGX data. This is an effective-access check, not a query of TCC.
nonisolated public enum MCPPermissionProbe {
    public enum Status: String, Sendable {
        case granted, denied, unavailable, invalidSettings
    }

    public static let markerName = ".mcp-permission-probe"
    private static let marker = Data("HarsharkNGX permission check v1\n".utf8)

    public static func prepare(in directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let url = directory.appendingPathComponent(markerName)
        try marker.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public static func check(in directory: URL) -> Status {
        do {
            guard try Data(contentsOf: directory.appendingPathComponent(markerName)) == marker else {
                return .unavailable
            }
            _ = try MCPAccessControl(sessionDirectory: directory).read()
            return .granted
        } catch {
            let error = error as NSError
            if error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoPermissionError {
                return .denied
            }
            if error.domain == NSPOSIXErrorDomain && [Int(EACCES), Int(EPERM)].contains(error.code) {
                return .denied
            }
            if error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
                return .unavailable
            }
            return .invalidSettings
        }
    }

    public static func notificationName(token: String) -> Notification.Name {
        Notification.Name("com.teezyyoxo.HarsharkNGX.permission.\(token)")
    }

    public static func stopNotificationName(token: String) -> Notification.Name {
        Notification.Name("com.teezyyoxo.HarsharkNGX.permission.stop.\(token)")
    }
}
