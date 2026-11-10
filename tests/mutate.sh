#!/usr/bin/env bash
#shellcheck disable=SC2016  # the sed expressions name the program's $variables literally
# Mutation check for editfile: break one behaviour at a time in a copy of the
# program or of the completion file, run the regression cases named for it,
# and report any break those cases do not notice. Each one is a hole in the tests.
set -euo pipefail
shopt -s inherit_errexit
declare -rx PATH=/usr/local/bin:/usr/bin:/bin

#shellcheck disable=SC2155  # BCS metadata: realpath in declare-r pattern
declare -r SCRIPT_PATH=$(realpath -- "$0")
declare -r SCRIPT_DIR=${SCRIPT_PATH%/*} SCRIPT_NAME=${SCRIPT_PATH##*/}
declare -r REPO=${SCRIPT_DIR%/*}
declare -r PROGRAM=editfile COMPLETION=editfile.bash_completion

declare -i CAUGHT=0 MISSED=0 UNTESTED=0 UNJUDGED=0
# The counts from the suite's last summary line
declare -i PASSED=0 FAILED=0 SKIPPED=0
declare -- TREE='' LAST_LINE=''

die() {
  >&2 echo "$SCRIPT_NAME: ${*:2}"
  exit "$1"
}

usage() {
  cat <<USAGE
Usage: $SCRIPT_NAME [-h]

Copies editfile, its completion file and tests/test_regressions.sh to a
private directory and runs the whole suite there once: a case that fails on
the unbroken program would credit every mutant routed to it, so the run stops.
Then, for each mutant, one behaviour is broken with sed and the cases that
should notice are run:

  caught    at least one of those cases failed
  MISSED    they ran and passed: a hole in the tests
  ??        not judged: the sed failed, one of its expressions changed
            nothing, or the mutant does not parse (update the mutant); or
            the suite ended without a summary line (look at the suite)
  untested  every one of those cases was skipped (a tool is not installed)

Status 0 when every mutant is caught, 1 otherwise. A full run takes minutes.
USAGE
}

# Put the unbroken files back in the private tree
restore() {
  cp -p -- "$REPO/$PROGRAM" "$TREE/$PROGRAM" || die 5 "Cannot copy ${PROGRAM@Q} to ${TREE@Q}"
  cp -p -- "$REPO/$COMPLETION" "$TREE/$COMPLETION" \
    || die 5 "Cannot copy ${COMPLETION@Q} to ${TREE@Q}"
}

# Runs the suite in the private tree on [case IDs] (none: all of them) and
# sets PASSED, FAILED and SKIPPED from its summary line, or LAST_LINE and
# returns 1 when there is none. EDIT_FILE is set here: the suite honours one
# from the environment, which would test another copy of the program
suite() {
  local -- out
  # The status is not the verdict: the summary line is
  out=$(EDIT_FILE=$TREE/$PROGRAM "$TREE/tests/test_regressions.sh" "$@" 2>&1) ||:
  if [[ ! $out =~ ([[:digit:]]+)\ passed,\ ([[:digit:]]+)\ failed,\ ([[:digit:]]+)\ skipped ]]; then
    LAST_LINE=${out##*$'\n'}
    return 1
  fi
  PASSED=${BASH_REMATCH[1]} FAILED=${BASH_REMATCH[2]} SKIPPED=${BASH_REMATCH[3]}
}

# <file> <label> <case IDs> <sed expression>...
mutant() {
  local -- file=$1 label=$2 ids=$3 expr
  local -a cases=() sed_args=()
  local -i stale=0
  # Each expression must change the file on its own: one that no longer
  # matches would leave a mutant half applied and its cases half tested
  for expr in "${@:4}"; do
    sed_args+=(-e "$expr")
    if sed -E -e "$expr" -- "$REPO/$file" | cmp -s -- "$REPO/$file" -; then
      stale+=1
    fi
  done
  read -ra cases <<<"$ids"
  restore
  if ! sed -i -E "${sed_args[@]}" -- "$TREE/$file"; then
    echo "??      $label: the sed failed"
    UNJUDGED+=1
  elif ((stale)); then
    echo "??      $label: $stale of $(($# - 3)) sed expression(s) changed nothing"
    UNJUDGED+=1
  elif ! bash -n -- "$TREE/$file" 2>/dev/null; then
    echo "??      $label: the mutant does not parse"
    UNJUDGED+=1
  elif ! suite "${cases[@]}"; then
    echo "??      $label: the suite ended without a summary: $LAST_LINE"
    UNJUDGED+=1
  elif ((FAILED)); then
    echo "caught  $label: $FAILED of ${#cases[@]} case(s) failed ($ids)"
    CAUGHT+=1
  elif ((PASSED)); then
    echo "MISSED  $label ($ids)"
    MISSED+=1
  else
    echo "untested $label: every case was skipped ($ids)"
    UNTESTED+=1
  fi
  return 0
}

# <label> <case IDs> <sed expression>...
program() { mutant "$PROGRAM" "$@"; }

# <label> <sed expression>...: the completion has one case, L12
completion() { mutant "$COMPLETION" "$1" L12 "${@:2}"; }

program_mutants() {
  program 'mode not restored on save' S3 \
    's|^    chmod -- "\$orig_mode" "\$TEMP_FILE" \\$|    : \\|'
  program 'new file keeps mktemp mode' S4 's|^    chmod -- "\$\(printf .%03o. .*$|    : \\|'
  program 'unchanged file saved anyway' S2 \
    's|^    if \(\(!file_changed\)\); then$|    if ((0)); then|'
  program 'read permission not checked' S9 \
    's|^  if \[\[ -e \$filepath && ! -r \$filepath \]\]; then$|  if ((0)); then|'
  program 'write permission not checked' S9 \
    's|^  if \[\[ -e \$filepath && ! -w \$filepath \]\]; then$|  if ((0)); then|'
  program 'q saves instead of discarding' P3 \
    's|^              discard_temps$|              editing=0; break|'
  program 's quits instead of saving' P2 \
    's|^              editing=0$|              discard_temps; return 0|'
  program 'external change overwritten' S7 \
    's|^    if ! cmp -s -- "\$ORIGINAL_BACKUP" "\$filepath"; then$|    if ((0)); then|'
  program 'cleanup never keeps edits' 'H2e H1 H2a' \
    's|^  if \(\(exitcode && EDITOR_RAN\)\) |  if ((0)) |'
  program 'no charset means binary' M1e 's|^  \[\[ \$hex != \*. 00.\* \]\]$|  return 1|'
  program 'parent directory not created' S5 's|^    mkdir -p -- "\$parent_dir" .*$|    :|'
  program '-n ignored' O1 \
    's#^    -n[|]--no-validate\)  VALIDATE=0 ;;$#    -n|--no-validate)  : ;;#'
  program '-s ignored' O2 \
    's#^    -s[|]--shellcheck\)   SHELLCHECK=1 ;;$#    -s|--shellcheck)   : ;;#'
  program '-q ignored' O3 \
    's#^    -q[|]--quiet\)        VERBOSE=0 ;;$#    -q|--quiet)        : ;;#'
  program 'symlink not resolved' S6 \
    's|^  resolved=\$\(realpath -m -- "\$FILENAME"\)|  resolved=$(realpath -m -s -- "$FILENAME")|'
  program 'library load failure is silent' R4 \
    's#^source -- "\$FILETYPE_LIB" [|][|] \{$#source -- "$FILETYPE_LIB"; false \&\& {#'
  program 'unresolvable path not named' R3 \
    's#^  resolved=\$\(realpath -m -- "\$FILENAME"\) #  FILENAME=$(realpath -m -- "$FILENAME") #' \
    '/^  FILENAME=\$resolved$/d'
  program 'self-edit allowed' S9 \
    's|^  if \[\[ \$FILENAME == "\$SCRIPT_PATH" \]\]; then$|  if ((0)); then|'
  program 'target replaced even when declined' L3a \
    's#^    yn .Overwrite it\?. [|][|] die 1 .Declined to overwrite.$#    :#'
  program 'file name evaluated as shell code' S8 \
    's#^  ft=\$\(filetype "\$filepath"\) (.*)$#  ft=$(eval "filetype $filepath") \1#'
  # The pre-1.0.1 defect, open('$filepath'). In the program's single-quoted
  # Python source that is '\'"$filepath"\'' (backslashes doubled for sed)
  local -- in_source
  IFS= read -r in_source <<'TEXT'
'\\'"$filepath"\\''
TEXT
  program 'path in Python source (YAML)' S8b \
    "s#yaml[.]parse[(]sys[.]stdin[.]buffer[)]#yaml.parse(open($in_source, \"rb\"))#"
  program 'path in Python source (XML)' S8c \
    "s#ET[.]parse[(]sys[.]stdin[.]buffer[)]#ET.parse($in_source)#"
  program 'path in Python source (TOML)' S8d \
    "s#open[(]sys[.]argv[[]1[]], mode[)]#open($in_source, mode)#"
  program 'working copy name not truncated' S8 \
    's#^  file_name_noext=\$\{file_name_noext:0:40\}$#  :#'
  program 'working copy name not sanitized' S8 \
    's#^  file_name_noext=\$\{file_name_noext//\[\^a-zA-Z0-9._-\]/_\}$#  :#'
  program 'failed type detection passes' R1 \
    's#^  ft=\$\(filetype "\$filepath"\) [|][|] return 1$#  ft=$(filetype "$filepath") ||:#'
  program 'chmod operand before --' R2 \
    's#^  chmod -- u\+w "\$TEMP_FILE" #  chmod u+w -- "$TEMP_FILE" #'
  program 'jump line never passed on' O4 \
    's#^    \(\(jump_line <= 0\)\) [|][|] editcmd_args\+=\(-l "\$jump_line"\)$#    :#'
  program 'jump line repeated on re-edit' O4 's#^    jump_line=0$#    :#'
  program 'SIGINT handler not parked' C1 's|^    trap : SIGINT$|    :|'
  program 'python not isolated (csv)' H3a "s|^    python3 -I -c '\$|    python3 -c '|"
  program 'python not isolated, seam bypassed' 'H3a H3b' \
    "s#^    python3 -I -c '\$#    command python3 -c '#" \
    "s#^    python3 -P -c '\$#    command python3 -c '#"
  program 'made directories left behind' L4 \
    's|^  while \[\[ -n \$NEW_DIR \]\] && rmdir -- "\$NEW_DIR" 2>/dev/null; do$|  while false; do|'
  program 'no hint for a binary on PATH' L2 \
    's|^          "To create a file of that name here, call it \$\{here@Q\}"$|          "no hint"|'
  program 'yes prompt reads one key' M6a \
    "s#^  read -r reply [|][|] raw_msg ''\$#  read -r -n 1 reply || raw_msg ''#"
  program 'signal exits report success' 'H2a H2c' \
    "s|^  trap 'cleanup 143' SIGTERM\$|  trap 'cleanup 0' SIGTERM|" \
    "s|^  trap 'cleanup 130' SIGINT\$|  trap 'cleanup 0' SIGINT|"
  program 'symlinked working copy installed' H4 \
    's|^  if \[\[ -L \$TEMP_FILE [|][|] ! -f \$TEMP_FILE \]\]; then$|  if ((0)); then|'
  program 'validator missing called validated' M5 's|^    "\$ERR_NODEP"\)$|    99)|'
  program 'INI header ends at the first ]' V5 's#!/\^\\\[\.\+\\\]#!/^\\[[^]]+\\]#'
  program 'version write error is fatal' L21 's#"\$VERSION" 2>/dev/null [|][|]:$#"$VERSION"#'
  program 'relative PATH entries searched' R7 \
    's#^  path=\$\(PATH=\$search type -P#  path=$(PATH=$ORIG_PATH type -P#'
  program 'line number may overflow' S9 \
    's#\^0\*\(\[\[:digit:\]\]\{1,18\}\)\$#^0*([[:digit:]]+)$#'
  program 'digit class is a locale range' R12 's#\[\[:digit:\]\]#[0-9]#g'
  program '-l value split as options' S9 's#^    -l\?\*\)  #    -l[0-9]*)  #'
  program 'empty file name skipped' S9 \
    's#^(  \[\[ -n \$1 \]\] [|][|] ).*A file name cannot be empty.$#\1return 0#'
  program 'tool output not shown' 'V5 V6' 's#^raw_msg\(\) \{ .*$#raw_msg() { :; }#'
}

completion_mutants() {
  completion 'second name offered' 's/^  \(\(have_name\)\) [|][|] _filedir$/  _filedir/'
  completion 'options offered after --' 's/^  if \(\(!options_ended\)\) && /  if /'
  completion 'bundle ending in l ignored' 's/-l[|]--line[|]-\[!-\]\*l\)/-l|--line)/'
  completion 'number word taken as a name' 's/^      want_number=0$/      :/'
  completion 'words after -- read as options' 's/^    elif \(\(options_ended\)\) [|][|] /    elif /'
  completion 'nothing after -l ignored' 's/^  \(\(!want_number\)\) [|][|] return 0$/  :/'
  completion 'old prev test, -V matches -v' \
    's/^  \(\(!want_number\)\) [|][|] return 0$/  case $prev in -l|-V) return 0 ;; *) ;; esac/'
  completion 'IFS not set' 's/^  local -- IFS=.*$/  :/'
  completion 'earlier words keep their quotes' '/^    word=\$\{word\/\/.*$/d'
  completion 'current word keeps its quotes' 's/^  bare=\$\{cur\/\/.*$/  bare=$cur/'
}

main() {
  case ${1:-} in
    -h|--help) usage; return 0 ;;
    '') ;;
    *) usage >&2; die 22 "Invalid argument ${1@Q}" ;;
  esac

  trap '[[ -z $TREE ]] || rm -rf -- "$TREE"' EXIT
  TREE=$(mktemp -d -t editfile-mutate.XXXXXXXX) || die 5 'Cannot create a private directory'
  readonly TREE
  mkdir -- "$TREE/tests" || die 5 "Cannot create ${TREE@Q}/tests"
  cp -p -- "$SCRIPT_DIR/test_regressions.sh" "$TREE/tests/" \
    || die 5 "Cannot copy the suite to ${TREE@Q}/tests"
  restore

  suite || die 1 "The suite ended without a result: $LAST_LINE"
  ((FAILED == 0)) || die 1 "$FAILED case(s) fail on the unbroken program; fix those first"
  echo "Baseline: $PASSED passed, $SKIPPED skipped"
  echo

  program_mutants
  completion_mutants

  echo
  echo "$CAUGHT caught, $MISSED missed, $UNTESTED untested, $UNJUDGED not judged"
  ((MISSED == 0 && UNTESTED == 0 && UNJUDGED == 0))
}

main "$@"
#fin
