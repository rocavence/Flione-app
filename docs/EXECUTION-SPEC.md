# FINIFY — Execution Specification

> **Finify is a premium native macOS music experience for your own Jellyfin library.**

## 0. Product Definition

Finify 是一個 **native macOS Jellyfin Music Client**。

核心定位：

> **Spotify-inspired usability + Sleeve-inspired album immersion + your own Jellyfin library**

Finify 不負責取得音樂、不取代 Jellyfin，也不在第一階段做 AI。

```text
Jellyfin
Library / Streaming
        ↓
Finify
Music Experience
        ↓
Future
Collection / Discovery / Intelligence
```

第一階段只需要證明：

> **Jellyfin 的音樂庫，可以被做成一個真正令人想每天使用的 macOS 音樂產品。**

---

# 1. Product Architecture

Finify 有兩個平級 App Mode：

```text
FINIFY
├── STANDARD MODE
│   ├── Home
│   ├── Search
│   ├── Library
│   ├── Artist
│   ├── Album
│   └── Player
│
└── OVERFLOW MODE
    ├── Album Wall
    ├── Album Flow
    ├── Fullscreen
    └── Immersive Player
```

**Overflow 不是 Album → Fullscreen 的子功能。**

它是一個獨立的 App Entry，可以獨立完成：

* Browse
* Search
* Play
* Queue
* Album navigation
* Artist navigation
* Recently played

---

# 2. Product Roadmap

整體路線只保留一條：

```text
MVP
Core Music Experience
        ↓
V1
Daily Driver
        ↓
V2
Collection Experience
        ↓
V3
Intelligent Discovery
        ↓
Future
Platform Expansion
```

## MVP — Core Music Experience

目標：

> 證明「Jellyfin Music Library → Premium macOS Music Experience」成立。

核心 Loop：

```text
Launch
 ↓
Connect Jellyfin
 ↓
Browse Library
 ↓
Search
 ↓
Open Album
 ↓
Play
 ↓
Queue
 ↓
Standard ↔ Overflow
 ↓
Album Wall
 ↓
Fullscreen
```

### MVP 包含

**System**

* Jellyfin authentication
* Keychain
* Connection / reconnect
* Artwork cache
* Error handling

**Library**

* Artists
* Albums
* Tracks
* Recently Added

**Search**

* Artist
* Album
* Track
* `⌘ K`
* Debounce
* Loading / Empty / Error

**Playback**

* Play / Pause
* Next / Previous
* Seek
* Volume
* Queue
* Shuffle
* Repeat
* Mini Player

**macOS**

* Media Keys
* Now Playing
* Keyboard shortcuts
* Native window
* Native menu

**Standard**

* Home
* Search
* Library
* Artist
* Album
* Player

**Overflow**

* Album Wall
* Small / Medium / Large density
* Trackpad pinch zoom
* Album Flow
* Fullscreen
* Ambient Background
* Currently Playing elevation

### MVP 明確不做

* Playlists
* Favorites
* Lyrics
* Album Flip
* Floating Player
* Always on Top
* Lidarr
* AI
* Offline
* Multi-server
* Mobile
* TV
* Artist Radio
* Smart Radio
* External lyrics
* Advanced metadata editor
* Social features

---

# 3. V1 — Daily Driver

目標：

> 從漂亮的 MVP，變成可以每天使用的完整音樂 App。

加入：

* Playlists
* Favorites
* Lyrics
* Genres
* Recently Played
* Recently Added enhancement
* Library sorting / filtering
* Expanded Player
* Floating Player
* Always on Top
* Better Queue UX
* Playback state persistence
* Album Flip
* Tiny / Huge density
* Advanced gestures
* Enhanced Album Flow
* Recently Played Wall
* Enhanced ambient transitions
* Menu bar controller
* Notifications
* Drag & Drop
* Context menus
* Share
* macOS services where useful
* Enhanced media-key integration

此階段重新評估：

> AVPlayer 是否已足夠，或是否需要 libmpv 支援更完整的 audio behavior。

### V1 Release Goal

V1 才是第一個真正適合公開推廣的版本。

