#!/bin/sh
set -eu

cli="node /app/dist/index.cjs"
settings=/data/db/settings.json
mkdir -p /data/db /data/vault

$cli init-settings "$settings" --force
printf '%s\n' "$SETUP_URI_PASSPHRASE" | $cli /data/db --settings "$settings" setup "$SETUP_URI"

node -e '
const fs = require("fs");
const settings = JSON.parse(fs.readFileSync(process.argv[1]));
Object.assign(settings, { liveSync: true, syncOnStart: true });
fs.writeFileSync(process.argv[1], JSON.stringify(settings, null, 2));
' "$settings"

remote_id=$($cli /data/db --settings "$settings" remote-ls | awk -F '\t' '$3 == "active" { print $1 }')
$cli /data/db --settings "$settings" remote-set "$remote_id" \
  "sls+http://livesync-server:${LIVESYNC_SERVER_PASSWORD}@couchdb:5984/?db=${DATABASE}"
