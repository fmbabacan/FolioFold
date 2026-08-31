# Architecture

FolioFold is a Swift Package with two production targets.

- `FolioFoldCore` contains document models, package storage, templates, PDF operations, conversion, editing, redaction, export, and workspace state.
- `FolioFold` contains the SwiftUI application, document workspace, design tokens, signature capture, release experience, localization resources, and application entry point.
- `FolioFoldCoreTests` mirrors the core capabilities with focused test files.
- `scripts` contains repeatable verification, packaging, notarization, and publication commands.
- `Distribution/Homebrew` contains the Homebrew Cask template used after release archives become immutable.

New core behavior should normally be implemented in `FolioFoldCore` with tests before being exposed through `FolioFold`. Document bytes must remain local unless a future explicit product decision changes the offline-first boundary.

The `FolioFold` application target is organized into `App`, `Features`, `DesignSystem`, and `Shared` folders. `FolioFoldCore` is organized into `Models`, `Editing`, `PDF`, `Templates`, `Persistence`, and `Workspace` responsibilities.
