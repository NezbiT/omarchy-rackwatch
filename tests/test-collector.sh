#!/usr/bin/env bash
set -uo pipefail

COLLECTOR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/collector.sh"
failures=0

check_failure() {
  local label="$1"
  shift
  local output status
  output=$(printf '\n' | "$COLLECTOR" "$@" 2>&1)
  status=$?
  if (( status == 0 )) || ! jq -e '.ok == false and (.error | type == "string")' <<<"$output" >/dev/null 2>&1; then
    printf 'FAIL: %s (status=%s output=%s)\n' "$label" "$status" "$output" >&2
    failures=$((failures + 1))
  else
    printf 'PASS: %s\n' "$label"
  fi
}

bash -n "$COLLECTOR" || failures=$((failures + 1))
check_failure 'rejects unsupported URL schemes' snapshot 'file:///etc/passwd'
check_failure 'rejects URL query strings' snapshot 'https://example.com/rackwatch?debug=1'
check_failure 'rejects URL fragments' snapshot 'https://example.com/rackwatch#top'
check_failure 'rejects invalid container names' restart-container 'http://127.0.0.1:9' '../bad'
check_failure 'unknown actions return valid JSON' invalid-action 'http://127.0.0.1:9'
check_failure 'network failures are not reported as success' restart-container 'http://127.0.0.1:9' demo

if (( failures > 0 )); then
  printf '%s test(s) failed\n' "$failures" >&2
  exit 1
fi
printf '%s\n' 'All collector tests passed.'
