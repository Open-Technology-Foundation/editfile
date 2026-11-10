# Security Policy for editfile

## Reporting Security Issues

If you discover a security vulnerability in editfile, please report it by creating a private security advisory on GitHub or by emailing the maintainers directly.

**Please do not report security vulnerabilities through public GitHub issues.**

## Security Considerations

### What editfile does with a file

editfile copies the file to a hidden working copy in the same directory, starts your editor on the copy, optionally validates it, and renames it over the original. Three things follow from that design and are worth knowing:

1. **The directory must be writable**, even for an existing file.
2. **The working copy is created by `mktemp`** with an unpredictable name. For an existing file it then takes the original's permissions, plus write permission for you; for a new file it stays private (0600) until it is saved with a mode derived from your umask.
3. **The rename is atomic.** A reader of the target sees the old content or the new content, never a mixture.

### Input Handling

1. **File names are data.** A file name is never evaluated as shell code and never interpolated into a program. It reaches external commands as one quoted argument after `--`, as the value of an option, or as a redirection; most validators do not receive it at all (see Validators below).

2. **Working copy names.** The working copy's name is derived from the file name:
   - at most 40 characters of the base name and 12 of the extension
   - only letters, digits, dots, hyphens and underscores are kept in the base name (no dots in the extension)
   - every other character is replaced with an underscore

3. **Binary files.** A file is refused when `file` recognises no character set in it and its first 4096 bytes contain a NUL byte, or when the filetype package classifies it as a binary format. Directories, devices and FIFOs are refused.

4. **Path resolution.** The path is resolved with `realpath -m`, so a symlink is followed and the real file is edited. This is not an access control: editfile edits whatever the invoking user is allowed to edit.

5. **Symlinked working copy.** Before saving, editfile checks that the working copy is still a regular file and not a symlink. If it is not, nothing is saved.

### Validators

- Validators read the file on **standard input** wherever the tool allows it. The file name is not passed, so it cannot be mistaken for an option and does not appear in diagnostics.
- The Python-based checks run **isolated**: `python3 -I` (no current directory, no `PYTHON*` variables, no user site directory on `sys.path`), or `python3 -P` for the two that may need a module installed with `pip --user` (PyYAML, tomli). A `csv.py`, `json.py` or `yaml.py` in the directory you happen to be standing in is not imported.
- editfile looks for validators in `/usr/local/bin:/usr/bin:/bin` only, whatever your `PATH` says. Your editor is the exception: it runs with your own `PATH`.
- Validation parses; it does not run the file. Python is checked with `compile()`, shell with `bash -n`, PHP with `php -l`.

### Known Limitations

1. **Root in a directory other users can write to.** The working copy lives beside the target. A user who can write to that directory can remove or replace the working copy while you are editing. The check before saving narrows the window but cannot close it. Do not run editfile as root on files in `/tmp` or a shared upload directory; use `sudoedit`, which edits a private copy.

2. **Working copies left behind on purpose.** If a session ends without saving after you have edited (the editor crashed, the save failed, the terminal closed, you pressed Ctrl-C at the validation prompt), the working copy is kept and its path is printed. It may hold sensitive content. Remove it once you have recovered your edits.

3. **"Save anyway".** After a failed validation you may save the file regardless. That is your decision; editfile does not second-guess it.

4. **Missing validators.** When no validator for the file type is installed, the file is saved with a `Not validated` warning. Nothing was checked.

5. **The environment is trusted.** editfile is a bash script, and bash imports exported shell functions, which take precedence over commands of the same name. The restricted `PATH` does not protect against a caller who controls the environment. editfile is not a privilege boundary: do not run it with elevated rights from an environment you do not control (`sudo -E`, a setuid wrapper).

### Safe Usage Guidelines

1. **Trusted Environments**: editfile is designed for use in trusted development environments.

2. **Automated Processing**: editfile is interactive. If you script it, give it a scripted `$EDITOR`, close or supply standard input for its prompts, and check its exit status.

3. **File Permissions**: editfile checks read and write permission on the file and write permission on its directory before starting the editor, and exits with status 13 if any is missing.

4. **Temporary Files**: Created in the same directory as the target with `mktemp`; removed on exit, except a working copy holding unsaved edits (see Known Limitations).

### External Tools

editfile invokes external tools. Ensure these are from trusted sources:

- **filetype / editcmd**: type detection and editor launch
- **jq**: JSON validation
- **yamllint**: YAML validation
- **xmllint**: XML validation
- **python3**: validator for Python, CSV and TOML; fallback for JSON, YAML and XML
- **php**: PHP validation
- **shellcheck**: Shell script analysis
- **tidy**: HTML validation

