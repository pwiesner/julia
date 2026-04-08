# Julia

A macOS command palette for tmux. Press `Cmd+Shift+T` from anywhere to open the palette and switch sessions, manage windows, or run tmux commands.

## Requirements

- macOS 14.0 or later
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

The app is installed to `/Applications` and launched from there because macOS Accessibility permissions don't apply reliably to binaries running out of Xcode's `DerivedData`. The Taskfile handles the install step automatically.

On first launch, macOS will prompt for Accessibility permission — grant it (required for the global hotkey).
