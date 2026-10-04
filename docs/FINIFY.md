# FINIFY

> **Your Music. Your Server. Your Experience.**

A premium native macOS music client for Jellyfin.

Finify 將個人 Jellyfin Music Library 轉化為一個具有 **Spotify 使用效率、Apple 原生體驗、Sleeve 視覺沉浸感**的高品質 macOS 音樂產品。

---

# 1. Product Vision

Finify 不是另一個 Jellyfin 管理介面。

Finify 是：

> **一個真正以「音樂」為核心，而不是以「Media Server」為核心的產品。**

使用者不需要知道：

* Jellyfin API
* Library ID
* Media Item
* Server
* Codec
* Metadata Provider

使用者只需要：

> 找音樂 → 播放 → 瀏覽 → 收藏 → 建立 Playlist → 享受音樂。

---

# 2. Product Positioning

```text
Spotify
  │
  ├── Information Architecture
  ├── Search
  ├── Playlist
  ├── Queue
  └── Music-first UX
          +
Sleeve
  │
  ├── Album Wall
  ├── Album Flow
  ├── Immersive Artwork
  ├── Ambient Color
  └── Album-centric interaction
          +
Jellyfin
  │
  ├── Private Library
  ├── Lossless
  ├── Self-hosted
  ├── Metadata
  └── Streaming
          ↓
       FINIFY
```

Finify 的目標不是複製 Spotify 或 Sleeve，而是：

> **重新思考「自己的音樂庫」在 macOS 上應該長什麼樣子。**

---

# 3. Design Ambition

Finify 的 UI / UX 品質目標：

> **Product Hunt launch-ready + Awwwards-level digital product craftsmanship**

這不是指單純做「漂亮」。

而是要求：

* Visual hierarchy
* Typography
* Motion
* Micro-interaction
* Icon consistency
* Artwork handling
* Empty states
* Loading states
* Error states
* Keyboard interaction
* Trackpad interaction
* Window behavior
* Performance
* Accessibility

全部維持同一套 Design System。

Product Hunt 的官方 launch checklist 本身也要求產品有清楚的 thumbnail、gallery、description、video 等呈現，因此 Finify 從第一天就必須把 product presentation 視為產品的一部分。

---

# 4. Core Product Principle

## Music First

Finify 永遠優先呈現：

1. Artwork
2. Artist
3. Album
4. Track
5. Playback

而不是：

1. Server
2. Library
3. Metadata
4. Technical information

---

# 5. Dual App Entry

這是 Finify 最重要的產品架構之一。

Finify 不是：

```text
Main App
  ↓
Fullscreen Player
```

而是：

```text
                         FINIFY
                           │
              ┌────────────┴────────────┐
              │                         │
        STANDARD MODE              OVERFLOW MODE
              │                         │
       Spotify-like UX            Sleeve-inspired UX
```

兩者是**平級 App Entry**。

---

# 6. Standard Mode

Standard Mode 是：

> **每天使用 Finify 的完整音樂 App。**

定位接近：

* Spotify Desktop
* Apple Music
* 高品質 native music player

主要功能：

```text
Home
Search
Library
Artists
Albums
Songs
Playlists
Favorites
Queue
Player
Lyrics
Settings
```

---

# 7. Overflow Mode

## Core Definition

**Overflow 是完整 App Mode，不是 Player Feature。**

它可以直接作為 Finify 啟動後的主要環境。

使用者可以：

* Browse
* Search
* Play
* Queue
* Navigate
* Favorite
* View artist
* View album
* Browse recently played

而不需要離開 Overflow。

---

# 8. Overflow Design Philosophy

Overflow 的核心原則：

> **讓音樂庫成為畫面本身。**

Standard Mode：

```text
Information → Action
```

Overflow：

```text
Artwork → Emotion → Action
```

---

# 9. Overflow — Album Wall

主要入口。

大量專輯封面形成一個可瀏覽的視覺牆。

```text
┌──────────────────────────────────────────┐
│                                          │
│  ▣ ▣ ▣ ▣ ▣ ▣ ▣ ▣ ▣ ▣ ▣ ▣              │
│  ▣ ▣ ▣ ▣ ▣ ▣ ▣ ▣ ▣ ▣ ▣ ▣              │
│  ▣ ▣ ▣ ▣ ▣ ▣ ▣ ▣ ▣ ▣ ▣ ▣              │
│  ▣ ▣ ▣ ▣ ▣ ▣ ▣ ▣ ▣ ▣ ▣ ▣              │
│                                          │
│                         PLAYING          │
│                           ↑              │
│                         ▣ ▣ ▣            │
│                                          │
└──────────────────────────────────────────┘
```

