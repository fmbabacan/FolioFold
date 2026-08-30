# FolioFold

FolioFold is a native, privacy-focused macOS workspace for creating, editing, converting, organizing, signing, and exporting PDF and Folio documents. Document processing stays on the Mac.

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

## Install

Download the archive for the Mac architecture from the latest GitHub Release, verify the published SHA-256 checksum, unzip it, and move FolioFold.app to /Applications.

After the first notarized public Homebrew release is published, install with: brew install --cask fmbabacan/tap/foliofold

The Mac App Store build will use the same document engine. App Store updates are delivered by macOS; GitHub and Homebrew installations use their respective release channels.

## Updates

Choose Help > Check for Updates in FolioFold. GitHub installations open the latest release page. Homebrew users can run brew update followed by brew upgrade --cask foliofold.

The current version is visible in the Help menu and in the first-launch welcome window.

## Build from source

Run swift build, swift test, and swift build -c release. Create a local application archive with FOLIOFOLD_VERSION=0.1.0 scripts/package-release.sh arm64.

Official public releases are signed with an Apple Developer ID Application certificate, notarized by Apple, and published with SHA-256 checksums.

## Privacy and signatures

FolioFold performs document operations locally. A visual signature is an image annotation and is not a certificate-backed digital signature.

## Support

For bug reports, installation problems, and feature requests, email [fatihmehmet@babacan.co](mailto:fatihmehmet@babacan.co). Please include the FolioFold version, macOS version, and steps that reproduce the issue.

## License

FolioFold is licensed under the Apache License 2.0. See [LICENSE](LICENSE).
