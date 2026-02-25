# create-dns-cname

Creates a DNS CNAME record in the `cust.nisportal.com` Azure DNS zone, pointing `{feature_name}.cust.nisportal.com` at the Front Door endpoint hostname. This triggers Front Door's automatic certificate validation and managed TLS certificate issuance for the custom domain.

The action bundles `frontdoor-dns.bicep` — the calling repo does not need any Bicep files.

## Prerequisites

- Active Azure CLI session with permissions to deploy to the DNS zone resource group
- A deployed Front Door endpoint (use `IceTechActions/deploy-feature` first)

## Inputs

| Input | Required | Description |
|-------|----------|-------------|
| `feature_name` | Yes | Feature environment name, e.g. `feature-1234`. Creates the record `feature-1234` in the `cust.nisportal.com` zone. |
| `fd_hostname` | Yes | Front Door endpoint hostname without `https://` — use the `fd_hostname` output from `deploy-feature` |
| `dns_zone_resource_group` | Yes | Resource group containing the `cust.nisportal.com` DNS zone |

## Usage

```yaml
- name: Create DNS CNAME record
  uses: IceTechActions/create-dns-cname@v1
  with:
    feature_name: feature-1234
    fd_hostname: ${{ steps.deploy.outputs.fd_hostname }}
    dns_zone_resource_group: my-dns-rg
```

## Result

Creates: `feature-1234.cust.nisportal.com` → CNAME → `<fd-endpoint>.z01.azurefd.net`

The CNAME is used by Front Door to validate domain ownership and issue a managed TLS certificate. The record TTL is 300 seconds.