功能：

* Infinite / virtual scrolling
* Artwork density
* Hover
* Click
* Double click
* Drag
* Context menu
* Play
* Add queue
* Favorite

---

# 10. Album Density

支援：

* Tiny
* Small
* Medium
* Large
* Huge

Trackpad pinch：

```text
Pinch in  → more albums
Pinch out → larger albums
```

這是 Overflow 的主要 interaction。

---

# 11. Album Flow

第二種核心 Overflow layout。

```text
             Album
               ↓

        ┌──────────────┐
        │              │
        │    CURRENT   │
        │              │
        └──────────────┘

   Album ←             → Album
```

Trackpad：

```text
← →
```

可以快速在整個 Library 中移動。

---

# 12. Currently Playing Elevation

目前播放的 Album 永遠有視覺優先級。

不是單純顯示：

```text
Playing
```

而是：

```text
Scale
Shadow
Depth
Ambient glow
Contrast
```

讓使用者自然知道：

> **這就是現在正在播放的東西。**

---

# 13. Ambient Artwork

目前 Album artwork → Color extraction。

```text
Artwork
   ↓
Dominant colors
   ↓
Color palette
   ↓
Ambient background
```

背景不是單純：

```text
#000000
```

而是：

```text
Artwork
     ↓
┌──────────────────────┐
│       blurred        │
│      color field     │
│                      │
│     Album artwork    │
│                      │
└──────────────────────┘
```

要求：

* Subtle
* Slow
* Non-distracting
* GPU friendly

---

# 14. Overflow Fullscreen

Fullscreen 不只是：

> Window Zoom 200%

而是完整的 immersive environment。

UI 預設：

```text
Artwork
```

滑鼠移動後：

```text
Artwork

Album
Artist

Progress

Playback controls

Queue / Lyrics
```

滑鼠停止：

```text
Controls → Fade Out
```

---

# 15. Album Flip

Album 可以翻面。

Front：

```text
┌──────────────┐
│              │
│    COVER     │
│              │
└──────────────┘
```

Back：

```text
┌──────────────┐
│ ALBUM TITLE  │
│              │
│ 01 Track     │
│ 02 Track     │
│ 03 Track     │
│ 04 Track     │
│ 05 Track     │
└──────────────┘
```

使用：

* 3D rotation
* Perspective
* Spring animation

---

# 16. Standard Home

Standard Mode：

```text
Good evening

Recently Played
[ Album ][ Album ][ Album ][ Album ]

Recently Added
[ Album ][ Album ][ Album ][ Album ]

Quick Picks
[ Album ][ Album ][ Album ][ Album ]

Favorite Artists
[ Artist ][ Artist ][ Artist ]
```

---

# 17. Search

全域：

```text
⌘ K
```

搜尋：

* Artists
* Albums
* Songs
* Playlists
* Genres

Search UI：

```text
┌─────────────────────────────────────────┐
│ 🔍  Search your music                   │
├─────────────────────────────────────────┤
│                                         │
│ Artists                                 │
│ Radiohead                               │
│                                         │
│ Albums                                  │
│ OK Computer                             │
│ Kid A                                   │
│                                         │
│ Songs                                   │
│ Karma Police                            │
└─────────────────────────────────────────┘
```

---

# 18. Artist

```text
Hero artwork

Radiohead

▶ Play
Shuffle
♡ Favorite

Popular

01 Everything In Its Right Place
02 Karma Police
03 No Surprises

Albums

[ OK Computer ]
[ Kid A ]
[ Amnesiac ]
[ In Rainbows ]
```

---

# 19. Album

```text
Artwork

OK Computer
Radiohead
1997

▶ Play
Shuffle
Add

Tracks

01 Airbag
02 Paranoid Android
03 Subterranean Homesick Alien
...
```

---

# 20. Player

Player 必須同時支援：

### Mini Player

```text
[ART]
Song
Artist

◀  ▶  ▶
━━━━━━
```

### Expanded Player

