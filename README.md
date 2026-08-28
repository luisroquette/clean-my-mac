# Clean My Mac

**A native macOS menu-bar guard that warns at 75% and starts safe cleanup at 78% to protect an 80% SSD ceiling.**

<p align="center">
  <a href="https://luisroquette.github.io/clean-my-mac/"><img src="https://img.shields.io/badge/product%20page-open-F28C38?style=flat-square" alt="Open the Clean My Mac product page"></a>
  <a href="https://github.com/luisroquette/clean-my-mac/releases/latest"><img src="https://img.shields.io/badge/version-1.1.0-1D1D1F?style=flat-square" alt="Version 1.1.0"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-1D1D1F?style=flat-square" alt="MIT license"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-1D1D1F?style=flat-square" alt="macOS 14 or later">
</p>

Clean My Mac watches the data volume every minute. It sends one warning when
usage reaches 75%. If automatic cleanup is enabled, it acts at 78%, then retries
after 15 minutes while storage remains under pressure.

No account. No telemetry. No cloud service. Native SwiftUI, not Electron.

![Clean My Mac showing a 91% storage warning and the automatic-cleanup controls](docs/img/app-popover.webp)

[Watch the 12-second product demo](docs/video/clean-my-mac-demo.mp4)

## Why it exists

Disk pressure usually becomes visible too late: builds fail, updates stop, and
the next urgent task begins with manual folder hunting. Clean My Mac turns that
failure into four predictable guardrails:

1. **75% used:** visible menu-bar state and a macOS notification.
2. **78% used:** optional automatic cleanup of narrowly allow-listed data.
3. **80% used:** hard-limit alert if safe cleanup cannot recover enough space.
4. **Below 73%:** the warning rearms for the next storage cycle.

## Safety contract

| It may remove | It never removes |
|---|---|
| npm, uv, Bun, Deno and Homebrew caches when those tools are installed | Documents, Desktop, Downloads, Photos, Music, Movies or Public folders |
| `node_modules` and `.next` directories of 100 MB or more | Git-tracked or non-ignored project content |
| Only generated folders inside a Git repository and ignored by Git | Artifacts belonging to an active Node/Python development process |
| Only after checking Git status before and after cleanup | Trash contents, Docker data, credentials, source files or external volumes |

Generated artifacts are deleted permanently to recover disk space. Every run is
recorded locally at `~/Library/Logs/CleanMyMac/clean-my-mac.log`.

## Install

Open the [download page](https://luisroquette.github.io/clean-my-mac/#download), complete the contact form, unzip the released file, and move **Clean My Mac.app** to Applications.

The free build is ad-hoc signed, not Apple-notarized. On first launch:

```bash
xattr -dr com.apple.quarantine "/Applications/Clean My Mac.app"
open "/Applications/Clean My Mac.app"
```

The prebuilt release targets Apple silicon and requires macOS 14 or later.

## Use

1. Find the disk icon in the top-right menu bar, beside Wi-Fi and the clock.
2. Leave **Automatic cleanup** enabled for the 78% preventive guard.
3. Leave **Open at Login** enabled for continuous monitoring.
4. Use **Check now** or **Clean now** whenever you want an immediate run.

The current app interface is in Brazilian Portuguese.

## Build from source

```bash
git clone https://github.com/luisroquette/clean-my-mac.git
cd clean-my-mac
./Scripts/preflight.sh
open "dist/Clean My Mac.app"
```

The project uses Swift 6, SwiftUI, AppKit and native macOS services. It has no
third-party runtime dependencies.

## Development roots

The generated-artifact scan is limited to `~/Projects`, `~/Projetos`,
`~/Developer`, `~/Code`, plus direct folders in the home directory that contain
either `.git` or `package.json`. Hidden folders and personal macOS folders are
excluded before traversal.

## Privacy

Storage samples, preferences and cleanup logs remain on the Mac. The app has no
analytics SDK, network client, account system or remote backend.

## Known limitations

- The 80% ceiling is best-effort: if safe regenerable data is insufficient, the app alerts instead of deleting personal files.
- The prebuilt release is Apple-silicon-only and not notarized.
- The interface is currently Brazilian Portuguese.
- Projects outside the documented roots are not scanned.
- Package caches are cleaned only when their command-line tools are installed.

## License

[MIT](LICENSE) © 2026 Luis Roquette.

---

Clean My Mac is an independent open-source utility. It is not affiliated with,
sponsored by, or endorsed by MacPaw. “CleanMyMac” is a trademark of its
respective owner.
