#!/bin/sh
set -eu

couch="http://couchdb:5984"
auth="${COUCHDB_ADMIN_USER}:${COUCHDB_ADMIN_PASSWORD}"

until curl -sf -u "$auth" "$couch/_up" >/dev/null; do
  sleep 2
done

put() {
  curl -sf -u "$auth" -X PUT -H 'Content-Type: application/json' "$couch/$1" ${2:+-d "$2"} >/dev/null
}

exists() {
  curl -sf -u "$auth" -o /dev/null "$couch/$1"
}

exists "$DATABASE" || put "$DATABASE"

upsert_user() {
  name="$1"
  password="$2"
  id="org.couchdb.user:$name"
  rev=$(curl -sf -u "$auth" "$couch/_users/$id" | sed -n 's/.*"_rev":"\([^"]*\)".*/\1/p' || true)
  put "_users/$id" "{${rev:+\"_rev\":\"$rev\",}\"name\":\"$name\",\"password\":\"$password\",\"roles\":[],\"type\":\"user\"}"
}

upsert_user livesync "$LIVESYNC_PASSWORD"
upsert_user livesync-server "$LIVESYNC_SERVER_PASSWORD"

put "$DATABASE/_security" '{"admins":{"names":[],"roles":[]},"members":{"names":["livesync","livesync-server"],"roles":[]}}'

echo "provisioned $DATABASE"
