#!/usr/bin/env bash
set -uo pipefail

stall_after=900

default_engine_image() {
  kubectl -n longhorn-system get ds longhorn-manager --request-timeout=10s -o json |
    jq -r '.spec.template.spec.containers[] | select(.name == "longhorn-manager") | .command as $c
      | $c[($c | index("--engine-image")) + 1]'
}

stale_volumes() {
  kubectl -n longhorn-system get volumes.longhorn.io --request-timeout=10s \
    -o jsonpath='{range .items[*]}{.metadata.name} {.spec.image} {.status.currentImage}{"\n"}{end}' |
    awk -v image="$1" '$2 != image || $3 != image { print $1 }'
}

if ! image=$(default_engine_image) || [ -z "$image" ]; then
  echo "cannot read --engine-image from ds/longhorn-manager" >&2
  exit 1
fi
echo "$(date +%T) default engine image: $image"

last_state=""
last_change=$SECONDS

while :; do
  if ! volumes=$(stale_volumes "$image"); then
    sleep 30
    continue
  fi
  if [ -z "$volumes" ]; then
    echo "$(date +%T) every volume runs $image"
    exit 0
  fi

  state="$(grep -c . <<<"$volumes") on an old engine: $(paste -sd ' ' - <<<"$volumes")"
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
