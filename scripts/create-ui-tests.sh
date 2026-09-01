#!/bin/zsh
set -euo pipefail

executable=${1:-.build/release/FolioFold}
ready_file=$(mktemp -u /tmp/foliofold-create-test-ready.XXXXXX)
log_file=$(mktemp /tmp/foliofold-create-test.XXXXXX)
save_target=$(mktemp -u /tmp/foliofold-create-test.XXXXXX.foliofold)
export_target=$(mktemp -u /tmp/foliofold-create-test.XXXXXX.pdf)

FOLIOFOLD_READY_FILE="${ready_file}" FOLIOFOLD_SAVE_TARGET="${save_target}" FOLIOFOLD_EXPORT_TARGET="${export_target}" "${executable}" >"${log_file}" 2>&1 &
pid=$!
cleanup() {
  kill "${pid}" 2>/dev/null || true
  wait "${pid}" 2>/dev/null || true
  rm -rf "${ready_file}" "${log_file}" "${save_target}" "${export_target}"
}
trap cleanup EXIT

for _ in {1..100}; do
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
  -e 'on elementWithIdentifier(elementList, expectedIdentifier)' \
  -e 'repeat with elementRef in elementList' \
  -e 'if my identifierOf(elementRef) is expectedIdentifier then return elementRef' \
  -e 'end repeat' \
  -e 'return missing value' \
  -e 'end elementWithIdentifier' \
  -e 'on elementWithIdentifierPrefix(elementList, expectedPrefix)' \
  -e 'repeat with elementRef in elementList' \
  -e 'if my identifierOf(elementRef) starts with expectedPrefix then return elementRef' \
  -e 'end repeat' \
  -e 'return missing value' \
  -e 'end elementWithIdentifierPrefix' \
  -e 'on countWithIdentifierPrefix(elementList, expectedPrefix)' \
  -e 'set matchCount to 0' \
  -e 'repeat with elementRef in elementList' \
  -e 'if my identifierOf(elementRef) starts with expectedPrefix then set matchCount to matchCount + 1' \
  -e 'end repeat' \
  -e 'return matchCount' \
  -e 'end countWithIdentifierPrefix' \
  -e 'on waitForWindow(targetPID)' \
  -e 'tell application "System Events"' \
  -e 'set targetProcess to first process whose unix id is targetPID' \
  -e 'repeat 100 times' \
  -e 'if (count of windows of targetProcess) > 0 then return' \
  -e 'delay 0.02' \
  -e 'end repeat' \
  -e 'error "FolioFold window did not return after modal transition"' \
  -e 'end tell' \
  -e 'end waitForWindow' \
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
  -e 'my waitForWindow(targetPID)' \
  -e 'set appProcess to first process whose unix id is targetPID' \
  -e 'set mainWindow to first window of appProcess' \
  -e 'set initialEditorCount to my countWithIdentifierPrefix(entire contents of mainWindow, "document.block.editor.")' \
  -e 'set addControl to my elementWithIdentifier(entire contents of mainWindow, "document.block.add")' \
  -e 'if addControl is missing value then error "Add control is missing"' \
  -e 'perform action "AXPress" of addControl' \
  -e 'delay 0.2' \
  -e 'if my countWithIdentifierPrefix(entire contents of mainWindow, "document.block.editor.") is not initialEditorCount + 1 then error "Add did not create a block"' \
  -e 'set editorControl to my elementWithIdentifierPrefix(entire contents of mainWindow, "document.block.editor.")' \
  -e 'set value of editorControl to "Create UI test content"' \
  -e 'delay 0.2' \
  -e 'set undoControl to my elementWithIdentifier(entire contents of mainWindow, "document.history.undo")' \
  -e 'if undoControl is missing value or enabled of undoControl is false then error "Undo was not enabled after editing"' \
  -e 'perform action "AXPress" of undoControl' \
  -e 'delay 0.2' \
  -e 'set redoControl to my elementWithIdentifier(entire contents of mainWindow, "document.history.redo")' \
  -e 'if redoControl is missing value or enabled of redoControl is false then error "Redo was not enabled after undo"' \
  -e 'perform action "AXPress" of redoControl' \
  -e 'delay 0.2' \
  -e 'set pinControl to my elementWithIdentifierPrefix(entire contents of mainWindow, "document.block.pin.")' \
  -e 'if pinControl is missing value then error "Pin control is missing"' \
  -e 'perform action "AXPress" of pinControl' \
  -e 'delay 0.2' \
  -e 'set returnControl to my elementWithIdentifierPrefix(entire contents of mainWindow, "document.overlay.return.")' \
  -e 'if returnControl is missing value then error "Pin did not expose Return to Flow"' \
  -e 'perform action "AXPress" of returnControl' \
  -e 'delay 0.2' \
  -e 'if my elementWithIdentifierPrefix(entire contents of mainWindow, "document.overlay.return.") is not missing value then error "Return to Flow did not remove the overlay"' \
  -e 'set saveControl to my elementWithIdentifier(entire contents of mainWindow, "document.save")' \
  -e 'if saveControl is missing value then error "Save control is missing"' \
  -e 'perform action "AXPress" of saveControl' \
  -e 'delay 0.2' \
  -e 'set exportControl to my elementWithIdentifier(entire contents of mainWindow, "document.export")' \
  -e 'if exportControl is missing value then error "Export control is missing"' \
  -e 'perform action "AXPress" of exportControl' \
  -e 'delay 0.2' \
  -e 'set templatesControl to my elementWithIdentifier(entire contents of mainWindow, "folio.templates")' \
  -e 'if templatesControl is missing value then error "Templates control is missing"' \
  -e 'perform action "AXPress" of templatesControl' \
  -e 'delay 0.3' \
  -e 'if my elementWithIdentifier(entire contents of appProcess, "template.field-name") is missing value then error "Template sheet did not open"' \
  -e 'if my elementWithIdentifier(entire contents of appProcess, "template.done") is missing value then error "Template Done control is missing"' \
  -e 'end tell' \
  -e 'end run' \
  "${pid}"

test -e "${save_target}"
test -s "${export_target}"
test "$(head -c 4 "${export_target}")" = "%PDF"
test ! -s "${log_file}"
print "create_ui_tests=passed"
