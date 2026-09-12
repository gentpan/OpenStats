# OpenStats

macOS 14+ menu-bar system monitor. Swift 6 language mode, AppKit status item and panels
hosting SwiftUI, no third-party dependencies. The Xcode project is generated from
`project.yml` by XcodeGen; everything testable lives in the local Swift package.

- `App/` — `main.swift` and the asset catalog.
- `Helper/` — the privileged helper (`OpenStatsHelper`) and its launchd plist, embedded in
  the app bundle for `SMAppService.daemon`.
- `Packages/OpenStatsKit/Sources/SMC` — the AppleSMC user client, fan control, temperature
  key discovery.
- `Packages/OpenStatsKit/Sources/Metrics` — one sampler per metric and `MetricsHub`.
- `Packages/OpenStatsKit/Sources/Cleaner` — cleanup rules, `SafetyGuard`, `CleanEngine`.
- `Packages/OpenStatsKit/Sources/HelperShared` — the XPC protocol and maintenance commands
  shared by the app and the helper.
- `Packages/OpenStatsKit/Sources/OpenStatsUI` — design tokens, panel pages, settings,
  menu-bar renderer, app controller, snapshot renderer.
- `Packages/OpenStatsKit/Tests` — metrics, SMC decoding and cleanup safety.

## Build

**A full Xcode is required.** CommandLineTools does not ship the SwiftUI macro plugins.

```bash
brew install xcodegen
make build            # Debug
make install          # Release into /Applications
make test             # swift test in the package
```

Builds are ad-hoc signed (`CODE_SIGN_IDENTITY: "-"` in `project.yml`). For a release,
switch to a Developer ID identity, keep hardened runtime on, notarize, and set
`HelperConstants.teamIdentifier` so the helper's code-signing requirement includes the team.

## Sampling

`MetricsHub` is an actor that runs one loop. `AppModel.demand` describes what is on screen —
which menu-bar items are enabled, whether the panel is open and on which tab — and the hub
samples only that: CPU always; memory and network cheaply; GPU, disk, processes, sensors and
fans only when a visible surface needs them. Disk is read at most every 30 s, battery every
10 s. The loop pauses on screen sleep, system sleep and session switch.

Things that are easy to get wrong and are handled on purpose:

- `host_processor_info` returns kernel-allocated memory; it is `vm_deallocate`d every sample.
- `getifaddrs`' `if_data` counters are 32-bit and wrap at 4 GiB; network uses
  `NET_RT_IFLIST2` and `if_data64`.
- Memory follows Activity Monitor: app memory is `internal − purgeable` pages; the page size
  comes from `host_page_size` (16 KB on Apple Silicon).
- Process CPU time and wall time are both in mach absolute units, so their ratio needs no
  timebase conversion.
- Core types come from `hw.perflevelN`; logical CPUs are numbered from the lowest
  performance level up.

## SMC

Temperatures are not hard-coded per chip. On first use the sampler enumerates every SMC key
once (≈3,800 keys in about 10 ms on an M5 Max), groups `Tp*`/`Te*` as CPU, `Tg*` as GPU,
`Tm*` as memory, `TB*` as battery and `Ts0P`/`Ts1P` as palm rest, keeps keys whose first
reading is plausible, and samples at most 12 per group.

Fans are read without privileges. Writing needs root and goes through the helper. On M5
the mode key (`F0md`) accepts a direct write; M1–M4 first need `Ftst=1` and a pause while
`thermalmonitord` lets go. The firmware records only manual or automatic, not who set it, so
a fan in manual mode that OpenStats did not set is shown as controlled by another program.

## Helper

Registered with `SMAppService.daemon`; `RunAtLoad` so that an unclean exit is repaired at
boot. The XPC interface is a fixed list of operations — no arbitrary commands — and each
connection gets `setCodeSigningRequirement`. State that must be undone (manual fans, disabled
sleep) is persisted to `/Library/Application Support/OpenStats/helper-state.plist` and
reverted when the last client disconnects or at the next start. The helper exits after 30 s
without clients.

## Cleanup

Every rule lists candidate items; every item passes `SafetyGuard` twice — at scan and again
right before deletion, because apps start in between.

- Deny by default: an item must sit strictly inside an allow-listed root under the home
  folder, never be the root itself, contain no `..` or control characters, and still pass
  after symlinks are resolved (resolution can only reject, never allow).
- Under `Application Support`, only folders named like caches (`Code Cache`, `GPUCache`,
  `CacheStorage`, …) are allowed.
- Any path component matching a protected keyword (keychains, password managers, VPNs,
  cookies, history, …) is rejected.
- Reverse-DNS cache folders whose app is running are skipped; browser rules are blocked while
  the browser runs; items modified in the last two minutes count as in use.

Regenerable caches are deleted outright; user files go to the Trash. Each action is appended
to `~/Library/Logs/OpenStats/cleanup.log` as a JSON line.

## Panel

A borderless, non-activating `NSPanel` under the status item, hosting SwiftUI inside
`NSGlassEffectView` on macOS 26+ (`NSVisualEffectView` before). The SwiftUI tree is created on
open and destroyed on close, so a hidden panel costs nothing. Height comes from measuring a
flat, scroll-free copy of the same view; placeholders keep that height stable until data
arrives, and the window is resized without animation because animating it makes SwiftUI
re-lay out every frame. Charts are drawn with `Canvas`, not Swift Charts.

`--snapshot <dir>` renders every panel tab, settings section and the menu bar in light and
dark, through real `NSHostingView`s in off-screen windows — `ImageRenderer` washes out pages
that contain bitmaps.