```text
Large artwork

Song
Artist

━━━━━━●━━━━━━

◀      ▶      ▶

♡   Queue   Lyrics
```

### Fullscreen Player

```text
Artwork dominates entire screen.

Controls appear only when needed.
```

---

# 21. Queue

Spotify-like Queue。

```text
Now Playing

Karma Police

Next

No Surprises
Paranoid Android
Street Spirit
```

支援：

* Drag
* Reorder
* Remove
* Play next
* Clear
* Shuffle

---

# 22. Lyrics

第一階段：

> 使用 Jellyfin 現有 Lyrics。

第二階段：

* Synced lyrics
* Karaoke mode
* Fullscreen lyrics
* Lyrics animation

---

# 23. Playlist

支援：

* Create
* Rename
* Delete
* Add
* Remove
* Reorder
* Duplicate
* Play
* Shuffle

Playlist 優先同步 Jellyfin。

---

# 24. Favorites

支援：

```text
Favorite Artist
Favorite Album
Favorite Track
```

與 Jellyfin 同步。

---

# 25. macOS Native Experience

Finify 必須讓使用者感覺：

> 這是一個 macOS App。

不是：

> 一個包著 Web UI 的網站。

---

## Native Features

### Media Keys

* Play/Pause
* Next
* Previous

### Now Playing

整合 macOS Control Center。

### Keyboard

```text
Space       Play/Pause
⌘ K         Search
⌘ F         Search
⌘ →         Next
⌘ ←         Previous
⌘ Shift F   Favorite
Esc         Close overlay
```

### Menu Bar

```text
Finify

Play / Pause
Previous
Next

Open Finify
Open Queue

Settings

Quit
```

---

# 26. Floating Player

提供獨立 Floating Player。

```text
┌────────────────────────┐
│                        │
│        Artwork         │
│                        │
│     Song / Artist      │
│                        │
│     ◀  ▶  ▶           │
│                        │
└────────────────────────┘
```

選項：

> Always on Top

適合：

> 工作時把 Finify 放在螢幕角落。

---

# 27. Reicon Design System

Finify 全 App icon system 統一採用：

**Reicon**

Reicon 目前提供 2,700+ handcrafted SVG icons、Outline / Filled 兩種 weight，MIT License，可用於 commercial projects。

---

## Icon Rules

### Primary

**Outline**

用於：

* Navigation
* Toolbar
* Secondary action
* Settings

### Filled

用於：

* Active state
* Selected state
* Primary playback
* Favorite
* Current mode

---

# 28. Icon Size System

```text
12px  Micro
16px  Compact
20px  Standard
24px  Primary
28px  Emphasis
32px  Large
```

標準 UI：

**20 / 24px**

Overflow：

**24 / 28 / 32px**

---

# 29. Icon Behavior

禁止：

* 混用不同 icon library
* 自己隨意畫 SVG
* Emoji 當 UI icon
* 混合 stroke style
* 混合 corner radius

所有 UI icon：

> **Reicon only**

Brand mark 除外。

---

# 30. Icon Semantic System

```text
Navigation
home
search
library
music
playlist
heart

Playback
play
pause
skip-forward
skip-back
shuffle
repeat
volume

Content
album
artist
disc
music-note

Actions
plus
minus
more
download
share
edit
delete

Window
fullscreen
minimize
close
expand

System
settings
info
warning
error
check
```

---

# 31. Typography

設計原則：

> Typography 必須比 UI 更安靜。

macOS 優先使用：

**SF Pro**

Display：

* Large
* Semibold

UI：

* Regular
* Medium

Metadata：

* Regular
* Secondary color

避免大量 Bold。

---

# 32. Spacing System

使用 4pt base grid。

```text
4
8
12
16
20
24
32
40
48
64
80
96
```

---

# 33. Radius System

```text
4px   Small
8px   UI
12px  Card
16px  Large
24px  Hero
32px  Floating
```

Artwork 本身：

**0–12px**

不要過度圓角。

---

# 34. Motion Design

Finify 的 motion 必須有目的。

### Micro

```text
120–180ms
```

### UI transition

```text
180–280ms
```

### Artwork transition

```text
300–600ms
```

### Ambient

```text
2–8 seconds
```

避免：

* Bounce everywhere
* Excessive parallax
* Constant animation
* Gratuitous 3D

---

# 35. Interaction Quality

每個 interactive element 必須有：

