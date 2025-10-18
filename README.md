# editfile - Developer's Text Editor with Built-in Validation

A terminal-based text editor wrapper that adds comprehensive syntax validation to your editing workflow. Built as a validation layer on top of the [filetype package](https://github.com/Open-Technology-Foundation/filetype), editfile provides automatic file type detection, syntax validation for 10+ languages/formats, and safe atomic file operations.

## Table of Contents

- [Features](#features)
- [How It Works](#how-it-works)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Usage](#usage)
- [Supported File Types](#supported-file-types)
- [Validation Workflow](#validation-workflow)
- [Editor Configuration](#editor-configuration)
- [Dependencies](#dependencies)
- [Use Cases](#use-cases)
- [Security](#security)
- [Troubleshooting](#troubleshooting)
- [Testing](#testing)
- [Contributing](#contributing)
- [License](#license)

## Features

### Core Capabilities
- **Automatic Syntax Validation** - Built-in validators for JSON, YAML, XML, Python, Shell, PHP, HTML, INI, CSV, and TOML
- **Intelligent File Type Detection** - Recognizes 46+ file types via extension, shebang, or content analysis
- **Interactive Error Recovery** - When validation fails, choose to re-edit, force save, or quit
- **Atomic File Operations** - Uses temporary files for safe editing; original never corrupted
- **PATH Search** - Automatically finds and edits executables/scripts in your PATH
- **Binary Protection** - Refuses to edit binary files to prevent corruption
- **Line Positioning** - Jump directly to specific line numbers
- **Shellcheck Integration** - Optional advanced shell script analysis (with `-s` flag)

### Editor Integration
- **Syntax Highlighting** - Automatic syntax configuration for 46+ file types
- **Multi-Editor Support** - Works with joe, nano, vim, emacs, VS Code
- **Auto-Detection** - Finds available editors or uses `$EDITOR` environment variable

### Safety Features
- Symlink resolution (edits actual file, not the link)
- Permission checking (file and directory)
- Self-edit protection (prevents corrupting the running script)
- Change detection (skips validation if file unchanged)
- Temporary file cleanup on exit/interrupt

## How It Works

editfile is a validation wrapper built on the [filetype package](https://github.com/Open-Technology-Foundation/filetype):

```
┌─────────────────────────────────────────────┐
│  editfile (this project)                    │
│  • Validation logic                         │
│  • Atomic file operations                   │
│  • Interactive error handling               │
│  • PATH search                              │
└─────────────────┬───────────────────────────┘
                  │ uses
┌─────────────────▼───────────────────────────┐
│  filetype package (dependency)              │
│  • editcmd - Editor launcher                │
│  • filetype-lib.sh - Type detection (46+)   │
│  • Syntax highlighting configuration        │
└─────────────────┬───────────────────────────┘
                  │ launches
┌─────────────────▼───────────────────────────┐
│  Your Editor                                │
│  vim, nano, joe, emacs, VS Code, etc.       │
└─────────────────────────────────────────────┘
```

### Workflow

1. **File Resolution** - Searches locally, then in PATH if not found
2. **Binary Check** - Verifies file is text (using `file` command and null-byte detection)
3. **Type Detection** - Identifies file type using filetype-lib.sh (extension, shebang, or content)
4. **Temporary Copy** - Creates temp file with preserved extension for proper syntax highlighting
5. **Editor Launch** - Uses editcmd to open file with correct syntax highlighting
6. **Change Detection** - Compares temp file with original to detect actual changes
7. **Validation** - Runs appropriate validator based on file type (if enabled)
8. **Interactive Handling** - On validation failure, prompts: [e]dit again, [s]ave anyway, or [q]uit
9. **Atomic Replace** - Moves validated temp file to final location

## Installation

### Automated Installation (Recommended)

The easiest way to install editfile with all dependencies:

```bash
# Clone the repository
git clone https://github.com/Open-Technology-Foundation/editfile.git
cd editfile

# Run the installer (automatically installs filetype package if needed)
sudo ./install.sh
```

The installer will:
1. Check for git
2. Install the filetype package dependency (if not already installed)
3. Install editfile to `/usr/local/bin`
4. Check which optional validators are available

### Manual Installation

If you prefer to install manually:

#### 1. Install the filetype Package (Required Dependency)

```bash
# Quick install (one-liner)
git clone https://github.com/Open-Technology-Foundation/filetype.git && cd filetype && sudo ./install.sh

# Or step-by-step
git clone https://github.com/Open-Technology-Foundation/filetype.git
cd filetype
sudo ./install.sh
```

This installs `editcmd` and `filetype-lib.sh` to `/usr/local/bin/`.

#### 2. Install editfile

```bash
# Clone this repository
git clone https://github.com/Open-Technology-Foundation/editfile.git
cd editfile

# Make executable
chmod +x editfile

# Install to PATH
sudo cp editfile /usr/local/bin/editfile
```

### Install Optional Validators (Recommended)

For full validation support:

```bash
# Ubuntu/Debian
sudo apt install jq yamllint libxml2-utils shellcheck php-cli tidy

# macOS with Homebrew
brew install jq yamllint libxml2 shellcheck php tidy-html5

# Fedora/RHEL/Rocky
sudo dnf install jq yamllint libxml2 ShellCheck php-cli tidy

# Python-based validators
pip install PyYAML tomli  # For YAML and TOML validation
```

**Note**: Missing validators generate warnings but don't prevent editing.

### Installation Options

```bash
# Standard installation
sudo ./install.sh

# Install editfile only (skip filetype check)
sudo ./install.sh --skip-filetype

# Uninstall editfile
sudo ./install.sh --uninstall

# View installer help
./install.sh --help
```

## Quick Start

```bash
# Edit with validation
editfile config.json

# Edit without validation (faster for large files)
editfile -n script.py

# Jump to specific line
editfile -l 42 server.py

# Edit shell script with shellcheck analysis
editfile -s deploy.sh

# Edit executable from PATH
editfile backup-script

# Create new file (with prompt)
editfile newfile.yaml
```

## Usage

### Syntax

```bash
editfile [OPTIONS] filename
```

### Options

| Option | Description |
|--------|-------------|
| `-n`, `--no-validate` | Skip syntax validation (faster for large files) |
| `-l`, `--line LINE` | Jump to specified line number |
| `-s`, `--shellcheck` | Run shellcheck on shell scripts (in addition to bash -n) |
| `-V`, `--version` | Show version and exit |
| `-h`, `--help` | Display help message |

### Examples

#### Basic Editing
```bash
editfile script.py              # Edit Python with validation
editfile config.json            # Edit JSON with validation
editfile data.yaml              # Edit YAML with validation
editfile -n large_data.xml      # Skip validation for large files
```

#### Line Positioning
```bash
editfile -l 42 script.py        # Jump to line 42
editfile -l 100 /etc/hosts      # Edit system file at line 100

# Integration with grep
line=$(grep -n "TODO" script.py | head -1 | cut -d: -f1)
editfile -l "$line" script.py
```

#### Shell Script Development
```bash
editfile deploy.sh              # Edit with bash -n validation
editfile -s deploy.sh           # Edit with bash -n + shellcheck
editfile -s -l 50 install.sh    # Jump to line 50, run shellcheck
```

#### PATH Search
```bash
editfile myscript               # Searches PATH if not local
editfile backup-script          # Edit from /usr/local/bin
editfile cln                    # Edit custom command

# When found in PATH, editfile prompts:
# "Edit executable '/usr/local/bin/backup-script'? y/n"
```

#### Creating New Files
```bash
editfile newfile.py             # Prompts: "Create 'newfile.py'? y/n"
editfile config/app.yaml        # Creates directory if needed
```

#### Configuration Files
```bash
editfile ~/.bashrc              # Shell configuration
editfile /etc/nginx/nginx.conf  # System config (requires sudo)
editfile docker-compose.yml     # Docker configuration
editfile package.json           # npm configuration
```

#### Advanced Workflows
```bash
# Find error and edit at line
error_line=$(python script.py 2>&1 | grep -oP 'line \K\d+' | head -1)
editfile -l "$error_line" script.py

# Edit and validate JSON from curl
curl https://api.example.com/config > config.json
editfile config.json

# Batch edit with validation check
for file in *.json; do
  editfile "$file" || echo "Failed: $file"
done
```

## Supported File Types

### Validated File Types (with Syntax Checking)

| Type | Extensions | Primary Validator | Fallback |
|------|-----------|-------------------|----------|
| JSON | .json, .jsonld, .jsonc | jq | python3 json.tool |
| YAML | .yaml, .yml | yamllint | python3 PyYAML |
| XML | .xml, .xsl, .xslt, .svg | xmllint | python3 xml.etree |
| HTML | .html, .htm, .xhtml | tidy | (basic check) |
| Python | .py, .pyw, .pyi | python3 -m py_compile | - |
| Shell | .sh, .bash, .zsh, .ksh, shebang | bash -n | (+ optional shellcheck) |
| PHP | .php, .phtml | php -l | - |
| INI | .ini, .conf, .cfg | awk validation | - |
| CSV | .csv, .tsv | awk column check | - |
| TOML | .toml, .tml | python3 tomli/toml | - |

### Syntax Highlighted Only (40+ additional types)

All files get syntax highlighting even without validators:

**Programming Languages**: JavaScript, TypeScript, C, C++, Java, Go, Rust, Ruby, Perl, Lua, TCL, Erlang, Elixir, Haskell, Lisp, OCaml, Scala, Swift, R

**Markup/Config**: Markdown, LaTeX, reStructuredText, AsciiDoc, SQL, Nginx config, Apache config, systemd units

**Data/Build**: Dockerfile, Makefile, CMake, Gradle, Maven, Terraform, Ansible

**Other**: Diff/Patch files, Git config, SSH config, and more

See the [filetype package](https://github.com/Open-Technology-Foundation/filetype) for the complete list of 46+ supported types.

## Validation Workflow

### When Validation Passes
```
Edit file → Make changes → Save → Validation passes → File saved ✓
```

### When Validation Fails
```
Edit file → Make changes → Save → Validation fails ✗
↓
editfile presents three options:
  [e] Edit again   - Fix errors and retry (changes preserved in temp file)
  [s] Save anyway  - Force save despite errors (not recommended)
  [q] Quit         - Discard changes and exit
```

### Example Session

```bash
$ editfile config.json

editfile: ◉ Launching editor with syntax highlighting
# (you edit and save the file with a syntax error)

editfile: ◉ Validating json file 'config.json'
parse error: Expected separator between values at line 5, column 12
editfile: ✗ Validation failed:

Options:
  [e] - Edit again
  [s] - Save anyway (not recommended)
  [q] - Quit without saving
editfile: What would you like to do? [e/s/q]: e

# (editor reopens with your changes still there)
# (you fix the error and save)

editfile: ◉ Validating json file 'config.json'
editfile: ✓ Validated
editfile: ✓ 'config.json' saved
```

### Validator Priority

Each file type uses the best available validator:

1. **Specialized tools first** (jq, yamllint, xmllint, shellcheck)
2. **Fallback to Python** (if specialized tool missing)
3. **Warn if no validator** (but still allow editing)

## Editor Configuration

### Editor Selection Priority

1. `$EDITOR` environment variable (if set)
2. Auto-detection searches for: joe → nano → vim → vi → emacs
3. Default fallback: vim

### Set Your Preferred Editor

```bash
# In ~/.bashrc or ~/.bash_profile
export EDITOR=nano      # Use nano
export EDITOR=vim       # Use vim
export EDITOR=joe       # Use joe
export EDITOR=emacs     # Use emacs
export EDITOR=code      # Use VS Code (if installed)
```

### Supported Editors

- **joe** - Joe's Own Editor
- **nano** - GNU nano
- **vim** - Vi IMproved
- **vi** - Classic vi
- **emacs** - GNU Emacs
- **VS Code** - Visual Studio Code (via `code` command)

All editors receive proper syntax highlighting configuration via editcmd.

## Dependencies

### Required
- **bash 5.2+** - Shell interpreter
- **filetype package** - Provides editcmd and filetype-lib.sh
  - Install: https://github.com/Open-Technology-Foundation/filetype
- **Standard Unix tools** - grep, awk, sed, file, od, readlink
- **Text editor** - At least one: vim, nano, joe, emacs, vi

### Optional Validators

Install these for enhanced validation (any combination works):

#### Package Managers
```bash
# Ubuntu/Debian
apt install jq yamllint libxml2-utils shellcheck php-cli tidy

# macOS
brew install jq yamllint libxml2 shellcheck php tidy-html5

# Fedora/RHEL
dnf install jq yamllint libxml2 ShellCheck php-cli tidy

# Arch Linux
pacman -S jq yamllint libxml2 shellcheck php tidy

# Alpine Linux
apk add jq yamllint libxml2-utils shellcheck php tidy
```

#### Python Validators
```bash
# YAML support
pip install PyYAML

# TOML support
pip install tomli          # Python 3.11+
pip install toml           # Older Python versions
```

#### Validator Check
```bash
# Check which validators are available
command -v jq yamllint xmllint shellcheck php tidy python3
```

## Use Cases

### 1. Configuration Management
Prevent broken config files from being deployed:

```bash
editfile nginx.conf             # Catch nginx config errors
editfile docker-compose.yml     # Validate Docker configs
editfile .gitlab-ci.yml         # Check CI/CD syntax
editfile terraform.tfvars       # Verify Terraform variables
```

### 2. Script Development
Catch syntax errors immediately:

```bash
editfile -s deploy.sh           # Bash with shellcheck
editfile backup.py              # Python syntax check
editfile install.php            # PHP lint check
```

### 3. DevOps/SRE Workflows
Quick editing of scripts in system paths:

```bash
editfile backup-script          # Edit from /usr/local/bin
editfile cleanup                # Edit system maintenance scripts
editfile -l 42 monitor          # Jump to specific line in monitoring script
```

### 4. Data File Editing
Ensure data integrity:

```bash
editfile users.csv              # Column consistency check
editfile api-response.json      # JSON structure validation
editfile translations.yaml      # YAML format verification
editfile config.toml            # TOML syntax check
```

### 5. API/Web Development
```bash
editfile api-spec.json          # OpenAPI/Swagger spec
editfile schema.xml             # XML schema validation
editfile index.html             # HTML validation
editfile endpoints.yaml         # API endpoint config
```

## Security

editfile implements multiple security measures:

### Protection Mechanisms
- **Command Injection Prevention** - All validators use safe argument passing (sys.argv[], not eval)
- **Filename Sanitization** - Temporary filenames sanitized to prevent shell injection
- **Binary File Protection** - Refuses to edit binary files (prevents corruption/exploitation)
- **Path Resolution** - Uses canonical paths to prevent traversal attacks
- **Self-Edit Protection** - Prevents editing the running script (avoids corruption during atomic replace)
- **Null Byte Detection** - Multiple methods to detect binary content

### Security Best Practices
- Always validate configuration files before deployment
- Use `-s` flag for shell scripts to catch common security issues via shellcheck
- Review validation output carefully
- Don't use `-n` (skip validation) for security-critical configs

For detailed security information and testing, see [SECURITY.md](SECURITY.md).

## Troubleshooting

### Common Issues

#### 1. "editcmd not found" Error

**Problem**: editfile can't find the filetype package

**Solution**:
```bash
# Install filetype package
git clone https://github.com/Open-Technology-Foundation/filetype.git
cd filetype
sudo ./install.sh

# Verify installation
command -v editcmd
ls -l /usr/local/bin/editcmd
ls -l /usr/local/bin/filetype-lib.sh
```

#### 2. "No validator available" Warning

**Problem**: Validation tool not installed

**Solution**:
```bash
# Install the specific validator needed
sudo apt install jq              # For JSON
sudo apt install yamllint        # For YAML
sudo apt install libxml2-utils   # For XML
pip install PyYAML               # Python YAML fallback

# Or edit without validation
editfile -n file.yaml
```

#### 3. Editor Not Opening / Wrong Editor

**Problem**: editfile can't find your preferred editor

**Solution**:
```bash
# Set EDITOR environment variable
export EDITOR=nano
editfile file.txt

# Or add to ~/.bashrc
echo 'export EDITOR=nano' >> ~/.bashrc
source ~/.bashrc
```

#### 4. Validation Fails but File Looks Correct

**Problem**: Validator is too strict or has false positives

**Options**:
```bash
# 1. Fix the actual issue (recommended)
editfile file.json              # Choose [e] to edit again

# 2. Save anyway (use with caution)
editfile file.json              # Choose [s] to force save

# 3. Skip validation entirely
editfile -n file.json           # No validation
```

#### 5. Permission Denied

**Problem**: No write access to file or directory

**Solution**:
```bash
# For system files, use sudo
sudo editfile /etc/hosts

# For user files, check permissions
ls -la file.txt
chmod u+w file.txt              # Add write permission
```

#### 6. Binary File Refusal

**Problem**: editfile refuses to edit a text file it thinks is binary

**Diagnosis**:
```bash
# Check file type
file filename
od -An -tx1 filename | head    # Look for null bytes (00)

# If truly text, it may have null bytes - handle carefully
```

#### 7. PATH Search Not Working

**Problem**: Can't find executable in PATH

**Debug**:
```bash
# Check if file exists in PATH
command -v scriptname
which scriptname

# Check PATH variable
echo "$PATH"

# Use absolute path instead
editfile /usr/local/bin/scriptname
```

### Debug Mode

```bash
# Enable bash debug output
bash -x editfile file.txt

# Check validation manually
jq empty file.json              # Test JSON
yamllint file.yaml              # Test YAML
bash -n script.sh               # Test shell script
```

### Getting Help

1. Check the help output: `editfile --help`
2. Review validator output carefully (it usually shows the exact error)
3. Test validators manually to isolate issues
4. Check file permissions and ownership
5. Verify filetype package installation
6. Report issues: https://github.com/Open-Technology-Foundation/editfile/issues

## Testing

### Run Test Suite

```bash
# Basic validation tests
./tests/test_validation.sh

# Security tests
./tests/test_security.sh
```

### Test Coverage

The validation test suite verifies:
- ✓ JSON, YAML, Python, Shell script validation (valid & invalid files)
- ✓ Editor detection and fallback
- ✓ Command-line argument parsing
- ✓ Temporary file naming and cleanup
- ✓ Binary file detection
- ✓ PATH search functionality

The security test suite verifies:
- ✓ Command injection prevention
- ✓ Filename sanitization
- ✓ Unicode and special character handling
- ✓ Path traversal prevention
- ✓ Validator security

### Manual Testing

```bash
# Test JSON validation
echo '{"valid": "json"}' > test.json
editfile test.json

echo '{invalid json}' > bad.json
editfile bad.json                # Should fail validation

# Test shellcheck integration
echo '#!/bin/bash' > test.sh
echo 'var=foo' >> test.sh
echo 'echo $var' >> test.sh
editfile -s test.sh              # Should warn about quoting

# Test PATH search
editfile bash                    # Should find /bin/bash
```

## Contributing

Contributions welcome! Please ensure:

1. **Code Quality**
   - Follow the [Bash Coding Standard](https://github.com/Open-Technology-Foundation/bash-coding-standard)
   - Pass shellcheck without errors: `shellcheck editfile`
   - Use 2-space indentation (not tabs)
   - Declare all variables with `declare` or `local`

2. **Testing**
   - Add tests for new validators
   - Ensure existing tests pass: `./tests/test_validation.sh`
   - Test security implications: `./tests/test_security.sh`

3. **Documentation**
   - Update README.md for new features
   - Update help text in the script
   - Add usage examples

### Adding a New Validator

1. Add file type detection in `detect_file_type()` function (or rely on filetype-lib.sh)
2. Create `validate_<type>()` function following existing patterns
3. Add case in `validate_file()` dispatcher
4. Update the validators table in README.md
5. Add test case in `tests/test_validation.sh`

Example:
```bash
validate_rust() {
  local -- filepath="$1"

  if command -v rustc >/dev/null 2>&1; then
    if ! rustc --crate-type lib --emit metadata "$filepath" 2>&1; then
      return 1
    fi
    return 0
  fi

  warn 'Rust compiler not available for validation'
  return 0
}
```

## License

This project is licensed under the GNU General Public License v3.0.

See the [GNU GPL v3](https://www.gnu.org/licenses/gpl-3.0.en.html) for full license text.

### Why GPL v3?

- Ensures the software remains free and open source
- Requires derivative works to also be open source
- Protects against patent claims
- Promotes community collaboration

---

## Project Links

- **Repository**: https://github.com/Open-Technology-Foundation/editfile
- **Issues**: https://github.com/Open-Technology-Foundation/editfile/issues
- **Security**: [SECURITY.md](SECURITY.md)
- **Dependencies**: [filetype package](https://github.com/Open-Technology-Foundation/filetype)

## Author

**Open Technology Foundation**

A community-driven organization focused on creating practical, well-documented open source tools for developers and system administrators.

---

**Note**: editfile is designed for developer workflows. It provides validation as a helpful safety net, but always review changes before committing to production systems.
