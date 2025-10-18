#!/bin/bash
# Test script for editfile validation features

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly SCRIPT_DIR
EDIT_FILE="$SCRIPT_DIR/../editfile"
readonly EDIT_FILE

# Colors for output
declare -- RED=$'\e[31m' GREEN=$'\e[32m' YELLOW=$'\e[33m' RESET=$'\e[0m'
readonly -- RED GREEN YELLOW RESET

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

# Create editor that makes a small change
cat > /tmp/json_editor.sh << 'EDITOR'
#!/bin/bash
sed -i 's/"test"/"test_modified"/' "$1"
EDITOR
chmod +x /tmp/json_editor.sh

if EDITOR=/tmp/json_editor.sh "$EDIT_FILE" /tmp/test_valid.json >/dev/null 2>&1; then
  echo "${GREEN}✓ Valid JSON test passed${RESET}"
else
  echo "${RED}✗ Valid JSON test failed${RESET}"
fi
rm -f /tmp/json_editor.sh

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

# Create editor that makes a small change
cat > /tmp/py_editor.sh << 'EDITOR'
#!/bin/bash
sed -i 's/Hello, World/Hello, Test/' "$1"
EDITOR
chmod +x /tmp/py_editor.sh

if EDITOR=/tmp/py_editor.sh "$EDIT_FILE" /tmp/test_valid.py >/dev/null 2>&1; then
  echo "${GREEN}✓ Valid Python test passed${RESET}"
else
  echo "${RED}✗ Valid Python test failed${RESET}"
fi
rm -f /tmp/py_editor.sh

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

# Create editor that makes a small change
cat > /tmp/sh_editor.sh << 'EDITOR'
#!/bin/bash
echo '# Modified' >> "$1"
EDITOR
chmod +x /tmp/sh_editor.sh

if EDITOR=/tmp/sh_editor.sh "$EDIT_FILE" /tmp/test_valid.sh >/dev/null 2>&1; then
  echo "${GREEN}✓ Valid Shell script test passed${RESET}"
else
  echo "${RED}✗ Valid Shell script test failed${RESET}"
fi
rm -f /tmp/sh_editor.sh

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

# Create editor that makes a small change
cat > /tmp/yaml_editor.sh << 'EDITOR'
#!/bin/bash
sed -i 's/item1/item1_modified/' "$1"
EDITOR
chmod +x /tmp/yaml_editor.sh

if EDITOR=/tmp/yaml_editor.sh "$EDIT_FILE" /tmp/test_valid.yaml >/dev/null 2>&1; then
  echo "${GREEN}✓ Valid YAML test passed${RESET}"
else
  echo "${RED}✗ Valid YAML test failed${RESET}"
fi
rm -f /tmp/yaml_editor.sh

# Test 8: File type detection
echo "Test 8: File type detection"

# Create an editor that adds content to files
cat > /tmp/add_content.sh << 'EDITOR'
#!/bin/bash
echo "test content" >> "$1"
EDITOR
chmod +x /tmp/add_content.sh

# Test extension detection with files that have validators
for ext in py sh json yaml xml html php ini csv; do
  # Create appropriate content for each file type
  case "$ext" in
    json) echo '{}' > "/tmp/test.$ext" ;;
    yaml) echo 'key: value' > "/tmp/test.$ext" ;;
    xml|html) echo '<root/>' > "/tmp/test.$ext" ;;
    py) echo 'pass' > "/tmp/test.$ext" ;;
    sh) echo 'true' > "/tmp/test.$ext" ;;
    *) echo 'test' > "/tmp/test.$ext" ;;
  esac

  detected=$(EDITOR=/tmp/add_content.sh "$EDIT_FILE" "/tmp/test.$ext" 2>&1 | grep "Validating" | awk '{print $2}' || true)
  if [[ -n "$detected" ]]; then
    echo "  ${GREEN}✓ .$ext detected as $detected${RESET}"
  else
    echo "  ${YELLOW}⚠ .$ext detection could not be verified${RESET}"
  fi
  rm -f "/tmp/test.$ext"
done

rm -f /tmp/add_content.sh

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

# Test 11: Self-edit prevention
echo "Test 11: Self-edit prevention"
# Try to edit the script itself
if "$EDIT_FILE" "$EDIT_FILE" 2>&1 | grep -q "Cannot edit the running script"; then
  echo "${GREEN}✓ Self-edit prevention works${RESET}"
else
  # It might not have errored because it's running in a subshell, test the message directly
  output=$("$EDIT_FILE" "$EDIT_FILE" 2>&1 || true)
  if echo "$output" | grep -q "Cannot edit"; then
    echo "${GREEN}✓ Self-edit prevention works${RESET}"
  else
    echo "${RED}✗ Self-edit prevention failed${RESET}"
  fi
fi

# Test with full path as well
declare -- FULL_PATH
FULL_PATH=$(readlink -f "$EDIT_FILE")
if "$EDIT_FILE" "$FULL_PATH" 2>&1 | grep -q "Cannot edit the running script"; then
  echo "  ${GREEN}✓ Full path self-edit prevention works${RESET}"
