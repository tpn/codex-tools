#!/usr/bin/env zsh

emulate -L zsh -o errexit -o nounset -o pipefail

export HOST="spark"
export USER="trent"
export CODEX_LOG_DIR="$PWD/.tmp/codex-logs"
export CLAUDE_LOG_DIR="$PWD/.tmp/claude-logs"
export COPILOT_LOG_DIR="$PWD/.tmp/copilot-logs"

typeset -ga TITLEBAR_CALLS=()
typeset -ga TMUX_CALLS=()
typeset -ga STRIP_ANSI_CALLS=()
typeset -ga TMUX_SESSION_LIST=()
typeset -gA TMUX_SESSION_EXISTS=()
typeset -gA TMUX_SESSION_TITLE=()
typeset -g TEST_TMUX_EXTRA_ENV_FILE="$PWD/.tmp/tmux-extra-env.local"
typeset -g TEST_FZF_SELECTION=""
typeset -g TEST_SHOW_OPTIONS_OUTPUT=""
typeset -g TEST_SESSION_STAMP="2026.03.22.12.34.56"
typeset -g TEST_HEADER_STAMP="2026-03-22 12:34:56 PDT"
typeset -g TEST_TMUX_ATTACH_EXITS_SESSION="0"

fail() {
    print -u2 -- "FAIL: $*"
    exit 1
}

assert_eq() {
    local actual="$1"
    local expected="$2"
    local message="$3"
    if [[ "$actual" != "$expected" ]]; then
        fail "$message: expected <$expected>, got <$actual>"
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        fail "$message: expected to find <$needle>"
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local message="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        fail "$message: unexpected match <$needle>"
    fi
}

assert_title_calls() {
    local expected_first="$1"
    local expected_second="$2"
    local label="$3"
    if (( ${#TITLEBAR_CALLS[@]} != 2 )); then
        fail "$label: expected 2 titlebar calls, got ${#TITLEBAR_CALLS[@]}"
    fi
    assert_eq "${TITLEBAR_CALLS[1]}" "$expected_first" "$label first title"
    assert_eq "${TITLEBAR_CALLS[2]}" "$expected_second" "$label second title"
}

reset_mocks() {
    TITLEBAR_CALLS=()
    TMUX_CALLS=()
    STRIP_ANSI_CALLS=()
    TMUX_SESSION_LIST=()
    TMUX_SESSION_EXISTS=()
    TMUX_SESSION_TITLE=()
    TEST_FZF_SELECTION=""
    TEST_SHOW_OPTIONS_OUTPUT=""
    TEST_TMUX_ATTACH_EXITS_SESSION="0"
    unset CODEX_TMUX_EXTRA_ENV_FILE 2>/dev/null || true
    unset CLAUDE_TMUX_EXTRA_ENV_FILE 2>/dev/null || true
    unset COPILOT_TMUX_EXTRA_ENV_FILE 2>/dev/null || true
    unset CODEX_SSH_AUTH_SOCK_GLOB 2>/dev/null || true
    unset CLAUDE_SSH_AUTH_SOCK_GLOB 2>/dev/null || true
    unset COPILOT_SSH_AUTH_SOCK_GLOB 2>/dev/null || true
    rm -f -- "$TEST_TMUX_EXTRA_ENV_FILE" 2>/dev/null || true
    unset TMUX 2>/dev/null || true
    unset SSH_AUTH_SOCK 2>/dev/null || true
}

date() {
    case "${1:-}" in
        '+%Y.%m.%d.%H.%M.%S') print -r -- "$TEST_SESSION_STAMP" ;;
        '+%Y-%m-%d %H:%M:%S %Z') print -r -- "$TEST_HEADER_STAMP" ;;
        *) command date "$@" ;;
    esac
}

sleep() {
    :
}

fzf() {
    cat >/dev/null || true
    print -r -- "$TEST_FZF_SELECTION"
}

make_dead_socket() {
    local sock_path="$1"

    command python3 - "$sock_path" <<'PY'
import socket
import sys

sock = socket.socket(socket.AF_UNIX)
sock.bind(sys.argv[1])
PY
}