Release quality：

```text
Stable
+
Fast
+
Accessible
+
Polished
+
Distinctive
```

**Product Hunt 應以 V1 為主要公開發布節點，而不是 MVP。**

---

# 4. V2 — Collection Experience

目標：

> 讓 Finify 從「播放自己的音樂」進化成「管理自己的音樂收藏」。

### Lidarr Integration

Finify 不負責下載。

例如：

```text
Album
 ↓
Not in Library
 ↓
Add to Lidarr
 ↓
Lidarr acquires music
 ↓
Jellyfin indexes it
 ↓
Finify displays it
```

### Collection Features

* Missing albums
* Missing discographies
* Unplayed albums
* Recently acquired
* Collection completeness
* Upgrade candidates
* Quality management integration
* Related Artists
* Similar Albums
* Discovery based on metadata
* Listening history
* Favorites

核心 Loop：

```text
Discover
 ↓
Acquire
 ↓
Library
 ↓
Listen
```

---

# 5. V3 — Intelligent Discovery

目標：

> 建立個人化的 Music Discovery Engine。

### AI Discovery

例如：

> Find 20 albums similar to Radiohead that I don't own.

結果提供：

* Album
* Artist
* Year
* Genre
* Why it matches
* Add to Lidarr

### Smart Radio

* Artist Radio
* Album Radio
* Genre Radio
* Mood Radio
* Personal Radio

### Personal Music Loop

```text
Listen
 ↓
Understand Taste
 ↓
Discover
 ↓
Add to Lidarr
 ↓
Download
 ↓
Jellyfin
 ↓
Listen
```

Finify 在這個階段才開始成為：

> **Personal Music Operating Layer**

---

# 6. Future — Platform Expansion

只有 macOS 版本成熟後才考慮：

* iOS / iPadOS
* visionOS
* tvOS
* Offline
* Multi-server

原則：

> **先把單一平台做到成熟，再擴張平台。**

---

# 7. MVP Technical Scope

## Tech Stack

| Layer          | Technology         |
| -------------- | ------------------ |
| Platform       | macOS 14+          |
| UI             | SwiftUI            |
| Language       | Swift              |
| Architecture   | MVVM + Repository  |
| Persistence    | SwiftData          |
| Networking     | URLSession         |
| Authentication | Keychain           |
| Backend        | Jellyfin API       |
| Audio          | AVPlayer           |
| Advanced Audio | libmpv if required |
| Testing        | XCTest             |
| CI             | GitHub Actions     |

---

# 8. Architecture

```text
SwiftUI
   ↓
ViewModel
   ↓
Repository
   ↓
Jellyfin API
```

Player：

```text
SwiftUI
   ↓
PlayerManager
   ↓
AVPlayer
   ↓
Jellyfin Stream
```

規則：

> View 不得直接呼叫 API。

---

# 9. Project Structure

```text
Finify/
├── App/
├── Core/
│   ├── Jellyfin/
│   ├── Audio/
│   ├── Cache/
│   ├── Persistence/
│   └── Platform/
├── Models/
├── DesignSystem/
│   ├── Colors/
│   ├── Typography/
│   ├── Spacing/
│   ├── Radius/
│   ├── Motion/
│   └── Icons/
├── Features/
│   ├── Standard/
│   │   ├── Home/
│   │   ├── Search/
│   │   ├── Library/
│   │   ├── Artist/
│   │   └── Album/
│   └── Overflow/
│       ├── AlbumWall/
│       ├── AlbumFlow/
│       └── Fullscreen/
├── Player/
├── Components/
└── Resources/
```

---

# 10. Design System

所有 UI 必須使用統一 Design System。

## Typography

**SF Pro**

## Spacing

4pt grid：

```text
4 8 12 16 20 24 32 40 48 64 80 96
```

## Radius

```text
4 8 12 16 24 32
```

禁止 Feature 自行建立：

* 新 spacing
* 新 radius
* 新 color
* 新 typography token

---

# 11. Icon System

全 App UI icon 統一使用：

**Reicon**

Repository：

