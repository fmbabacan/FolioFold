# Sparkle Update Requirements for FolioFold v0.4.0

## Functional requirements

- Help > Check for Updates opens the native Sparkle update flow.
- Automatic checks are enabled while unattended installation remains disabled.
- Apple Silicon bundles use `appcast-arm64.xml`; Intel bundles use `appcast-x86_64.xml`. Each feed contains exactly one update per bundle version, preventing selection of an archive for the wrong processor architecture.
- Sparkle, GitHub Releases, and Homebrew reference the same notarized immutable archives.

## Security requirements

- FolioFold uses a dedicated Ed25519 account named `FolioFold`; the private key stays in the release operator's Keychain.
- Only the public `SUPublicEDKey` value is embedded in the application bundle.
- Every enclosure carries an EdDSA signature, exact byte length, semantic version, build version, and minimum macOS version.
- The feed is served over HTTPS and published from the protected `main` branch.
- Developer ID signing, Apple notarization, stapling, Gatekeeper validation, SHA-256 verification, and Sparkle signing are all required before publication.

## Packaging requirements

- `Sparkle.framework`, Updater.app, Autoupdate, and Sparkle XPC services are embedded under `Contents/Frameworks`.
- The executable resolves frameworks through `@executable_path/../Frameworks`.
- The final application bundle is signed after Sparkle is embedded.
- CI verifies framework presence, runtime linkage, Info.plist keys, architectures, checksums, and package size.

## Release sequence

1. Build and test v0.4.0.
2. Package and notarize arm64 and x86_64 archives.
3. Sign both final archives with the FolioFold Sparkle key.
4. Generate `appcast-arm64.xml`, `appcast-x86_64.xml`, and the Homebrew Cask from those exact archives.
5. Publish immutable GitHub Release assets.
6. Explicitly commit both generated appcasts after verifying that their enclosure lengths and EdDSA signatures match the final immutable archives, then update the Homebrew tap.
7. Verify an upgrade from v0.3.1 to v0.4.0 on both architectures.
