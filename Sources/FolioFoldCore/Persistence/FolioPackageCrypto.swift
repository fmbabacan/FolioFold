import CommonCrypto
import CryptoKit
import Foundation

extension FolioPackageStore {
    static let minimumIterations = 100_000
    static let maximumIterations = 1_000_000
    static func deriveKey(password: String, settings: FolioPackageManifest.Encryption) throws -> SymmetricKey {
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

    static func authenticatedManifestData(_ manifest: FolioPackageManifest) throws -> Data {
        let authenticated = FolioPackageManifest(
            formatVersion: manifest.formatVersion,
            documentPath: manifest.documentPath,
            encryption: manifest.encryption
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(authenticated)
    }

    static func passwordVerifier(for key: SymmetricKey) -> Data {
        Data(HMAC<SHA256>.authenticationCode(
            for: Data("FolioFold password verifier v1".utf8),
            using: key
        ))
    }

    static func randomData(count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

}
