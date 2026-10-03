# Flione — Three Browsing Modes

Flione 的三種模式都來自 **Clione（海天使）在海洋中的不同狀態與觀看方式**。

不是三套獨立 UI，而是同一個「海洋世界」的三種體驗。

---

## Modern — 海中的日常

**Modern 是 Flione 的基礎模式，也是預設模式。**

海天使生活在廣大的海洋中，Modern 就像是使用者進入這片海洋後的**日常視角**。

所有音樂都以清楚、熟悉的方式呈現：

- Library
- Albums
- Artists
- Playlists
- Search
- Recently Played
- Now Playing

它讓使用者知道自己**現在身在海洋的哪裡，以及正在聽什麼**。

### 核心概念

> **像海天使在海洋中自由漂浮。**

沒有特別目的，也不需要特別探索；只是自然地在自己的音樂世界裡活動。

**Modern = Presence**

---

## Infinity — 無盡的海洋

Infinity 將海洋的尺度放大。

海天使生活在一個幾乎沒有邊界的水下世界，向任何方向游動，都可能遇見新的生命與環境。

Infinity 不以「頁面」作為瀏覽單位，而是讓音樂內容可以持續延伸：

```text
Album
  ↓
Artist
  ↓
Related Album
  ↓
Another Artist
  ↓
Another Album
  ↓
...
```

沒有明確的終點。

它適合：

- 大型 Jellyfin 音樂庫
- 隨機探索
- 發現久未播放的音樂
- Artist → Album → Related 的連續探索
- 沒有明確目的的瀏覽

### 核心概念

> **海天使游向更深、更遠的海域。**

使用者不需要知道下一站是什麼，只需要繼續前進。

**Infinity = Depth**

---

## Cover Flow — 海中的漂浮群落

Cover Flow 來自海洋中漂浮生物的視覺感。

海天使本身就是漂浮於水中的生物；當大量音樂專輯以 Cover 的形式排列時，整個 Library 就像一片**漂浮在深海中的形體群落**。

專輯不再只是列表中的一列資料，而是成為一個個可以接近、辨識、選擇的視覺物件。

```text
        Album
          ↓
     ┌─────────┐
  ┌───────┐ ┌───────┐
  │ Cover │ │ Cover │
  └───────┘ └───────┘
       ←  ●  →
          ↑
       Current
```

使用者透過左右移動，在專輯之間游動。

### 核心概念

> **海天使穿梭在漂浮的音樂群落之間。**

Cover Flow 特別適合：

- Album collectors
- 大型音樂收藏
- 依封面選音樂
- 欣賞 Album Artwork
- 沒有特定歌曲目標的瀏覽

**Cover Flow = Visual**

---

# 三種模式的完整關係

```text
                         FLIONE
                            │
                     ┌──────┴──────┐
                     │   OCEAN     │
                     │   海洋      │
                     └──────┬──────┘
                            │
          ┌─────────────────┼─────────────────┐
          ↓                 ↓                 ↓
       MODERN            INFINITY         COVER FLOW
          │                 │                 │
      日常漂浮           深入海域          漂浮群落
          │                 │                 │
       Presence            Depth            Visual
          │                 │                 │
      使用音樂            探索音樂          欣賞音樂
```

### Modern

**我現在身處這片海洋。**

### Infinity

**我可以一直游向更遠的地方。**

### Cover Flow

**我在漂浮的音樂群落中尋找下一個目標。**

三者共同構成 Flione 的核心：

> **一隻海天使，在自己的音樂海洋裡漂浮、探索與發現。**
