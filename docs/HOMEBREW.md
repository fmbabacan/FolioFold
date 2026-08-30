# Homebrew Distribution

FolioFold uses a personal Homebrew tap so users can install with:

```shell
brew install --cask fmbabacan/tap/foliofold
```

After the first GitHub Release is final:

1. Create the public repository `fmbabacan/homebrew-tap`.
2. Add `Casks/foliofold.rb`.
3. Copy `Cask/foliofold.rb.template` from FolioFold.
4. Replace the version and SHA-256 placeholders with the immutable release values.
5. Run `brew audit --cask --online foliofold` and test installation.
6. Verify upgrades, uninstall, and `zap` cleanup on a clean test account.