```text
Default
Hover
Pressed
Focused
Disabled
Loading
Error
```

Hover：

> 不只是改顏色。

可以：

* Scale 1.01
* Artwork elevation
* Background
* Shadow
* Reicon transition

---

# 36. Loading

禁止：

> 一整頁 Spinner。

改用：

**Skeleton UI**

例如：

```text
[████████]

████████████
████████
```

Artwork 可以使用：

> blurred placeholder

---

# 37. Empty State

例如沒有 Playlist：

```text
Your playlists are empty.

Create your first playlist
and make the library yours.

[ Create Playlist ]
```

不能只顯示：

> No items.

---

# 38. Error State

例如 Jellyfin server offline：

```text
Can't reach your music server.

Your cached library is still available.

[ Retry ]
[ Settings ]
```

錯誤訊息必須：

* 說明問題
* 給出下一步
* 不使用 technical jargon

---

# 39. Architecture

```text
                         FINIFY APP
                             │
              ┌──────────────┴──────────────┐
              │                             │
        Standard Mode                Overflow Mode
              │                             │
              └──────────────┬──────────────┘
                             │
                       Domain Layer
                             │
                  ┌──────────┴──────────┐
                  │                     │
             Jellyfin API          Player Engine
                  │                     │
                  │                 AVPlayer
                  │                     │
                  └──────────┬──────────┘
                             │
                         Jellyfin
```

---

# 40. Tech Stack

| Layer          | Technology                |
| -------------- | ------------------------- |
| UI             | SwiftUI                   |
| Language       | Swift                     |
| Architecture   | MVVM + Repository         |
| Persistence    | SwiftData                 |
| Networking     | URLSession                |
| Auth           | Keychain                  |
| Audio MVP      | AVPlayer                  |
| Advanced Audio | libmpv                    |
| Backend        | Jellyfin API              |
| Image          | SwiftUI + custom cache    |
| Testing        | XCTest                    |
| CI             | GitHub Actions            |
| Distribution   | DMG / Sparkle / App Store |

---

# 41. Repository

```text
Finify/
│
├── App/
│   ├── FinifyApp.swift
│   ├── AppState.swift
│   └── AppEnvironment.swift
│
├── Core/
│   ├── Jellyfin/
│   ├── Audio/
│   ├── Cache/
│   ├── Persistence/
│   └── Platform/
│
├── Models/
│
├── DesignSystem/
│   ├── Colors/
│   ├── Typography/
│   ├── Spacing/
│   ├── Radius/
│   ├── Motion/
│   └── Icons/
│
├── Features/
│   ├── Standard/
│   │   ├── Home/
│   │   ├── Search/
│   │   ├── Library/
│   │   ├── Artist/
│   │   ├── Album/
│   │   ├── Playlist/
│   │   └── Favorites/
│   │
│   └── Overflow/
│       ├── AlbumWall/
│       ├── AlbumFlow/
│       ├── Fullscreen/
│       ├── RecentlyPlayed/
│       └── FloatingPlayer/
│
├── Player/
│
├── Components/
│
└── Resources/
```

---

# 42. Design System First

Vibe Coding 前先建立：

```text
FinifyDesignSystem
```

包含：

```text
Colors
Typography
Spacing
Radius
Motion
Buttons
Cards
TrackRows
AlbumCards
ArtistCards
PlayerControls
Reicon wrappers
```

任何 Feature 都不能自行發明 UI。

---

# 43. Reusable Components

至少建立：

```text
FinifyButton
FinifyIconButton
AlbumCard
AlbumGrid
ArtistCard
TrackRow
ArtworkView
PlayerBar
ProgressBar
SearchField
SectionHeader
ContextMenu
Toast
EmptyState
Skeleton
```

---

# 44. Artwork Component

所有 artwork 必須經過：

```text
ArtworkView
```

統一處理：

* Cache
* Placeholder
* Loading
* Error
* Aspect ratio
* Corner radius
* Shadow
* Hover
* Selection
* Playing state

禁止 Feature 自己處理 artwork。

---

# 45. Performance

目標：

### App launch

< 2 sec

### Search

< 500 ms server response

### Cache hit

接近 instant

### Album Wall

即使數千張專輯：

> 仍保持 smooth scrolling。

必須使用：

* Lazy grids
* Virtualized rendering
* Image thumbnail pipeline
* Disk cache
* Memory cache

