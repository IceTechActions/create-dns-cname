#!/usr/bin/env bash
# create-dns-records.sh
# Creates a DNS CNAME record via Bicep and a _dnsauth TXT record for
# AFD custom domain validation.
#
# Required environment variables:
#   FEATURE_NAME   - Feature environment name, e.g. feature-1234
#   FD_HOSTNAME    - Front Door endpoint hostname (without https://)
#   DNS_ZONE_RG    - Resource group containing the cust.nisportal.com DNS zone
#   RESOURCE_GROUP - Resource group containing the Front Door profile
#   ACTION_PATH    - Path to the action directory (contains frontdoor-dns.bicep)
set -euo pipefail

DNS_ZONE="cust.nisportal.com"

# ── Step 1: Deploy CNAME record via Bicep ────────────────────────────────────
az deployment group create \
  --name "dns-${FEATURE_NAME}-$(date +%Y%m%d-%H%M%S)" \
  --resource-group "${DNS_ZONE_RG}" \
  --template-file "${ACTION_PATH}/frontdoor-dns.bicep" \
  --parameters \
    recordName="${FEATURE_NAME}" \
    cnameValue="${FD_HOSTNAME}" \
    dnsZoneName="${DNS_ZONE}"

# ── Step 2: Create _dnsauth TXT record for AFD custom domain validation ───────
# AFD custom domain resource name: feature-99999-cust-nisportal-com
CUSTOM_DOMAIN_NAME=$(echo "${FEATURE_NAME}-${DNS_ZONE}" | tr '.' '-')

# Find the Front Door Premium profile in the resource group
FD_PROFILE=$(az afd profile list \
  --resource-group "${RESOURCE_GROUP}" \
  --query "[?sku.name=='Premium_AzureFrontDoor'].name | [0]" -o tsv)

echo "Getting validation token from AFD profile '${FD_PROFILE}', custom domain '${CUSTOM_DOMAIN_NAME}'..."
VALIDATION_TOKEN=$(az afd custom-domain show \
  --profile-name "${FD_PROFILE}" \
  --resource-group "${RESOURCE_GROUP}" \
  --custom-domain-name "${CUSTOM_DOMAIN_NAME}" \
  --query "validationProperties.validationToken" -o tsv)

# Remove any existing TXT record (handles re-deploys where token may have changed)
az network dns record-set txt delete \
  --resource-group "${DNS_ZONE_RG}" \
  --zone-name "${DNS_ZONE}" \
  --record-set-name "_dnsauth.${FEATURE_NAME}" \
  --yes 2>/dev/null || true

echo "Creating _dnsauth.${FEATURE_NAME}.${DNS_ZONE} TXT record..."
az network dns record-set txt add-record \
  --resource-group "${DNS_ZONE_RG}" \
  --zone-name "${DNS_ZONE}" \
  --record-set-name "_dnsauth.${FEATURE_NAME}" \
  --value "${VALIDATION_TOKEN}"
echo "DNS TXT record created — AFD will validate the custom domain and provision the SSL certificate."
