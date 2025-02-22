#!/bin/bash

set -ex

ls -l /etc/letsencrypt/live/ | grep ^d | awk '{print $9}' | while read -r domain; do
  cat /etc/letsencrypt/live/$domain/fullchain.pem /etc/letsencrypt/live/$domain/privkey.pem > /etc/haproxy/certs/$domain.pem
done

systemctl reload haproxy
