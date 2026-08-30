#!/bin/zsh
set -euo pipefail

executable=${1:-.build/release/FolioFold}
maximum_startup_ms=${FOLIOFOLD_MAX_STARTUP_MS:-2000}
maximum_rss_kb=${FOLIOFOLD_MAX_RSS_KB:-122880}
ready_file=$(mktemp -u /tmp/foliofold-ready.XXXXXX)
log_file=$(mktemp /tmp/foliofold-runtime.XXXXXX)
start_ns=$(python3 -c 'import time; print(time.time_ns())')

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

test -f "${ready_file}" || { print -u2 "FolioFold did not signal UI readiness"; exit 1; }
end_ns=$(python3 -c 'import time; print(time.time_ns())')
startup_ms=$(python3 -c 'import sys; print((int(sys.argv[2]) - int(sys.argv[1])) // 1000000)' "${start_ns}" "${end_ns}")
sleep 0.5
rss_kb=$(ps -o rss= -p "${pid}" | tr -d ' ')

test -n "${rss_kb}"
test "${startup_ms}" -ge 0
test "${startup_ms}" -lt "${maximum_startup_ms}"
test "${rss_kb}" -lt "${maximum_rss_kb}"
test ! -s "${log_file}"

print "startup_ms=${startup_ms}"
print "rss_kb=${rss_kb}"
