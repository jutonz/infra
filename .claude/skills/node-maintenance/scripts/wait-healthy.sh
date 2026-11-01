#!/usr/bin/env bash
set -uo pipefail

stall_after=900

unhealthy_volumes() {
  kubectl -n longhorn-system get volumes.longhorn.io --request-timeout=10s \
    -o jsonpath='{range .items[*]}{.metadata.name} {.status.state} {.status.robustness}{"\n"}{end}' |
    awk '$2 != "detached" && $3 != "healthy" { print $1 }'
}

rebuild_progress() {
  kubectl -n longhorn-system get engines.longhorn.io --request-timeout=10s \
    -o jsonpath='{range .items[*]}{.spec.volumeName}{range .status.rebuildStatus.*} {.progress}%{end}{"\n"}{end}' |
    awk 'NF > 1'
}

last_state=""
last_change=$SECONDS

while :; do
  if ! volumes=$(unhealthy_volumes); then
    sleep 30
    continue
  fi
  if [ -z "$volumes" ]; then
    echo "$(date +%T) every volume is healthy"
    exit 0
  fi

  state="$(grep -c . <<<"$volumes") not healthy; $(rebuild_progress | paste -sd ';' -)"
  if [ "$state" != "$last_state" ]; then
    echo "$(date +%T) $state"
    last_state=$state
    last_change=$SECONDS
  fi
  if ((SECONDS - last_change > stall_after)); then
    echo "STALLED: no change for 15 minutes: $state"
    exit 1
  fi
  sleep 30
done
