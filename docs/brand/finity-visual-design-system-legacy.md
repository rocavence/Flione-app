# Finity — macOS Music Player
## Visual Design System

> A modern macOS music player combining Jellyfin and Spotify into one focused listening experience.

---

## 1. Brand Direction

**Product:** Finity  
**Platform:** macOS Desktop  
**Category:** Music Player / Personal Music Library  
**Core integrations:** Jellyfin + Spotify

### Design keywords

- Calm
- Modern
- Musical
- Focused
- Premium
- Atmospheric
- Native macOS feeling

### Visual principle

**Blue first → Violet atmosphere → White highlights**

The interface should feel distinctly blue rather than becoming another generic blue-purple AI product.

---

## 2. Color System

### Primary

| Token | HEX | Usage |
|---|---|---|
| Finity Blue | `#2F6BFF` | Primary / CTA / Active |
| Electric Blue | `#3E7CF6` | Hover / Highlight |
| Sky Blue | `#6AA0FF` | Secondary accent |
| Aurora Violet | `#9B8CFF` | Gradient secondary color |
| Soft Lavender | `#BDBDFF` | Secondary text / Glow |
| Ice | `#EAF0FF` | Highlight text |
| White | `#FFFFFF` | Primary text |

### Dark surfaces

| Token | HEX | Usage |
|---|---|---|
| Ink | `#080D20` | Deepest background |
| Navy | `#0D1633` | Main app background |
| Deep Navy | `#111D40` | Sidebar / panels |
| Blue Glass | `#182956` | Cards / controls |
| Elevated Blue | `#1B2B56` | Elevated cards |

### Text

| Token | HEX | Usage |
|---|---|---|
| Primary | `#FFFFFF` | Main text |
| Secondary | `#AAB7D6` | Supporting text |
| Tertiary | `#7180A5` | Metadata |
| Disabled | `#526080` | Disabled states |

### UI chrome

| Token | Value | Usage |
|---|---|---|
| Divider | `#FFFFFF14` | Separators |
| Glass White | `#FFFFFF0A` | Glass surfaces |
| Glass Highlight | `#FFFFFF12` | Hover / elevated glass |

---

## 3. Finity Aurora Gradient

Primary brand gradient:

```text
#1D4ED8
   ↓
#2F6BFF
   ↓
#6A8DFF
   ↓
#A78BFA
```

Use for:

- App icon
- Hero artwork overlay
- Active states
- Progress bar
- Selected navigation
- Ambient background glow

Avoid using the gradient everywhere. It should remain an accent rather than the default fill.

---

## 4. Color Proportion

Target visual balance:

```text
70%  Deep Blue / Navy
20%  Finity Blue
7%   Violet / Aurora
3%   White / Ice highlights
```

The interface should remain predominantly dark blue.

Purple is atmospheric and supporting, not the primary brand color.

---

## 5. App Icon

The App Icon is the strongest expression of the Finity brand.

### Characteristics

- Rounded macOS app icon shape
- Deep blue → electric blue gradient
- Subtle violet atmosphere
- Translucent ribbon-like abstract `F`
- Glass / gel material
- Soft internal lighting
- Premium but restrained
- No text

### Important distinction

The App Icon **should not be reused directly inside the application UI**.

The UI should use the Finity symbol only where necessary and otherwise remain clean and content-focused.

---

## 6. Menubar Icon

The macOS Menubar icon is a separate UI glyph.

### Characteristics

- Simplified Finity `F`
- No square background
- No app-icon container
- No heavy glass effect
- Small and elegant
- Approximately 16–18 pt visual size
- Designed as a macOS Template Image

### States

| State | Appearance |
|---|---|
| Default — Light | Black / dark gray |
| Default — Dark | White |
| Hover | Soft gray |
| Active | Finity Blue |
| Playing | Finity Blue + minimal playback indicator |

The Menubar icon should behave like a native macOS system icon rather than a miniature application icon.

---

## 7. Application UI

### Overall structure

