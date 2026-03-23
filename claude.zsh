_claude_host() {
    print -r -- "${HOST:-$(hostname 2>/dev/null)}"
}

_claude_user() {
    print -r -- "${USER:-$(whoami 2>/dev/null)}"
}

_claude_session_title() {
    local session_name="$1"
    local host="$(_claude_host)"

    host="${host:-unknown}"
    print -r -- "${host}:${session_name}"
}

_claude_default_title() {
    local host user

    host="$(_claude_host)"
    user="$(_claude_user)"
    host="${host:-unknown}"
    user="${user:-unknown}"
    print -r -- "${user}@${host}"
}

_claude_prompt_read() {
    local prompt="$1"
    local __var="$2"
    local tty=""
    if [[ -r /dev/tty && -w /dev/tty ]]; then
        tty="/dev/tty"
    fi
    if [[ -n "$tty" ]]; then
        print -n -- "$prompt" >"$tty"
        read -r "$__var" <"$tty"
    else
        print -n -- "$prompt"
        read -r "$__var"
    fi
}

_claude_sh_quote() {
    local s="$1"
    s=${s//\'/\'\\\'\'}
    print -r -- "'$s'"
}

_claude_log_dir() {
    local host
    host="${HOST:-$(hostname 2>/dev/null)}"
    echo "${CLAUDE_LOG_DIR:-$HOME/src/claude-logs/logs/${host:-unknown}}"
}

_claude_ensure_zstd() {
    if command -v zstd >/dev/null 2>&1; then
        return 0
    fi
    if command -v apt >/dev/null 2>&1; then
        print -u2 "claude: zstd not found; attempting install via apt"
        sudo apt install -y zstd >/dev/null
        return $?
    fi
    print -u2 "claude: zstd not found and apt unavailable"
    return 1
}

_claude_zstd_compress() {
    local file="$1"
    local -a level_args
    local level_spec="${CLAUDE_ZSTD_LEVEL:-}"

    if [[ -z "$file" || ! -f "$file" ]]; then
        return 0
    fi
    if [[ -n "$level_spec" ]]; then
        level_args=(${=level_spec})
    else
        level_args=(-19)
    fi
    if ! _claude_ensure_zstd; then
        print -u2 "claude: zstd unavailable; skipping compression for $file"
        return 0
    fi
    if ! zstd -q -T0 -k -f "${level_args[@]}" -- "$file"; then
        print -u2 "claude: zstd failed for $file"
        return 0
    fi
}

_claude_compress_artifacts() {
    local log_path="$1"
    local md_path="$2"
    if [[ -n "$log_path" && "$log_path" != "-" ]]; then
        _claude_zstd_compress "$log_path"
    fi
    if [[ -n "$md_path" && "$md_path" != "-" ]]; then
        _claude_zstd_compress "$md_path"
    fi
}

_claude_header() {
    local start_pwd="$1"
    local session_name="$2"
    local host os time user tty shell term lang uptime claude_version
    local term_hints tmux_flag ssh_flag
    local git_root git_branch git_state git_ahead git_behind sha ahead_behind
    local hints=()

    host="${HOST:-$(hostname 2>/dev/null)}"
    os="$(uname -srm 2>/dev/null)"
    time="$(date '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null)"
    user="${USER:-$(whoami 2>/dev/null)}"
    tty="$(tty 2>/dev/null)"
    shell="${SHELL:-$0}"
    term="${TERM:-}"
    lang="${LANG:-}"
    uptime="$(uptime -p 2>/dev/null)"

    if [[ -n "${TERM_PROGRAM:-}" ]]; then hints+=("TERM_PROGRAM=$TERM_PROGRAM"); fi
    if [[ -n "${WT_SESSION:-}" ]]; then hints+=("WT_SESSION=1"); fi
    if [[ -n "${VTE_VERSION:-}" ]]; then hints+=("VTE_VERSION=$VTE_VERSION"); fi
    if [[ -n "${VSCODE_PID:-}" ]]; then hints+=("VSCODE_PID=$VSCODE_PID"); fi
    if (( ${#hints[@]} )); then
        term_hints="${hints[*]}"
    fi

    tmux_flag="no"
    [[ -n "${TMUX:-}" ]] && tmux_flag="yes"

    ssh_flag="no"
    if [[ -n "${SSH_CONNECTION:-}" ]]; then
        ssh_flag="yes (${SSH_CONNECTION})"
    elif [[ -n "${SSH_TTY:-}" ]]; then
        ssh_flag="yes"
    fi

    if command -v claude >/dev/null 2>&1; then
        claude_version="$(claude --version 2>/dev/null | head -n 1)"
    fi

    if git -C "$start_pwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git_root="$(git -C "$start_pwd" rev-parse --show-toplevel 2>/dev/null)"
        git_branch="$(git -C "$start_pwd" symbolic-ref --quiet --short HEAD 2>/dev/null)"
        if [[ -z "$git_branch" ]]; then
            sha="$(git -C "$start_pwd" rev-parse --short HEAD 2>/dev/null)"
            git_branch="(detached: ${sha:-unknown})"
        fi
        if [[ -n "$(git -C "$start_pwd" status --porcelain 2>/dev/null)" ]]; then
            git_state="dirty"
        else
            git_state="clean"
        fi
        ahead_behind="$(git -C "$start_pwd" rev-list --left-right --count @{upstream}...HEAD 2>/dev/null)"
        if [[ -n "$ahead_behind" ]]; then
            git_behind="${ahead_behind%% *}"
            git_ahead="${ahead_behind##* }"
        fi
    fi

    print -r -- "# Claude session"
    if [[ -n "$session_name" ]]; then
        print -r -- "Session: $session_name"
    fi
    print -r -- "Started: ${time:-unknown}"
    print -r -- "User: ${user:-unknown}"
    print -r -- "Host: ${host:-unknown}"
    print -r -- "OS: ${os:-unknown}"
    if [[ -n "$uptime" ]]; then
        print -r -- "Uptime: $uptime"
    fi
    if [[ -n "$tty" ]]; then
        print -r -- "TTY: $tty"
    fi
    if [[ -n "$shell" ]]; then
        print -r -- "Shell: $shell"
    fi
    if [[ -n "$term" ]]; then
        print -r -- "TERM: $term"
    fi
    if [[ -n "$term_hints" ]]; then
        print -r -- "Terminal hints: $term_hints"
    fi
    if [[ -n "$lang" ]]; then
        print -r -- "Locale: $lang"
    fi
    print -r -- "tmux: $tmux_flag"
    print -r -- "SSH: $ssh_flag"
    print -r -- "PWD: $start_pwd"
    if [[ -n "$git_root" ]]; then
        print -r -- "Git root: $git_root"
        print -r -- "Git branch: $git_branch"
        print -r -- "Git state: $git_state"
        if [[ -n "$git_ahead" || -n "$git_behind" ]]; then
            print -r -- "Git upstream: ahead ${git_ahead:-0}, behind ${git_behind:-0}"
        fi
    fi
    if [[ -n "$claude_version" ]]; then
        print -r -- "Claude: $claude_version"
    fi
}

_claude_prompt_session_name() {
    local name
    while true; do
        local base="${PWD##*/}"
        local default=""
        if [[ -n "$base" ]]; then
            default="${base//[^a-zA-Z0-9-]/-}"
        fi
        if [[ -n "$default" ]]; then
            if ! _claude_prompt_read "Claude session name [a-zA-Z0-9- only] (default: $default): " name; then
                return 1
            fi
        else
            if ! _claude_prompt_read "Claude session name [a-zA-Z0-9- only]: " name; then
                return 1
            fi
        fi
        if [[ -z "$name" && -n "$default" ]]; then
            name="$default"
        fi
        if [[ -z "$name" ]]; then
            print -u2 "claude: session name required"
            return 1
        fi
        if [[ "$name" == *[^a-zA-Z0-9-]* ]]; then
            print -u2 "claude: session name must be letters, numbers, and hyphens only"
            continue
        fi
        print -r -- "$name"
        return 0
    done
}

_claude_prompt_args() {
    local answer extra
    reply=()

    if ! _claude_prompt_read "--dangerously-skip-permissions? (y/N/q/a/o) " answer; then
        return 1
    fi
    case "$answer" in
        [Qq]) return 2 ;;
        [Aa])
            if ! _claude_prompt_read "Enter additional args: --dangerously-skip-permissions " extra; then
                return 1
            fi
            reply=(--dangerously-skip-permissions ${(z)extra})
            ;;
        [Oo])
            if ! _claude_prompt_read "Enter args: " extra; then
                return 1
            fi
            reply=(${(z)extra})
            ;;
        [Yy])
            reply=(--dangerously-skip-permissions)
            ;;
        *)
            if ! _claude_prompt_read "--permission-mode auto? (y/N/q) " answer; then
                return 1
            fi
            case "$answer" in
                [Qq]) return 2 ;;
                [Yy]) reply=(--permission-mode auto) ;;
                *) reply=() ;;
            esac
            ;;
    esac

    return 0
}

