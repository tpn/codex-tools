_set_titlebar() {
    echo -ne "\033]0;$*\007"
}

_codex_prompt_read() {
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

_codex_sh_quote() {
    local s="$1"
    s=${s//\'/\'\\\'\'}
    print -r -- "'$s'"
}

_codex_log_dir() {
    local host
    host="${HOST:-$(hostname 2>/dev/null)}"
    echo "${CODEX_LOG_DIR:-$HOME/src/codex-logs/logs/${host:-unknown}}"
}

_codex_ensure_zstd() {
    if command -v zstd >/dev/null 2>&1; then
        return 0
    fi
    if command -v apt >/dev/null 2>&1; then
        print -u2 "codex: zstd not found; attempting install via apt"
        sudo apt install -y zstd >/dev/null
        return $?
    fi
    print -u2 "codex: zstd not found and apt unavailable"
    return 1
}

_codex_zstd_compress() {
    local file="$1"
    local -a level_args
    local level_spec="${CODEX_ZSTD_LEVEL:-}"

    if [[ -z "$file" || ! -f "$file" ]]; then
        return 0
    fi
    if [[ -n "$level_spec" ]]; then
        level_args=(${=level_spec})
    else
        level_args=(-19)
    fi
    if ! _codex_ensure_zstd; then
        print -u2 "codex: zstd unavailable; skipping compression for $file"
        return 0
    fi
    if ! zstd -q -T0 -k -f "${level_args[@]}" -- "$file"; then
        print -u2 "codex: zstd failed for $file"
        return 0
    fi
}

_codex_compress_artifacts() {
    local log_path="$1"
    local md_path="$2"
    if [[ -n "$log_path" && "$log_path" != "-" ]]; then
        _codex_zstd_compress "$log_path"
    fi
    if [[ -n "$md_path" && "$md_path" != "-" ]]; then
        _codex_zstd_compress "$md_path"
    fi
}

_codex_header() {
    local start_pwd="$1"
    local session_name="$2"
    local host os time user tty shell term lang uptime codex_version
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

    if command -v codex >/dev/null 2>&1; then
        codex_version="$(codex --version 2>/dev/null | head -n 1)"
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

    print -r -- "# Codex session"
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
    if [[ -n "$codex_version" ]]; then
        print -r -- "Codex: $codex_version"
    fi
}

_codex_prompt_session_name() {
    local name
    while true; do
        local base="${PWD##*/}"
        local default=""
        if [[ -n "$base" ]]; then
            default="${base//[^a-zA-Z0-9-]/-}"
        fi
        if [[ -n "$default" ]]; then
            if ! _codex_prompt_read "Codex session name [a-zA-Z0-9- only] (default: $default): " name; then
                return 1
            fi
        else
            if ! _codex_prompt_read "Codex session name [a-zA-Z0-9- only]: " name; then
                return 1
            fi
        fi
        if [[ -z "$name" && -n "$default" ]]; then
            name="$default"
        fi
        if [[ -z "$name" ]]; then
            print -u2 "codex: session name required"
            return 1
        fi
        if [[ "$name" == *[^a-zA-Z0-9-]* ]]; then
            print -u2 "codex: session name must be letters, numbers, and hyphens only"
            continue
        fi
        print -r -- "$name"
        return 0
    done
}

_codex_header_legacy() {
    local hdr_pwd="$1"
    local hdr_branch="$2"
    local hdr_host="$3"
    local hdr_os="$4"
    local hdr_time="$5"

    if [[ -z "$hdr_pwd" ]]; then
        return 0
    fi

    print -r -- "# Codex session"
    print -r -- "Started: ${hdr_time:-unknown}"
    print -r -- "Host: ${hdr_host:-unknown}"
    print -r -- "OS: ${hdr_os:-unknown}"
    print -r -- "PWD: $hdr_pwd"
    if [[ -n "$hdr_branch" ]]; then
        print -r -- "Git branch: $hdr_branch"
    fi
}

_codex_prompt_args() {
    local answer extra
    reply=()

    if ! _codex_prompt_read "--dangerously-bypass-approvals-and-sandbox? (y/N/q/a/o) " answer; then
        return 1
    fi
    case "$answer" in
        [Qq]) return 2 ;;
        [Aa])
            if ! _codex_prompt_read "Enter additional args: --dangerously-bypass-approvals-and-sandbox " extra; then
                return 1
            fi
            reply=(--dangerously-bypass-approvals-and-sandbox ${(z)extra})
            ;;
        [Oo])
            if ! _codex_prompt_read "Enter args: " extra; then
                return 1
            fi
            reply=(${(z)extra})
            ;;
        [Yy])
            reply=(--dangerously-bypass-approvals-and-sandbox)
            ;;
        *)
            if ! _codex_prompt_read "--full-auto? (y/N/q) " answer; then
                return 1
            fi
            case "$answer" in
                [Qq]) return 2 ;;
                [Yy]) reply=(--full-auto) ;;
                *) reply=() ;;
            esac
            ;;
    esac

    return 0
}

