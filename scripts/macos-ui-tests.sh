#!/bin/zsh
set -euo pipefail

executable=${1:-.build/release/FolioFold}
ready_file=$(mktemp -u /tmp/foliofold-ui-test-ready.XXXXXX)
log_file=$(mktemp /tmp/foliofold-ui-test.XXXXXX)

FOLIOFOLD_READY_FILE="${ready_file}" FOLIOFOLD_SHOW_WELCOME=1 "${executable}" >"${log_file}" 2>&1 &
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
  -e 'on run argv' \
  -e 'set targetPID to item 1 of argv as integer' \
  -e 'tell application "System Events"' \
  -e 'set appProcess to first process whose unix id is targetPID' \
  -e 'repeat 100 times' \
  -e 'if (count of windows of appProcess) > 0 then' \
  -e 'set allElements to entire contents of first window of appProcess' \
  -e 'if my elementWithIdentifier(allElements, "welcome.sheet") is not missing value then exit repeat' \
  -e 'end if' \
  -e 'delay 0.02' \
  -e 'end repeat' \
  -e 'if (count of windows of appProcess) is 0 then error "FolioFold window did not appear"' \
  -e 'set mainWindow to first window of appProcess' \
  -e 'set welcomeSheet to my elementWithIdentifier(entire contents of mainWindow, "welcome.sheet")' \
  -e 'if welcomeSheet is missing value then error "First-launch welcome sheet did not appear"' \
  -e 'set continueControl to my elementWithIdentifier(entire contents of mainWindow, "welcome.continue")' \
  -e 'if continueControl is missing value then error "Welcome Continue control is missing"' \
  -e 'perform action "AXPress" of continueControl' \
  -e 'delay 0.2' \
  -e 'if my elementWithIdentifier(entire contents of mainWindow, "welcome.sheet") is not missing value then error "Welcome sheet did not close"' \
  -e 'if my elementWithIdentifier(entire contents of mainWindow, "workspace.sidebar") is missing value then error "Workspace did not become available after welcome"' \
  -e 'end tell' \
  -e 'end run' \
  "${pid}"

test ! -s "${log_file}"
print "welcome_ui_test=passed"
cleanup
trap - EXIT
scripts/ui-smoke.sh "${executable}"
scripts/create-ui-tests.sh "${executable}"
scripts/workspace-tab-ui-tests.sh "${executable}"
print "macos_ui_tests=passed"
