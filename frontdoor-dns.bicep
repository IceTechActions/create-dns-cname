// ============================================================
// DNS CNAME Module (Per-Feature, Deploy to DNS Zone RG)
// ============================================================
// Creates a CNAME record in the DNS zone for Front Door custom domain
// validation and managed certificate issuance.
//
// This module must be deployed to the DNS zone's resource group
// (cross-RG from the main deployment).
//
// Usage (GitHub Actions — via IceTechActions/create-dns-cname action):
//   uses: IceTechActions/create-dns-cname@v1
//   with:
//     feature_name: feature-1234
//     fd_hostname: <fdEndpoint>.z01.azurefd.net
//     dns_zone_resource_group: $DNS_ZONE_RESOURCE_GROUP
//
// Usage (direct CLI):
//   az deployment group create \
//     --resource-group "$DNS_ZONE_RESOURCE_GROUP" \
//     --template-file modules/frontdoor-dns.bicep \
//     --parameters recordName="feature-1234.cust" \
//                  cnameValue="feature-1234.z01.azurefd.net" \
//                  dnsZoneName="nisportal.com"
//
// This creates: feature-1234.cust.nisportal.com → CNAME → <fdEndpoint>.z01.azurefd.net
// ============================================================

@description('The record name (subdomain) to create, e.g., "feature-1234".')
param recordName string

@description('The CNAME target - the Front Door endpoint hostname (output frontDoorUrl from main.bicep, strip https://).')
param cnameValue string

@description('The Azure DNS zone name, e.g., "nisportal.com". The recordName is relative to this zone.')
param dnsZoneName string = 'nisportal.com'

@description('TTL in seconds for the CNAME record.')
param ttl int = 300

resource dnsZone 'Microsoft.Network/dnsZones@2018-05-01' existing = {
  name: dnsZoneName
}

resource cnameRecord 'Microsoft.Network/dnsZones/CNAME@2018-05-01' = {
  parent: dnsZone
  name: recordName
  properties: {
    TTL: ttl
    CNAMERecord: {
      cname: cnameValue
    }
  }
}

output fqdn string = '${recordName}.${dnsZoneName}'