tmux() {
    local cmd=""
    local target=""
    local option=""
    local value=""
    local session=""

    TMUX_CALLS+=("${(j: :)@}")

    while (( $# > 0 )); do
        case "$1" in
            -L|-f) shift 2 ;;
            *) cmd="$1"; shift; break ;;
        esac
    done

    case "$cmd" in
        new-session)
            while (( $# > 0 )); do
                case "$1" in
                    -s) session="$2"; shift 2 ;;
                    -c) shift 2 ;;
                    -d) shift ;;
                    *) shift ;;
                esac
            done
            TMUX_SESSION_EXISTS[$session]=1
            return 0
            ;;
        has-session)
            while (( $# > 0 )); do
                case "$1" in
                    -t) target="$2"; shift 2 ;;
                    *) shift ;;
                esac
            done
            target="${target%:}"
            [[ -n "${TMUX_SESSION_EXISTS[$target]:-}" ]]
            return
            ;;
        set-option|set)
            while (( $# > 0 )); do
                case "$1" in
                    -t) target="$2"; shift 2 ;;
                    -g|-q|-w|-p|-s|-u|-o|-a|-F) shift ;;
                    *)
                        option="$1"
                        shift
                        value="${1:-}"
                        [[ $# -gt 0 ]] && shift
                        break
                        ;;
                esac
            done
            target="${target%:}"
            if [[ "$option" == "@titlebar-title" ]]; then
                TMUX_SESSION_TITLE[$target]="$value"
            fi
            return 0
            ;;
        show-options|show-option|show)
            while (( $# > 0 )); do
                case "$1" in
                    -t) target="$2"; shift 2 ;;
                    -v|-q|-g|-w|-p|-s) shift ;;
                    *)
                        option="$1"
                        shift
                        break
                        ;;
                esac
            done
            if [[ "$option" == "@titlebar-title" && -n "$TEST_SHOW_OPTIONS_OUTPUT" ]]; then
                print -r -- "$TEST_SHOW_OPTIONS_OUTPUT"
                return 0
            fi
            return 1
            ;;
        list-sessions|ls)
            if (( ${#TMUX_SESSION_LIST[@]} )); then
                printf '%s\n' "${TMUX_SESSION_LIST[@]}"
            fi
            return 0
            ;;
        attach|attach-session|switch-client)
            while (( $# > 0 )); do
                case "$1" in
                    -t) target="$2"; shift 2 ;;
                    *) shift ;;
                esac
            done
            if [[ "$TEST_TMUX_ATTACH_EXITS_SESSION" == "1" ]]; then
                target="${target%:}"
                unset "TMUX_SESSION_EXISTS[$target]"
            fi
            return 0
            ;;
        pipe-pane)
            while (( $# > 0 )); do
                case "$1" in
                    -t) target="$2"; shift 2 ;;
                    -o) shift ;;
                    *)
                        if [[ "$1" == *'cat >> "'* ]]; then
                            local log_path="${1#*cat >> \"}"
                            log_path="${log_path%\"*}"
                            mkdir -p -- "${log_path%/*}"
                            : > "$log_path"
                        fi
                        shift
                        ;;
                esac
            done
            return 0
            ;;
        unbind)
            return 0
            ;;
        *)
            return 0
            ;;
    esac
}

source "$PWD/codex.zsh"
source "$PWD/claude.zsh"
source "$PWD/copilot.zsh"

_set_titlebar() {
    TITLEBAR_CALLS+=("$*")
}

_codex_header() {
    print -r -- "codex header"
}

_claude_header() {
    print -r -- "claude header"
}

_copilot_header() {
    print -r -- "copilot header"
}

codex_strip_ansi() {
    STRIP_ANSI_CALLS+=("codex:$1:$2:$3")
}

claude_strip_ansi() {
    STRIP_ANSI_CALLS+=("claude:$1:$2:$3")
}

copilot_strip_ansi() {
    STRIP_ANSI_CALLS+=("copilot:$1:$2:$3")
}

_codex_prompt_session_name() {
    print -r -- "codex-tools"
}

_claude_prompt_session_name() {
    print -r -- "claude-tools"
}

_copilot_prompt_session_name() {
    print -r -- "copilot-tools"
}

test_helper_titles() {
    assert_eq "$(_codex_session_title "codex-tools")" "spark:codex-tools" "codex session title helper"
    assert_eq "$(_codex_default_title)" "trent@spark" "codex default title helper"
    assert_eq "$(_claude_session_title "claude-tools")" "spark:claude-tools" "claude session title helper"
    assert_eq "$(_claude_default_title)" "trent@spark" "claude default title helper"
    assert_eq "$(_copilot_session_title "copilot-tools")" "spark:copilot-tools" "copilot session title helper"
    assert_eq "$(_copilot_default_title)" "trent@spark" "copilot default title helper"
}

