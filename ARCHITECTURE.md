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
- `Packages/OpenStatsKit/Sources/Cleaner` — cleanup rules, `SafetyGuard`, `CleanEngine`, the single
  deletion funnel (`Deletion/`: `PathPolicy`, `FileIdentity`, `DeletionService`), the app uninstaller's
  leftover search with its diagnostics, and the launchd startup-item list.
- `Packages/OpenStatsKit/Sources/Updates` — the update manifest and the download → verify →
  replace → relaunch steps.
- `Packages/OpenStatsKit/Sources/HelperShared` — the XPC protocol and maintenance commands
  shared by the app and the helper.
- `Packages/OpenStatsKit/Sources/AccountSync` — the sync API client, PKCE helpers and the keychain
  token store; `server/sync` is the Go service it talks to.
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
fans only when a visible surface needs them. Disk is read at most every 30 s (the purgeable part
of free space is expensive to compute and is reused for 5 minutes unless the disk page is open),
battery every 10 s. When only the menu bar shows fans, only their current speed is read; fan count
and limits are cached. The loop pauses on screen sleep, system sleep and session switch. A window
that is fully covered, on another Space, hidden with ⌘H or behind the lock screen counts as not
visible, so sampling falls back to what the menu bar needs.

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
reverted when the last client disconnects or at the next start; a fan that the helper did not
set to manual is left alone, so other fan tools are not overridden. The app keeps the connection
open only while the helper holds state for it (manual fans, lid-closed mode) and otherwise closes it
10 s after the last call (protocol 5 and later), so the helper exits after its 30 s idle timeout.

## Cleanup and uninstall

### One deletion funnel

All user-data deletion goes through `DeletionService` (`Cleaner/Deletion`): the cleaner, the app
uninstaller and the large-file "move to Trash" action. A static audit test
(`DeletionAuditTests`) fails when any other source file calls `removeItem`, `trashItem`,
`unlink`, `removefile` or `recycle` without a same-line `// SAFE: <reason>` (own temp files and
the like). An item is checked in a fixed order, and preview (`plan`) and execution (`execute`)
call the same `evaluate`, so a preview never promises something execution would refuse:

1. `PathPolicy` — the feature-independent floor. Absolute, no `..`, no control characters; system
   trees (`/System`, `/usr`, …), top-level folders themselves (`/Applications`, the home folder,
   `~/Library`, `~/Documents`, …) and credential or sync roots (`~/.ssh`, `Keychains`,
   `Mobile Documents`) are refused, compared case-insensitively *and* by device+inode, so APFS
   case aliases, the `/System/Volumes/Data` firmlink and links pointing at them are caught. From the
   trusted base downwards every component must be a real directory entry; a symlink leaf or
   ancestor is refused. Resolving links can only make this stricter. Deletion is only allowed
   inside the home folder, `/Applications` and the per-user cache area (`/var/folders`), so
   system-level locations (`/Library`, `/Users/Shared`, …) are refused here even if a caller's
   scope would allow them.
2. The caller's own scope — `SafetyGuard` for cleanup rules, the scan's candidate list for uninstall.
   A path that no longer exists is reported as missing before this check.
3. The item is still the object that was scanned (`FileIdentity`: the parent folder, the type, and
   for directories the inode). A regular file's own inode may change, because preference writes and
   `defaults write` replace the file atomically on every save. A request without a scan-time
   identity is never executed.
4. Related apps: running → skipped; the running list unreadable (an empty list from the system is
   treated as unreadable) → skipped, "unknown" never means "idle"; entries named like a running app's
   bundle id (also with a team-id or `group.` prefix) are skipped; recently modified → skipped. The
   modification time is read straight from the directory entry (`lstat`), never from `URL.resourceValues`,
   which caches per URL object.

Known limit: the check and the move are not atomic. The window is microseconds for the standard
route, but the interactive route (an administrator prompt inside `NSWorkspace`) can leave seconds
between them; the target is the Trash, so the result is recoverable.

