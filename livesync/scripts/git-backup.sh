#!/bin/sh
set -eu

cd /data/vault
export GIT_SSH_COMMAND="ssh -i /ssh/id_ed25519 -o IdentitiesOnly=yes -o UserKnownHostsFile=/ssh-known-hosts/known_hosts"

git config --global user.name livesync-server
git config --global user.email livesync-server@jutonz.com
git config --global --add safe.directory /data/vault

# Adopt the remote history without touching the working tree. The
# LiveSync CLI owns these files, and it uploads any file whose mtime is
# newer than the database copy, so a checkout here would push every note
# back to CouchDB.
if [ ! -d .git ]; then
  git init -q -b main
  git remote add origin "$GIT_REMOTE"
  git fetch -q origin main
  git reset -q origin/main
fi
echo .livesync-snapshot.json > .git/info/exclude

report_success() {
  printf '# TYPE last_success_timestamp_seconds gauge\nlast_success_timestamp_seconds %s\n' "$(date +%s)" |
    wget -q -O /dev/null --post-file=/dev/stdin "$PUSHGATEWAY_URL/metrics/job/livesync_git_backup"
}

# LiveSync stores each note's metadata in a document whose ID starts with
# "f:". Chunks and customization sync use other prefixes.
newest_note_seq() {
  wget -q -O - "http://livesync-server:${LIVESYNC_SERVER_PASSWORD}@couchdb:5984/${DATABASE}/_changes?descending=true&limit=200" |
    grep -o '"seq":"[^"]*","id":"f:' | head -n 1 | cut -d '"' -f 4
}

# The CLI copies each note's mtime from the Remote, so only ctime shows when
# the CLI last wrote here. Directory ctimes also record deletions.
newest_vault_write() {
  find /data/vault -path /data/vault/.git -prune -o -exec stat -c %Z {} + | sort -n | tail -n 1
}

last_seq=""
changed_after=0
previous_check=$(date +%s)

report_mirror_lag() {
  now=$(date +%s)
  seq=$(newest_note_seq)
  [ -n "$seq" ] || return 1
  if [ -n "$last_seq" ] && [ "$seq" != "$last_seq" ] && [ "$changed_after" -eq 0 ]; then
    changed_after=$previous_check
  fi
  last_seq=$seq
  previous_check=$now
  if [ "$changed_after" -ne 0 ] && [ "$(newest_vault_write)" -ge "$changed_after" ]; then
    changed_after=0
  fi
  lag=0
  if [ "$changed_after" -ne 0 ]; then
    lag=$((now - changed_after))
  fi
  printf '# TYPE livesync_mirror_lag_seconds gauge\nlivesync_mirror_lag_seconds %s\n' "$lag" |
    wget -q -O /dev/null --post-file=/dev/stdin "$PUSHGATEWAY_URL/metrics/job/livesync_mirror"
}

backup() {
  git add -A
  if ! git diff --cached --quiet; then
    git commit -q -m "vault backup: $(date '+%Y-%m-%d %H:%M:%S')"
  fi
  git push -q origin HEAD:main
  report_success
}

while true; do
  sleep "$INTERVAL_SECONDS"
  report_mirror_lag || echo "mirror lag check failed" >&2
  backup || echo "backup failed" >&2
done
