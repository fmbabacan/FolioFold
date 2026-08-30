import CommonCrypto
import CryptoKit
import Foundation

public struct FolioPackageManifest: Codable, Equatable, Sendable {
    public struct Encryption: Codable, Equatable, Sendable {
        public var algorithm: String
        public var keyDerivation: String
        public var derivationVersion: Int
        public var iterations: Int
        public var salt: Data
        public var passwordVerifier: Data?

        public init(
            algorithm: String = "AES-256-GCM",
            keyDerivation: String = "PBKDF2-HMAC-SHA256",
            derivationVersion: Int = 2,
            iterations: Int = 200_000,
            salt: Data,
            passwordVerifier: Data? = nil
        ) {
            self.algorithm = algorithm
            self.keyDerivation = keyDerivation
            self.derivationVersion = derivationVersion
            self.iterations = iterations
            self.salt = salt
            self.passwordVerifier = passwordVerifier
        }
    }

    public var formatVersion: FormatVersion
    public var documentPath: String
    public var documentChecksum: String?
    public var encryption: Encryption?

    public init(
        formatVersion: FormatVersion,
        documentPath: String,
        documentChecksum: String? = nil,
        encryption: Encryption? = nil
    ) {
        self.formatVersion = formatVersion
        self.documentPath = documentPath
        self.documentChecksum = documentChecksum
        self.encryption = encryption
    }
}

public enum FolioPackageError: Error, Equatable {
    case invalidPackage
    case passwordRequired
    case authenticationFailed
    case manifestAuthenticationFailed
    case unsupportedEncryption
    case readOnlySaveProhibited
    case interrupted
}

public enum SaveInterruptionPoint: Sendable {
    case none
    case beforeReplace
}

public struct OpenedFolioPackage: Sendable {
    public var document: FolioDocument
    public var isReadOnly: Bool
    public var recoveryState: WorkspaceSession.RecoveryState
}

public enum FolioPackageStore {
    private static let manifestName = "manifest.json"
    private static let recoverySuffix = ".recovery"
    private static let minimumIterations = 100_000
    private static let maximumIterations = 1_000_000

