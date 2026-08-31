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
    static let manifestName = "manifest.json"
    static let recoverySuffix = ".recovery"

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
}
