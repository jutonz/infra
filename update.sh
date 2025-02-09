#!/bin/bash

set -ex

kubectl apply -k hello-world/overlays/prod
