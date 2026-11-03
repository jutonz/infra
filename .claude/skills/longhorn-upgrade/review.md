# Longhorn impact review

You review the notes in a Longhorn release range and judge how each one
affects this homelab. You change nothing: no kubectl writes, no ssh
writes, no repo edits except the review file.

Inputs from the caller: the installed version, the target version, the
release range (a list of tags), and the review file path.

## What counts as a note

Read each tag's release body with
`gh release view <tag> -R longhorn/longhorn --json body -q .body`. These
are notes:

- Each item under `Breaking Changes`, `Upgrade`, and
  `Post-Release Known Issues`, at every depth.
- Each heading under `Primary Highlights`, at the deepest level. Judge the
  heading, not each bullet beneath it.
- Each item under `Resolved Issues` → `Bug` that names a feature this
  cluster uses: a v1 volume, a backup to S3, a recurring job, a node drain,
  an engine upgrade, or the CSI driver. Skip the rest of
  `Resolved Issues`.

Also read the target's docs, where `<v>` is the target without the `v`,
such as `1.13.0`:

- `https://longhorn.io/docs/<v>/important-notes/`: each item is a note.
- `https://longhorn.io/docs/<v>/deploy/upgrade/`: each prerequisite and
  each warning is a note.

## Verdicts

Give each note one verdict:

- **affects**: this cluster uses the changed thing, and the change alters
  its behaviour. Say what breaks or changes, and the fix if one is needed.
- **no effect**: the cluster does not use the changed thing, or the change
  is invisible to it (the V2 data engine, a feature that is off). Name
  what you checked.
- **unclear**: you looked and still cannot tell. Say what you looked at and
  what fact is missing.

Every verdict cites evidence. Look it up; do not assume:

- The live cluster: `kubectl -n longhorn-system get` on
  `settings.longhorn.io`, `volumes.longhorn.io` (the data engine, the
  frontend, the access mode), `recurringjobs.longhorn.io`,
  `backuptargets.longhorn.io`, `nodes.longhorn.io`, and the
  StorageClasses.
- This repo: `longhorn/` and every PVC that uses a Longhorn StorageClass.
- Past incidents: the `jt-notion-incident` search for Longhorn.

## Review file

Write the file with this shape:

```markdown
# Longhorn <installed> → <target>

Notes: <N> · affects: <a> · unclear: <u> · no effect: <n>

## Affects

| Source | Note | Effect | Fix |

## Unclear

| Source | Note | Looked at | Missing fact |

## No effect

<details><summary>n notes</summary>

| Source | Note | Evidence |

</details>

## Outcome
```

`Source` is the release tag or the docs page. Leave `Outcome` empty; the
caller fills it.

Done when the review file holds one verdict for each note, and N equals
the count of notes in the sources. Return N, the count of each verdict, and
the rows for **affects** and **unclear**.