test_tmux_update_environment_local_file() {
    local expected="COLORTERM DISPLAY SSH_AUTH_SOCK SSH_AGENT_PID SSH_CLIENT SSH_CONNECTION SSH_TTY TERM_PROGRAM TERM_PROGRAM_VERSION XAUTHORITY WAYLAND_DISPLAY DISTCC_HOSTS MAX_JOBS OPENAI_API_KEY"

    reset_mocks
    mkdir -p -- "$PWD/.tmp"
    cat > "$TEST_TMUX_EXTRA_ENV_FILE" <<'EOF'
# carry interactive distcc state
DISTCC_HOSTS
MAX_JOBS

OPENAI_API_KEY  # allow explicit override
INVALID-NAME
SSH_AUTH_SOCK
EOF
    export CODEX_TMUX_EXTRA_ENV_FILE="$TEST_TMUX_EXTRA_ENV_FILE"
    export CLAUDE_TMUX_EXTRA_ENV_FILE="$TEST_TMUX_EXTRA_ENV_FILE"
    export COPILOT_TMUX_EXTRA_ENV_FILE="$TEST_TMUX_EXTRA_ENV_FILE"

    assert_eq "$(_codex_tmux_update_environment)" "$expected" "codex tmux update-environment local file"
    assert_eq "$(_claude_tmux_update_environment)" "$expected" "claude tmux update-environment local file"
    assert_eq "$(_copilot_tmux_update_environment)" "$expected" "copilot tmux update-environment local file"
}

test_codex_tmux_sync_environment_refreshes_display_vars() {
    local tmux_calls=""
    local xauth="$PWD/.tmp/test.Xauthority"

    reset_mocks
    mkdir -p -- "$PWD/.tmp"
    : > "$xauth"
    export DISPLAY=":1"
    export XAUTHORITY="$xauth"

    _codex_tmux_sync_environment "codex-existing"

    tmux_calls="${(F)TMUX_CALLS}"
    assert_contains "$tmux_calls" "set-environment -g DISPLAY :1" "codex sync refreshes global DISPLAY"
    assert_contains "$tmux_calls" "set-environment -t codex-existing DISPLAY :1" "codex sync refreshes session DISPLAY"
    assert_contains "$tmux_calls" "set-environment -g XAUTHORITY $xauth" "codex sync refreshes global XAUTHORITY"
    assert_contains "$tmux_calls" "set-environment -t codex-existing XAUTHORITY $xauth" "codex sync refreshes session XAUTHORITY"
}

test_codex_tmux_sync_environment_refreshes_forwarded_display() {
    local tmux_calls=""

    reset_mocks
    export DISPLAY="localhost:10.0"

    _codex_tmux_sync_environment "codex-existing"

    tmux_calls="${(F)TMUX_CALLS}"
    assert_contains "$tmux_calls" "set-environment -g DISPLAY localhost:10.0" "codex sync refreshes forwarded global DISPLAY"
    assert_contains "$tmux_calls" "set-environment -t codex-existing DISPLAY localhost:10.0" "codex sync refreshes forwarded session DISPLAY"
}

test_tmux_sync_environment_skips_dead_ssh_agent_socket() {
    local tmux_calls=""
    local sock="$PWD/.tmp/dead-agent.sock"

    reset_mocks
    mkdir -p -- "$PWD/.tmp"
    rm -f -- "$sock"
    make_dead_socket "$sock"
    export SSH_AUTH_SOCK="$sock"

    _codex_tmux_sync_environment "codex-existing"
    _claude_tmux_sync_environment "claude-existing"
    _copilot_tmux_sync_environment "copilot-existing"

    tmux_calls="${(F)TMUX_CALLS}"
    assert_not_contains \
        "$tmux_calls" \
        "set-environment -g SSH_AUTH_SOCK $sock" \
        "tmux sync skips dead global SSH_AUTH_SOCK"
    assert_not_contains \
        "$tmux_calls" \
        "set-environment -t codex-existing SSH_AUTH_SOCK $sock" \
        "codex sync skips dead session SSH_AUTH_SOCK"
    assert_not_contains \
        "$tmux_calls" \
        "set-environment -t claude-existing SSH_AUTH_SOCK $sock" \
        "claude sync skips dead session SSH_AUTH_SOCK"
    assert_not_contains \
        "$tmux_calls" \
        "set-environment -t copilot-existing SSH_AUTH_SOCK $sock" \
        "copilot sync skips dead session SSH_AUTH_SOCK"
}

