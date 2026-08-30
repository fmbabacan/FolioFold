# FolioFold v1 Release Checklist

## Automated gates

- Run the complete test suite on macOS 15 and the current macOS release.
- Build arm64 and x86_64 release executables.
- Validate the String Catalog, required accessibility labels, dependency-free package graph, offline-only source tree, runtime smoke test, and executable and archive size budgets.
- Confirm that the 1,000-page layout test stays deterministic and completes within its bounded performance budget without eagerly rasterizing every page.
- Run `scripts/runtime-smoke.sh .build/release/FolioFold` on a reference Apple Silicon machine to verify that the SwiftUI workspace reaches its ready state within the startup budget, remains below 120 MB idle RSS, and emits no unexpected output.
- Run `scripts/ui-smoke.sh .build/release/FolioFold` to launch the real macOS process, verify the main workspace controls, open Merge, Split, and Convert, and create a new Folio workspace through the accessibility tree.

## Signing and notarization

1. Build each architecture using the release configuration.
2. Place the executable in a signed application bundle using the distribution identity supplied by the release operator.
3. Sign with the hardened runtime and without a network-client entitlement.
4. Submit the archive to Apple notarization, wait for acceptance, staple the ticket, and verify the result with `spctl`.
5. Publish SHA-256 checksums with both GitHub release archives.

Signing identities, App Store Connect credentials, notarization credentials, and Homebrew repository access are release-operator secrets and must never be stored in this repository.

Run `scripts/package-release.sh arm64` or `scripts/package-release.sh x86_64` to create a signed archive and checksum. The signing identity is read from `FOLIOFOLD_SIGNING_IDENTITY`; omission produces an ad-hoc signed local verification build. After configuring an Apple notarytool keychain profile, set `FOLIOFOLD_NOTARY_PROFILE` and run `scripts/notarize-release.sh <archive.zip>`.

Each architecture-specific archive contains a consistently named `FolioFold.app`, matching the Homebrew Cask and Finder installation name. Generated release artifacts are written to the ignored `dist/` directory.

## Distribution channels

- GitHub Releases: upload the notarized arm64 and x86_64 archives with checksums.
- Homebrew Cask: update URLs and hashes only after the notarized GitHub assets are final.
- Homebrew Cask: replace the placeholders in `Cask/foliofold.rb.template` with the final version and published archive hashes.
- Mac App Store: use the same sandbox-compatible feature set and verify that document processing does not require network access.

## Manual acceptance

- Verify keyboard navigation, VoiceOver names, increased contrast, reduced motion, light and dark appearance, and large system text.
- Exercise Create, Open, Merge, Split, Convert, encrypted package recovery, PDF password entry, annotations, forms, redaction, recents, external-change handling, and explicit source replacement.
- Test long localized strings and right-to-left layout without clipping or inaccessible controls.
