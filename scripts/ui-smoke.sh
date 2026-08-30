#!/bin/zsh
set -euo pipefail

executable=${1:-.build/release/FolioFold}
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

for _ in {1..100}; do
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
  -e 'if createControl is missing value then error "Create control is missing"' \
  -e 'if openControl is missing value then error "Open control is missing"' \
  -e 'if mergeControl is missing value then error "Merge control is missing"' \
  -e 'if splitControl is missing value then error "Split control is missing"' \
  -e 'if convertControl is missing value then error "Convert control is missing"' \
  -e 'click mergeControl' \
  -e 'delay 0.2' \
  -e 'if not my hasNamedElement(entire contents of mainWindow, "Merge PDFs") then error "Merge workspace did not open"' \
  -e 'click splitControl' \
  -e 'delay 0.2' \
  -e 'if not my hasNamedElement(entire contents of mainWindow, "Split PDF") then error "Split workspace did not open"' \
  -e 'click convertControl' \
  -e 'delay 0.2' \
  -e 'if not my hasNamedElement(entire contents of mainWindow, "Convert Files") then error "Convert workspace did not open"' \
  -e 'click createControl' \
  -e 'delay 0.2' \
  -e 'if not my hasNamedElement(entire contents of mainWindow, "Untitled") then error "Created Folio workspace is missing the untitled document"' \
  -e 'end tell' \
  -e 'end run' \
  "${pid}"

test ! -s "${log_file}"
print "ui_smoke=passed"
