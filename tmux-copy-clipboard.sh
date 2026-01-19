#!/bin/sh

# Read selection from stdin and copy to system clipboard.
# Works on Wayland (wl-copy) or X11 (xclip/xsel).

set -u

tmp="$(mktemp)"
cleanup() {
  rm -f "$tmp"
}
trap cleanup EXIT INT TERM

cat >"$tmp"

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

# X11 fallback.
if [ -z "${DISPLAY:-}" ]; then
  for s in /tmp/.X11-unix/X*; do
    [ -S "$s" ] || continue
    DISPLAY=":$(basename "$s" | sed 's/^X//')"
    export DISPLAY
    break
  done
fi
if [ -z "${XAUTHORITY:-}" ]; then
  XAUTHORITY="$HOME/.Xauthority"
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