---

# 46. Music Library Scale

Finify 預設設計：

```text
1,000 albums
5,000 albums
10,000+ albums
```

仍能正常工作。

Overflow 特別需要：

> Virtualized Album Wall

不能一次 render 所有 artwork。

---

# 47. Audio

MVP：

**AVPlayer**

支援：

* FLAC
* MP3
* AAC
* ALAC
* WAV

如果進階需求出現：

```text
AVPlayer
   ↓
limitations
   ↓
libmpv
```

不要在第一版過度工程化。

---

# 48. Jellyfin Integration

Repository abstraction：

```swift
protocol MusicRepository {
    func getArtists()
    func getAlbums()
    func getTracks()
    func search()
    func getLyrics()
}
```

View 不直接呼叫 API。

---

# 49. Authentication

使用：

**macOS Keychain**

保存：

```text
Server URL
User ID
Access Token
```

禁止：

* Password plaintext
* UserDefaults 保存 token
* hardcoded credentials

---

# 50. Local Cache

SwiftData：

```text
Artists
Albums
Tracks
Recently Played
Search History
UI Preferences
```

Image cache：

```text
Memory
   ↓
Disk
   ↓
Jellyfin
```

---

# 51. Startup Experience

第一次開啟：

```text
┌──────────────────────────────────┐
│                                  │
│             FINIFY               │
│                                  │
│     Your music. Your server.     │
│                                  │
│      [ Connect Jellyfin ]        │
│                                  │
└──────────────────────────────────┘
```

成功連線後：

```text
Choose your experience

┌──────────────┐   ┌──────────────┐
│              │   │              │
│  STANDARD    │   │  OVERFLOW    │
│              │   │              │
│  Classic     │   │  Immersive   │
│  Music App   │   │  Album World │
│              │   │              │
└──────────────┘   └──────────────┘
```

可設定：

> Remember my choice

---

# 52. Settings

```text
General
Appearance
Playback
Overflow
Keyboard
Jellyfin
Cache
Advanced
About
```

---

# 53. Appearance

```text
Theme

● System
○ Light
○ Dark

Accent

[ Finify Accent ]

Artwork

● Dynamic
○ Static
```

---

# 54. Overflow Settings

```text
Mode

● Album Wall
○ Album Flow

Album Density

Tiny ─────●──── Huge

Ambient Background
ON

Animation
ON

Auto Hide Controls
ON

Always on Top
OFF
```

---

# 55. Accessibility

必須支援：

* VoiceOver
* Keyboard navigation
* Reduce Motion
* Increase Contrast
* Dynamic Type where applicable
* Focus states
* Tooltip

如果：

> Reduce Motion = ON

則：

```text
3D Flip → Crossfade
Parallax → None
Ambient animation → Static
```

---

# 56. Privacy

Finify 的產品哲學：

> **Your music stays yours.**

Finify 不需要：

* Account
* Analytics by default
* Cloud music
* Advertising
* Tracking

預設：

> Jellyfin server 是唯一的音樂資料來源。

---

# 57. Telemetry

第一版：

**Opt-in only**

如果未來需要：

```text
Anonymous crash reports
Performance metrics
```

必須明確取得使用者同意。

---

# 58. AI — Future

後續階段才加入。

AI 完全在裝置上執行，使用 Apple Foundation Models（Apple Intelligence，macOS 26 以上）。不使用雲端服務，聆聽資料不會離開這台 Mac。

例如：

> 找一些適合下雨天的爵士。

Finify 只從使用者自己的音樂庫推薦專輯，優先挑很久沒播的。

結果：

```text
Album
Artist
Year
Why this fits
Last played
[ Play ]
```

AI 的目標是讓使用者重新發現自己的收藏。

---

# 59. Product Differentiation

Finify 的真正產品護城河不是：

> Jellyfin API

而是：

### 1. Premium UX

### 2. Overflow

### 3. Album-centric interaction

### 4. macOS native integration

### 5. Personal music discovery

---

# 60. MVP

## P0

