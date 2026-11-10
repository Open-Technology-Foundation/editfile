#!/usr/bin/env bash
# test_regressions.sh - Outcome-based regression tests for editfile
#
# Each test runs the real program with a scripted editor inside a private
# sandbox, then checks what is on disk and how the program exited.
#
#   test_regressions.sh [ID...]      run every test, or only those named
#   EDIT_FILE=/path/to/editfile      test another copy of the program
set -euo pipefail
shopt -s inherit_errexit shift_verbose extglob nullglob
declare -rx PATH=/usr/local/bin:/usr/bin:/bin

#shellcheck disable=SC2155  # BCS metadata: realpath in declare-r pattern
declare -r SCRIPT_PATH=$(realpath -- "$0")
declare -r SCRIPT_DIR=${SCRIPT_PATH%/*} SCRIPT_NAME=${SCRIPT_PATH##*/}
declare -r COMPLETION=$SCRIPT_DIR/../editfile.bash_completion
# The program under test, and the name it gives itself in messages; setup()
# resolves both
declare -- EDIT_FILE=${EDIT_FILE:-$SCRIPT_DIR/../editfile} PROG=''

if [[ -t 1 && -t 2 ]]; then
  declare -r RED=$'\033[0;31m' GREEN=$'\033[0;32m' YELLOW=$'\033[0;33m' NC=$'\033[0m'
else
  declare -r RED='' GREEN='' YELLOW='' NC=''
fi

declare -i PASSED=0 FAILED=0 SKIPPED=0
# Exit status and process id of the last editfile run
declare -i RC=0 PID=0
# SANDBOX holds everything; CASE is the current test's directory, WORK the
# directory its target files live in, CWD where editfile is started
declare -- SANDBOX='' STUB='' CASE='' WORK='' CWD='' SKIP=''
declare -- FAKE_MV='' FAKE_COMMAND='' SLOW_OD='' MARK_PYTHON='' FAKE_TYPE=''
declare -a FAILURES=() PIDS=() ONLY=() IDS=()
# Set while main() is only collecting the names of the tests
declare -i COLLECTING=0

# The suite itself cannot go on
die() {
  >&2 echo "$SCRIPT_NAME: ${*:2}"
  exit "$1"
}

# Record a failed expectation; the test carries on to its other checks
fail() { FAILURES+=("$1"); }

cleanup() {
  local -i exitcode=${1:-$?}
  local -- pid
  trap - SIGINT SIGTERM EXIT
  for pid in "${PIDS[@]}"; do
    kill -KILL "$pid" 2>/dev/null ||:  # most have exited by now
  done
  [[ -z $SANDBOX ]] || rm -rf -- "$SANDBOX"
  exit "$exitcode"
}

# $? in a signal trap is the status of the command that was interrupted, not
# the signal, so each signal reports its own 128+n
#bcscheck disable=BCS0603
{
  trap 'cleanup $?' EXIT
  trap 'cleanup 130' SIGINT
  trap 'cleanup 143' SIGTERM
}

# Sandbox and seams

setup() {
  local -- resolved
  # Resolved because every run starts in a directory of its own. A failed
  # assignment would empty EDIT_FILE before the message could name it.
  resolved=$(realpath -e -- "$EDIT_FILE") || die 3 "No program to test at ${EDIT_FILE@Q}"
  EDIT_FILE=$resolved
  PROG=${EDIT_FILE##*/}
  readonly EDIT_FILE PROG

  SANDBOX=$(mktemp -d -t editfile-tests.XXXXXXXX) || die 5 'Cannot create the sandbox directory'
  readonly SANDBOX
  mkdir -- "$SANDBOX/bin"

  # Stand-in for an interactive editor: carries out the actions named in
  # $STUB_DO, in order, on the file it is given (its last argument)
  cat > "$SANDBOX/bin/stub-editor" <<'STUB'
#!/usr/bin/env bash
# stub-editor - scripted stand-in for an interactive editor
set -euo pipefail
shopt -s inherit_errexit
# The PATH that the program under test hands its editor is evidence
# (record-env); the stand-in's own commands do not depend on it
declare -r GIVEN_PATH=$PATH
declare -rx PATH=/usr/local/bin:/usr/bin:/bin

(($#)) || { >&2 echo 'stub-editor: no file to edit'; exit 2; }
declare -a ARGS=("$@") ACTIONS=()
declare -r FILE=${ARGS[-1]}
declare -- ACTION
declare -i CALLS=0 TRIES=0

read -ra ACTIONS <<<"${STUB_DO:-}"
for ACTION in "${ACTIONS[@]}"; do
  case $ACTION in
    append)       printf 'edited\n' >> "$FILE" ;;
    put)          cat -- "$STUB_PAYLOAD" > "$FILE" ;;
    put-next)     # a different payload each time the editor is opened
                  [[ ! -e $STUB_MARK/calls ]] || CALLS=$(<"$STUB_MARK/calls")
                  CALLS+=1
                  echo "$CALLS" > "$STUB_MARK/calls"
                  cat -- "$STUB_PAYLOAD.$CALLS" > "$FILE" ;;
    ignore-int)   trap '' INT ;;
    mark-started) : > "$STUB_MARK/started" ;;
    wait-go)      until [[ -e $STUB_MARK/go ]]; do
                    TRIES+=1
                    ((TRIES < 400)) || { >&2 echo 'stub-editor: no go marker in 20 s'; exit 24; }
                    sleep 0.05
                  done ;;
    record-env)   printf '%s\n' "$GIVEN_PATH" > "$STUB_MARK/path"
                  sed -n 's/^SigIgn:[[:space:]]*//p' "/proc/$$/status" > "$STUB_MARK/sigign" ;;
    record-stdin) cat > "$STUB_MARK/stdin" ;;
    record-name)  printf '%s' "${FILE##*/}" > "$STUB_MARK/name" ;;
    swap-symlink) rm -f -- "$FILE"
                  ln -s -- "$STUB_VICTIM" "$FILE" ;;
    write-target) printf 'written by another process\n' > "$STUB_TARGET" ;;
    fail)         exit 3 ;;
    *)            >&2 echo "stub-editor: unknown action ${ACTION@Q}"
                  exit 22 ;;
  esac
done
#fin
STUB
  chmod -- +x "$SANDBOX/bin/stub-editor"
  printf -v STUB '%q' "$SANDBOX/bin/stub-editor"
  readonly STUB

  # editfile is a bash script and bash imports functions from its environment,
  # so these replace mv, od, python3 and `command -v` inside it. Each leaves a
  # marker so that a test can tell whether the seam was reached.
  # read -d '' takes the whole here-document and reports the end-of-file that
  # stopped it as status 1: that is the ordinary outcome, hence each ||:
  IFS= read -r -d '' FAKE_MV <<'CODE' ||:
() { : > "$STUB_MARK/mv-called"; return 1
}
CODE
  # Report the tools named in $STUB_HIDE as not installed
  IFS= read -r -d '' FAKE_COMMAND <<'CODE' ||:  # status 1 is end-of-file
() { if [[ $1 == -v && " ${STUB_HIDE:-} " == *" $2 "* ]]; then : > "$STUB_MARK/hid-$2"; return 1; fi
  builtin command "$@"
}
CODE
  # od that pauses after its first line: a reader that has seen enough is gone
  # before the rest is written
  IFS= read -r -d '' SLOW_OD <<'CODE' ||:  # status 1 is end-of-file
() { local -- out; : > "$STUB_MARK/od-slowed"; out=$(command od "$@") || return
  printf '%s\n' "${out%%$'\n'*}"; sleep 0.3; printf '%s\n' "${out#*$'\n'}"
}
CODE
  # python3 as it is, except that it notes that a Python validator ran
  IFS= read -r -d '' MARK_PYTHON <<'CODE' ||:  # status 1 is end-of-file
() { : > "$STUB_MARK/python-ran"; command python3 "$@"
}
CODE
  readonly FAKE_MV FAKE_COMMAND SLOW_OD MARK_PYTHON

  "$EDIT_FILE" --version >/dev/null \
    || die 18 "${EDIT_FILE@Q} cannot run; is the filetype package installed?"
}

# Running editfile

