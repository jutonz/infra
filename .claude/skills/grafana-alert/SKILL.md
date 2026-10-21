---
name: grafana-alert
description: List the Grafana alerts that fire at grafana.home.jutonz.com, with each rule's PromQL and live value. Use when the user says Grafana alerts fire, asks which alerts are active, or asks whether an alert has resolved.
---

# Grafana alerts

The Grafana HTTP API needs a login that this session does not have. Read alert state from Grafana's SQLite database in the pod instead. The user has authorised `kubectl exec` into `deploy/grafana` for this. Leave the admin password in the `config` secret alone: the permission classifier blocks that read as credential exploration.

## Steps

1. **List.** Run `.claude/skills/grafana-alert/list-alerts.sh` from the repo root. It copies `grafana.db` into a temp directory, prints each instance whose latest state is not `Normal`, and deletes the copy. Pass `--all` to include `Normal` instances. Done when you have the list of firing, pending, NoData, and Error instances.

2. **Confirm live.** The list comes from state history, which records only transitions, so an instance can read `Alerting` after its series went away. Run each instance's `expr` against Prometheus at `https://prometheus.home.jutonz.com/api/v1/query` (no auth), filtered by the instance's labels. Done when every instance has a current value and a verdict: still firing, or resolved.

3. **Report.** Give the user each firing alert with its start time, current value, and verdict, before you investigate any cause.

## Reference

- The `values` line shows the result of each query ref at the transition, such as `A=45.17, C=1`. `C` is the threshold condition: `1` means firing.
- Rules in the `Scripts` folder alert on metrics that cron jobs and sidecars push to the Pushgateway. Find the producer with `grep -rn '<job name>'` on the `job` label in the query, then read the script and any README beside it for what the metric means.
- Keep the database copy out of the repo and the scratchpad. It holds user password hashes and API keys, which is why the script works in `mktemp -d` and deletes it on exit.