claude_strip_ansi() {
    local in="$1"
    local out="${2:-${in%.log}.md}"
    local header="$3"
    local esc=$'\033'
    local bel=$'\a'
    local cleaner="${CLAUDE_LOG_CLEANER:-$HOME/src/codex-tools/codex_log_clean.py}"
    local python=""

    if [[ -z "$in" || ! -f "$in" ]]; then
        print -u2 "claude_strip_ansi: missing log file"
        return 1
    fi

    if command -v python3 >/dev/null 2>&1; then
        python="python3"
    elif command -v python >/dev/null 2>&1; then
        python="python"
    fi

    {
        if [[ -n "$header" ]]; then
            print -r -- "$header"
            print -r -- ""
        fi
        if [[ -n "$python" && -f "$cleaner" ]]; then
            "$python" "$cleaner" --input "$in"
        else
            sed -E "s/${esc}\\[[0-9;]*[mK]//g; s/${esc}\\]0;[^${bel}]*${bel}//g" "$in"
        fi
    } > "$out"
    print -r -- "Wrote $out"
    _claude_compress_artifacts "$in" "$out"
}

claude_clean() {
    local in="$1"
    local out="$2"
    if [[ -z "$in" ]]; then
        print -u2 "Usage: claude_clean <log> [out.md]"
        return 2
    fi
    if [[ -z "$out" ]]; then
        out="${in%.log}.md"
    fi
    claude_strip_ansi "$in" "$out"
}

