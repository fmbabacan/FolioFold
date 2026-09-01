#!/bin/zsh
set -euo pipefail

executable=${1:-.build/release/FolioFold}
pdf_workspace_source=Sources/FolioFold/Features/PDFWorkspace/PDFWorkspace.swift
grep -Fq 'pdf.page-number' "$pdf_workspace_source"
grep -Fq 'pdf.zoom-value' "$pdf_workspace_source"
grep -Fq 'pdf.find' "$pdf_workspace_source"
grep -Fq 'PDFViewPageChanged' "$pdf_workspace_source"
grep -Fq 'PDFViewScaleChanged' "$pdf_workspace_source"
grep -Fq 'Fit Page' "$pdf_workspace_source"
grep -Fq 'Fit Width' "$pdf_workspace_source"
grep -Fq 'pdf.inspector-category' "$pdf_workspace_source"
grep -Fq 'pdf.inspector.pages' "$pdf_workspace_source"
grep -Fq 'pdf.inspector.annotation' "$pdf_workspace_source"
grep -Fq 'pdf.inspector.form' "$pdf_workspace_source"
grep -Fq 'pdf.inspector.redaction' "$pdf_workspace_source"
grep -Fq 'InteractivePDFView' "$pdf_workspace_source"
grep -Fq 'pdf.redaction.validation' "$pdf_workspace_source"
grep -Fq 'pdf.redaction.advanced' "$pdf_workspace_source"
grep -Fq 'pdf.annotation-placement-help' "$pdf_workspace_source"
grep -Fq 'pdf.form-placement-help' "$pdf_workspace_source"
grep -Fq 'case annotation' "$pdf_workspace_source"
grep -Fq 'case form' "$pdf_workspace_source"
grep -Fq 'let bounds = annotationBounds' "$pdf_workspace_source"
grep -Fq 'bounds: formFieldBounds' "$pdf_workspace_source"
grep -Fq 'document.first-use-guide' Sources/FolioFold/Features/FolioDocument/FolioDocumentWorkspace.swift
grep -Fq 'workspace.tabs.overflow' Sources/FolioFold/Features/Workspace/WorkspaceView.swift
grep -Fq 'notification: .announcementRequested' Sources/FolioFold/Shared/OperationStatusView.swift
grep -Fq 'Arrow keys move by 1 point' "$pdf_workspace_source"
grep -Fq 'page.bounds(for: .mediaBox).contains(bounds)' "$pdf_workspace_source"
grep -Fq 'Export PDF…' "$pdf_workspace_source"
grep -Fq 'merge.primary-action' Sources/FolioFold/Features/Merge/MergeWorkspace.swift
grep -Fq 'split.primary-action' Sources/FolioFold/Features/Split/SplitWorkspace.swift
grep -Fq 'convert.primary-action' Sources/FolioFold/Features/Convert/ConvertWorkspace.swift
grep -Fq 'document.workspace-heading' Sources/FolioFold/Features/FolioDocument/FolioDocumentWorkspace.swift
grep -Fq 'pdf.workspace-heading' "$pdf_workspace_source"
grep -Fq 'workspaceGuidanceMaximumWidth' Sources/FolioFold/DesignSystem/DesignTokens.swift
grep -Fq 'document.block-kind' Sources/FolioFold/Features/FolioDocument/FolioDocumentWorkspace.swift
grep -Fq '.keyboardShortcut("z", modifiers: [.command])' Sources/FolioFold/Features/FolioDocument/FolioDocumentWorkspace.swift
grep -Fq '.keyboardShortcut("z", modifiers: [.command, .shift])' Sources/FolioFold/Features/FolioDocument/FolioDocumentWorkspace.swift
grep -Fq '.keyboardShortcut("s", modifiers: [.command])' Sources/FolioFold/Features/FolioDocument/FolioDocumentWorkspace.swift
grep -Fq 'document.block.editor.' Sources/FolioFold/Features/FolioDocument/FolioDocumentWorkspace.swift
grep -Fq 'document.block.add' Sources/FolioFold/Features/FolioDocument/FolioDocumentWorkspace.swift
grep -Fq 'document.history.undo' Sources/FolioFold/Features/FolioDocument/FolioDocumentWorkspace.swift
grep -Fq 'document.history.redo' Sources/FolioFold/Features/FolioDocument/FolioDocumentWorkspace.swift
grep -Fq 'document.save' Sources/FolioFold/Features/FolioDocument/FolioDocumentWorkspace.swift
grep -Fq 'document.export' Sources/FolioFold/Features/FolioDocument/FolioDocumentWorkspace.swift
grep -Fq 'document.overlay.return.' Sources/FolioFold/Features/FolioDocument/FolioDocumentWorkspace.swift
grep -Fq 'template.field-name' Sources/FolioFold/Features/Templates/TemplateWorkspace.swift
grep -Fq 'template.field-default' Sources/FolioFold/Features/Templates/TemplateWorkspace.swift
grep -Fq 'template.field-add' Sources/FolioFold/Features/Templates/TemplateWorkspace.swift
grep -Fq 'template.generated-value.' Sources/FolioFold/Features/Templates/TemplateWorkspace.swift
grep -Fq 'template.binding.' Sources/FolioFold/Features/Templates/TemplateWorkspace.swift
grep -Fq 'template.generate' Sources/FolioFold/Features/Templates/TemplateWorkspace.swift
grep -Fq 'template.done' Sources/FolioFold/Features/Templates/TemplateWorkspace.swift
grep -Fq 'layoutPriority(1)' Sources/FolioFold/Features/FolioDocument/FolioDocumentWorkspace.swift
grep -Fq 'SemanticStatus' Sources/FolioFold/Shared/OperationStatusView.swift
grep -Fq 'checkmark.circle.fill' Sources/FolioFold/Shared/OperationStatusView.swift
grep -Fq 'exclamationmark.triangle.fill' Sources/FolioFold/Shared/OperationStatusView.swift
grep -Fq 'xmark.octagon.fill' Sources/FolioFold/Shared/OperationStatusView.swift
grep -Fq 'info.circle.fill' Sources/FolioFold/Shared/OperationStatusView.swift
grep -Fq 'OperationStatusView(isRunning: false' Sources/FolioFold/Features/FolioDocument/FolioDocumentWorkspace.swift
grep -Fq 'localization-smoke.sh' scripts/verify.sh
grep -Fq 'appearance-smoke.sh' scripts/verify.sh
grep -Fq 'FOLIOFOLD_SHOW_WELCOME' Sources/FolioFold/App/FolioFoldApp.swift
grep -Fq 'welcome.continue' Sources/FolioFold/App/ReleaseExperience.swift
grep -Fq 'accessibilityElement(children: .contain)' Sources/FolioFold/App/ReleaseExperience.swift
grep -Fq 'workspace-tab-ui-tests.sh' scripts/macos-ui-tests.sh
grep -Fq 'CommandMenu("Tabs")' Sources/FolioFold/App/FolioFoldApp.swift
grep -Fq '.keyboardShortcut(.tab, modifiers: [.control])' Sources/FolioFold/App/FolioFoldApp.swift
grep -Fq '.keyboardShortcut(.tab, modifiers: [.control, .shift])' Sources/FolioFold/App/FolioFoldApp.swift
grep -Fq '.keyboardShortcut("w", modifiers: [.command])' Sources/FolioFold/App/FolioFoldApp.swift
grep -Fq 'folioFoldSelectNextTab' Sources/FolioFold/Features/Workspace/WorkspaceView.swift
grep -Fq 'folioFoldSelectPreviousTab' Sources/FolioFold/Features/Workspace/WorkspaceView.swift
grep -Fq 'folioFoldCloseCurrentTab' Sources/FolioFold/Features/Workspace/WorkspaceView.swift
ready_file=$(mktemp -u /tmp/foliofold-ui-ready.XXXXXX)
log_file=$(mktemp /tmp/foliofold-ui-smoke.XXXXXX)

