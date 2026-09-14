# OpenStats

macOS 14+ menu-bar system monitor. Swift 6 language mode, AppKit status item and panels
hosting SwiftUI, no third-party dependencies. The Xcode project is generated from
`project.yml` by XcodeGen; everything testable lives in the local Swift package.

- `App/` — `main.swift` and the asset catalog.
- `Widget/` — the sandboxed WidgetKit extension (“System overview”), embedded in `Contents/PlugIns`.
  It samples CPU, memory, disk and battery itself through `Metrics`, so it works without the app.
- `Helper/` — the privileged helper (`OpenStatsHelper`) and its launchd plist, embedded in
  the app bundle for `SMAppService.daemon`.
- `Packages/OpenStatsKit/Sources/Localization` — `tr(_:)` and the English table (see below).
- `Packages/OpenStatsKit/Sources/SMC` — the AppleSMC user client, fan control, temperature
  key discovery.
- `Packages/OpenStatsKit/Sources/Metrics` — one sampler per metric and `MetricsHub`; power and CPU
  frequency (`PowerSampler`), disk activity and NVMe SMART (`DiskSamplers`), Bluetooth battery,
  the SQLite history store.
- `Packages/OpenStatsKit/Sources/Cleaner` — cleanup rules, `SafetyGuard`, `CleanEngine`, the app
  uninstaller's leftover search and the launchd startup-item list.
- `Packages/OpenStatsKit/Sources/Updates` — the update manifest and the download → verify →
  replace → relaunch steps.
- `Packages/OpenStatsKit/Sources/HelperShared` — the XPC protocol and maintenance commands
  shared by the app and the helper.
- `Packages/OpenStatsKit/Sources/OpenStatsUI` — design tokens, panel pages, settings,
  menu-bar renderer, app controller, snapshot renderer.
- `Packages/OpenStatsKit/Tests` — metrics, SMC decoding, cleanup safety, updates, UI logic and
  localization.

## Build

**Xcode 26 or later is required** — CommandLineTools does not ship the SwiftUI macro plugins.

```bash
brew install xcodegen
make build            # Release build, then replace /Applications/OpenStats.app and relaunch
make test             # swift test in the package
```

Versions read `0.2.0 (0003)`: `MARKETING_VERSION` changes only when releasing
(`make bump-patch` for small releases, `make bump-minor` for larger ones), and the four-digit
`CURRENT_PROJECT_VERSION` goes up by one on every `make build` (`BUMP=0` skips it). Build numbers
never reset, so every package has a larger `CFBundleVersion` than the one before. Every `make build` runs
`Scripts/install_local.sh`: it ends the running app (the helper restores fans and sleep when the
connection drops), deletes the old `/Applications/OpenStats.app`, *moves* the new bundle there so no
copy stays in the build folder, re-registers it with Launch Services, and relaunches. Only one
OpenStats ever exists on the machine, so Spotlight and the widget gallery never show duplicates.
`INSTALL=0` compiles without installing; `Scripts/release.sh` uses it and installs the notarized
build at the end.

`project.yml` defaults to ad-hoc signing so the project opens anywhere. The Makefile passes
the first Developer ID Application identity from the keychain (and `--timestamp` for Release)
when there is one. `make release` runs `Scripts/release.sh`: build, verify team, timestamp and
hardened runtime on both binaries, notarize and staple the app, build and notarize the DMG,
write the online-update zip and `appcast.json`, and write a Homebrew cask (`auto_updates true`). The helper derives its client requirement from its own signing
team at run time, so no team ID is hard-coded.

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

## Menu bar, popovers and main window

`MenuBarController` owns the status items. In the *separate* layout every enabled metric gets
its own `NSStatusItem` (created in reverse so they read left to right) and opens a 320 pt
popover for that metric; in the *combined* layout a single item opens the main window.

Popovers are borderless, non-activating `NSPanel`s. The SwiftUI tree is created on open and
destroyed on close, so a hidden popover costs nothing. Height comes from measuring a flat,
scroll-free copy of the same view; placeholders keep that height stable until data arrives, and
the window is resized without animation because animating it makes SwiftUI re-lay out every
frame. Charts are drawn with `Canvas`, not Swift Charts.

The main window reuses the popover content with `isDetailPage` set (all sections, taller charts)
next to the dashboard and tool pages. Windows use a transparent, full-size-content title bar with
an empty compact toolbar, so the traffic lights sit on the same ground colour as the sidebar and
line up with the 40 pt page header; the app switches to a regular activation policy while a window
is open and back to accessory when all are closed.