Moving to the Trash goes through a `Trasher`; if it fails the item stays where it is — there is no
silent fallback to permanent deletion. The Trash location is written to the log. Regenerable caches
may be deleted outright; everything else goes to the Trash. Every decision, including skips and the
reason code, is appended to `~/Library/Logs/OpenStats/cleanup.log` as one JSON line (control
characters in file names are escaped, so a name cannot forge a record).

### Cleanup rules

Every rule lists candidate items. Under `Application Support`, only folders named like caches
(`Code Cache`, `GPUCache`, …) are allowed; any path component matching a protected keyword
(keychains, password managers, VPNs, cookies, history, …) is rejected; browser rules are blocked
while the browser runs.

The `apps` category covers Electron / Chromium apps. A folder under `Application Support` is only
considered when it contains a Chromium marker (`Code Cache`, `GPUCache`, `DawnCache`, …); the marker
directories are then listed together with the companions that only exist beside them (`Cache`,
`CachedData`, `Service Worker/CacheStorage`), and one item is produced per app and cache folder
(`CleanItem.title`, e.g. `Slack › Cache`). Browsers' own profile folders are excluded from this rule.
Developer-tool rules (Xcode, frontend/Python/Cargo/Swift caches) are `selectedByDefault: false`; a few
exact `~/.cache` subfolders are allow-listed by name (`SafetyGuard.allowedItems`) instead of opening the
whole directory, and every component is still checked against the protected keywords.

Running-app checks use bundle ids first and then names (`DeletionRequest.guardNames`, matched
case-insensitively against localized name, bundle file name and executable name), because a cache
folder named `Slack` carries no bundle id. When the system returns an empty running-app list the
check fails closed (`RunningApps.unknown`).

### Uninstaller

`AppUninstaller.scan` returns evidence-bearing leftovers: each item records why it was claimed
(`AppLeftover.Evidence`: bundle id, embedded component, app group from the code signature, container
metadata, name, vendor folder, launch item or native-messaging manifest that points into the app,
crash report, known path). Shared and name-only matches are not preselected. Matching is by
bundle-id boundary (`com.foo` never claims `com.foobar`); a name that extends another installed
app's bundle id (`com.google.Chrome.canary` while uninstalling `com.google.Chrome`) is that app's data
and is left out, with the reason in the diagnostics. App-group names compare case-insensitively.
Beyond `~/Library`, it previews **system-level** leftovers (`/Library` data and caches, launch
daemons, privileged helpers, receipts, `/Users/Shared`) — read-only, marked `location: .system`,
never preselected and rejected by the uninstall scope, so they cannot reach the funnel.

`AppScanDiagnostics` records what the scan read (per library folder: listed N, missing, denied,
behind a symlink) and every candidate that matched by name but was dropped, with the reason. A
folder the system refuses to list is reported as unreadable instead of silently treated as absent.
The uninstall page shows a banner with a "Copy Diagnostics" button when only the app was found or
some candidates were skipped.

## Disk tools

The disk page is also where users act on the disk. `DiskToolsController` (`OpenStatsUI/State`) fronts four
pieces of read-mostly logic in `Cleaner/DiskTools.swift`, each testable without the UI:

- `SpaceScanner` walks a root (the home folder) once, sums every top-level entry and keeps the largest files;
  packages (`.app`, `.photoslibrary`, …) count as one item. It never follows symlinks and skips folders it
  cannot read. `canTrash` allows Trash only for files inside the home folder, outside `Library`, with no hidden
  path component, checked again after resolving symlinks; everything else only gets "reveal in Finder".
- `VolumeVerifier` runs `diskutil verifyVolume /` (read-only, no privileges) and reduces the output to OK /
  problem plus the offending line.
- `LocalSnapshots` parses `tmutil listlocalsnapshots /`. Deleting goes through the helper
  (`deleteLocalSnapshots`, protocol version 4) and falls back to a one-off administrator prompt; both paths only
  accept identifiers shaped like `2026-09-14-120000` (`HelperShared/LocalSnapshotCommand`).