* [ ] Jellyfin authentication
* [ ] Home
* [ ] Search
* [ ] Artists
* [ ] Albums
* [ ] Tracks
* [ ] Playback
* [ ] Queue
* [ ] Recently Played
* [ ] Recently Added
* [ ] Mini Player
* [ ] Standard Mode
* [ ] Overflow Mode
* [ ] Album Wall
* [ ] Pinch zoom
* [ ] Album Flow
* [ ] Fullscreen
* [ ] Ambient background
* [ ] Media Keys
* [ ] macOS Now Playing
* [ ] Keyboard shortcuts
* [ ] Reicon system
* [ ] Artwork cache
* [ ] Keychain

---

# 61. P1

* [ ] Playlists
* [ ] Favorites
* [ ] Lyrics
* [ ] Album Flip
* [ ] Floating Player
* [ ] Always on Top
* [ ] Recently Played Wall
* [ ] Advanced animation
* [ ] Smart Home

---

# 62. P2

* [ ] AI Discovery
* [ ] Offline
* [ ] Artist Radio
* [ ] Smart Radio
* [ ] Multi-server
* [ ] Mobile
* [ ] TV

---

# 63. Development Roadmap

## Sprint 01 — Foundation

```text
Xcode
SwiftUI
Architecture
Design System
Reicon
Navigation
Jellyfin Authentication
```

---

## Sprint 02 — Library

```text
Artists
Albums
Tracks
Search
Artwork
Cache
```

---

## Sprint 03 — Playback

```text
Player
Queue
Seek
Volume
Next
Previous
Media Keys
Now Playing
```

---

## Sprint 04 — Standard

```text
Home
Library
Artist
Album
Playlist
Favorites
```

---

## Sprint 05 — Overflow

```text
Album Wall
Virtualization
Album Density
Album Flow
Playing Elevation
Ambient Background
Fullscreen
```

---

## Sprint 06 — Premium Interaction

```text
Motion
Album Flip
Floating Player
Keyboard
Trackpad
Micro interactions
Loading
Empty states
Error states
```

---

## Sprint 07 — Polish

```text
Performance
Accessibility
Animation tuning
Artwork cache
Memory
CPU
GPU
Crash handling
```

---

# 64. Definition of Done

Finify 的功能只有在以下條件全部滿足時才算完成：

```text
Functional
    +
Visual
    +
Motion
    +
Accessibility
    +
Performance
    +
Error handling
```

不能：

> 「功能有了，所以完成。」

而必須：

> **「功能完成，而且值得被展示。」**

---

# 65. Product Hunt Readiness

Product Hunt 官方建議產品本身應該已經可以被使用，而不是只有 signup landing page；官方也建議準備 thumbnail、gallery、video 與清楚的 value proposition。

Finify Launch Package：

```text
01 Product Website
02 Product Hunt Page
03 App Icon
04 Product Screenshots
05 Overflow Video
06 30–60 sec Product Demo
07 GIFs
08 Feature Gallery
09 README
10 Documentation
```

---

# 66. Product Hunt Hero

第一張圖不要放：

> Dashboard screenshot

而應該直接呈現：

```text
FINIFY

Your Music.
Your Server.
Your Experience.

[ beautiful Overflow screenshot ]
```

Product Hunt 官方要求 thumbnail 並建議 gallery 圖片，因此產品第一印象必須在小尺寸下仍然辨識清楚。

---

# 67. Launch Gallery

推薦 6 張：

### 01

**Finify Overview**

Standard Mode

### 02

**Overflow**

Album Wall

### 03

**Album Flow**

### 04

**Your Library**

Artist / Album

### 05

**Native macOS**

Now Playing / Mini Player

### 06

**Your Music.**

FLAC / Jellyfin / Private Library

---

# 68. Demo Video

第一支影片：

**30–45 秒**

節奏：

```text
0–03
Finify launch

03–08
Overflow

08–14
Album Wall

14–19
Album Flow

19–24
Play

24–29
Standard Mode

29–34
Search

34–39
Now Playing

39–45
Finify logo
```

沒有旁白也可以。

讓 UI 自己說話。

---

# 69. Website

Landing page：

```text
Hero
  ↓
Overflow
  ↓
Standard Mode
  ↓
Jellyfin
  ↓
Lossless
  ↓
macOS Native
  ↓
Screenshots
  ↓
Download
```

第一屏只回答：

> **Why Finify?**

---

# 70. Brand Identity

## Wordmark

```text
FINIFY
```

推薦：

* 全大寫作 marketing
* Title Case 作 App UI
* 自訂微調字距

---

## App Icon

不要使用：

