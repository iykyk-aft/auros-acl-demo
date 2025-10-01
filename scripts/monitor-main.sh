#!/usr/bin/env bash
set -euo pipefail

POLL_SECS="${POLL_SECS:-10}"
REMOTE_TRACKING="${REMOTE_TRACKING:-0}"
IMAGE="${IMAGE:-localhost:5001/acl-api}"
IMAGE_TAG_PREFIX="${IMAGE_TAG_PREFIX:-sha}"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "Not a git repo."; exit 1; }
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[ "$BRANCH" = "main" ] || echo "Warning: branch is '$BRANCH' (expected 'main')."

if [ "$REMOTE_TRACKING" = "1" ]; then
  git fetch origin main || true
  LAST="$(git rev-parse origin/main)"
else
  LAST="$(git rev-parse HEAD)"
fi
echo "Monitoring 'main' for commits (poll ${POLL_SECS}s). Start: $LAST"

while true; do
  sleep "${POLL_SECS}"
  if [ "$REMOTE_TRACKING" = "1" ]; then
    git fetch origin main || true
    HEAD="$(git rev-parse origin/main)"
  else
    HEAD="$(git rev-parse HEAD)"
  fi

  if [ "$HEAD" != "$LAST" ]; then
    echo "New commit: ${HEAD}"
    CHANGES="$(git diff --name-only ${LAST}..${HEAD} || true)"
    echo "$CHANGES"

    NEED_BUILD=0
    NEED_DB=0

    echo "$CHANGES" | grep -E '^app/|^k8s/api/' >/dev/null && NEED_BUILD=1 || true
    echo "$CHANGES" | grep -E '^k8s/db/' >/dev/null && NEED_DB=1 || true

    TAG="${IMAGE_TAG_PREFIX}-${HEAD:0:12}"

    if [ "$NEED_BUILD" -eq 1 ]; then
      ./scripts/build-and-push.sh "${TAG}"
      kubectl -n acl set image deploy/acl-api api="${IMAGE}:${TAG}"
    fi

    if [ "$NEED_DB" -eq 1 ]; then
      kubectl apply -k k8s
      kubectl -n acl rollout status statefulset/postgres --timeout=180s || true
    fi

    # Always sync config, apply, and restart API
    mkdir -p k8s/config
    cp -f config/config.yaml k8s/config/config.yaml
    kubectl apply -k k8s
    kubectl -n acl rollout restart deploy/acl-api
    kubectl -n acl rollout status deploy/acl-api --timeout=180s || true

    LAST="$HEAD"
  fi
done
