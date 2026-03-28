#!/usr/bin/env zsh

emulate -L zsh -o errexit -o nounset -o pipefail

export HOST="spark"
export USER="trent"
export CODEX_LOG_DIR="$PWD/.tmp/codex-logs"
export CLAUDE_LOG_DIR="$PWD/.tmp/claude-logs"

typeset -ga TITLEBAR_CALLS=()
typeset -ga TMUX_CALLS=()
typeset -ga TMUX_SESSION_LIST=()
typeset -gA TMUX_SESSION_EXISTS=()
typeset -gA TMUX_SESSION_TITLE=()
typeset -g TEST_TMUX_EXTRA_ENV_FILE="$PWD/.tmp/tmux-extra-env.local"
typeset -g TEST_FZF_SELECTION=""
typeset -g TEST_SHOW_OPTIONS_OUTPUT=""
typeset -g TEST_SESSION_STAMP="2026.03.22.12.34.56"
typeset -g TEST_HEADER_STAMP="2026-03-22 12:34:56 PDT"

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
    TMUX_SESSION_LIST=()
    TMUX_SESSION_EXISTS=()
    TMUX_SESSION_TITLE=()
    TEST_FZF_SELECTION=""
    TEST_SHOW_OPTIONS_OUTPUT=""
    unset CODEX_TMUX_EXTRA_ENV_FILE 2>/dev/null || true
    unset CLAUDE_TMUX_EXTRA_ENV_FILE 2>/dev/null || true
    rm -f -- "$TEST_TMUX_EXTRA_ENV_FILE" 2>/dev/null || true
    unset TMUX 2>/dev/null || true
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
        attach|attach-session|switch-client|pipe-pane|unbind)
            return 0
            ;;
        *)
            return 0
            ;;
    esac
}

source "$PWD/codex.zsh"
source "$PWD/claude.zsh"

_set_titlebar() {
    TITLEBAR_CALLS+=("$*")
}

_codex_header() {
    print -r -- "codex header"
}

_claude_header() {
    print -r -- "claude header"
}

_codex_prompt_session_name() {
    print -r -- "codex-tools"
}

_claude_prompt_session_name() {
    print -r -- "claude-tools"
}

test_helper_titles() {
    assert_eq "$(_codex_session_title "codex-tools")" "spark:codex-tools" "codex session title helper"
    assert_eq "$(_codex_default_title)" "trent@spark" "codex default title helper"
    assert_eq "$(_claude_session_title "claude-tools")" "spark:claude-tools" "claude session title helper"
    assert_eq "$(_claude_default_title)" "trent@spark" "claude default title helper"
}

test_tmux_update_environment_local_file() {
    local expected="DISPLAY SSH_AUTH_SOCK SSH_AGENT_PID SSH_CLIENT SSH_CONNECTION SSH_TTY XAUTHORITY WAYLAND_DISPLAY DISTCC_HOSTS MAX_JOBS OPENAI_API_KEY"

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

    assert_eq "$(_codex_tmux_update_environment)" "$expected" "codex tmux update-environment local file"
    assert_eq "$(_claude_tmux_update_environment)" "$expected" "claude tmux update-environment local file"
}

test_codex_tmux_persists_and_resets_title() {
    local session="codex-codex-tools-2026-03-22-12-34-56"
    local tmux_calls=""

    reset_mocks
    codex_tmux >/dev/null

    assert_eq "${TMUX_SESSION_TITLE[$session]}" "spark:codex-tools" "codex tmux stored title"
    assert_title_calls "spark:codex-tools" "trent@spark" "codex tmux title sequence"
    tmux_calls="${(F)TMUX_CALLS}"
    assert_contains "$tmux_calls" "set-option -g update-environment DISPLAY SSH_AUTH_SOCK SSH_AGENT_PID SSH_CLIENT SSH_CONNECTION SSH_TTY XAUTHORITY WAYLAND_DISPLAY" "codex tmux refreshes SSH agent env"
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
    assert_contains "$tmux_calls" "set-option -g update-environment DISPLAY SSH_AUTH_SOCK SSH_AGENT_PID SSH_CLIENT SSH_CONNECTION SSH_TTY XAUTHORITY WAYLAND_DISPLAY" "codex attach refreshes SSH agent env"
}

test_claude_tmux_persists_and_resets_title() {
    local session="claude-claude-tools-2026-03-22-12-34-56"
    local tmux_calls=""

    reset_mocks
    claude_tmux >/dev/null

    assert_eq "${TMUX_SESSION_TITLE[$session]}" "spark:claude-tools" "claude tmux stored title"
    assert_title_calls "spark:claude-tools" "trent@spark" "claude tmux title sequence"
    tmux_calls="${(F)TMUX_CALLS}"
    assert_contains "$tmux_calls" "set-option -g update-environment DISPLAY SSH_AUTH_SOCK SSH_AGENT_PID SSH_CLIENT SSH_CONNECTION SSH_TTY XAUTHORITY WAYLAND_DISPLAY" "claude tmux refreshes SSH agent env"
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
    assert_contains "$tmux_calls" "set-option -g update-environment DISPLAY SSH_AUTH_SOCK SSH_AGENT_PID SSH_CLIENT SSH_CONNECTION SSH_TTY XAUTHORITY WAYLAND_DISPLAY" "claude attach refreshes SSH agent env"
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

    assert_contains "$conf_contents" 'set -g update-environment "DISPLAY SSH_AUTH_SOCK SSH_AGENT_PID SSH_CLIENT SSH_CONNECTION SSH_TTY XAUTHORITY WAYLAND_DISPLAY"' "tmux conf SSH agent env list"
}

test_helper_titles
test_tmux_update_environment_local_file
test_codex_tmux_persists_and_resets_title
test_codex_attach_restores_and_resets_title
test_claude_tmux_persists_and_resets_title
test_claude_attach_restores_and_resets_title
test_tmux_conf_uses_home_for_clipboard_helper
test_tmux_conf_preserves_ssh_agent_env

print -r -- "ok"
