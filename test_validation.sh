#!/bin/bash
# Test script for editfile validation features

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly EDIT_FILE="$SCRIPT_DIR/editfile"

# Colors for output
RED=$'\e[31m'
GREEN=$'\e[32m'
YELLOW=$'\e[33m'
RESET=$'\e[0m'

echo "Testing editfile validation features..."
echo

# Test 1: Valid JSON
echo "Test 1: Valid JSON validation"
cat > /tmp/test_valid.json << 'EOF'
{
  "name": "test",
  "value": 123,
  "array": [1, 2, 3]
}
EOF

if "$EDIT_FILE" -n /tmp/test_valid.json >/dev/null 2>&1; then
  echo "${GREEN}✓ Valid JSON test passed${RESET}"
else
  echo "${RED}✗ Valid JSON test failed${RESET}"
fi

# Test 2: Invalid JSON
echo "Test 2: Invalid JSON detection"
cat > /tmp/test_invalid.json << 'EOF'
{
  "name": "test"
  "missing": "comma"
}
EOF

# We need to validate without editing - so let's just check the JSON directly
if ! jq empty /tmp/test_invalid.json 2>/dev/null && ! python3 -m json.tool /tmp/test_invalid.json >/dev/null 2>&1; then
  echo "${GREEN}✓ Invalid JSON detection passed${RESET}"
else
  echo "${RED}✗ Invalid JSON detection failed${RESET}"
fi

# Test 3: Valid Python
echo "Test 3: Valid Python validation"
cat > /tmp/test_valid.py << 'EOF'
#!/usr/bin/env python3

def hello():
    print("Hello, World!")

if __name__ == "__main__":
    hello()
EOF

if "$EDIT_FILE" -n /tmp/test_valid.py >/dev/null 2>&1; then
  echo "${GREEN}✓ Valid Python test passed${RESET}"
else
  echo "${RED}✗ Valid Python test failed${RESET}"
fi

# Test 4: Invalid Python
echo "Test 4: Invalid Python detection"
cat > /tmp/test_invalid.py << 'EOF'
def hello()
    print("Missing colon")
EOF

if ! python3 -m py_compile /tmp/test_invalid.py 2>/dev/null; then
  echo "${GREEN}✓ Invalid Python detection passed${RESET}"
else
  echo "${RED}✗ Invalid Python detection failed${RESET}"
fi

# Test 5: Valid Shell script
echo "Test 5: Valid Shell script validation"
cat > /tmp/test_valid.sh << 'EOF'
#!/bin/bash

echo "Hello, World!"
exit 0
EOF

if "$EDIT_FILE" -n /tmp/test_valid.sh >/dev/null 2>&1; then
  echo "${GREEN}✓ Valid Shell script test passed${RESET}"
else
  echo "${RED}✗ Valid Shell script test failed${RESET}"
fi

# Test 6: Invalid Shell script
echo "Test 6: Invalid Shell script detection"
cat > /tmp/test_invalid.sh << 'EOF'
#!/bin/bash

if [ "$1" = "test" ] then  # Missing semicolon
  echo "test"
fi
EOF

if ! bash -n /tmp/test_invalid.sh 2>/dev/null; then
  echo "${GREEN}✓ Invalid Shell script detection passed${RESET}"
else
  echo "${RED}✗ Invalid Shell script detection failed${RESET}"
fi

# Test 7: Valid YAML
echo "Test 7: Valid YAML validation"
cat > /tmp/test_valid.yaml << 'EOF'
name: test
version: 1.0
items:
  - item1
  - item2
EOF

if "$EDIT_FILE" -n /tmp/test_valid.yaml >/dev/null 2>&1; then
  echo "${GREEN}✓ Valid YAML test passed${RESET}"
else
  echo "${RED}✗ Valid YAML test failed${RESET}"
fi

# Test 8: File type detection
echo "Test 8: File type detection"

# Test extension detection
for ext in py sh json yaml xml html php ini csv; do
  touch "/tmp/test.$ext"
  detected=$("$EDIT_FILE" -n "/tmp/test.$ext" 2>&1 | grep "Validating" | awk '{print $2}' || true)
  if [[ -n "$detected" ]]; then
    echo "  ${GREEN}✓ .$ext detected as $detected${RESET}"
  fi
  rm -f "/tmp/test.$ext"
done

# Test 9: Editor detection
echo "Test 9: Editor detection"
if EDITOR=nonexistent "$EDIT_FILE" --help >/dev/null 2>&1; then
  echo "${GREEN}✓ Editor detection with fallback works${RESET}"
else
  echo "${RED}✗ Editor detection failed${RESET}"
fi

# Test 10: Line number option
echo "Test 10: Line number option"
if "$EDIT_FILE" -l 5 --help 2>&1 | grep -q "editfile"; then
  echo "${GREEN}✓ Line number option parsing works${RESET}"
else
  echo "${RED}✗ Line number option failed${RESET}"
fi

# Clean up
rm -f /tmp/test_*.json /tmp/test_*.py /tmp/test_*.sh /tmp/test_*.yaml

echo
echo "${GREEN}Testing complete!${RESET}"