---
name: node-maintenance
description: Drain a k3s node, reboot it or hold it for other work, then bring it back and wait for Longhorn to heal.
disable-model-invocation: true
argument-hint: <node> [--reboot]
---

# Node maintenance

Take one **data node** out of the cluster, do the work, and put it back.
You drive every command. The user owns two decisions: the go after
preflight, and any fix when something breaks.

Arguments: `<node>` is `cary`, `mini`, or `littlebox`. `--reboot` means the
user already chose a reboot; do not ask again.

Facts the steps depend on:

- kubectl reaches the API through the VIP `192.168.1.21`. The **VIP hosts**
  are cary (MASTER) and mini (BACKUP); littlebox runs no keepalived. If both
  VIP hosts lose keepalived, kubectl stops working.
- All three nodes run etcd. Two nodes down loses quorum.
- Longhorn has `disable-scheduling-on-cordoned-node: true`, so replicas
  cannot rebuild onto the node until you uncordon it.
- Longhorn has `node-drain-policy: block-if-contains-last-replica`, so a
  drain hangs while the node holds the only healthy replica of a volume.
- psql runs only on mini. It is down while mini is down. That is expected.

Volume health, used in several steps:

```sh
kubectl -n longhorn-system get volumes.longhorn.io \
  -o custom-columns=NAME:.metadata.name,STATE:.status.state,ROBUSTNESS:.status.robustness
```

A volume is **healthy** when it is detached or its robustness is `healthy`.

## 1. Read state

Read the node's current state before you change anything:

- `kubectl get nodes` (Ready, SchedulingDisabled)
- On a VIP host: `ssh root@<node> systemctl is-active keepalived`
- Volume health

If an earlier run stopped partway (node cordoned, or keepalived stopped),
tell the user where it stopped. Offer two paths: **resume** at the matching
step, or **abort** (go to step 5 with no reboot, then step 6).

Done when you know the node's state and the user chose fresh run, resume,
or abort.

## 2. Preflight

Check each gate. Refuse to continue if one fails, and show why:

1. `<node>` is in `kubectl get nodes`.
2. Every other node is `Ready`.
3. Every volume is healthy.
4. If `<node>` is a VIP host, keepalived is active on the other VIP host.

Then show one report: the node, what happens to the VIP, the pods that
will move (`kubectl get pods -A --field-selector spec.nodeName=<node>`),
and for mini, that psql goes down until mini returns. Ask for go. Without
`--reboot`, ask in the same question whether to reboot.

Done when every gate passes and the user said go.

## 3. Drain

```sh
ssh root@<node> systemctl stop keepalived   # VIP hosts only
kubectl cordon <node>
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data --timeout=10m
```

Done when the drain exits 0. On timeout, go to **When something breaks**
with the pods that still block the drain.

## 4. Maintenance

With a reboot:

```sh
ssh root@<node> reboot
```

Wait in the background, so the session stays responsive, until SSH answers
(`ssh -o ConnectTimeout=5 -o BatchMode=yes root@<node> true`) and the node
is `Ready`. Allow 15 minutes.

Without a reboot: tell the user the node is drained, and wait until they
say the work is done.

Done when the node is `Ready` and the work is over.

## 5. Restore

Run these in order:

```sh
kubectl uncordon <node>
kubectl -n seaweedfs rollout restart deploy/filer
ssh root@<node> systemctl start keepalived  # VIP hosts only
```

Restart the filer after every run, even when no seaweedfs pod moved. The
filer holds pod IPs and is slow to notice that a node rebooted; the restart
makes it pick up the current IPs.

Done when the node is uncordoned, the filer rollout is complete, and
keepalived is active on each VIP host.

## 6. Heal

Wait in the background until every volume is healthy. Report progress as
the count of volumes that are not yet healthy. A rebuild is **stalled**
when that count does not drop for 15 minutes.

Done when every volume is healthy. Report the final state: node Ready and
uncordoned, keepalived active on each VIP host, every volume healthy.

For an abort, run step 5 and then this step.

## When something breaks

A drain timeout, a node that is not `Ready` after 15 minutes, and a stalled
rebuild all stop the run. Then:

1. Investigate read-only: `kubectl describe`, events, Longhorn
   `volumes`/`replicas`/`engines`, and `ssh root@<node> journalctl -b`.
2. Search past incidents for the node and symptom with `jt-notion-incident`.
3. Give the user the cause you found and a proposed fix. Change nothing
   until they approve it.

For an Ubuntu release upgrade, run without a reboot, and use
`jt-ubuntu-upgrade` for the upgrade itself.
