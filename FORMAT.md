# FolioFold Package Format v1

FolioFold editable documents use a directory package with the `.foliofold` extension. Finder presents the package as one document while implementations can inspect its versioned contents without depending on the FolioFold application license.

## Required entries

- `manifest.json` describes the package format version, document payload, optional authenticated-encryption settings, checksums, assets, and optional source PDF.
- The document payload contains the encoded `FolioDocument` model.
- Referenced assets and an optional source PDF are stored as separate package entries and authenticated by the manifest.
- Temporary previews, caches, passwords, and derived encryption keys are never package entries.

Paths in the manifest are relative package paths. Absolute paths, symbolic links, traversal components, and entries resolving outside the package root must be rejected.

## Compatibility

The format uses semantic major and minor version components. Readers preserve unknown fields where possible. A package with a newer unsupported major version may be opened read-only but must not be rewritten as a supported version.

## Integrity and encryption

Unencrypted entries are verified against manifest checksums before use. Optional encryption uses authenticated encryption with a unique package salt and versioned password-based key-derivation parameters. The password, derived key, document contents, and signature data must not be logged or stored outside the encrypted package. There is no password-recovery mechanism.

## Safe writing

Writers create a complete temporary package, reopen and verify it, preserve a recovery candidate when replacing an existing document, and then atomically replace the destination. A failed or interrupted save must leave the prior valid package intact.

## Recovery

An implementation may keep a sibling recovery package using the `.recovery` suffix. Recovery packages use the same validation and password rules as the primary package and are removed after a successful committed save.
