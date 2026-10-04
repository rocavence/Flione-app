# FINIFY — Product Roadmap & Execution Specification

> **Your Music. Your Server. Your Experience.**

---

# 1. Product Strategy

Finify 的產品發展分成四個階段：

```text
MVP
 │
 │  證明「Finify 值得存在」
 ▼
V1
 │
 │  成為 Daily Driver
 ▼
V3
 │
 │  用裝置端 AI 重新發現自己的收藏
 ▼
Future
```

核心原則：

> **先把 Playback + Standard + Overflow 做到極致，再擴張功能。**

---

# 2. MVP — Core Experience

## MVP Objective

MVP 不追求完整。

只驗證：

> **Jellyfin 音樂庫能不能被 Finify 轉化成一個高品質 macOS 音樂體驗。**

MVP 必須完成一條完整閉環：

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
Standard Mode
 ↕
Overflow Mode
 ↓
Album Wall
 ↓
Fullscreen
 ↓
Exit
```

---

# 3. MVP Scope

## 3.1 Jellyfin

* [ ] Server connection
* [ ] Authentication
* [ ] Keychain token storage
* [ ] Connection error
* [ ] Reconnect

---

## 3.2 Library

MVP 只需要三層：

```text
Artists
Albums
Tracks
```

* [ ] Artist list
* [ ] Album grid
* [ ] Track list
* [ ] Artist detail
* [ ] Album detail
* [ ] Recently Added

### MVP 不做

* Playlists
* Genres browser
* Advanced metadata editor
* Multi-server

---

# 4. MVP Search

支援：

```text
⌘ K
```

搜尋：

* Artist
* Album
* Track

搜尋流程：

```text
Input
 ↓
Debounce
 ↓
Jellyfin Search
 ↓
Grouped Results
```

### MVP 不做

* Search history
* AI Search
* Semantic search
* Recommendation

---

# 5. MVP Playback

這是 P0。

必須支援：

* Play
* Pause
* Next
* Previous
* Seek
* Volume
* Queue
* Shuffle
* Repeat

Player：

```text
Mini Player
+
Queue
```

### MVP Audio

先使用：

**AVPlayer**

不要在 MVP 引入 libmpv。

只有在實際測試發現：

* codec
* gapless
* ReplayGain
* Hi-Res
* FLAC

需求不足時才引入 libmpv。

---

# 6. MVP macOS Integration

必須：

* [ ] Media Keys
* [ ] macOS Now Playing
* [ ] Keyboard shortcuts
* [ ] Native window
* [ ] Menu commands

Keyboard：

```text
Space       Play/Pause
⌘ K         Search
⌘ →         Next
⌘ ←         Previous
Esc         Close
```

---

# 7. MVP Standard Mode

Standard Mode 只保留：

```text
Home
Search
Library
Artist
Album
Player
```

Home：

```text
Good evening

Recently Played
Recently Added
Quick Picks
```

MVP 不需要：

* Playlist
* Favorites
* Smart Home
* AI recommendation

---

# 8. MVP Overflow Mode

Overflow 是 MVP 的核心差異化。

它必須從 App Entry 進入，而不是 Album → Fullscreen。

```text
FINIFY
│
├── Standard
│
└── Overflow
```

---

# 9. MVP Overflow Features

## Album Wall

* [ ] Virtualized grid
* [ ] Artwork cache
* [ ] Hover
* [ ] Play
* [ ] Add to queue
* [ ] Playing state
* [ ] Context menu

---

## Album Density

MVP：

```text
Small
Medium
Large
```

先不做 Tiny / Huge。

支援：

> Trackpad pinch zoom

---

## Album Flow

MVP：

* [ ] Horizontal navigation
* [ ] Current album focus
* [ ] Previous / next album
* [ ] Keyboard navigation

---

## Fullscreen

MVP：

* [ ] Fullscreen window
* [ ] Album artwork
* [ ] Track
* [ ] Artist
* [ ] Progress
* [ ] Playback controls
* [ ] Auto-hide controls

---

## Ambient Background

MVP：

* [ ] Dominant color extraction
* [ ] Static / slow gradient
* [ ] Smooth transition

不做：

* Complex shaders
* Advanced particle effects
* Reactive visualization

---

# 10. MVP Artwork System

建立唯一：

```text
ArtworkView
```

負責：

* Artwork loading
* Thumbnail
* Cache
* Placeholder
* Error
* Playing state
* Hover
* Aspect ratio

Cache：

```text
Memory
 ↓
Disk
 ↓