> Jellyfin logo + Spotify logo

也不要直接拼兩個品牌。

Finify 必須有自己的 symbol。

概念方向：

```text
FIN
+
∞ / waveform / record
+
F
```

App icon 要在：

```text
16px
32px
64px
128px
256px
512px
1024px
```

都能辨識。

---

# 71. Color Direction

不要直接使用 Spotify Green。

Finify 建立自己的 Accent。

核心 palette：

```text
Ink
Paper
Surface
Elevated
Muted
Primary
Accent
```

Overflow 可以由 Artwork 動態產生 accent。

Brand color 與 artwork ambient color 必須分離。

---

# 72. Design Quality Bar

每一個畫面都要通過：

### Visual

* Alignment
* Typography
* Contrast
* Spacing
* Composition

### Interaction

* Hover
* Press
* Focus
* Keyboard
* Trackpad

### Motion

* Enter
* Exit
* State transition
* Loading
* Playback

### System

* macOS window
* Menu
* Media keys
* VoiceOver
* Reduce Motion

---

# 73. Anti-patterns

Finify 禁止：

```text
❌ Generic sidebar
❌ Generic card grid
❌ Random gradients
❌ Emoji icons
❌ Mixed icon libraries
❌ Excessive glassmorphism
❌ Every element rounded
❌ Huge shadows
❌ Unnecessary animations
❌ Web dashboard aesthetic
❌ Loading spinner everywhere
❌ Technical error messages
```

---

# 74. Vibe Coding Rules

Finify 適合 AI-assisted development，但 AI 必須被 Design System 約束。

禁止：

> 「Claude，幫我把這頁做漂亮。」

改成：

```text
Implement AlbumCard using Finify Design System.

Constraints:
- Reicon only
- 4pt spacing
- SF Pro
- Existing color tokens
- Existing motion tokens
- Existing artwork component
- No new arbitrary colors
- No new arbitrary radius
- No custom SVG
```

---

# 75. Development Rule

每個 feature：

```text
Design
 ↓
Component
 ↓
Implementation
 ↓
Interaction
 ↓
Animation
 ↓
Accessibility
 ↓
Performance
 ↓
Commit
```

而不是：

```text
Code
 ↓
Code
 ↓
Code
 ↓
最後才整理 UI
```

---

# 76. First Vertical Slice

第一個真正可工作的 Slice：

```text
Launch
 ↓
Connect Jellyfin
 ↓
Home
 ↓
Album
 ↓
Play
 ↓
Mini Player
 ↓
Overflow
 ↓
Album Wall
 ↓
Fullscreen
 ↓
Exit
```

如果這條路徑完整且漂亮：

> Finify 已經是一個真正的產品 prototype。

---

# 77. Final Product Architecture

```text
                              FINIFY
                                │
                ┌───────────────┴───────────────┐
                │                               │
          STANDARD MODE                    OVERFLOW MODE
                │                               │
       Spotify-inspired                   Sleeve-inspired
                │                               │
       ┌────────┼────────┐             ┌────────┼────────┐
       │        │        │             │        │        │
      Home    Search   Library        Wall     Flow   Fullscreen
       │        │        │             │        │        │
       └────────┴────────┘             └────────┴────────┘
                │                               │
                └───────────────┬───────────────┘
                                │
                           PLAYER ENGINE
                                │
                          Jellyfin Server
                                │
                       Personal Music Library
```

---

# 78. Final Product Statement

Finify 的最終目標不是：

> 「一個比較漂亮的 Jellyfin Client。」

而是：

> **「如果 Spotify 是為了串流世界的音樂而設計，那 Finify 就是為了你自己的音樂世界而設計。」**

Jellyfin 負責：

> **Library**

Finify 負責：

> **Experience**

而 Overflow 負責：

> **Emotion**

---

# 79. One-line Definition

> **Finify is a premium native macOS music experience for your own Jellyfin library — combining Spotify-like usability with Sleeve-inspired album immersion.**

---

# 80. Initial Build Target

第一階段只追求一件事：

> **讓使用者第一次打開 Finify，就覺得「這不是另一個 Jellyfin UI」。**

而不是先追求功能數量。

第一個 release 應該只有：

```text
Standard
+
Overflow
+
Playback
+
Search
+
Library
```

但這五件事必須做到：

**fast / beautiful / native / coherent / memorable。**
