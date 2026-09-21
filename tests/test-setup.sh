#!/usr/bin/env bash
set -uo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../setup-rackwatch
source "$ROOT/setup-rackwatch"

failures=0

pass() {
  printf 'PASS: %s\n' "$1"
}

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

expect_url() {
  local expected="$1" url="$2" label="$3"
  if validate_url "$url"; then
    [[ "$expected" == pass ]] && pass "$label" || fail "$label"
  else
    [[ "$expected" == fail ]] && pass "$label" || fail "$label"
  fi
}

expect_transport() {
  local expected="$1" url="$2" token="$3" label="$4"
  if token_transport_allowed "$url" "$token"; then
    [[ "$expected" == pass ]] && pass "$label" || fail "$label"
  else
    [[ "$expected" == fail ]] && pass "$label" || fail "$label"
  fi
}

expect_url pass 'http://127.0.0.1:8080' 'accepts local RackWatch URL'
expect_url pass 'https://rackwatch.example/base' 'accepts HTTPS base path'
expect_url pass 'http://rackwatch_service:8080' 'accepts Docker-style local alias'
expect_url pass 'https://rackwatch.internal.' 'accepts absolute FQDN with trailing dot'
expect_url fail 'ftp://rackwatch.example' 'rejects unsupported scheme'
expect_url fail 'https://rackwatch.example/?token=secret' 'rejects query string'
expect_url fail 'https://user:pass@rackwatch.example' 'rejects URL credentials'
expect_url fail 'https://rackwatch.example:0' 'rejects port zero'
expect_url fail 'https://rackwatch.example:65536' 'rejects out-of-range port'
expect_url fail 'https://rackwatch.example:999999999999999999999' 'rejects oversized port'
expect_url fail 'https://rackwatch.example\@evil.test' 'rejects URL backslashes'
expect_url fail $'https://rackwatch.example/path\tvalue' 'rejects URL control whitespace'

expect_transport pass 'http://localhost:8080' 'token' 'allows token on localhost'
expect_transport pass 'http://[::1]:8080' 'token' 'allows token on IPv6 loopback'
expect_transport pass 'https://rackwatch.example' 'token' 'allows token over HTTPS'
expect_transport fail 'http://rackwatch.example' 'token' 'rejects token over remote HTTP'
expect_transport pass 'http://rackwatch.example' '' 'allows tokenless remote HTTP'

test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT
SHELL_CONFIG="$test_dir/shell.json"
cat >"$SHELL_CONFIG" <<'JSON'
{
  "version": 1,
  "bar": {
    "layout": {
      "left": [],
      "center": [],
      "right": [{"id": "nezbit.rackwatch", "refreshIntervalSec": 5}]
    }
  }
}
JSON
chmod 644 "$SHELL_CONFIG"

secret='not-printed-secret'
if output=$(configure_widget 'https://rackwatch.example' "$secret" 2>&1); then
  if jq -e --arg secret "$secret" '
    .bar.layout.right[0]
    | .url == "https://rackwatch.example"
      and .token == $secret
      and .refreshIntervalSec == 5
  ' "$SHELL_CONFIG" >/dev/null; then
    pass 'configures URL and token while preserving widget settings'
  else
    fail 'configures URL and token while preserving widget settings'
  fi
  [[ "$output" != *"$secret"* ]] \
    && pass 'does not print token during configuration' \
    || fail 'does not print token during configuration'
  [[ "$(stat -c '%a' "$SHELL_CONFIG")" == 600 ]] \
    && pass 'restricts shell configuration permissions' \
    || fail 'restricts shell configuration permissions'
else
  fail 'configures widget atomically'
fi

if (( failures > 0 )); then
  printf '%s setup test(s) failed\n' "$failures" >&2
  exit 1
fi

printf '%s\n' 'All setup tests passed.'
