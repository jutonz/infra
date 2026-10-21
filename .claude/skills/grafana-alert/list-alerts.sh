#!/bin/bash
# Usage: list-alerts.sh [--all]
#
# Prints each Grafana alert instance whose latest state is not Normal, with
# the rule's PromQL. Pass --all to print every instance.

set -euo pipefail

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Grafana runs SQLite in WAL mode (#176), so recent writes live in the -wal
# file until a checkpoint. The image has no sqlite3, so copy both files out.
for f in grafana.db grafana.db-wal; do
  kubectl -n grafana exec deploy/grafana -- cat "/var/lib/grafana/$f" > "$work/$f"
done

python3 -I - "$work/grafana.db" "${1:-}" <<'EOF'
import datetime, json, sqlite3, sys

db, mode = sys.argv[1], sys.argv[2]
conn = sqlite3.connect(db)

exprs = {}
for rule_id, data in conn.execute("select id, data from alert_rule"):
    queries = [q["model"].get("expr") for q in json.loads(data)]
    exprs[rule_id] = [q for q in queries if q]

# alert_instance stopped updating in Oct 2025, so it shows stale state.
# The annotation table is Grafana's state history and stays current.
latest = {}
rows = conn.execute("""
    select a.alert_id, r.title, r.is_paused, a.prev_state, a.new_state, a.epoch, a.text
    from annotation a join alert_rule r on r.id = a.alert_id
    order by a.id""")
for rule_id, title, paused, prev, new, epoch, text in rows:
    # Text is "<title> {labels} - <values>", and values are empty when an
    # instance resolves. Text under an older title is from before a rename.
    if not text.startswith(title + " "):
        continue
    labels, _, values = text.removeprefix(title + " ").rpartition(" - ")
    latest[(rule_id, labels)] = (title, paused, prev, new, epoch, labels, values)

for (rule_id, _), (title, paused, prev, new, epoch, labels, values) in sorted(
    latest.items(), key=lambda item: -item[1][4]
):
    if mode != "--all" and new.startswith("Normal"):
        continue
    since = datetime.datetime.fromtimestamp(epoch / 1000).strftime("%Y-%m-%d %H:%M")
    print(f"{new:<24} since {since}  {title}{'  (paused)' if paused else ''}")
    print(f"    labels: {labels}")
    print(f"    values: {values or '-'}  (was {prev})")
    for expr in exprs.get(rule_id, []):
        print(f"    expr:   {expr}")
EOF