## Network details

`NetworkController` runs only while it is needed:

- **Connection probe** — an unprivileged `SOCK_DGRAM` ICMP echo (`ConnectivityProbe`), matched on
  sequence number and a random payload token because the kernel rewrites the identifier.
- **Interface and addresses** — `SCDynamicStore` / `SCPreferences` for the primary and physical
  service, `getifaddrs` for addresses, CoreWLAN for signal and rate.
- **Public IP** — Cloudflare trace (ipify as fallback) for the address only. Region and ASN come from
  MaxMind GeoLite2 databases read by `MaxMindDatabase`, a memory-mapped reader of the MaxMind DB
  format (search tree + data section decoder, no dependencies). `server/geoip/` holds the systemd
  timer that syncs GeoLite2 onto getopenstats.com with the MaxMind key kept in `/etc/openstats` on the
  server; the app fetches `geoip/manifest.json`, downloads changed files, verifies sha256 and the
  database type, then swaps them in. Without a local database it falls back to ipinfo.io. Country
  codes are validated before being used as flag file names.
- **Per-process traffic** — cumulative bytes from `/usr/bin/nettop`, diffed between samples.
- **DNS** — `networksetup -setdnsservers` through the helper (protocol 3), which re-validates the
  service name and every address; without the helper, a one-off administrator prompt runs the
  same fixed command.

## Online updates

`UpdateController` fetches `https://getopenstats.com/download/appcast.json` at launch and daily
(version, date, notes taken from `CHANGELOG.md` by `Scripts/appcast.py`, zip URL, sha256, size). An
update is installed only after: sha256 matches, the zip holds exactly one `.app`, its bundle ID and
version match, `SecStaticCodeCheckValidity` passes with a requirement pinned to the running app's
team, and `spctl --assess` accepts it (notarized). The old bundle is renamed into a same-volume
temporary folder, the new one moved into place (restored on failure; an administrator prompt is
used when the folder is not writable), and a detached shell waits for the process to exit before
reopening the app. After an update the old helper may still be running; the app disconnects, waits
for its 30 s idle exit and checks the protocol version again before asking for a reinstall.

## Power, disk and history

- System, adapter and battery power come from SMC `PSTR`, `PDTR`, `PPBR`. GPU power comes from the
  IOReport *Energy Model* `GPU Energy` counter; CPU energy counters on recent chips barely update,
  so CPU power is not shown. Cluster frequencies are residency-weighted averages of *CPU Complex
  Performance States*, using the `voltage-states*-sram` tables of `pmgr` (Hz on older chips, MHz on
  newer ones). Each IOReport sample costs about 5 ms of CPU, so it runs at most every 2 s and only
  while a page shows it.
- Disk activity diffs `IOBlockStorageDriver` statistics; SSD health reads the NVMe SMART log
  through the system `NVMeSMARTLib` plug-in (no root).
- `HistoryRecorder` folds each sample into a per-minute record (averages, CPU and temperature
  peaks, worst memory pressure) and writes it to `history.sqlite`; records older than 8 days are
  pruned hourly. Queries bucket by 1, 5 or 30 minutes and charts break lines across gaps.

## Localization

Source strings are Simplified Chinese. `Scripts/l10n_wrap.py` wraps every Chinese literal in
`tr(...)` (skipping logger calls, `case` patterns and multi-line strings) and lists the keys.
`tr` returns the input unless English is active; otherwise it looks the text up in
`Localization/Translations.swift` — exact keys first, then templates where `{}` stands for an
interpolated value, longest literal fragments first, translating captured values once more. The
language is configured at launch (System follows the global `AppleLanguages`). Changing it
reconfigures `L10n`, rebuilds the main window and update prompt through `.id(language)`, rebuilds the
app menu and redraws the menu bar; popovers are created on open. Names supplied by macOS follow the
app's `AppleLanguages`, which changes at the next launch. Dates use `L10n.locale`. `--snapshot <dir> --language en` renders English screenshots and
writes any untranslated string to `untranslated.txt`.

`--snapshot <dir>` renders every main-window page, popover, settings section and the menu bar in light and
dark, through real `NSHostingView`s in off-screen windows — `ImageRenderer` washes out pages
that contain bitmaps.
