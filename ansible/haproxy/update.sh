#!/bin/bash

tmpfile=$(mktemp)
mv "$tmpfile" "$tmpfile.yaml"
tmpfile="${tmpfile}.yaml"
sops decrypt ./hosts.yaml > "$tmpfile"
cat "$tmpfile"
ansible-playbook -i "$tmpfile" ./playbook.yaml
rm $tmpfile