# Run editfile in the foreground; its exit status goes to RC.
#   edit [NAME=value ...] -- [editfile arguments]
# stdin is the caller's; tests start with /dev/null, so every prompt sees
# end-of-file unless a test supplies answers.
edit() {
  local -a vars=()
  while [[ $1 != -- ]]; do vars+=("$1"); shift; done
  shift
  RC=0
  (
    cd -- "$CWD" && exec timeout --kill-after=5 60 env --default-signal=INT,PIPE -- \
      EDITOR="$STUB" STUB_MARK="$CASE/mark" "${vars[@]}" "$EDIT_FILE" "$@"
  ) >"$CASE/stdout" 2>"$CASE/stderr" || RC=$?
}

# Start editfile in the background, for signal tests; its process id goes to
# PID. A background job of a non-interactive shell starts with SIGINT ignored,
# which the program could never undo: --default-signal restores it.
edit_bg() {
  local -a vars=()
  while [[ $1 != -- ]]; do vars+=("$1"); shift; done
  shift
  {
    cd -- "$CWD" && exec env --default-signal=INT,PIPE -- \
      EDITOR="$STUB" STUB_MARK="$CASE/mark" "${vars[@]}" "$EDIT_FILE" "$@"
  } <&0 >"$CASE/stdout" 2>"$CASE/stderr" &
  PID=$!
  PIDS+=("$PID")
}

# Collect the background editfile's exit status into RC
reap() {
  RC=0
  wait "$PID" || RC=$?
}

signal() { kill -"$1" "$PID" 2>/dev/null || fail "could not send SIG$1 to editfile"; }

# Wait, with a limit, for a path to exist or for text to appear on stderr
wait_for() {
  local -i tries=0
  until [[ -e $1 ]]; do
    tries+=1
    ((tries < 400)) || { fail "timed out waiting for ${1##*/}"; return 0; }
    sleep 0.05
  done
}

wait_for_stderr() {
  local -i tries=0
  until grep -qF -- "$1" "$CASE/stderr"; do
    tries+=1
    ((tries < 400)) || { fail "timed out waiting for ${1@Q} on stderr"; return 0; }
    sleep 0.05
  done
}

# Skip the current test unless every named tool is installed
need() {
  local -- tool
  for tool in "$@"; do
    type -P -- "$tool" >/dev/null || { SKIP="$tool is not installed"; return 1; }
  done
}

# Assertion helpers

assert_rc() { ((RC == $1)) || fail "exit status $RC, expected $1"; }

# The path is a regular file (not a symlink) identical to the reference file
assert_same() {
  [[ -f $1 && ! -L $1 ]] || { fail "${1##*/} is not a regular file"; return 0; }
  cmp -s -- "$1" "$2" || fail "${1##*/} holds $(head -c 300 -- "$1" | cat -A)"
}

# The path is a regular file holding exactly this text
assert_content() {
  printf '%s' "$2" > "$CASE/expected"
  assert_same "$1" "$CASE/expected"
}

assert_absent() { [[ ! -e $1 && ! -L $1 ]] || fail "$2"; }

assert_mode() {
  local -- mode
  mode=$(stat -c '%a' -- "$1") || { fail "${1##*/}: no mode to read, expected $2"; return 0; }
  [[ $mode == "$2" ]] || fail "${1##*/} has mode $mode, expected $2"
}

assert_stderr() { grep -qF -- "$1" "$CASE/stderr" || fail "stderr lacks ${1@Q}"; }

refute_stderr() { ! grep -qF -- "$1" "$CASE/stderr" || fail "stderr contains ${1@Q}"; }

