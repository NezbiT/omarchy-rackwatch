#!/usr/bin/env bash
set -uo pipefail

COLLECTOR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/collector.sh"
FAKE_BIN="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/fixtures/bin"
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

check_loopback_token() {
  local url="$1"
  local output status
  output=$(printf 'test-token\n' | PATH="$FAKE_BIN:$PATH" EXPECT_TOKEN='test-token' \
    "$COLLECTOR" snapshot "$url" 2>&1)
  status=$?
  if (( status != 0 )) || ! jq -e '.ok == true' <<<"$output" >/dev/null 2>&1; then
    printf 'FAIL: loopback token policy for %s (status=%s output=%s)\n' "$url" "$status" "$output" >&2
    failures=$((failures + 1))
  else
    printf 'PASS: allows loopback token policy for %s\n' "$url"
  fi
}

check_remote_http_token_rejected() {
  local url="$1"
  local output status
  output=$(printf 'test-token\n' | "$COLLECTOR" snapshot "$url" 2>&1)
  status=$?
  if (( status != 2 )) || ! jq -e '.error == "Refusing to send API token over plain HTTP"' <<<"$output" >/dev/null 2>&1; then
    printf 'FAIL: remote HTTP token policy for %s (status=%s output=%s)\n' "$url" "$status" "$output" >&2
    failures=$((failures + 1))
  else
    printf 'PASS: rejects remote HTTP token for %s\n' "$url"
  fi
}

check_valid_url() {
  local url="$1" label="$2" output status
  output=$(printf '\n' | PATH="$FAKE_BIN:$PATH" "$COLLECTOR" snapshot "$url" 2>&1)
  status=$?
  if (( status != 0 )) || ! jq -e '.ok == true' <<<"$output" >/dev/null 2>&1; then
    printf 'FAIL: %s (status=%s output=%s)\n' "$label" "$status" "$output" >&2
    failures=$((failures + 1))
  else
    printf 'PASS: %s\n' "$label"
  fi
}

check_success() {
  local output status mutation_output mutation_status
  output=$(printf 'test-token\n' | PATH="$FAKE_BIN:$PATH" EXPECT_TOKEN='test-token' \
    "$COLLECTOR" snapshot 'https://rackwatch.example/base')
  status=$?
  if (( status != 0 )) || ! jq -e '.ok == true and .data.instance == "test"' <<<"$output" >/dev/null 2>&1; then
    printf 'FAIL: valid authenticated snapshot (status=%s output=%s)\n' "$status" "$output" >&2
    failures=$((failures + 1))
  else
    printf 'PASS: valid authenticated snapshot\n'
  fi

  mutation_output=$(printf 'test-token\n' | PATH="$FAKE_BIN:$PATH" EXPECT_TOKEN='test-token' \
    "$COLLECTOR" restart-container 'https://rackwatch.example/base' demo)
  mutation_status=$?
  if (( mutation_status != 0 )) || ! jq -e '.ok == true and .action == "restart" and .target == "demo"' <<<"$mutation_output" >/dev/null 2>&1; then
    printf 'FAIL: valid authenticated mutation (status=%s output=%s)\n' "$mutation_status" "$mutation_output" >&2
    failures=$((failures + 1))
  else
    printf 'PASS: valid authenticated mutation\n'
  fi
}

bash -n "$COLLECTOR" || failures=$((failures + 1))
check_failure 'rejects unsupported URL schemes' snapshot 'file:///etc/passwd'
check_failure 'rejects URL query strings' snapshot 'https://example.com/rackwatch?debug=1'
check_failure 'rejects URL fragments' snapshot 'https://example.com/rackwatch#top'
check_failure 'rejects embedded URL credentials' snapshot 'https://user:pass@example.com'
check_failure 'rejects invalid URL ports' snapshot 'https://example.com:70000'
check_failure 'rejects oversized URL ports' snapshot 'https://example.com:999999999999999999999'
check_failure 'rejects URL backslashes' snapshot 'https://example.com\@evil.test'
check_failure 'rejects URL control whitespace' snapshot $'https://example.com/path\tvalue'
check_failure 'rejects invalid container names' restart-container 'http://127.0.0.1:9' '../bad'
check_failure 'unknown actions return valid JSON' invalid-action 'http://127.0.0.1:9'
check_failure 'network failures are not reported as success' restart-container 'http://127.0.0.1:9' demo
check_loopback_token 'http://localhost/rackwatch'
check_loopback_token 'http://127.0.0.1/rackwatch'
check_loopback_token 'http://[::1]/rackwatch'
check_remote_http_token_rejected 'http://localhost.evil/rackwatch'
check_remote_http_token_rejected 'http://rackwatch.example/rackwatch'
check_valid_url 'http://rackwatch_service:8080' 'accepts Docker-style local aliases'
check_valid_url 'https://rackwatch.internal.' 'accepts absolute FQDN with trailing dot'
check_success

if (( failures > 0 )); then
  printf '%s test(s) failed\n' "$failures" >&2
  exit 1
fi
printf '%s\n' 'All collector tests passed.'
