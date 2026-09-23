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

if grep -E -q 'git (clone|pull)( |$)' "$ROOT/setup-rackwatch"; then
  fail 'setup does not clone or pull a branch'
else
  pass 'setup does not clone or pull a branch'
fi

expect_pin() {
  local mode="$1" value="$2" label="$3"
  if pinned_commit_ok "$value"; then
    [[ "$mode" == pass ]] && pass "$label" || fail "$label"
  else
    [[ "$mode" == fail ]] && pass "$label" || fail "$label"
  fi
}

expect_pin pass "$RACKWATCH_COMMIT" 'accepts the reviewed RackWatch SHA'
expect_pin fail 'main' 'rejects a branch name'
expect_pin fail 'e9858730f5f9e862' 'rejects a short SHA'
expect_pin fail 'E9858730F5F9E86269AE2B685CBF7A2D22C385B5' 'rejects an uppercase SHA'
expect_pin fail 'e9858730f5f9e86269ae2b685cbf7a2d22c385b5 ' 'rejects a padded SHA'

src="$test_dir/src"
git init -q -b main "$src"
git -C "$src" config user.email 'setup-test@example.com'
git -C "$src" config user.name 'setup-test'
printf 'v1\n' >"$src/docker-compose.yml"
git -C "$src" add docker-compose.yml
git -C "$src" commit -q -m 'reviewed'
pin=$(git -C "$src" rev-parse HEAD)
printf 'v2\n' >"$src/docker-compose.yml"
git -C "$src" commit -q -am 'unreviewed tip'

saved_repo="$RACKWATCH_REPOSITORY"
saved_commit="$RACKWATCH_COMMIT"
saved_install="$INSTALL_DIR"
RACKWATCH_REPOSITORY="$src"
RACKWATCH_COMMIT="$pin"
INSTALL_DIR="$test_dir/install"

if prepare_local_checkout \
  && [[ "$(git -C "$INSTALL_DIR" rev-parse HEAD)" == "$pin" ]] \
  && [[ "$(git -C "$INSTALL_DIR" rev-parse --abbrev-ref HEAD)" == "HEAD" ]] \
  && [[ "$(cat "$INSTALL_DIR/docker-compose.yml")" == "v1" ]]; then
  pass 'fresh checkout is the detached pin, not the branch tip'
else
  fail 'fresh checkout is the detached pin, not the branch tip'
fi

clone="$test_dir/clone"
git clone -q "$src" "$clone"
RACKWATCH_REPOSITORY=$(git -C "$clone" remote get-url origin)
INSTALL_DIR="$clone"
if prepare_local_checkout \
  && [[ "$(git -C "$clone" rev-parse HEAD)" == "$pin" ]] \
  && [[ "$(git -C "$clone" rev-parse --abbrev-ref HEAD)" == "HEAD" ]] \
  && [[ "$(cat "$clone/docker-compose.yml")" == "v1" ]]; then
  pass 'moves an existing branch checkout onto the detached pin'
else
  fail 'moves an existing branch checkout onto the detached pin'
fi

if (
  INSTALL_DIR="$clone"
  RACKWATCH_REPOSITORY=$(git -C "$clone" remote get-url origin)
  RACKWATCH_COMMIT="$pin"
  git -C "$INSTALL_DIR" checkout -q main
  verify_pinned_checkout
); then
  fail 'refuses to build after HEAD leaves the pin'
else
  pass 'refuses to build after HEAD leaves the pin'
fi

dirty="$test_dir/dirty"
git clone -q "$src" "$dirty"
printf 'local\n' >>"$dirty/docker-compose.yml"
if (
  INSTALL_DIR="$dirty"
  RACKWATCH_REPOSITORY=$(git -C "$dirty" remote get-url origin)
  RACKWATCH_COMMIT="$pin"
  prepare_local_checkout
); then
  fail 'refuses a dirty checkout'
else
  pass 'refuses a dirty checkout'
fi

other="$test_dir/other"
git init -q "$other"
git -C "$other" remote add origin 'https://example.invalid/not-rackwatch.git'
if (
  INSTALL_DIR="$other"
  RACKWATCH_REPOSITORY="$src"
  RACKWATCH_COMMIT="$pin"
  prepare_local_checkout
); then
  fail 'refuses a different origin'
else
  pass 'refuses a different origin'
fi

if (
  INSTALL_DIR="$test_dir/branch-pin"
  RACKWATCH_REPOSITORY="$src"
  RACKWATCH_COMMIT='main'
  prepare_local_checkout
); then
  fail 'refuses to follow a branch name'
else
  pass 'refuses to follow a branch name'
fi

RACKWATCH_REPOSITORY="$saved_repo"
RACKWATCH_COMMIT="$saved_commit"
INSTALL_DIR="$saved_install"

if (( failures > 0 )); then
  printf '%s setup test(s) failed\n' "$failures" >&2
  exit 1
fi

printf '%s\n' 'All setup tests passed.'
