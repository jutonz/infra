---
name: longhorn-upgrade
description: Review the Longhorn release notes between the installed and target version, then upgrade the manager and every volume engine.
disable-model-invocation: true
argument-hint: "[<version>]"
---

# Longhorn upgrade

Move Longhorn one **hop**: from the installed version to one target
version, for the manager and for the engine of every volume. You drive
every command. The user owns the go, each fix, each manual backup, and
each **unclear** note they accept.

Argument: `<version>` is a Longhorn tag such as `v1.13.0`. Without it, the
script picks the target.

Volume health, used in several steps, is the same as in
`.claude/skills/node-maintenance/SKILL.md`: a volume is **healthy** when it
is detached or its robustness is `healthy`.

## 1. Target and preflight

```sh
.claude/skills/longhorn-upgrade/scripts/release-range.sh [<version>]
```

The script prints the installed version, the target, and the release range.
A hop moves to the newest patch of the current minor, or to the newest
patch of the next minor once Longhorn is on the newest patch. It refuses a
skipped minor.

Stop on these outputs: `CURRENT` (nothing to do), `INVALID`, and
`KUBERNETES` (the target needs a newer Kubernetes; tell the user to run
`/k3s-upgrade` first).

Then check each gate, and stop with the reason if one fails:

1. Every volume is healthy, and none is rebuilding.
2. Every node in `kubectl -n longhorn-system get nodes.longhorn.io` is
   `Ready` and schedulable, and no node in `kubectl get nodes` is cordoned.
3. `kubectl -n longhorn-system get settings.longhorn.io
   concurrent-automatic-engine-upgrade-per-node-limit -o jsonpath='{.value}'`
   is greater than 0. Step 6 depends on it.

Done when you have the target and the range, and every gate passes.

## 2. Backups

The daily `s3-backup` recurring job backs up each volume with the label
`recurring-job-group.longhorn.io/s3-backup: enabled`. Read each volume's
newest backup:

```sh
kubectl -n longhorn-system get volumes.longhorn.io \
  -o 'custom-columns=NAME:.metadata.name,GROUP:.metadata.labels.recurring-job-group\.longhorn\.io/s3-backup,LAST:.status.lastBackupAt'
```

Show the user two lists: the volumes in the group whose newest backup is
older than 26 hours, and the volumes outside the group. The second list is
for information only.

For each stale volume the user wants backed up, create a snapshot and a
backup of it, as in
`https://longhorn.io/docs/<target without v>/snapshots-and-backups/backup-and-restore/create-a-backup/`:

```sh
kubectl -n longhorn-system create -f - <<EOF
apiVersion: longhorn.io/v1beta2
kind: Snapshot
metadata:
  name: pre-<target>-<volume>
spec:
  volume: <volume>
  createSnapshot: true
---
apiVersion: longhorn.io/v1beta2
kind: Backup
metadata:
  name: pre-<target>-<volume>
  labels:
    backup-volume: <volume>
spec:
  snapshotName: pre-<target>-<volume>
EOF
```

Wait until `kubectl -n longhorn-system get backups.longhorn.io
pre-<target>-<volume>` shows `Completed`.

Then take a Longhorn system backup, which the upgrade docs recommend. It
saves Longhorn's own resources and points at the volume backups above:

```sh
kubectl -n longhorn-system create -f - <<EOF
apiVersion: longhorn.io/v1beta2
kind: SystemBackup
metadata:
  name: pre-<target>
spec:
  volumeBackupPolicy: disabled
EOF
```

Wait until `kubectl -n longhorn-system get systembackups.longhorn.io
pre-<target>` shows `Ready`.

Done when every volume in the group has a backup newer than 26 hours, or
the user chose to skip it, and the system backup is `Ready`.

## 3. Branch

```sh
git switch main && git pull && git switch -c jt-longhorn-<target>
```

## 4. Impact review

Dispatch a general-purpose subagent. Give it the brief in
[`review.md`](review.md), plus the installed version, the target, the
range, and the review file path `docs/longhorn-upgrades/<target>.md`.

