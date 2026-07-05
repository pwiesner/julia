# Julia

> [!NOTE]  
> This project is vibe coded the whole way down. It was created for fun and is not something i'm taking seriously.

A macOS command palette for tmux. Press the global hotkey (`Cmd+Shift+T` by default, configurable in Settings) from anywhere to open the palette and jump between windows, switch sessions, or run tmux commands. Why? Because I have a sprawl of tmux windows and can't ever remember the built in key commands to manage them.

## What it shows

- Windows named by their **project directory** instead of `zsh`/`claude.exe`, with the foreground process, **git branch**, and last activity in the detail line — all searchable, so typing a ticket number finds its window
- Whether a **Claude Code session is working** (orange sparkles), **waiting on you** (blue speech bubble), or **blocked on tool permission** (red lock) — press Tab for a triage view: needs permission, needs you, working, idle
- **Your agents page you**: a menu bar badge counts Claudes waiting unseen, a global hotkey jumps through them longest-wait first, and native notifications carry the agent's actual question (configurable: off / permission requests / all waits)
- Windows ordered by **frecency** — your working set assembles at the top, the previous window is preselected (hotkey + return = alt-tab), and `Cmd+1`–`Cmd+9` jump straight to a row
- A **live pane preview** for the selected window (watch an agent think before you commit to the jump), and a collapsible sessions sidebar (`Cmd+B`)

Agent state comes from [beeper](https://github.com/pwiesner/beeper) when installed — exact state straight from Claude Code's own hooks, mapped to windows by pane — with pane-content heuristics as the fallback.

## Install

Grab `Julia.zip` from the [latest release](https://github.com/pwiesner/julia/releases), unzip, and drop `Julia.app` into `/Applications`. Releases are Developer ID-signed and notarized, so they launch without any Gatekeeper fuss.

## Requirements

- [tmux](https://github.com/tmux/tmux) — `brew install tmux`

To build from source, additionally:

- [Xcode](https://developer.apple.com/xcode/) 16.0 or later
- [Task](https://taskfile.dev) — `brew install go-task`
- [xcbeautify](https://github.com/cpisciotta/xcbeautify) — `brew install xcbeautify`
- Apple Developer account with a configured signing team in Xcode

## Build & Run

```sh
task           # Build, install to /Applications, and launch (default)
task build     # Just build to ./build/
task install   # Build and copy to /Applications/Julia.app
task run       # Build, install, and launch
task release   # Build, notarize, and staple a release zip at ./build/Julia.zip
task clean     # Remove ./build/
```
