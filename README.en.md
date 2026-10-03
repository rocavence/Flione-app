# Flione

[繁體中文](README.md) · **English**

A native macOS music player for Jellyfin. Your music, your server, three ways to browse it.

<p align="center">
  <img src="Flione/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png" width="160" alt="Flione icon">
</p>

## What it does

Flione connects to your own Jellyfin server and gives you three peer ways to browse your library. Switch any time with ⌘1 / ⌘2 / ⌘3 or from the top-right corner:

- **Modern**: a full music app. Home, Library (albums, artists, songs, genres, playlists, favorites), album and artist pages, ⌘K search, the queue, and lyrics. Album pages glow with the colors of the cover, and the translucent sidebar picks up the glow.
- **Infinity**: your whole library as one wall of covers. Pinch to resize; the wall drifts slowly when the pointer is away, or keeps moving with Auto-scroll on. Magic sort rearranges it by color, genre, era, or chance.
- **Cover Flow**: a horizontal stage of covers. Click the center cover to flip it and see the tracks; the background glow follows the center album.

### Playback

- Pressing Play responds instantly: the UI switches to playing right away while tracks load in the background, and you only see a message if loading fails or stalls
- Gapless playback (AVQueuePlayer buffers the next track), shuffle, Smart Shuffle (Jellyfin Instant Mix), repeat
- Media keys, Now Playing in Control Center, Dock menu, menu bar player, floating mini player
- Synced lyrics, with an optional LRCLIB fallback when your server has none (off by default)
- Restores your last queue when you reopen it

### Appearance and language

- 7 color themes: Deep Ocean (default), Silence, Midnight, Aurora, Emerald, Bordeaux, Glacier. They apply to all three views, light and dark; the orange that marks what's playing never changes
- Modern supports light and dark; Infinity and Cover Flow are always dark, each with its own options for rounded covers, drift speed, glow brightness, and more
- English and Traditional Chinese, switchable in Settings; adding a language only takes translations in the String Catalog

## Why it's built this way

- **Talks only to your server**: no account, no analytics, no tracking. Sign-in details live in the Keychain.
- **Native**: SwiftUI with AppKit where it matters. The cover wall and library grid reuse cells with `NSCollectionView`, so libraries with 1,400+ albums scroll smoothly.
- **Covers come first**: colors come from each cover's BlurHash, so glows and Magic sort work without downloading extra images.

Design decisions not covered by the spec are recorded in [`docs/DECISIONS.md`](docs/DECISIONS.md) (Traditional Chinese).

## Install

There are no prebuilt releases yet. Build from source.

Requirements:

- macOS 14 or later (Liquid Glass needs macOS 26)
- Xcode 26 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- A Jellyfin server (tested with 12.1)

```sh
xcodegen generate          # generates Flione.xcodeproj from project.yml
open Flione.xcodeproj      # run the Flione scheme
```

On first launch Flione asks you to connect to Jellyfin. You can enter just a host name (for example `mediabox`); Flione tries `http://mediabox:8096` for you.

`Flione.xcodeproj` is not checked in; change project settings in `project.yml`. Code signing is set in `project.yml`; to build with your own certificate, change `CODE_SIGN_IDENTITY` and `DEVELOPMENT_TEAM`.

<details><summary>Tests</summary>

```sh
xcodebuild -project Flione.xcodeproj -scheme Flione -destination 'platform=macOS' test
```

`RepositoryIntegrationTests` talk to a real server. Create `.secrets/` at the repo root (ignored by git):

```text
.secrets/jellyfin.env   JELLYFIN_URL=, JELLYFIN_USER=, JELLYFIN_PASSWORD=
.secrets/session.env    JELLYFIN_TOKEN=, JELLYFIN_USER_ID=
```

Without `.secrets/`, the integration tests are skipped. Debug builds and test builds from `scripts/build-release.sh` sign in automatically when they find `.secrets/`.

</details>

<details><summary>Project layout</summary>

