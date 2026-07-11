# saivignesh-venkatraman-taxcalc-config

GitOps desired state for `taxcalc-api` on the local k3d workload cluster (`k3d-taxcalc`).

## Related repositories

| Repo | Role |
|---|---|
| [`saivignesh-venkatraman-tax-liability`](https://github.com/AI-Native-2026-06-01-Intuit/saivignesh-venkatraman-tax-liability) | Application source, CI build/test, ECR push |
| **this repo** | Kubernetes desired state consumed by Argo CD |

ECR image (shared `_sai` suffix):

`043000359802.dkr.ecr.us-east-1.amazonaws.com/uptimecrew/taxcalc-api_sai`

## W6D2 summary

Promoted W5D3 workload manifests from the app repo into a Kustomize `base/` plus `overlays/dev|staging|prod/`, wired Argo CD `AppProject taxcalc` (strict allow-list, no wildcards), a standalone dev `Application`, and a matrix `ApplicationSet` for all envs. Slack notifications route `team=taxcalc` apps to `taxcalc-deploys-sai` on sync-failed and health-degraded only. Platform-owned `ResourceQuota`/`LimitRange` and cluster-scoped `Namespace` objects are intentionally excluded from the app-team GitOps base.

Reconcile loop: app CI on `main` pushes ECR → opens a dev overlay bump PR here via `_bump-config.yml` → merge updates desired state → Argo CD syncs with automated prune/selfHeal. For this k3d assignment, prod keeps automated sync; real prod may require manual promotion later.

**Note:** We are using Argo CD v3.x for this assignment due to setup issues encountered with the v2.11.7 install path from the course materials. The manifests and GitOps patterns in this repo remain the same; only the local Argo CD version differs.

## Layout

```text
base/                         # Namespace-scoped app + backing services (no Namespace/Quota/LimitRange)
overlays/dev|staging|prod/    # Env-specific patches + ECR image tag
argocd/projects/              # AppProject allow-list
argocd/applications/          # Standalone dev anchor Application
argocd/applicationsets/       # Matrix generator for dev/staging/prod
argocd-system/                # Argo CD Notifications ConfigMap (no Secret committed)
```

Commits in this repo are split by concern: base manifests, env overlays, Argo CD project/apps, notifications, and docs — so each layer can be reviewed independently.

## Namespace / bootstrap contract

`CreateNamespace=true` is retained on Applications per W6D2 rubric. Because the AppProject intentionally keeps `clusterResourceWhitelist: []` to prevent app-managed cluster-scoped resources, the local k3d namespaces `taxcalc-dev`, `taxcalc-staging`, and `taxcalc-prod` are bootstrap-owned and pre-created out-of-band. Argo manages only the namespace-scoped application resources inside those destinations.

Pre-create workload namespaces before the first sync (platform/bootstrap, not GitOps):

```bash
kubectl create namespace taxcalc-dev --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace taxcalc-staging --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace taxcalc-prod --dry-run=client -o yaml | kubectl apply -f -
```

Run `./check-gitops-config-ready.sh` to validate repo config; missing live namespaces warn only (local bootstrap prerequisite for sync evidence, not a merge blocker).

## W6D2 guardrails

- **No Namespace object in base/overlays**: Namespace YAML is never committed here. `CreateNamespace=true` stays on Applications per rubric, but with `clusterResourceWhitelist: []` the target namespaces must already exist — bootstrap them out-of-band before sync evidence.
- **No ResourceQuota / LimitRange in base**: `manifests/00-namespace.yaml` in the app repo bundles platform-owned quota/limit objects. Those are intentionally excluded from this GitOps base because the AppProject blacklists `ResourceQuota` and `LimitRange`.
- **ServiceMonitor / PrometheusRule**: omitted from base for now because local k3d may lack Prometheus Operator CRDs. Kinds remain allowed in the AppProject for a later observability follow-up.
- **Placeholder Secret only**: `base/40-taxcalc-api.secret.yaml` contains non-real placeholder values. Replace at deploy time via your secret manager or out-of-band `kubectl create secret`.
- **No committed secrets**: Slack webhook URL and GitHub PAT live out-of-band only.

## Image policy

Overlays rewrite the base image `uptimecrew/taxcalc-api:0.1.1` to:

`043000359802.dkr.ecr.us-east-1.amazonaws.com/uptimecrew/taxcalc-api_sai:37f63b8a3456abc3532086474abf53b0c55dd672`

The app repo CI opens PRs that bump `overlays/dev/kustomization.yaml` via `_bump-config.yml` using secret `GITOPS_REPO_TOKEN_SAI`.

## Install tooling (local)

```bash
brew install argocd kustomize
kubectl config current-context   # expect k3d-taxcalc for this assignment
```

## Install Argo CD v3.x

> **Why v3.x?** The W6D2 course materials pin Argo CD v2.11.7, but that install path caused setup issues on our local `k3d-taxcalc` cluster (rollout failures / compatibility friction). We switched to Argo CD **v3.x** for a reliable local bootstrap. The GitOps manifests in this repo (`AppProject`, `Application`, `ApplicationSet`, notifications) are unchanged — only the controller install version differs.

Pinned to `v3.0.23` below; any recent v3.x release should work for this assignment.

```bash
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.0.23/manifests/install.yaml
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=5m
kubectl -n argocd rollout status deploy/argocd-repo-server --timeout=5m
kubectl -n argocd rollout status deploy/argocd-server --timeout=5m
```

## Slack notifications secret (never commit)

```bash
# SLACK_WEBHOOK_URL is a local shell variable only — never commit it.
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl -n argocd create secret generic argocd-notifications-secret \
  --from-literal=slack-token="$SLACK_WEBHOOK_URL" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n argocd apply -f argocd-system/notifications-cm.yaml
```

## Label workload cluster for ApplicationSet

```bash
# If no in-cluster Secret exists yet:
argocd cluster add k3d-taxcalc

# Find the cluster secret name, then label it:
kubectl -n argocd get secret -l argocd.argoproj.io/secret-type=cluster -o name
kubectl -n argocd label secret <cluster-secret-name> uptimecrew.example.internal/tier=workload --overwrite
```

## Apply AppProject, dev Application, ApplicationSet

Bootstrap workload namespaces first (see [Namespace / bootstrap contract](#namespace--bootstrap-contract)), then:

```bash
kubectl -n argocd apply -f argocd/projects/taxcalc.yaml
kubectl -n argocd apply -f argocd/applications/taxcalc-api-dev.yaml
kubectl -n argocd apply -f argocd/applicationsets/taxcalc-api-envs.yaml
```

After ApplicationSet owns dev, delete the standalone anchor:

```bash
kubectl -n argocd delete application taxcalc-api-dev --ignore-not-found
```

## Validate manifests

```bash
kustomize build overlays/dev > /tmp/taxcalc-dev.yaml
kustomize build overlays/staging > /tmp/taxcalc-staging.yaml
kustomize build overlays/prod > /tmp/taxcalc-prod.yaml
kubectl -n argocd get appproject taxcalc -o yaml
argocd app list --project taxcalc
```

Policy checks:

```bash
grep -RIn 'spec.project: default' argocd/ && exit 1 || true
grep -RIn 'on-sync-succeeded' argocd-system/notifications-cm.yaml && exit 1 || true
grep -RIn 'hooks.slack.com' . && exit 1 || true
```

## Test rogue Application rejection

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: rogue-default-project
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/AI-Native-2026-06-01-Intuit/saivignesh-venkatraman-taxcalc-config.git
    path: overlays/dev
  destination:
    server: https://kubernetes.default.svc
    namespace: taxcalc-dev
EOF
# Expect AppProject policy to deny or require correction to project: taxcalc
kubectl -n argocd delete application rogue-default-project --ignore-not-found
```

## Test drift / selfHeal

```bash
kubectl -n taxcalc-dev scale deploy/taxcalc-api --replicas=9
# With automated selfHeal enabled, Argo CD should revert replica drift after sync.
argocd app sync taxcalc-api-dev
kubectl -n taxcalc-dev get deploy taxcalc-api -o jsonpath='{.spec.replicas}{"\n"}'
```

## Prod automated sync note

For this local k3d assignment, the ApplicationSet keeps **automated sync enabled for prod**. Real prod may remove automated sync and require manual promotion later.

## Bootstrap this repo on GitHub

```bash
gh repo clone AI-Native-2026-06-01-Intuit/saivignesh-venkatraman-taxcalc-config /Users/svenkatrama/saivignesh-venkatraman-taxcalc-config
```

If creating from scratch:

```bash
cd /Users/svenkatrama/saivignesh-venkatraman-taxcalc-config
git init && git add . && git commit -m "feat: initial GitOps scaffold"
gh repo create AI-Native-2026-06-01-Intuit/saivignesh-venkatraman-taxcalc-config \
  --private --source . --remote origin --push
```