claude_script() {
    local dir log start_pwd header session_name base session_title
    local -a claude_args
    dir="$(_claude_log_dir)"
    mkdir -p "$dir"
    session_name="$(_claude_prompt_session_name)" || return 1
    session_title="$(_claude_session_title "$session_name")"
    _set_titlebar "$session_title"
    _claude_prompt_args
    case $? in
        2)
            print -r -- "claude_script: cancelled"
            return 0
            ;;
        0) claude_args=("${reply[@]}") ;;
        *) return 1 ;;
    esac
    base="${session_name}-$(date +%Y.%m.%d.%H.%M.%S)"
    log="$dir/${base}.log"
    start_pwd="$PWD"
    header="$(_claude_header "$start_pwd" "$session_name")"
    print -r -- "Logging to $log"

    local cmd_str
    cmd_str="$(_claude_sh_quote claude)"
    if (( ${#claude_args[@]} )); then
        for a in "${claude_args[@]}"; do
            cmd_str+=" $(_claude_sh_quote "$a")"
        done
    fi
    if script --help 2>/dev/null | grep -q -- '-f'; then
        script -q -f -c "$cmd_str" "$log"
    else
        script -q -c "$cmd_str" "$log"
    fi

    claude_strip_ansi "$log" "" "$header"
}

claude_tmux() {
    local dir log base session start_pwd header session_name session_title default_title
    local -a cmd
    local shell_bin
    local tmux_conf tmux_socket
    local -a tmux_cmd
    local tmux_mouse inside_tmux attach_status

    if ! command -v tmux >/dev/null 2>&1; then
        print -u2 "claude_tmux: tmux not found"
        return 1
    fi

    dir="$(_claude_log_dir)"
    mkdir -p "$dir"
    session_name="$(_claude_prompt_session_name)" || return 1
    session_title="$(_claude_session_title "$session_name")"
    default_title="$(_claude_default_title)"
    inside_tmux="no"
    [[ -n "${TMUX:-}" ]] && inside_tmux="yes"
    _set_titlebar "$session_title"
    base="${session_name}-$(date +%Y.%m.%d.%H.%M.%S)"
    log="$dir/${base}.log"
    session="${CLAUDE_TMUX_SESSION:-claude}-${base//./-}"
    start_pwd="$PWD"
    header="$(_claude_header "$start_pwd" "$session_name")"
    print -r -- "Logging to $log"

    shell_bin="/bin/zsh"
    if [[ ! -x "$shell_bin" ]]; then
        shell_bin="${SHELL:-/bin/sh}"
    fi
    if [[ "$shell_bin" == */zsh ]]; then
        cmd=("$shell_bin" -il)
    else
        cmd=("$shell_bin" -l -i)
    fi

    tmux_conf="${CLAUDE_TMUX_CONF:-$HOME/src/codex-tools/codex.tmux.conf}"
    tmux_socket="${CLAUDE_TMUX_SOCKET:-claude}"
    tmux_mouse="${CLAUDE_TMUX_MOUSE:-scroll}"
    case "$tmux_mouse" in
        on|enable|enabled|true|yes|scroll) tmux_mouse="on" ;;
        off|disable|disabled|false|no) tmux_mouse="off" ;;
        ignore|none) tmux_mouse="ignore" ;;
        *) tmux_mouse="on" ;;
    esac
    tmux_cmd=(tmux)
    if [[ -n "$tmux_socket" ]]; then
        tmux_cmd+=(-L "$tmux_socket")
    fi
    if [[ -r "$tmux_conf" ]]; then
        tmux_cmd+=(-f "$tmux_conf")
    else
        print -u2 "claude_tmux: tmux conf not found; using default config: $tmux_conf"
    fi

    if ! "${tmux_cmd[@]}" new-session -d -s "$session" -c "$start_pwd" "${cmd[@]}"; then
        print -u2 "claude_tmux: failed to start tmux session"
        return 1
    fi
    sleep 0.2
    if ! "${tmux_cmd[@]}" has-session -t "$session" 2>/dev/null; then
        print -u2 "claude_tmux: session exited immediately; check shell startup output"
        return 1
    fi
    "${tmux_cmd[@]}" set-option -t "$session" status off
    if [[ "$tmux_mouse" == "ignore" ]]; then
        "${tmux_cmd[@]}" set-option -t "$session" mouse on
        "${tmux_cmd[@]}" unbind -n WheelUpPane
        "${tmux_cmd[@]}" unbind -n WheelDownPane
    else
        "${tmux_cmd[@]}" set-option -t "$session" mouse "$tmux_mouse"
    fi
    "${tmux_cmd[@]}" set-option -t "$session" allow-rename off
    "${tmux_cmd[@]}" set-option -t "$session" @titlebar-title "$session_title"
    "${tmux_cmd[@]}" pipe-pane -o -t "${session}:" "cat >> \"$log\""
    attach_status=0
    if [[ "$inside_tmux" == "yes" ]]; then
        "${tmux_cmd[@]}" switch-client -t "$session" || "${tmux_cmd[@]}" attach -t "$session"
    else
        "${tmux_cmd[@]}" attach -t "$session"
        attach_status=$?
        _set_titlebar "$default_title"
    fi
    if [[ "$inside_tmux" == "yes" ]]; then
        attach_status=$?
    fi
    if (( attach_status != 0 )); then
        return "$attach_status"
    fi

    # Detach returns from attach, but the session can still be alive.
    if "${tmux_cmd[@]}" has-session -t "$session" 2>/dev/null; then
        print -r -- "Detached; tmux session still running: $session"
        return 0
    fi

    if [[ -f "$log" ]]; then
        claude_strip_ansi "$log" "" "$header"
    fi
}

