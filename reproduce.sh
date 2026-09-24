#!/usr/bin/env bash
# Stack: bash + curl + python3 | File: reproduce.sh
# Triggers every error code in the article against one backend and prints a table: label, HTTP status, code, error.
# The label starts with the code the article expects; the columns are what the backend answered.
#   ./reproduce.sh auth   — users, sessions, keys, malformed requests (any backend with cloud/main.js deployed)
#   ./reproduce.sh data   — class permissions, ACLs, hooks, roles (a backend prepared by seed.sh + cloud/main.js)
#   ./reproduce.sh all    — both (default)
# usage: set -a; . ./.env; set +a; ./reproduce.sh [auth|data|all] | tee results/$(date -u +%Y%m%dT%H%M%SZ).txt
set -uo pipefail
GROUP="${1:-all}"
BASE="${BASE:-https://parseapi.back4app.com}"
ANA_PASS="${ANA_PASS:-ana-pass-2026}"; BOB_PASS="${BOB_PASS:-bob-pass-2026}"
APP=(-H "X-Parse-Application-Id: $APP_ID" -H "Content-Type: application/json")
JS=("${APP[@]}" -H "X-Parse-JavaScript-Key: $JS_KEY" -H "X-Parse-Revocable-Session: 1")
MK=("${APP[@]}" -H "X-Parse-Master-Key: $MASTER_KEY")
BODY=$(mktemp); trap 'rm -f "$BODY"' EXIT
RUN=$(date -u +%Y-%m-%dT%H:%M:%SZ)
printf 'reproduce.sh · %s · backend %s · group %s\n\n' "$RUN" "${BACKEND_LABEL:-unnamed}" "$GROUP"
printf '%-3s  %-70s  %-4s  %-4s  %s\n' "#" "label (expected code · request · situation)" "HTTP" "code" "error"
printf '%-3s  %-70s  %-4s  %-4s  %s\n' "---" "----------------------------------------------------------------------" "----" "----" "-----"
n=0
probe() {  # probe <label> <curl args…> → one table row; the response body stays in $BODY for field()
  local label=$1; shift; n=$((n+1))
  local status; status=$(curl -s -o "$BODY" -w '%{http_code}' "$@")
  local line; line=$(python3 - "$BODY" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print("-\t(body is not JSON)"); sys.exit()
if isinstance(d, dict):
    err = d.get("error")
    msg = err if isinstance(err, str) else json.dumps(d, separators=(",", ":"))
    print(f'{d.get("code", "-")}\t{msg[:90]}')
else:
    print("-\t" + json.dumps(d)[:90])
PY
)
  printf '%-3s  %-70s  %-4s  %-4s  %s\n' "$n" "$label" "$status" "${line%%$'\t'*}" "${line#*$'\t'}"
}
field() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2],""))' "$BODY" "$1"; }
login() { curl -s "${JS[@]}" -X POST "$BASE/login" -d "{\"username\":\"$1\",\"password\":\"$2\"}" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("sessionToken",""))'; }

