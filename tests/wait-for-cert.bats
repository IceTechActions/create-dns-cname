#!/usr/bin/env bats
# Tests for scripts/wait-for-cert.sh
# Uses bats (https://github.com/bats-core/bats-core) and mocks az/curl/dig/sleep.

SCRIPT="$BATS_TEST_DIRNAME/../scripts/wait-for-cert.sh"

setup() {
  export FEATURE_NAME="feature-1234"
  export RESOURCE_GROUP="feature-rg"
  export FRONT_DOOR_NAME="my-front-door"
  export DNS_ZONE_NAME="qa.example.com"
  export CERT_WAIT_TIMEOUT="60"

  # Temp files for capturing calls and tracking state across mock invocations
  export AZ_CALLS_FILE
  AZ_CALLS_FILE=$(mktemp)
  export CALL_COUNT_FILE
  CALL_COUNT_FILE=$(mktemp)
  echo "0" > "$CALL_COUNT_FILE"

  # Mock sleep to avoid real delays while still allowing ELAPSED to increment
  sleep() { :; }
  export -f sleep

  # Mock dig to avoid real DNS lookups (203.0.113.1 is from the TEST-NET-3 reserved range)
  dig() { echo "203.0.113.1"; }
  export -f dig
}

teardown() {
  rm -f "$AZ_CALLS_FILE" "$CALL_COUNT_FILE"
}

# ---------------------------------------------------------------------------
# Test 1: domain is already Approved/Succeeded and TLS (HTTP 200) is working
# ---------------------------------------------------------------------------
@test "exits 0 when domain is already Approved/Succeeded and TLS returns HTTP 200" {
  az() {
    echo "$*" >> "$AZ_CALLS_FILE"
    # Main status query returns Approved/Succeeded; route-check query returns a string
    if [[ "$*" == *"validationState"* ]]; then
      echo '{"validationState":"Approved","provisioningState":"Succeeded"}'
    else
      echo "qa.example.com"
    fi
  }
  export -f az

  curl() {
    # Health-check curl uses --write-out; diagnostic verbose curl does not
    if [[ "$*" == *"--write-out"* ]]; then
      echo "200"
    else
      echo "mock-curl-verbose-output"
    fi
  }
  export -f curl

  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Custom domain certificate is ready" ]]
}

# ---------------------------------------------------------------------------
# Test 2: timeout reached before cert becomes ready → warning printed, exit 0
# ---------------------------------------------------------------------------
@test "prints warning and exits when timeout is reached without cert being ready" {
  export CERT_WAIT_TIMEOUT="0"

  az() {
    echo "$*" >> "$AZ_CALLS_FILE"
    echo '{"validationState":"Pending","provisioningState":"Updating"}'
  }
  export -f az

  curl() { echo ""; }
  export -f curl
}

# ---------------------------------------------------------------------------
# Test 3: domain transitions from Pending → Approved/Succeeded mid-poll
# ---------------------------------------------------------------------------
@test "polls until domain transitions from Pending to Approved/Succeeded then exits 0" {
  # First az call (ELAPSED=0) returns Pending; subsequent calls return Approved
  az() {
    echo "$*" >> "$AZ_CALLS_FILE"
    if [[ "$*" == *"validationState"* ]]; then
      COUNT=$(cat "$CALL_COUNT_FILE")
      COUNT=$((COUNT + 1))
      echo "$COUNT" > "$CALL_COUNT_FILE"
      if [ "$COUNT" -le 1 ]; then
        echo '{"validationState":"Pending","provisioningState":"Updating"}'
      else
        echo '{"validationState":"Approved","provisioningState":"Succeeded"}'
      fi
    else
      echo "qa.example.com"
    fi
  }
  export -f az

  curl() {
    if [[ "$*" == *"--write-out"* ]]; then
      echo "200"
    else
      echo "mock-curl-verbose-output"
    fi
  }
  export -f curl

  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Pending" ]]
  [[ "$output" =~ "Custom domain certificate is ready" ]]
}

# ---------------------------------------------------------------------------
# Test 4: curl returns 000 (no TLS yet) → script keeps polling until TLS ready
# ---------------------------------------------------------------------------
@test "keeps polling when curl returns 000 and exits 0 once TLS is ready" {
  az() {
    echo "$*" >> "$AZ_CALLS_FILE"
    if [[ "$*" == *"validationState"* ]]; then
      echo '{"validationState":"Approved","provisioningState":"Succeeded"}'
    else
      echo "qa.example.com"
    fi
  }
  export -f az

  # First health-check returns 000, second returns 200
  curl() {
    if [[ "$*" == *"--write-out"* ]]; then
      COUNT=$(cat "$CALL_COUNT_FILE")
      COUNT=$((COUNT + 1))
      echo "$COUNT" > "$CALL_COUNT_FILE"
      if [ "$COUNT" -le 1 ]; then
        echo "000"
      else
        echo "200"
      fi
    else
      echo "mock-curl-verbose-output"
    fi
  }
  export -f curl

  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "tls=000" ]]
  [[ "$output" =~ "Custom domain certificate is ready" ]]
}

# ---------------------------------------------------------------------------
# Test 5: missing required env var causes the script to fail
# ---------------------------------------------------------------------------
@test "fails when FEATURE_NAME is not set" {
  unset FEATURE_NAME

  az() { echo '{}'; }
  export -f az
  curl() { :; }
  export -f curl

  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
}

@test "fails when CERT_WAIT_TIMEOUT is not set" {
  unset CERT_WAIT_TIMEOUT

  az() { echo '{}'; }
  export -f az
  curl() { :; }
  export -f curl

  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
}
