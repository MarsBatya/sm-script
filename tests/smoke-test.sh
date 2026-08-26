#!/usr/bin/env bash
#
# Smoke-test harness for `sm`.
#
# Runs the real sm script from this repo against a fully sandboxed
# environment: isolated $HOME (so ~/.sm/projects.txt and ~/.bashrc are
# throwaway), and fake `sudo`/`systemctl`/`journalctl` binaries placed
# first on PATH so nothing here ever touches the real systemd, the real
# /etc/systemd/system, or the real /usr/local/bin/sm symlink.
#
# Deliberately NOT covered:
#   - `sm uninstall`   -- deletes /usr/local/bin/sm and ~/.sm for real;
#                          too destructive to safely script here.
#   - `sm update`      -- runs `git pull` against this repo; touches
#                          real repo state / needs network.
#   - `sm install-helpers` -- only appends to a (sandboxed) ~/.bashrc, so
#                          it's safe, but it tests bashrc string-appending
#                          rather than service management; out of scope.
#
# Usage: ./tests/smoke-test.sh
# Exit code is nonzero if any test failed (CI-usable).

set -uo pipefail   # deliberately no -e: sm exits nonzero by design in
                    # several tests we assert on; -e would abort the harness
                    # on the first "expected failure" case.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SM_SCRIPT="$REPO_ROOT/sm"

if [[ ! -x "$SM_SCRIPT" ]]; then
    echo "FATAL: sm script not found or not executable at $SM_SCRIPT" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Sandbox setup
# ---------------------------------------------------------------------------

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

MOCKBIN="$SANDBOX/bin"
WORKDIR="$SANDBOX/work"
export HOME="$SANDBOX/home"
export SM_TEST_ETC_DIR="$SANDBOX/etc"
export SM_TEST_STATE_DIR="$SANDBOX/systemctl-state"
export SM_TEST_SUDO_LOG="$SANDBOX/sudo.log"
export SM_TEST_JOURNALCTL_LOG="$SANDBOX/journalctl.log"

mkdir -p "$MOCKBIN" "$WORKDIR" "$HOME" "$SM_TEST_ETC_DIR/systemd/system" "$SM_TEST_STATE_DIR"
: > "$SM_TEST_SUDO_LOG"
: > "$SM_TEST_JOURNALCTL_LOG"

# `find_sm_repo` (used by cmd_install_helpers/cmd_update, and indirectly
# exercised whenever `command -v sm` is resolved) resolves the real script
# location via `readlink -f`, so it must be a real symlink to the repo's sm.
ln -s "$SM_SCRIPT" "$MOCKBIN/sm"

# --- fake sudo ---------------------------------------------------------
# Rewrites /etc/systemd/system -> the sandboxed etc dir so `cp`/`rm` land
# there instead of the real filesystem. Refuses anything that touches the
# real sm install symlink, as a hard stop in case a future test path ever
# tries to invoke `sm uninstall` by accident.
cat > "$MOCKBIN/sudo" <<'EOF'
#!/usr/bin/env bash
case " $* " in
    *"/usr/local/bin/sm"*)
        echo "fake sudo: refusing to touch the real install symlink: $*" >&2
        exit 1
        ;;
esac
args=()
for a in "$@"; do
    args+=("${a//\/etc\/systemd\/system//${SM_TEST_ETC_DIR}\/systemd\/system}")
done
printf 'sudo: %s\n' "$*" >> "$SM_TEST_SUDO_LOG"
exec "${args[@]}"
EOF
chmod +x "$MOCKBIN/sudo"

# --- fake systemctl ------------------------------------------------------
# Minimal stateful stub: tracks active/enabled/pid/timestamp per unit in
# $SM_TEST_STATE_DIR/<unit>.state so is-active/show reflect prior
# start/stop/enable/disable calls made through it.
cat > "$MOCKBIN/systemctl" <<'EOF'
#!/usr/bin/env bash
STATE_DIR="${SM_TEST_STATE_DIR:?SM_TEST_STATE_DIR not set}"
mkdir -p "$STATE_DIR"

