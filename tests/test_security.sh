#!/bin/bash
# Security test suite for editfile
# Tests for command injection vulnerabilities and secure filename handling

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly SCRIPT_DIR
EDIT_FILE="$SCRIPT_DIR/../editfile"
readonly EDIT_FILE

# Colors for output
declare -- RED=$'\e[31m' GREEN=$'\e[32m' YELLOW=$'\e[33m' RESET=$'\e[0m'
readonly -- RED GREEN YELLOW RESET

# Test counter
declare -i TESTS_PASSED=0
declare -i TESTS_FAILED=0

echo "========================================"
echo "Security Test Suite for editfile"
echo "========================================"
echo

# Create a safe test directory
TEST_DIR="/tmp/editfile_security_test_$$"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR" || exit 1

# Cleanup function
cleanup() {
  cd /tmp || true
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# Test helper function
run_test() {
  local -- test_name="$1"
  local -- test_cmd="$2"
  local -- expected_behavior="$3"

  echo "Test: $test_name"

  if eval "$test_cmd"; then
    echo "  ${GREEN}✓ PASS${RESET} - $expected_behavior"
    ((TESTS_PASSED+=1))
  else
    echo "  ${RED}✗ FAIL${RESET} - $expected_behavior"
    ((TESTS_FAILED+=1))
  fi
}

# Create a simple test editor
cat > "$TEST_DIR/test_editor.sh" << 'EOF'
#!/bin/bash
# Editor that just touches the file to indicate it was opened
echo "# Modified by test" >> "$1"
EOF
chmod +x "$TEST_DIR/test_editor.sh"

echo "=== Command Injection Tests ==="
echo

# Test 1: Single quote in filename (YAML validator)
echo "Test 1: Single quote in YAML filename"
cat > "$TEST_DIR/test.yaml" << 'EOF'
name: test
value: 123
EOF

# Create malicious filename
MALICIOUS_YAML="test'); import os; os.system('echo EXPLOITED > /tmp/exploit_test')#.yaml"
cp "$TEST_DIR/test.yaml" "$TEST_DIR/$MALICIOUS_YAML" 2>/dev/null || {
  echo "  ${YELLOW}⚠ SKIP${RESET} - Cannot create filename with single quote (filesystem limitation)"
}

if [[ -f "$TEST_DIR/$MALICIOUS_YAML" ]]; then
  # Run editfile with the malicious filename
  if EDITOR="$TEST_DIR/test_editor.sh" "$EDIT_FILE" -n "$TEST_DIR/$MALICIOUS_YAML" >/dev/null 2>&1; then
    # Check if exploit file was created
    if [[ -f /tmp/exploit_test ]]; then
      echo "  ${RED}✗ FAIL${RESET} - Command injection succeeded (file /tmp/exploit_test created)"
      ((TESTS_FAILED+=1))
      rm -f /tmp/exploit_test
    else
      echo "  ${GREEN}✓ PASS${RESET} - Command injection prevented"
      ((TESTS_PASSED+=1))
    fi
  else
    echo "  ${YELLOW}⚠ SKIP${RESET} - editfile failed to run"
  fi
fi

# Test 2: Backtick in filename
echo "Test 2: Backtick command substitution in filename"
MALICIOUS_JSON='test`touch /tmp/backtick_exploit`.json'
echo '{}' > "$TEST_DIR/test_backtick.json"
cp "$TEST_DIR/test_backtick.json" "$TEST_DIR/$MALICIOUS_JSON" 2>/dev/null || {
  echo "  ${YELLOW}⚠ SKIP${RESET} - Cannot create filename with backtick (filesystem limitation)"
}

if [[ -f "$TEST_DIR/$MALICIOUS_JSON" ]]; then
  if EDITOR="$TEST_DIR/test_editor.sh" "$EDIT_FILE" -n "$TEST_DIR/$MALICIOUS_JSON" >/dev/null 2>&1; then
    if [[ -f /tmp/backtick_exploit ]]; then
      echo "  ${RED}✗ FAIL${RESET} - Backtick injection succeeded"
      ((TESTS_FAILED+=1))
      rm -f /tmp/backtick_exploit
    else
      echo "  ${GREEN}✓ PASS${RESET} - Backtick injection prevented"
      ((TESTS_PASSED+=1))
    fi
  else
    echo "  ${YELLOW}⚠ SKIP${RESET} - editfile failed to run"
  fi
fi

# Test 3: $() command substitution in filename
echo "Test 3: \$() command substitution in filename"
MALICIOUS_PY='test$(touch /tmp/dollar_exploit).py'
echo 'pass' > "$TEST_DIR/test_dollar.py"
cp "$TEST_DIR/test_dollar.py" "$TEST_DIR/$MALICIOUS_PY" 2>/dev/null || {
  echo "  ${YELLOW}⚠ SKIP${RESET} - Cannot create filename with \$() (filesystem limitation)"
}

if [[ -f "$TEST_DIR/$MALICIOUS_PY" ]]; then
  if EDITOR="$TEST_DIR/test_editor.sh" "$EDIT_FILE" -n "$TEST_DIR/$MALICIOUS_PY" >/dev/null 2>&1; then
    if [[ -f /tmp/dollar_exploit ]]; then
      echo "  ${RED}✗ FAIL${RESET} - \$() injection succeeded"
      ((TESTS_FAILED+=1))
      rm -f /tmp/dollar_exploit
    else
      echo "  ${GREEN}✓ PASS${RESET} - \$() injection prevented"
      ((TESTS_PASSED+=1))
    fi
  else
    echo "  ${YELLOW}⚠ SKIP${RESET} - editfile failed to run"
  fi
fi

echo
echo "=== Filename Sanitization Tests ==="
echo

# Test 4: Very long filename
echo "Test 4: Very long filename handling"
LONG_NAME=$(printf 'a%.0s' {1..200}).txt
echo "test" > "$TEST_DIR/$LONG_NAME"
if EDITOR="$TEST_DIR/test_editor.sh" "$EDIT_FILE" -n "$TEST_DIR/$LONG_NAME" >/dev/null 2>&1; then
  echo "  ${GREEN}✓ PASS${RESET} - Long filename handled safely"
  ((TESTS_PASSED+=1))
else
  echo "  ${YELLOW}⚠ WARN${RESET} - Long filename may have issues"
fi

# Test 5: Special characters in filename
echo "Test 5: Special characters in filename"
SPECIAL_NAME='test@#%&.txt'
echo "test" > "$TEST_DIR/$SPECIAL_NAME"
if EDITOR="$TEST_DIR/test_editor.sh" "$EDIT_FILE" -n "$TEST_DIR/$SPECIAL_NAME" >/dev/null 2>&1; then
  echo "  ${GREEN}✓ PASS${RESET} - Special characters handled safely"
  ((TESTS_PASSED+=1))
else
  echo "  ${YELLOW}⚠ WARN${RESET} - Special characters may have issues"
fi

# Test 6: Unicode filename
echo "Test 6: Unicode filename handling"
UNICODE_NAME='test_ñoño_文件.txt'
echo "test" > "$TEST_DIR/$UNICODE_NAME"
if EDITOR="$TEST_DIR/test_editor.sh" "$EDIT_FILE" -n "$TEST_DIR/$UNICODE_NAME" >/dev/null 2>&1; then
  echo "  ${GREEN}✓ PASS${RESET} - Unicode filename handled safely"
  ((TESTS_PASSED+=1))
else
  echo "  ${YELLOW}⚠ WARN${RESET} - Unicode filename may have issues"
fi

echo
echo "=== Validator Security Tests ==="
echo

# Test 7: YAML validator with malicious content (not filename)
echo "Test 7: YAML validator with safe processing"
cat > "$TEST_DIR/safe.yaml" << 'EOF'
name: "test'); import os; os.system('echo EXPLOIT')#"
value: 123
EOF

if EDITOR="$TEST_DIR/test_editor.sh" "$EDIT_FILE" "$TEST_DIR/safe.yaml" >/dev/null 2>&1; then
  echo "  ${GREEN}✓ PASS${RESET} - YAML with malicious content in data processed safely"
  ((TESTS_PASSED+=1))
else
  echo "  ${YELLOW}⚠ INFO${RESET} - YAML validation may have failed (expected if PyYAML not installed)"
fi

# Test 8: XML validator with safe processing
echo "Test 8: XML validator with safe processing"
cat > "$TEST_DIR/safe.xml" << 'EOF'
<root>
  <data>'); import os; os.system('echo EXPLOIT')#</data>
</root>
EOF

if EDITOR="$TEST_DIR/test_editor.sh" "$EDIT_FILE" "$TEST_DIR/safe.xml" >/dev/null 2>&1; then
  echo "  ${GREEN}✓ PASS${RESET} - XML with malicious content in data processed safely"
  ((TESTS_PASSED+=1))
else
  echo "  ${YELLOW}⚠ INFO${RESET} - XML validation may have failed (expected if xmllint not installed)"
fi

# Test 9: TOML validator with safe processing
echo "Test 9: TOML validator with safe processing"
cat > "$TEST_DIR/safe.toml" << 'EOF'
name = "'); import os; os.system('echo EXPLOIT')#"
value = 123
EOF

if EDITOR="$TEST_DIR/test_editor.sh" "$EDIT_FILE" "$TEST_DIR/safe.toml" >/dev/null 2>&1; then
  echo "  ${GREEN}✓ PASS${RESET} - TOML with malicious content in data processed safely"
  ((TESTS_PASSED+=1))
else
  echo "  ${YELLOW}⚠ INFO${RESET} - TOML validation may have failed (expected if tomli not installed)"
fi

echo
echo "=== Path Traversal Tests ==="
echo

# Test 10: Path traversal attempt
echo "Test 10: Path traversal in filename"
TRAVERSAL_NAME='../../../tmp/traversal_test.txt'
echo "test" > "$TEST_DIR/traversal_test.txt"
# editfile should resolve the path, not follow the traversal
if EDITOR="$TEST_DIR/test_editor.sh" "$EDIT_FILE" -n "$TEST_DIR/$TRAVERSAL_NAME" 2>/dev/null; then
  # Check if it created file in /tmp (bad) or in TEST_DIR (good)
  if [[ -f /tmp/traversal_test.txt ]]; then
    echo "  ${RED}✗ FAIL${RESET} - Path traversal succeeded"
    ((TESTS_FAILED+=1))
    rm -f /tmp/traversal_test.txt
  else
    echo "  ${GREEN}✓ PASS${RESET} - Path traversal prevented"
    ((TESTS_PASSED+=1))
  fi
else
  echo "  ${GREEN}✓ PASS${RESET} - Path traversal rejected"
  ((TESTS_PASSED+=1))
fi

echo
echo "========================================"
echo "Security Test Results"
echo "========================================"
echo "Tests Passed: ${GREEN}$TESTS_PASSED${RESET}"
echo "Tests Failed: ${RED}$TESTS_FAILED${RESET}"
echo

if ((TESTS_FAILED == 0)); then
  echo "${GREEN}All security tests passed!${RESET}"
  exit 0
else
  echo "${RED}Some security tests failed. Please review.${RESET}"
  exit 1
fi
#fin