### Self-Edit Protection

editfile refuses to edit its own script file (exit status 16). The check compares canonical paths.

## Testing

`tests/test_regressions.sh` runs the real program and checks outcomes. Its security-relevant cases:

```bash
./tests/test_regressions.sh S8 S8b S8c S8d H3a H3b H3c H3d H3e H4 M1a M1c M2 L1 L1b
```

- **S8** - file names containing spaces, quotes, backticks, `$()`, semicolons, `*`, a leading dash, a newline, non-ASCII characters, or 250 characters are only ever names, and the working copy handed to the editor is named from `[a-zA-Z0-9._-]` only
- **S8b-S8d** - a directory name holding shell and Python syntax reaches the YAML, XML and TOML validators (their Python fallbacks included) as data, never as code
- **H3a-H3e** - a Python module planted in the working directory is not imported by any validator
- **H4** - a working copy swapped for a symlink is not installed
- **M1a, M1c** - binary files are refused regardless of their extension
- **M2** - the editor runs with the caller's PATH
- **L1, L1b** - a function name (one of editfile's own, or one exported by the caller) does not redirect PATH search or the library lookup

`make mutation` (`tests/mutate.sh`) checks that these cases fail when the behaviour they guard is broken, for example a file name evaluated as shell code (S8) or a Python validator run without isolation (H3a, H3b).

## Security Updates

### Version 1.3.0 (2026-11-10)
- **FIXED**: Python validators imported modules from the current directory (`csv.py`, `json.py`, ...)
- **FIXED**: Ctrl-C in the editor could end the session and delete the edits
- **FIXED**: a failed save, a signal, or a closed prompt deleted the edits
- **FIXED**: binary detection depended on pipeline timing for large files
- **CHANGED**: validators read standard input; the editor runs with the caller's PATH
- **ADDED**: check that the working copy is still a regular file before saving
- **REMOVED**: the older test suites, including `tests/test_security.sh`; its hostile-name checks are now cases S8 and S8b-S8d of `tests/test_regressions.sh`

### Version 1.0.1 (2025-10-11)
- **FIXED**: Command injection in YAML validator (CRITICAL)
- **FIXED**: Command injection in XML validator (CRITICAL)
- **FIXED**: Command injection in TOML validator (HIGH)
- **ADDED**: Security test suite
- **ADDED**: Security documentation

Versions before 1.0.1 interpolated the file name into Python source:

```bash
# VULNERABLE (pre-1.0.1): the file name becomes code
python3 -c "import yaml; yaml.safe_load(open('$filepath'))"
```

## Best Practices for Contributors

When contributing to editfile:

1. **Never interpolate** a file name into shell or Python source
2. **Feed files on standard input** where the tool allows it; otherwise pass the name as one argument after `--`
3. **Run Python helpers with `-I`** (or `-P` when a user-installed module is needed)
4. **Always quote variable expansions** in command arguments
5. **Test with hostile file names** (see case S8)
6. **Run `make test`** before submitting PRs
7. **Follow the BASH-CODING-STANDARD** for all shell scripts

## Secure Coding Examples

### ✓ Correct

```bash
# The file goes in on standard input; -I keeps the current directory off sys.path
python3 -I -c 'import sys, json; json.load(sys.stdin)' < "$filepath"

# Quoted, and -- ends option parsing: a name starting with - stays a name
rm -f -- "$tempfile"
```

### ✗ Incorrect

```bash
# The file name becomes Python code
python3 -c "import json; json.load(open('$filepath'))"

# No injection, but json.py in the current directory is imported and run
python3 -c 'import sys, json; json.load(open(sys.argv[1]))' "$filepath"

# Unquoted: word splitting and globbing; a name starting with - becomes an option
rm -f $tempfile
```

## Security Checklist for New Validators

When adding a new file type validator:

- [ ] The file is read from standard input, or its name is passed as a single argument after `--`
- [ ] No file name or file content is interpolated into code
- [ ] Python helpers run with `-I` (or `-P`)
- [ ] The validator parses the file and does not execute it
- [ ] With no tool installed it returns `ERR_NODEP` and a one-line message, so the save is reported as not validated
- [ ] Tested with hostile file names and with malicious content in the data
- [ ] Shellcheck passes with no warnings
- [ ] `make test` passes

## Contact

For security concerns or questions, please open an issue on GitHub or contact the maintainers.

---

Last Updated: 2026-11-10