if [ "$GROUP" = auth ] || [ "$GROUP" = all ]; then
  U="probe$RANDOM$RANDOM"; PW="Probe-pass-2026"
  probe "401 · GET /classes/_User · no X-Parse-Application-Id header"          -H "Content-Type: application/json" "$BASE/classes/_User"
  probe "401 · GET /classes/_User · App ID that does not exist"                -H "X-Parse-Application-Id: not-an-app-id" -H "X-Parse-JavaScript-Key: $JS_KEY" "$BASE/classes/_User"
  probe "403 · GET /classes/_User · right App ID, wrong JavaScript key"        "${APP[@]}" -H "X-Parse-JavaScript-Key: not-the-key" "$BASE/classes/_User"
  probe "403 · GET /classes/_User · right App ID, no key at all"               "${APP[@]}" "$BASE/classes/_User"
  probe "400 · POST /login · body is not valid JSON"                           "${JS[@]}" -X POST "$BASE/login" -d '{"username": "ana", '
  probe "404 · GET /nothing-here · path that does not exist"                   "${JS[@]}" "$BASE/nothing-here"
  probe "ok  · POST /users · sign up the probe user $U"                        "${JS[@]}" -X POST "$BASE/users" -d "{\"username\":\"$U\",\"email\":\"$U@example.com\",\"password\":\"$PW\"}"
  UID_=$(field objectId); TOKEN_A=$(field sessionToken)
  probe "101 · POST /login · right username, wrong password"                   "${JS[@]}" -X POST "$BASE/login" -d "{\"username\":\"$U\",\"password\":\"wrong\"}"
  probe "101 · POST /login · username that does not exist"                    "${JS[@]}" -X POST "$BASE/login" -d '{"username":"nobody-here","password":"wrong"}'
  probe "101 · GET /classes/_User/xxxxxxxxxx · id that does not exist (master)" "${MK[@]}" "$BASE/classes/_User/xxxxxxxxxx"
  probe "202 · POST /users · same username again"                              "${JS[@]}" -X POST "$BASE/users" -d "{\"username\":\"$U\",\"email\":\"other-$U@example.com\",\"password\":\"$PW\"}"
  probe "203 · POST /users · new username, same e-mail"                        "${JS[@]}" -X POST "$BASE/users" -d "{\"username\":\"other-$U\",\"email\":\"$U@example.com\",\"password\":\"$PW\"}"
  probe "142 · POST /users · username \"ab\" (beforeSave hook wants 3+)"       "${JS[@]}" -X POST "$BASE/users" -d "{\"username\":\"ab\",\"email\":\"ab-$U@example.com\",\"password\":\"$PW\"}"
  probe "200 · POST /users · no username"                                      "${JS[@]}" -X POST "$BASE/users" -d "{\"email\":\"nouser-$U@example.com\",\"password\":\"$PW\"}"
  probe "201 · POST /users · no password"                                      "${JS[@]}" -X POST "$BASE/users" -d "{\"username\":\"nopass-$U\",\"email\":\"nopass-$U@example.com\"}"
  probe "125 · POST /users · e-mail \"not-an-email\""                          "${JS[@]}" -X POST "$BASE/users" -d "{\"username\":\"badmail-$U\",\"email\":\"not-an-email\",\"password\":\"$PW\"}"
  probe "200 · POST /login · empty body"                                       "${JS[@]}" -X POST "$BASE/login" -d '{}'
  probe "204 · POST /requestPasswordReset · no e-mail"                         "${JS[@]}" -X POST "$BASE/requestPasswordReset" -d '{}'
  probe "205 · POST /requestPasswordReset · e-mail nobody has (docs say 205)"  "${JS[@]}" -X POST "$BASE/requestPasswordReset" -d "{\"email\":\"nobody-$U@example.com\"}"
  probe "209 · GET /users/me · made-up session token"                          "${JS[@]}" -H "X-Parse-Session-Token: r:0000000000000000000000000000000f" "$BASE/users/me"
  probe "209 · GET /users/me · no session token at all"                        "${JS[@]}" "$BASE/users/me"
  probe "209 · POST /functions/whoami · no session token"                      "${JS[@]}" -X POST "$BASE/functions/whoami" -d '{}'
  probe "ok  · POST /logout · probe user"                                      "${JS[@]}" -H "X-Parse-Session-Token: $TOKEN_A" -X POST "$BASE/logout"
  probe "209 · GET /users/me · the token that just logged out"                 "${JS[@]}" -H "X-Parse-Session-Token: $TOKEN_A" "$BASE/users/me"
  probe "141 · POST /functions/doesNotExist · function not defined"            "${JS[@]}" -X POST "$BASE/functions/doesNotExist" -d '{}'
  probe "105 · POST /classes/ErrProbe · field name with a space"               "${JS[@]}" -X POST "$BASE/classes/ErrProbe" -d '{"bad key":1}'
  probe "103 · GET /classes/bad-name · class name with a hyphen"               "${JS[@]}" "$BASE/classes/bad-name"
  probe "103 · POST /classes/bad-name · create in a class name with a hyphen"  "${JS[@]}" -X POST "$BASE/classes/bad-name" -d '{"x":1}'
  # tidy up: the probe user, and the empty class the rejected 105 create left behind
  [ -n "$UID_" ] && curl -s -o /dev/null "${MK[@]}" -X DELETE "$BASE/users/$UID_"
  curl -s -o /dev/null "${MK[@]}" -X DELETE "$BASE/schemas/ErrProbe"
fi

