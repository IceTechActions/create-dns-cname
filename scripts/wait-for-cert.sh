#!/usr/bin/env bash
set -euo pipefail

# Wait for Azure Front Door custom domain certificate to be ready
# This script waits for the custom domain to be validated and provisioned,
# then checks that TLS is working by making an HTTP request.

FEATURE="${FEATURE_NAME}"
RG="${RESOURCE_GROUP}"
FD="${FRONT_DOOR_NAME}"
DNS_ZONE="${DNS_ZONE_NAME}"
CUSTOM_DOMAIN_NAME=$(echo "${FEATURE}-${DNS_ZONE}" | sed 's/\./-/g')
QA_URL="https://${FEATURE}.${DNS_ZONE}"
TIMEOUT="${CERT_WAIT_TIMEOUT}"
ELAPSED=0

echo "Waiting for AFD custom domain '${CUSTOM_DOMAIN_NAME}' cert (timeout: ${TIMEOUT}s)..."

while [ $ELAPSED -lt $TIMEOUT ]; do
  RESULT=$(az afd custom-domain show \
    --profile-name "$FD" \
    --resource-group "$RG" \
    --custom-domain-name "$CUSTOM_DOMAIN_NAME" \
    --query '{validationState:domainValidationState,provisioningState:provisioningState}' \
    -o json 2>/dev/null || echo '{}')
  
  VS=$(echo "$RESULT" | jq -r '.validationState // "Unknown"')
  PS=$(echo "$RESULT" | jq -r '.provisioningState // "Unknown"')
  
  if [ "$VS" = "Approved" ] && [ "$PS" = "Succeeded" ]; then
    HTTP_CODE=$(curl --silent --output /dev/null --write-out "%{http_code}" \
      --max-time 15 "${QA_URL}/health" 2>/dev/null || true)
    echo "  domainValidationState=$VS  provisioningState=$PS  tls=${HTTP_CODE:-000}  (${ELAPSED}s elapsed)"
    
    if [ "${HTTP_CODE:-0}" -ge 100 ] 2>/dev/null; then
      echo "Custom domain certificate is ready (HTTP ${HTTP_CODE})."
      exit 0
    fi
  else
    echo "  domainValidationState=$VS  provisioningState=$PS  (${ELAPSED}s elapsed)"
  fi
  
  sleep 30
  ELAPSED=$((ELAPSED + 30))
done

echo "::warning::AFD cert did not become ready within ${TIMEOUT}s"
