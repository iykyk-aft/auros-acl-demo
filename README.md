# Anti-Corruption Layer (ACL) 

Short, optimized demo of a self-service ACL in front of PostgreSQL. No Helm. Includes:
- Minimal Flask API that reads Config-as-Code (YAML) and exposes REST endpoints.
- Kustomize-only Kubernetes manifests.
- Local GitOps/CI monitor that watches commits on `main` and reconciles the cluster.
- Local kind cluster + local Docker registry bootstrap.

The API supports both YAML schemas:
1) **Legacy** `mappings:` (DB column → API field)
2) **Newer** `endpoints:` (API field → DB column)

## Quick Start

Prereqs: Docker, kubectl, kind, git, bash.

```bash
# 1) Create kind cluster with a local registry
./scripts/kind-with-registry.sh

# 2) Build & push the API image
./scripts/build-and-push.sh dev

# 3) Deploy everything
./scripts/deploy.sh

# 4) Port-forward and test
kubectl -n acl port-forward svc/acl-api 8000:80
curl -s http://localhost:8000/healthz
curl -s http://localhost:8000/__meta/routes
curl -s http://localhost:8000/myapi
```

## Config-as-Code (`config/config.yaml`)

### Legacy schema (DB → API)
```yaml
mappings:
  - api_endpoint: /myapi
    columns:
      id: myapi_id
      name: myapi_name
      created_at: myapi_created_at
    query: |
      SELECT id, username AS name, created_at
      FROM users
      WHERE active = true
      ORDER BY id;
```

### Newer schema (API → DB)
```yaml
endpoints:
  - path: /users
    query: |
      SELECT id, username, email, active
      FROM users
      WHERE active = true
      ORDER BY id
    mapping:
      id: id
      name: username
      email: email
      isActive: active
```

## Local GitOps / CI Monitor

Watches `main` and reconciles:
- `config/` change → updates ConfigMap & restarts API
- `app/` or `k8s/api/` change → builds/pushes image with commit SHA & patches Deployment
- `k8s/db/` change → reapplies DB IaC
- Always converges with `kubectl apply -k k8s`

Usage:
```bash
git init && git add -A && git commit -m "initial" && git branch -M main
./scripts/monitor-main.sh
```

## Stop Delete Cluster


Delete (clean slate):
```bash
kind delete cluster --name acl-kind
docker rm -f kind-registry || true
```



License: MIT
# auros-acl-demo
# auros-acl-demo
