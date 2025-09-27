#!/bin/bash
# Minimal test of validation flow

set -euo pipefail

# Global vars
declare -ig VALIDATE=1
declare -ig SHELLCHECK=1  # Simulate -s flag

# Minimal validate_shell function
validate_shell() {
  local -- filepath="$1"
  
  # Basic syntax check with bash -n
  echo "Running bash -n validation..."
  if ! bash -n "$filepath" 2>&1; then
    echo "Basic syntax check failed"
    return 1
  fi
  
  # Run shellcheck if requested and available
  if ((SHELLCHECK)) && command -v shellcheck >/dev/null 2>&1; then
    echo "SHELLCHECK is enabled, running shellcheck..."
    local -- shellcheck_output
    shellcheck_output=$(shellcheck "$filepath" 2>&1 || true)
    if [[ -n "$shellcheck_output" ]]; then
      echo "Shellcheck issues found:"
      echo "$shellcheck_output"
    else
      echo "No shellcheck issues found"
    fi
  else
    echo "SHELLCHECK not enabled or shellcheck not available"
  fi
  
  return 0
}

# Test it
echo "Testing with file: test_shellcheck.sh"
echo "SHELLCHECK variable is: $SHELLCHECK"
validate_shell "test_shellcheck.sh"