test_tmux_sync_environment_recovers_live_ssh_agent_socket() {
    local tmux_calls=""
    local old_path="$PATH"
    local bin_dir="$PWD/.tmp/mock-bin"
    local dead_sock="$PWD/.tmp/dead-agent.sock"
    local good_sock="$PWD/.tmp/good-agent.sock"

    reset_mocks
    mkdir -p -- "$bin_dir" "$PWD/.tmp"
    rm -f -- "$dead_sock" "$good_sock"
    make_dead_socket "$dead_sock"
    make_dead_socket "$good_sock"
    cat >"$bin_dir/ssh-add" <<'EOF'
#!/bin/sh
case "${SSH_AUTH_SOCK:-}" in
  *good-agent.sock) exit 0 ;;
  *) exit 2 ;;
esac
EOF
    chmod +x -- "$bin_dir/ssh-add"

    export PATH="$bin_dir:$PATH"
    export SSH_AUTH_SOCK="$dead_sock"
    export CODEX_SSH_AUTH_SOCK_GLOB="$PWD/.tmp/*-agent.sock"
    export CLAUDE_SSH_AUTH_SOCK_GLOB="$PWD/.tmp/*-agent.sock"
    export COPILOT_SSH_AUTH_SOCK_GLOB="$PWD/.tmp/*-agent.sock"

    _codex_tmux_sync_environment "codex-existing"
    _claude_tmux_sync_environment "claude-existing"
    _copilot_tmux_sync_environment "copilot-existing"

    PATH="$old_path"
    tmux_calls="${(F)TMUX_CALLS}"
    assert_contains "$tmux_calls" "set-environment -g SSH_AUTH_SOCK $good_sock" "tmux sync recovers live global SSH_AUTH_SOCK"
    assert_contains "$tmux_calls" "set-environment -t codex-existing SSH_AUTH_SOCK $good_sock" "codex sync recovers live session SSH_AUTH_SOCK"
    assert_contains "$tmux_calls" "set-environment -t claude-existing SSH_AUTH_SOCK $good_sock" "claude sync recovers live session SSH_AUTH_SOCK"
    assert_contains "$tmux_calls" "set-environment -t copilot-existing SSH_AUTH_SOCK $good_sock" "copilot sync recovers live session SSH_AUTH_SOCK"
    assert_not_contains "$tmux_calls" "set-environment -g SSH_AUTH_SOCK $dead_sock" "tmux sync does not propagate stale SSH_AUTH_SOCK"
}

test_codex_tmux_persists_and_resets_title() {
    local session="codex-codex-tools-2026-03-22-12-34-56"
    local tmux_calls=""

    reset_mocks
    codex_tmux >/dev/null

    assert_eq "${TMUX_SESSION_TITLE[$session]}" "spark:codex-tools" "codex tmux stored title"
    assert_title_calls "spark:codex-tools" "trent@spark" "codex tmux title sequence"
    tmux_calls="${(F)TMUX_CALLS}"
    assert_contains "$tmux_calls" "set-option -g update-environment COLORTERM DISPLAY SSH_AUTH_SOCK SSH_AGENT_PID SSH_CLIENT SSH_CONNECTION SSH_TTY TERM_PROGRAM TERM_PROGRAM_VERSION XAUTHORITY WAYLAND_DISPLAY" "codex tmux refreshes SSH agent env"
    assert_not_contains "$tmux_calls" "pipe-pane -o -t ${session}:" "codex tmux skips logging by default"
    assert_eq "${#STRIP_ANSI_CALLS[@]}" "0" "codex tmux skips post-processing by default"
}