Jellyfin
```

---

# 11. MVP Design System

MVP 就建立完整 Design System，不等到 V1 才補。

原因：

> 如果 MVP UI 沒有 Design System，Vibe Coding 很快會產生大量 inconsistent UI。

必須先完成：

```text
Colors
Typography
Spacing
Radius
Motion
Buttons
Icon
Artwork
TrackRow
AlbumCard
Player
```

---

# 12. MVP Icon System

所有 UI icon：

**Reicon**

規則：

* Outline → normal
* Filled → active
* 20 / 24px → standard
* 24 / 28 / 32px → Overflow

禁止：

* Emoji
* SF Symbols 與 Reicon 混用
* Heroicons
* Lucide
* 自製相同用途 SVG

Brand mark 可以例外。

---

# 13. MVP Accessibility

必須：

* VoiceOver
* Keyboard navigation
* Focus state
* Reduce Motion

MVP 不要求完整 accessibility audit，但架構必須從第一天支援。

---

# 14. MVP Performance

目標：

```text
Startup              < 2 sec
Search response      < 500ms target
Cached artwork       Near instant
Album scrolling      60fps target
```

Library：

> 10,000+ albums

必須使用：

* Lazy rendering
* Virtualized grid
* Thumbnail
* Memory cache
* Disk cache

---

# 15. MVP Explicitly Out of Scope

以下全部不進 MVP：

```text
❌ Playlist
❌ Favorites
❌ Lyrics
❌ Album Flip
❌ Floating Player
❌ Always on Top
❌ AI
❌ Offline
❌ Multi-server
❌ Mobile
❌ TV
❌ Artist Radio
❌ Smart Radio
❌ External lyrics
```

這些全部進後續 Roadmap。

---

# 16. MVP Release Definition

MVP 完成的判斷不是功能 checklist，而是：

```text
Connect
 ↓
Browse
 ↓
Search
 ↓
Play
 ↓
Queue
 ↓
Standard
 ↕
Overflow
 ↓
Fullscreen
```

整條流程：

> **無明顯卡頓、視覺一致、可日常使用。**

如果這條流程完成，Finify MVP 成立。

---

# 17. V1 — Daily Driver

MVP 驗證成功後，進入 V1。

目標：

> **從「漂亮 Prototype」變成真正每天可以使用的音樂 App。**

---

# 18. V1 Library

加入：

* [ ] Playlists
* [ ] Favorites
* [ ] Genres
* [ ] Recently Played
* [ ] Recently Added
* [ ] Full Library sorting
* [ ] Filtering

Library：

```text
Artists
Albums
Songs
Genres
Playlists
Favorites
```

---

# 19. V1 Player

加入：

* [ ] Lyrics
* [ ] Expanded Player
* [ ] Floating Player
* [ ] Always on Top
* [ ] Better Queue UX
* [ ] Playback state persistence

---

# 20. V1 Overflow

加入：

* [ ] Album Flip
* [ ] Tiny / Huge density
* [ ] Advanced gestures
* [ ] Better Album Flow
* [ ] Recently Played Wall
* [ ] Enhanced Ambient background
* [ ] Better transitions
* [ ] Fullscreen polish

---

# 21. V1 macOS Integration

加入：

* [ ] Menu Bar mini controller
* [ ] Notifications
* [ ] Better media key handling
* [ ] Share
* [ ] Drag & Drop
* [ ] Context menus
* [ ] macOS Services where useful

---

# 22. V1 Audio

開始評估：

```text
AVPlayer
 ↓
Real-world testing
 ↓
Gapless / FLAC / ReplayGain / Hi-Res
 ↓
Decision
 ↓
AVPlayer OR libmpv
```

不要因為「高品質音樂播放器」而預先增加不必要的 audio engine complexity。

---

# 23. V1 Definition

V1 成為：

> **Daily Driver**

使用者可以：

```text
Find
Play
Browse
Favorite
Playlist
Queue
Lyrics
Listen
```

並且 Standard / Overflow 都可以獨立完成日常使用。

---

# 24. V3 — Intelligent Discovery

V3 才加入 AI。

AI 完全在裝置上執行，使用 Apple Foundation Models（Apple Intelligence，macOS 26 以上）：

* 不使用任何雲端服務
* 聆聽資料不會離開這台 Mac

目標：

> **讓 Finify 從 Music Player 變成 Personal Music Discovery Engine，幫你重新發現自己的收藏。**

---

# 25. V3 AI Discovery

使用者用自然語言問：

> 找一些適合下雨天的爵士。

Finify 只從使用者自己的音樂庫推薦專輯，並優先挑很久沒播的：

```text
User Library
      +
Listening History
      +
Metadata
      +
On-device AI（Foundation Models）
      ↓
Recommendations（只來自 User Library）
```

每個結果：

```text
Album
Artist
Year
Genre
Last played

Why this fits

[ Play ]
```

---

# 26. V3 Rediscovery Loop

完整閉環：

```text
Listen
 ↓
Understand taste
 ↓
Rediscover from your own library
 ↓
Listen
```

Finify 成為：

> **Personal Listening Layer：讓你重新聽見自己的收藏。**

---

# 27. V3 Smart Radio


加入：

* [ ] Artist Radio
* [ ] Album Radio
* [ ] Genre Radio
* [ ] Mood Radio
* [ ] Personal Radio

例如：

```text
Radiohead Radio

Radiohead
↓
Thom Yorke
↓
Massive Attack
↓
Portishead
↓
Mogwai
...
```

---

# 28. Future — Platform Expansion

macOS 穩定後才考慮：

```text
macOS
 ↓
iOS / iPadOS
 ↓
visionOS
 ↓
