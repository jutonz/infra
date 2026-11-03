#!/usr/bin/env bash
set -euo pipefail

target=${1:-}

installed=$(kubectl -n longhorn-system get settings.longhorn.io current-longhorn-version -o jsonpath='{.value}')
kubernetes=$(kubectl get nodes -o jsonpath='{range .items[*]}{.status.nodeInfo.kubeletVersion}{"\n"}{end}' | sort -V | head -1)

minor_of() {
  cut -d. -f2 <<<"$1"
}
patch_series() {
  cut -d. -f1-2 <<<"$1"
}
is_newer() {
  [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$1" ]
}

# Longhorn publishes patches of older minors after newer minors, so sort by
# version, never by release date.
releases=$(gh release list -R longhorn/longhorn -L 200 --exclude-pre-releases --json tagName -q '.[].tagName' | sort -V)
newest_of() {
  grep "^$1\." <<<"$releases" | tail -1
}

series=$(patch_series "$installed")
next_series="v1.$(($(minor_of "$installed") + 1))"

if [ -z "$target" ]; then
  same_minor=$(newest_of "$series")
  next_minor=$(newest_of "$next_series" || true)
  if is_newer "$same_minor" "$installed"; then
    target=$same_minor
  elif [ -n "$next_minor" ]; then
    target=$next_minor
  else
    echo "CURRENT: $installed is the newest patch, and $next_series has no release"
    exit 0
  fi
fi

if ! grep -qx "$target" <<<"$releases"; then
  echo "INVALID: target $target is not a stable Longhorn release" >&2
  exit 1
fi
if ! is_newer "$target" "$installed"; then
  echo "INVALID: target $target is not newer than installed $installed" >&2
  exit 1
fi
if [ "$(minor_of "$target")" -gt $(($(minor_of "$installed") + 1)) ]; then
  echo "INVALID: target $target skips a minor from installed $installed" >&2
  exit 1
fi

kube_minimum=$(curl -sf "https://raw.githubusercontent.com/longhorn/longhorn/$target/chart/Chart.yaml" |
  sed -n 's/^kubeVersion: *">=\([0-9.]*\).*"/v\1/p')
if [ -z "$kube_minimum" ]; then
  echo "INVALID: cannot read kubeVersion from the $target chart" >&2
  exit 1
fi
if is_newer "$kube_minimum" "${kubernetes%%+*}"; then
  echo "KUBERNETES: $target needs Kubernetes $kube_minimum, and the oldest node runs $kubernetes" >&2
  exit 1
fi

echo "installed:  $installed"
echo "target:     $target"
echo "kubernetes: $kubernetes (target needs $kube_minimum)"
echo "range:"
while read -r tag; do
  if is_newer "$tag" "$installed" && ! is_newer "$tag" "$target"; then
    echo "$tag"
  fi
done <<<"$releases"
