# Flione — Color System

## 01. Design Direction

Flione uses a **deep-ocean / bioluminescent** visual language.

> **Deep Navy × Electric Blue × Soft Violet × Bright Orange**

The orange is intentionally bright and warm, acting as the visual focus against the cool blue environment.

The icon itself is a **single unified organic silhouette**. The color system should preserve that simplicity rather than introducing too many decorative colors.

---

## 02. Core Palette

| Token | HEX | Usage |
|---|---|---|
| Abyss | `#061426` | Primary app background |
| Deep Ocean | `#0A2A67` | Navigation / elevated background |
| Flione Blue | `#2F6BFF` | Primary brand / active state |
| Ice Blue | `#6AA8FF` | Secondary accent / highlights |
| Aurora Violet | `#A78BFF` | Atmospheric gradient |
| Bright Coral Orange | `#FF8A3D` | Primary warm accent |
| Orange Highlight | `#FFB36B` | Glow / soft highlight |
| Light | `#EAF2FF` | Primary light text |
| White | `#FFFFFF` | High-contrast text |

---

## 03. Accent Orange

### Primary Orange

```text
#FF8A3D
```

Use for:
- Playback progress
- Playing indicator
- Important interactive moments
- Track highlights
- Core glow in the Flione symbol

### Orange Highlight

```text
#FFB36B
```

Use sparingly for:
- Glow center
- Hover highlight
- Soft gradient transition

### Orange Glow

```text
rgba(255, 138, 61, 0.24)
```

Do not make orange the dominant UI color.

---

## 04. Blue System

### Flione Blue

```text
#2F6BFF
```

Use for:
- Buttons
- Links
- Active navigation
- Selected controls
- Focus rings
- Playback controls

### Ice Blue

```text
#6AA8FF
```

Use for:
- Secondary controls
- Artwork glow
- Hover states
- Supporting visual details

---

## 05. Violet

```text
#A78BFF
```

Violet is atmospheric rather than functional.

Use for:
- Artwork gradients
- Ambient lighting
- Icon transitions
- Hero surfaces

Avoid using violet for primary buttons or navigation states.

---

## 06. Background Hierarchy

```text
Abyss
#061426
    ↓
Deep Ocean
#0A2A67
    ↓
Ocean Surface
#102F70
    ↓
Elevated Surface
#143778
    ↓
Flione Blue
#2F6BFF
```

Recommended visual proportion:

```text
60%  Abyss / Deep Navy
20%  Deep Ocean
12%  Blue
5%   Violet
3%   Orange
```

The interface should remain predominantly dark and cool.

---

## 07. Brand Gradient

### Flione Aurora

```text
#2F6BFF
    ↓
#6AA8FF
    ↓
#A78BFF
    ↓
#FF8A3D
```

Orange should appear toward the **visual focal point**, not evenly across the gradient.

Use for:
- App icon
- Hero artwork
- Now Playing artwork glow
- Large atmospheric surfaces

Do not use it on every button or interactive element.

---

## 08. Text Colors

| Token | HEX | Usage |
|---|---|---|
| Primary | `#FFFFFF` | Track / artist / heading |
| Light | `#EAF2FF` | Supporting text |
| Secondary | `#AFC0DF` | Metadata |
| Tertiary | `#7185AA` | Subtle information |
| Disabled | `#4D6085` | Disabled controls |

---

## 09. Surface Colors

| Token | HEX | Usage |
|---|---|---|
| Surface 0 | `#061426` | App background |
| Surface 1 | `#0A1D3C` | Sidebar |
| Surface 2 | `#10264B` | Cards |
| Surface 3 | `#14305A` | Elevated cards |
| Surface Active | `#183D78` | Selected / active surface |

Borders:

```text
#FFFFFF12
```

Hover overlay:

```text
#FFFFFF0A
```

---

## 10. Semantic Colors

| State | Color |
|---|---|
| Success | `#55D6A6` |
| Warning | `#FFB84D` |
| Error | `#FF5F6D` |
| Info | `#6AA8FF` |

Use these only for actual system states.

---

## 11. Icon Color

The Flione symbol is fundamentally monochrome when used as a UI glyph.

### Light Mode

```text
#111827
```

### Dark Mode

```text
#FFFFFF
```

### Active

```text
#2F6BFF
```

### Playback / Special Active

```text
#FF8A3D
```

The Menubar icon remains **single-color** and does not use the brand gradient.

---

## 12. App Icon

The App Icon can use the full color system:

```text
Background
#061426

Blue
#2F6BFF

Ice
#6AA8FF

Violet
#A78BFF

Core
#FF8A3D
```

Visual hierarchy:

```text
Deep Navy
    ↓
Blue
    ↓
Violet
    ↓
Bright Orange
```

Orange is the warm focal point of the symbol.

---

## 13. Color Philosophy

Flione should feel like:

> **a luminous object floating in deep water**

rather than:

> **a blue music dashboard**

Therefore:

- Dark background first
- Blue establishes the environment
- Violet adds depth
- Orange creates life
- White provides clarity

Strongest brand contrast:

```text
#061426 × #FF8A3D
```

Strongest interactive contrast:

```text
#061426 × #2F6BFF
```

---

## 14. Final Brand Palette

```text
FLIONE

#061426  Abyss
#0A2A67  Deep Ocean
#2F6BFF  Flione Blue
#6AA8FF  Ice Blue
#A78BFF  Aurora Violet
#FF8A3D  Bright Coral Orange
#FFB36B  Orange Highlight
#EAF2FF  Light
#FFFFFF  White
```

### Signature combination

```text
████  #061426
████  #2F6BFF
████  #A78BFF
████  #FF8A3D
████  #EAF2FF
```

**Core identity: Deep Ocean + Electric Blue + Bright Orange.**