```text
Flione/
├── App/              entry point, AppEnvironment, menus and shortcuts
├── Core/
│   ├── Jellyfin/     API client, DTOs, MusicRepository
│   ├── Cache/        ImagePipeline (memory + disk), BlurHash
│   ├── Localization/ AppLanguage (interface language)
│   ├── Persistence/  Keychain, library snapshot, favorites, playlists
│   └── Platform/     Now Playing, media keys, keyboard
├── DesignSystem/     colors and themes, type, spacing, radius, motion, shadows, Reicon
├── Components/       ArtworkView, buttons, player bar, queue and lyrics panel, Toast
├── Features/
│   ├── Onboarding/   sign-in, mode picker
│   ├── Standard/     Modern: Home, Library, Album, Artist, Search
│   ├── Overflow/     Infinity (cover wall), Cover Flow, mini player
│   ├── Lyrics/, MenuBar/, Settings/
├── Player/           PlayerManager (AVQueuePlayer), PlayQueue
└── Resources/        Assets, Localizable.xcstrings (translations)
Spikes/               technical spikes (not shipped)
scripts/              Reicon, app icon, and test build scripts
docs/                 spec, roadmap, decision log, brand, spike reports
```

</details>

<details><summary>Icons and translations</summary>

All UI icons come from [Reicon](https://github.com/dqev/reicon). To add one:

1. Add the Reicon name to `scripts/reicon/icons.txt`
2. Run `python3 scripts/reicon/generate.py`
3. Use `FinifyIcon(.name)` in code

The app icon and menu bar icon are generated by `scripts/icon/make-icon.swift` on the macOS icon grid.

Interface translations live in `Flione/Resources/Localizable.xcstrings`. To add a language, add its translations to the catalog and a case to `Core/Localization/AppLanguage.swift`.

</details>

<details><summary>Debug launch arguments</summary>

| Argument | Effect |
| ---- | ---- |
| `-FinifySecrets <folder>` | Read sign-in details from a folder; an empty folder stops at the sign-in screen |
| `-FinifyStartMode standard\|overflow`, `-FinifyOverflowLayout Wall\|Flow` | Start in Modern, Infinity, or Cover Flow |
| `-FinifyMuted YES` | Volume 0, and no playback reporting to Jellyfin |
| `-FinifyDemoPlay "<album>"`, `-FinifyDemoOpen "<album>"` | Play / open that album after launch |
| `-FinifyDemoSearch "<term>"`, `-FinifyDemoSettings YES` | Open search / settings after launch |
| `-FinifyDemoTab library`, `-FinifyDemoSection <section>` | Open a Library section |
| `-FinifyDemoSwitchTo coverFlow\|infinity\|modern` | Switch views after a few seconds (`-FinifyDemoSwitchAfter <seconds>`) |
| `-FinifyDemoHoverAll YES` | Show every Infinity cover in its hover state |
| `-FinifyDemoSeekToEnd <seconds>` | Jump near the end of the first track (to check track changes) |
| `-FinifyLatencyProbe <file>` | Measure the time from pressing Play to UI response, tracks loaded, and audio |
| `-AppleLanguages "(zh-Hant)"` | Launch in a given language |

Settings can also be overridden for one launch, for example `-FinifyTheme Dark`, `-FinifyColorTheme bordeaux`, `-FinifyFlowSettleDim 0.5`.

Performance and stability (build Release with `SWIFT_ACTIVE_COMPILATION_CONDITIONS=BENCHMARK`):

| Argument | Effect |
| ---- | ---- |
| `-FinifyBenchWall <out.json>` | Auto-scroll the cover wall (add `-FinifyBenchTarget library` for the library grid) and record dropped frames and memory |
| `-FinifyLaunchMark <file>` | Record time to first window and to Home loaded |
| `-FinifyGaplessProbe <file>` | Measure gaps between tracks on PlayerManager (with `-FinifyDemoPlay`) |
| `-FinifySoak <file>` | Change tracks 40 times and record memory |

</details>

## Docs (Traditional Chinese)

- [`docs/FINIFY.md`](docs/FINIFY.md): product vision
- [`docs/EXECUTION-SPEC.md`](docs/EXECUTION-SPEC.md): implementation spec (wins on conflicts)
- [`docs/ROADMAP.md`](docs/ROADMAP.md): phases
- [`docs/DECISIONS.md`](docs/DECISIONS.md): decisions and how to change them
- [`docs/brand/`](docs/brand/): brand story and color system
- [`docs/spikes/`](docs/spikes/): spike results

Flione was formerly called Finify; internal type prefixes, the bundle id, settings keys, and launch arguments still use Finify.
