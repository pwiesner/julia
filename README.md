# Julia

> [!NOTE]  
> This project is vibe coded the whole way down. It was created for fun and is not something i'm taking seriously.

A macOS command palette for tmux. Press the global hotkey (`Cmd+Shift+T` by default, configurable in Settings) from anywhere to open the palette and jump between windows, switch sessions, or run tmux commands. Why? Because I have a sprawl of tmux windows and can't ever remember the built in key commands to manage them.

## What it shows

- Windows named by their **project directory** instead of `zsh`/`claude.exe`, with the foreground process, **git branch**, and last activity in the detail line — all searchable, so typing a ticket number finds its window
- Whether a **Claude Code session is working** (orange sparkles) or **waiting on you** (blue speech bubble)
- Windows ordered by **visit recency** — your working set assembles at the top, the previous window is preselected (hotkey + return = alt-tab), and `Cmd+1`–`Cmd+9` jump straight to a row
- A live **pane preview** for the selected window, and a collapsible sessions sidebar (`Cmd+B`)

## Install

Grab `Julia.zip` from the [latest release](https://github.com/pwiesner/julia/releases), unzip, and drop `Julia.app` into `/Applications`. The app is signed with a development certificate but not notarized, so on first launch right-click → Open (or `xattr -d com.apple.quarantine /Applications/Julia.app`).

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
task release   # Build a Release-configuration zip at ./build/Julia.zip
task clean     # Remove ./build/
```