tvOS
```

但不是直接複製 macOS UI。

共同：

> Finify Design Language

不同：

> Platform-specific interaction

---

# 29. Future — Multi-server

支援：

```text
Home Jellyfin
Work Jellyfin
Remote Jellyfin
```

但只有在：

> Single-server experience 完整成熟

後才加入。

---

# 30. Future — Offline

Offline Music：

```text
Album
 ↓
Download
 ↓
Local encrypted / managed storage
 ↓
Offline Playback
```

這會大幅增加：

* Storage management
* DRM / file handling
* Sync
* Conflict
* Metadata

因此不提前加入。

---

# 31. Roadmap Overview

```text
┌─────────────────────────────────────────────┐
│ MVP                                         │
│ Core Music Experience                       │
│                                             │
│ Jellyfin                                    │
│ Library                                     │
│ Search                                      │
│ Playback                                    │
│ Queue                                       │
│ Standard                                    │
│ Overflow                                    │
│ Album Wall                                  │
│ Album Flow                                  │
│ Fullscreen                                  │
└──────────────────────┬──────────────────────┘
                       ↓
┌─────────────────────────────────────────────┐
│ V1 — DAILY DRIVER                           │
│                                             │
│ Playlists                                   │
│ Favorites                                   │
│ Lyrics                                      │
│ Floating Player                             │
│ Album Flip                                  │
│ Advanced Overflow                           │
│ macOS polish                                │
└──────────────────────┬──────────────────────┘
                       ↓
┌─────────────────────────────────────────────┐
│ V3 — DISCOVERY                              │
│                                             │
│ AI Discovery                                │
│ Smart Radio                                 │
│ Personal recommendations                    │
│ Rediscovery loop                            │
└──────────────────────┬──────────────────────┘
                       ↓
┌─────────────────────────────────────────────┐
│ FUTURE                                      │
│                                             │
│ iOS / iPadOS                                │
│ tvOS / visionOS                             │
│ Offline                                     │
│ Multi-server                                │
└─────────────────────────────────────────────┘
```

---

# 32. Release Strategy

## MVP

定位：

> **Private Beta**

目標：

驗證：

* Jellyfin connection
* Playback
* Standard
* Overflow
* Performance
* Visual identity

---

## V1

定位：

> **Public Release**

目標：

> Daily Driver

這時才開始 Product Hunt Launch。

---

## V3

定位：

> **Personal Music Intelligence**

AI / Discovery 成為主要產品敘事。

---

# 33. Product Hunt Timing

不要在 MVP 階段急著 Product Hunt。

推薦：

```text
MVP
 ↓
Private Beta
 ↓
V1 Polish
 ↓
Performance / Accessibility
 ↓
Landing Page
 ↓
Demo Video
 ↓
Product Hunt
```

原因：

> Product Hunt 帶來的是第一印象與真實使用者，而不是開發回饋本身。

因此公開發布時，Finify 必須已經具有：

* 完整 Standard
* 完整 Overflow
* 穩定 Playback
* 完整 macOS integration
* 完整 Design System
* 高品質 onboarding
* Error / Empty / Loading states

---

# 34. Awwwards-level Quality Gate

不論 MVP / V1 / V3，每個公開畫面都遵守：

```text
Visual
+
Interaction
+
Motion
+
Typography
+
Iconography
+
Performance
+
Accessibility
```

但：

> **MVP 追求「核心流程的精緻度」，不是「功能完整度」。**

---

# 35. Final Scope Alignment

## MVP = Experience

```text
Jellyfin
+
Library
+
Search
+
Playback
+
Standard
+
Overflow
```

## V1 = Daily Driver

```text
MVP
+
Playlist
+
Favorites
+
Lyrics
+
Advanced Player
+
Advanced Overflow
```

## V3 = Intelligence

```text
V1
+
On-device AI
+
Smart Radio
+
Personal Discovery
+
Rediscovery Loop
```

---

# 36. 最終產品演進

```text
                    FINIFY
                       │
              ┌────────┴────────┐
              │                 │
           PLAYBACK          EXPERIENCE
              │                 │
          Jellyfin        Standard / Overflow
              │                 │
              └────────┬────────┘
                       │
                     MVP
                       │
                       ▼
                 DAILY DRIVER
                       │
              Playlist / Lyrics
                       │
                       ▼
                 DISCOVERY
                       │
                 On-device AI
                       │
                       ▼
            PERSONAL MUSIC ECOSYSTEM
```

---

# 37. Execution Priority

任何新功能都先問：

### Q1

是否改善：

> **Play / Browse / Discover / Enjoy？**

如果不是：

> 不進 MVP。

### Q2

是否能讓 Finify 成為更好的 Daily Driver？

如果是：

> V1。

### Q3

是否改善：

> **Music Discovery / Intelligence？**

如果是：

> V3。

---

# 38. Final Rule

Finify 的開發順序永遠是：

> **Experience → Daily Driver → Intelligence**

而不是：

> **Features → Features → Features**

第一個公開版本只需要證明：

> **「我的 Jellyfin 音樂庫，在 Finify 裡值得每天打開。」**
