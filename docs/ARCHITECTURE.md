# Architecture

FolioFold is a Swift Package with two production targets.

- `FolioFoldCore` contains document models, package storage, templates, PDF operations, conversion, editing, redaction, export, and workspace state.
- `FolioFold` contains the SwiftUI application, document workspace, design tokens, signature capture, release experience, localization resources, and application entry point.
- `FolioFoldCoreTests` mirrors the core capabilities with focused test files.
- `scripts` contains repeatable verification, packaging, notarization, and publication commands.
- `Cask` contains the Homebrew template used after a release archive becomes immutable.

New core behavior should normally be implemented in `FolioFoldCore` with tests before being exposed through `FolioFold`. Document bytes must remain local unless a future explicit product decision changes the offline-first boundary.

`FolioFoldApp.swift` currently contains application composition and several interface sections. Splitting this file into feature-focused files is a maintainability task that should be completed in small, behavior-preserving commits.
