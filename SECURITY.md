# Security Policy for editfile

## Reporting Security Issues

If you discover a security vulnerability in editfile, please report it by creating a private security advisory on GitHub or by emailing the maintainers directly.

**Please do not report security vulnerabilities through public GitHub issues.**

## Security Considerations

### Input Validation

editfile implements several security measures to handle potentially malicious filenames and content:

1. **Filename Sanitization**: Filenames are sanitized before creating temporary files:
   - Maximum length: 40 characters for the base name
   - Only alphanumeric characters, dots, hyphens, and underscores are preserved
   - Other characters are replaced with underscores

2. **Binary File Protection**: The tool refuses to edit binary files to prevent corruption and potential security issues.

3. **Path Resolution**: All file paths are resolved to their canonical form using `readlink -f` to prevent path traversal attacks.

### Validator Security (Fixed in v1.0.1+)

**Previous Vulnerability (CVE-PENDING)**: Versions prior to 1.0.1 contained command injection vulnerabilities in the Python-based validators (YAML, XML, TOML). Filenames with special characters could potentially execute arbitrary code.

**Fix Applied**: All Python validators now use `sys.argv[]` to pass filenames instead of string interpolation, preventing command injection.

**Affected Validators**:
- YAML validator (Python fallback)
- XML validator (Python fallback)
- TOML validator (Python)

**Example of Previous Vulnerability**:
```bash
# VULNERABLE (pre-1.0.1):
python3 -c "import yaml; yaml.safe_load(open('$filepath'))"

# SECURE (1.0.1+):
python3 -c "import sys, yaml; yaml.safe_load(open(sys.argv[1]))" "$filepath"
```

### Safe Usage Guidelines

1. **Trusted Environments**: editfile is designed for use in trusted development environments where users control the filenames.

2. **Automated Processing**: If using editfile in automated workflows that process untrusted filenames:
   - Validate and sanitize filenames before passing to editfile
   - Use the `-n` flag to skip validation if validators are not needed
   - Consider running in a sandboxed environment

3. **File Permissions**: editfile respects file and directory permissions:
   - Checks write permissions before editing
   - Refuses to edit files without proper permissions
   - Will not create parent directories without write permission

4. **Temporary Files**: Temporary files are created in the same directory as the target file:
   - Uses secure `mktemp` with randomized suffixes
   - Cleaned up automatically on exit via trap handlers
   - Inherits directory permissions

### External Validators

editfile invokes external validation tools. Ensure these are from trusted sources:

- **jq**: JSON validation
- **yamllint**: YAML validation
- **xmllint**: XML validation
- **python3**: Fallback validator for JSON, YAML, XML, Python, TOML
- **php**: PHP validation
- **shellcheck**: Shell script analysis
- **tidy**: HTML validation

### Self-Edit Protection

editfile prevents editing itself while running to avoid corruption during atomic file replacement. This is checked using canonical path comparison.

## Testing

A comprehensive security test suite is included in `test_security.sh`:

```bash
./test_security.sh
```

Tests include:
- Command injection attempts (single quotes, backticks, $())
- Filename sanitization (long names, special characters, Unicode)
- Validator security (malicious content in data fields)
- Path traversal prevention

## Security Updates

### Version 1.0.1 (2025-10-11)
- **FIXED**: Command injection in YAML validator (CRITICAL)
- **FIXED**: Command injection in XML validator (CRITICAL)
- **FIXED**: Command injection in TOML validator (HIGH)
- **ADDED**: Comprehensive security test suite
- **ADDED**: Security documentation

## Best Practices for Contributors

When contributing to editfile:

1. **Never use string interpolation** for filenames in shell commands or Python code
2. **Always quote variable expansions** in bash
3. **Use `sys.argv[]`** for passing filenames to Python scripts
4. **Test with special characters** in filenames
5. **Run security test suite** before submitting PRs
6. **Follow the BASH-CODING-STANDARD** for all shell scripts

## Secure Coding Examples

### ✅ Correct: Safe filename handling
```bash
# Bash
python3 -c "import sys, json; json.load(open(sys.argv[1]))" "$filepath"

# Use quote all variables
if [[ -n "$filename" ]]; then
  process_file "$filename"
fi
```

### ❌ Incorrect: Unsafe filename handling
```bash
# Bash - VULNERABLE to injection
python3 -c "import json; json.load(open('$filepath'))"

# Unquoted variable - can break on spaces/special chars
if [[ -n $filename ]]; then
  process_file $filename
fi
```

## Security Checklist for New Validators

When adding a new file type validator:

- [ ] Filename is passed via `sys.argv[]` or command-line arguments, not string interpolation
- [ ] All bash variables are properly quoted
- [ ] Validator fails gracefully if tool is not installed
- [ ] Error messages do not expose sensitive information
- [ ] Validator has been tested with special characters in filenames
- [ ] Validator has been tested with malicious content in file data
- [ ] Shellcheck passes with no warnings
- [ ] Security test suite passes

## Contact

For security concerns or questions, please open an issue on GitHub or contact the maintainers.

---

Last Updated: 2025-10-11
