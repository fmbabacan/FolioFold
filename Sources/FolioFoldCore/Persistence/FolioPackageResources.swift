import Foundation

extension FolioPackageStore {
    static func packageResources(
        from document: FolioDocument,
        into packageURL: URL
    ) throws -> FolioDocument {
        var packaged = document
        if !document.assets.isEmpty {
            let assetsDirectory = packageURL.appendingPathComponent("assets", isDirectory: true)
            try FileManager.default.createDirectory(
                at: assetsDirectory,
                withIntermediateDirectories: true
            )
            packaged.assets = try document.assets.enumerated().map { index, asset in
                let source = URL(fileURLWithPath: asset.path)
                let fileName = "\(index)-\(source.lastPathComponent)"
                let relativePath = "assets/\(fileName)"
                let data = try Data(contentsOf: source)
                try data.write(
                    to: assetsDirectory.appendingPathComponent(fileName),
                    options: .atomic
                )
                return FolioAsset(
                    path: relativePath,
                    mediaType: asset.mediaType,
                    checksum: digest(data)
                )
            }
        }

        if let sourcePDF = document.sourcePDF {
            let source = URL(fileURLWithPath: sourcePDF.path)
            let sourceDirectory = packageURL.appendingPathComponent("source", isDirectory: true)
            try FileManager.default.createDirectory(
                at: sourceDirectory,
                withIntermediateDirectories: true
            )
            let data = try Data(contentsOf: source)
            try data.write(
                to: sourceDirectory.appendingPathComponent("original.pdf"),
                options: .atomic
            )
            packaged.sourcePDF = SourcePDFInfo(
                path: "source/original.pdf",
                checksum: digest(data),
                pageCount: sourcePDF.pageCount
            )
        }
        return packaged
    }

    static func verifyResources(in document: FolioDocument, packageURL: URL) throws {
        for asset in document.assets {
            let resourceURL = try safeURL(for: asset.path, in: packageURL)
            guard let data = try? Data(contentsOf: resourceURL),
                  digest(data) == asset.checksum else {
                throw FolioPackageError.invalidPackage
            }
        }
        if let sourcePDF = document.sourcePDF {
            let resourceURL = try safeURL(for: sourcePDF.path, in: packageURL)
            guard let data = try? Data(contentsOf: resourceURL),
                  digest(data) == sourcePDF.checksum else {
                throw FolioPackageError.invalidPackage
            }
        }
    }

    static func safeURL(for path: String, in packageURL: URL) throws -> URL {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.split(separator: "/").contains("..") else {
            throw FolioPackageError.invalidPackage
        }
        let root = packageURL.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = packageURL.appendingPathComponent(path).standardizedFileURL
        if (try? candidate.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            throw FolioPackageError.invalidPackage
        }
        let resolved = candidate.resolvingSymlinksInPath()
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard resolved.path.hasPrefix(rootPrefix) else {
            throw FolioPackageError.invalidPackage
        }
        return resolved
    }

}