- `MountedVolumes` lists browsable non-root volumes; ejecting uses `NSWorkspace`.

## Menu bar, popovers and main window

`MenuBarController` owns the status items. In the *separate* layout every enabled metric gets
its own `NSStatusItem` (created in reverse so they read left to right) and opens a 320 pt
popover for that metric; in the *combined* layout a single item opens `CombinedPopoverView`: a status
overview with one row per enabled metric, plus tabs that switch to each metric's full popover content
(`PopoverDetail`, shared with the separate layout). While a detail tab is showing, `AppModel.openPopover`
is set to that metric so sampling matches the standalone popover.

Popovers are borderless, non-activating `NSPanel`s. The SwiftUI tree is created on open and
destroyed on close, so a hidden popover costs nothing; the main, egress, speed-test and update
windows do the same (`WindowContent`), so a closed window no longer re-evaluates on every sample or
keeps its `.task` loops running. Height comes from measuring a flat,
scroll-free copy of the same view; placeholders keep that height stable until data arrives, and
the window is resized without animation because animating it makes SwiftUI re-lay out every
frame. Charts are drawn with `Shape` paths, one shape per colour, not with Swift Charts and not
with `Canvas`: while any `Canvas` keeps redrawing, SwiftUI holds about 190 MB of graphics memory
regardless of how many or how large the canvases are. Menu-bar images are rasterised to a small
bitmap and only assigned when it differs from the last one, because every assignment redraws the
item on every display's menu bar.

The main window reuses the popover content with `isDetailPage` set (all sections, taller charts)
next to the dashboard and tool pages. Windows use a transparent, full-size-content title bar with
an empty compact toolbar, so the traffic lights sit on the same ground colour as the sidebar and
line up with the 40 pt page header; the app switches to a regular activation policy while a window
is open and back to accessory when all are closed.

## Network details

`NetworkController` runs only while it is needed:

- **Connection probe** — an unprivileged `SOCK_DGRAM` ICMP echo (`ConnectivityProbe`), matched on
  sequence number and a random payload token because the kernel rewrites the identifier. When the
  target is the router, a reply only proves the LAN hop (the router's WAN light can be red while it
  still answers), so each reply is followed by `internetReachable`, which pings two public addresses
  in parallel and passes on the first answer; a router-only reply is recorded as `ProbeSample.State.routerOnly`
  (orange cell). If the gateway address cannot be read, the sample is recorded as failed, not skipped.
- **Interface and addresses** — `SCDynamicStore` / `SCPreferences` for the primary and physical
  service, `getifaddrs` for addresses, CoreWLAN for signal and rate.
- **Public IP** — Cloudflare trace (ipify as fallback) for the address only. Location, ASN, network
  type, native / broadcast and the cleanliness score come from `cleanip.io/cli?json=1`, queried directly
  from each Mac by `PublicAddressLookup`. The endpoint only reports the caller's own address, so
  `AddressFamilyRequest` opens one Network.framework connection pinned to IPv4 and one pinned to IPv6
  (URLSession cannot choose the family) and speaks plain HTTP/1.1 over TLS; when a pinned connection
  cannot be set up it falls back to URLSession and keeps the answer only if it is for the same family.
  If cleanip.io sees a different exit than Cloudflare (split-routing proxies), its address is shown.
  Results are cached per IP for an hour in memory and for a week on disk (failed lookups are not
  cached), and a 429 stops further calls until the next UTC day. Country
  codes are validated before being used as flag file names. `server/geoip/` still holds the systemd
  timer that syncs MaxMind GeoLite2 onto `getopenstats.com/geoip/` (account and key in
  `/etc/openstats/maxmind.env` on the server); the app no longer downloads those files, they are kept
  for other uses.
- **Per-process traffic** — cumulative bytes from `/usr/bin/nettop`, diffed between samples.
- **DNS** — `networksetup -setdnsservers` through the helper (protocol 3), which re-validates the
  service name and every address; without the helper, a one-off administrator prompt runs the
  same fixed command.

## Online updates

### Battery and Bluetooth

