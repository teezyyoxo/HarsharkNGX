import Foundation
import Testing
@testable import HarsharkCore

struct MCPPermissionProbeTests {
    @Test func missingProbeNeverReportsPermissionGranted() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        #expect(MCPPermissionProbe.check(in: directory) == .unavailable)
    }

    @Test func probeTracksSettingsFailureAndRecoveryWithoutChangingAccess() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try MCPPermissionProbe.prepare(in: directory)
        #expect(MCPPermissionProbe.check(in: directory) == .granted)
        let access = MCPAccessControl(sessionDirectory: directory)
        try access.setEnabled(false)
        let disabled = try access.read()
        #expect(MCPPermissionProbe.check(in: directory) == .granted)
        #expect(try access.read() == disabled)
        try Data("invalid settings".utf8).write(to: directory.appendingPathComponent(".mcp-access.json"))
        #expect(MCPPermissionProbe.check(in: directory) == .invalidSettings)
        try access.setEnabled(true)
        #expect(MCPPermissionProbe.check(in: directory) == .granted)
        try Data("wrong marker".utf8).write(to: directory.appendingPathComponent(MCPPermissionProbe.markerName))
        #expect(MCPPermissionProbe.check(in: directory) == .unavailable)
    }
}
