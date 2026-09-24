#!/usr/bin/env bash
# Stack: bash + curl + python3 | File: seed.sh
# Prepares a backend for the "data" group of reproduce.sh: users ana and bob, a "moderator" role containing bob,
# a Note class whose class-level permissions require a session, and a Vault class that allows nobody.
# Idempotent: re-running it looks things up instead of creating them twice.
# usage: set -a; . ./.env; set +a; ./seed.sh
set -euo pipefail
BASE="${BASE:-https://parseapi.back4app.com}"
ANA_PASS="${ANA_PASS:-ana-pass-2026}"; BOB_PASS="${BOB_PASS:-bob-pass-2026}"
JS=(-H "X-Parse-Application-Id: $APP_ID" -H "X-Parse-JavaScript-Key: $JS_KEY" -H "Content-Type: application/json")
MK=(-H "X-Parse-Application-Id: $APP_ID" -H "X-Parse-Master-Key: $MASTER_KEY" -H "Content-Type: application/json")

mkuser() {  # mkuser <name> <password> → objectId (signs up, or looks the user up if the signup answers 202)
  local id; id=$(curl -s "${JS[@]}" -X POST "$BASE/users" -d "{\"username\":\"$1\",\"password\":\"$2\",\"email\":\"$1@example.com\"}" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("objectId",""))')
  [ -n "$id" ] || id=$(curl -s -G "${MK[@]}" "$BASE/users" --data-urlencode "where={\"username\":\"$1\"}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["results"][0]["objectId"])')
  echo "$id"
}
ANA_ID=$(mkuser ana "$ANA_PASS"); BOB_ID=$(mkuser bob "$BOB_PASS")
echo "ana=$ANA_ID bob=$BOB_ID"

ROLE=$(curl -s -G "${MK[@]}" "$BASE/roles" --data-urlencode 'where={"name":"moderator"}' | python3 -c 'import json,sys; r=json.load(sys.stdin)["results"]; print(r[0]["objectId"] if r else "")')
if [ -z "$ROLE" ]; then
  ROLE=$(curl -s "${MK[@]}" -X POST "$BASE/roles" -d "{\"name\":\"moderator\",\"ACL\":{\"*\":{\"read\":true}},\"users\":{\"__op\":\"AddRelation\",\"objects\":[{\"__type\":\"Pointer\",\"className\":\"_User\",\"objectId\":\"$BOB_ID\"}]}}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["objectId"])')
fi
echo "role moderator=$ROLE (bob is a member)"

ensure_class() {  # ensure_class <name> <schema JSON> — creates the class with its CLP if it does not exist
  local status; status=$(curl -s -o /dev/null -w '%{http_code}' "${MK[@]}" "$BASE/schemas/$1")
  if [ "$status" = 200 ]; then echo "class $1 exists, left as is"; else
    curl -s "${MK[@]}" -X POST "$BASE/schemas/$1" -d "$2" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("created", d.get("className", d), "CLP", json.dumps(d.get("classLevelPermissions")))'
  fi
}
# Note: every operation needs a session. Written exactly as the article's lockdown script wrote it: without a "count" key,
# which the schema API stores as count: {} — nobody may count, not even a logged-in user (that is the 119 the table shows).
ensure_class Note '{"className":"Note","fields":{"text":{"type":"String"},"owner":{"type":"Pointer","targetClass":"_User"}},"classLevelPermissions":{"find":{"requiresAuthentication":true},"get":{"requiresAuthentication":true},"create":{"requiresAuthentication":true},"update":{"requiresAuthentication":true},"delete":{"requiresAuthentication":true},"addField":{}}}'
# Vault: nobody may do anything through a client key. Every operation answers 119.
ensure_class Vault '{"className":"Vault","fields":{"secret":{"type":"String"}},"classLevelPermissions":{"find":{},"count":{},"get":{},"create":{},"update":{},"delete":{},"addField":{}}}'
echo "now deploy cloud/main.js in the dashboard (Cloud Code → Deploy, twice on a fresh backend) and run ./reproduce.sh data"
