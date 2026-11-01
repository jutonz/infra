#!/usr/bin/env bash
set -uo pipefail

node=$1
old_boot_id=$2
deadline=$((SECONDS + 900))

node_field() {
  kubectl get node "$node" --request-timeout=10s -o jsonpath="$1" 2>/dev/null
}

until [ "$(node_field '{.status.nodeInfo.bootID}')" != "$old_boot_id" ] &&
  [ "$(node_field '{.status.conditions[?(@.type=="Ready")].status}')" = True ]; do
  if ((SECONDS > deadline)); then
    echo "TIMEOUT: $node is not Ready on a new boot after 15 minutes"
    exit 1
  fi
  sleep 10
done

echo "$(date +%T) $node is Ready on a new boot"