test_codex_attach_restores_and_resets_title() {
    local tmux_calls=""

    reset_mocks
    TMUX_SESSION_LIST=("codex-existing")
    TMUX_SESSION_EXISTS["codex-existing"]=1
    TEST_FZF_SELECTION="codex-existing"
    TEST_SHOW_OPTIONS_OUTPUT="spark:codex-tools"

    codex_attach >/dev/null

    assert_title_calls "spark:codex-tools" "trent@spark" "codex attach title sequence"
    tmux_calls="${(F)TMUX_CALLS}"
    assert_contains "$tmux_calls" "set-option -g update-environment COLORTERM DISPLAY SSH_AUTH_SOCK SSH_AGENT_PID SSH_CLIENT SSH_CONNECTION SSH_TTY TERM_PROGRAM TERM_PROGRAM_VERSION XAUTHORITY WAYLAND_DISPLAY" "codex attach refreshes SSH agent env"
}

test_codex_attach_switches_client_inside_tmux() {
    local tmux_calls=""
    local TMUX

    reset_mocks
    TMUX="/tmp/tmux-$(id -u)/codex,1234,0"
    TMUX_SESSION_LIST=("codex-existing")
    TMUX_SESSION_EXISTS["codex-existing"]=1
    TEST_FZF_SELECTION="codex-existing"
    TEST_SHOW_OPTIONS_OUTPUT="spark:codex-tools"

    codex_attach >/dev/null

    tmux_calls="${(F)TMUX_CALLS}"
    assert_contains "$tmux_calls" "switch-client -t codex-existing" "codex attach switches existing tmux client"
    assert_not_contains "$tmux_calls" "attach-session -t codex-existing" "codex attach avoids nested attach inside tmux"
}

test_claude_tmux_persists_and_resets_title() {
    local session="claude-claude-tools-2026-03-22-12-34-56"
    local tmux_calls=""

    reset_mocks
    claude_tmux >/dev/null

    assert_eq "${TMUX_SESSION_TITLE[$session]}" "spark:claude-tools" "claude tmux stored title"
    assert_title_calls "spark:claude-tools" "trent@spark" "claude tmux title sequence"
    tmux_calls="${(F)TMUX_CALLS}"
    assert_contains "$tmux_calls" "set-option -g update-environment COLORTERM DISPLAY SSH_AUTH_SOCK SSH_AGENT_PID SSH_CLIENT SSH_CONNECTION SSH_TTY TERM_PROGRAM TERM_PROGRAM_VERSION XAUTHORITY WAYLAND_DISPLAY" "claude tmux refreshes SSH agent env"
    assert_not_contains "$tmux_calls" "pipe-pane -o -t ${session}:" "claude tmux skips logging by default"
    assert_eq "${#STRIP_ANSI_CALLS[@]}" "0" "claude tmux skips post-processing by default"
}

test_claude_attach_restores_and_resets_title() {
    local tmux_calls=""

    reset_mocks
    TMUX_SESSION_LIST=("claude-existing")
    TMUX_SESSION_EXISTS["claude-existing"]=1
    TEST_FZF_SELECTION="claude-existing"
    TEST_SHOW_OPTIONS_OUTPUT="spark:claude-tools"

    claude_attach >/dev/null

    assert_title_calls "spark:claude-tools" "trent@spark" "claude attach title sequence"
    tmux_calls="${(F)TMUX_CALLS}"
    assert_contains "$tmux_calls" "set-option -g update-environment COLORTERM DISPLAY SSH_AUTH_SOCK SSH_AGENT_PID SSH_CLIENT SSH_CONNECTION SSH_TTY TERM_PROGRAM TERM_PROGRAM_VERSION XAUTHORITY WAYLAND_DISPLAY" "claude attach refreshes SSH agent env"
}

test_copilot_tmux_persists_and_resets_title() {
    local session="copilot-copilot-tools-2026-03-22-12-34-56"
    local tmux_calls=""

    reset_mocks
    copilot_tmux >/dev/null

    assert_eq "${TMUX_SESSION_TITLE[$session]}" "spark:copilot-tools" "copilot tmux stored title"
    assert_title_calls "spark:copilot-tools" "trent@spark" "copilot tmux title sequence"
    tmux_calls="${(F)TMUX_CALLS}"
    assert_contains "$tmux_calls" "set-option -g update-environment COLORTERM DISPLAY SSH_AUTH_SOCK SSH_AGENT_PID SSH_CLIENT SSH_CONNECTION SSH_TTY TERM_PROGRAM TERM_PROGRAM_VERSION XAUTHORITY WAYLAND_DISPLAY" "copilot tmux refreshes SSH agent env"
    assert_not_contains "$tmux_calls" "pipe-pane -o -t ${session}:" "copilot tmux skips logging by default"
    assert_eq "${#STRIP_ANSI_CALLS[@]}" "0" "copilot tmux skips post-processing by default"
}

