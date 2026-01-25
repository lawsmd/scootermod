# Damage Meters Component

ScooterMod's Damage Meters component provides styling customization for Blizzard's built-in damage meter frames (introduced in The War Within).

## Current Implementation Status

### Completed: TUI Settings Panel (v2)

The v2 settings panel renderer (`ui/v2/SettingsPanel.lua`) is fully implemented with:

**Parent-Level Control:**
- **Style** (emphasized selector) - Default, Bordered, Thin - syncs with Edit Mode

**Collapsible Sections:**

1. **Layout**
   - Frame Width (slider 300-600)
   - Frame Height (slider 120-400)
   - Bar Height (slider 15-40)
   - Padding (slider 2-10)

2. **Bars** (tabbed: Style | Border)
   - *Style tab:* Bar Texture, Foreground Color, Show Class Color, Background Color
   - *Border tab:* Use Custom Border, Border Style, Border Tint, Border Thickness

3. **Icons**
   - Show Spec Icon
   - Icon Border (toggle + color)
   - Icon Background (color)

4. **Text** (tabbed: Title | Names | Numbers)
   - *Title tab:* Text Size, Font, Font Style, Color
   - *Names tab:* Font, Font Style, Font Size, Color
   - *Numbers tab:* Font, Font Style, Font Size, Color

5. **Windows** (tabbed: Border | Background)
   - *Border tab:* Show Border, Border Style, Border Color, Border Thickness
   - *Background tab:* Background Opacity, Custom Backdrop, Backdrop Texture, Backdrop Color

6. **Visibility & Misc**
   - Visibility (Always, In Combat, Hidden)
   - Opacity (slider 50-100%)

### Completed: File Structure

- `core/components/damagemeters.lua` - Component definition with settings and styling logic
- `ui/panel/builders/damagemeters.lua` - Classic panel builder (minimal)
- TOC entries added for both files
- Navigation registered in both v2 and classic panels

### Completed: Edit Mode Integration

The following settings sync bidirectionally with WoW's Edit Mode:

| Setting | Edit Mode Enum | DB Key |
|---------|----------------|--------|
| Style | Style | `style` |
| Frame Width | FrameWidth | `frameWidth` |
| Frame Height | FrameHeight | `frameHeight` |
| Bar Height | BarHeight | `barHeight` |
| Padding | Padding | `padding` |
| Opacity | Transparency | `opacity` |
| Background | BackgroundTransparency | `background` |
| Text Size | TextSize | `textSize` |
| Visibility | Visibility | `visibility` |
| Show Spec Icon | ShowSpecIcon | `showSpecIcon` |
| Show Class Color | ShowClassColor | `showClassColor` |

Edit Mode wiring added to `core/editmode.lua`:
- `ResolveSettingId` handles DamageMeter system
- `SyncComponentSettingToEditMode` writes TUI changes to Edit Mode
- `SyncEditModeSettingToComponent` reads Edit Mode changes to TUI

---

## What's Next

### Phase 1: Core Styling Logic

The component file (`core/components/damagemeters.lua`) needs the actual styling implementation:

1. **Frame Discovery**
   - Hook into `DamageMeter` frame acquisition
   - Support multiple windows (Details, Recount-style panels if exposed)

2. **Entry Styling Hooks**
   - Hook ScrollBox Update for entry frame styling
   - Target frames: `entry.StatusBar`, `entry.IconFrame`, `entry.StatusBar.Name`, `entry.StatusBar.Value`

3. **ApplyStyling Function**
   - Apply bar textures from SharedMedia
   - Apply foreground/background colors (with class color support)
   - Apply custom borders (hide Blizzard's `BackgroundEdge` when custom enabled)
   - Apply font settings to name/value FontStrings
   - Apply window border and backdrop settings

### Phase 2: Polish

1. **Foreground Color Graying**
   - When "Show Class Color" is enabled, gray out the Foreground Color picker
   - Visual feedback that the setting is overridden

2. **Combat Safety**
   - Ensure all styling defers during combat with `C_Timer.After(0, ...)`
   - Use `SaveOnly()` for Edit Mode writes during combat

3. **Multi-Window Support**
   - Detect and style all damage meter windows identically
   - Handle window creation/destruction dynamically

### Phase 3: Classic Panel

The classic panel builder (`ui/panel/builders/damagemeters.lua`) currently has a minimal implementation. If needed, expand to match v2 panel functionality using the existing patterns from `groupframes.lua`.

---

## Technical Notes

### DB Path
```lua
addon.db.profile.components.damageMeter
```

### Component Registration
```lua
addon.Components["damageMeter"]
```

### Key Patterns Used

- **Emphasized Selector**: Parent-level Style uses `emphasized = true` for visual prominence
- **Tabbed Sections Inside Collapsibles**: Bars, Text, and Windows use `inner:AddTabbedSection()` inside `builder:AddCollapsibleSection()`
- **Edit Mode Sync**: Settings marked with `[EM]` in the plan use `syncEditModeSetting()` helper

### Frame Targeting

Blizzard's damage meter frames (TWW+):
```lua
local dmFrame = _G.DamageMeter
local sessionWindow = dmFrame and dmFrame.SessionWindow
local scrollBox = sessionWindow and sessionWindow.ScrollBox
```

Entry frames contain:
- `StatusBar` - The bar itself
- `StatusBar.Name` - Player name FontString
- `StatusBar.Value` - DPS/HPS value FontString
- `StatusBar.Background` - Bar background texture
- `StatusBar.BackgroundEdge` - Blizzard border (hide when custom)
- `IconFrame` - Spec icon container
