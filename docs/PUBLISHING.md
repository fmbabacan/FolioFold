# Publishing FolioFold

Official downloads are published through GitHub Releases. GitHub Packages is not used for the macOS application. Homebrew Cask references immutable release archives.

## Security model

The Developer ID private key stays in the release operator's macOS Keychain. Do not commit it, attach it to an issue, paste it into chat, or upload it as a repository file. The initial release process deliberately avoids storing a `.p12` private key in GitHub Actions.

## One-time Apple setup

1. Install a `Developer ID Application` certificate and its private key in the login Keychain.
2. Run `security find-identity -v -p codesigning` and copy the exact identity name.
3. Create a Keychain-backed notarization profile with `xcrun notarytool store-credentials foliofoldnotary`.
4. Keep a separately encrypted offline backup of the certificate and private key.

## Release sequence

1. Run `scripts/verify.sh`.
2. Prepare Apple Silicon and Intel artifacts with `scripts/prepare-release.sh`.
3. Test both archives on clean Macs.
4. Run `scripts/publish-release.sh <version>` to create the annotated tag and GitHub Release.
5. Wait for Release verification to confirm checksums, signatures, architectures, and Gatekeeper acceptance.
6. Run `scripts/generate-distribution-metadata.sh <version> <build>` against the final notarized archives, then commit `appcast-arm64.xml` and `appcast-x86_64.xml` explicitly with `git add -f`. Generated appcasts are ignored by default to prevent test artifacts from being committed accidentally.
7. Copy the generated `dist/foliofold.rb` into the Homebrew tap, audit it, and verify install, upgrade, uninstall, and zap behavior.
8. For v0.4.0, test the one-time manual bootstrap replacement from the published v0.3.1 archive on Apple Silicon and Intel. v0.3.1 has no Sparkle client or feed, so this transition cannot be an in-app update. Confirm that both versions use `app.foliofold.FolioFold`, that v0.4.0 launches, and that preferences and representative documents remain usable.
9. Beginning with the release after v0.4.0, test the complete signed Sparkle upgrade path from the published notarized v0.4.0 bundle on both architectures.

The generated GitHub Release description identifies `arm64` for Apple Silicon Macs and `x86_64` for Intel Macs, and publishes a matching SHA-256 file for each archive.

Never replace a published asset. Publish a new patch version instead.