# editfile keeps its working copies as hidden files beside the target
assert_no_leftovers() {
  local -a found=("$WORK"/.*)
  ((${#found[@]} == 0)) || fail "working files left behind: ${found[*]##*/}"
}

discard_leftovers() {
  local -a found=("$WORK"/.*)
  ((${#found[@]} == 0)) || rm -f -- "${found[@]}"
}

# Exactly one working copy was kept, it holds the edits, and stderr names it
assert_preserved() {
  local -a found=("$WORK"/.*)
  if ((${#found[@]} != 1)); then
    fail "expected one preserved working copy, found ${#found[@]}: ${found[*]##*/}"
    return 0
  fi
  assert_content "${found[0]}" "$1"
  # The program prints the path quoted for the shell
  grep -qF -- "${found[0]@Q}" "$CASE/stderr" || fail 'stderr does not say where the edits are'
}

# Editing <name> so that it holds <content> (printf %b escapes) is saved
saves() {
  local -- name=$1 f=$WORK/$1
  printf 'seed\n' > "$f"
  printf '%b' "$2" > "$CASE/payload"
  edit STUB_DO=put STUB_PAYLOAD="$CASE/payload" -- "$f"
  if ((RC)); then
    fail "$name: exit status $RC, expected 0: $(tail -n 2 -- "$CASE/stderr" | tr '\n' ' ')"
  else
    cmp -s -- "$f" "$CASE/payload" || fail "$name: the edit was not saved"
  fi
  discard_leftovers
}

# Editing <name> so that it holds <content> fails validation; with no answer
# at the prompt nothing is saved and the edit is kept. <expect> is text the
# diagnostic must contain.
rejects() {
  local -- name=$1 f=$WORK/$1 expect=${3:-}
  local -a found
  printf 'seed\n' > "$f"
  printf '%b' "$2" > "$CASE/payload"
  edit STUB_DO=put STUB_PAYLOAD="$CASE/payload" -- "$f"
  ((RC == 1)) || fail "$name: exit status $RC, expected 1"
  grep -qF -- 'Validation failed' "$CASE/stderr" \
    || fail "$name: no 'Validation failed' message"
  [[ -z $expect ]] || grep -qF -- "$expect" "$CASE/stderr" \
    || fail "$name: diagnostic lacks ${expect@Q}"
  [[ $(<"$f") == seed ]] || fail "$name: the target was changed"
  found=("$WORK"/.*)
  ((${#found[@]} == 1)) || fail "$name: expected one preserved working copy, found ${#found[@]}"
  discard_leftovers
}

# Tests: edits survive

test_sigint_survived_by_editor() {
  local -- f=$WORK/notes.txt
  printf 'one\n' > "$f"
  edit_bg STUB_DO='ignore-int mark-started wait-go append' -- "$f"
  wait_for "$CASE/mark/started"
  signal INT
  : > "$CASE/mark/go"
  reap
  assert_rc 0
  assert_content "$f" $'one\nedited\n'
  assert_no_leftovers
}

test_failed_save_keeps_edits() {
  local -- f=$WORK/notes.txt
  printf 'one\n' > "$f"
  edit STUB_DO=append "BASH_FUNC_mv%%=$FAKE_MV" -- "$f"
  [[ -e $CASE/mark/mv-called ]] || { SKIP='could not make mv fail'; return 0; }
  assert_rc 5
  assert_content "$f" $'one\n'
  assert_preserved $'one\nedited\n'
}

# A signal that arrives while the editor is open takes effect when it closes
signal_during_edit() {
  local -- f=$WORK/notes.txt
  printf 'one\n' > "$f"
  edit_bg STUB_DO='append mark-started wait-go' -- "$f"
  wait_for "$CASE/mark/started"
  signal "$1"
  : > "$CASE/mark/go"
  reap
  assert_rc "$2"
  assert_content "$f" $'one\n'
  assert_preserved $'one\nedited\n'
}

test_sigterm_during_edit() { signal_during_edit TERM 143; }

test_sighup_during_edit() { signal_during_edit HUP 129; }

test_sigint_at_prompt() {
  local -- f=$WORK/cfg.json
  local -i holder
  need jq || return 0
  printf '{"a": 1}\n' > "$f"
  printf '{"a": 1,,}\n' > "$CASE/payload"
  # A writer that stays open makes the prompt block instead of seeing end-of-file
  mkfifo -- "$CASE/stdin"
  sleep 60 > "$CASE/stdin" &
  holder=$!
  PIDS+=("$holder")
  edit_bg STUB_DO=put STUB_PAYLOAD="$CASE/payload" -- "$f" <"$CASE/stdin"
  wait_for_stderr '[q]'
  signal INT
  kill "$holder" 2>/dev/null ||:  # its 60 seconds may be up already
  reap
  assert_rc 130
  assert_content "$f" $'{"a": 1}\n'
  assert_preserved $'{"a": 1,,}\n'
}

test_signal_without_edits() {
  local -- f=$WORK/notes.txt
  printf 'one\n' > "$f"
  edit_bg STUB_DO='mark-started wait-go' -- "$f"
  wait_for "$CASE/mark/started"
  signal TERM
  : > "$CASE/mark/go"
  reap
  assert_rc 143
  assert_content "$f" $'one\n'
  assert_no_leftovers
}

test_editor_failure_keeps_edits() {
  local -- f=$WORK/notes.txt
  printf 'one\n' > "$f"
  edit STUB_DO='append fail' -- "$f"
  assert_rc 1
  assert_content "$f" $'one\n'
  assert_preserved $'one\nedited\n'
}

# Tests: validator isolation

# A module of this name in the working directory; importing it leaves a marker
plant() {
  printf 'import os\nopen(os.environ["STUB_MARK"] + "/ran-%s", "w").close()\n' "$1" \
    > "$WORK/$1.py"
}

# <file name> <valid content> <module> [tool to hide so the Python fallback runs]
planted_module_ignored() {
  local -- f=$WORK/$1 hide=${4:-}
  need python3 || return 0
  printf 'seed\n' > "$f"
  printf '%b' "$2" > "$CASE/payload"
  plant "$3"
  edit STUB_DO=put STUB_PAYLOAD="$CASE/payload" STUB_HIDE="$hide" \
    "BASH_FUNC_command%%=$FAKE_COMMAND" "BASH_FUNC_python3%%=$MARK_PYTHON" -- "$f"
  # A planted module that ran is a failure, however python3 was started
  assert_absent "$CASE/mark/ran-$3" "$3.py from the working directory was executed"
  assert_rc 0
  assert_same "$f" "$CASE/payload"
  # Otherwise the case proves nothing unless the Python validator was used
  if [[ -n $hide && ! -e $CASE/mark/hid-$hide ]]; then
    SKIP="could not hide $hide"
  elif [[ ! -e $CASE/mark/python-ran ]]; then
    SKIP='no Python validator ran'
  fi
}

test_csv_ignores_planted_module() { planted_module_ignored data.csv 'a,b\n1,2\n' csv; }

test_toml_ignores_planted_module() { planted_module_ignored conf.toml 'k = 1\n' tomllib; }

test_json_ignores_planted_module() { planted_module_ignored cfg.json '{"a": 1}\n' json jq; }

test_yaml_ignores_planted_module() { planted_module_ignored cfg.yaml 'a: 1\n' yaml yamllint; }

test_xml_ignores_planted_module() { planted_module_ignored doc.xml '<a/>\n' xml xmllint; }

# Tests: working copy integrity

test_swapped_working_copy_not_installed() {
  local -- f=$WORK/app.txt victim=$CASE/victim
  printf 'config\n' > "$f"
  chmod -- 644 "$f"
  printf 'secret\n' > "$victim"
  chmod -- 600 "$victim"
  edit STUB_DO=swap-symlink STUB_VICTIM="$victim" -- "$f"
  assert_rc 1
  assert_content "$f" $'config\n'
  assert_content "$victim" $'secret\n'
  assert_mode "$victim" 600
  assert_no_leftovers
}

# Tests: binary detection

# 8 KiB that file(1) calls "data", with NUL bytes throughout
blob() {
  local -- chunk
  local -i i=0
  chunk=$(printf '\\x%02x' {0..255})
  while ((i < 32)); do
    printf '%b' "$chunk"
    i+=1
  done
}

# <file> is refused as binary without the editor being started
refused_as_binary() {
  cp -- "$1" "$CASE/reference" || { fail "${1##*/} could not be copied for comparison"; return 0; }
  edit STUB_DO='mark-started append' "${@:2}" -- "$1"
  assert_rc 10
  assert_absent "$CASE/mark/started" 'the editor was started on a binary file'
  assert_same "$1" "$CASE/reference"
  assert_no_leftovers
}

test_binary_with_text_extension_refused() {
  local -- f=$WORK/blob.txt
  local -i run=0
  # The original probe was a race, so one run proves nothing
  while ((run < 10 && ${#FAILURES[@]} == 0)); do
    blob > "$f"
    refused_as_binary "$f"
    run+=1
  done
}

test_nul_probe_independent_of_timing() {
  local -- f=$WORK/blob.txt
  blob > "$f"
  refused_as_binary "$f" "BASH_FUNC_od%%=$SLOW_OD"
  [[ -e $CASE/mark/od-slowed ]] || SKIP='od was not called by name, so the delay could not be put in'
}

test_compressed_file_refused() {
  local -- f=$WORK/notes.txt
  # A gzip member whose header records the original name "myscript.sh":
  # file(1) repeats that name, and "script" must not make it text
  printf '\x1f\x8b\x08\x08\x00\x00\x00\x00\x00\x03myscript.sh\x00' > "$f"
  printf '\x03\x00\x00\x00\x00\x00\x00\x00\x00\x00' >> "$f"
  refused_as_binary "$f"
}

test_library_binary_verdict_reported() {
  local -- f=$WORK/backup.dat
  local -i i=0
  # Control bytes but no NUL: only the filetype library calls this binary
  while ((i < 512)); do
    printf '\x01\x02\x03\x04\x05\x06\x07\x08'
    i+=1
  done > "$f"
  refused_as_binary "$f"
}

test_text_encodings_stay_editable() {
  local -- name
  printf '\xff\xfeh\x00i\x00\n\x00' > "$WORK/utf16.txt"
  printf 'caf\xe9 na\xefve\n' > "$WORK/latin1.txt"
  printf '\033[1mbold\033[0m\n' > "$WORK/ansi.txt"
  : > "$WORK/empty.txt"
  for name in utf16.txt latin1.txt ansi.txt empty.txt; do
    edit STUB_DO=append -- "$WORK/$name"
    ((RC == 0)) || fail "$name: exit status $RC, expected 0"
  done
  assert_no_leftovers
}

# Tests: editor environment

test_editor_gets_callers_path() {
  local -- f=$WORK/notes.txt path=$CASE/userbin:/usr/local/bin:/usr/bin:/bin
  mkdir -- "$CASE/userbin"
  printf 'one\n' > "$f"
  edit STUB_DO='record-env append' PATH="$path" -- "$f"
  assert_rc 0
  assert_content "$CASE/mark/path" "$path"$'\n'
}

test_editor_gets_default_sigpipe() {
  local -- f=$WORK/notes.txt mask
  printf 'one\n' > "$f"
  edit STUB_DO='record-env append' -- "$f"
  assert_rc 0
  [[ -s $CASE/mark/sigign ]] || { fail 'the editor did not report its signal mask'; return 0; }
  mask=$(<"$CASE/mark/sigign")
  # SIGPIPE is signal 13: bit 12 of the ignored-signals mask
  (((16#$mask >> 12 & 1) == 0)) || fail "SIGPIPE is ignored in the editor (SigIgn $mask)"
}

# Tests: validator verdicts

test_shell_validator() {
  #shellcheck disable=SC2016  # the sample script is literal text, expanded by nothing here
  local -- script='#!/usr/bin/env bash\nshopt -s extglob\ncase ${1:-} in\n'
  script+='  +([0-9])) echo number ;;\n  !(*.txt)) echo other ;;\nesac\n'
  saves ext.sh "$script"
  rejects bad.sh 'if true; then\n  echo hi\n' 'syntax error'
}

test_yaml_validator() {
  need yamllint || return 0
  saves trailing.yaml 'a: 1 \nb: 2\n'
  saves nonewline.yaml 'a: 1\nb: 2'
  saves crlf.yaml 'a: 1\r\nb: 2\r\n'
  rejects bad.yaml 'a: [1, 2\n' 'syntax error'
  rejects dup.yaml 'a: 1\na: 2\n' 'duplication of key'
}

test_html_validator() {
  local -- head='<!DOCTYPE html>\n<html><head><title>t</title></head>\n'
  need tidy || return 0
  saves custom.html "$head"'<body><my-widget>x</my-widget></body></html>\n'
  rejects bad.html "$head"'<body><frobnicate>x</frobnicate></body></html>\n' 'frobnicate'
}

test_csv_validator() {
  need python3 || return 0
  saves semicolon.csv 'name;price\nwidget;1,50\ngadget;2,00\n'
  saves latin1.csv 'nom,ville\ncaf\xe9,Gen\xe8ve\n'
  saves quoted.csv 'a,b\n"x, y",2\n'
  rejects ragged.csv 'a,b\n1,2,3\n' 'Line 2'
  # The ragged row is on line 5 of the file but is only the fourth record
  rejects multiline.csv 'a,b\n"multi\nline",2\nx,y\n1,2,3\n' 'Line 5'
}

test_ini_validator() {
  local -- tox='[tox]\nenvlist =\n    py311\n    py312\n\n'
  tox+='[testenv]\ncommands =\n    pytest {posargs}\n'
  saves tox.ini "$tox"
  saves valueless.ini '[mysqld]\nskip-name-resolve\nport = 3306\n'
  saves colon.ini '[section]\nkey: value\n; comment\n'
  # EditorConfig section names are globs, character classes included
  saves editorconfig.ini '[*]\nindent_style = space\n\n[*.[ch]]\nindent_size = 8\n'
  rejects header.ini '[section = oops\nkey = 1\n' 'Line 1'
}

test_json_validator() {
  need jq || return 0
  saves good.json '{"a": [1, 2, {"b": null}]}\n'
  rejects bad.json '{"a": 1,,}\n'
  # The validator's own message follows the heading instead of preceding it
  awk '/Validation failed/ { heading = NR } /jq: error|parse error/ { detail = NR }
       END { exit !(heading && detail && heading < detail) }' < "$CASE/stderr" \
    || fail 'the diagnostic does not follow the "Validation failed" heading'
  rejects two.json '{"a": 1}{"b": 2}\n'
  rejects blank.json '\n\n'
}

test_toml_validator() {
  need python3 || return 0
  saves good.toml 'k = 1\n[t]\nx = "y"\n'
  rejects bad.toml 'k =\n' 'line 1'
  refute_stderr 'Traceback'
}

test_xml_validator() {
  need xmllint || return 0
  saves good.xml '<?xml version="1.0"?>\n<a><b/></a>\n'
  rejects bad.xml '<a><b></a>\n'
}

test_python_validator() {
  need python3 || return 0
  saves good.py 'def f():\n    return 1\n'
  rejects bad.py 'def f(:\n    pass\n' 'SyntaxError'
}

test_php_validator() {
  need php || return 0
  saves good.php '<?php\necho "x";\n'
  refute_stderr 'No syntax errors'
  rejects bad.php '<?php\nif (true) {\n'
}

test_unvalidated_save_not_called_validated() {
  local -- f=$WORK/cfg.json
  printf '{}\n' > "$f"
  printf '{"a": 1,,}\n' > "$CASE/payload"
  edit STUB_DO=put STUB_PAYLOAD="$CASE/payload" STUB_HIDE='jq python3' \
    "BASH_FUNC_command%%=$FAKE_COMMAND" -- "$f"
  [[ -e $CASE/mark/hid-jq ]] || { SKIP='could not hide the JSON validators'; return 0; }
  assert_rc 0
  assert_stderr 'Not validated'
  refute_stderr '✓ Validated'
  assert_same "$f" "$CASE/payload"
}

test_json_fallback_shows_error() {
  local -- f=$WORK/cfg.json
  need python3 || return 0
  printf '{}\n' > "$f"
  printf '{"a": 1,,}\n' > "$CASE/payload"
  edit STUB_DO=put STUB_PAYLOAD="$CASE/payload" STUB_HIDE=jq \
    "BASH_FUNC_command%%=$FAKE_COMMAND" -- "$f"
  [[ -e $CASE/mark/hid-jq ]] || { SKIP='could not hide jq'; return 0; }
  assert_rc 1
  assert_stderr 'line 1 column'
}

test_yaml_fallback_accepts_documents_and_tags() {
  local -- f=$WORK/stack.yaml
  need python3 || return 0
  printf 'seed\n' > "$f"
  printf 'a: 1\n---\nb: !Ref thing\n' > "$CASE/payload"
  edit STUB_DO=put STUB_PAYLOAD="$CASE/payload" STUB_HIDE=yamllint \
    "BASH_FUNC_command%%=$FAKE_COMMAND" -- "$f"
  [[ -e $CASE/mark/hid-yamllint ]] || { SKIP='could not hide yamllint'; return 0; }
  refute_stderr 'Not validated'
  assert_rc 0
  assert_same "$f" "$CASE/payload"
}

test_validation_messages() {
  local -- f=$WORK/cfg.json line
  need jq || return 0
  printf '{}\n' > "$f"
  printf '{"a": 1,,}\n' > "$CASE/payload"
  edit STUB_DO=put STUB_PAYLOAD="$CASE/payload" -- "$f"
  assert_rc 1
  # No line that is only the program's name and a colon, with or without an icon
  while IFS= read -r line; do
    [[ $line != "$PROG:"?( @(✓|▲|◉|✗))*( ) ]] || fail "stderr has an empty message line: ${line@Q}"
  done < "$CASE/stderr"
}

# Tests: the validation prompt

test_fix_after_failed_validation() {
  local -- f=$WORK/cfg.json
  need jq || return 0
  printf '{"a": 1}\n' > "$f"
  printf '{"a": 1,,}\n' > "$CASE/payload.1"
  printf '{"a": 2}\n' > "$CASE/payload.2"
  edit STUB_DO=put-next STUB_PAYLOAD="$CASE/payload" -- "$f" <<<'e'
  assert_rc 0
  assert_content "$f" $'{"a": 2}\n'
  assert_no_leftovers
}

test_save_despite_failed_validation() {
  local -- f=$WORK/cfg.json
  need jq || return 0
  printf '{"a": 1}\n' > "$f"
  printf '{"a": 1,,}\n' > "$CASE/payload"
  edit STUB_DO=put STUB_PAYLOAD="$CASE/payload" -- "$f" <<<'s'
  assert_rc 0
  assert_content "$f" $'{"a": 1,,}\n'
  assert_no_leftovers
}

test_quit_after_failed_validation() {
  local -- f=$WORK/cfg.json
  need jq || return 0
  printf '{"a": 1}\n' > "$f"
  printf '{"a": 1,,}\n' > "$CASE/payload"
  edit STUB_DO=put STUB_PAYLOAD="$CASE/payload" -- "$f" <<<'q'
  assert_rc 0
  assert_content "$f" $'{"a": 1}\n'
  assert_no_leftovers
}

# Tests: yes/no prompts

test_typeahead_not_passed_to_editor() {
  local -- f=$WORK/new.txt
  printf 'hello\n' > "$CASE/payload"
  edit STUB_DO='record-stdin put' STUB_PAYLOAD="$CASE/payload" -- "$f" <<<'yes'
  assert_rc 0
  assert_content "$f" $'hello\n'
  assert_content "$CASE/mark/stdin" ''
}

test_prompt_answers() {
  local -- answer f
  printf 'hello\n' > "$CASE/payload"
  for answer in y yes Y YES; do
    f=$WORK/created-$answer.txt
    edit STUB_DO=put STUB_PAYLOAD="$CASE/payload" -- "$f" <<<"$answer"
    [[ -f $f ]] || fail "answer ${answer@Q}: the file was not created"
  done
  for answer in n no yep ''; do
    f=$WORK/declined-${answer:-empty}.txt
    edit STUB_DO=put STUB_PAYLOAD="$CASE/payload" -- "$f" <<<"$answer"
    [[ ! -e $f ]] || fail "answer ${answer@Q}: the file was created"
    ((RC == 0)) || fail "answer ${answer@Q}: exit status $RC, expected 0"
  done
  edit STUB_DO=put STUB_PAYLOAD="$CASE/payload" -- "$WORK/eof.txt"
  assert_rc 0
  assert_absent "$WORK/eof.txt" 'end-of-file at the prompt created the file'
  assert_no_leftovers
}

# Tests: locating the file

test_path_search_ignores_own_functions() {
  local -- tool=$CASE/userbin/warn
  mkdir -- "$CASE/userbin"
  printf '#!/bin/sh\necho hi\n' > "$tool"
  chmod -- 755 "$tool"
  # "warn" is also the name of a function inside editfile
  edit STUB_DO=append PATH="$CASE/userbin:/usr/local/bin:/usr/bin:/bin" -- warn <<<'y'
  assert_rc 0
  assert_content "$tool" $'#!/bin/sh\necho hi\nedited\n'
  assert_mode "$tool" 755
  assert_absent "$WORK/warn" 'a new file was created instead of editing the script on PATH'
}

test_line_number_ascii_digits() {
  local -- locales
  printf 'one\n' > "$WORK/a.txt"
  locales=$(locale -a) || { fail 'locale -a failed'; return 0; }
  if ! grep -qix -- 'en_US.utf8' <<<"$locales"; then
    SKIP='the en_US.UTF-8 locale is not installed'
    return 0
  fi
  # There a regex [0-9] is a collation range that takes other scripts'
  # digits too, and those are no number to the shell's arithmetic
  edit LC_ALL=en_US.UTF-8 -- -l '١٢' "$WORK/a.txt"
  assert_rc 22
  assert_stderr 'Line number must be a non-negative integer'
}

test_path_search_skips_relative_entries() {
  local -- tool=$CASE/absbin/mytool
  mkdir -- "$CASE/absbin" "$WORK/relbin"
  printf '#!/bin/sh\necho hi\n' > "$tool"
  chmod -- 755 "$tool"
  cp -p -- "$tool" "$WORK/relbin/mytool"
  # A hit through the relative entry is not trusted; the search goes on past
  # it to the absolute one instead of ending there
  edit STUB_DO=append PATH="relbin:$CASE/absbin:/usr/local/bin:/usr/bin:/bin" -- mytool <<<'y'
  assert_rc 0
  assert_content "$tool" $'#!/bin/sh\necho hi\nedited\n'
  assert_content "$WORK/relbin/mytool" $'#!/bin/sh\necho hi\n'
  assert_absent "$WORK/mytool" 'a new file was created instead of editing the script on PATH'
}

test_dependency_lookup_ignores_functions() {
  local -- f=$WORK/notes.txt
  printf 'one\n' > "$f"
  # With a function called editcmd in the environment, `command -v editcmd`
  # answers "editcmd", and the library would be looked up as ./editcmd/filetype
  mkdir -- "$WORK/editcmd"
  cat > "$WORK/editcmd/filetype" <<'PLANTED'
: > "$STUB_MARK/sourced"
PLANTED
  edit STUB_DO=append 'BASH_FUNC_editcmd%%=() { :
}' -- "$f"
  assert_absent "$CASE/mark/sourced" 'a file in the working directory was sourced as the library'
  assert_rc 0
  assert_content "$f" $'one\nedited\n'
}

test_name_ending_in_newline_refused() {
  local -- f=$WORK/$'trail\n'
  printf 'one\n' > "$f"
  edit STUB_DO=append -- "$f"
  assert_rc 22
  assert_content "$f" $'one\n'
  assert_absent "$WORK/trail" 'a different file was created'
}

test_new_script_without_extension_validated() {
  local -- f=$WORK/deploy
  printf '#!/bin/bash\nif true; then\n  echo hi\n' > "$CASE/payload"
  edit STUB_DO=put STUB_PAYLOAD="$CASE/payload" -- "$f" <<<'y'
  assert_rc 1
  assert_stderr 'Validation failed'
  assert_absent "$f" 'a script with a syntax error was saved unvalidated'
}

# Tests: saving files

test_edit_is_saved() {
  local -- f=$WORK/notes.txt
  printf 'one\n' > "$f"
  edit STUB_DO=append -- "$f"
  assert_rc 0
  assert_content "$f" $'one\nedited\n'
  assert_stderr 'saved'
  assert_no_leftovers
}

test_unchanged_file_left_alone() {
  local -- f=$WORK/notes.txt before after
  printf 'one\n' > "$f"
  before=$(stat -c '%i %Y' -- "$f") || fail 'the file cannot be examined before the edit'
  edit STUB_DO='' -- "$f"
  after=$(stat -c '%i %Y' -- "$f") || fail 'the file is gone after the edit'
  assert_rc 0
  [[ $before == "$after" ]] || fail 'the file was rewritten although nothing changed'
  assert_no_leftovers
}

test_modes_survive_a_save() {
  local -- mode f
  for mode in 600 750 4755; do
    f=$WORK/mode-$mode.txt
    printf 'one\n' > "$f"
    chmod -- "$mode" "$f"
    edit STUB_DO=append -- "$f"
    ((RC == 0)) || fail "mode $mode: exit status $RC, expected 0"
    assert_mode "$f" "$mode"
  done
}

test_new_file_mode_follows_umask() {
  local -- f=$WORK/new.txt saved_umask
  saved_umask=$(umask)
  printf 'hello\n' > "$CASE/payload"
  umask 027
  edit STUB_DO=put STUB_PAYLOAD="$CASE/payload" -- "$f" <<<'y'
  umask "$saved_umask"
  assert_rc 0
  assert_content "$f" $'hello\n'
  assert_mode "$f" 640
}

test_new_file_in_new_directory() {
  local -- f=$WORK/config/app.yaml
  printf 'a: 1\n' > "$CASE/payload"
  edit STUB_DO=put STUB_PAYLOAD="$CASE/payload" -- "$f" <<<'y'
  assert_rc 0
  assert_content "$f" $'a: 1\n'
}

test_abandoned_new_file_removes_created_dirs() {
  local -a kept
  mkdir -- "$WORK/keep"
  # y to "Create?"; the editor writes nothing; n to "Create empty file?"
  edit -- "$WORK/keep/new/sub/file.txt" <<<$'y\nn'
  assert_rc 0
  assert_absent "$WORK/keep/new" 'the directories made for the abandoned file were left behind'
  [[ -d $WORK/keep ]] || fail 'a directory that was there before was removed'

  # Edits that could not be saved stay where they are, directory included
  printf 'if then\n' > "$CASE/payload"
  edit STUB_DO=put STUB_PAYLOAD="$CASE/payload" -- "$WORK/keep/other/tool.sh" <<<'y'
  assert_rc 1
  kept=("$WORK"/keep/other/.*)
  ((${#kept[@]} == 1)) || fail "expected one preserved working copy, found ${#kept[@]}"
}

test_symlink_followed_and_kept() {
  printf 'one\n' > "$WORK/real.txt"
  ln -s -- real.txt "$WORK/link.txt"
  edit STUB_DO=append -- "$WORK/link.txt"
  assert_rc 0
  [[ -L $WORK/link.txt ]] || fail 'the symlink was replaced by a file'
  assert_content "$WORK/real.txt" $'one\nedited\n'
}

test_external_change_not_overwritten() {
  local -- f=$WORK/notes.txt
  printf 'one\n' > "$f"
  edit STUB_DO='write-target append' STUB_TARGET="$f" -- "$f" <<<'n'
  assert_rc 1
  assert_content "$f" $'written by another process\n'
  assert_preserved $'one\nedited\n'
}

test_file_created_meanwhile_not_overwritten() {
  local -- f=$WORK/new.txt
  printf 'mine\n' > "$CASE/payload"
  edit STUB_DO='write-target put' STUB_TARGET="$f" STUB_PAYLOAD="$CASE/payload" -- "$f" <<<$'y\nn'
  assert_rc 1
  assert_content "$f" $'written by another process\n'
  assert_preserved $'mine\n'
}

test_file_created_meanwhile_overwritten_on_request() {
  local -- f=$WORK/new.txt
  printf 'mine\n' > "$CASE/payload"
  edit STUB_DO='write-target put' STUB_TARGET="$f" STUB_PAYLOAD="$CASE/payload" -- "$f" <<<$'y\ny'
  assert_rc 0
  assert_content "$f" $'mine\n'
  assert_no_leftovers
}

test_empty_file_created_on_request() {
  local -- f=$WORK/empty.xml
  need xmllint || return 0
  # An empty XML document is not well-formed; a file the user asked to be
  # empty is not something to validate
  edit STUB_DO='' -- "$f" <<<$'y\ny'
  assert_rc 0
  assert_content "$f" ''
  assert_no_leftovers
}

test_hostile_filenames() {
  local -- name f copy
  #shellcheck disable=SC2016  # the names must hold shell syntax literally
  local -a names=('with space.json' '$(touch pwned).json' '`touch pwned`.json'
    'semi;touch pwned;.json' "quote'\".json" $'new\nline.json' '*.json' '-dash.json'
    'ñoño_文件.json' "$(printf 'a%.0s' {1..245}).json")
  need jq || return 0
  printf '{"a": 1}\n' > "$CASE/payload"
  for name in "${names[@]}"; do
    f=$WORK/$name
    printf '{}\n' > "$f"
    # The marker of the previous name must not stand in for this one
    rm -f -- "$CASE/mark/name" || { fail 'cannot clear the name marker'; return 0; }
    edit STUB_DO='record-name put' STUB_PAYLOAD="$CASE/payload" -- -- "$name"
    ((RC == 0)) || fail "${name@Q}: exit status $RC, expected 0"
    cmp -s -- "$f" "$CASE/payload" || fail "${name@Q}: the edit was not saved"
    # The editor gets a working copy named from these characters only. A glob,
    # not a regex: in a regex the ranges follow the locale's collation
    if [[ ! -f $CASE/mark/name ]]; then
      fail "${name@Q}: the editor was not started"
    elif ! copy=$(<"$CASE/mark/name"); then
      fail "${name@Q}: cannot read the name the editor was given"
    elif [[ $copy != .+([a-zA-Z0-9._-]) ]]; then
      fail "${name@Q}: the editor was given a working copy called ${copy@Q}"
    fi
  done
  assert_absent "$WORK/pwned" 'a file name was executed as a command'
  assert_no_leftovers
}

# Before 1.0.1 the YAML, XML and TOML validators put the path into Python
# source, as open('$filepath'). The working copy's own name is sanitized, its
# directory's is not: a directory name holding shell and Python syntax must
# reach no validator as code, the Python fallbacks included. Pasted into that
# old code, this name runs os.system('touch pwned') before Python fails. The
# invalid edit must be rejected, which shows that the validator read the content.
#   hostile_dir_inert <file name> <valid content> <invalid content> [tool to hide]
hostile_dir_inert() {
  local -- dir f hide=${4:-}
  local -a seams=()
  need python3 || return 0
  dir=$WORK/$'$(touch pwned)`touch pwned`\'+__import__(\'os\').system(\'touch pwned\')+\''
  f=$dir/$1
  seams=(STUB_DO=put STUB_PAYLOAD="$CASE/payload" STUB_HIDE="$hide"
    "BASH_FUNC_command%%=$FAKE_COMMAND" "BASH_FUNC_python3%%=$MARK_PYTHON")
  mkdir -- "$dir"
  printf 'seed\n' > "$f"
  printf '%b' "$2" > "$CASE/payload"
  edit "${seams[@]}" -- "$f"
  assert_rc 0
  assert_same "$f" "$CASE/payload"
  printf '%b' "$3" > "$CASE/payload"
  edit "${seams[@]}" -- "$f"
  ((RC == 1)) || fail "the invalid edit: exit status $RC, expected 1"
  grep -qF -- 'Validation failed' "$CASE/stderr" \
    || fail "the invalid edit: no 'Validation failed' message"
  assert_absent "$WORK/pwned" 'a directory name was executed as code'
  if [[ -n $hide && ! -e $CASE/mark/hid-$hide ]]; then
    SKIP="could not hide $hide"
  elif [[ ! -e $CASE/mark/python-ran ]]; then
    SKIP='no Python validator ran'
  fi
}

test_hostile_dir_yaml() { hostile_dir_inert cfg.yaml 'a: 1\n' 'a: [1\n' yamllint; }

test_hostile_dir_xml() { hostile_dir_inert doc.xml '<a/>\n' '<a>\n' xmllint; }

test_hostile_dir_toml() { hostile_dir_inert conf.toml 'a = 1\n' 'a =\n'; }

# Tests: command line

# <expected status> [editfile arguments]
exits_with() {
  edit -- "${@:2}"
  ((RC == $1)) || fail "editfile ${*:2}: exit status $RC, expected $1"
}

test_exit_codes() {
  printf 'one\n' > "$WORK/a.txt"
  printf 'one\n' > "$WORK/readonly.txt"
  chmod -- 444 "$WORK/readonly.txt"
  printf 'one\n' > "$WORK/writeonly.txt"
  chmod -- 200 "$WORK/writeonly.txt"
  mkdir -- "$WORK/dir"
  exits_with 2
  exits_with 2 "$WORK/a.txt" "$WORK/b.txt"
  exits_with 2 -l
  exits_with 22 --bogus
  exits_with 22 -l abc "$WORK/a.txt"
  # The value named is the one typed, not what the bundle splitter made of it
  exits_with 22 -lx "$WORK/a.txt"
  assert_stderr "integer: 'x'"
  # Beyond 2^63-1 the arithmetic wraps: one of these would open at line 42
  exits_with 22 -l 18446744073709551658 "$WORK/a.txt"
  exits_with 22 -l 9223372036854775808 "$WORK/a.txt"
  exits_with 0 -l 000000000000000000042 "$WORK/a.txt"
  # An empty name is not skipped in favour of the next one
  exits_with 22 '' "$WORK/a.txt"
  exits_with 22 -- ''
  exits_with 0 -l 2 "$WORK/a.txt"
  exits_with 0 -l2 "$WORK/a.txt"
  exits_with 0 -ql2 "$WORK/a.txt"
  exits_with 10 "$WORK/dir"
  exits_with 16 "$EDIT_FILE"
  # root can read and write anything, so the permission checks do not apply
  ((EUID == 0)) || exits_with 13 "$WORK/readonly.txt"
  ((EUID == 0)) || exits_with 13 "$WORK/writeonly.txt"
  exits_with 0 --version
  [[ $(<"$CASE/stdout") == "$PROG "+([0-9.]) ]] || fail "--version printed $(<"$CASE/stdout")"
  exits_with 0 --help
  assert_no_leftovers
}

test_no_validate_option() {
  local -- f=$WORK/cfg.json
  printf '{}\n' > "$f"
  printf '{"a": 1,,}\n' > "$CASE/payload"
  edit STUB_DO=put STUB_PAYLOAD="$CASE/payload" -- -n "$f"
  assert_rc 0
  assert_same "$f" "$CASE/payload"
  refute_stderr 'Validating'
  assert_no_leftovers
}

test_shellcheck_option() {
  local -- f=$WORK/tool.sh
  need shellcheck || return 0
  printf '#!/bin/bash\ntrue\n' > "$f"
  # Valid syntax that shellcheck has advice about (SC2086)
  #shellcheck disable=SC2016  # the sample script must contain $1 literally
  printf '%s\n' '#!/bin/bash' 'echo $1' > "$CASE/payload"
  edit STUB_DO=put STUB_PAYLOAD="$CASE/payload" -- -s "$f"
  assert_rc 0
  assert_same "$f" "$CASE/payload"
  assert_stderr 'SC2086'
  edit STUB_DO=append -- "$f"
  assert_rc 0
  refute_stderr 'SC2086'
}

test_quiet_option() {
  local -- f=$WORK/cfg.json
  need jq || return 0
  printf '{}\n' > "$f"
  printf '{"a": 1}\n' > "$CASE/payload"
  edit STUB_DO=put STUB_PAYLOAD="$CASE/payload" -- -q "$f"
  assert_rc 0
  [[ ! -s $CASE/stderr ]] || fail "stderr is not empty: $(<"$CASE/stderr")"
  # Errors are still reported
  printf '{"a": 1,,}\n' > "$CASE/payload"
  edit STUB_DO=put STUB_PAYLOAD="$CASE/payload" -- -q "$f"
  assert_rc 1
  assert_stderr 'Validation failed'
  discard_leftovers
}

test_line_option_reaches_editor() {
  local -- f=$WORK/cfg.json nano=$CASE/nano
  local -a launches=()
  need jq || return 0
  # editcmd sends an editor to a line only if it knows the editor's family,
  # which it tells from the name. This "nano" notes the arguments that come
  # before the file name, then does the scripted editor's work.
  cat > "$nano" <<'NANO'
#!/usr/bin/env bash
# nano - records how it was called, then acts as the scripted editor
set -euo pipefail
shopt -s inherit_errexit
declare -rx PATH=/usr/local/bin:/usr/bin:/bin
printf '%s\n' "${*:1:$#-1}" >> "$STUB_MARK/launches"
exec -- "$STUB_EDITOR" "$@"
#fin
NANO
  chmod -- +x "$nano"
  printf '{"a": 1}\n' > "$f"
  printf '{"a": 1,,}\n' > "$CASE/payload.1"
  printf '{"a": 2}\n' > "$CASE/payload.2"
  edit EDITOR="$nano" STUB_EDITOR="$SANDBOX/bin/stub-editor" STUB_DO=put-next \
    STUB_PAYLOAD="$CASE/payload" -- -l 4711 "$f" <<<'e'
  assert_rc 0
  assert_content "$f" $'{"a": 2}\n'
  [[ ! -e $CASE/mark/launches ]] || mapfile -t launches < "$CASE/mark/launches"
  if ((${#launches[@]} != 2)); then
    fail "the editor was started ${#launches[@]} times, expected 2"
    return 0
  fi
  [[ ${launches[0]} == *4711* ]] || fail "the first launch was not sent to the line: ${launches[0]}"
  [[ ${launches[1]} != *4711* ]] || fail "the re-edit was sent to the line again: ${launches[1]}"
}

test_help_into_closed_pipe() {
  local -i closed
  local -- opt
  # A pipe whose reader has already gone
  exec {closed}> >(exit 0)
  wait "$!" || fail 'could not set up a closed pipe'
  for opt in --help --version; do
    RC=0
    env --default-signal=PIPE -- "$EDIT_FILE" "$opt" 1>&"$closed" 2>"$CASE/stderr" || RC=$?
    ((RC == 0)) || fail "$opt: exit status $RC, expected 0"
    [[ ! -s $CASE/stderr ]] || fail "$opt: stderr: $(<"$CASE/stderr")"
  done
  exec {closed}>&-
}

# Make a filetype package in $CASE/pkg whose library consists of the given
# lines. editfile is led to it by a function called `type` in its environment
# (bash looks functions up before builtins): FAKE_TYPE holds that function.
# The library leaves a marker, so that a test can tell whether it was reached.
plant_package() {
  local -- pkg=$CASE/pkg real
  real=$(type -P editcmd) || { fail 'editcmd is not installed'; return 1; }
  # Each step is checked: callers test this function's status, which turns
  # errexit off inside it
  mkdir -- "$pkg" || { fail "cannot create ${pkg@Q}"; return 1; }
  ln -s -- "$real" "$pkg/editcmd" || { fail 'cannot link editcmd into the package'; return 1; }
  #shellcheck disable=SC2016  # expanded when editfile sources the library
  printf '%s\n' ': > "$STUB_MARK/planted-library"' "$@" > "$pkg/filetype" \
    || { fail 'cannot write the planted library'; return 1; }
  FAKE_TYPE="() { if [[ \$1 == -P && \$2 == editcmd ]]; then
    echo ${pkg@Q}/editcmd
  else
    builtin type \"\$@\"
  fi
}"
}

test_failed_type_detection_is_fatal() {
  local -- f=$WORK/notes.txt
  plant_package 'filetype() { return 1; }' || return 0
  printf 'one\n' > "$f"
  edit STUB_DO=append "BASH_FUNC_type%%=$FAKE_TYPE" -- "$f"
  [[ -e $CASE/mark/planted-library ]] \
    || { SKIP='functions are not imported from the environment'; return 0; }
  assert_rc 1
  assert_stderr 'File type detection failed'
  [[ $(<"$f") == one ]] || fail 'the file was edited although its type is unknown'
  assert_no_leftovers
}

test_library_that_cannot_be_loaded() {
  local -- f=$WORK/notes.txt lib=$CASE/pkg/filetype
  plant_package 'return 3' || return 0
  printf 'one\n' > "$f"
  edit STUB_DO=append "BASH_FUNC_type%%=$FAKE_TYPE" -- "$f"
  [[ -e $CASE/mark/planted-library ]] \
    || { SKIP='functions are not imported from the environment'; return 0; }
  assert_rc 18
  assert_stderr "${lib@Q}"
  assert_content "$f" $'one\n'
  assert_no_leftovers
}

test_posixly_correct_environment() {
  local -- f=$WORK/notes.txt
  printf 'one\n' > "$f"
  # GNU tools stop reading options at the first operand when this is set
  edit POSIXLY_CORRECT=1 STUB_DO=append -- "$f"
  ((RC == 0)) || fail "exit status $RC, expected 0: $(tail -n 1 -- "$CASE/stderr")"
  [[ $(<"$f") == $'one\nedited' ]] || fail 'the edit was not saved'
  assert_no_leftovers
}

test_unresolvable_path_is_named() {
  local -- f=$WORK/notes.txt
  printf 'one\n' > "$f"
  # realpath -m fails only in odd places (a working directory that has been
  # removed), so a function in editfile's environment fails it on demand
  #shellcheck disable=SC2016  # expanded inside editfile
  edit STUB_DO=append 'BASH_FUNC_realpath%%=() { if [[ $1 == -m ]]; then
    : > "$STUB_MARK/realpath-failed"
    return 1
  fi
  command realpath "$@"
}' -- "$f"
  [[ -e $CASE/mark/realpath-failed ]] \
    || { SKIP='functions are not imported from the environment'; return 0; }
  assert_rc 5
  assert_stderr "Cannot resolve path ${f@Q}"
  assert_content "$f" $'one\n'
  assert_no_leftovers
}

test_binary_on_path_names_the_way_out() {
  edit -- ls
  assert_rc 10
  assert_stderr './ls'
  assert_absent "$WORK/ls" 'a file was created'
}

# What the completion file in the repository offers for a command line typed
# in $WORK, in a shell whose IFS is <ifs> and that has <option> set ('' for
# none); one candidate per line.
#   completions_for <bash-completion library> <ifs> <option> <word>...
# The library loads whatever copy of the completion is installed. That one is
# forgotten before the file under test is read, so that nothing else can
# answer for it; each step ends the inner shell if it fails.
completions_for() {
  #shellcheck disable=SC2016  # expanded by the inner shell
  bash -c 'source -- "$1" || exit
    unset -f _editfile
    source -- "$2" || exit
    cd -- "$3" || exit
    COMP_WORDS=("${@:6}") COMP_CWORD=$(($# - 6)) COMP_LINE="${*:6}"
    COMP_POINT=${#COMP_LINE}
    # The state under test: this shell exists only for the one call
    IFS=$4
    [[ -z $5 ]] || shopt -s "$5" || exit
    _editfile || exit
    printf "%s\n" "${COMPREPLY[@]}"' _ "$1" "$COMPLETION" "$WORK" "${@:2}" 2>&1
}

# Record a failure unless the completion of the last word, in the usual IFS,
# is exactly <expected> (one candidate per line; '' for none)
#   completes_to <bash-completion library> <expected> <option> <word>...
completes_to() {
  local -- expected=$2 line="'${*:4}'${3:+ with $3 set}" out
  out=$(completions_for "$1" $' \t\n' "${@:3}") \
    || { fail "the completion function failed for $line: $out"; return 0; }
  [[ $out == "$expected" ]] \
    || fail "for $line the completion offers ${out@Q}, not ${expected@Q}"
}

test_completion_candidates() {
  local -- lib=/usr/share/bash-completion/bash_completion ifs out opt
  [[ -r $lib ]] || { SKIP='bash-completion is not installed'; return 0; }
  printf 'one\n' > "$WORK/notes.txt"
  printf 'two\n' > "$WORK/-dash.txt"
  # The user's shell may have any IFS: the list of options is split on it
  for ifs in $' \t\n' ','; do
    out=$(completions_for "$lib" "$ifs" '' editfile -) \
      || { fail "the completion function failed (IFS ${ifs@Q}): $out"; return 0; }
    for opt in -n --no-validate -l --line -s --shellcheck -v --verbose -q --quiet \
        -V --version -h --help; do
      grep -qxF -- "$opt" <<<"$out" || fail "$opt is not offered (IFS ${ifs@Q})"
    done
  done
  # A word is started in each case: outside an interactive shell the library
  # finds no file names for an empty one
  completes_to "$lib" notes.txt '' editfile no
  completes_to "$lib" notes.txt '' editfile -l 5 no
  completes_to "$lib" notes.txt nocasematch editfile -v no
  completes_to "$lib" -dash.txt '' editfile -- -d
  completes_to "$lib" --no-validate '' editfile notes.txt --no
  # The program wants a number after -l, also at the end of a bundle, and
  # takes one file name
  completes_to "$lib" '' '' editfile -l no
  completes_to "$lib" '' '' editfile -nl no
  completes_to "$lib" '' '' editfile notes.txt no
  completes_to "$lib" '' '' editfile -- notes.txt no
  completes_to "$lib" '' '' editfile -- -dash.txt no
  # Words arrive as typed, quotes and all; the program sees them without
  completes_to "$lib" notes.txt '' editfile '"-n"' no
  completes_to "$lib" -dash.txt '' editfile "'--'" -d
  completes_to "$lib" '' '' editfile "'-d"
}

# Test runner

# <id> <test function> <what the test establishes>
# While COLLECTING is set only the ID is noted: main() goes through the tests
# once to learn their names, and then again to run them
run() {
  local -- id=$1 fn=$2 title=$3 line
  if ((COLLECTING)); then
    IDS+=("$id")
    return 0
  fi
  if ((${#ONLY[@]})) && [[ " ${ONLY[*]} " != *" $id "* ]]; then
    return 0
  fi
  CASE=$SANDBOX/$id WORK=$SANDBOX/$id/work CWD=$SANDBOX/$id/work
  mkdir -p -- "$CASE/mark" "$WORK"
  : > "$CASE/stderr"
  FAILURES=() SKIP=''
  "$fn" </dev/null
  # A failure recorded before a test gave up still counts
  if ((${#FAILURES[@]})); then
    FAILED+=1
    printf '%s %-4s %s\n' "$RED✗$NC" "$id" "$title"
    for line in "${FAILURES[@]}"; do
      printf '         %s\n' "$line"
    done
  elif [[ -n $SKIP ]]; then
    SKIPPED+=1
    printf '%s %-4s %s (skipped: %s)\n' "$YELLOW▲$NC" "$id" "$title" "$SKIP"
  else
    PASSED+=1
    printf '%s %-4s %s\n' "$GREEN✓$NC" "$id" "$title"
  fi
}

tests() {
  run C1 test_sigint_survived_by_editor \
    'Ctrl-C that the editor survives does not end the session'
  run H1 test_failed_save_keeps_edits \
    'a failed save keeps the edits'
  run H2a test_sigterm_during_edit \
    'SIGTERM during the edit: status 143, edits kept'
  run H2b test_sighup_during_edit \
    'SIGHUP during the edit: status 129, edits kept'
  run H2c test_sigint_at_prompt \
    'Ctrl-C at the e/s/q prompt: status 130, edits kept'
  run H2d test_signal_without_edits \
    'a signal with nothing edited: status 143, nothing left behind'
  run H2e test_editor_failure_keeps_edits \
    'an editor that fails after writing: edits kept'
  run H3a test_csv_ignores_planted_module \
    'CSV check does not import csv.py from the working directory'
  run H3b test_toml_ignores_planted_module \
    'TOML check does not import tomllib.py from the working directory'
  run H3c test_json_ignores_planted_module \
    'JSON fallback does not import json.py from the working directory'
  run H3d test_yaml_ignores_planted_module \
    'YAML fallback does not import yaml.py from the working directory'
  run H3e test_xml_ignores_planted_module \
    'XML fallback does not import xml.py from the working directory'
  run H4 test_swapped_working_copy_not_installed \
    'a working copy swapped for a symlink is not installed'
  run M1a test_binary_with_text_extension_refused \
    'a binary file with a text extension is refused, every time'
  run M1b test_nul_probe_independent_of_timing \
    'the NUL probe does not depend on pipeline timing'
  run M1c test_compressed_file_refused \
    'a compressed file is refused whatever name it records'
  run M1d test_library_binary_verdict_reported \
    'a file the filetype library calls binary: status 10'
  run M1e test_text_encodings_stay_editable \
    'UTF-16, Latin-1, escape sequences and empty files stay editable'
  run M2 test_editor_gets_callers_path \
    "the editor runs with the caller's PATH"
  run M3 test_editor_gets_default_sigpipe \
    'the editor runs with SIGPIPE at its default'
  run M5 test_unvalidated_save_not_called_validated \
    'without a validator the save is not called validated'
  run M6a test_typeahead_not_passed_to_editor \
    'typing "yes" at a prompt leaves nothing for the editor'
  run M6b test_prompt_answers \
    'prompts take y or yes; anything else, or end-of-file, is no'
  run V1 test_shell_validator \
    'shell: extglob patterns accepted, syntax errors rejected'
  run V2 test_yaml_validator \
    'YAML: whitespace style accepted, syntax errors and duplicate keys rejected'
  run V3 test_html_validator \
    'HTML: custom elements accepted, unknown tags rejected'
  run V4 test_csv_validator \
    'CSV: other delimiters and encodings accepted, ragged rows rejected by line'
  run V5 test_ini_validator \
    'INI: common dialects accepted, a broken section header rejected'
  run V6 test_json_validator \
    'JSON: exactly one document required'
  run V7 test_toml_validator \
    'TOML: errors reported in one line'
  run V8 test_xml_validator \
    'XML: well-formedness'
  run V9 test_python_validator \
    'Python: syntax'
  run V10 test_php_validator \
    'PHP: syntax, with nothing printed on success'
  run L6a test_json_fallback_shows_error \
    'JSON fallback shows why validation failed'
  run L6b test_yaml_fallback_accepts_documents_and_tags \
    'YAML fallback accepts several documents and custom tags'
  run L7 test_validation_messages \
    'no empty message lines'
  run P1 test_fix_after_failed_validation \
    'prompt: e reopens the editor and the corrected file is saved'
  run P2 test_save_despite_failed_validation \
    'prompt: s saves the file as it is'
  run P3 test_quit_after_failed_validation \
    'prompt: q discards the edit'
  run L1 test_path_search_ignores_own_functions \
    'PATH search finds a script named like an internal function'
  run L1b test_dependency_lookup_ignores_functions \
    'a function named editcmd does not redirect the library lookup'
  run L17 test_name_ending_in_newline_refused \
    'a name ending in a newline is refused'
  run L20 test_new_script_without_extension_validated \
    'a new script without an extension is validated'
  run S1 test_edit_is_saved \
    'an edit is saved'
  run S2 test_unchanged_file_left_alone \
    'an unchanged file is not rewritten'
  run S3 test_modes_survive_a_save \
    'file modes survive a save, setuid included'
  run S4 test_new_file_mode_follows_umask \
    'a new file gets its mode from the umask'
  run S5 test_new_file_in_new_directory \
    'a new file in a new directory is created'
  run L4 test_abandoned_new_file_removes_created_dirs \
    'directories made for a new file go when the file is abandoned'
  run S6 test_symlink_followed_and_kept \
    'a symlink is followed and stays a symlink'
  run S7 test_external_change_not_overwritten \
    'a file changed by someone else is not overwritten unasked'
  run L3a test_file_created_meanwhile_not_overwritten \
    'a file created by someone else meanwhile is not overwritten unasked'
  run L3b test_file_created_meanwhile_overwritten_on_request \
    'a file created meanwhile is overwritten on request'
  run L19 test_empty_file_created_on_request \
    'an empty file the user asked for is created without validation'
  run S8 test_hostile_filenames \
    'file names with shell syntax in them are only ever names'
  run S8b test_hostile_dir_yaml \
    'a directory name with shell and Python syntax is inert (YAML, Python fallback)'
  run S8c test_hostile_dir_xml \
    'a directory name with shell and Python syntax is inert (XML, Python fallback)'
  run S8d test_hostile_dir_toml \
    'a directory name with shell and Python syntax is inert (TOML)'
  run S9 test_exit_codes \
    'documented exit statuses'
  run O1 test_no_validate_option \
    '-n saves without validating'
  run O2 test_shellcheck_option \
    '-s adds shellcheck advice without failing the save'
  run O3 test_quiet_option \
    '-q prints nothing on success and still reports errors'
  run O4 test_line_option_reaches_editor \
    '-l sends the editor to the line, on the first launch only'
  run L21 test_help_into_closed_pipe \
    '--help and --version into a closed pipe are silent and succeed'
  run R1 test_failed_type_detection_is_fatal \
    'a type detection that fails stops the edit'
  run R4 test_library_that_cannot_be_loaded \
    'a filetype library that cannot be loaded: status 18, and the message names it'
  run R2 test_posixly_correct_environment \
    'POSIXLY_CORRECT in the environment does not break an edit'
  run R3 test_unresolvable_path_is_named \
    'a path that cannot be resolved: status 5, and the message names it'
  run R7 test_path_search_skips_relative_entries \
    'PATH search goes on past a relative entry to an absolute one'
  run R12 test_line_number_ascii_digits \
    '-l takes ASCII digits only, whatever the locale'
  run L2 test_binary_on_path_names_the_way_out \
    'a binary found on PATH: status 10, and how to make a local file instead'
  run L12 test_completion_candidates \
    'completion: every option whatever the IFS, one file name, nothing where -l wants its number'
}

main() {
  local -- id
  ONLY=("$@")
  COLLECTING=1
  tests
  COLLECTING=0
  # A name that selects nothing would otherwise pass for a successful run
  for id in "${ONLY[@]}"; do
    [[ $id != *[[:space:]]* && " ${IDS[*]} " == *" $id "* ]] \
      || die 22 "No test is called ${id@Q}; the tests are ${IDS[*]}"
  done
  readonly ONLY

  setup
  echo "Testing $EDIT_FILE"
  tests
  echo
  echo "$PASSED passed, $FAILED failed, $SKIPPED skipped"
  ((FAILED == 0))
}

main "$@"
#fin
