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

        public init(
            algorithm: String = "AES-256-GCM",
            keyDerivation: String = "PBKDF2-HMAC-SHA256",
            derivationVersion: Int = 1,
            iterations: Int = 200_000,
            salt: Data
        ) {
            self.algorithm = algorithm
            self.keyDerivation = keyDerivation
            self.derivationVersion = derivationVersion
            self.iterations = iterations
            self.salt = salt
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
        let temporary = parent.appendingPathComponent(".(destination.lastPathComponent).(UUID().uuidString).tmp", isDirectory: true)
        defer { try? manager.removeItem(at: temporary) }
        try manager.createDirectory(at: temporary, withIntermediateDirectories: true)

        let documentData = try FolioDocumentCodec.encode(document)
        let manifest: FolioPackageManifest
        if let password {
            let settings = FolioPackageManifest.Encryption(salt: randomData(count: 16))
            let key = try deriveKey(password: password, settings: settings)
            let sealed = try AES.GCM.seal(documentData, using: key)
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
            try Data().write(to: recoveryURL(for: destination), options: .atomic)
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
        if digest(payload) != expectedChecksum {
            throw FolioPackageError.invalidPackage
        }

        let documentData: Data
        if let settings = manifest.encryption {
            guard let password else { throw FolioPackageError.passwordRequired }
            do {
                let key = try deriveKey(password: password, settings: settings)
                let box = try AES.GCM.SealedBox(combined: payload)
                documentData = try AES.GCM.open(box, using: key)
            } catch let error as FolioPackageError {
                throw error
            } catch {
                throw FolioPackageError.authenticationFailed
            }
        } else {
            documentData = payload
        }

        let opened: OpenedFolioDocument
        do { opened = try FolioDocumentCodec.decode(documentData) }
        catch { throw FolioPackageError.invalidPackage }
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

    private static func replace(_ destination: URL, with temporary: URL) throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: destination.path) else {
            try manager.moveItem(at: temporary, to: destination)
            return
        }
        let backup = destination.deletingLastPathComponent()
            .appendingPathComponent(".(destination.lastPathComponent).(UUID().uuidString).backup", isDirectory: true)
        try manager.moveItem(at: destination, to: backup)
        do {
            try manager.moveItem(at: temporary, to: destination)
            try manager.removeItem(at: backup)
        } catch {
            try? manager.moveItem(at: backup, to: destination)
            throw error
        }
    }

    private static func deriveKey(password: String, settings: FolioPackageManifest.Encryption) throws -> SymmetricKey {
        guard settings.algorithm == "AES-256-GCM",
              settings.keyDerivation == "PBKDF2-HMAC-SHA256",
              settings.derivationVersion == 1,
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
