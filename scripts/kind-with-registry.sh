#!/usr/bin/env bash
set -euo pipefail

REG_NAME='kind-registry'
REG_PORT='5001'
CLUSTER_NAME='acl-kind'

if [ "$(docker inspect -f '{{.State.Running}}' ${REG_NAME} 2>/dev/null || true)" != 'true' ]; then
  docker run -d --restart=always -p "127.0.0.1:${REG_PORT}:5000" --name "${REG_NAME}" registry:2
fi

cat <<EOF | kind create cluster --name "${CLUSTER_NAME}" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:${REG_PORT}"]
    endpoint = ["http://kind-registry:5000"]
EOF

docker network connect "kind" "${REG_NAME}" 2>/dev/null || true

kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHosting.v1: |
    host: "localhost:${REG_PORT}"
    help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
EOF

echo "kind cluster '${CLUSTER_NAME}' ready with local registry at localhost:${REG_PORT}"
