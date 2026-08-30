# Contributing to FolioFold

Thank you for helping improve FolioFold. Bug reports, focused fixes, accessibility improvements, tests, and documentation updates are welcome.

## Before opening an issue

- Search existing issues to avoid duplicates.
- Include the FolioFold version, macOS version, Mac architecture, and reproducible steps.
- Remove confidential document content from examples and screenshots.

## Development workflow

1. Fork the repository and create a focused branch.
2. Run `swift test` and `swift build -c release`.
3. For interface changes, run `scripts/ui-smoke.sh .build/release/FolioFold`.
4. For startup or memory-sensitive changes, run `scripts/runtime-smoke.sh .build/release/FolioFold`.
5. Open a pull request describing the problem, approach, verification, and user-visible impact.

Contributions must preserve local-first document processing and must not introduce telemetry, document uploads, or network dependencies without an explicit project decision.

## Security reports

Do not open public issues for suspected vulnerabilities. Follow [SECURITY.md](SECURITY.md).
