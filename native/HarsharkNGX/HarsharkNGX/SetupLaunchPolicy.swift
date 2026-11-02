import Foundation

enum SetupLaunchPolicy {
    /// Registered defaults are not evidence of an existing installation.
    static func beginLaunch(defaults: UserDefaults, domain: String, configurationDirectory: URL) -> Bool {
        let preferencesExist = !(defaults.persistentDomain(forName: domain) ?? [:]).isEmpty
        var configurationExists = false
        if FileManager.default.fileExists(atPath: configurationDirectory.path) {
            let files = FileManager.default.enumerator(at: configurationDirectory,
                includingPropertiesForKeys: [.isDirectoryKey], errorHandler: { _, _ in
                    configurationExists = true // Treat unreadable existing data as configured.
                    return false
                })
            while let url = files?.nextObject() as? URL {
                if url.lastPathComponent != ".DS_Store",
                   (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true {
                    configurationExists = true
                    break
                }
            }
        }
        let firstLaunch = !preferencesExist && !configurationExists
        defaults.set(true, forKey: "hasLaunchedBefore")
        return firstLaunch
    }
}
