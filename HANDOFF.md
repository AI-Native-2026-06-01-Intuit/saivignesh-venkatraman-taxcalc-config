# HANDOFF — w7d5-implementation

## Branch / bar-for-done
- **Branch:** `w7d5-implementation`
- **Goal:** GitOps config for agent-svc, mcp-server, web; runtime secrets out-of-band; multi-service image bump.
- **Remaining:** Publish ECR images from app repo → bump overlay tags → run `sync-runtime-secrets` → scale replicas > 0.

## Key paths
| Area | Path |
|---|---|
| New workloads | `base/11-13-*`, `base/21-23-*`, `base/31-33-*` |
| Ingress `/api/chat` | `base/60-taxcalc-api.ingress.yaml` |
| Overlay gates | `overlays/*/kustomization.yaml` (replicas=0, sentinel tags) |
| Secrets sync | `.github/workflows/sync-runtime-secrets.yml` |
| Image bump | `.github/workflows/_bump-image.yml`, `scripts/bump-config-image.sh` |

## Verify
```bash
kubectl kustomize overlays/dev
# After secrets sync + image bump:
# kubectl -n taxcalc-dev get deploy,pod
```

## Gotchas
- Committed `base/40-taxcalc-api.secret.yaml` removed; all runtime Secrets via workflow_dispatch.
- New services use `0.0.0-local-unpublished` sentinel until CI bumps tags.
- Ingress proxy-read-timeout raised to 300s for AI SDK v7 streaming.

## PR
- Not opened yet.