When it returns, count the notes in the sources yourself. If your count
differs from its N, send it back with the missing notes.

Done when the review file holds one verdict for each note.

## 5. Gate

Show the user the **affects** and **unclear** rows, and the exact
`kubectl apply` command from step 6.

- For each **affects** note that needs a change, propose the fix. Apply it
  after the user approves it, and commit it.
- Investigate each **unclear** note again until it becomes **affects** or
  **no effect**. The user accepts each one that stays **unclear**.

Update the review file as verdicts change, and commit it. Then ask for go.

Done when no **affects** note is left without a fix or an accept, the user
accepted each **unclear** note, and the user said go.

## 6. Upgrade

The apply upgrades the manager on every node at once. After the go, run
steps 6 and 7 without asking again, unless something breaks.

```sh
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/<target>/deploy/longhorn.yaml
kubectl -n longhorn-system rollout status ds/longhorn-manager --timeout=15m
kubectl -n longhorn-system get deploy -o name | xargs -n1 kubectl -n longhorn-system rollout status --timeout=10m
kubectl -n longhorn-system get settings.longhorn.io current-longhorn-version -o jsonpath='{.value}'
```

The manager part is over when every rollout completes and
`current-longhorn-version` equals the target.

Then run the engine wait in the background:

```sh
.claude/skills/longhorn-upgrade/scripts/wait-engines.sh
```

It reads the new default engine image from `ds/longhorn-manager` and prints
the volumes on an old engine whenever that list changes. It exits 0 when
every volume runs the new image. It exits 1 when the list is **stalled**:
no change for 15 minutes.

On a stall, upgrade each listed volume by hand, one at a time. Patch the
volume, then wait until `.status.currentImage` equals the new image:

```sh
kubectl -n longhorn-system patch volumes.longhorn.io <volume> --type merge \
  -p '{"spec":{"image":"<new engine image>"}}'
```

A live upgrade needs a healthy volume. When a volume stays on the old
engine after the patch, go to **When something breaks**: an offline
upgrade detaches its workload, and the user decides on that.

Then run `.claude/skills/node-maintenance/scripts/wait-healthy.sh` in the
background.

Done when every volume runs the new engine image and every volume is
healthy.

## 7. Verify

- `current-longhorn-version` equals the target.
- Every volume runs the new engine image and is healthy.
- Every pod in `kubectl -n longhorn-system get pods` is `Running` or
  `Completed`.
- `curl -sS -o /dev/null -w '%{http_code}' https://longhorn.home.jutonz.com`
  returns 2xx or 3xx.
- `kubectl get pods -A | grep -E 'CrashLoopBackOff|Error'` finds nothing.

Then delete each engine image that no volume uses. List them with
`kubectl -n longhorn-system get engineimages.longhorn.io`, and delete each
one whose `REFCOUNT` is 0 and whose image is not the new default.

Write the result, the backups from step 2, and anything the user
accepted into `Outcome` in the review file. Commit, push, and open the PR
with the title `Upgrade Longhorn to <target>`.

Done when every check passes, no old engine image is left, and the PR is
open.

## When something breaks

A failed apply, a rollout that times out, a version that does not change,
a stalled engine upgrade, a stalled rebuild, and a failed check all stop
the run. Change nothing on your own. Then:

1. Investigate read-only: `kubectl describe`, events, the
   `longhorn-manager` logs, and Longhorn `volumes`, `engines`, and
   `replicas`.
2. Search past incidents in the Obsidian notes at
   `~/code/jutonz/notes/Tech/Incidents/`.
3. Give the user the cause and a proposed fix. Change nothing until they
   approve.

Longhorn does not support a downgrade. Propose a re-apply of the installed
version's `longhorn.yaml` only when the new manager refused the upgrade
and `current-longhorn-version` still shows the installed version. A
restore from the step 2 backups is the last resort, and the user approves
it volume by volume.
