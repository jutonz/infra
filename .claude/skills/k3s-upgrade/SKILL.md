---
name: k3s-upgrade
description: Review every k3s release note between the installed and target version, then upgrade the cluster one node at a time.
disable-model-invocation: true
argument-hint: "[<version>]"
---

# k3s upgrade

Move the cluster one **hop**: from the installed k3s version to one target
version, on every node. You drive every command. The user owns the go, each
fix, and each **unclear** note they accept.

Argument: `<version>` is a k3s tag such as `v1.36.5+k3s1`. Without it, the
script picks the target.

## 1. Target and preflight

```sh
.claude/skills/k3s-upgrade/scripts/release-range.sh [<version>]
```

The script prints the installed version, the target, and the release range.
A hop moves to the newest patch of the current minor, or to the next minor
once the cluster is on the newest patch. It refuses a skipped minor.

Stop on these outputs: `CURRENT` (nothing to do), `MIXED` (a node is
on another version; ask the user), `INVALID`. On `WARNING` (the target is
not yet on the stable channel), ask the user to confirm the target.

Then check one gate: on every node,
`ssh root@<node> cat /etc/rancher/k3s/config.yaml` lists both `jutonz.com`
and `192.168.1.21` under `tls-san`. The install in step 5 rewrites the
systemd unit without flags, so a SAN that is missing here is lost. If the
gate fails, tell the user to run `ansible/k3s-server/update.sh`.

Done when you have the target and the range, and the gate passes.

## 2. Branch

```sh
git switch main && git pull && git switch -c jt-k3s-<target>
```

## 3. Impact review

Dispatch a general-purpose subagent. Give it the brief in
[`review.md`](review.md), plus the installed version, the target, the
range, and the review file path `docs/k3s-upgrades/<target>.md`.

When it returns, count the notes in the sources yourself. If your count
differs from its N, send it back with the missing notes.

Done when the review file holds one verdict for each note.

## 4. Gate

Show the user the **affects** and **unclear** rows.

- For each **affects** note that needs a change, propose the fix. Apply it
  after the user approves it, and commit it.
- Investigate each **unclear** note again until it becomes **affects** or
  **no effect**. The user accepts each one that stays **unclear**.

Update the review file as verdicts change, and commit it. Then ask for go.

Done when no **affects** note is left without a fix or an accept, the user
accepted each **unclear** note, and the user said go.

## 5. Upgrade the nodes

On the first node, take a snapshot. k3s appends the node and a timestamp
to the name, so record the full path from the `ls` in the review file:

```sh
ssh root@littlebox k3s etcd-snapshot save --name pre-<target>
ssh root@littlebox ls /var/lib/rancher/k3s/server/db/snapshots/pre-*
```

Upgrade the nodes in this order:

1. littlebox, which is not a VIP host.
2. The VIP host that does not hold the VIP.
3. The VIP host that holds the VIP. Find it with
   `ssh root@<host> ip -4 addr | grep -c 192.168.1.21` on cary and mini.

For each node, follow `.claude/skills/node-maintenance/SKILL.md` without a
reboot. The go from step 4 is the go for its preflight. Its work step is:

```sh
ssh root@<node> 'curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=<target> sh -s - server'
kubectl get node <node> -o jsonpath='{.status.nodeInfo.kubeletVersion}'
```

The work is over when the node reports the target and is `Ready`.

After the first node heals, show the user its state and the step 6
checks, and ask whether to continue.

Done when every node reports the target and every Longhorn volume is
healthy.

## 6. Verify

- Every node in `kubectl get nodes` is `Ready` at the target.
- `kubectl -n kube-system rollout status` completes for `deploy/traefik`,
  `deploy/coredns`, `deploy/metrics-server`, and
  `deploy/local-path-provisioner`.
- `curl -sS -o /dev/null -w '%{http_code}' https://grafana.home.jutonz.com`
  returns 2xx or 3xx.
- `kubectl get pods -A | grep -E 'CrashLoopBackOff|Error'` finds nothing.

Write the result, the snapshot name, and anything the user accepted into
`Outcome` in the review file. Commit, push, and open the PR.

Done when every check passes and the PR is open.

## When something breaks

A failed install, a node that is not `Ready`, a failed rollout, and a
failed check all stop the run. Do not roll back on your own. Then:

1. Investigate read-only: `kubectl describe`, events, and
   `ssh root@<node> journalctl -u k3s -b`.
2. Search past incidents with `jt-notion-incident`.
3. Give the user the cause and a proposed fix. Also give the rollback:
   the install command with the installed version, and for etcd damage,
   `k3s server --cluster-reset --cluster-reset-restore-path=<snapshot>`
   with the snapshot path from step 5. Change nothing until they approve.
