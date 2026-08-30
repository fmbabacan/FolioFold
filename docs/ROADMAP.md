# Publication Roadmap

## Phase 1: Public repository

- Community, security, license, CI, CodeQL, architecture, and contributor guidance.
- Clear installation and source-build instructions.
- Small, reviewable refactoring of the application composition file.

## Phase 2: GitHub Release

- Local Developer ID signing and Apple notarization.
- Apple Silicon and Intel archives with SHA-256 files.
- Annotated semantic-version tag and post-publication verification.

## Phase 3: Homebrew

- Public `homebrew-tap` repository.
- Audited architecture-aware Cask using immutable GitHub Release assets.
- Installation, upgrade, uninstall, and cleanup verification.

## Phase 4: App Store

- App identifier, sandbox entitlements, privacy declarations, metadata, screenshots, archive validation, TestFlight, and App Review submission.
