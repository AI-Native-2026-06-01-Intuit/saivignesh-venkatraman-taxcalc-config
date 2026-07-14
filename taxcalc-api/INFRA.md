# taxcalc Infrastructure

## Four stacks and deploy order

Stacks must be deployed in this order — each one imports exports from the previous.

| Order | Stack | Template | Purpose |
|-------|-------|----------|---------|
| 1 | `taxcalc-bootstrap-dev-sai` | `cfn/taxcalc-bootstrap-dev.yaml` | S3 bucket for CFN artifacts + GitHub OIDC deploy role |
| 2 | `taxcalc-network-dev-sai` | `cfn/taxcalc-network-dev.yaml` | VPC, subnets, security groups |
| 3 | `taxcalc-app-dev-sai` | `cfn/taxcalc-app-dev.yaml` | RDS PostgreSQL instance + DB security group |
| 4 | `taxcalc-artifacts-dev-sai` | `cfn/taxcalc-artifacts-dev.yaml` | S3 bucket for application build artifacts |

Stack 3 imports from stack 2 (`NetworkStackName` parameter). Stack 4 is independent of 2 and 3 but depends on 1 for the deploy role.

## ChangeSet flow

Every stack change goes through create → describe → execute. Never use `deploy` directly.

```bash
# 1. Create
aws cloudformation create-change-set \
  --stack-name <stack-name> \
  --change-set-name <name> \
  --change-set-type CREATE|UPDATE \
  --template-body file://cfn/<template>.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameters ParameterKey=EnvName,ParameterValue=dev

# 2. Describe — check ExecutionStatus=AVAILABLE and inspect Changes[]
aws cloudformation describe-change-set \
  --stack-name <stack-name> \
  --change-set-name <name>

# 3. Execute
aws cloudformation execute-change-set \
  --stack-name <stack-name> \
  --change-set-name <name>
```

Key things to verify in `describe-change-set` output:
- `ExecutionStatus: AVAILABLE` — safe to execute
- `ResourceChange.Action` — `Add`, `Modify`, or `Remove`
- `ResourceChange.Replacement` — `True` means downtime; `False`/`Conditional` means in-place

Note: change sets are deleted by AWS after execution — `describe-change-set` will return `ChangeSetNotFound` afterwards. The stack itself persists.

## Cross-stack export naming

All exports follow the pattern `<stack-name>-<Key>`. Since stack names are suffixed per trainee (`-sai`), exports are automatically namespaced.

| Stack | Export | Value |
|-------|--------|-------|
| `taxcalc-bootstrap-dev-sai` | `taxcalc-bootstrap-dev-sai-BucketName` | Bootstrap S3 bucket name |
| `taxcalc-bootstrap-dev-sai` | `taxcalc-bootstrap-dev-sai-BucketArn` | Bootstrap S3 bucket ARN |
| `taxcalc-bootstrap-dev-sai` | `taxcalc-bootstrap-dev-sai-CfnDeployRoleArn` | GitHub Actions OIDC role ARN |
| `taxcalc-network-dev-sai` | `taxcalc-network-dev-sai-VpcId` | VPC ID |
| `taxcalc-network-dev-sai` | `taxcalc-network-dev-sai-VpcCidr` | VPC CIDR block |
| `taxcalc-network-dev-sai` | `taxcalc-network-dev-sai-PublicSubnets` | Comma-delimited public subnet IDs |
| `taxcalc-network-dev-sai` | `taxcalc-network-dev-sai-PrivateSubnets` | Comma-delimited private subnet IDs |
| `taxcalc-network-dev-sai` | `taxcalc-network-dev-sai-AppSgId` | Application security group ID |
| `taxcalc-app-dev-sai` | `taxcalc-app-dev-sai-DbEndpoint` | RDS endpoint hostname |
| `taxcalc-app-dev-sai` | `taxcalc-app-dev-sai-DbSecretArn` | Secrets Manager secret ARN |
| `taxcalc-app-dev-sai` | `taxcalc-app-dev-sai-DbSecurityGroupId` | DB security group ID |
| `taxcalc-artifacts-dev-sai` | `taxcalc-artifacts-dev-sai-BucketName` | Artifacts S3 bucket name |
| `taxcalc-artifacts-dev-sai` | `taxcalc-artifacts-dev-sai-BucketArn` | Artifacts S3 bucket ARN |

List all live exports:
```bash
aws cloudformation list-exports --query 'Exports[?starts_with(Name, `taxcalc-`)].{Name:Name,Value:Value}' --output table
```

## Drift verification

Detect drift after any out-of-band change:

```bash
# Trigger detection
aws cloudformation detect-stack-drift --stack-name <stack-name>

# Poll until DriftDetectionStatus=DETECTION_COMPLETE
aws cloudformation describe-stack-drift-detection-status --stack-drift-detection-id <id>

# View drifted resources
aws cloudformation describe-stack-resource-drifts --stack-name <stack-name>
```

Tag-only updates produce `Modify` actions with no replacement. Confirmed on `taxcalc-network-dev-sai` — tag rename executed with `UPDATE_COMPLETE`, zero replacements.

## AI-tool audit

| Task | Tool used | Outcome |
|------|-----------|---------|
| Scaffold CFN templates | `/cfn-author` skill | Skill generates VPC/EKS/S3/CI stacks; actual repo uses RDS-centric stacks — structural overlap on VPC and S3 hardening patterns (PAB, versioning, TLS-only bucket policy), diverges on compute (no EKS here) |
| Secret management | AWS Secrets Manager out-of-band | `taxcalc/dev/db-master-sai` pre-created before stack deploy; referenced via `{{resolve:secretsmanager:...}}` dynamic reference — secret value never appears in template |
| ROLLBACK_COMPLETE recovery | Stack delete + re-deploy | Triggered by password shorter than 8 chars in Secrets Manager; fixed by `put-secret-value` then `delete-stack` + new change set |
| Cross-stack wiring | `Fn::ImportValue` | Network stack exports consumed by app stack via `NetworkStackName` parameter |
