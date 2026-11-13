#!/bin/sh
set -eu

cli="node /app/dist/index.cjs"
settings=/data/db/settings.json
mkdir -p /data/db /data/vault

# Since 1.0.45 the CLI refuses setup and remote-set when the database
# directory holds runtime state from an older CLI. The settings do not
# depend on that state, so build them against an empty directory.
setup_db=$(mktemp -d)
trap 'rm -rf "$setup_db"' EXIT

# fetch and rebuild switch to a new local database and record it in these
# settings. Setup resets them from the Setup URI, so carry them over.
previous="$setup_db/previous-settings.json"
if [ -f "$settings" ]; then
  cp "$settings" "$previous"
fi

$cli init-settings "$settings" --force
printf '%s\n' "$SETUP_URI_PASSPHRASE" | $cli "$setup_db" --settings "$settings" setup "$SETUP_URI"

node -e '
const fs = require("fs");
const [path, previousPath] = process.argv.slice(1);
const settings = JSON.parse(fs.readFileSync(path));
Object.assign(settings, { liveSync: true, syncOnStart: true });
if (fs.existsSync(previousPath)) {
  const previous = JSON.parse(fs.readFileSync(previousPath));
  for (const key of ["additionalSuffixOfDatabaseName", "pathNormalizationVersion"]) {
    if (key in previous) settings[key] = previous[key];
  }
}
fs.writeFileSync(path, JSON.stringify(settings, null, 2));
' "$settings" "$previous"

remote_id=$($cli "$setup_db" --settings "$settings" remote-ls | awk -F '\t' '$3 == "active" { print $1 }')
$cli "$setup_db" --settings "$settings" remote-set "$remote_id" \
  "sls+http://livesync-server:${LIVESYNC_SERVER_PASSWORD}@couchdb:5984/?db=${DATABASE}"