state_file() { echo "$STATE_DIR/$1.state"; }

get_field() {
    local unit="$1" field="$2" default="$3" f
    f=$(state_file "$unit")
    [[ -f "$f" ]] || { echo "$default"; return; }
    awk -F= -v k="$field" '$1==k{print $2; found=1} END{if(!found) print ""}' "$f"
}

set_field() {
    local unit="$1" field="$2" value="$3" f
    f=$(state_file "$unit")
    touch "$f"
    if grep -q "^$field=" "$f" 2>/dev/null; then
        sed -i "s|^$field=.*|$field=$value|" "$f"
    else
        echo "$field=$value" >> "$f"
    fi
}

do_is_active() {
    local quiet=false
    local units=()
    for a in "$@"; do
        if [[ "$a" == "--quiet" ]]; then quiet=true; else units+=("$a"); fi
    done
    local all_active=0
    for u in "${units[@]}"; do
        local st
        st=$(get_field "$u" active inactive)
        [[ -z "$st" ]] && st=inactive
        [[ "$quiet" == false ]] && echo "$st"
        [[ "$st" != "active" ]] && all_active=1
    done
    return "$all_active"
}

do_show() {
    local prop=""
    local units=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p) prop="$2"; shift 2 ;;
            *) units+=("$1"); shift ;;
        esac
    done
    for u in "${units[@]}"; do
        case "$prop" in
            ActiveState)
                local st; st=$(get_field "$u" active inactive)
                echo "ActiveState=${st:-inactive}"
                ;;
            SubState)
                local st; st=$(get_field "$u" active inactive)
                [[ "$st" == "active" ]] && echo "SubState=running" || echo "SubState=dead"
                ;;
            LoadState)
                echo "LoadState=loaded"
                ;;
            MainPID)
                echo "MainPID=$(get_field "$u" pid 0)"
                ;;
            Restart)
                echo "Restart=always"
                ;;
            ActiveEnterTimestamp)
                echo "ActiveEnterTimestamp=$(get_field "$u" since n/a)"
                ;;
            InactiveEnterTimestamp)
                echo "InactiveEnterTimestamp=$(get_field "$u" since n/a)"
                ;;
            *)
                echo "$prop="
                ;;
        esac
    done
}

cmd="${1:-}"
shift || true
case "$cmd" in
    enable)
        for u in "$@"; do set_field "$u" enabled 1; done
        ;;
    disable)
        for u in "$@"; do set_field "$u" enabled 0; done
        ;;
    restart)
        for u in "$@"; do
            set_field "$u" active active
            set_field "$u" pid $$
            set_field "$u" since "$(date '+%a %Y-%m-%d %H:%M:%S UTC')"
        done
        ;;
    stop)
        for u in "$@"; do
            set_field "$u" active inactive
            set_field "$u" since "$(date '+%a %Y-%m-%d %H:%M:%S UTC')"
        done
        ;;
    daemon-reload)
        ;;
    is-active)
        do_is_active "$@"
        exit $?
        ;;
    show)
        do_show "$@"
        ;;
    *)
        echo "fake systemctl: unhandled command: $cmd $*" >&2
        exit 1
        ;;
esac
EOF
chmod +x "$MOCKBIN/systemctl"

# --- fake systemd-analyze --------------------------------------------------
# Minimal fake of `systemd-analyze verify FILE`: extracts ExecStart's
# executable and checks it resolves (absolute path exists, or bare command
# is on PATH), mirroring the real tool's core check closely enough for
# tests without depending on the real systemd-analyze being installed.
cat > "$MOCKBIN/systemd-analyze" <<'EOF'
#!/usr/bin/env bash
cmd="${1:-}"
shift || true
if [[ "$cmd" != "verify" ]]; then
    echo "fake systemd-analyze: unhandled command: $cmd $*" >&2
    exit 1
