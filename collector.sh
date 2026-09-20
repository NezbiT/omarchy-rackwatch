#!/usr/bin/env bash
set -uo pipefail

ACTION="${1:-snapshot}"
URL="${2:-http://127.0.0.1:8080}"
TARGET="${3:-}"
TOKEN=""
TOKEN_FILE=""
BODY_FILE=""
ERROR_FILE=""

cleanup() {
  [[ -n "$TOKEN_FILE" ]] && rm -f -- "$TOKEN_FILE"
  [[ -n "$BODY_FILE" ]] && rm -f -- "$BODY_FILE"
  [[ -n "$ERROR_FILE" ]] && rm -f -- "$ERROR_FILE"
}
trap cleanup EXIT HUP INT TERM

json_error() {
  local message="$1"
  local detail="${2:-}"
  local code="${3:-1}"
  jq -cn --arg error "$message" --arg detail "$detail" --argjson code "$code" \
    '{ok:false,error:$error,detail:$detail,code:$code}'
}

fail() {
  json_error "$1" "${2:-}" "${3:-1}"
  exit "${3:-1}"
}

command -v curl >/dev/null 2>&1 || fail "Missing dependency: curl"
command -v jq >/dev/null 2>&1 || {
  printf '%s\n' '{"ok":false,"error":"Missing dependency: jq","detail":"Install jq before using RackWatch","code":127}'
  exit 127
}

URL="${URL%/}"
case "$URL" in
  http://*|https://*) ;;
  *) fail "Invalid RackWatch URL" "Only http:// and https:// URLs are allowed" 2 ;;
esac
[[ "$URL" != *$'\n'* && "$URL" != *$'\r'* && "$URL" != *' '* ]] \
  || fail "Invalid RackWatch URL" "Whitespace is not allowed" 2
[[ "$URL" != *'?"* && "$URL" != *'#'* ]] \
  || fail "Invalid RackWatch URL" "Query strings and fragments are not allowed" 2
[[ "$URL" =~ ^https?://([A-Za-z0-9.-]+|\[[0-9A-Fa-f:]+\])(:[0-9]+)?(/[^?#]*)?$ ]] \
  || fail "Invalid RackWatch URL" "Use a base URL like http://host:8080 or https://host/rackwatch" 2

if [[ "$ACTION" != "open-url" ]]; then
  # Quickshell writes the token through stdin so it never appears in argv.
  IFS= read -r -t 2 TOKEN || TOKEN=""
  [[ "$TOKEN" != *$'\n'* && "$TOKEN" != *$'\r'* ]] \
    || fail "Invalid API token" "Newlines are not allowed" 2
fi

if [[ -n "$TOKEN" && "$URL" == http://* ]]; then
  case "$URL" in
    http://127.0.0.1:*|http://127.0.0.1|http://localhost:*|http://localhost|http://\[::1\]:*|http://\[::1\]) ;;
    *) fail "Refusing to send API token over plain HTTP" "Use HTTPS or a loopback URL" 2 ;;
  esac
fi

make_temp() {
  local name="$1"
  if [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
    mktemp "$XDG_RUNTIME_DIR/$name.XXXXXX" 2>/dev/null && return 0
  fi
  mktemp "/tmp/$name.XXXXXX" 2>/dev/null
}

BODY_FILE=$(make_temp rackwatch-body) || fail "Cannot create response file"
ERROR_FILE=$(make_temp rackwatch-error) || fail "Cannot create error file"
chmod 600 "$BODY_FILE" "$ERROR_FILE"

CURL_AUTH=()
if [[ -n "$TOKEN" ]]; then
  TOKEN_FILE=$(make_temp rackwatch-token) || fail "Cannot create token file"
  chmod 600 "$TOKEN_FILE"
  printf 'X-API-Key: %s\n' "$TOKEN" >"$TOKEN_FILE"
  CURL_AUTH=(--header "@$TOKEN_FILE")
fi

request() {
  local method="$1"
  local path="$2"
  local timeout="$3"
  local data="${4:-}"
  local http_code curl_exit detail
  local args=(
    --silent --show-error
    --connect-timeout 2 --max-time "$timeout"
    --proto '=http,https'
    --max-filesize 4194304
    --request "$method"
    --output "$BODY_FILE"
    --write-out '%{http_code}'
  )
  if [[ -n "$data" ]]; then
    args+=(--header 'Content-Type: application/json' --data "$data")
  fi

  : >"$BODY_FILE"
  : >"$ERROR_FILE"
  http_code=$(curl "${args[@]}" "${CURL_AUTH[@]}" --url "$URL$path" 2>"$ERROR_FILE")
  curl_exit=$?
  detail=$(<"$ERROR_FILE")

  if (( curl_exit != 0 )); then
    json_error "RackWatch request failed" "$detail" "$curl_exit"
    return "$curl_exit"
  fi
  if [[ ! "$http_code" =~ ^2[0-9][0-9]$ ]]; then
    detail=$(jq -r '.detail // .error // empty' "$BODY_FILE" 2>/dev/null || true)
    [[ -n "$detail" ]] || detail="HTTP $http_code"
    json_error "RackWatch returned HTTP $http_code" "$detail" 22
    return 22
  fi
  if ! jq -e . "$BODY_FILE" >/dev/null 2>&1; then
    json_error "RackWatch returned invalid JSON" "The response could not be parsed" 65
    return 65
  fi
  return 0
}

case "$ACTION" in
  snapshot)
    request GET '/api/v1/snapshot' 3 || exit $?
    jq -c '{ok:true,data:.}' "$BODY_FILE"
    ;;

  restart-container|start-container|stop-container)
    [[ -n "$TARGET" ]] || fail "Missing container name" "" 2
    [[ "$TARGET" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] \
      || fail "Invalid container name" "Allowed characters: letters, numbers, dot, underscore and dash" 2
    verb="${ACTION%%-container}"
    request POST "/api/v1/containers/$TARGET/$verb" 25 '{"reason":"Omarchy RackWatch bar button"}' || exit $?
    jq -c --arg action "$verb" --arg target "$TARGET" \
      '{ok:true,action:$action,target:$target,response:.}' "$BODY_FILE"
    ;;

  ack-alert)
    [[ "$TARGET" =~ ^[0-9]+$ ]] || fail "Invalid alert ID" "Expected a numeric ID" 2
    request POST "/api/v1/alerts/$TARGET/ack" 5 || exit $?
    jq -c --argjson id "$TARGET" '{ok:true,alert_id:$id,response:.}' "$BODY_FILE"
    ;;

  open-url)
    command -v xdg-open >/dev/null 2>&1 || fail "Missing dependency: xdg-open" "" 127
    xdg-open "$URL" >/dev/null 2>&1 &
    printf '%s\n' '{"ok":true}'
    ;;

  *)
    fail "Unknown action" "$ACTION" 2
    ;;
esac

