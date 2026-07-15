#!/usr/bin/env bash
# scripts/bootstrap-cost-cfn-service-role.sh
# Creates the scoped CloudFormation service role used to deploy
# taxcalc-cost-dev-sai with --role-arn (trainee IAM lacks budgets:ModifyBudget).
set -euo pipefail

ROLE_NAME="${ROLE_NAME:-taxcalc-cost-cfn-service-sai}"
ACCOUNT_ID="${ACCOUNT_ID:-043000359802}"
REGION="${REGION:-us-east-1}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TRUST="${ROOT}/scripts/taxcalc-cost-cfn-service-trust.json"
POLICY="${ROOT}/scripts/taxcalc-cost-cfn-service-policy.json"

if aws iam get-role --role-name "${ROLE_NAME}" >/dev/null 2>&1; then
  echo "==> role ${ROLE_NAME} already exists"
else
  echo "==> creating role ${ROLE_NAME}"
  aws iam create-role \
    --role-name "${ROLE_NAME}" \
    --assume-role-policy-document "file://${TRUST}" \
    --description "CFN service role for taxcalc-cost-dev-sai (Budgets + SNS + CW + S3 + Secrets)" \
    --tags Key=trainee,Value=saivignesh-venkatraman Key=team,Value=capstone-team-5 Key=environment,Value=training Key=Project,Value=taxcalc \
    --region "${REGION}"
fi

echo "==> putting inline policy taxcalc-cost-cfn-service"
aws iam put-role-policy \
  --role-name "${ROLE_NAME}" \
  --policy-name taxcalc-cost-cfn-service \
  --policy-document "file://${POLICY}" \
  --region "${REGION}"

echo "==> ready: arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
echo "    Use: --role-arn arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