[Reicon — GitHub](https://github.com/dqev/reicon)

規則：

* 不使用 Emoji 作為 UI icon
* 不混用其他 icon library
* 不自行繪製相同用途 SVG
* Outline：一般 UI
* Filled：Active / Selected / Primary

尺寸：

```text
16
20
24
28
32
```

建立唯一 abstraction：

```text
FinifyIcon
```

整合方式：

* Reicon 沒有 Swift 套件，以腳本讀取 `data/icon-data.json`，產生 `Assets.xcassets`（template image、preserve vector data）。
* Reicon 缺少的用途以語意相近的 icon 代替：Queue → `list`、Lyrics → `microphone`。

例外：

* AirPlay / 音訊輸出選擇器使用系統元件 `AVRoutePickerView`，其 icon 由系統提供。

---

# 12. Artwork System

所有 Artwork 統一經過：

```text
ArtworkView
```

負責：

* URL
* Cache
* Placeholder
* Loading
* Error
* Aspect ratio
* Radius
* Shadow
* Hover
* Playing
* Selection

Cache：

```text
Memory
 ↓
Disk
 ↓
Jellyfin
```

禁止：

> 每個 Feature 自己實作 artwork loading。

---

# 13. Standard Mode

## Home

* Recently Played
* Recently Added
* Quick Picks

## Library

* Artists
* Albums
* Songs

## Artist

* Artwork
* Artist name
* Popular tracks
* Albums
* Play
* Shuffle

## Album

* Artwork
* Artist
* Year
* Track list
* Play
* Shuffle
* Queue

## Player

```text
Mini Player          MVP
Expanded Player      V1
Fullscreen Player    MVP 由 Overflow Fullscreen 承擔
```

---

# 14. Search

Shortcut：

```text
⌘ K
```

分類：

```text
Search
├── Artists
├── Albums
├── Songs
└── Playlists
```

MVP 實際搜尋資料：

* Artist
* Album
* Track

Playlist 搜尋於 V1 啟用。

要求：

* Debounce
* Loading
* Empty
* Error
* Retry

目標：

> Server response < 500ms，實際依網路狀況而定。

---

# 15. Playback

建立：

```swift
PlayerManager
QueueManager
```

支援：

* Play
* Pause
* Seek
* Next
* Previous
* Volume
* Queue
* Shuffle
* Repeat

Mini Player：

```text
Artwork
Track
Artist
Previous
Play/Pause
Next
Progress
Volume
```

---

# 16. macOS Integration

## Media Keys

* Play / Pause
* Previous
* Next

## Now Playing

包含：

* Track
* Artist
* Album
* Artwork
* Playback state
* Controls

## Keyboard

```text
Space       Play/Pause
⌘ K         Search
⌘ →         Next
⌘ ←         Previous
Esc         Close overlay
```

---

# 17. Overflow Mode

Overflow 是完整 App Mode。

```text
Finify
├── Standard
└── Overflow
```

不是：

```text
Album → Fullscreen
```

---

# 18. Album Wall

核心：

```text
Album Album Album Album
Album Album Album Album
Album Album Album Album
Album Album Album Album
```

要求：

* Lazy rendering
* Virtualized grid
* Smooth scrolling
* Artwork cache
* Hover state
* Playing state
* Selection state
* Context menu
* Play
* Queue

MVP density：

```text
Small
Medium
Large
```

MVP 支援：

> Trackpad pinch zoom

V1 加入：

```text
Tiny
Huge
```

---

# 19. Album Flow

Cover Flow-style navigation：

```text
Previous
Previous
CURRENT
Next
Next
```

支援：

* Trackpad horizontal swipe
* Keyboard arrows
* Mouse wheel

Current Album：

* Larger scale
* Higher elevation
* Shadow
* Ambient color

---

# 20. Fullscreen

Fullscreen 是完整 immersive environment。

核心：

> Artwork dominates screen.

Controls：

```text
Album
Artist
Progress
Play/Pause
Previous
Next
Queue
```

V1 再加入：

* Lyrics
* Favorite
* Album Flip

Mouse idle：

> Controls fade out.

Mouse movement：

> Controls fade in.

---

# 21. Ambient Background

流程：

```text
Current Artwork
 ↓
Dominant Color Extraction
 ↓
Ambient Background
```

要求：

* GPU friendly
* Subtle blur
* Slow transition
* No distracting animation

Reduce Motion：

> Ambient animation → Static

---

# 22. Performance

目標支援：

> **10,000+ albums**

Overflow 必須使用：

* Lazy grids
* Virtualized rendering
* Thumbnail pipeline
* Memory cache
* Disk cache

禁止：

> 一次載入所有 artwork。

Performance targets：

```text
Startup       < 2 sec
Cached image  ~ instant
Scrolling     60fps target
```

---

# 23. UX Quality

每個 interactive component：

```text
Default
Hover
Pressed
Focused
Disabled
Loading
Error
```

所有 async UI：

```text
Loading
Empty
Error
Retry
```

優先：

> Skeleton / Blur Placeholder

避免：

> Generic spinner everywhere

---

# 24. Accessibility

必須支援：

* VoiceOver
* Keyboard navigation
* Focus state
* Reduce Motion
* Increase Contrast

Reduce Motion：

```text
3D Flip → Crossfade
Parallax → Disabled
Ambient animation → Static
```

---

# 25. Privacy

Finify 預設：

* 不需要 Finify account
* 不需要 cloud account
* 不追蹤音樂內容
* 不廣告
* 不上傳 Library metadata

Jellyfin Server 是主要資料來源。

---

# 26. Quality Bar

每個 Feature 必須同時通過：

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
Error Handling
```

Definition of Done：

> **可以用，而且值得展示。**

---

# 27. Design Direction

整體設計參考三個方向：

```text
Spotify
Information Architecture
        +
Apple
Native macOS interaction
        +
Sleeve
Album immersion
        +
Finify
Original visual identity
```

禁止：

* Spotify clone
* Sleeve clone
* Generic dashboard
* Excessive glassmorphism
* Random gradients
* Mixed icon styles
* Excessive rounded cards
* Gratuitous animation
* Web-dashboard aesthetic

---

# 28. Product Hunt / Awwwards Target

設計目標：

> **每個主要畫面都應該可以直接作為 Product Hunt gallery image。**

品質要求：

* Strong visual hierarchy
* Premium typography
* Consistent iconography
* Distinctive Overflow experience
* Excellent motion
* Native macOS interaction
* Fast response
* Accessibility
* High-quality artwork treatment

公開發布素材：

```text
Product Hunt
├── Hero
├── Gallery
├── Demo Video
└── Feature GIFs

Website
├── Hero
├── Overflow
├── Standard
├── Library
├── Native macOS
└── Download
```

---

# 29. MVP First Vertical Slice

第一條必須完整跑通的 User Journey：

```text
Launch Finify
      ↓
Connect Jellyfin
      ↓
Home
      ↓
Album
      ↓
Play Track
      ↓
Mini Player
      ↓
Enter Overflow
      ↓
Album Wall
      ↓
Select Album
      ↓
Play
      ↓
Fullscreen
      ↓
Exit
```

在這條流程完整以前：

> 不開始 AI、Lidarr、Offline、Mobile 或其他非 MVP 工作。

---

# 30. Initial Task Queue

```text
TASK-001  Create macOS SwiftUI project
TASK-002  Create Finify Design System
TASK-003  Integrate Reicon
TASK-004  Create App navigation
TASK-005  Implement Jellyfin authentication
TASK-006  Implement Library repository
TASK-007  Implement Album Grid
TASK-008  Implement Artist page
TASK-009  Implement Album page
TASK-010  Implement Search
TASK-011  Implement PlayerManager
TASK-012  Implement Queue
TASK-013  Implement Mini Player
TASK-014  Implement macOS Media Keys
TASK-015  Implement Now Playing
TASK-016  Implement Standard Home
TASK-017  Implement Overflow entry
TASK-018  Implement Album Wall
TASK-019  Implement Album Density
TASK-020  Implement Album Flow
TASK-021  Implement Ambient Background
TASK-022  Implement Fullscreen Overflow
TASK-023  Performance optimization
TASK-024  Accessibility
TASK-025  Visual polish
TASK-026  Release build
```

這 26 個 Task 對應 **MVP**，V1–V3 功能不進入這條 MVP queue。

---

# 31. AI Coding Rules

所有 AI Coding Agent 必須遵守：

### Rule 1

**Read existing code before modifying.**

### Rule 2

**Never invent a new Design Token if an existing one exists.**

### Rule 3

**Never introduce another icon library.**

### Rule 4

**Never bypass Repository layer.**

### Rule 5

**Never modify unrelated features.**

### Rule 6

每個 Task：

```text
Build
 ↓
Test
 ↓
Fix
 ↓
Commit
```

### Rule 7

每次只實作一個 vertical slice。

### Rule 8

任何 UI 新增都必須符合 Finify Design System。

---

# 32. MVP Acceptance Criteria

## Functional

* Jellyfin 可以登入
* Library 可以瀏覽
* Search 可用
* Album 可以播放
* Queue 可操作
* Standard Mode 可正常使用
* Overflow Mode 可正常使用

## Native

* Media Keys 正常
* Now Playing 正常
* Keyboard shortcuts 正常
* macOS window behavior 正常

## Visual

* Reicon 一致
* Artwork rendering 一致
* Typography 一致
* Spacing 一致
* Motion 一致
* Standard / Overflow 有明確差異

## Performance

* 10,000 albums 可瀏覽
* Album Wall 使用 virtualized rendering
* Artwork 有 cache
* Scrolling 流暢
* 啟動快速

## Accessibility

* VoiceOver
* Keyboard navigation
* Reduce Motion
* Increase Contrast

## Reliability

* Loading states
* Empty states
* Error states
* Retry
* Crash-free basic flow

---

# 33. Final Product Definition

> **Finify is a premium native macOS music client for Jellyfin, combining Spotify-inspired usability, Sleeve-inspired album immersion, and the freedom of a private music library.**

完整產品路線：

```text
MVP
Core Music Experience
        ↓
V1
Daily Driver
        ↓
V2
Collection Experience
        ↓
V3
Intelligent Discovery
        ↓
Future
Platform Expansion
```

產品發展原則：

> **先把 Music Experience 做對，再做 Daily Driver；再做 Collection；最後才做 Intelligence 與 Platform Expansion。**

---

# 34. Open Questions & Spikes

開始 TASK-002 前必須先處理。

## 待定義

* **Onboarding mode picker**：`FINIFY.md` §51 的「Choose your experience」尚無對應 Task。
* **Overflow Search**：§1 要求 Overflow 可獨立 Search，但 UI 尚未定義。

## Spikes

| Spike | 驗證問題 | 結果影響 |
| ----- | -------- | -------- |
| S1 Reicon → Asset Catalog | Reicon 沒有 Swift 套件，SVG 能否轉成 template image 並支援 Outline / Filled | `FinifyIcon` 實作方式 |
| S2 AVPlayer gapless | Jellyfin FLAC 串流在 AVQueuePlayer 換曲是否有間隙 | libmpv 是否提前到 MVP |
| S3 Album Wall 10k | 10,000 格 + pinch 換密度能否維持 60fps、記憶體有上限 | `LazyVGrid` 或 `NSCollectionView` |

測試環境：實際 Jellyfin library 約 1,700 張專輯；S3 以假資料補到 10,000。

## S3 記憶體策略

Album Wall 採「只準備看得到的東西」：

```text
Metadata（10k 筆，數 MB）   全部常駐
Cell / View                 只存在可視範圍 + 緩衝，離開即回收重用
Decoded image               NSCache，以 byte 設上限（例如 150 MB），LRU 淘汰
Disk cache                  已下載縮圖，以容量上限淘汰
Prefetch                    依捲動方向預載下一屏；離開預載範圍即取消請求
LOD                         依 density 請求對應尺寸縮圖；快速捲動先顯示 BlurHash，停下再補清晰圖
Decode                      ImageIO 在背景 thread downsample，不在 main thread 解碼原圖
```
