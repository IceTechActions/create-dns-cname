# create-dns-cname

Creates a DNS CNAME record in the `cust.nisportal.com` Azure DNS zone, pointing `{feature_name}.cust.nisportal.com` at the Front Door endpoint hostname. This triggers Front Door's automatic certificate validation and managed TLS certificate issuance for the custom domain.

After the DNS records are created, the action waits for the Azure Front Door custom domain certificate to be fully provisioned and TLS connectivity to be confirmed before completing.

The action includes `frontdoor-dns.bicep`, `scripts/create-dns-records.sh`, and `scripts/wait-for-cert.sh` — the calling repo does not need any Bicep files or scripts.

## Prerequisites

- Active Azure CLI session with permissions to deploy to the DNS zone resource group
- A deployed Front Door endpoint (use `IceTechActions/deploy-feature` first)

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `feature_name` | Yes | — | Feature environment name, e.g. `feature-1234`. Creates the record `feature-1234` in the `cust.nisportal.com` zone. |
| `fd_hostname` | Yes | — | Front Door endpoint hostname without `https://` — use the `fd_hostname` output from `deploy-feature` |
| `dns_zone_resource_group` | Yes | — | Resource group containing the `cust.nisportal.com` DNS zone |
| `resource_group` | Yes | — | Resource group containing the Front Door profile |
| `front_door_name` | No | `fd-nisportal` | Name of the shared Azure Front Door profile |
| `dns_zone_name` | No | `cust.nisportal.com` | DNS zone name used to construct the custom domain resource name and the URL checked for TLS readiness |
| `cert_wait_timeout` | No | `1800` | Seconds to wait for the AFD managed certificate to become ready. Set to `0` to skip the wait step entirely. |

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

After creating the DNS records, the action polls Azure Front Door until the custom domain's `domainValidationState` is `Approved`, `provisioningState` is `Succeeded`, and an HTTP response is received from `https://<feature_name>.<dns_zone_name>/health`. Diagnostic output (DNS resolution, AFD domain association, verbose curl) is emitted every 2 minutes to aid troubleshooting. A workflow warning is emitted if the certificate is not ready before `cert_wait_timeout` expires.

## Development

The DNS record creation logic lives in `scripts/create-dns-records.sh`. The certificate-waiting logic lives in `scripts/wait-for-cert.sh`. Both scripts read their inputs from environment variables, making them straightforward to test independently of GitHub Actions.

`create-dns-records.sh` env vars: `FEATURE_NAME`, `FD_HOSTNAME`, `DNS_ZONE_RG`, `RESOURCE_GROUP`, `ACTION_PATH`

`wait-for-cert.sh` env vars: `FEATURE_NAME`, `RESOURCE_GROUP`, `FRONT_DOOR_NAME`, `DNS_ZONE_NAME`, `CERT_WAIT_TIMEOUT`

### Running tests locally

```bash
# Install bats (https://github.com/bats-core/bats-core)
sudo apt-get install bats   # Debian/Ubuntu
brew install bats-core      # macOS

# Run the test suite
bats tests/create-dns-records.bats
```

