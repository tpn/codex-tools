#!/usr/bin/env zsh

emulate -L zsh -o errexit -o nounset -o pipefail

fail() {
    print -u2 -- "FAIL: $*"
    exit 1
}

tmpdir="$(mktemp -d)"
cleanup() {
    rm -rf "$tmpdir"
}
trap cleanup EXIT INT TERM

cat >"$tmpdir/pbcopy" <<'EOF'
#!/bin/sh
cat >"$TEST_PBCOPY_OUT"
EOF
chmod +x "$tmpdir/pbcopy"

export TEST_PBCOPY_OUT="$tmpdir/pbcopy.out"
export PATH="$tmpdir:/usr/bin:/bin:/usr/sbin:/sbin"

print -n -- "hello-from-test" | "$PWD/tmux-copy-clipboard.sh"

if [[ ! -f "$TEST_PBCOPY_OUT" ]]; then
    fail "pbcopy stub was not invoked"
fi

actual="$(<"$TEST_PBCOPY_OUT")"
if [[ "$actual" != "hello-from-test" ]]; then
    fail "expected pbcopy to receive selection, got <$actual>"
fi

print -r -- "ok"
