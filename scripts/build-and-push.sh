#!/usr/bin/env bash
set -euo pipefail

IMAGE="localhost:5001/acl-api"
TAG="${1:-dev}"

docker build -t "${IMAGE}:${TAG}" ./app
docker push "${IMAGE}:${TAG}"