fi
file="$1"
if [[ ! -f "$file" ]]; then
    echo "Unit $file not found." >&2
    exit 1
fi
exec_line=$(grep -E '^ExecStart=' "$file" | head -1 | cut -d= -f2-)
exec_bin=$(awk '{print $1}' <<< "$exec_line")
if [[ -z "$exec_bin" ]]; then
    exit 0
fi
if [[ "$exec_bin" == /* ]]; then
    [[ -e "$exec_bin" ]] || { echo "$(basename "$file"): Command $exec_bin is not executable: No such file or directory" >&2; exit 1; }
else
    command -v "$exec_bin" >/dev/null 2>&1 || { echo "$(basename "$file"): Command $exec_bin is not executable: No such file or directory" >&2; exit 1; }
fi
exit 0
EOF
chmod +x "$MOCKBIN/systemd-analyze"

# --- fake journalctl -------------------------------------------------------
# Never actually follows/blocks -- just records its argv so tests can
# assert on exactly what sm passed it, then exits immediately.
cat > "$MOCKBIN/journalctl" <<'EOF'
#!/usr/bin/env bash
printf 'journalctl: %s\n' "$*" >> "$SM_TEST_JOURNALCTL_LOG"
echo "[fake journalctl output]"
EOF
chmod +x "$MOCKBIN/journalctl"

# ---------------------------------------------------------------------------
# Test framework
# ---------------------------------------------------------------------------

PASS_COUNT=0
FAIL_COUNT=0

# Runs `sm` (via the mock bin's symlink) with stdin closed so an
# unexpected `read -p` fails fast instead of hanging, and with the mock
# bin first on PATH so sudo/systemctl/journalctl resolve to our fakes.
# Sets $out and $rc; never exits the harness on nonzero.
run_sm() {
    out=$(cd "$WORKDIR" && PATH="$MOCKBIN:$PATH" "$MOCKBIN/sm" "$@" 2>&1 </dev/null)
    rc=$?
}

# Same, but feeds $1 as stdin (for commands that prompt) instead of /dev/null.
run_sm_with_input() {
    local input="$1"
    shift
    out=$(cd "$WORKDIR" && printf '%s' "$input" | PATH="$MOCKBIN:$PATH" "$MOCKBIN/sm" "$@" 2>&1)
    rc=$?
}

pass() {
    PASS_COUNT=$((PASS_COUNT + 1))
    echo "  PASS: $1"
}

fail() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "  FAIL: $1"
    [[ -n "${2:-}" ]] && echo "        $2"
}

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        pass "$desc"
    else
        fail "$desc" "expected [$expected], got [$actual]"
    fi
}

assert_contains() {
    local desc="$1" haystack="$2" needle="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        pass "$desc"
    else
        fail "$desc" "expected output to contain [$needle], got: $haystack"
    fi
}

assert_not_contains() {
    local desc="$1" haystack="$2" needle="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        pass "$desc"
    else
        fail "$desc" "expected output NOT to contain [$needle], got: $haystack"
    fi
}

section() {
    echo
    echo "== $1 =="
}

# Registers a project directly in the registry file, bypassing `sm add`,
# for tests that only care about behavior downstream of registration.
register_project() {
    local name="$1" service_file="$2" working_dir="$3" owned="${4:-1}"
    mkdir -p "$HOME/.sm"
    touch "$HOME/.sm/projects.txt"
    echo "$name:$service_file:$working_dir:$owned" >> "$HOME/.sm/projects.txt"
}

reset_registry() {
    mkdir -p "$HOME/.sm"
    : > "$HOME/.sm/projects.txt"
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

section "add: existing .service file, fresh name"
reset_registry
proj_dir="$WORKDIR/proj-add"
mkdir -p "$proj_dir"
cat > "$proj_dir/smtest-add.service" <<'EOF'
[Unit]
Description=test
[Service]
ExecStart=/bin/true
[Install]
WantedBy=multi-user.target
EOF
out=$(cd "$proj_dir" && PATH="$MOCKBIN:$PATH" "$MOCKBIN/sm" add 2>&1 </dev/null)
rc=$?
assert_eq "add: exits 0" "0" "$rc"
registry_line=$(grep "^smtest-add:" "$HOME/.sm/projects.txt" 2>/dev/null)
assert_contains "add: registry line has 4 fields, owned=1" "$registry_line" ":1"
field_count=$(awk -F: '{print NF}' <<< "$registry_line")
assert_eq "add: registry line field count" "4" "$field_count"
assert_eq "add: unit landed in sandboxed etc, not real /etc" "1" \
    "$([[ -f "$SM_TEST_ETC_DIR/systemd/system/smtest-add.service" ]] && echo 1 || echo 0)"

section "start / restart / stop enable-disable semantics"
reset_registry
register_project "smtest-svc" "$WORKDIR/smtest-svc.service" "$WORKDIR" 1
: > "$SM_TEST_SUDO_LOG"

run_sm start smtest-svc
assert_eq "start: exits 0" "0" "$rc"
assert_contains "start: started successfully message" "$out" "started successfully"
assert_contains "start: enables by default" "$(cat "$SM_TEST_SUDO_LOG")" "enable smtest-svc.service"

: > "$SM_TEST_SUDO_LOG"
run_sm start smtest-svc --no-enable
assert_not_contains "start --no-enable: does not enable" "$(cat "$SM_TEST_SUDO_LOG")" "enable smtest-svc.service"

: > "$SM_TEST_SUDO_LOG"
run_sm restart smtest-svc
assert_eq "restart: exits 0" "0" "$rc"
assert_contains "restart: restarted successfully message" "$out" "restarted successfully"
sudo_log=$(cat "$SM_TEST_SUDO_LOG")
assert_not_contains "restart: does not touch enable" "$sudo_log" "enable smtest-svc.service"
assert_not_contains "restart: does not touch disable" "$sudo_log" "disable smtest-svc.service"

: > "$SM_TEST_SUDO_LOG"
run_sm stop smtest-svc
assert_eq "stop: exits 0" "0" "$rc"
assert_not_contains "stop: does not disable by default" "$(cat "$SM_TEST_SUDO_LOG")" "disable"

: > "$SM_TEST_SUDO_LOG"
run_sm stop smtest-svc --disable
assert_contains "stop --disable: disables" "$(cat "$SM_TEST_SUDO_LOG")" "disable smtest-svc.service"

section "start / restart: pre-flight validation via systemd-analyze verify"
reset_registry
proj_dir="$WORKDIR/proj-verify"
mkdir -p "$proj_dir"

cat > "$proj_dir/smtest-badexec.service" <<'EOF'
[Unit]
Description=bad exec
[Service]
ExecStart=/nonexistent/path/to/binary
[Install]
WantedBy=multi-user.target
EOF
register_project "smtest-badexec" "$proj_dir/smtest-badexec.service" "$proj_dir" 1

: > "$SM_TEST_SUDO_LOG"
run_sm start smtest-badexec
assert_eq "start: bad ExecStart fails validation, exits nonzero" "1" "$rc"
assert_contains "start: reports validation failure" "$out" "failed validation"
assert_not_contains "start: does not proceed to systemctl restart after failed validation" \
    "$(cat "$SM_TEST_SUDO_LOG")" "restart smtest-badexec.service"

: > "$SM_TEST_SUDO_LOG"
run_sm start smtest-badexec --skip-verify
assert_eq "start --skip-verify: bypasses validation, exits 0" "0" "$rc"
assert_contains "start --skip-verify: proceeds to systemctl restart" \
    "$(cat "$SM_TEST_SUDO_LOG")" "restart smtest-badexec.service"

: > "$SM_TEST_SUDO_LOG"
run_sm restart smtest-badexec
assert_eq "restart: bad ExecStart fails validation, exits nonzero" "1" "$rc"
assert_contains "restart: reports validation failure" "$out" "failed validation"

cat > "$proj_dir/smtest-goodexec.service" <<'EOF'
[Unit]
Description=good exec
[Service]
ExecStart=/bin/true
[Install]
WantedBy=multi-user.target
EOF
register_project "smtest-goodexec" "$proj_dir/smtest-goodexec.service" "$proj_dir" 1

run_sm start smtest-goodexec
assert_eq "start: valid unit passes validation, exits 0" "0" "$rc"
assert_not_contains "start: no validation failure reported for valid unit" "$out" "failed validation"

run_sm restart smtest-goodexec
assert_eq "restart: valid unit passes validation, exits 0" "0" "$rc"

section "remove: respects ownership"
reset_registry
register_project "smtest-owned" "$WORKDIR/o.service" "$WORKDIR" 1
touch "$SM_TEST_ETC_DIR/systemd/system/smtest-owned.service"
run_sm_with_input $'y\n' remove smtest-owned
assert_eq "remove owned=1: exits 0" "0" "$rc"
assert_eq "remove owned=1: unit file deleted from sandbox" "0" \
    "$([[ -f "$SM_TEST_ETC_DIR/systemd/system/smtest-owned.service" ]] && echo 1 || echo 0)"
assert_eq "remove owned=1: removed from registry" "" \
    "$(grep "^smtest-owned:" "$HOME/.sm/projects.txt" 2>/dev/null)"

reset_registry
register_project "smtest-unowned" "$WORKDIR/u.service" "$WORKDIR" 0
touch "$SM_TEST_ETC_DIR/systemd/system/smtest-unowned.service"
run_sm_with_input $'y\n' remove smtest-unowned
assert_eq "remove owned=0: exits 0" "0" "$rc"
assert_eq "remove owned=0: unit file NOT deleted" "1" \
    "$([[ -f "$SM_TEST_ETC_DIR/systemd/system/smtest-unowned.service" ]] && echo 1 || echo 0)"

# Legacy 3-field registry line (predates the "owned" column): should default
# to owned=1, matching the pre-upgrade always-delete behavior.
reset_registry
mkdir -p "$HOME/.sm"
echo "smtest-legacy:$WORKDIR/l.service:$WORKDIR" >> "$HOME/.sm/projects.txt"
touch "$SM_TEST_ETC_DIR/systemd/system/smtest-legacy.service"
run_sm_with_input $'y\n' remove smtest-legacy
assert_eq "remove legacy 3-field line: exits 0" "0" "$rc"
assert_eq "remove legacy 3-field line: unit file deleted (owned defaults to 1)" "0" \
    "$([[ -f "$SM_TEST_ETC_DIR/systemd/system/smtest-legacy.service" ]] && echo 1 || echo 0)"

section "logs: -s / -n flag combinations"
reset_registry
register_project "smtest-logs" "$WORKDIR/logs.service" "$WORKDIR" 1

: > "$SM_TEST_JOURNALCTL_LOG"
run_sm logs smtest-logs -s 2d --no-follow
assert_eq "logs -s only: exits 0" "0" "$rc"
jctl_call=$(cat "$SM_TEST_JOURNALCTL_LOG")
assert_contains "logs -s only: passes --since" "$jctl_call" "--since 2 days ago"
assert_not_contains "logs -s only: does NOT pass -n (unlimited since)" "$jctl_call" " -n "

: > "$SM_TEST_JOURNALCTL_LOG"
run_sm logs smtest-logs -s 2d -n 50 --no-follow
jctl_call=$(cat "$SM_TEST_JOURNALCTL_LOG")
assert_contains "logs -s + -n: passes --since" "$jctl_call" "--since 2 days ago"
assert_contains "logs -s + -n: also passes -n (regression check for the fixed bug)" "$jctl_call" "-n 50"

: > "$SM_TEST_JOURNALCTL_LOG"
run_sm logs smtest-logs -n 25 --no-follow
jctl_call=$(cat "$SM_TEST_JOURNALCTL_LOG")
assert_contains "logs -n only: passes -n" "$jctl_call" "-n 25"

section "name validation"
reset_registry
proj_dir="$WORKDIR/proj-badname"
mkdir -p "$proj_dir"
_saved_workdir="$WORKDIR"
WORKDIR="$proj_dir"
run_sm_with_input $'y\nbad:name\n' add
WORKDIR="$_saved_workdir"
assert_eq "add with ':' in name: exits nonzero" "1" "$rc"
assert_eq "add with ':' in name: registry has no entry for it" "" \
    "$(grep "^bad" "$HOME/.sm/projects.txt" 2>/dev/null)"

# Regression check: valid_project_name's charset (letters, digits, '.',
# '_', '-') would otherwise allow a name to *start* with '-', but every
# command that takes a positional [project_name] (start/stop/restart/
# logs/info/remove) parses leading-'-' args as flags first, so such a name
# could be registered but never referenced positionally afterwards.
reset_registry
proj_dir="$WORKDIR/proj-dashname"
mkdir -p "$proj_dir"
_saved_workdir="$WORKDIR"
WORKDIR="$proj_dir"
run_sm_with_input $'y\n-dash\nsome desc\n/bin/true\n' add
WORKDIR="$_saved_workdir"
assert_eq "add with leading '-' in name: rejected (name would be unusable positionally otherwise)" "1" "$rc"

section "info / ls: 4-field registry doesn't corrupt working_dir"
reset_registry
register_project "smtest-info" "$WORKDIR/info.service" "$WORKDIR/some/dir" 1
run_sm info smtest-info
assert_eq "info: exits 0" "0" "$rc"
assert_contains "info: working dir shown without trailing owned-flag" "$out" "$WORKDIR/some/dir"
assert_not_contains "info: working dir does NOT have a stray ':1' suffix" "$out" "${WORKDIR}/some/dir:1"

run_sm ls
assert_eq "ls: exits 0" "0" "$rc"
assert_contains "ls: working dir shown without trailing owned-flag" "$out" "$WORKDIR/some/dir"
assert_not_contains "ls: working dir does NOT have a stray ':1' suffix" "$out" "${WORKDIR}/some/dir:1"

section "ls: status reflects actual per-service state"
reset_registry
register_project "smtest-running" "$WORKDIR/r.service" "$WORKDIR" 1
register_project "smtest-stopped" "$WORKDIR/s.service" "$WORKDIR" 1
: > "$SM_TEST_SUDO_LOG"
run_sm start smtest-running
run_sm ls
running_row=$(echo "$out" | grep "^smtest-running" )
stopped_row=$(echo "$out" | grep "^smtest-stopped")
assert_contains "ls: started project shows running" "$running_row" "running"
assert_contains "ls: never-started project shows stopped" "$stopped_row" "stopped"

section "workdir: requires an explicit name (no cwd inference)"
reset_registry
register_project "smtest-wd" "$WORKDIR/wd.service" "$WORKDIR/wd-target" 1
run_sm workdir smtest-wd
assert_eq "workdir <name>: exits 0" "0" "$rc"
assert_eq "workdir <name>: prints the working dir" "$WORKDIR/wd-target" "$out"

run_sm workdir
assert_eq "workdir with no name: exits nonzero" "1" "$rc"

section "generate_service: sed special characters (&, |, \\) are escaped"
gen_dir="$WORKDIR/gen"
mkdir -p "$gen_dir"
gen_result=$(cd "$REPO_ROOT" && HOME="$HOME" bash -c '
    source <(sed -n "1,/^main \"\$@\"\$/p" "'"$SM_SCRIPT"'" | sed "\$d")
    init_sm
    generate_service "smtest-gen" "Runs A & B | C \\ things" \
        "/usr/bin/python3 main.py --flag \"a|b\"" "'"$gen_dir"'" "testuser" >/dev/null
    cat "'"$gen_dir"'/smtest-gen.service"
')
assert_contains "generate_service: & survives literally in Description" "$gen_result" "Description=Runs A & B | C \\ things"
assert_contains "generate_service: | inside ExecStart survives literally" "$gen_result" 'ExecStart=/usr/bin/python3 main.py --flag "a|b"'

# Regression check: a user-supplied Description containing literal
# "{{EXEC_START}}"/"{{WORKING_DIR}}" text must survive as plain text, not
# get re-substituted with the real values just because it happens to
# match a *different* field's template placeholder syntax.
gen_dir2="$WORKDIR/gen2"
mkdir -p "$gen_dir2"
gen_result2=$(cd "$REPO_ROOT" && HOME="$HOME" bash -c '
    source <(sed -n "1,/^main \"\$@\"\$/p" "'"$SM_SCRIPT"'" | sed "\$d")
    init_sm
    generate_service "smtest-gen2" "Deploys {{EXEC_START}} to {{WORKING_DIR}}" \
        "/usr/bin/python3 main.py" "'"$gen_dir2"'" "testuser" >/dev/null
    cat "'"$gen_dir2"'/smtest-gen2.service"
')
assert_contains "generate_service: literal {{EXEC_START}} in Description text is not re-substituted" \
    "$gen_result2" "Description=Deploys {{EXEC_START}} to {{WORKING_DIR}}"

section "remove: '.' in a project name must not act as a sed wildcard"
# Regression check: '.' is a legal character in a project name per
# valid_project_name, but it's "match any character" in a regex, so
# removing "my.app" must not also delete an unrelated entry like "myXapp"
# that merely has some other character in the same position.
reset_registry
register_project "my.app" "$WORKDIR/a.service" "$WORKDIR/a" 0
register_project "myXapp" "$WORKDIR/b.service" "$WORKDIR/b" 0
run_sm_with_input $'y\n' remove my.app
assert_eq "remove 'my.app': exits 0" "0" "$rc"
assert_eq "remove 'my.app': unrelated 'myXapp' entry survives (dot must not act as wildcard)" \
    "1" "$([[ -n "$(grep '^myXapp:' "$HOME/.sm/projects.txt" 2>/dev/null)" ]] && echo 1 || echo 0)"

section "add: multi-file picker rejects invalid selection"
# Regression check: unlike infer_project_name's equivalent prompt (which
# bounds-checks the choice), cmd_add's "multiple .service files" branch
# used to index the array with no validation at all -- non-numeric input
# like "abc" makes bash's arithmetic context treat it as an unset variable
# (== 0), so choice-1 silently evaluated to -1, and negative array
# indexing silently selected the LAST file. Now it must be rejected
# up front instead, same as infer_project_name's prompt.
reset_registry
proj_dir="$WORKDIR/proj-multi"
mkdir -p "$proj_dir"
for svc in alpha beta gamma; do
    cat > "$proj_dir/$svc.service" <<EOF
[Unit]
Description=$svc
[Service]
ExecStart=/bin/true
EOF
done
_saved_workdir="$WORKDIR"
WORKDIR="$proj_dir"
run_sm_with_input $'abc\n' add
WORKDIR="$_saved_workdir"
assert_eq "add: garbage selection ('abc') exits nonzero instead of silently succeeding" "1" "$rc"
assert_contains "add: garbage selection ('abc') reports invalid selection" "$out" "Invalid selection"
assert_eq "add: garbage selection ('abc') is not silently mapped to the last (gamma) entry" \
    "0" "$([[ -n "$(grep '^gamma:' "$HOME/.sm/projects.txt" 2>/dev/null)" ]] && echo 1 || echo 0)"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo
echo "======================================"
echo "PASSED: $PASS_COUNT"
echo "FAILED: $FAIL_COUNT"
echo "======================================"

[[ "$FAIL_COUNT" -eq 0 ]]
