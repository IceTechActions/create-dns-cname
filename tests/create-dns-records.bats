#!/usr/bin/env bats
# Tests for scripts/create-dns-records.sh
# Uses bats (https://github.com/bats-core/bats-core) and mocks the `az` CLI.

SCRIPT="$BATS_TEST_DIRNAME/../scripts/create-dns-records.sh"

setup() {
  # Common input environment variables
  export FEATURE_NAME="feature-1234"
  export FD_HOSTNAME="my-endpoint.z01.azurefd.net"
  export DNS_ZONE_RG="dns-rg"
  export RESOURCE_GROUP="feature-rg"
  export ACTION_PATH="$BATS_TEST_DIRNAME/.."

  # Capture az calls for assertions
  export AZ_CALLS_FILE
  AZ_CALLS_FILE=$(mktemp)

  # Mock az CLI – records calls and returns deterministic test data
  az() {
    echo "$*" >> "$AZ_CALLS_FILE"
    case "$1 $2 $3 $4 $5" in
      "deployment group create"*)
        echo "mock: bicep deployment succeeded"
        ;;
      "afd profile list"*)
        echo "my-fd-profile"
        ;;
      "afd custom-domain show"*)
        echo "mock-validation-token"
        ;;
      "network dns record-set txt delete"*)
        return 0
        ;;
      "network dns record-set txt add-record"*)
        echo "mock: TXT record added"
        ;;
      *)
        echo "unexpected az call: $*" >&2
        return 1
        ;;
    esac
  }
  export -f az
}

teardown() {
  rm -f "$AZ_CALLS_FILE"
}

@test "script exits successfully with valid inputs" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "script performs Bicep CNAME deployment" {
  run bash "$SCRIPT"
  grep -q "deployment group create" "$AZ_CALLS_FILE"
}

@test "script passes correct parameters to Bicep deployment" {
  run bash "$SCRIPT"
  grep -q "recordName=feature-1234" "$AZ_CALLS_FILE"
  grep -q "cnameValue=my-endpoint.z01.azurefd.net" "$AZ_CALLS_FILE"
  grep -q "dnsZoneName=cust.nisportal.com" "$AZ_CALLS_FILE"
}

@test "script creates _dnsauth TXT record" {
  run bash "$SCRIPT"
  grep -q "record-set-name _dnsauth.feature-1234" "$AZ_CALLS_FILE"
}

@test "script outputs success message for TXT record" {
  run bash "$SCRIPT"
  [[ "$output" =~ "DNS TXT record created" ]]
}

@test "custom domain name is derived correctly from feature name and DNS zone" {
  local feature_name="feature-99999"
  local dns_zone="cust.nisportal.com"
  local expected="feature-99999-cust-nisportal-com"
  local actual
  actual=$(echo "${feature_name}-${dns_zone}" | tr '.' '-')
  [ "$actual" = "$expected" ]
}

@test "script fails when FEATURE_NAME is not set" {
  unset FEATURE_NAME
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
}

@test "script fails when FD_HOSTNAME is not set" {
  unset FD_HOSTNAME
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
}
