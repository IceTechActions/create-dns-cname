# create-dns-cname

Creates a DNS CNAME record in the `cust.nisportal.com` Azure DNS zone, pointing `{feature_name}.cust.nisportal.com` at the Front Door endpoint hostname. This triggers Front Door's automatic certificate validation and managed TLS certificate issuance for the custom domain.

The action includes `frontdoor-dns.bicep` and `scripts/create-dns-records.sh` — the calling repo does not need any Bicep files or scripts.

## Prerequisites

- Active Azure CLI session with permissions to deploy to the DNS zone resource group
- A deployed Front Door endpoint (use `IceTechActions/deploy-feature` first)

## Inputs

| Input | Required | Description |
|-------|----------|-------------|
| `feature_name` | Yes | Feature environment name, e.g. `feature-1234`. Creates the record `feature-1234` in the `cust.nisportal.com` zone. |
| `fd_hostname` | Yes | Front Door endpoint hostname without `https://` — use the `fd_hostname` output from `deploy-feature` |
| `dns_zone_resource_group` | Yes | Resource group containing the `cust.nisportal.com` DNS zone |
| `resource_group` | Yes | Resource group containing the Front Door profile |

## Usage

```yaml
- name: Create DNS CNAME record
  uses: IceTechActions/create-dns-cname@v1
  with:
    feature_name: feature-1234
    fd_hostname: ${{ steps.deploy.outputs.fd_hostname }}
    dns_zone_resource_group: my-dns-rg
    resource_group: my-feature-rg
```

## Result

Creates: `feature-1234.cust.nisportal.com` → CNAME → `<fd-endpoint>.z01.azurefd.net`

Also creates the `_dnsauth.feature-1234.cust.nisportal.com` TXT record required for AFD custom domain validation.

The CNAME is used by Front Door to validate domain ownership and issue a managed TLS certificate. The record TTL is 300 seconds.

## Development

The action logic lives in `scripts/create-dns-records.sh`. The script reads its inputs from environment variables (`FEATURE_NAME`, `FD_HOSTNAME`, `DNS_ZONE_RG`, `RESOURCE_GROUP`, `ACTION_PATH`), making it straightforward to test independently of GitHub Actions.

### Running tests locally

```bash
# Install bats (https://github.com/bats-core/bats-core)
sudo apt-get install bats   # Debian/Ubuntu
brew install bats-core      # macOS

# Run the test suite
bats tests/create-dns-records.bats
```

