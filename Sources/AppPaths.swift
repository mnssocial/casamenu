import Foundation

/// Public bundle resources and private per-user state have separate lifecycles.
enum AppPaths {
    static var support: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("CasaMenu", isDirectory: true)
    }
    static var bridgeRoots: [URL] {
        [Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/HomeKit"),
         support.appendingPathComponent("HomeKit"),
         Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("HomeKit")]
    }
    static var storageFolders: [URL] {
        [support.appendingPathComponent("homebridge-data")] + bridgeRoots.map { $0.appendingPathComponent(".state") }
    }
    static func bridgeFile(_ name: String) -> URL? {
        bridgeRoots.map { $0.appendingPathComponent(name) }.first { FileManager.default.fileExists(atPath: $0.path) }
    }
    static var node: URL? {
        let explicit = ProcessInfo.processInfo.environment["CASAMENU_NODE"].map { URL(fileURLWithPath: $0) }
        let candidates = bridgeRoots.map { $0.appendingPathComponent("runtime/bin/node") } +
            [explicit, URL(fileURLWithPath: "/opt/homebrew/bin/node"), URL(fileURLWithPath: "/usr/local/bin/node")].compactMap { $0 }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
