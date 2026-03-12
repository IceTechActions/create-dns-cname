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
    # Add diagnostic checks every 2 minutes (or at 120s for first check)
    if [ $ELAPSED -eq 120 ] || [ $((ELAPSED % 120)) -eq 0 ]; then
      echo "  === Diagnostic check at ${ELAPSED}s ==="
      
      # DNS resolution check
      DNS_RESULT=$(dig +short "${FEATURE}.${DNS_ZONE}" 2>/dev/null || echo "")
      if [ -z "$DNS_RESULT" ]; then
        echo "  WARNING: DNS not resolving for ${FEATURE}.${DNS_ZONE}"
      else
        echo "  DNS resolves to: $DNS_RESULT"
      fi
      
      # Check if custom domain is associated with a route
      ROUTE_CHECK=$(az afd custom-domain show \
        --profile-name "$FD" \
        --resource-group "$RG" \
        --custom-domain-name "$CUSTOM_DOMAIN_NAME" \
        --query "azureDnsZone" -o tsv 2>/dev/null || echo "")
      echo "  Custom domain DNS zone: ${ROUTE_CHECK:-not configured}"
      
      # Try verbose curl to see what's failing
      echo "  Attempting connection to ${QA_URL}/health..."
      curl -v --max-time 10 "${QA_URL}/health" 2>&1 | head -n 20 || true
      echo "  === End diagnostic check ==="
    fi
    
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