if [ "$GROUP" = data ] || [ "$GROUP" = all ]; then
  TA=$(login ana "$ANA_PASS"); TB=$(login bob "$BOB_PASS")
  [ -n "$TA" ] && [ -n "$TB" ] || { echo "users ana/bob missing: run ./seed.sh first" >&2; exit 1; }
  probe "101 · GET /classes/Note · anonymous, CLP requires a session"          "${JS[@]}" "$BASE/classes/Note"
  probe "101 · POST /classes/Note · anonymous, CLP requires a session"         "${JS[@]}" -X POST "$BASE/classes/Note" -d '{"text":"drive-by"}'
  probe "101 · GET /classes/Note/xxxxxxxxxx · anonymous, id does not exist"    "${JS[@]}" "$BASE/classes/Note/xxxxxxxxxx"
  probe "101 · GET /classes/Note/xxxxxxxxxx · ana, id does not exist"          "${JS[@]}" -H "X-Parse-Session-Token: $TA" "$BASE/classes/Note/xxxxxxxxxx"
  probe "119 · GET /classes/Note?count=1 · anonymous"                          "${JS[@]}" "$BASE/classes/Note?count=1&limit=0"
  probe "119 · GET /classes/Note?count=1 · ana (CLP has no count entry)"       "${JS[@]}" -H "X-Parse-Session-Token: $TA" "$BASE/classes/Note?count=1&limit=0"
  probe "ok  · POST /classes/Note · ana creates a note (hook stamps her ACL)"  "${JS[@]}" -H "X-Parse-Session-Token: $TA" -X POST "$BASE/classes/Note" -d '{"text":"ana private"}'
  NOTE=$(field objectId)
  probe "101 · GET /classes/Note/<ana's note> · bob (ACL hides the row)"       "${JS[@]}" -H "X-Parse-Session-Token: $TB" "$BASE/classes/Note/$NOTE"
  probe "101 · PUT /classes/Note/<ana's note> · bob (ACL hides the row)"       "${JS[@]}" -H "X-Parse-Session-Token: $TB" -X PUT "$BASE/classes/Note/$NOTE" -d '{"text":"bob was here"}'
  probe "ok  · GET /classes/Note/<ana's note> · ana reads her own note"        "${JS[@]}" -H "X-Parse-Session-Token: $TA" "$BASE/classes/Note/$NOTE"
  probe "119 · GET /classes/Vault · ana, CLP allows nobody"                    "${JS[@]}" -H "X-Parse-Session-Token: $TA" "$BASE/classes/Vault"
  probe "119 · GET /classes/Vault · anonymous, CLP allows nobody"              "${JS[@]}" "$BASE/classes/Vault"
  probe "119 · POST /classes/Vault · ana, CLP allows nobody"                   "${JS[@]}" -H "X-Parse-Session-Token: $TA" -X POST "$BASE/classes/Vault" -d '{"secret":"x"}'
  probe "119 · POST /functions/moderatorList · ana is not a moderator"         "${JS[@]}" -H "X-Parse-Session-Token: $TA" -X POST "$BASE/functions/moderatorList" -d '{}'
  probe "209 · POST /functions/moderatorList · no session token"               "${JS[@]}" -X POST "$BASE/functions/moderatorList" -d '{}'
  probe "ok  · POST /functions/moderatorList · bob is a moderator"             "${JS[@]}" -H "X-Parse-Session-Token: $TB" -X POST "$BASE/functions/moderatorList" -d '{}'
  probe "206 · POST /classes/Note · master key, no session (hook needs a user)" "${MK[@]}" -X POST "$BASE/classes/Note" -d '{"text":"no owner"}'
  probe "141 · POST /classes/Note · master key, owner is a plain object (hook throws)" "${MK[@]}" -X POST "$BASE/classes/Note" -d '{"text":"bad owner","owner":{"foo":"bar"}}'
  probe "111 · POST /classes/Note · ana, text is a number not a string"        "${JS[@]}" -H "X-Parse-Session-Token: $TA" -X POST "$BASE/classes/Note" -d '{"text":123}'
  [ -n "$NOTE" ] && curl -s -o /dev/null "${JS[@]}" -H "X-Parse-Session-Token: $TA" -X DELETE "$BASE/classes/Note/$NOTE"
fi
