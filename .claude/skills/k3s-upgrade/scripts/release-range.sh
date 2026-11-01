#!/usr/bin/env bash
set -euo pipefail

target=${1:-}

installed=$(kubectl get nodes -o jsonpath='{range .items[*]}{.status.nodeInfo.kubeletVersion}{"\n"}{end}' | sort -u)
if [ "$(wc -l <<<"$installed")" -ne 1 ]; then
  echo "MIXED: the nodes run different versions:" >&2
  kubectl get nodes -o custom-columns=NAME:.metadata.name,VERSION:.status.nodeInfo.kubeletVersion >&2
  exit 1
fi

channels=$(curl -sf https://update.k3s.io/v1-release/channels)
channel_latest() {
  jq -r --arg name "$1" '.data[] | select(.name == $name) | .latest // empty' <<<"$channels"
}
minor_of() {
  cut -d. -f2 <<<"$1"
}
is_newer() {
  [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$1" ]
}

stable=$(channel_latest stable)
minor=$(minor_of "$installed")

if [ -z "$target" ]; then
  same_minor=$(channel_latest "v1.$minor")
  next_minor=$(channel_latest "v1.$((minor + 1))")
  if is_newer "$same_minor" "$installed"; then
    target=$same_minor
  elif [ -n "$next_minor" ] && [ "$(minor_of "$stable")" -gt "$minor" ]; then
    target=$next_minor
  else
    echo "CURRENT: $installed is the newest patch, and stable ($stable) has no newer minor"
    exit 0
  fi
fi

if ! is_newer "$target" "$installed"; then
  echo "INVALID: target $target is not newer than installed $installed" >&2
  exit 1
fi
if [ "$(minor_of "$target")" -gt $((minor + 1)) ]; then
  echo "INVALID: target $target skips a minor from installed $installed" >&2
  exit 1
fi
if is_newer "$target" "$stable"; then
  echo "WARNING: target $target is newer than stable ($stable)"
fi

echo "installed: $installed"
echo "target:    $target"
echo "stable:    $stable"
echo "range:"
gh release list -R k3s-io/k3s -L 200 --exclude-pre-releases --json tagName -q '.[].tagName' |
  while read -r tag; do
    if is_newer "$tag" "$installed" && ! is_newer "$tag" "$target"; then
      echo "$tag"
    fi
  done |
  sort -V