codex_strip_ansi() {
    local in="$1"
    local out="${2:-${in%.log}.md}"
    local header="$3"
    local esc=$'\033'
    local bel=$'\a'
    local cleaner="${CODEX_LOG_CLEANER:-$HOME/src/codex-tools/codex_log_clean.py}"
    local python=""

    if [[ -z "$in" || ! -f "$in" ]]; then
        print -u2 "codex_strip_ansi: missing log file"
        return 1
    fi

    if (( $# >= 4 )); then
        header="$(_codex_header_legacy "$3" "$4" "$5" "$6" "$7")"
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
    _codex_compress_artifacts "$in" "$out"
}

codex_clean() {
    local in="$1"
    local out="$2"
    if [[ -z "$in" ]]; then
        print -u2 "Usage: codex_clean <log> [out.md]"
        return 2
    fi
    if [[ -z "$out" ]]; then
        out="${in%.log}.md"
    fi
    codex_strip_ansi "$in" "$out"
}

codex_script() {
    local dir log start_pwd header session_name base
    local -a codex_args
    dir="$(_codex_log_dir)"
    mkdir -p "$dir"
    session_name="$(_codex_prompt_session_name)" || return 1
    _set_titlebar "$session_name"
    _codex_prompt_args
    case $? in
        2)
            print -r -- "codex_script: cancelled"
            return 0
            ;;
        0) codex_args=("${reply[@]}") ;;
        *) return 1 ;;
    esac
    base="${session_name}-$(date +%Y.%m.%d.%H.%M.%S)"
    log="$dir/${base}.log"
    start_pwd="$PWD"
    header="$(_codex_header "$start_pwd" "$session_name")"
    print -r -- "Logging to $log"

    local cmd_str
    cmd_str="$(_codex_sh_quote codex)"
    if (( ${#codex_args[@]} )); then
        for a in "${codex_args[@]}"; do
            cmd_str+=" $(_codex_sh_quote "$a")"
        done
    fi
    if script --help 2>/dev/null | grep -q -- '-f'; then
        script -q -f -c "$cmd_str" "$log"
    else
        script -q -c "$cmd_str" "$log"
    fi

    codex_strip_ansi "$log" "" "$header"
}

codex_tmux() {
    local dir log base session start_pwd header session_name
    local -a cmd
    local shell_bin
    local tmux_conf tmux_socket
    local -a tmux_cmd
    local tmux_mouse

    if ! command -v tmux >/dev/null 2>&1; then
        print -u2 "codex_tmux: tmux not found"
        return 1
    fi

    dir="$(_codex_log_dir)"
    mkdir -p "$dir"
    session_name="$(_codex_prompt_session_name)" || return 1
    _set_titlebar "$session_name"
    base="${session_name}-$(date +%Y.%m.%d.%H.%M.%S)"
    log="$dir/${base}.log"
    session="${CODEX_TMUX_SESSION:-codex}-${base//./-}"
    start_pwd="$PWD"
    header="$(_codex_header "$start_pwd" "$session_name")"
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

    tmux_conf="${CODEX_TMUX_CONF:-$HOME/src/codex-tools/codex.tmux.conf}"
    tmux_socket="${CODEX_TMUX_SOCKET:-codex}"
    tmux_mouse="${CODEX_TMUX_MOUSE:-scroll}"
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
        print -u2 "codex_tmux: tmux conf not found; using default config: $tmux_conf"
    fi

    if ! "${tmux_cmd[@]}" new-session -d -s "$session" -c "$start_pwd" "${cmd[@]}"; then
        print -u2 "codex_tmux: failed to start tmux session"
        return 1
    fi
    sleep 0.2
    if ! "${tmux_cmd[@]}" has-session -t "$session" 2>/dev/null; then
        print -u2 "codex_tmux: session exited immediately; check shell startup output"
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
    "${tmux_cmd[@]}" pipe-pane -o -t "${session}:" "cat >> \"$log\""
    if [[ -n "${TMUX:-}" ]]; then
        "${tmux_cmd[@]}" switch-client -t "$session" || "${tmux_cmd[@]}" attach -t "$session"
    else
        "${tmux_cmd[@]}" attach -t "$session"
    fi

    if [[ -f "$log" ]]; then
        codex_strip_ansi "$log" "" "$header"
    fi
}

codex_attach() {
    local session
    local tmux_socket
    local -a tmux_cmd

    if ! command -v tmux >/dev/null 2>&1; then
        print -u2 "codex_attach: tmux not found"
        return 1
    fi
    if ! command -v fzf >/dev/null 2>&1; then
        print -u2 "codex_attach: fzf not found"
        return 1
    fi

    tmux_socket="${CODEX_TMUX_SOCKET:-codex}"
    tmux_cmd=(tmux)
    if [[ -n "$tmux_socket" ]]; then
        tmux_cmd+=(-L "$tmux_socket")
    fi

    session="$("${tmux_cmd[@]}" list-sessions -F '#S' 2>/dev/null | fzf)"
    if [[ -z "$session" ]]; then
        print -u2 "codex_attach: no session selected"
        return 1
    fi

    "${tmux_cmd[@]}" attach-session -t "$session"
}

alias codexd='codex --dangerously-bypass-approvals-and-sandbox'
alias codexfa='codex --full-auto'