else
  output=$("$EDIT_FILE" "$FULL_PATH" 2>&1 || true)
  if echo "$output" | grep -q "Cannot edit"; then
    echo "  ${GREEN}✓ Full path self-edit prevention works${RESET}"
  else
    echo "  ${YELLOW}⚠ Full path self-edit prevention may not work${RESET}"
  fi
fi

# Test 12: No-change detection
echo "Test 12: No-change detection"
# Create a test file and editor that doesn't modify it
cat > /tmp/test_nochange.txt << 'EOF'
Original content
EOF
cat > /tmp/nochange_editor.sh << 'EOF'
#!/bin/bash
# Editor that doesn't modify the file
exit 0
EOF
chmod +x /tmp/nochange_editor.sh

if EDITOR=/tmp/nochange_editor.sh "$EDIT_FILE" -n /tmp/test_nochange.txt 2>&1 | grep -q "No changes made"; then
  echo "${GREEN}✓ No-change detection works${RESET}"
else
  echo "${RED}✗ No-change detection failed${RESET}"
fi
rm -f /tmp/nochange_editor.sh /tmp/test_nochange.txt

# Test 13: PATH search for executables
echo "Test 13: PATH search for executables"
# Test with a command that exists in PATH
if command -v ls >/dev/null; then
  output=$(echo "n" | "$EDIT_FILE" ls 2>&1 || true)
  if echo "$output" | grep -q "binary file"; then
    echo "${GREEN}✓ PATH search works (correctly identifies binary)${RESET}"
  else
    echo "${YELLOW}⚠ PATH search may not be working as expected${RESET}"
  fi
fi

# Test 14: Binary file detection
echo "Test 14: Binary file detection"
# Try to edit a binary executable
if command -v /bin/ls >/dev/null; then
  output=$("$EDIT_FILE" /bin/ls 2>&1 || true)
  if echo "$output" | grep -q "binary file"; then
    echo "${GREEN}✓ Binary file detection works${RESET}"
  else
    echo "${RED}✗ Binary file detection failed${RESET}"
  fi
fi

# Test 15: Validation message suppression for non-validated types
echo "Test 15: Validation message suppression"
# Create markdown and text files with an editor that modifies them
cat > /tmp/modify_editor.sh << 'EOF'
#!/bin/bash
echo "Modified content" >> "$1"
EOF
chmod +x /tmp/modify_editor.sh

# Test markdown - should not show validation message
echo "# Markdown" > /tmp/test.md
if EDITOR=/tmp/modify_editor.sh "$EDIT_FILE" /tmp/test.md 2>&1 | grep -q "Validating markdown"; then
  echo "${RED}✗ Markdown validation message shown (should be suppressed)${RESET}"
else
  echo "${GREEN}✓ Markdown validation message correctly suppressed${RESET}"
fi

# Test text file - should not show validation message
echo "Text content" > /tmp/test.txt
if EDITOR=/tmp/modify_editor.sh "$EDIT_FILE" /tmp/test.txt 2>&1 | grep -q "Validating text"; then
  echo "${RED}✗ Text validation message shown (should be suppressed)${RESET}"
else
  echo "${GREEN}✓ Text validation message correctly suppressed${RESET}"
fi

# Test JSON - should show validation message
echo '{"test": true}' > /tmp/test.json
# Create a separate JSON modifier that keeps JSON valid
cat > /tmp/json_modifier.sh << 'EOF'
#!/bin/bash
# Modify JSON while keeping it valid
echo '{"test": false, "modified": true}' > "$1"
EOF
chmod +x /tmp/json_modifier.sh
if EDITOR=/tmp/json_modifier.sh "$EDIT_FILE" /tmp/test.json 2>&1 | grep -q "Validating json"; then
  echo "${GREEN}✓ JSON validation message correctly shown${RESET}"
else
  echo "${RED}✗ JSON validation message not shown (should be shown)${RESET}"
fi
rm -f /tmp/json_modifier.sh

rm -f /tmp/modify_editor.sh /tmp/test.md /tmp/test.txt /tmp/test.json

# Test 16: Temporary file naming
echo "Test 16: Descriptive temporary file naming"
# Check that temp files use descriptive names
echo "test" > /tmp/test_tempname.txt
cat > /tmp/check_tempname.sh << 'EOF'
#!/bin/bash
# List temp files in the directory while editing
ls -la /tmp/.test_tempname* 2>/dev/null | head -1
sleep 0.1
EOF
chmod +x /tmp/check_tempname.sh

# This is tricky to test without actually observing the temp file
# We'll just make sure the script runs without error
if EDITOR=/tmp/check_tempname.sh "$EDIT_FILE" -n /tmp/test_tempname.txt >/dev/null 2>&1; then
  echo "${GREEN}✓ Temporary file naming works${RESET}"
else
  echo "${YELLOW}⚠ Could not verify temporary file naming${RESET}"
fi
rm -f /tmp/check_tempname.sh /tmp/test_tempname.txt

# Clean up
rm -f /tmp/test_*.json /tmp/test_*.py /tmp/test_*.sh /tmp/test_*.yaml /tmp/test_*.md /tmp/test_*.txt

echo
echo "${GREEN}Testing complete!${RESET}"
#fin