The battery item reuses `BatterySampler` (IOKit power sources, sampled every 10 s while the item is in the
menu bar or its popover / page is open). `BatteryPopover` is both the popover and the main-window page
(`DetailPage`). The 24-hour charge curve comes from the history database, which gained a `battery` column
(migrated with `ALTER TABLE` on first open); `HistoryRecorder.loadBattery()` queries it independently of
the History page's range. Macs without a battery show only Bluetooth devices, and the menu-bar segment
falls back to the Bluetooth device with the lowest battery.

`BluetoothController` (`OpenStatsUI/State`) wraps `BluetoothBatteryReader`, which shells out to
`system_profiler` and takes a second or two, so it polls only on demand: every minute while the battery
popover / page or the System page is open, every five minutes when the menu bar needs it (the
low-battery hint or a Mac without a battery), otherwise not at all. `AppModel.bluetoothDemand` derives
that from the same visibility state as `demand`.

`UpdateController` fetches `https://getopenstats.com/download/appcast.json` at launch and daily
(version, date, notes taken from `CHANGELOG.md` by `Scripts/appcast.py`, zip URL, sha256, size). An
update is installed only after: sha256 matches, the zip holds exactly one `.app`, its bundle ID and
version match, `SecStaticCodeCheckValidity` passes with a requirement pinned to the running app's
team, and `spctl --assess` accepts it (notarized). The old bundle is renamed into a same-volume
temporary folder, the new one moved into place (restored on failure; an administrator prompt is
used when the folder is not writable), and a detached shell waits for the process to exit before
reopening the app. After an update the old helper may still be running; the app disconnects, waits
for its 30 s idle exit and checks the protocol version again before asking for a reinstall.

## Account sync

Optional. `SyncController` (in `OpenStatsUI/State`) signs in through `ASWebAuthenticationSession`:
the app generates a PKCE verifier, opens `https://getopenstats.com/api/v1/auth/<provider>/start` with the
S256 challenge, the server runs the GitHub / Google / Apple OAuth flow and redirects to
`openstats://auth/callback?code=…` (the scheme is declared in `project.yml`). The app trades the one-time
code plus the verifier for a bearer token, so a stray app that claims the scheme gains nothing. The token
lives in the login keychain (`KeychainTokenStore`; the file keychain, because ad-hoc dev builds have no
application identifier for the data-protection keychain).

`SettingsDocument` is the synced subset of `AppSettings` — preferences only, never machine state such as the
current tab, helper status, the history database or the GeoIP files. Enums are stored by raw value and every
field is optional, so old and new builds can read each other's documents; `apply` validates each value and
skips what it does not know. `exportDocument()` reads every synced property, which is also how the
controller observes changes (`withObservationTracking`). A change is pushed whole after a 2 s debounce; the
cloud is pulled at launch, on wake, when the account page opens and every hour, and applied when its version differs from the last
one seen. The last pushed or applied document is remembered so applying the cloud copy does not echo back
as a push. On first sign-in: no cloud copy → upload; local still at defaults → apply cloud; both present and
different → the account page asks which to keep. After that the last write wins.

The service (`server/sync`, Go + SQLite, deployed by `server/sync/install.sh` behind Caddy) stores one
document per user with a version counter, links providers that share a verified email into one user, and
deletes everything on `DELETE /account`.

## Power, disk and history

- System, adapter and battery power come from SMC `PSTR`, `PDTR`, `PPBR`. GPU power comes from the
  IOReport *Energy Model* `GPU Energy` counter; CPU energy counters on recent chips barely update,
  so CPU power is not shown. Cluster frequencies are residency-weighted averages of *CPU Complex
  Performance States*, using the `voltage-states*-sram` tables of `pmgr` (Hz on older chips, MHz on
  newer ones). The *Energy Model* subscription is filtered to the single `GPU Energy` channel (the
  whole group has hundreds and cost about 5 ms per sample). IOReport runs at most every 2 s, and
  GPU power, GPU frequency and cluster frequency are each read only while a page shows them.
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
