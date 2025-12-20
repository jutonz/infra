#!/bin/bash
set -eu

export DEBIAN_FRONTEND=noninteractive

apt-get update -qq

UPGRADABLE=$(apt-get -s dist-upgrade | grep "^Inst" | wc -l)

cat <<EOF
# HELP apt_upgradable_packages Number of apt packages that can be upgraded
# TYPE apt_upgradable_packages gauge
apt_upgradable_packages ${UPGRADABLE}
EOF
