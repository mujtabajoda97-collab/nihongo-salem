#!/bin/sh
# CI helper: runs a command; if it fails, publishes the interesting lines of its output
# as GitHub annotations (readable from the run page and the API), then returns its exit code.
#   sh tool/ci_report.sh <title> <command...>
title="$1"; shift
log="$(mktemp)"
"$@" > "$log" 2>&1
code=$?
cat "$log"
if [ "$code" -ne 0 ]; then
  esc() { sed -e 's/%/%25/g' -e 's/\r//g' | awk '{printf "%s%%0A", $0}'; }
  sig=$(grep -nE "Error|error:|FAILURE|What went wrong|\[E\]|Expected|Actual|e: |Exception|Could not|not found|Unhandled" "$log" | head -40 | cut -c1-300 | esc)
  tail=$(tail -n 45 "$log" | cut -c1-300 | esc)
  echo "::error title=${title} (signature)::${sig}"
  echo "::error title=${title} (last lines)::${tail}"
fi
exit "$code"
