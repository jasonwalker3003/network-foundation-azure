#!/usr/bin/env bash
# One-off setup Terraform can't do for itself. Safe to re-run.
set -euo pipefail
: "${P3_PREFIX:?Run: source ~/p3.env}"

echo "Registering resource providers..."
for ns in Microsoft.Network Microsoft.Compute Microsoft.Storage Microsoft.KeyVault \
          Microsoft.Insights Microsoft.OperationalInsights; do
  az provider register --namespace "$ns" -o none
done

echo "Creating resource groups and Terraform state storage..."
for rg in "$P3_TFSTATE_RG" "$P3_RG"; do
  az group create -n "$rg" -l "$P3_LOCATION" --tags project=network-foundation owner=jason env=lab -o none
done
az storage account create -n "$P3_TFSTATE_SA" -g "$P3_TFSTATE_RG" -l "$P3_LOCATION" \
  --sku Standard_LRS --kind StorageV2 --min-tls-version TLS1_2 --allow-blob-public-access false -o none
az storage account blob-service-properties update -n "$P3_TFSTATE_SA" -g "$P3_TFSTATE_RG" \
  --enable-versioning true --enable-delete-retention true --delete-retention-days 14 -o none
az storage container create -n tfstate --account-name "$P3_TFSTATE_SA" --auth-mode key -o none

echo "Making sure Network Watcher exists in $P3_LOCATION..."
if [ "$(az group exists -n NetworkWatcherRG)" != "true" ]; then
  az group create -n NetworkWatcherRG -l "$P3_LOCATION" -o none
fi
az network watcher configure -g NetworkWatcherRG -l "$P3_LOCATION" --enabled true -o none

echo "Creating the pipeline identity..."
read -r OWNER_ID REPO_ID < <(curl -s "https://api.github.com/repos/$GH_OWNER/$P3_REPO" \
  | jq -r '"\(.owner.id) \(.id)"')
PREFIX="repo:$GH_OWNER@$OWNER_ID/$P3_REPO@$REPO_ID"

APP_ID=$(az ad app list --display-name "github-$P3_REPO" --query "[0].appId" -o tsv)
if [ -z "$APP_ID" ]; then
  APP_ID=$(az ad app create --display-name "github-$P3_REPO" --query appId -o tsv)
  sleep 20
fi
SP_ID=$(az ad sp show --id "$APP_ID" --query id -o tsv 2>/dev/null || az ad sp create --id "$APP_ID" --query id -o tsv)

for cred in "gh-main:ref:refs/heads/main" "gh-pr:pull_request"; do
  name="${cred%%:*}"; suffix="${cred#*:}"
  if ! az ad app federated-credential show --id "$APP_ID" --federated-credential-id "$name" >/dev/null 2>&1; then
    params=$(jq -n --arg n "$name" --arg s "$PREFIX:$suffix" \
      '{name:$n, issuer:"https://token.actions.githubusercontent.com", subject:$s, audiences:["api://AzureADTokenExchange"]}')
    az ad app federated-credential create --id "$APP_ID" --parameters "$params" -o none
  fi
done

for rg in "$P3_RG" "$P3_TFSTATE_RG"; do
  az role assignment create --assignee-object-id "$SP_ID" --assignee-principal-type ServicePrincipal \
    --role Contributor --scope "$(az group show -n "$rg" --query id -o tsv)" -o none
done
az role assignment create --assignee-object-id "$SP_ID" --assignee-principal-type ServicePrincipal \
  --role "Network Contributor" --scope "$(az group show -n NetworkWatcherRG --query id -o tsv)" -o none

echo "Bootstrap complete. Copy these into GitHub from THIS output:"
echo "AZURE_CLIENT_ID=$APP_ID"
echo "AZURE_TENANT_ID=$(az account show --query tenantId -o tsv)"
echo "AZURE_SUBSCRIPTION_ID=$ARM_SUBSCRIPTION_ID"