test_copilot_attach_restores_and_resets_title() {
    local tmux_calls=""

    reset_mocks
    TMUX_SESSION_LIST=("copilot-existing")
    TMUX_SESSION_EXISTS["copilot-existing"]=1
    TEST_FZF_SELECTION="copilot-existing"
    TEST_SHOW_OPTIONS_OUTPUT="spark:copilot-tools"

    copilot_attach >/dev/null

    assert_title_calls "spark:copilot-tools" "trent@spark" "copilot attach title sequence"
    tmux_calls="${(F)TMUX_CALLS}"
    assert_contains "$tmux_calls" "set-option -g update-environment COLORTERM DISPLAY SSH_AUTH_SOCK SSH_AGENT_PID SSH_CLIENT SSH_CONNECTION SSH_TTY TERM_PROGRAM TERM_PROGRAM_VERSION XAUTHORITY WAYLAND_DISPLAY" "copilot attach refreshes SSH agent env"
}

test_aliases_are_wired() {
    assert_eq "${aliases[codexd]}" "codex --dangerously-bypass-approvals-and-sandbox" "codexd alias"
    assert_eq "${aliases[clauded]}" "claude --dangerously-skip-permissions" "clauded alias"
    assert_eq "${aliases[copilotd]}" "copilot --allow-all" "copilotd alias"
    assert_eq "${aliases[copilotfa]}" "copilot --autopilot --allow-all" "copilotfa alias"
    assert_eq "${aliases[copilotls]}" "copilot_ls" "copilotls alias"
}

test_codex_tmux_log_flag_enables_logging() {
    local session="codex-codex-tools-2026-03-22-12-34-56"
    local tmux_calls=""

    reset_mocks
    TEST_TMUX_ATTACH_EXITS_SESSION="1"

    codex_tmux --log >/dev/null

    tmux_calls="${(F)TMUX_CALLS}"
    assert_contains "$tmux_calls" "pipe-pane -o -t ${session}: cat >> \"$PWD/.tmp/codex-logs/codex-tools-2026.03.22.12.34.56.log\"" "codex tmux log flag enables pane logging"
    assert_eq "${#STRIP_ANSI_CALLS[@]}" "1" "codex tmux log flag triggers post-processing"
    assert_contains "${STRIP_ANSI_CALLS[1]}" "codex:$PWD/.tmp/codex-logs/codex-tools-2026.03.22.12.34.56.log::codex header" "codex tmux log flag passes log path and header"
}

test_claude_tmux_log_flag_enables_logging() {
    local session="claude-claude-tools-2026-03-22-12-34-56"
    local tmux_calls=""

    reset_mocks
    TEST_TMUX_ATTACH_EXITS_SESSION="1"

    claude_tmux --log >/dev/null

    tmux_calls="${(F)TMUX_CALLS}"
    assert_contains "$tmux_calls" "pipe-pane -o -t ${session}: cat >> \"$PWD/.tmp/claude-logs/claude-tools-2026.03.22.12.34.56.log\"" "claude tmux log flag enables pane logging"
    assert_eq "${#STRIP_ANSI_CALLS[@]}" "1" "claude tmux log flag triggers post-processing"
    assert_contains "${STRIP_ANSI_CALLS[1]}" "claude:$PWD/.tmp/claude-logs/claude-tools-2026.03.22.12.34.56.log::claude header" "claude tmux log flag passes log path and header"
}

test_copilot_tmux_log_flag_enables_logging() {
    local session="copilot-copilot-tools-2026-03-22-12-34-56"
    local tmux_calls=""

    reset_mocks
    TEST_TMUX_ATTACH_EXITS_SESSION="1"

    copilot_tmux --log >/dev/null

    tmux_calls="${(F)TMUX_CALLS}"
    assert_contains "$tmux_calls" "pipe-pane -o -t ${session}: cat >> \"$PWD/.tmp/copilot-logs/copilot-tools-2026.03.22.12.34.56.log\"" "copilot tmux log flag enables pane logging"
    assert_eq "${#STRIP_ANSI_CALLS[@]}" "1" "copilot tmux log flag triggers post-processing"
    assert_contains "${STRIP_ANSI_CALLS[1]}" "copilot:$PWD/.tmp/copilot-logs/copilot-tools-2026.03.22.12.34.56.log::copilot header" "copilot tmux log flag passes log path and header"
}

