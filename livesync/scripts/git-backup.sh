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
  backup || echo "backup failed" >&2
done
