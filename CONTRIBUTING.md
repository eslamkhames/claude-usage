# Contributing

Thanks for helping out! Bug reports, ideas and pull requests are all welcome.

## Building

You need macOS 14+ and the Xcode command line tools (`xcode-select --install`). There's no Xcode project; the app is built with `swiftc` directly:

```sh
./build.sh            # builds build/ClaudeBar.app
./build.sh --install  # also copies it to /Applications and launches it
```

## Where things live

| File | What it does |
| --- | --- |
| `Sources/Models.swift` | Parses claude.ai's usage response. Start here if numbers stop showing. |
| `Sources/AccountStore.swift` | Accounts, refreshing and per-account cookie stores. |
| `Sources/ClaudeWebSession.swift` | The hidden web view that talks to claude.ai. |
| `Sources/MenuBarRenderer.swift` | Draws the menu bar item in each style. |
| `Sources/Views.swift`, `Sources/SettingsView.swift` | The panel and settings UI. |
| `Sources/ClaudeCodeUsage.swift` | Reads Claude Code usage from `~/.claude/projects`. |
| `Sources/Updater.swift` | Checks GitHub releases and installs updates. |

## Pull requests

- Keep changes focused: one fix or feature per PR.
- Match the style of the surrounding code.
- Make sure `./build.sh` succeeds; CI builds every PR.
- For UI changes, add a screenshot to the PR.
- Never commit or paste a real `sessionKey` or other credentials, even in test data or screenshots.

## Reporting bugs

Open an issue with your macOS version, the ClaudeBar version (shown in Settings) and what you expected versus what happened. If the usage numbers are wrong or missing, say which plan the account is on (Pro, Max 5x, …), since claude.ai's response differs by plan.

Security problems go through [SECURITY.md](SECURITY.md) instead.
