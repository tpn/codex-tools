#!/bin/sh

# Read selection from stdin and copy to system clipboard.
# Works on WSL (clip.exe), Wayland (wl-copy), or X11 (xclip/xsel).

set -u

tmp="$(mktemp)"
cleanup() {
  rm -f "$tmp"
}
trap cleanup EXIT INT TERM

cat >"$tmp"

_is_wsl() {
  [ -n "${WSL_DISTRO_NAME:-}" ] && return 0
  [ -n "${WSL_INTEROP:-}" ] && return 0
  [ -e /proc/sys/fs/binfmt_misc/WSLInterop ] && return 0
  grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null
}

if _is_wsl && command -v clip.exe >/dev/null 2>&1; then
  clip.exe <"$tmp" || true
  exit 0
fi

if command -v wl-copy >/dev/null 2>&1; then
  if [ -n "${WAYLAND_DISPLAY:-}" ]; then
    wl-copy <"$tmp" || true
    exit 0
  fi
  if [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -S "${XDG_RUNTIME_DIR}/wayland-0" ]; then
    WAYLAND_DISPLAY=wayland-0 wl-copy <"$tmp" || true
    exit 0
  fi
fi

_local_x_socket_display() {
  for s in /tmp/.X11-unix/X*; do
    [ -S "$s" ] || continue
    printf ':%s\n' "$(basename "$s" | sed 's/^X//')"
    return 0
  done
  return 1
}

_display_is_ssh_forwarded() {
  case "${DISPLAY:-}" in
    localhost:*|127.0.0.1:*|\[::1\]:*) return 0 ;;
    *) return 1 ;;
  esac
}

# X11 fallback.  Tmux sessions can retain stale SSH-forwarded displays such as
# localhost:10.0; those cannot update the workstation clipboard after the SSH
# session is gone, so prefer a real local X socket when one exists.
if [ -z "${DISPLAY:-}" ] || _display_is_ssh_forwarded; then
  local_display="$(_local_x_socket_display || true)"
  if [ -n "$local_display" ]; then
    DISPLAY="$local_display"
    export DISPLAY
  fi
fi
if [ -z "${XAUTHORITY:-}" ] || [ ! -r "${XAUTHORITY:-}" ]; then
  uid="$(id -u 2>/dev/null || true)"
  if [ -n "$uid" ] && [ -r "/run/user/$uid/gdm/Xauthority" ]; then
    XAUTHORITY="/run/user/$uid/gdm/Xauthority"
  else
    XAUTHORITY="$HOME/.Xauthority"
  fi
  export XAUTHORITY
fi

if command -v xclip >/dev/null 2>&1; then
  xclip -selection clipboard -in <"$tmp" || true
  exit 0
fi

if command -v xsel >/dev/null 2>&1; then
  xsel --clipboard --input <"$tmp" || true
  exit 0
fi

exit 0
