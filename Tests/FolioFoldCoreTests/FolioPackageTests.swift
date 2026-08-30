import CryptoKit
import Foundation
import Testing
@testable import FolioFoldCore

@Suite("Folio package")
struct FolioPackageTests {
    @Test("an unencrypted package writes a manifest and reopens the document")
    func unencryptedPackageRoundTrip() throws {
        let directory = temporaryURL("plain.foliofold")
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        let document = FolioDocument.blank()

        try FolioPackageStore.save(document, to: directory)
        let opened = try FolioPackageStore.open(directory)

        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("manifest.json").path))
        #expect(opened.document == document)
        #expect(!opened.isReadOnly)
        #expect(opened.recoveryState == .none)
    }

    @Test("encrypted packages use unique salts and require the correct password")
    func encryptedPackagesUseUniqueSalt() throws {
        let first = temporaryURL("first.foliofold")
        let second = first.deletingLastPathComponent().appendingPathComponent("second.foliofold")
        defer { try? FileManager.default.removeItem(at: first.deletingLastPathComponent()) }

        try FolioPackageStore.save(.blank(), to: first, password: "correct horse")
        try FolioPackageStore.save(.blank(), to: second, password: "correct horse")
        let firstManifest = try JSONDecoder().decode(FolioPackageManifest.self, from: Data(contentsOf: first.appendingPathComponent("manifest.json")))
        let secondManifest = try JSONDecoder().decode(FolioPackageManifest.self, from: Data(contentsOf: second.appendingPathComponent("manifest.json")))

        #expect(firstManifest.encryption?.salt != secondManifest.encryption?.salt)
        #expect(firstManifest.encryption?.derivationVersion == 2)
        #expect(firstManifest.encryption?.passwordVerifier != nil)
        #expect(throws: FolioPackageError.authenticationFailed) {
            try FolioPackageStore.open(first, password: "wrong")
        }
        #expect(try FolioPackageStore.open(first, password: "correct horse").document.formatVersion.major == 1)
    }

    @Test("version two encryption requires its password verifier")
    func versionTwoEncryptionRequiresPasswordVerifier() throws {
        let directory = temporaryURL("missing-verifier.foliofold")
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        try FolioPackageStore.save(.blank(), to: directory, password: "secret")
        let manifestURL = directory.appendingPathComponent("manifest.json")
        var object = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
        )
        var encryption = try #require(object["encryption"] as? [String: Any])
        encryption.removeValue(forKey: "passwordVerifier")
        object["encryption"] = encryption
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            .write(to: manifestURL)

        #expect(throws: FolioPackageError.unsupportedEncryption) {
            try FolioPackageStore.open(directory, password: "secret")
        }
    }

    @Test("authenticated encryption rejects modified package data")
    func encryptedPackageRejectsCorruption() throws {
        let directory = temporaryURL("corrupt.foliofold")
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        try FolioPackageStore.save(.blank(), to: directory, password: "secret")
        let payloadURL = directory.appendingPathComponent("document.enc")
        var payload = try Data(contentsOf: payloadURL)
        payload[payload.startIndex] ^= 0xff
        try payload.write(to: payloadURL)

        #expect(throws: FolioPackageError.authenticationFailed) {
            try FolioPackageStore.open(directory, password: "secret")
        }
    }

    @Test("an interrupted save preserves the prior valid package and recovery data")
    func interruptedSavePreservesPreviousPackage() throws {
        let directory = temporaryURL("interrupted.foliofold")
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        var original = FolioDocument.blank()
        original.flow[0].text = "original"
        try FolioPackageStore.save(original, to: directory)
        var replacement = original
        replacement.flow[0].text = "replacement"

        #expect(throws: FolioPackageError.interrupted) {
            try FolioPackageStore.save(replacement, to: directory, interruptionPoint: .beforeReplace)
        }

        let opened = try FolioPackageStore.open(directory)
        #expect(opened.document.flow[0].text == "original")
        #expect(opened.recoveryState == .available)
        let recovered = try FolioPackageStore.openRecovery(for: directory)
        #expect(recovered.document.flow[0].text == "replacement")
    }

    @Test("a read only package cannot be saved through the opened package API")
    func readOnlyPackageSaveIsRejected() throws {
        let directory = temporaryURL("readonly.foliofold")
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        var document = FolioDocument.blank()
        document.formatVersion = FormatVersion(major: 2)
        #expect(throws: FolioPackageError.readOnlySaveProhibited) {
            try FolioPackageStore.save(document, to: directory)
        }
    }

    @Test("a package without a document checksum is rejected")
    func missingChecksumIsRejected() throws {
        let directory = temporaryURL("missing-checksum.foliofold")
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        try FolioPackageStore.save(.blank(), to: directory)
        let manifestURL = directory.appendingPathComponent("manifest.json")
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
        object.removeValue(forKey: "documentChecksum")
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: manifestURL)
        #expect(throws: FolioPackageError.invalidPackage) {
            try FolioPackageStore.open(directory)
        }
    }

    @Test("encrypted package manifest tampering is detected")
    func encryptedManifestTamperingIsDetected() throws {
        let directory = temporaryURL("manifest-tamper.foliofold")
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        try FolioPackageStore.save(.blank(), to: directory, password: "secret")
        let manifestURL = directory.appendingPathComponent("manifest.json")
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
        var version = try #require(object["formatVersion"] as? [String: Any])
        version["minor"] = 7
        object["formatVersion"] = version
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: manifestURL)
        #expect(throws: FolioPackageError.manifestAuthenticationFailed) {
            try FolioPackageStore.open(directory, password: "secret")
        }
    }

    @Test("unsafe KDF work factors fail closed")
    func unsafeKDFParametersFailClosed() throws {
        let directory = temporaryURL("kdf-limit.foliofold")
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        try FolioPackageStore.save(.blank(), to: directory, password: "secret")
        let manifestURL = directory.appendingPathComponent("manifest.json")
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
        var encryption = try #require(object["encryption"] as? [String: Any])
        encryption["iterations"] = 100_000_001
        object["encryption"] = encryption
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: manifestURL)
        #expect(throws: FolioPackageError.unsupportedEncryption) {
            try FolioPackageStore.open(directory, password: "secret")
        }
    }

    @Test("a symlink document path cannot escape the package")
    func symlinkDocumentPathIsRejected() throws {
        let directory = temporaryURL("symlink.foliofold")
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        try FolioPackageStore.save(.blank(), to: directory)
        let payload = directory.appendingPathComponent("document.json")
        let outside = directory.deletingLastPathComponent().appendingPathComponent("outside.json")
        try FileManager.default.moveItem(at: payload, to: outside)
        try FileManager.default.createSymbolicLink(at: payload, withDestinationURL: outside)
        #expect(throws: FolioPackageError.invalidPackage) {
            try FolioPackageStore.open(directory)
        }
    }

    @Test("asset and source PDF bytes are copied into and verified with the package")
    func resourcesArePackagedAndVerified() throws {
        let directory = temporaryURL("resources.foliofold")
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        let inputRoot = directory.deletingLastPathComponent().appendingPathComponent("inputs", isDirectory: true)
        try FileManager.default.createDirectory(at: inputRoot, withIntermediateDirectories: true)
        let assetURL = inputRoot.appendingPathComponent("logo.bin")
        let sourceURL = inputRoot.appendingPathComponent("source.pdf")
        try Data("asset".utf8).write(to: assetURL)
        try Data("pdf".utf8).write(to: sourceURL)
        var document = FolioDocument.blank()
        document.assets = [FolioAsset(path: assetURL.path, mediaType: "application/octet-stream", checksum: "")]
        document.sourcePDF = SourcePDFInfo(path: sourceURL.path, checksum: "", pageCount: 1)
        try FolioPackageStore.save(document, to: directory)
        let opened = try FolioPackageStore.open(directory)
        let packagedAsset = directory.appendingPathComponent(opened.document.assets[0].path)
        let packagedSource = directory.appendingPathComponent(try #require(opened.document.sourcePDF?.path))
        #expect(try Data(contentsOf: packagedAsset) == Data("asset".utf8))
        #expect(try Data(contentsOf: packagedSource) == Data("pdf".utf8))
        try Data("tampered".utf8).write(to: packagedAsset)
        #expect(throws: FolioPackageError.invalidPackage) {
            try FolioPackageStore.open(directory)
        }
    }

    @Test("a newer package major version opens read only")
    func newerPackageVersionIsReadOnly() throws {
        let directory = temporaryURL("newer.foliofold")
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var document = FolioDocument.blank()
        document.formatVersion = FormatVersion(major: 2)
        let documentData = try FolioDocumentCodec.encode(document)
        try documentData.write(to: directory.appendingPathComponent("document.json"))
        let checksum = SHA256.hash(data: documentData)
            .map { String(format: "%02x", $0) }
            .joined()
        let manifest = FolioPackageManifest(
            formatVersion: FormatVersion(major: 2),
            documentPath: "document.json",
            documentChecksum: checksum
        )
        try JSONEncoder().encode(manifest).write(
            to: directory.appendingPathComponent("manifest.json")
        )

        #expect(try FolioPackageStore.open(directory).isReadOnly)
    }

    private func temporaryURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
    }
}