test_tmux_log_flag_rejects_unknown_option() {
    local output=""

    reset_mocks
    output="$(codex_tmux --bogus 2>&1)" && fail "codex tmux unknown option should fail"
    assert_contains "$output" "Usage: codex_tmux [--log]" "codex tmux usage message"

    output="$(claude_tmux --bogus 2>&1)" && fail "claude tmux unknown option should fail"
    assert_contains "$output" "Usage: claude_tmux [--log]" "claude tmux usage message"

    output="$(copilot_tmux --bogus 2>&1)" && fail "copilot tmux unknown option should fail"
    assert_contains "$output" "Usage: copilot_tmux [--log]" "copilot tmux usage message"
}

test_tmux_conf_uses_home_for_clipboard_helper() {
    local conf_contents
    local expected='$HOME/src/codex-tools/tmux-copy-clipboard.sh'

    conf_contents="$(<"$PWD/codex.tmux.conf")"

    assert_contains "$conf_contents" "$expected" "tmux conf clipboard helper path"
    assert_not_contains "$conf_contents" "/home/" "tmux conf hardcoded clipboard helper path"
}

test_tmux_conf_preserves_ssh_agent_env() {
    local conf_contents

    conf_contents="$(<"$PWD/codex.tmux.conf")"

    assert_contains "$conf_contents" 'set -g update-environment "COLORTERM DISPLAY SSH_AUTH_SOCK SSH_AGENT_PID SSH_CLIENT SSH_CONNECTION SSH_TTY TERM_PROGRAM TERM_PROGRAM_VERSION XAUTHORITY WAYLAND_DISPLAY"' "tmux conf SSH agent env list"
}

test_tmux_conf_enables_truecolor() {
    local conf_contents

    conf_contents="$(<"$PWD/codex.tmux.conf")"

    assert_contains "$conf_contents" 'set -g default-terminal "tmux-256color"' "tmux conf default terminal"
    assert_contains "$conf_contents" 'set -g terminal-features "xterm*:clipboard:ccolour:cstyle:focus:title:RGB,screen*:title:RGB,rxvt*:ignorefkeys,*:RGB"' "tmux conf RGB terminal features"
}

test_tmux_conf_forces_mosh_clipboard_selector() {
    local conf_contents

    conf_contents="$(<"$PWD/codex.tmux.conf")"

    assert_contains "$conf_contents" 'set -g terminal-overrides "xterm*:Ms=\\E]52;c;%p2%s\\007"' "tmux conf mosh OSC 52 clipboard selector"
}

test_clipboard_helper_prefers_clip_exe_on_wsl() {
    local bin_dir out copied

    bin_dir="$PWD/.tmp/mock-bin"
    out="$PWD/.tmp/clip.out"
    rm -rf -- "$bin_dir"
    mkdir -p -- "$bin_dir"

    cat >"$bin_dir/clip.exe" <<'EOF'
#!/bin/sh
cat >"$CLIP_MOCK_OUT"
EOF
    cat >"$bin_dir/wl-copy" <<'EOF'
#!/bin/sh
printf '%s\n' "wl-copy should not run" >"$CLIP_MOCK_OUT"
exit 99
EOF
    cat >"$bin_dir/xclip" <<'EOF'
#!/bin/sh
printf '%s\n' "xclip should not run" >"$CLIP_MOCK_OUT"
exit 99
EOF
    cat >"$bin_dir/uname" <<'EOF'
#!/bin/sh
printf '%s\n' Linux
EOF
    chmod +x "$bin_dir/clip.exe" "$bin_dir/wl-copy" "$bin_dir/xclip" "$bin_dir/uname"

    printf 'wsl-copy' | env WSL_DISTRO_NAME=Ubuntu CLIP_MOCK_OUT="$out" PATH="$bin_dir:/usr/bin:/bin" "$PWD/tmux-copy-clipboard.sh"

    copied="$(<"$out")"
    assert_eq "$copied" "wsl-copy" "clipboard helper prefers clip.exe on WSL"
}

