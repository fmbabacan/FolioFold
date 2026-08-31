# Publishing FolioFold

Official downloads are published through GitHub Releases. GitHub Packages is not used for the macOS application. Homebrew Cask references immutable release archives.

## Security model

The Developer ID private key stays in the release operator's macOS Keychain. Do not commit it, attach it to an issue, paste it into chat, or upload it as a repository file. The initial release process deliberately avoids storing a `.p12` private key in GitHub Actions.

## One-time Apple setup

1. Install a `Developer ID Application` certificate and its private key in the login Keychain.
2. Run `security find-identity -v -p codesigning` and copy the exact identity name.
3. Create a Keychain-backed notarization profile with `xcrun notarytool store-credentials FolioFoldNotary`.
4. Keep a separately encrypted offline backup of the certificate and private key.

## Release sequence

1. Run `scripts/verify.sh`.
2. Prepare Apple Silicon and Intel artifacts with `scripts/prepare-release.sh`.
3. Test both archives on clean Macs.
4. Run `scripts/publish-release.sh <version>` to create the annotated tag and GitHub Release.
5. Wait for Release verification to confirm checksums, signatures, architectures, and Gatekeeper acceptance.
6. Generate and publish the Homebrew Cask from the immutable release hashes.

The generated GitHub Release description identifies `arm64` for Apple Silicon Macs and `x86_64` for Intel Macs, and publishes a matching SHA-256 file for each archive.

Never replace a published asset. Publish a new patch version instead.