FOLIOFOLD_READY_FILE="${ready_file}" "${executable}" >"${log_file}" 2>&1 &
pid=$!
cleanup() {
  kill "${pid}" 2>/dev/null || true
  wait "${pid}" 2>/dev/null || true
  rm -f "${ready_file}" "${log_file}"
}
trap cleanup EXIT

for _ in {1..500}; do
  test -f "${ready_file}" && break
  kill -0 "${pid}" 2>/dev/null || { cat "${log_file}" >&2; exit 1; }
  sleep 0.02
done
test -f "${ready_file}"

osascript \
  -e 'on elementWithIdentifier(elementList, expectedIdentifier)' \
  -e 'repeat with elementRef in elementList' \
  -e 'try' \
  -e 'tell application "System Events" to set candidateIdentifier to value of attribute "AXIdentifier" of elementRef' \
  -e 'if candidateIdentifier is expectedIdentifier then return elementRef' \
  -e 'end try' \
  -e 'end repeat' \
  -e 'return missing value' \
  -e 'end elementWithIdentifier' \
  -e 'on hasNamedElement(elementList, expectedName)' \
  -e 'repeat with elementRef in elementList' \
  -e 'try' \
  -e 'tell application "System Events" to set candidateName to name of elementRef' \
  -e 'if candidateName is expectedName then return true' \
  -e 'end try' \
  -e 'end repeat' \
  -e 'return false' \
  -e 'end hasNamedElement' \
  -e 'on run argv' \
  -e 'set targetPID to item 1 of argv as integer' \
  -e 'tell application "System Events"' \
  -e 'set appProcess to first process whose unix id is targetPID' \
  -e 'repeat 100 times' \
  -e 'if (count of windows of appProcess) > 0 then exit repeat' \
  -e 'delay 0.02' \
  -e 'end repeat' \
  -e 'if (count of windows of appProcess) is 0 then error "FolioFold window did not appear"' \
  -e 'set mainWindow to first window of appProcess' \
  -e 'set allElements to entire contents of mainWindow' \
  -e 'set createControl to my elementWithIdentifier(allElements, "sidebar.create")' \
  -e 'set openControl to my elementWithIdentifier(allElements, "sidebar.open")' \
  -e 'set mergeControl to my elementWithIdentifier(allElements, "sidebar.merge")' \
  -e 'set splitControl to my elementWithIdentifier(allElements, "sidebar.split")' \
  -e 'set convertControl to my elementWithIdentifier(allElements, "sidebar.convert")' \
  -e 'set narrowerSidebarControl to my elementWithIdentifier(allElements, "sidebar.width.decrease")' \
  -e 'set widerSidebarControl to my elementWithIdentifier(allElements, "sidebar.width.increase")' \
  -e 'if createControl is missing value then error "Create control is missing"' \
  -e 'if openControl is missing value then error "Open control is missing"' \
  -e 'if mergeControl is missing value then error "Merge control is missing"' \
  -e 'if splitControl is missing value then error "Split control is missing"' \
  -e 'if convertControl is missing value then error "Convert control is missing"' \
  -e 'if narrowerSidebarControl is missing value then error "Narrower sidebar control is missing"' \
  -e 'if widerSidebarControl is missing value then error "Wider sidebar control is missing"' \
  -e 'click mergeControl' \
  -e 'delay 0.2' \
  -e 'if not my hasNamedElement(entire contents of mainWindow, "Merge PDFs") then error "Merge workspace did not open"' \
  -e 'click splitControl' \
  -e 'delay 0.2' \
  -e 'if not my hasNamedElement(entire contents of mainWindow, "Split PDF") then error "Split workspace did not open"' \
  -e 'click convertControl' \
  -e 'delay 0.2' \
  -e 'if not my hasNamedElement(entire contents of mainWindow, "Convert Files") then error "Convert workspace did not open"' \
  -e 'click splitControl' \
  -e 'delay 0.2' \
  -e 'if not my hasNamedElement(entire contents of mainWindow, "Split PDF") then error "Repeated Split selection did not open its reusable workspace"' \
  -e 'click splitControl' \
  -e 'delay 0.2' \
  -e 'if not my hasNamedElement(entire contents of mainWindow, "Split PDF") then error "Repeated Split click lost workspace synchronization"' \
  -e 'click createControl' \
  -e 'delay 0.2' \
  -e 'if not my hasNamedElement(entire contents of mainWindow, "Untitled") then error "Created Folio workspace is missing the untitled document"' \
  -e 'end tell' \
  -e 'end run' \
  "${pid}"

test ! -s "${log_file}"
print "ui_smoke=passed"
