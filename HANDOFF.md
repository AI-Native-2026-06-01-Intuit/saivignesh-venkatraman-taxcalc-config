# HANDOFF — config repo (main)

## Branch / bar-for-done
- **Branch:** `main`
- **Goal:** GitOps for taxcalc stack; agent-svc rollout evidence (Synced/Healthy Argo CD).
- **Remaining:** Publish ECR images for mcp-server/web → bump overlay tags → `sync-runtime-secrets` → scale mcp/web replicas > 0.

## Key paths
| Area | Path |
|---|---|
| Agent-svc Argo app | `argocd/applications/taxcalc-agent-svc-dev.yaml` |
| API dev app + env set | `argocd/applications/taxcalc-api-dev.yaml`, `argocd/applicationsets/taxcalc-api-envs.yaml` |
| HPA (minReplicas 2) | `base/50-taxcalc-api.hpa.yaml` |
| Dev overlay gates | `overlays/dev/kustomization.yaml` |
| Image bump | `scripts/bump-config-image.sh`, `.github/workflows/_bump-image.yml` |

## Verify
```bash
kubectl -n argocd apply -f argocd/applications/taxcalc-agent-svc-dev.yaml
argocd app get taxcalc-agent-svc | grep -E 'Sync Status|Health Status'
# Expect: Synced / Healthy
```

## Gotchas
- **HPA vs git replicas:** `taxcalc-api-hpa` minReplicas=2; dev overlay sets replicas=1. Argo apps ignore `/spec/replicas` on `Deployment/taxcalc-api` so HPA owns scale without OutOfSync/Progressing churn.
- **Shared resources:** `taxcalc-agent-svc` and `taxcalc-api-dev` both target `overlays/dev` — `SharedResourceWarning` is expected; agent app also ignores `tracking-id` annotation drift.
- Runtime Secrets via `sync-runtime-secrets` workflow only (no committed Secret manifests).

## PR
- Argo HPA fix committed on `main`; open PR if org policy requires review before merge to shared main.
