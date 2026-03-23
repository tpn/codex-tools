# Tmux Titlebar Persistence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prefix session titles with `<hostname>:`, restore `<username>@<hostname>` after tmux detach, and reuse the original friendly title when reattaching existing `codex` and `claude` tmux sessions.

**Architecture:** Keep the behavior in the existing zsh wrappers. Add small helpers to compute session and default titles, persist the friendly title in a tmux session user option when creating a session, and restore/reset titles in the attach paths.

**Tech Stack:** zsh functions, tmux session user options, shell-script regression tests

---

### Task 1: Regression Coverage

**Files:**
- Create: `tests/titlebar_regression.zsh`
- Test: `tests/titlebar_regression.zsh`

- [ ] **Step 1: Write the failing test**

```zsh
codex_tmux
assert session option @titlebar-title == "spark:codex-tools"
assert titlebar calls are "spark:codex-tools" then "trent@spark"

codex_attach
assert titlebar calls are restored session title then default title
```

- [ ] **Step 2: Run test to verify it fails**

Run: `zsh tests/titlebar_regression.zsh`
Expected: FAIL because the wrappers do not yet compute host-prefixed titles or restore them from tmux metadata.

### Task 2: Codex Wrapper Changes

**Files:**
- Modify: `codex.zsh`
- Test: `tests/titlebar_regression.zsh`

- [ ] **Step 1: Write minimal title helpers**

```zsh
_codex_session_title() { print -r -- "${host}:${session_name}"; }
_codex_default_title() { print -r -- "${user}@${host}"; }
```

- [ ] **Step 2: Persist title on new tmux sessions**

Run inside `codex_tmux`:

```zsh
tmux set-option -t "$session" @titlebar-title "$session_title"
```

- [ ] **Step 3: Restore and reset title in attach paths**

```zsh
codex_attach() { _set_titlebar "$stored_title"; tmux attach-session ...; _set_titlebar "$default_title"; }
```

- [ ] **Step 4: Run tests**

Run: `zsh tests/titlebar_regression.zsh`
Expected: PASS for codex coverage

### Task 3: Claude Wrapper Changes

**Files:**
- Modify: `claude.zsh`
- Test: `tests/titlebar_regression.zsh`

- [ ] **Step 1: Mirror the codex helper and tmux metadata changes**
- [ ] **Step 2: Run tests**

Run: `zsh tests/titlebar_regression.zsh`
Expected: PASS for claude coverage too
