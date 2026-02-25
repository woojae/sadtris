# :( Sadtris

A sad Tetris clone built natively for macOS with SwiftUI.  The only reason you would use this is if you're on the plane, or in the woods.

![macOS](https://img.shields.io/badge/macOS-13%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)

## Features

- **Modern Tetris mechanics** — hold piece, ghost piece, lock delay, DAS/ARR, wall kicks
- **T-spin detection** — full and mini T-spins with bonus scoring
- **High scores** — top 5 leaderboard with 3-letter initials, persisted across sessions
- **Increasing difficulty** — speed ramps up as you clear lines

## Controls

| Key | Action |
|-----|--------|
| `← →` | Move |
| `↑` | Rotate |
| `↓` | Soft drop |
| `Space` | Hard drop |
| `C` | Hold piece |
| `P` | Pause |
| `R` | Restart |

## Build & Run

Requires macOS 13+ and Swift 5.9+.

```sh
swift build -c release
cp .build/release/Sadtris Sadtris.app/Contents/MacOS/Sadtris
cp Resources/AppIcon.icns Sadtris.app/Contents/Resources/AppIcon.icns
open Sadtris.app
```

Or run directly during development:

```sh
swift run
```
