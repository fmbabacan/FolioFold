# FolioFold

[![CI](https://github.com/fmbabacan/FolioFold/actions/workflows/ci.yml/badge.svg)](https://github.com/fmbabacan/FolioFold/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![macOS](https://img.shields.io/badge/macOS-15%2B-black.svg)](#requirements)

FolioFold is an open-source, native macOS workspace for creating, editing, converting, organizing, signing, and exporting PDF and Folio documents. It works locally, without uploading your documents to a service.

## Download and install

FolioFold requires macOS 15 or later. Download the latest notarized build from the [Releases page](https://github.com/fmbabacan/FolioFold/releases/latest).

1. Choose `FolioFold-<version>-arm64.zip` for Apple Silicon Macs (M1, M2, M3, M4, or newer).
2. Choose `FolioFold-<version>-x86_64.zip` for Intel Macs.
3. Open the downloaded ZIP file.
4. Drag `FolioFold.app` into the Applications folder.
5. Open FolioFold from Applications. A notarized public release should open normally without bypassing Gatekeeper.

If you are unsure which Mac you have, choose Apple menu > About This Mac and check whether the processor or chip says Apple or Intel.

FolioFold v0.4.0 is distributed as separate notarized downloads for Apple Silicon and Intel Macs. Use Apple menu > About This Mac if the Mac architecture is unknown.

### Homebrew

Install the notarized release through the FolioFold Homebrew tap:

```shell
brew install --cask fmbabacan/tap/foliofold
```

GitHub Packages is not used for the FolioFold macOS application. Installable application archives belong in GitHub Releases; Homebrew Cask points to those same notarized release files.

Thank you for using and supporting FolioFold. If you encounter a problem or have an idea, contact [fatihmehmet@babacan.co](mailto:fatihmehmet@babacan.co).

## Highlights

- Create structured Folio documents and generate documents from reusable template fields.
- Open, merge, split, reorder, rotate, duplicate, and export PDF pages.
- Convert supported text, image, RTF, and controlled local HTML files to PDF.
- Add notes, links, highlights, drawings, images, forms, and visual signatures.
- Draw a visual signature with a mouse or trackpad, import one, and store signatures locally.
- Apply destructive redactions to newly generated PDFs without overwriting the source.
- Use encrypted Folio packages, recovery snapshots, undo, redo, and workspace restoration.
- Work offline without uploading documents to a service.

## Requirements

- macOS 15 or later
- Apple Silicon or Intel Mac, according to the downloaded package

## Updates

Choose Help > Check for Updates in FolioFold to use the native Sparkle update flow. Homebrew users can also run brew update followed by brew upgrade --cask foliofold.

The current version is visible in the Help menu and in the first-launch welcome window.

## Build from source

Install Xcode 26 or later, clone the repository, and run:

```shell
swift build
swift test
swift build -c release
```

Create an ad-hoc signed local application archive with:

```shell
SPARKLE_PUBLIC_KEY="$(.build/artifacts/sparkle/Sparkle/bin/generate_keys --account FolioFold -p)" FOLIOFOLD_VERSION=0.4.0 scripts/package-release.sh arm64
```

Official public releases are signed with an Apple Developer ID Application certificate, notarized by Apple, and published with SHA-256 checksums.

## Privacy and signatures

FolioFold performs document operations locally. A visual signature is an image annotation and is not a certificate-backed digital signature.

## Support

For bug reports, installation problems, and feature requests, email [fatihmehmet@babacan.co](mailto:fatihmehmet@babacan.co). Please include the FolioFold version, macOS version, and steps that reproduce the issue.

Public bug reports and feature requests can also be submitted through [GitHub Issues](https://github.com/fmbabacan/FolioFold/issues). Security reports must follow [SECURITY.md](SECURITY.md) and should not be posted publicly.

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) and the [Code of Conduct](CODE_OF_CONDUCT.md).

Start with the [architecture guide](docs/ARCHITECTURE.md), then run `scripts/verify.sh` before opening a pull request. The [publication roadmap](docs/ROADMAP.md) explains the GitHub, Homebrew, and future App Store phases.

## License

FolioFold is licensed under the Apache License 2.0. See [LICENSE](LICENSE).
