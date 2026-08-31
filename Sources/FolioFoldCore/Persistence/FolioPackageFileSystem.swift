import Foundation

extension FolioPackageStore {
    static func replace(_ destination: URL, with temporary: URL) throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: destination.path) else {
            try manager.moveItem(at: temporary, to: destination)
            return
        }
        _ = try manager.replaceItemAt(
            destination,
            withItemAt: temporary,
            backupItemName: nil,
            options: []
        )
    }

    static func recoveryURL(for packageURL: URL) -> URL {
        packageURL.deletingLastPathComponent()
            .appendingPathComponent(packageURL.lastPathComponent + recoverySuffix)
    }
}
