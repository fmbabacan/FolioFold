#!/bin/zsh
set -euo pipefail

workspace=Sources/FolioFold/Features/Workspace/WorkspaceView.swift

grep -Fq '@Environment(\.colorSchemeContrast)' "$workspace"
grep -Fq '@Environment(\.accessibilityDifferentiateWithoutColor)' "$workspace"
grep -Fq '@Environment(\.accessibilityReduceMotion)' "$workspace"
grep -Fq 'transaction.disablesAnimations = true' "$workspace"
grep -Fq 'differentiateWithoutColor ? Color.primary : DesignTokens.inkBlue' "$workspace"
grep -Fq 'colorSchemeContrast == .increased ? 0.30 : 0.18' "$workspace"
grep -Fq '.accessibilityAddTraits(isSelected ? .isSelected : [])' "$workspace"

print "appearance_smoke=passed"