claude_attach() {
    local session session_title default_title
    local tmux_socket
    local -a tmux_cmd
    local attach_status

    if ! command -v tmux >/dev/null 2>&1; then
        print -u2 "claude_attach: tmux not found"
        return 1
    fi
    if ! command -v fzf >/dev/null 2>&1; then
        print -u2 "claude_attach: fzf not found"
        return 1
    fi

    tmux_socket="${CLAUDE_TMUX_SOCKET:-claude}"
    tmux_cmd=(tmux)
    if [[ -n "$tmux_socket" ]]; then
        tmux_cmd+=(-L "$tmux_socket")
    fi

    session="$("${tmux_cmd[@]}" list-sessions -F '#S' 2>/dev/null | fzf)"
    if [[ -z "$session" ]]; then
        print -u2 "claude_attach: no session selected"
        return 1
    fi

    session_title="$("${tmux_cmd[@]}" show-options -v -t "$session" @titlebar-title 2>/dev/null)"
    if [[ -z "$session_title" ]]; then
        session_title="$session"
    fi
    default_title="$(_claude_default_title)"
    _set_titlebar "$session_title"
    "${tmux_cmd[@]}" attach-session -t "$session"
    attach_status=$?
    _set_titlebar "$default_title"
    return "$attach_status"
}

claude_ls() {
    local tmux_socket
    local -a tmux_cmd
    local sessions session_name session_windows session_attached attached_label

    if ! command -v tmux >/dev/null 2>&1; then
        print -u2 "claude_ls: tmux not found"
        return 1
    fi

    tmux_socket="${CLAUDE_TMUX_SOCKET:-claude}"
    tmux_cmd=(tmux)
    if [[ -n "$tmux_socket" ]]; then
        tmux_cmd+=(-L "$tmux_socket")
    fi

    sessions="$("${tmux_cmd[@]}" list-sessions -F '#S	#{session_windows}	#{session_attached}' 2>/dev/null)"
    if [[ -z "$sessions" ]]; then
        print -r -- "No tmux sessions on socket: ${tmux_socket:-default}"
        return 0
    fi

    printf '%-56s %-8s %-10s\n' "SESSION" "WINDOWS" "ATTACHED"
    while IFS=$'\t' read -r session_name session_windows session_attached; do
        attached_label="no"
        if [[ "$session_attached" != "0" ]]; then
            attached_label="yes($session_attached)"
        fi
        printf '%-56s %-8s %-10s\n' "$session_name" "$session_windows" "$attached_label"
    done <<< "$sessions"
}

alias clauded='claude --dangerously-skip-permissions'
alias claudefa='claude --permission-mode auto'
alias claudels='claude_ls'

# Ensure log directory exists at source time.
mkdir -p "$(_claude_log_dir)"