test_clipboard_helper_prefers_active_forwarded_display() {
    local bin_dir out copied

    bin_dir="$PWD/.tmp/mock-bin"
    out="$PWD/.tmp/xclip.out"
    rm -rf -- "$bin_dir"
    mkdir -p -- "$bin_dir"

    cat >"$bin_dir/xclip" <<'EOF'
#!/bin/sh
printf 'DISPLAY=%s\n' "${DISPLAY:-}" >"$CLIP_MOCK_OUT"
cat >>"$CLIP_MOCK_OUT"
EOF
    cat >"$bin_dir/uname" <<'EOF'
#!/bin/sh
printf '%s\n' Linux
EOF
    chmod +x "$bin_dir/xclip" "$bin_dir/uname"

    printf 'forwarded-copy' | env -u WAYLAND_DISPLAY -u WSL_DISTRO_NAME -u WSL_INTEROP CLIP_MOCK_OUT="$out" DISPLAY=localhost:20.0 PATH="$bin_dir:/usr/bin:/bin" "$PWD/tmux-copy-clipboard.sh"

    copied="$(<"$out")"
    assert_eq "$copied" $'DISPLAY=localhost:20.0\nforwarded-copy' "clipboard helper prefers active SSH-forwarded DISPLAY"
}

test_clipboard_helper_retries_forwarded_display_with_home_xauthority() {
    local bin_dir out copied home_dir stale_xauth

    bin_dir="$PWD/.tmp/mock-bin"
    home_dir="$PWD/.tmp/mock-home"
    stale_xauth="/run/user/1000/gdm/Xauthority"
    out="$PWD/.tmp/xclip-xauthority.out"
    rm -rf -- "$bin_dir" "$home_dir"
    mkdir -p -- "$bin_dir" "$home_dir"
    : > "$home_dir/.Xauthority"

    cat >"$bin_dir/xclip" <<'EOF'
#!/bin/sh
if [ "${XAUTHORITY:-}" != "$HOME/.Xauthority" ]; then
  exit 1
fi
printf 'DISPLAY=%s XAUTHORITY=%s\n' "${DISPLAY:-}" "${XAUTHORITY:-}" >"$CLIP_MOCK_OUT"
cat >>"$CLIP_MOCK_OUT"
EOF
    cat >"$bin_dir/uname" <<'EOF'
#!/bin/sh
printf '%s\n' Linux
EOF
    chmod +x "$bin_dir/xclip" "$bin_dir/uname"

    printf 'forwarded-xauth-copy' | env -u WAYLAND_DISPLAY -u WSL_DISTRO_NAME -u WSL_INTEROP CLIP_MOCK_OUT="$out" DISPLAY=localhost:20.0 XAUTHORITY="$stale_xauth" HOME="$home_dir" PATH="$bin_dir:/usr/bin:/bin" "$PWD/tmux-copy-clipboard.sh"

    copied="$(<"$out")"
    assert_eq "$copied" "DISPLAY=localhost:20.0 XAUTHORITY=$home_dir/.Xauthority"$'\nforwarded-xauth-copy' "clipboard helper retries forwarded DISPLAY with home Xauthority"
}

test_helper_titles
test_tmux_update_environment_local_file
test_codex_tmux_sync_environment_refreshes_display_vars
test_codex_tmux_sync_environment_refreshes_forwarded_display
test_tmux_sync_environment_skips_dead_ssh_agent_socket
test_tmux_sync_environment_recovers_live_ssh_agent_socket
test_codex_tmux_persists_and_resets_title
test_codex_attach_restores_and_resets_title
test_codex_attach_switches_client_inside_tmux
test_claude_tmux_persists_and_resets_title
test_claude_attach_restores_and_resets_title
test_copilot_tmux_persists_and_resets_title
test_copilot_attach_restores_and_resets_title
test_codex_tmux_log_flag_enables_logging
test_claude_tmux_log_flag_enables_logging
test_copilot_tmux_log_flag_enables_logging
test_tmux_log_flag_rejects_unknown_option
test_tmux_conf_uses_home_for_clipboard_helper
test_tmux_conf_preserves_ssh_agent_env
test_tmux_conf_enables_truecolor
test_tmux_conf_forces_mosh_clipboard_selector
test_clipboard_helper_prefers_clip_exe_on_wsl
test_clipboard_helper_prefers_active_forwarded_display
test_clipboard_helper_retries_forwarded_display_with_home_xauthority
test_aliases_are_wired

print -r -- "ok"