    public static func save(
        _ document: FolioDocument,
        to destination: URL,
        password: String? = nil,
        interruptionPoint: SaveInterruptionPoint = .none
    ) throws {
        guard document.formatVersion.major <= 1 else {
            throw FolioPackageError.readOnlySaveProhibited
        }
        let manager = FileManager.default
        let parent = destination.deletingLastPathComponent()
        try manager.createDirectory(at: parent, withIntermediateDirectories: true)
        let temporary = parent.appendingPathComponent(
            ".\(destination.lastPathComponent).\(UUID().uuidString).tmp",
            isDirectory: true
        )
        defer { try? manager.removeItem(at: temporary) }
        try manager.createDirectory(at: temporary, withIntermediateDirectories: true)

        let packagedDocument = try packageResources(from: document, into: temporary)
        let documentData = try FolioDocumentCodec.encode(packagedDocument)
        let manifest: FolioPackageManifest
        if let password {
            var settings = FolioPackageManifest.Encryption(salt: randomData(count: 16))
            let key = try deriveKey(password: password, settings: settings)
            settings.passwordVerifier = passwordVerifier(for: key)
            let authenticatedManifest = FolioPackageManifest(
                formatVersion: FormatVersion(major: 1),
                documentPath: "document.enc",
                encryption: settings
            )
            let sealed = try AES.GCM.seal(
                documentData,
                using: key,
                authenticating: try authenticatedManifestData(authenticatedManifest)
            )
            guard let combined = sealed.combined else { throw FolioPackageError.invalidPackage }
            try combined.write(to: temporary.appendingPathComponent("document.enc"), options: .atomic)
            manifest = FolioPackageManifest(
                formatVersion: FormatVersion(major: 1),
                documentPath: "document.enc",
                documentChecksum: digest(combined),
                encryption: settings
            )
        } else {
            try documentData.write(to: temporary.appendingPathComponent("document.json"), options: .atomic)
            manifest = FolioPackageManifest(
                formatVersion: FormatVersion(major: 1),
                documentPath: "document.json",
                documentChecksum: digest(documentData)
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(manifest).write(to: temporary.appendingPathComponent(manifestName), options: .atomic)
        _ = try open(temporary, password: password)

        if interruptionPoint == .beforeReplace {
            let recovery = recoveryURL(for: destination)
            let recoveryCandidate = parent.appendingPathComponent(
                ".\(destination.lastPathComponent).\(UUID().uuidString).recovery.tmp",
                isDirectory: true
            )
            defer { try? manager.removeItem(at: recoveryCandidate) }
            try manager.copyItem(at: temporary, to: recoveryCandidate)
            _ = try open(recoveryCandidate, password: password)
            try replace(recovery, with: recoveryCandidate)
            throw FolioPackageError.interrupted
        }

        try replace(destination, with: temporary)
        try? manager.removeItem(at: recoveryURL(for: destination))
    }

    public static func open(_ packageURL: URL, password: String? = nil) throws -> OpenedFolioPackage {
        let manifestURL = packageURL.appendingPathComponent(manifestName)
        guard let manifest = try? JSONDecoder().decode(
            FolioPackageManifest.self,
            from: Data(contentsOf: manifestURL)
        ), let expectedChecksum = manifest.documentChecksum,
           !expectedChecksum.isEmpty else {
            throw FolioPackageError.invalidPackage
        }

        let payloadURL = try safeURL(for: manifest.documentPath, in: packageURL)
        let payload: Data
        do { payload = try Data(contentsOf: payloadURL) }
        catch { throw FolioPackageError.invalidPackage }
        let documentData: Data
        if let settings = manifest.encryption {
            guard let password else { throw FolioPackageError.passwordRequired }
            let payloadChecksumMatches = digest(payload) == expectedChecksum
            do {
                let key = try deriveKey(password: password, settings: settings)
                if settings.derivationVersion == 2 {
                    guard let expectedVerifier = settings.passwordVerifier else {
                        throw FolioPackageError.unsupportedEncryption
                    }
                    guard passwordVerifier(for: key) == expectedVerifier else {
                        throw FolioPackageError.authenticationFailed
                    }
                }
                let box = try AES.GCM.SealedBox(combined: payload)
                if settings.derivationVersion == 2 {
                    documentData = try AES.GCM.open(
                        box,
                        using: key,
                        authenticating: try authenticatedManifestData(manifest)
                    )
                } else {
                    documentData = try AES.GCM.open(box, using: key)
                }
            } catch let error as FolioPackageError {
                throw error
            } catch {
                if payloadChecksumMatches {
                    throw FolioPackageError.manifestAuthenticationFailed
                }
                throw FolioPackageError.authenticationFailed
            }
        } else {
            guard digest(payload) == expectedChecksum else {
                throw FolioPackageError.invalidPackage
            }
            documentData = payload
        }

        let opened: OpenedFolioDocument
        do { opened = try FolioDocumentCodec.decode(documentData) }
        catch { throw FolioPackageError.invalidPackage }
        try verifyResources(in: opened.document, packageURL: packageURL)
        let recovery: WorkspaceSession.RecoveryState = FileManager.default.fileExists(
            atPath: recoveryURL(for: packageURL).path
        ) ? .available : .none
        return OpenedFolioPackage(
            document: opened.document,
            isReadOnly: manifest.formatVersion.major > 1 || opened.isReadOnly,
            recoveryState: recovery
        )
    }

    public static func openRecovery(
        for packageURL: URL,
        password: String? = nil
    ) throws -> OpenedFolioPackage {
        try open(recoveryURL(for: packageURL), password: password)
    }

    public static func saveRecovery(
        _ document: FolioDocument,
        for packageURL: URL,
        password: String? = nil
    ) throws {
        let manager = FileManager.default
        let recovery = recoveryURL(for: packageURL)
        let parent = recovery.deletingLastPathComponent()
        try manager.createDirectory(at: parent, withIntermediateDirectories: true)
        let candidate = parent.appendingPathComponent(
            ".\(recovery.lastPathComponent).\(UUID().uuidString).tmp",
            isDirectory: true
        )
        defer { try? manager.removeItem(at: candidate) }

        try save(document, to: candidate, password: password)
        _ = try open(candidate, password: password)
        try replace(recovery, with: candidate)
    }

    public static func discardRecovery(for packageURL: URL) throws {
        let recovery = recoveryURL(for: packageURL)
        guard FileManager.default.fileExists(atPath: recovery.path) else { return }
        try FileManager.default.removeItem(at: recovery)
    }

    private static func replace(_ destination: URL, with temporary: URL) throws {
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

    private static func deriveKey(password: String, settings: FolioPackageManifest.Encryption) throws -> SymmetricKey {
        guard settings.algorithm == "AES-256-GCM",
              settings.keyDerivation == "PBKDF2-HMAC-SHA256",
              (1 ... 2).contains(settings.derivationVersion),
              settings.salt.count >= 16,
              (minimumIterations ... maximumIterations).contains(settings.iterations) else {
            throw FolioPackageError.unsupportedEncryption
        }
        let derivedKeyByteCount = 32
        var material = Data(count: derivedKeyByteCount)
        let status = password.withCString { passwordBytes in
            settings.salt.withUnsafeBytes { saltBytes in
                material.withUnsafeMutableBytes { outputBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes,
                        strlen(passwordBytes),
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        settings.salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(settings.iterations),
                        outputBytes.bindMemory(to: UInt8.self).baseAddress,
                        derivedKeyByteCount
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw FolioPackageError.unsupportedEncryption }
        return SymmetricKey(data: material)
    }

    private static func authenticatedManifestData(_ manifest: FolioPackageManifest) throws -> Data {
        let authenticated = FolioPackageManifest(
            formatVersion: manifest.formatVersion,
            documentPath: manifest.documentPath,
            encryption: manifest.encryption
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(authenticated)
    }

    private static func passwordVerifier(for key: SymmetricKey) -> Data {
        Data(HMAC<SHA256>.authenticationCode(
            for: Data("FolioFold password verifier v1".utf8),
            using: key
        ))
    }

    private static func packageResources(
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

    private static func verifyResources(in document: FolioDocument, packageURL: URL) throws {
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

    private static func safeURL(for path: String, in packageURL: URL) throws -> URL {
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

    private static func randomData(count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func recoveryURL(for packageURL: URL) -> URL {
        packageURL.deletingLastPathComponent()
            .appendingPathComponent(packageURL.lastPathComponent + recoverySuffix)
    }
}
