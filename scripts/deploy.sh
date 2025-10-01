#!/usr/bin/env bash
set -euo pipefail

mkdir -p k8s/config
cp -f config/config.yaml k8s/config/config.yaml

kubectl apply -k k8s
kubectl -n acl rollout status deploy/acl-api --timeout=180s || true
kubectl -n acl rollout status statefulset/postgres --timeout=180s || true
