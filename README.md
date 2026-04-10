# Julia

A macOS command palette for tmux. Press `Cmd+Shift+T` from anywhere to open the palette and switch sessions, manage windows, or run tmux commands. Why? Because I have a sprawl of tmux windows and can't ever remember the built in key commands to manage them.

## Requirements

- [Xcode](https://developer.apple.com/xcode/) 16.0 or later
- [tmux](https://github.com/tmux/tmux) — `brew install tmux`
- [Task](https://taskfile.dev) — `brew install go-task`
- [xcbeautify](https://github.com/cpisciotta/xcbeautify) — `brew install xcbeautify`
- Apple Developer account with a configured signing team in Xcode

## Build & Run

```sh
task           # Build, install to /Applications, and launch (default)
task build     # Just build to ./build/
task install   # Build and copy to /Applications/Julia.app
task run       # Build, install, and launch
task clean     # Remove ./build/
```