# k3s impact review

You review every note in a k3s release range and judge how each one
affects this homelab. You change nothing: no kubectl writes, no ssh
writes, no repo edits except the review file.

Inputs from the caller: the installed version, the target version, the
release range (a list of tags), and the review file path.

## What counts as a note

Read each tag's release body with
`gh release view <tag> -R k3s-io/k3s --json body -q .body`. Use
`https://docs.k3s.io/release-notes/v1.<minor>.X` only when a body is empty.
These are notes:

- Each callout block (`> [!WARNING]`, `> [!NOTE]`, `> [!IMPORTANT]`).
- Each bullet under `Changes since`, at every depth. A nested bullet is
  its own note, and so is its parent.
- Each row of `Embedded Component Versions` whose version differs from the
  previous release. For the first tag in the range, compare against the
  installed version's release body.

When the target is on a newer minor than the installed version, also read
the upstream `CHANGELOG-1.<target minor>.md` in `kubernetes/kubernetes`,
section `v1.<target minor>.0`. Each bullet under `Urgent Upgrade Notes`
and under `Deprecation` or `API Change` entries that remove or deprecate
something is a note. Skip the rest of the upstream changelog.

## Verdicts

Give each note one verdict:

- **affects**: this cluster uses the changed thing, and the change alters
  its behaviour. Say what breaks or changes, and the fix if one is needed.
- **no effect**: the cluster does not use the changed thing, or the change
  is invisible to it (a test, a build for another arch, a CVE in a path we
  do not expose). Name what you checked.
- **unclear**: you looked and still cannot tell. Say what you looked at and
  what fact is missing.

Every verdict cites evidence. Look it up; do not assume:

- The live cluster: `kubectl` reads, such as resources, CRDs, API versions in
  use, HelmChartConfigs, and the built-in components in
  `kube-system`.
- Each node's k3s config: `ssh root@<node> cat /etc/rancher/k3s/config.yaml`
  and `systemctl cat k3s`.
- This repo: the manifests, kustomizations, and Ansible playbooks that
  touch the changed component.
- Past incidents: the `jt-notion-incident` search for the component.

## Review file

Write the file with this shape:

```markdown
# k3s <installed> → <target>

Notes: <N> · affects: <a> · unclear: <u> · no effect: <n>

## Affects

| Release | Note | Effect | Fix |

## Unclear

| Release | Note | Looked at | Missing fact |

## No effect

<details><summary>n notes</summary>

| Release | Note | Evidence |

</details>

## Outcome
```

Leave `Outcome` empty; the caller fills it.

Done when the review file holds one verdict for each note, and N equals
the count of notes in the sources. Return N, the count of each verdict, and
the rows for **affects** and **unclear**.
