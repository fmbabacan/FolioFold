#!/bin/zsh
set -euo pipefail

executable=${1:-.build/release/FolioFold}
ready_file=$(mktemp -u /tmp/foliofold-tab-ui-ready.XXXXXX)
log_file=$(mktemp /tmp/foliofold-tab-ui.XXXXXX)

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
  -e 'on identifierOf(elementRef)' \
  -e 'try' \
  -e 'tell application "System Events" to return value of attribute "AXIdentifier" of elementRef as text' \
  -e 'on error' \
  -e 'return ""' \
  -e 'end try' \
  -e 'end identifierOf' \
  -e 'on elementWithIdentifierPrefix(elementList, expectedPrefix)' \
  -e 'repeat with elementRef in elementList' \
  -e 'set candidateIdentifier to my identifierOf(elementRef)' \
  -e 'if candidateIdentifier starts with expectedPrefix then return elementRef' \
  -e 'end repeat' \
  -e 'return missing value' \
  -e 'end elementWithIdentifierPrefix' \
  -e 'on elementsWithIdentifierPrefix(elementList, expectedPrefix)' \
  -e 'set matches to {}' \
  -e 'repeat with elementRef in elementList' \
  -e 'if my identifierOf(elementRef) starts with expectedPrefix then set end of matches to elementRef' \
  -e 'end repeat' \
  -e 'return matches' \
  -e 'end elementsWithIdentifierPrefix' \
  -e 'on elementWithIdentifier(elementList, expectedIdentifier)' \
  -e 'repeat with elementRef in elementList' \
  -e 'if my identifierOf(elementRef) is expectedIdentifier then return elementRef' \
  -e 'end repeat' \
  -e 'return missing value' \
  -e 'end elementWithIdentifier' \
  -e 'on run argv' \
  -e 'set targetPID to item 1 of argv as integer' \
  -e 'tell application "System Events"' \
  -e 'set appProcess to first process whose unix id is targetPID' \
  -e 'repeat 100 times' \
  -e 'if (count of windows of appProcess) > 0 then exit repeat' \
  -e 'delay 0.02' \
  -e 'end repeat' \
  -e 'if (count of windows of appProcess) is 0 then error "FolioFold window did not appear"' \
  -e 'set frontmost of appProcess to true' \
  -e 'set mainWindow to first window of appProcess' \
  -e 'set allElements to entire contents of mainWindow' \
  -e 'set editorControl to my elementWithIdentifierPrefix(allElements, "document.block.editor.")' \
  -e 'if editorControl is missing value then error "Document block editor is missing"' \
  -e 'set value of editorControl to "Unsaved UI test content"' \
  -e 'delay 0.3' \
  -e 'set saveStateControl to my elementWithIdentifier(entire contents of mainWindow, "document.save-state")' \
  -e 'if saveStateControl is missing value then error "Document save state is missing"' \
  -e 'if description of saveStateControl does not contain "Unsaved" and name of saveStateControl does not contain "Unsaved" then error "Editing did not expose unsaved state"' \
  -e 'set documentTab to my elementWithIdentifierPrefix(entire contents of mainWindow, "workspace.tab.select.")' \
  -e 'if documentTab is missing value then error "Document tab is missing"' \
  -e 'set documentTabIdentifier to my identifierOf(documentTab)' \
  -e 'set mergeControl to my elementWithIdentifier(entire contents of mainWindow, "sidebar.merge")' \
  -e 'perform action "AXPress" of mergeControl' \
  -e 'delay 0.2' \
  -e 'set tabsAfterMerge to my elementsWithIdentifierPrefix(entire contents of mainWindow, "workspace.tab.select.")' \
  -e 'if (count of tabsAfterMerge) is not 2 then error "Merge did not create exactly one reusable tool tab"' \
  -e 'if my elementWithIdentifier(entire contents of mainWindow, "workspace.tabs.overflow") is missing value then error "Open tabs overflow menu is missing"' \
  -e 'perform action "AXPress" of mergeControl' \
  -e 'delay 0.2' \
  -e 'if (count of my elementsWithIdentifierPrefix(entire contents of mainWindow, "workspace.tab.select.")) is not 2 then error "Repeated Merge created a duplicate tool tab"' \
  -e 'set documentTab to my elementWithIdentifier(entire contents of mainWindow, documentTabIdentifier)' \
  -e 'perform action "AXPress" of documentTab' \
  -e 'delay 0.2' \
  -e 'set tabsMenu to first menu bar item of menu bar 1 of appProcess whose name is "Tabs"' \
  -e 'click tabsMenu' \
  -e 'click menu item "Select Next Tab" of menu 1 of tabsMenu' \
  -e 'delay 0.2' \
  -e 'if my elementWithIdentifier(entire contents of mainWindow, "merge.primary-action") is missing value then error "Control-Tab did not select the next tab"' \
  -e 'click tabsMenu' \
  -e 'click menu item "Select Previous Tab" of menu 1 of tabsMenu' \
  -e 'delay 0.2' \
  -e 'if my elementWithIdentifier(entire contents of mainWindow, "document.workspace-heading") is missing value then error "Control-Shift-Tab did not select the previous tab"' \
  -e 'click tabsMenu' \
  -e 'click menu item "Close Current Tab" of menu 1 of tabsMenu' \
  -e 'delay 0.3' \
  -e 'if not (exists sheet 1 of mainWindow) and not (exists window 1 whose name contains "Close Unsaved Session") then error "Close Current Tab did not request unsaved confirmation"' \
  -e 'key code 53' \
  -e 'delay 0.2' \
  -e 'if my elementWithIdentifier(entire contents of mainWindow, documentTabIdentifier) is missing value then error "Cancelling close removed the unsaved document tab"' \
  -e 'end tell' \
  -e 'end run' \
  "${pid}"

test ! -s "${log_file}"
print "workspace_tab_ui_tests=passed"
