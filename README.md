# editfile - Developer's Text Editor with Built-in Validation

A terminal-based text editor wrapper that adds comprehensive syntax validation to your editing workflow. Built as a validation layer on top of the [filetype package](https://github.com/Open-Technology-Foundation/filetype), editfile provides automatic file type detection, syntax validation for 10 file formats, and atomic saves.

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
- **File Type Detection** - From the extension, the shebang line, or the content (via the filetype package)
- **Interactive Error Recovery** - When validation fails, choose to re-edit, save anyway, or quit
- **Atomic Saves** - You edit a working copy; the original is replaced in a single rename, and only when you save
- **PATH Search** - Finds scripts on your PATH and offers to edit them
- **Binary Protection** - Refuses to edit binary files
- **Line Positioning** - Jump directly to a line number
- **Shellcheck Integration** - Optional shell script analysis (with the `-s` flag)

### Editor Integration
- **Syntax Highlighting** - The editor is started with the syntax that matches the file type
- **Multi-Editor Support** - Works with joe, nano, vim, emacs, VS Code, helix, micro, zed, or any other command in `$EDITOR`
- **Editor Selection** - Uses `$EDITOR`; vim when it is not set

### Safety Features
- Symlink resolution (edits the actual file, not the link)
- Permission checking (read and write, file and directory)
- Self-edit protection (refuses to edit the running script)
- Change detection (an unchanged file is neither validated nor rewritten)
- Lost-update guard (asks before overwriting a file that changed on disk while you were editing)
- File mode preserved on save
- Edits survive an interrupted or failed session: the working copy is kept and its path is reported

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
│  • filetype - Type detection                │
│  • Syntax highlighting configuration        │
└─────────────────┬───────────────────────────┘
                  │ launches
┌─────────────────▼───────────────────────────┐
│  Your Editor                                │
│  vim, nano, joe, emacs, VS Code, etc.       │
└─────────────────────────────────────────────┘
```

### Workflow

1. **File Resolution** - Looks for the file as given; a bare name that does not exist is searched for in PATH
2. **Binary Check** - Refuses anything that is not a regular text file (`file` character-set detection, then a NUL-byte check)
3. **Type Detection** - Identifies the file type with the filetype library (extension, shebang, or content)
4. **Working Copy** - Creates a hidden working copy beside the target, keeping the extension so highlighting works
5. **Editor Launch** - Uses editcmd to open the working copy with the right syntax highlighting
6. **Change Detection** - Compares the working copy with the original; no change means nothing is written
7. **Validation** - Runs the validator for the file type (unless `-n` is given)
8. **Interactive Handling** - On validation failure, prompts: [e]dit again, [s]ave anyway, or [q]uit
9. **Lost-Update Check** - Asks before overwriting if the target changed on disk in the meantime
10. **Atomic Replace** - Renames the working copy over the target, with the original file mode

## Installation

### Quick Start

editfile needs the [filetype package](https://github.com/Open-Technology-Foundation/filetype) (it provides `editcmd` and the type detection library). Install that first:

```bash
git clone https://github.com/Open-Technology-Foundation/filetype.git
cd filetype && sudo make install && cd ..
```

Then editfile:

```bash
git clone https://github.com/Open-Technology-Foundation/editfile.git
cd editfile
sudo make install        # Install editfile and bash completion
```

### Available Targets

```bash
make                # Show help and available targets
sudo make install   # Install editfile and bash completion
sudo make uninstall # Remove editfile and bash completion
make test           # Run the test suites
make check          # Report whether editfile is on your PATH
```

### Custom Install Location

```bash
# Install to a custom prefix
sudo make install PREFIX=/opt/editfile

# Packaging (staged install)
make install DESTDIR=/tmp/pkg PREFIX=/usr
```

### Install Optional Validators (Recommended)

For full validation support:

```bash
# Ubuntu/Debian
sudo apt install jq yamllint libxml2-utils shellcheck php-cli tidy

# Fedora/RHEL/Rocky
sudo dnf install jq yamllint libxml2 ShellCheck php-cli tidy

# Python fallbacks (only needed when the tools above are missing)
pip install PyYAML        # YAML without yamllint
pip install tomli         # TOML on Python older than 3.11 (3.11+ has tomllib built in)

# Check what's installed
type -P jq yamllint xmllint shellcheck php tidy python3
```

**Note**: A missing validator produces a `Not validated: ...` warning that names what to install. It does not prevent editing or saving.

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
| `-l`, `--line LINE` | Jump to specified line number (`-l 42` or `-l42`) |
| `-s`, `--shellcheck` | Run shellcheck on shell scripts (in addition to bash -n) |
| `-v`, `--verbose` | Enable informational messages (default) |
| `-q`, `--quiet` | Suppress informational messages |
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
# "Edit executable '/usr/local/bin/backup-script'? [y/N]"
```

Only a bare name is searched for; a name containing a `/` is always taken as a path. Answer `y` or `yes` and press Enter; anything else declines.

#### Creating New Files
```bash
editfile newfile.py             # Prompts: "Create 'newfile.py'? [y/N]"
editfile config/app.yaml        # Creates the directory if needed
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

| Type | Recognised by | Primary Validator | Fallback |
|------|---------------|-------------------|----------|
| JSON | .json | jq | python3 json.tool |
| YAML | .yaml, .yml | yamllint (syntax and duplicate keys) | python3 PyYAML |
| XML | .xml | xmllint | python3 xml.etree |
| HTML | .html, .htm | tidy (errors fail, warnings are shown) | - |
| Python | .py, python shebang | python3 `compile()` (nothing is executed or written) | - |
| Shell | .sh, .bash, sh/bash shebang | bash -n (+ shellcheck advice with `-s`) | - |
| PHP | .php, php shebang | php -l | - |
| INI | .ini | awk (malformed section headers) | - |
| CSV | .csv | python3 csv module (consistent column count) | awk |
| TOML | .toml | python3 tomllib (3.11+) | tomli, toml |

Type detection belongs to the filetype package, so the list above is exactly what it maps to these types. Related extensions such as `.jsonc`, `.jsonl`, `.xhtml`, `.zsh`, `.conf`, `.cfg` and `.tsv` are **not validated**.

A few plain-text formats are currently classified as binary by the filetype package and are refused (exit status 10): SVG images, armoured PGP keys, SubRip subtitles and other text whose MIME type is not `text/...`. Edit those with your editor directly.

When no validator for the type is installed, editfile says so (`Not validated: ...`) and saves the file unvalidated.

### Syntax Highlighted Only

Everything else the filetype package recognises is opened with syntax highlighting and saved without validation, for example:

**Programming Languages**: JavaScript, TypeScript, C, C++, Java, Kotlin, Go, Rust, Ruby, Perl, Lua, Tcl, Erlang, Elixir, Haskell, Lisp, OCaml, Scala, Swift, R, Zig

**Markup/Config**: Markdown, TeX, SQL, CSS, conf files, Git config files

**Data/Build**: Dockerfile, Makefile, CMake, Gradle, Terraform, Nix, protobuf

**Other**: Diff/Patch files

See the [filetype package](https://github.com/Open-Technology-Foundation/filetype) for the complete list.

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
  [e] Edit again   - Fix errors and retry (your changes are still in the working copy)
  [s] Save anyway  - Save despite the errors (not recommended)
  [q] Quit         - Discard changes and exit
```

Closing the prompt (Ctrl-D) or interrupting it (Ctrl-C) is not an answer: nothing is saved, and the working copy with your edits is kept and its path reported.

### Example Session

```bash
$ editfile config.json

editfile: ◉ Launching editor with syntax highlighting
# (you edit and save the file with a syntax error)

editfile: ◉ Validating json syntax
editfile: ✗ Validation failed:
jq: parse error: Expected separator between values at line 1, column 22
editfile: Options:
editfile:   [e] - Edit again
editfile:   [s] - Save anyway (not recommended)
editfile:   [q] - Quit without saving
editfile: What would you like to do? [e/s/q]: e

editfile: ◉ Launching editor with syntax highlighting
# (editor reopens with your changes still there)
# (you fix the error and save)

editfile: ◉ Validating json syntax
editfile: ✓ Validated
editfile: ✓ '/home/you/project/config.json' saved
```

### Validator Priority

Each file type uses the best available validator:

1. **Specialized tools first** (jq, yamllint, xmllint)
2. **Fallback to Python** for JSON, YAML and XML (if the specialized tool is missing)
3. **Warn if no validator** (`Not validated: ...`; the file is still saved)

## Editor Configuration

### Editor Selection Priority

1. `$EDITOR` environment variable (if set)
2. Otherwise vim

There is no auto-detection: if `$EDITOR` is not set and vim is not installed, set `$EDITOR`.

### Set Your Preferred Editor

```bash
# In ~/.bashrc or ~/.bash_profile
export EDITOR=nano      # Use nano
export EDITOR=vim       # Use vim
export EDITOR=joe       # Use joe
export EDITOR=emacs     # Use emacs
export EDITOR='code --wait'   # Use VS Code (the editor must wait, see below)
```

### Supported Editors

editcmd knows these editors by name and passes them the line number (`-l`) in their own syntax:

- **joe** (also `jstar`, `jj`), **nano**, **vim** (also `vi`, `nvim`), **emacs** - started with the syntax for the file type
- **VS Code** (`code`), **helix** (`hx`), **micro**, **zed** - these detect the syntax themselves

Any other value of `$EDITOR` is run as given, with the file name appended. It may contain options (`EDITOR='code --wait'`), and it gets neither `-l` nor a syntax setting.

**The editor must not return until you have finished.** editfile reads the working copy when the editor command exits. An editor that hands the file to a background window and returns at once (`code`, `zed`, ...) looks like "no changes made"; give it its wait option, for example `EDITOR='code --wait'`.

The editor runs with your own `PATH`, not the restricted one editfile uses for its validators.

**Known limitation:** files recognised by their name and not by an extension (`Makefile`, `Dockerfile`, `.bashrc`, `.gitignore`) are opened as plain text. The editor is given the working copy, whose name is different.

## Dependencies

### Required
- **bash 5.2+** - Shell interpreter
- **filetype package** - Provides filetype and editcmd
  - Install: https://github.com/Open-Technology-Foundation/filetype
- **GNU coreutils and friends** - file, head, od, cmp, cp, mv, mktemp, stat, chmod, realpath, awk
- **Text editor** - vim, or whatever `$EDITOR` names

### Optional Validators

Install these for enhanced validation (any combination works):

#### Package Managers
```bash
# Ubuntu/Debian
apt install jq yamllint libxml2-utils shellcheck php-cli tidy

# Fedora/RHEL
dnf install jq yamllint libxml2 ShellCheck php-cli tidy

# Arch Linux
pacman -S jq yamllint libxml2 shellcheck php tidy

# Alpine Linux
apk add jq yamllint libxml2-utils shellcheck php tidy
```

#### Python Validators
```bash
# YAML without yamllint
pip install PyYAML

# TOML: Python 3.11+ needs nothing (tomllib is in the standard library)
pip install tomli          # Python older than 3.11
```

#### Validator Check
```bash
# Check which validators are available
type -P jq yamllint xmllint shellcheck php tidy python3
```

## Use Cases

### 1. Configuration Management
Prevent broken config files from being deployed:

```bash
editfile docker-compose.yml     # YAML syntax and duplicate keys
editfile .gitlab-ci.yml         # Check CI/CD syntax
editfile pyproject.toml         # TOML syntax
editfile settings.ini           # INI section headers
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
editfile schema.xml             # XML well-formedness
editfile index.html             # HTML validation
editfile endpoints.yaml         # API endpoint config
```

## Security

### Protection Mechanisms
- **File names are data** - A file name is never evaluated as shell code or interpolated into a program; validators read the file on standard input
- **Isolated Python helpers** - The Python-based checks run with `-I` or `-P`, so a `csv.py` or `json.py` in the directory you are standing in is not imported
- **Restricted PATH for tools** - editfile finds its own tools and validators in `/usr/local/bin:/usr/bin:/bin` only; your editor still runs with your own PATH
- **Working copy names** - The working copy's name is built from a sanitized form of the file name
- **Binary File Protection** - Refuses files that are not regular text files
- **Symlinks** - The target is resolved first, so the real file is edited; a working copy that has been replaced by a symlink is not installed
- **Self-Edit Protection** - Refuses to edit the running script

### Things To Know
- **Do not run editfile as root in a directory other users can write to** (`/tmp`, a shared upload directory). The working copy lives beside the target, and a user who can write to that directory can interfere with it. Use `sudoedit` for that case.
- A failed or interrupted session leaves a hidden working copy (`.name_XXXXXX.ext`) beside the target, on purpose: it holds your edits. Remove it once you have recovered them.
- "Save anyway" writes a file that failed validation. Use it knowingly.

### Security Best Practices
- Validate configuration files before deployment
- Use the `-s` flag for shell scripts to get shellcheck's advice
- Read the validation output; a `Not validated` warning means nothing was checked
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
sudo make install

# Verify installation
type -P editcmd
ls -l /usr/local/bin/editcmd
ls -l /usr/local/bin/filetype
```

#### 2. "Not validated" Warning

**Problem**: No validation tool for this file type is installed. The message names what to install, for example `Not validated: no JSON validator available (install jq or python3)`. The file is saved without being checked.

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

#### 3. Editor Not Opening / Wrong Editor / "No changes made" Straight Away

**Problem**: `$EDITOR` is not set (vim is used), or it names an editor that returns before you have finished (see [Supported Editors](#supported-editors))

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

**Problem**: No read or write access to the file, or no write access to its directory. The directory must be writable even for an existing file, because the working copy is created beside it and renamed over it.

**Solution**:
```bash
# For system files
sudo editfile /etc/hosts        # sudo usually drops $EDITOR, so vim is used

# For user files, check permissions
ls -la file.txt
chmod u+w file.txt              # Add write permission
```

#### 6. Binary File Refusal

**Problem**: editfile refuses to edit a text file it thinks is binary

editfile refuses a file in two cases:

1. `file` recognises no character set in it **and** there is a NUL byte in its first 4096 bytes. A file with a recognised character set (UTF-8, UTF-16, ISO-8859, ...) passes this test even though UTF-16 text is full of NUL bytes.
2. The filetype package classifies it as a binary format (an image, an archive, a compiled program).

**Diagnosis**:
```bash
file -b --mime-encoding filename         # "binary" means no character set was recognised
head -c 4096 filename | od -An -tx1 | grep -c ' 00'   # Lines containing NUL bytes
filetype filename                        # "binary" means the filetype package refuses it
```

#### 7. PATH Search Not Working

**Problem**: Can't find executable in PATH

**Debug**:
```bash
# Check if file exists in PATH
type -P scriptname

# Check PATH variable
echo "$PATH"

# Use absolute path instead
editfile /usr/local/bin/scriptname
```

The search applies only to a bare name that does not exist in the current directory, finds files only (not aliases, functions or builtins), and refuses binaries such as compiled programs.

### Debug Mode

```bash
# Enable bash debug output
bash -x editfile file.txt

# Check validation manually
jq empty file.json              # Test JSON
yamllint -d '{rules: {key-duplicates: enable}}' file.yaml   # Test YAML the way editfile does
bash -n script.sh               # Test shell script
```

### Exit Status

| Status | Meaning |
|-------:|---------|
| 0 | Saved, nothing to save, or you answered no to a question |
| 1 | Not saved: the editor failed, you declined an overwrite, or the validation prompt got no answer |
| 2 | Usage error |
| 5 | I/O error (the directory or working copy could not be created, or the save failed) |
| 10 | Not an editable text file (binary, directory, device) |
| 13 | Permission denied |
| 16 | Refused to edit the running script |
| 18 | The filetype package is missing |
| 22 | Invalid argument |
| 129, 130, 143 | Ended by SIGHUP, SIGINT, SIGTERM |

`editfile --help` has the full table.

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
make test                            # The regression suite
./tests/test_regressions.sh C1 S7    # Selected cases, by ID
EDIT_FILE=/path/to/copy ./tests/test_regressions.sh   # Test another copy of the program

make mutation                        # Do the tests notice a break? (slow)
```

### Test Coverage

`tests/test_regressions.sh` runs the real program with a scripted stand-in for the editor and checks outcomes: file content and mode, exit status, messages, and what is left on disk. It covers:
- ✓ Every validator accepting a valid file and rejecting an invalid one
- ✓ The [e]dit / [s]ave / [q]uit prompt, and prompts that are closed or interrupted
- ✓ Signals (SIGINT, SIGTERM, SIGHUP) and editor failures: nothing saved, edits kept
- ✓ Saving: unchanged files, modes and umask, symlinks, new directories, files changed or created by someone else, a failing rename
- ✓ Binary detection, including files in other character sets that must stay editable
- ✓ File and directory names containing shell or Python syntax, and Python modules planted in the working directory
- ✓ PATH search, options, and the documented exit statuses

A case that needs a tool which is not installed is reported as skipped, not passed.

### Mutation Check

`tests/mutate.sh` (`make mutation`) tests the tests. It copies the program and the completion file to a private directory and runs the whole suite there once; a case that already fails stops the run, since it would credit every break routed to it. Then it breaks one behaviour at a time with `sed` (the mode no longer restored on save, `[q]` saving, a file name evaluated as shell code, …) and runs the cases that should notice. A break that no case notices is reported as `MISSED`; a `sed` that no longer matches the code is reported as `??` (change the program and the mutant that targets it must change too); a break whose cases were all skipped is `untested`. The status is 0 only when every break was caught.

### Manual Testing

```bash
# Test JSON validation
echo '{"valid": "json"}' > test.json
editfile test.json

echo '{invalid json}' > bad.json
editfile bad.json                # Change something and save: validation fails
                                 # (an unchanged file is not validated)

# Test shellcheck integration
echo '#!/bin/bash' > test.sh
echo 'var=foo' >> test.sh
echo 'echo $var' >> test.sh
editfile -s test.sh              # Change something and save: shellcheck warns about quoting

# Test PATH search
editfile editcmd                 # Offers to edit the script found on PATH
editfile bash                    # Found on PATH, refused: it is a binary
```

## Contributing

Contributions welcome! Please ensure:

1. **Code Quality**
   - Follow the [Bash Coding Standard](https://github.com/Open-Technology-Foundation/bash-coding-standard)
   - Pass shellcheck without errors: `shellcheck editfile`
   - Use 2-space indentation (not tabs)
   - Declare all variables with `declare` or `local`

2. **Testing**
   - Add tests for new validators and for every behaviour change
   - Ensure all tests pass: `make test`

3. **Documentation**
   - Update README.md for new features
   - Update help text in the script
   - Add usage examples

### Adding a New Validator

1. Find the type name the filetype library reports: `bash -c 'source "$(type -P filetype)" && filetype "$1"' _ yourfile` (the `filetype` command itself prints the name mapped for your editor, which can differ). Add a mapping in `detect_file_type()` only if you want a different name
2. Create a `validate_<type>()` function: return 0 when the file is valid, 1 when it is not (diagnostics on stdout or stderr), and `ERR_NODEP` with a one-line message when there is no tool to check it with
3. Add the type name to the list in `validate_file()`
4. Update the validators table in README.md and the help text
5. Add an accept/reject case in `tests/test_regressions.sh`

Feed the file on standard input where the tool allows it. That keeps the working copy's name out of the diagnostics, and file names out of the tool's argument parsing.

Example (JavaScript, which the library reports as `js`):
```bash
validate_js() {
  local -- filepath=$1

  if command -v node &>/dev/null; then
    node --check - < "$filepath" || return 1
    return 0
  fi

  echo 'no JavaScript validator available (install node)'
  return "$ERR_NODEP"
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
