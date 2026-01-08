#!/usr/bin/env bash
# install.sh - Installation script for editfile
set -euo pipefail
shopt -s inherit_errexit shift_verbose

# Script metadata
#shellcheck disable=SC2034  # VERSION reserved for future use per BCS0103
VERSION='1.0.0'
#shellcheck disable=SC2155  # BCS metadata: realpath in declare-r pattern
declare -r SCRIPT_PATH=$(realpath -- "$0")
#shellcheck disable=SC2034  # SCRIPT_NAME reserved for future use per BCS0103
declare -r SCRIPT_DIR=${SCRIPT_PATH%/*} SCRIPT_NAME=${SCRIPT_PATH##*/}

# Constants
readonly FILETYPE_REPO="https://github.com/Open-Technology-Foundation/filetype.git"
readonly INSTALL_DIR="/usr/local/bin"

# Color definitions
if [[ -t 1 && -t 2 ]]; then
  declare -- RED=$'\033[0;31m' GREEN=$'\033[0;32m' YELLOW=$'\033[0;33m' CYAN=$'\033[0;36m' NC=$'\033[0m'
else
  declare -- RED='' GREEN='' YELLOW='' CYAN='' NC=''
fi
readonly -- RED GREEN YELLOW CYAN NC

# Message functions
info() { >&2 echo "${CYAN}==>${NC} $*"; }
success() { >&2 echo "${GREEN}✓${NC} $*"; }
warn() { >&2 echo "${YELLOW}⚠${NC} $*"; }
error() { >&2 echo "${RED}✗${NC} $*"; }
die() { (($# > 1)) && error "${@:2}"; exit "${1:-1}"; }

# Yes/no prompt
yn() {
  local -- reply
  read -r -n1 -p "${CYAN}==>${NC} $1 [y/n] " reply
  echo
  [[ ${reply,,} == y ]]
}

# Check if running with appropriate permissions
check_permissions() {
  if [[ ! -w "$INSTALL_DIR" ]]; then
    if [[ $EUID -ne 0 ]]; then
      warn "Installation requires write permission to $INSTALL_DIR"
      info "Please run with sudo: sudo $0"
      exit 1
    fi
  fi
}

# Check for git
check_git() {
  if ! command -v git >/dev/null 2>&1; then
    die 1 "git is required but not installed" \
           "Install it with: sudo apt install git (or equivalent)"
  fi
}

# Check if filetype package is installed
check_filetype_installed() {
  if command -v editcmd >/dev/null 2>&1 && [[ -f /usr/local/bin/filetype-lib.sh ]]; then
    return 0
  fi
  return 1
}

# Install filetype package
install_filetype() {
  info "Installing filetype package dependency..."

  local -- temp_dir
  temp_dir=$(mktemp -d)
  trap 'rm -rf "$temp_dir"' EXIT

  cd "$temp_dir" || die 1 "Failed to create temporary directory"

  info "Cloning filetype repository..."
  if ! git clone --quiet "$FILETYPE_REPO" filetype; then
    die 1 "Failed to clone filetype repository"
  fi

  cd filetype || die 1 "Failed to enter filetype directory"

  info "Running filetype installation..."
  if [[ -x ./install.sh ]]; then
    if ! ./install.sh; then
      die 1 "Filetype installation failed"
    fi
  else
    die 1 "Filetype install.sh not found or not executable"
  fi

  cd - >/dev/null
  rm -rf "$temp_dir"
  trap - EXIT

  success "Filetype package installed successfully"
}

# Install editfile
install_editfile() {
  # Use SCRIPT_DIR from metadata (lines 9-10)
  info "Installing editfile..."

  # Check if editfile exists in current directory
  if [[ ! -f "$SCRIPT_DIR/editfile" ]]; then
    die 1 "editfile script not found in $SCRIPT_DIR"
  fi

  # Make executable
  chmod +x "$SCRIPT_DIR/editfile" || die 1 "Failed to make editfile executable"

  # Copy to install directory
  if ! cp "$SCRIPT_DIR/editfile" "$INSTALL_DIR/editfile"; then
    die 1 "Failed to copy editfile to $INSTALL_DIR"
  fi

  success "editfile installed to $INSTALL_DIR/editfile"
}

# Check optional validators
check_validators() {
  info "Checking optional validators..."

  local -a installed=() missing=()
  local -a validators=(
    'jq:JSON validation'
    'yamllint:YAML validation'
    'xmllint:XML validation'
    'shellcheck:Shell script analysis'
    'php:PHP validation'
    'tidy:HTML validation'
    'python3:Python/fallback validation'
  )

  local -- validator cmd desc
  for validator in "${validators[@]}"; do
    IFS=: read -r cmd desc <<< "$validator"
    if command -v "$cmd" >/dev/null 2>&1; then
      installed+=("  ${GREEN}✓${NC} $cmd - $desc")
    else
      missing+=("  ${YELLOW}✗${NC} $cmd - $desc")
    fi
  done

  if ((${#installed[@]} > 0)); then
    echo
    echo "Installed validators:"
    printf '%s\n' "${installed[@]}"
  fi

  if ((${#missing[@]} > 0)); then
    echo
    echo "Missing validators (optional):"
    printf '%s\n' "${missing[@]}"
    echo
    info "Install missing validators for full functionality:"
    echo "  Ubuntu/Debian: sudo apt install jq yamllint libxml2-utils shellcheck php-cli tidy"
    echo "  macOS:         brew install jq yamllint libxml2 shellcheck php tidy-html5"
    echo "  Fedora/RHEL:   sudo dnf install jq yamllint libxml2 ShellCheck php-cli tidy"
  fi
}

# Check Python modules
check_python_modules() {
  if command -v python3 >/dev/null 2>&1; then
    local -a installed=() missing=()

    if python3 -c "import yaml" 2>/dev/null; then
      installed+=("  ${GREEN}✓${NC} PyYAML - YAML validation")
    else
      missing+=("  ${YELLOW}✗${NC} PyYAML - YAML validation")
    fi

    if python3 -c "import tomli" 2>/dev/null || python3 -c "import toml" 2>/dev/null; then
      installed+=("  ${GREEN}✓${NC} tomli/toml - TOML validation")
    else
      missing+=("  ${YELLOW}✗${NC} tomli/toml - TOML validation")
    fi

    if ((${#installed[@]} > 0)); then
      echo
      echo "Installed Python modules:"
      printf '%s\n' "${installed[@]}"
    fi

    if ((${#missing[@]} > 0)); then
      echo
      echo "Missing Python modules (optional):"
      printf '%s\n' "${missing[@]}"
      echo
      info "Install with: pip install PyYAML tomli"
    fi
  fi
}

# Display usage
usage() {
  cat <<'EOF'
editfile installation script

USAGE
  ./install.sh [OPTIONS]

OPTIONS
  -h, --help              Show this help message
  --skip-filetype        Skip filetype package installation
  --uninstall            Uninstall editfile

DESCRIPTION
  This script installs editfile and its required dependency (filetype package).
  It will:
  1. Check for git
  2. Install filetype package (if not already installed)
  3. Install editfile to /usr/local/bin
  4. Check for optional validators

  Run with sudo if you don't have write permission to /usr/local/bin

EXAMPLES
  ./install.sh                    # Full installation
  sudo ./install.sh               # Installation with sudo
  ./install.sh --skip-filetype    # Install editfile only
  ./install.sh --uninstall        # Remove editfile

EOF
  exit "${1:-0}"
}

# Uninstall editfile
uninstall() {
  info "Uninstalling editfile..."

  if [[ -f "$INSTALL_DIR/editfile" ]]; then
    rm -f "$INSTALL_DIR/editfile" || die 1 "Failed to remove $INSTALL_DIR/editfile"
    success "editfile removed from $INSTALL_DIR"
  else
    warn "editfile not found in $INSTALL_DIR"
  fi

  info "Note: filetype package was not removed (it may be used by other tools)"
  info "To remove filetype package manually:"
  echo "  sudo rm -f /usr/local/bin/editcmd"
  echo "  sudo rm -f /usr/local/bin/filetype-lib.sh"

  exit 0
}

# Main installation
main() {
  local -i skip_filetype=0

  # Parse arguments
  while (($#)); do case "$1" in
    -h|--help)
      usage 0
      ;;
    --skip-filetype)
      skip_filetype=1
      ;;
    --uninstall)
      check_permissions
      uninstall
      ;;
    *)
      error "Unknown option: $1"
      echo "Try './install.sh --help' for more information."
      exit 22
      ;;
  esac; shift; done

  # Start installation
  echo
  info "editfile installation"
  echo

  # Check prerequisites
  check_git
  check_permissions

  # Install filetype package if needed
  if ((skip_filetype == 0)); then
    if check_filetype_installed; then
      success "filetype package already installed"
    else
      info "filetype package not found (required dependency)"
      if yn "Install filetype package from GitHub?"; then
        install_filetype
      else
        die 1 "Installation cancelled" \
               "filetype package is required for editfile to work"
      fi
    fi
  else
    warn "Skipping filetype package installation"
    if ! check_filetype_installed; then
      warn "filetype package not installed - editfile will not work without it"
    fi
  fi

  # Install editfile
  install_editfile

  # Verify installation
  if command -v editfile >/dev/null 2>&1; then
    echo
    success "Installation complete!"
    echo
    info "editfile is now available in your PATH"
    info "Run 'editfile --help' for usage information"
  else
    error "Installation completed but editfile not found in PATH"
    error "You may need to add $INSTALL_DIR to your PATH"
  fi

  # Check validators
  echo
  check_validators
  check_python_modules

  # Final instructions
  echo
  info "Quick start:"
  echo "  editfile config.json        # Edit with validation"
  echo "  editfile -l 42 script.py    # Jump to line 42"
  echo "  editfile -s deploy.sh       # Edit shell script with shellcheck"
  echo
}

# Run main
main "$@"
#fin