```text
┌──────────────────────────────────────────────────────┐
│ Traffic lights     Search              Source/User   │
├────────────┬──────────────────────────────┬──────────┤
│            │                              │          │
│ Sidebar    │ Main Content                 │ Now      │
│            │                              │ Playing  │
│ Home       │ Hero                         │          │
│ Search     │                              │ Album    │
│            │ Recently Played              │ Track    │
│ Library    │                              │ Queue    │
│ Artists    │ Made for You                 │          │
│ Albums     │                              │          │
│ Songs      │                              │          │
│ Playlists  │                              │          │
│            │                              │          │
│ Well       │                              │          │
│ Overflow   │                              │          │
├────────────┴──────────────────────────────┴──────────┤
│ Mini Player / Playback Controls                      │
└──────────────────────────────────────────────────────┘
```

---

## 8. Sidebar

Primary navigation:

- Home
- Search

### Music

- Library
- Artists
- Albums
- Songs
- Playlists

### Sources

- Jellyfin
- Spotify

### Smart

- Well
- Overflow
- Recently Added
- Favorites

### Playlists

User-created playlists and smart playlists.

The sidebar should use subdued navy surfaces and only a small amount of blue for the active item.

---

## 9. Home

The Home screen should feel closer to Spotify's content discovery model than a traditional media-library application.

### Hero

Example:

> GOOD EVENING  
> **Music Without Limits.**

Supporting copy:

> Your Jellyfin library and Spotify, together in one seamless experience.

Primary actions:

- Play
- Shuffle

### Content sections

- Recently Played
- Made for You
- Well
- Overflow
- Recently Added
- Favorites
- Recommended

Content should be image-led with minimal UI chrome.

---

## 10. Well

**Well** represents music that belongs to the user's established listening world.

Examples:

- Focus
- Chill Mix
- Night Drive
- Favorites
- Recently Played
- Personal mixes

Visual language:

- Calm
- Familiar
- Personal
- Curated

Well should feel like returning to something familiar.

---

## 11. Overflow

**Overflow** represents discovery beyond the user's immediate library.

Examples:

- New Releases
- Trending
- Discover
- Because You Listened
- Similar Artists
- Spotify recommendations

Visual language:

- Exploratory
- Dynamic
- Slightly more colorful
- More varied artwork

Well = **depth**

Overflow = **breadth**

---

## 12. Jellyfin + Spotify

Finity should make the two sources feel like one music library.

Source filtering:

```text
All    Jellyfin    Spotify
```

The user should not need to understand which backend contains a track unless source information is relevant.

Source badges should remain subtle.

---

## 13. Now Playing

Right-side Now Playing panel:

- Album artwork
- Track title
- Artist
- Favorite
- More actions
- Progress
- Current time
- Duration
- Shuffle
- Previous
- Play / Pause
- Next
- Repeat

Tabs:

- Up Next
- Lyrics
- Related

Queue items should remain visually lightweight.

---

## 14. Bottom Player

Persistent player:

```text
[Artwork] [Track / Artist]

          Shuffle
             Previous
               Play
                Next
              Repeat

             ───────────────

                         Volume
                         Output
```

The playback bar uses **Finity Blue**.

Do not overuse the Aurora gradient inside playback controls.

---

## 15. Glassmorphism

Glass is used as a material, not a decoration.

### Rules

- Dark translucent surfaces
- Very subtle borders
- Low-opacity white highlights
- Background blur
- Soft shadows
- Large corner radii

Avoid:

- Excessive blur
- Excessive glow
- Strong borders
- Heavy neon effects
- Every card looking like glass

---

## 16. Typography

Recommended system:

**SF Pro / SF Pro Display**

Hierarchy:

```text
Hero          36–48 px
Page title    28–32 px
Section       20–24 px
Card title    14–16 px
Metadata      12–13 px
Navigation    13–14 px
```

Typography should be clean and spacious.

---

## 17. Interaction

### Active

Use:

```text
Finity Blue #2F6BFF
```

with subtle surface elevation.

### Hover

Use a translucent white overlay:

```text
#FFFFFF0A
```

### Pressed

Reduce brightness and surface elevation rather than adding another color.

### Playing

The current track can use:

- Finity Blue accent
- Minimal animated playback indicator
- Slightly elevated artwork

---

## 18. Overall Design Rule

Finity should feel like:

**Spotify's discovery model  
+ Jellyfin's ownership  
+ macOS's restraint  
+ Finity's blue atmospheric identity**

The interface should prioritize the music and artwork.

The brand exists to support the experience, not dominate it.
