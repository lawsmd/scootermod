local addonName, addon = ...

-- Damage Meters Component
-- Targets Blizzard's Damage Meter frame (DamageMeter, Edit Mode system) and provides:
-- - Edit Mode settings: Style, Frame Width/Height, Bar Height, Padding, Opacity, Background, Text Size, Visibility, Show Spec Icon, Show Class Color
-- - Addon-only settings: Bar textures, fonts, colors, borders, etc.
--
-- Zero-Touch invariant:
-- - If the profile has no persisted table for this component, ApplyStyling must do nothing.
-- - Even if the component DB exists due to Edit Mode changes, addon-only styling should only apply
--   when the specific config tables exist.

local function SafeSetAlpha(frame, alpha)
    if not frame or not frame.SetAlpha then return false end
    return pcall(frame.SetAlpha, frame, alpha)
end

local function SafeSetShown(region, shown)
    if not region then return end
    if region.SetShown then
        pcall(region.SetShown, region, shown and true or false)
        return
    end
    if shown then
        if region.Show then pcall(region.Show, region) end
    else
        if region.Hide then pcall(region.Hide, region) end
    end
end

local function PlayerInCombat()
    if addon and addon.ComponentsUtil and type(addon.ComponentsUtil.PlayerInCombat) == "function" then
        return addon.ComponentsUtil.PlayerInCombat()
    end
    if InCombatLockdown() then
        return true
    end
    return UnitAffectingCombat("player") and true or false
end

local function GetClassColor(classToken)
    if not classToken then return 1, 1, 1, 1 end
    local colors = _G.RAID_CLASS_COLORS
    if colors and colors[classToken] then
        local c = colors[classToken]
        return c.r or 1, c.g or 1, c.b or 1, 1
    end
    return 1, 1, 1, 1
end

-- JiberishIcons Integration Helpers
local function GetJiberishIcons()
    local JIGlobal = _G.ElvUI_JiberishIcons
    if not JIGlobal or type(JIGlobal) ~= "table" then return nil end
    local JI = JIGlobal[1]
    if not JI then return nil end
    return JI
end

local function IsJiberishIconsAvailable()
    local JI = GetJiberishIcons()
    if not JI then return false end
    if not JI.dataHelper or not JI.dataHelper.class then return false end
    if not JI.mergedStylePacks or not JI.mergedStylePacks.class then return false end
    return true
end

local function GetJiberishIconsStyles()
    local JI = GetJiberishIcons()
    if not JI or not JI.mergedStylePacks or not JI.mergedStylePacks.class then return {} end
    local styles = {}
    for key, data in pairs(JI.mergedStylePacks.class.styles or {}) do
        styles[key] = data.name or key
    end
    return styles
end

-- Export to addon namespace for UI access
addon.IsJiberishIconsAvailable = IsJiberishIconsAvailable
addon.GetJiberishIconsStyles = GetJiberishIconsStyles

-- Per-window state storage (avoids tainting Blizzard frames with _Scoot* properties)
local windowState = setmetatable({}, { __mode = "k" })  -- Weak keys for GC

local function getWindowState(sessionWindow)
    if not windowState[sessionWindow] then
        windowState[sessionWindow] = {}
    end
    return windowState[sessionWindow]
end

-- Per-element state (icons, status bars, overlays) — avoids writing _scooter* fields
-- directly onto Blizzard child frames which can propagate taint to the parent system frame.
local elementState = setmetatable({}, { __mode = "k" })

local function getElementState(frame)
    if not elementState[frame] then
        elementState[frame] = {}
    end
    return elementState[frame]
end

-- OPT-18: Style generation counter for dirty-flag caching.
-- Bumped before every full-pass ForEachVisibleEntry call so that subsequent
-- per-entry InitEntry calls with matching classToken can skip redundant work.
local dmStyleGeneration = 0

-- Forward declaration (defined after CreateEntryOverlay, used by hideAllDMOverlays)
local RestoreBlizzardEntryContent

-- Overlay visibility management for UIParent-parented overlays.
-- UIParent-parented overlays don't auto-hide when entries are hidden/recycled
-- by the ScrollBox. Use a per-window "hide then show visible" pattern.
local windowOverlays = setmetatable({}, { __mode = "k" })

-- Strong set of session windows we've styled (for cleanup iteration)
-- windowOverlays/windowState are weak-key tables and can't be reliably iterated.
local knownSessionWindows = {}

local function registerDMOverlay(sessionWindow, overlay)
    if not sessionWindow or not overlay then return end
    if not windowOverlays[sessionWindow] then
        windowOverlays[sessionWindow] = {}
    end
    windowOverlays[sessionWindow][#windowOverlays[sessionWindow] + 1] = overlay
end

local function hideWindowOverlays(sessionWindow)
    local overlays = sessionWindow and windowOverlays[sessionWindow]
    if not overlays then return end
    for _, overlay in ipairs(overlays) do
        overlay:Hide()
    end
end

local function hideAllDMOverlays()
    -- Restore Blizzard entry visuals before hiding overlays
    for _, overlays in pairs(windowOverlays) do
        for _, overlay in ipairs(overlays) do
            if overlay._lastEntry then
                RestoreBlizzardEntryContent(overlay._lastEntry)
            end
            overlay:Hide()
        end
    end
    -- Clip frames, button overlays, title right-click overlays from windowState
    for sessionWindow in pairs(knownSessionWindows) do
        local ws = windowState[sessionWindow]
        if ws then
            if ws.clipFrame then ws.clipFrame:Hide() end
            if ws.buttonOverlays then
                if ws.buttonOverlays.typeArrow then ws.buttonOverlays.typeArrow:Hide() end
                if ws.buttonOverlays.settingsIcon then ws.buttonOverlays.settingsIcon:Hide() end
            end
            if ws.titleRightClickOverlay then ws.titleRightClickOverlay:Hide() end
        end
    end
end

--------------------------------------------------------------------------------
-- Entry Overlay System
-- Creates Scoot-owned overlay frames that visually cover Blizzard entries.
-- All styling calls target overlays, preventing taint on system frame children.
--------------------------------------------------------------------------------

local OVERLAY_DEFAULT_BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local OVERLAY_DEFAULT_FONT = "Fonts\\FRIZQT__.TTF"
local OVERLAY_DEFAULT_FONT_SIZE = 12
local OVERLAY_DEFAULT_FONT_FLAGS = "OUTLINE"

-- Replicate Blizzard's DamageMeterEntryMixin:GetValueText using safe table reads
local function FormatOverlayValueText(entry)
    if not entry then return "" end

    -- Early bail if key values are secret (can't format secret numbers)
    local val = entry.value
    if issecretvalue(val) then return "" end

    local primary, secondary
    local vps = entry.valuePerSecond
    local showVPS = entry.showsValuePerSecondAsPrimary
    if not issecretvalue(vps) and not issecretvalue(showVPS) and vps and showVPS then
        primary = vps
        secondary = val
    else
        primary = val or 0
        secondary = (not issecretvalue(vps)) and vps or nil
    end

    if type(primary) ~= "number" then primary = 0 end
    if secondary and type(secondary) ~= "number" then secondary = nil end

    local abbrev = AbbreviateLargeNumbers or function(n) return tostring(math.floor(n)) end
    local round = Round or function(n) return math.floor(n + 0.5) end

    local ndt = entry.numberDisplayType
    if issecretvalue(ndt) then ndt = 1 end
    ndt = ndt or 1
    local DMN = Enum.DamageMeterNumbers

    if DMN and ndt == DMN.Complete then
        local pct = 0
        local stv = entry.sessionTotalValue
        if not issecretvalue(stv) and type(val) == "number"
           and type(stv) == "number" and stv > 0 then
            pct = round((val / stv) * 100)
        end
        local fmt = _G.DAMAGE_METER_ENTRY_FORMAT_COMPLETE
        if fmt then
            return fmt:format(abbrev(primary), abbrev(secondary or 0), pct)
        end
        return string.format("%s (%s, %d%%)", abbrev(primary), abbrev(secondary or 0), pct)
    elseif DMN and ndt == DMN.Compact then
        local fmt = _G.DAMAGE_METER_ENTRY_FORMAT_COMPACT
        if fmt then
            return fmt:format(abbrev(primary), abbrev(secondary or 0))
        end
        return string.format("%s (%s)", abbrev(primary), abbrev(secondary or 0))
    else
        local fmt = _G.DAMAGE_METER_ENTRY_FORMAT_MINIMAL
        if fmt then
            return fmt:format(abbrev(primary))
        end
        return abbrev(primary)
    end
end

-- Create a per-window clip frame anchored to the ScrollBox
local function CreateClipFrame(sessionWindow)
    local scrollBox = sessionWindow and sessionWindow.ScrollBox
    if not scrollBox then return nil end

    local clipFrame = CreateFrame("Frame", nil, UIParent)
    clipFrame:SetClipsChildren(true)
    clipFrame:SetAllPoints(scrollBox)
    -- Use HIGH strata so overlays (clipFrame children) render above Blizzard's system frame subtree
    clipFrame:SetFrameStrata("HIGH")
    local ok2, sbLevel = pcall(scrollBox.GetFrameLevel, scrollBox)
    if ok2 and type(sbLevel) == "number" then clipFrame:SetFrameLevel(sbLevel) end

    return clipFrame
end

-- Create an entry overlay frame hierarchy
local function CreateEntryOverlay(parentFrame)
    local overlay = CreateFrame("Frame", nil, parentFrame)
    overlay:EnableMouse(false)
    -- Frame level set dynamically in PopulateEntryOverlay per-entry (handles ScrollBox recycling)

    -- Bar overlay (StatusBar) for the fill
    local barOverlay = CreateFrame("StatusBar", nil, overlay)
    barOverlay:SetStatusBarTexture(OVERLAY_DEFAULT_BAR_TEXTURE)

    -- Opaque base behind bar (hides Blizzard StatusBar content)
    local bgBase = barOverlay:CreateTexture(nil, "BACKGROUND", nil, -8)
    bgBase:SetAllPoints(barOverlay)
    bgBase:SetColorTexture(0, 0, 0, 1)

    -- Background texture (behind bar fill, user-configurable alpha)
    local bgTexture = barOverlay:CreateTexture(nil, "BACKGROUND")
    bgTexture:SetAllPoints(barOverlay)
    bgTexture:SetColorTexture(0.1, 0.1, 0.1, 0.8)

    -- BackgroundEdge replica (thin dark border for default style)
    local bgEdge = barOverlay:CreateTexture(nil, "BORDER")
    bgEdge:SetAllPoints(barOverlay)
    bgEdge:SetColorTexture(0, 0, 0, 0.4)
    bgEdge:Hide()

    -- Name FontString (left-aligned on bar)
    local nameFS = barOverlay:CreateFontString(nil, "OVERLAY", nil, 7)
    nameFS:SetFont(OVERLAY_DEFAULT_FONT, OVERLAY_DEFAULT_FONT_SIZE, OVERLAY_DEFAULT_FONT_FLAGS)
    nameFS:SetTextColor(1, 1, 1, 1)
    nameFS:SetJustifyH("LEFT")
    nameFS:SetWordWrap(false)

    -- Value FontString (right-aligned on bar)
    local valueFS = barOverlay:CreateFontString(nil, "OVERLAY", nil, 7)
    valueFS:SetFont(OVERLAY_DEFAULT_FONT, OVERLAY_DEFAULT_FONT_SIZE, OVERLAY_DEFAULT_FONT_FLAGS)
    valueFS:SetTextColor(1, 1, 1, 1)
    valueFS:SetJustifyH("RIGHT")
    valueFS:SetWordWrap(false)

    -- Icon frame (anchored to entry.Icon later)
    local iconFrame = CreateFrame("Frame", nil, overlay)
    local iconTexture = iconFrame:CreateTexture(nil, "ARTWORK")
    iconTexture:SetAllPoints(iconFrame)

    -- Opaque base behind icon (hides Blizzard Icon content)
    local iconBg = iconFrame:CreateTexture(nil, "BACKGROUND", nil, -8)
    iconBg:SetAllPoints(iconFrame)
    iconBg:SetColorTexture(0, 0, 0, 0)
    iconBg:Hide()

    -- Square border edges for the bar (on barOverlay so they render above its fill)
    overlay._squareBorderEdges = {
        top = barOverlay:CreateTexture(nil, "OVERLAY", nil, 5),
        bottom = barOverlay:CreateTexture(nil, "OVERLAY", nil, 5),
        left = barOverlay:CreateTexture(nil, "OVERLAY", nil, 5),
        right = barOverlay:CreateTexture(nil, "OVERLAY", nil, 5),
    }
    for _, edge in pairs(overlay._squareBorderEdges) do
        edge:Hide()
    end

    -- Icon border edges (on iconFrame so they render above its content)
    overlay._iconBorderEdges = {
        top = iconFrame:CreateTexture(nil, "OVERLAY", nil, 5),
        bottom = iconFrame:CreateTexture(nil, "OVERLAY", nil, 5),
        left = iconFrame:CreateTexture(nil, "OVERLAY", nil, 5),
        right = iconFrame:CreateTexture(nil, "OVERLAY", nil, 5),
    }
    for _, edge in pairs(overlay._iconBorderEdges) do
        edge:Hide()
    end

    overlay.bgBase = bgBase
    overlay.barOverlay = barOverlay
    overlay.bgTexture = bgTexture
    overlay.iconBg = iconBg
    overlay.bgEdge = bgEdge
    overlay.nameFS = nameFS
    overlay.valueFS = valueFS
    overlay.iconFrame = iconFrame
    overlay.iconTexture = iconTexture

    return overlay
end

-- Hide Blizzard's visual content on a DM entry (overlay replaces it)
local function HideBlizzardEntryContent(entry)
    if not entry then return end
    -- SetAlpha(0) on parent frame hides all children (Name, Value, Background, fill)
    if entry.StatusBar then pcall(entry.StatusBar.SetAlpha, entry.StatusBar, 0) end
    if entry.Icon then pcall(entry.Icon.SetAlpha, entry.Icon, 0) end
end

-- Restore Blizzard's visual content (cleanup when overlays removed)
RestoreBlizzardEntryContent = function(entry)
    if not entry then return end
    if entry.StatusBar then pcall(entry.StatusBar.SetAlpha, entry.StatusBar, 1) end
    if entry.Icon then pcall(entry.Icon.SetAlpha, entry.Icon, 1) end
end

-- Apply icon to overlay (spec icon or JiberishIcons)
local function ApplyOverlayIcon(overlay, entry, db)
    if not overlay or not entry then return end

    local showIcons = entry.showBarIcons
    if issecretvalue(showIcons) then showIcons = true end
    if db.showSpecIcon == false then showIcons = false end

    if not showIcons then
        overlay.iconFrame:Hide()
        return
    end

    overlay.iconFrame:Show()

    -- JiberishIcons integration
    if db.jiberishIconsEnabled then
        local JI = GetJiberishIcons()
        local classToken = entry.classFilename
        if issecretvalue(classToken) then classToken = nil end
        if JI and classToken then
            local classData = JI.dataHelper and JI.dataHelper.class and JI.dataHelper.class[classToken]
            if classData and classData.texCoords then
                local styleName = db.jiberishIconsStyle or "fabled"
                local mergedStyles = JI.mergedStylePacks and JI.mergedStylePacks.class
                if mergedStyles then
                    local styleData = mergedStyles.styles and mergedStyles.styles[styleName]
                    local basePath = (styleData and styleData.path) or mergedStyles.path
                    if basePath then
                        overlay.iconTexture:SetTexture(basePath .. styleName)
                        overlay.iconTexture:SetTexCoord(unpack(classData.texCoords))
                        overlay.iconTexture:Show()
                        return
                    end
                end
            end
        end
    end

    -- Default: spec icon from entry properties
    local iconID = entry.specIconID
    if issecretvalue(iconID) then iconID = nil end
    if not iconID then
        iconID = entry.iconTexture
        if issecretvalue(iconID) then iconID = nil end
    end
    if iconID then
        overlay.iconTexture:SetTexture(iconID)
        overlay.iconTexture:SetTexCoord(0, 1, 0, 1)
        overlay.iconTexture:Show()
    else
        overlay.iconTexture:Hide()
    end
end

-- Apply bar borders to overlay (all calls on Scoot-owned frames)
local function ApplyOverlayBorders(overlay, db, sessionWindow, isBorderedStyle)
    if not overlay or not db then return end

    -- Bordered edit mode style has Blizzard's border baked into the atlas.
    -- Clear any active Scoot borders and return.
    if isBorderedStyle then
        overlay.bgEdge:Hide()
        for _, edge in pairs(overlay._squareBorderEdges) do edge:Hide() end
        if addon.BarBorders and addon.BarBorders.ClearBarFrame then
            addon.BarBorders.ClearBarFrame(overlay.barOverlay)
        end
        return
    end

    local borderStyle = db.barBorderStyle or "default"
    local barOverlay = overlay.barOverlay

    local thickness = db.barBorderThickness or 1
    local r, g, b, a = 0, 0, 0, 1
    if db.barBorderTintEnabled and db.barBorderTintColor then
        local c = db.barBorderTintColor
        r = c.r or c[1] or 0
        g = c.g or c[2] or 0
        b = c.b or c[3] or 0
        a = c.a or c[4] or 1
    end

    -- bgEdge: visible only for "default" border style
    if borderStyle == "default" then
        overlay.bgEdge:Show()
    else
        overlay.bgEdge:Hide()
    end

    -- Square border edges
    local edges = overlay._squareBorderEdges
    if borderStyle == "square" then
        edges.top:ClearAllPoints()
        edges.top:SetPoint("TOPLEFT", barOverlay, "TOPLEFT", 0, 0)
        edges.top:SetPoint("TOPRIGHT", barOverlay, "TOPRIGHT", 0, 0)
        edges.top:SetHeight(thickness)
        edges.top:SetColorTexture(r, g, b, a)
        edges.top:Show()

        edges.bottom:ClearAllPoints()
        edges.bottom:SetPoint("BOTTOMLEFT", barOverlay, "BOTTOMLEFT", 0, 0)
        edges.bottom:SetPoint("BOTTOMRIGHT", barOverlay, "BOTTOMRIGHT", 0, 0)
        edges.bottom:SetHeight(thickness)
        edges.bottom:SetColorTexture(r, g, b, a)
        edges.bottom:Show()

        edges.left:ClearAllPoints()
        edges.left:SetPoint("TOPLEFT", barOverlay, "TOPLEFT", 0, -thickness)
        edges.left:SetPoint("BOTTOMLEFT", barOverlay, "BOTTOMLEFT", 0, thickness)
        edges.left:SetWidth(thickness)
        edges.left:SetColorTexture(r, g, b, a)
        edges.left:Show()

        edges.right:ClearAllPoints()
        edges.right:SetPoint("TOPRIGHT", barOverlay, "TOPRIGHT", 0, -thickness)
        edges.right:SetPoint("BOTTOMRIGHT", barOverlay, "BOTTOMRIGHT", 0, thickness)
        edges.right:SetWidth(thickness)
        edges.right:SetColorTexture(r, g, b, a)
        edges.right:Show()
    else
        for _, edge in pairs(edges) do
            edge:Hide()
        end
    end

    -- Textured borders (BarBorders system) — holder parented to barOverlay (inherits strata/visibility)
    if borderStyle ~= "default" and borderStyle ~= "none" and borderStyle ~= "square" then
        if addon.BarBorders and addon.BarBorders.ApplyToBarFrame then
            addon.BarBorders.ApplyToBarFrame(barOverlay, borderStyle, {
                thickness = thickness,
                color = { r, g, b, a },
                hiddenEdges = db.barBorderHiddenEdges or {},
            })
        end
    else
        if addon.BarBorders and addon.BarBorders.ClearBarFrame then
            addon.BarBorders.ClearBarFrame(barOverlay)
        end
    end
end

-- Apply icon border to overlay
local function ApplyOverlayIconBorder(overlay, db)
    if not overlay or not db then return end

    local edges = overlay._iconBorderEdges
    local iconFrame = overlay.iconFrame

    if not db.iconBorderEnable or not iconFrame:IsShown() then
        for _, edge in pairs(edges) do
            edge:Hide()
        end
        return
    end

    local thickness = db.iconBorderThickness or 1
    local insetH = tonumber(db.iconBorderInsetH) or 0
    local insetV = tonumber(db.iconBorderInsetV) or 2

    local r, g, b, a = 0, 0, 0, 1
    if db.iconBorderTintEnable and db.iconBorderTintColor then
        local c = db.iconBorderTintColor
        r = c.r or c[1] or 0
        g = c.g or c[2] or 0
        b = c.b or c[3] or 0
        a = c.a or c[4] or 1
    end

    edges.top:ClearAllPoints()
    edges.top:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", insetH, -insetV)
    edges.top:SetPoint("TOPRIGHT", iconFrame, "TOPRIGHT", -insetH, -insetV)
    edges.top:SetHeight(thickness)
    edges.top:SetColorTexture(r, g, b, a)
    edges.top:Show()

    edges.bottom:ClearAllPoints()
    edges.bottom:SetPoint("BOTTOMLEFT", iconFrame, "BOTTOMLEFT", insetH, insetV)
    edges.bottom:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -insetH, insetV)
    edges.bottom:SetHeight(thickness)
    edges.bottom:SetColorTexture(r, g, b, a)
    edges.bottom:Show()

    edges.left:ClearAllPoints()
    edges.left:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", insetH, -(insetV + thickness))
    edges.left:SetPoint("BOTTOMLEFT", iconFrame, "BOTTOMLEFT", insetH, insetV + thickness)
    edges.left:SetWidth(thickness)
    edges.left:SetColorTexture(r, g, b, a)
    edges.left:Show()

    edges.right:ClearAllPoints()
    edges.right:SetPoint("TOPRIGHT", iconFrame, "TOPRIGHT", -insetH, -(insetV + thickness))
    edges.right:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -insetH, insetV + thickness)
    edges.right:SetWidth(thickness)
    edges.right:SetColorTexture(r, g, b, a)
    edges.right:Show()
end

-- Full overlay population (styling + data) — all calls on Scoot-owned frames
local function PopulateEntryOverlay(overlay, entry, db, sessionWindow)
    if not overlay or not entry or not db then return end

    -- Anchor overlay to entry (anchoring TO system frame = safe, no taint)
    overlay:ClearAllPoints()
    overlay:SetAllPoints(entry)

    -- HIGH strata ensures overlays render above Blizzard's MEDIUM-strata system frame subtree
    overlay:SetFrameStrata("HIGH")
    local ok2, entryLevel = pcall(entry.GetFrameLevel, entry)
    if ok2 and type(entryLevel) == "number" then
        overlay:SetFrameLevel(entryLevel + 3)
    end

    -- Hide Blizzard's original content (overlay replaces it visually)
    HideBlizzardEntryContent(entry)
    overlay._lastEntry = entry

    -- Detect entry style (Thin/Bordered/Default) for style-specific layout
    local entryStyle = entry.style
    if issecretvalue(entryStyle) then entryStyle = nil end
    local isThinStyle = (entryStyle == Enum.DamageMeterStyle.Thin)
    local isBorderedStyle = (entryStyle == Enum.DamageMeterStyle.Bordered)

    -- Anchor bar overlay to entry's StatusBar
    local statusBar = entry.StatusBar or entry.bar
    local barAnchor = statusBar or overlay
    overlay.barOverlay:ClearAllPoints()
    if not isThinStyle and not isBorderedStyle then
        -- Default style: inset left edge so bar doesn't butt against transparent icons
        overlay.barOverlay:SetPoint("TOPLEFT", barAnchor, "TOPLEFT", 5, 0)
        overlay.barOverlay:SetPoint("BOTTOMRIGHT", barAnchor, "BOTTOMRIGHT", 0, 0)
    else
        overlay.barOverlay:SetAllPoints(barAnchor)
    end

    -- Anchor icon to entry's Icon frame
    if entry.Icon then
        overlay.iconFrame:ClearAllPoints()
        overlay.iconFrame:SetAllPoints(entry.Icon)
    end

    -- Bar texture
    if db.barTexture and db.barTexture ~= "default" then
        local resolved = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(db.barTexture)
        if resolved then
            overlay.barOverlay:SetStatusBarTexture(resolved)
        end
    else
        overlay.barOverlay:SetStatusBarTexture(OVERLAY_DEFAULT_BAR_TEXTURE)
    end

    -- Bar foreground color
    local showClassColor = db.showClassColor
    local colorMode = db.barForegroundColorMode or "default"
    local classToken = entry.classFilename
    if issecretvalue(classToken) then classToken = nil end

    if showClassColor and classToken then
        local cr, cg, cb = GetClassColor(classToken)
        overlay.barOverlay:SetStatusBarColor(cr, cg, cb, 1)
    elseif colorMode == "custom" and db.barForegroundTint then
        local c = db.barForegroundTint
        overlay.barOverlay:SetStatusBarColor(c.r or c[1] or 1, c.g or c[2] or 0.8, c.b or c[3] or 0, c.a or c[4] or 1)
    else
        -- Default: use entry's status bar color if available
        local sbc = entry.statusBarColor
        if issecretvalue(sbc) then sbc = nil end
        local isClassColor = entry.isClassColorDesired
        if issecretvalue(isClassColor) then isClassColor = nil end
        if sbc and type(sbc) == "table" then
            overlay.barOverlay:SetStatusBarColor(sbc.r or sbc[1] or 0.8, sbc.g or sbc[2] or 0.8, sbc.b or sbc[3] or 0.8, 1)
        elseif isClassColor and classToken then
            local cr, cg, cb = GetClassColor(classToken)
            overlay.barOverlay:SetStatusBarColor(cr, cg, cb, 1)
        else
            overlay.barOverlay:SetStatusBarColor(0.8, 0.8, 0.8, 1)
        end
    end

    -- Bar fill values (StatusBar:SetMinMaxValues/SetValue accept secrets — AllowedWhenTainted)
    pcall(overlay.barOverlay.SetMinMaxValues, overlay.barOverlay, 0, entry.maxValue)
    pcall(overlay.barOverlay.SetValue, overlay.barOverlay, entry.value)

    -- Background color
    local bgColorMode = db.barBackgroundColorMode or "default"
    if bgColorMode == "custom" and db.barBackgroundTint then
        local c = db.barBackgroundTint
        overlay.bgTexture:SetColorTexture(c.r or c[1] or 0.1, c.g or c[2] or 0.1, c.b or c[3] or 0.1, c.a or c[4] or 0.8)
    else
        local bgAlpha = entry.backgroundAlpha
        if issecretvalue(bgAlpha) or type(bgAlpha) ~= "number" then bgAlpha = 0.8 end
        overlay.bgTexture:SetColorTexture(0.1, 0.1, 0.1, bgAlpha)
    end

    -- Bordered style: use Blizzard's bordered atlas (border baked into texture)
    if isBorderedStyle then
        overlay.bgTexture:SetAtlas("UI-HUD-CoolDownManager-Bar-BG")
        overlay.bgTexture:SetAlpha(1)
        overlay.bgTexture:ClearAllPoints()
        overlay.bgTexture:SetPoint("TOPLEFT", overlay.barOverlay, "TOPLEFT", -2, 2)
        overlay.bgTexture:SetPoint("BOTTOMRIGHT", overlay.barOverlay, "BOTTOMRIGHT", 6, -7)
    else
        overlay.bgTexture:ClearAllPoints()
        overlay.bgTexture:SetAllPoints(overlay.barOverlay)
    end

    -- Name text + styling
    local nameText = entry.nameText
    if issecretvalue(nameText) then nameText = nil end
    if not nameText then
        nameText = entry.sourceName
        if issecretvalue(nameText) then nameText = nil end
    end
    if nameText then
        overlay.nameFS:SetText(nameText)
    elseif entry.StatusBar and entry.StatusBar.Name then
        local ok, text = pcall(entry.StatusBar.Name.GetText, entry.StatusBar.Name)
        if ok and text then overlay.nameFS:SetText(text) else overlay.nameFS:SetText("") end
    else
        overlay.nameFS:SetText("")
    end
    if db.textNames then
        local cfg = db.textNames
        if cfg.fontFace and addon and addon.ResolveFontFace then
            local face = addon.ResolveFontFace(cfg.fontFace)
            local baseFontSize = cfg.fontSize or OVERLAY_DEFAULT_FONT_SIZE
            local editModeScale = (db.textSize or 100) / 100
            local addonScale = cfg.scaleMultiplier or 1.0
            overlay.nameFS:SetFont(face, baseFontSize * editModeScale * addonScale, cfg.fontStyle or OVERLAY_DEFAULT_FONT_FLAGS)
        end
        if cfg.colorMode == "custom" and cfg.color then
            local c = cfg.color
            overlay.nameFS:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
        else
            overlay.nameFS:SetTextColor(1, 1, 1, 1)
        end
    end
    -- Value text + styling (must anchor before nameFS since name anchors to value)
    local fmtOk, fmtText = pcall(FormatOverlayValueText, entry)
    if fmtOk and fmtText and fmtText ~= "" then
        overlay.valueFS:SetText(fmtText)
    elseif entry.StatusBar and entry.StatusBar.Value then
        local ok, text = pcall(entry.StatusBar.Value.GetText, entry.StatusBar.Value)
        if ok and text then overlay.valueFS:SetText(text) else overlay.valueFS:SetText("") end
    else
        overlay.valueFS:SetText("")
    end
    if db.textNumbers then
        local cfg = db.textNumbers
        if cfg.fontFace and addon and addon.ResolveFontFace then
            local face = addon.ResolveFontFace(cfg.fontFace)
            local baseFontSize = cfg.fontSize or OVERLAY_DEFAULT_FONT_SIZE
            local editModeScale = (db.textSize or 100) / 100
            local addonScale = cfg.scaleMultiplier or 1.0
            overlay.valueFS:SetFont(face, baseFontSize * editModeScale * addonScale, cfg.fontStyle or OVERLAY_DEFAULT_FONT_FLAGS)
        end
        if cfg.colorMode == "custom" and cfg.color then
            local c = cfg.color
            overlay.valueFS:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
        else
            overlay.valueFS:SetTextColor(1, 1, 1, 1)
        end
    end
    overlay.valueFS:ClearAllPoints()
    if isThinStyle then
        -- Thin: text at top of entry, bar beneath
        overlay.valueFS:SetPoint("TOP", overlay, "TOP", 0, 0)
        overlay.valueFS:SetPoint("RIGHT", overlay, "RIGHT", -8, 0)
    else
        -- Default/Bordered: text vertically centered on bar, nudged down 2px
        overlay.valueFS:SetPoint("RIGHT", overlay.barOverlay, "RIGHT", -4, 0)
        overlay.valueFS:SetPoint("TOP", overlay.barOverlay, "TOP", 0, -2)
        overlay.valueFS:SetPoint("BOTTOM", overlay.barOverlay, "BOTTOM", 0, -2)
    end

    -- Name text anchoring
    overlay.nameFS:ClearAllPoints()
    if isThinStyle then
        overlay.nameFS:SetPoint("TOP", overlay, "TOP", 0, 0)
        overlay.nameFS:SetPoint("LEFT", overlay.barOverlay, "LEFT", 4, 0)
        overlay.nameFS:SetPoint("RIGHT", overlay.valueFS, "LEFT", -4, 0)
    else
        overlay.nameFS:SetPoint("LEFT", overlay.barOverlay, "LEFT", 4, 0)
        overlay.nameFS:SetPoint("RIGHT", overlay.valueFS, "LEFT", -4, 0)
        overlay.nameFS:SetPoint("TOP", overlay.barOverlay, "TOP", 0, -2)
        overlay.nameFS:SetPoint("BOTTOM", overlay.barOverlay, "BOTTOM", 0, -2)
    end

    -- Icon (spec or JiberishIcons)
    ApplyOverlayIcon(overlay, entry, db)

    -- Borders
    ApplyOverlayBorders(overlay, db, sessionWindow, isBorderedStyle)
    ApplyOverlayIconBorder(overlay, db)

    overlay:Show()
end

-- Data-only update for overlays (safe during combat — only updates bar fill + text)
local function UpdateEntryOverlayData(overlay, entry)
    if not overlay or not entry then return end

    -- StatusBar:SetMinMaxValues/SetValue accept secrets (AllowedWhenTainted)
    pcall(overlay.barOverlay.SetMinMaxValues, overlay.barOverlay, 0, entry.maxValue)
    pcall(overlay.barOverlay.SetValue, overlay.barOverlay, entry.value)

    -- Name: forward from Blizzard's FontString (SetText(secret) is allowed and renders correctly)
    if entry.StatusBar and entry.StatusBar.Name then
        local ok, text = pcall(entry.StatusBar.Name.GetText, entry.StatusBar.Name)
        if ok and text then
            overlay.nameFS:SetText(text)
        end
    end

    -- Value: forward from Blizzard's FontString (SetText(secret) is allowed and renders correctly)
    if entry.StatusBar and entry.StatusBar.Value then
        local ok, text = pcall(entry.StatusBar.Value.GetText, entry.StatusBar.Value)
        if ok and text then
            overlay.valueFS:SetText(text)
        end
    end
end

--------------------------------------------------------------------------------
-- Enhanced Title Feature: Display session type alongside meter type
-- e.g., "DPS (Current)", "HPS (Overall)", "Interrupts (Segment 3)"
--------------------------------------------------------------------------------

-- Lookup tables for meter type and session type display names
-- Uses Blizzard's global strings with fallbacks
local METER_TYPE_NAMES = {
    [Enum.DamageMeterType.DamageDone] = DAMAGE_METER_DAMAGE_DONE or "Damage Done",
    [Enum.DamageMeterType.Dps] = DAMAGE_METER_DPS or "DPS",
    [Enum.DamageMeterType.HealingDone] = DAMAGE_METER_HEALING_DONE or "Healing Done",
    [Enum.DamageMeterType.Hps] = DAMAGE_METER_HPS or "HPS",
    [Enum.DamageMeterType.Absorbs] = DAMAGE_METER_ABSORBS or "Absorbs",
    [Enum.DamageMeterType.Interrupts] = DAMAGE_METER_INTERRUPTS or "Interrupts",
    [Enum.DamageMeterType.Dispels] = DAMAGE_METER_DISPELS or "Dispels",
    [Enum.DamageMeterType.DamageTaken] = DAMAGE_METER_DAMAGE_TAKEN or "Damage Taken",
    [Enum.DamageMeterType.AvoidableDamageTaken] = DAMAGE_METER_AVOIDABLE_DAMAGE_TAKEN or "Avoidable Damage",
    [Enum.DamageMeterType.Deaths] = DAMAGE_METER_TYPE_DEATHS or "Deaths",
    [Enum.DamageMeterType.EnemyDamageTaken] = DAMAGE_METER_TYPE_ENEMY_DAMAGE_TAKEN or "Enemy Damage Taken",
}

local SESSION_TYPE_NAMES = {
    [Enum.DamageMeterSessionType.Overall] = "Overall",
    [Enum.DamageMeterSessionType.Current] = "Current",
}

-- Build enhanced title string combining meter type and session info
-- @param sessionWindow - The DamageMeterSessionWindow frame
-- @return string - Enhanced title like "DPS (Current)" or "HPS (Segment 3)"
local function GetEnhancedTitle(sessionWindow)
    if not sessionWindow then return nil end

    local meterType = sessionWindow.damageMeterType
    local sessionType = sessionWindow.sessionType
    local sessionID = sessionWindow.sessionID

    -- Get meter type name
    local typeName = METER_TYPE_NAMES[meterType] or "Unknown"

    -- Get session name based on type or ID
    local sessionName
    if sessionType then
        sessionName = SESSION_TYPE_NAMES[sessionType] or "Unknown"
    elseif sessionID then
        sessionName = "Segment " .. sessionID
    else
        sessionName = "Unknown"
    end

    return typeName .. " (" .. sessionName .. ")"
end

-- Update a single session window's title with enhanced text
-- @param sessionWindow - The DamageMeterSessionWindow frame
local function UpdateEnhancedTitle(sessionWindow)
    if not sessionWindow then return end

    -- Get the component's db to check setting
    local comp = addon.Components and addon.Components["damageMeter"]
    if not comp or not comp.db or not comp.db.showSessionInTitle then return end

    -- Get the TypeName FontString
    local typeNameFS = sessionWindow.DamageMeterTypeDropdown and sessionWindow.DamageMeterTypeDropdown.TypeName
    if not typeNameFS or not typeNameFS.SetText then return end

    local enhancedTitle = GetEnhancedTitle(sessionWindow)
    if enhancedTitle then
        pcall(typeNameFS.SetText, typeNameFS, enhancedTitle)
    end
end

-- Restore a single session window's title to the original (meter type only)
-- @param sessionWindow - The DamageMeterSessionWindow frame
local function RestoreOriginalTitle(sessionWindow)
    if not sessionWindow then return end

    local typeNameFS = sessionWindow.DamageMeterTypeDropdown and sessionWindow.DamageMeterTypeDropdown.TypeName
    if not typeNameFS or not typeNameFS.SetText then return end

    local meterType = sessionWindow.damageMeterType
    local typeName = METER_TYPE_NAMES[meterType] or ""
    pcall(typeNameFS.SetText, typeNameFS, typeName)
end

-- Refresh all visible window titles (enhanced or original based on setting)
local function RefreshAllWindowTitles()
    if not DamageMeter then return end

    local comp = addon.Components and addon.Components["damageMeter"]
    if not comp or not comp.db then return end

    local showEnhanced = comp.db.showSessionInTitle

    -- Iterate through numbered windows
    for i = 1, 10 do
        local windowName = "DamageMeterSessionWindow" .. i
        local window = _G[windowName]
        if window and window:IsShown() then
            if showEnhanced then
                UpdateEnhancedTitle(window)
            else
                RestoreOriginalTitle(window)
            end
        end
    end

    -- Also check DamageMeter.sessionWindows array
    if DamageMeter.sessionWindows then
        for _, window in ipairs(DamageMeter.sessionWindows) do
            if window and window:IsShown() then
                if showEnhanced then
                    UpdateEnhancedTitle(window)
                else
                    RestoreOriginalTitle(window)
                end
            end
        end
    end
end

-- Hook right-click on title text to open meter type dropdown
-- @param sessionWindow - The DamageMeterSessionWindow frame to hook
-- @return boolean - true if hooks were newly installed, false if already hooked
local function HookSessionWindowTitleRightClick(sessionWindow)
    if not sessionWindow then return false end
    local state = getWindowState(sessionWindow)
    if state.titleRightClickHooked then return false end

    local dropdown = sessionWindow.DamageMeterTypeDropdown
    local typeNameFS = dropdown and dropdown.TypeName
    if not typeNameFS then return false end

    state.titleRightClickHooked = true

    -- Create invisible overlay button covering the TypeName FontString
    -- Parented to UIParent (not dropdown) to avoid tainting the dropdown frame.
    -- In 12.0.1, dropdown anchors to SessionTimer TOPRIGHT; tainting it causes
    -- Menu.lua secret value errors when SessionTimer triggers layout recalculation.
    local overlay = CreateFrame("Button", nil, UIParent)
    overlay:SetAllPoints(typeNameFS)         -- anchoring TO Blizzard frames is safe
    overlay:SetFrameStrata("MEDIUM")
    local ok, level = pcall(dropdown.GetFrameLevel, dropdown)
    if ok and type(level) == "number" then
        overlay:SetFrameLevel(level + 10)
    end
    overlay:RegisterForClicks("RightButtonUp")  -- Only right-click
    overlay:EnableMouse(false)  -- Disabled by default

    state.titleRightClickOverlay = overlay

    overlay:SetScript("OnClick", function(self, button)
        if button == "RightButton" and dropdown.OpenMenu and not InCombatLockdown() then
            securecallfunction(dropdown.OpenMenu, dropdown)
        end
    end)

    return true
end

-- Enable/disable the right-click overlay based on setting
local function UpdateTitleRightClickState(sessionWindow, enabled)
    local state = sessionWindow and getWindowState(sessionWindow)
    local overlay = state and state.titleRightClickOverlay
    if overlay then
        overlay:EnableMouse(enabled)
        overlay:SetShown(enabled)    -- hide entirely when not needed (UIParent child)
    end
end

-- Apply styling to a single entry via overlay system
-- Zero direct method calls on Blizzard entry or its children — all styling on Scoot-owned frames
local function ApplySingleEntryStyle(entry, db, sessionWindow)
    if not entry or not db then return end

    -- Get/create clip frame for this session window
    local ws = getWindowState(sessionWindow)
    if not ws.clipFrame then
        ws.clipFrame = CreateClipFrame(sessionWindow)
    end
    if ws.clipFrame then ws.clipFrame:Show() end

    -- Determine parent (clip frame for scroll entries, UIParent for LocalPlayerEntry)
    local isLocalPlayerEntry = (entry == sessionWindow.LocalPlayerEntry)
    local parentFrame = isLocalPlayerEntry and UIParent or ws.clipFrame

    -- Get/create entry overlay
    local elSt = getElementState(entry)
    if not elSt.entryOverlay then
        elSt.entryOverlay = CreateEntryOverlay(parentFrame)
        registerDMOverlay(sessionWindow, elSt.entryOverlay)
    end

    local overlay = elSt.entryOverlay
    local classToken = entry.classFilename
    if issecretvalue(classToken) then classToken = nil end
    classToken = classToken or ""

    -- OPT-18: Skip full restyle if entry hasn't changed since last full pass
    if elSt._cacheGen == dmStyleGeneration and elSt._cacheClass == classToken then
        HideBlizzardEntryContent(entry)
        UpdateEntryOverlayData(overlay, entry)
        overlay:Show()
        return
    end

    PopulateEntryOverlay(overlay, entry, db, sessionWindow)

    elSt._cacheGen = dmStyleGeneration
    elSt._cacheClass = classToken
end

-- Apply window-level styling (border, background)
local function ApplyWindowStyling(window, db)
    if not window or not db then return end

    -- Window border
    if db.windowShowBorder then
        -- Apply border using addon border system if available
        if addon and addon.ApplyFrameBorder then
            local borderOpts = {
                style = db.windowBorderStyle or "default",
                color = db.windowBorderColor,
                thickness = db.windowBorderThickness or 1,
            }
            addon.ApplyFrameBorder(window, borderOpts)
        end
    end

    -- Window background
    if db.windowCustomBackdrop and db.windowBackdropTexture then
        -- Apply custom backdrop
        if window.SetBackdrop and addon and addon.ResolveBackdropTexture then
            local texturePath = addon.ResolveBackdropTexture(db.windowBackdropTexture)
            if texturePath then
                local backdrop = {
                    bgFile = texturePath,
                    edgeFile = nil,
                    tile = true,
                    tileSize = 16,
                    edgeSize = 0,
                    insets = { left = 0, right = 0, top = 0, bottom = 0 },
                }
                pcall(window.SetBackdrop, window, backdrop)

                if db.windowBackdropColor and window.SetBackdropColor then
                    local c = db.windowBackdropColor
                    pcall(window.SetBackdropColor, window, c[1] or 0.1, c[2] or 0.1, c[3] or 0.1, c[4] or 0.9)
                end
            end
        end
    end
end

-- Default color for GameFontNormalMed1 (from Blizzard FontStyles.xml)
-- Gold/yellow color used by default for damage meter title text
local TITLE_DEFAULT_COLOR = { 1.0, 0.82, 0, 1 }

-- Apply title/header text styling to a session window
-- Note: Font styling applies to both TypeName and SessionName
-- Color styling only applies to TypeName (SessionName color is controlled by Button Tint)
local function ApplyTitleStyling(sessionWindow, db)
    if not sessionWindow or not db then return end

    local titleCfg = db.textTitle

    -- Collect ALL title FontStrings for font styling (font face, size, style)
    local allTitleTargets = {}

    -- DamageMeterTypeDropdown.TypeName (meter type: "Damage Done", "DPS", etc.)
    local typeNameFS = sessionWindow.DamageMeterTypeDropdown and sessionWindow.DamageMeterTypeDropdown.TypeName
    if typeNameFS then
        table.insert(allTitleTargets, typeNameFS)
    end

    -- SessionDropdown.SessionName (session letter in button - font only, color via Button Tint)
    local sessionNameFS = sessionWindow.SessionDropdown and sessionWindow.SessionDropdown.SessionName
    if sessionNameFS then
        table.insert(allTitleTargets, sessionNameFS)
    end

    -- Apply font styling (font face, size, style) to ALL title FontStrings
    if titleCfg then
        for _, fs in ipairs(allTitleTargets) do
            if fs and fs.SetFont then
                if titleCfg.fontFace and addon and addon.ResolveFontFace then
                    local face = addon.ResolveFontFace(titleCfg.fontFace)
                    local baseSize = 12
                    local scale = titleCfg.scaleMultiplier or 1.0
                    local size = baseSize * scale
                    local flags = titleCfg.fontStyle or "OUTLINE"
                    pcall(fs.SetFont, fs, face, size, flags)
                end
            end
        end

        -- Apply color ONLY to TypeName (SessionName color is controlled by Button Tint)
        if typeNameFS and typeNameFS.SetTextColor then
            local colorMode = titleCfg.colorMode or "default"
            if colorMode == "custom" and titleCfg.color then
                local c = titleCfg.color
                pcall(typeNameFS.SetTextColor, typeNameFS, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
            elseif colorMode == "default" then
                -- Restore Blizzard's default gold color
                pcall(typeNameFS.SetTextColor, typeNameFS, TITLE_DEFAULT_COLOR[1], TITLE_DEFAULT_COLOR[2], TITLE_DEFAULT_COLOR[3], TITLE_DEFAULT_COLOR[4])
            end
        end
    end

    -- Apply enhanced title if enabled (e.g., "DPS (Current)" instead of just "DPS")
    if db.showSessionInTitle then
        UpdateEnhancedTitle(sessionWindow)
    else
        RestoreOriginalTitle(sessionWindow)
    end

    -- Hook and update right-click behavior
    HookSessionWindowTitleRightClick(sessionWindow)
    UpdateTitleRightClickState(sessionWindow, db.titleTextRightClickMeterType or false)
end

-- Default color for SessionTimer (inherits GameFontNormalMed1 - same gold as title)
local TIMER_DEFAULT_COLOR = { 1.0, 0.82, 0, 1 }

-- Apply session timer text styling (the [00:05:23] timer next to the title)
local function ApplyTimerStyling(sessionWindow, db)
    if not sessionWindow or not db then return end
    local timerFS = sessionWindow.SessionTimer
    if not timerFS or not timerFS.SetFont then return end

    local timerCfg = db.textTimer
    if not timerCfg then return end

    -- Font face and style
    if timerCfg.fontFace and addon and addon.ResolveFontFace then
        local face = addon.ResolveFontFace(timerCfg.fontFace)
        local baseSize = 12
        local flags = timerCfg.fontStyle or "OUTLINE"
        pcall(timerFS.SetFont, timerFS, face, baseSize, flags)
    end

    -- Color
    local colorMode = timerCfg.colorMode or "default"
    if colorMode == "custom" and timerCfg.color then
        local c = timerCfg.color
        pcall(timerFS.SetTextColor, timerFS, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
    elseif colorMode == "default" then
        pcall(timerFS.SetTextColor, timerFS, TIMER_DEFAULT_COLOR[1], TIMER_DEFAULT_COLOR[2], TIMER_DEFAULT_COLOR[3], TIMER_DEFAULT_COLOR[4])
    end
end

-- Apply button tint styling to a session window
-- This tints all button visuals consistently:
-- - DamageMeterTypeDropdown.Arrow (the arrow IS the button)
-- - SessionDropdown.Background + Arrow + SessionName (separate background + icons)
-- - SettingsDropdown.Icon (the gear IS the button)
local function ApplyButtonTintStyling(sessionWindow, db)
    if not sessionWindow or not db then return end

    -- Check if tint mode is custom; if default, restore original colors
    local tintMode = db.buttonTintMode or "default"

    -- Collect ALL button textures (icons and backgrounds)
    local buttonTextures = {}

    -- DamageMeterTypeDropdown.Arrow (the arrow IS the entire button visual)
    if sessionWindow.DamageMeterTypeDropdown and sessionWindow.DamageMeterTypeDropdown.Arrow then
        table.insert(buttonTextures, sessionWindow.DamageMeterTypeDropdown.Arrow)
    end

    -- SessionDropdown - has separate Background + Arrow + SessionName
    if sessionWindow.SessionDropdown then
        -- Background (the circular button background)
        if sessionWindow.SessionDropdown.Background then
            table.insert(buttonTextures, sessionWindow.SessionDropdown.Background)
        end
        -- Arrow (the small arrow below the letter)
        if sessionWindow.SessionDropdown.Arrow then
            table.insert(buttonTextures, sessionWindow.SessionDropdown.Arrow)
        end
    end

    -- SettingsDropdown.Icon (the gear IS the entire button visual)
    if sessionWindow.SettingsDropdown and sessionWindow.SettingsDropdown.Icon then
        table.insert(buttonTextures, sessionWindow.SettingsDropdown.Icon)
    end

    -- SessionDropdown.SessionName (the C/O letter - uses SetTextColor, not SetVertexColor)
    local sessionNameFS = sessionWindow.SessionDropdown and sessionWindow.SessionDropdown.SessionName

    if tintMode == "custom" then
        local tint = db.buttonTint
        if not tint then return end

        local r = tint.r or tint[1] or 1
        local g = tint.g or tint[2] or 1
        local b = tint.b or tint[3] or 1
        local a = tint.a or tint[4] or 1

        -- Apply tint to all button textures
        -- Desaturate first to convert to grayscale, then SetVertexColor tints uniformly
        for _, tex in ipairs(buttonTextures) do
            if tex then
                if tex.SetDesaturated then
                    pcall(tex.SetDesaturated, tex, true)
                end
                if tex.SetVertexColor then
                    pcall(tex.SetVertexColor, tex, r, g, b, a)
                end
            end
        end

        -- Apply same tint color to SessionName text (SetTextColor - absolute)
        if sessionNameFS and sessionNameFS.SetTextColor then
            pcall(sessionNameFS.SetTextColor, sessionNameFS, r, g, b, a)
        end
    else
        -- Default mode: restore original colors and disable desaturation
        for _, tex in ipairs(buttonTextures) do
            if tex then
                if tex.SetDesaturated then
                    pcall(tex.SetDesaturated, tex, false)
                end
                if tex.SetVertexColor then
                    pcall(tex.SetVertexColor, tex, 1, 1, 1, 1)
                end
            end
        end

        -- Restore SessionName to default gold color
        if sessionNameFS and sessionNameFS.SetTextColor then
            pcall(sessionNameFS.SetTextColor, sessionNameFS, TITLE_DEFAULT_COLOR[1], TITLE_DEFAULT_COLOR[2], TITLE_DEFAULT_COLOR[3], TITLE_DEFAULT_COLOR[4])
        end
    end
end

-- Create a Scoot-owned overlay texture for a button icon
-- Uses SetAtlas with built-in WoW graphics for consistent styling
-- @param parent - The frame to create the texture on
-- @param atlasName - The atlas to use
-- @param anchorTo - The Blizzard texture to anchor/size match
-- @param size - {w, h} size for the overlay
-- @param yOffset - Optional vertical offset (positive = up)
local function CreateButtonIconOverlay(parent, atlasName, anchorTo, size, yOffset)
    local overlay = parent:CreateTexture(nil, "OVERLAY", nil, 7)

    -- Position at the same location as the anchor, with optional Y offset
    overlay:ClearAllPoints()
    overlay:SetPoint("CENTER", anchorTo, "CENTER", 0, yOffset or 0)

    -- Set size
    overlay:SetSize(size[1], size[2])

    -- Set the atlas
    overlay:SetAtlas(atlasName, false)  -- false = don't use atlas size, we set it manually

    getElementState(overlay).isScootOverlay = true
    overlay:Hide()  -- Start hidden
    return overlay
end

-- Get or create button overlays for a session window
-- Only creates overlays for Button 1 (type dropdown arrow) and Button 3 (settings gear)
-- Button 2 just needs its background hidden, no overlay replacement
local function GetOrCreateButtonOverlays(sessionWindow)
    local st = getWindowState(sessionWindow)
    if st.buttonOverlays then
        return st.buttonOverlays
    end

    st.buttonOverlays = {}

    -- Button 1: DamageMeterTypeDropdown.Arrow
    -- Replace the full button with just a simple downward arrow (no background)
    -- Atlas: friendslist-categorybutton-arrow-down (icon-only, no button backdrop)
    local typeDropdown = sessionWindow.DamageMeterTypeDropdown
    if typeDropdown and typeDropdown.Arrow then
        st.buttonOverlays.typeArrow = CreateButtonIconOverlay(
            typeDropdown,
            "friendslist-categorybutton-arrow-down",
            typeDropdown.Arrow,
            { 13, 13 },  -- Small arrow size (10% bigger)
            2            -- Nudge up 2 pixels
        )
    end

    -- Button 3: SettingsDropdown.Icon
    -- Replace the full button with just a gear icon (no background)
    -- Atlas: GM-icon-settings (simple gear icon used in raid frames)
    local settingsDropdown = sessionWindow.SettingsDropdown
    if settingsDropdown and settingsDropdown.Icon then
        st.buttonOverlays.settingsIcon = CreateButtonIconOverlay(
            settingsDropdown,
            "GM-icon-settings",
            settingsDropdown.Icon,
            { 25, 25 },  -- Gear icon size (25% bigger than before)
            3            -- Nudge up 3 pixels
        )
    end

    return st.buttonOverlays
end

-- Apply button icon overlay styling
-- When enabled:
--   Button 1: Hide Blizzard arrow, show the overlay arrow
--   Button 2: Just hide the background (keep letter visible)
--   Button 3: Hide Blizzard gear, show the overlay gear
-- When disabled:
--   Restore all Blizzard visuals
local function ApplyButtonIconOverlays(sessionWindow, db)
    if not sessionWindow or not db then return end

    local overlaysEnabled = db.buttonIconOverlaysEnabled
    local overlays = GetOrCreateButtonOverlays(sessionWindow)

    -- Get tint settings (used for overlays when enabled)
    local tintMode = db.buttonTintMode or "default"
    local r, g, b, a = 1, 1, 1, 1

    if tintMode == "custom" and db.buttonTint then
        local c = db.buttonTint
        r = c.r or c[1] or 1
        g = c.g or c[2] or 1
        b = c.b or c[3] or 1
        a = c.a or c[4] or 1
    end

    if overlaysEnabled then
        -- === Button 1: DamageMeterTypeDropdown ===
        -- Hide Blizzard's arrow, show the overlay
        local typeDropdown = sessionWindow.DamageMeterTypeDropdown
        if typeDropdown and typeDropdown.Arrow then
            pcall(typeDropdown.Arrow.SetAlpha, typeDropdown.Arrow, 0)

            local overlay = overlays.typeArrow
            if overlay then
                overlay:Show()
                -- Always desaturate the arrow to make it solid color
                pcall(overlay.SetDesaturated, overlay, true)
                if tintMode == "custom" then
                    pcall(overlay.SetVertexColor, overlay, r, g, b, a)
                else
                    -- Default: use white for solid appearance
                    pcall(overlay.SetVertexColor, overlay, 1, 1, 1, 1)
                end
            end
        end

        -- === Button 2: SessionDropdown ===
        -- Just hide the background, keep the letter/arrow visible
        local sessionDropdown = sessionWindow.SessionDropdown
        if sessionDropdown and sessionDropdown.Background then
            pcall(sessionDropdown.Background.SetAlpha, sessionDropdown.Background, 0)
        end

        -- === Button 3: SettingsDropdown ===
        -- Hide Blizzard's gear icon, show the overlay
        local settingsDropdown = sessionWindow.SettingsDropdown
        if settingsDropdown and settingsDropdown.Icon then
            pcall(settingsDropdown.Icon.SetAlpha, settingsDropdown.Icon, 0)

            local overlay = overlays.settingsIcon
            if overlay then
                overlay:Show()
                -- Always desaturate the gear to make it solid color
                pcall(overlay.SetDesaturated, overlay, true)
                if tintMode == "custom" then
                    pcall(overlay.SetVertexColor, overlay, r, g, b, a)
                else
                    -- Default: use white for solid appearance
                    pcall(overlay.SetVertexColor, overlay, 1, 1, 1, 1)
                end
            end
        end

        return true  -- Signal that button styling was handled
    else
        -- === Restore all Blizzard visuals ===

        -- Button 1: Restore arrow
        local typeDropdown = sessionWindow.DamageMeterTypeDropdown
        if typeDropdown and typeDropdown.Arrow then
            pcall(typeDropdown.Arrow.SetAlpha, typeDropdown.Arrow, 1)
        end
        if overlays.typeArrow then
            overlays.typeArrow:Hide()
        end

        -- Button 2: Restore background
        local sessionDropdown = sessionWindow.SessionDropdown
        if sessionDropdown and sessionDropdown.Background then
            pcall(sessionDropdown.Background.SetAlpha, sessionDropdown.Background, 1)
        end

        -- Button 3: Restore gear icon
        local settingsDropdown = sessionWindow.SettingsDropdown
        if settingsDropdown and settingsDropdown.Icon then
            pcall(settingsDropdown.Icon.SetAlpha, settingsDropdown.Icon, 1)
        end
        if overlays.settingsIcon then
            overlays.settingsIcon:Hide()
        end

        return false  -- Signal that ApplyButtonTintStyling should handle it
    end
end

-- Apply header backdrop styling to a session window
local function ApplyHeaderBackdropStyling(sessionWindow, db)
    if not sessionWindow or not db then return end

    local header = sessionWindow.Header
    if not header then return end

    -- Show/hide control
    local show = db.headerBackdropShow
    if show == false then
        SafeSetShown(header, false)
        return
    else
        SafeSetShown(header, true)
    end

    -- Apply tint color
    local tint = db.headerBackdropTint
    if tint and header.SetVertexColor then
        local r = tint.r or tint[1] or 1
        local g = tint.g or tint[2] or 1
        local b = tint.b or tint[3] or 1
        local a = tint.a or tint[4] or 1
        pcall(header.SetVertexColor, header, r, g, b, a)
    end
end

-- Find all damage meter session windows
--------------------------------------------------------------------------------
-- Shared Damage Meter Export Data
--------------------------------------------------------------------------------

local function GetCurrentZoneLabel()
    local instName, instType, _, diffName = GetInstanceInfo()
    if instName and instName ~= "" and instType ~= "none" then
        return (diffName and diffName ~= "") and (instName .. " (" .. diffName .. ")") or instName
    else
        return (instName and instName ~= "") and instName or "Open World"
    end
end

local dmResetZoneSnapshot = nil

local function SnapshotResetZone()
    dmResetZoneSnapshot = GetCurrentZoneLabel()
end

function addon.GatherDamageMeterExportData(sessionType, primaryMeterType)
    if not C_DamageMeter or not C_DamageMeter.IsDamageMeterAvailable then
        return nil, "Damage Meter API not available."
    end
    local isAvailable, failureReason = C_DamageMeter.IsDamageMeterAvailable()
    if not isAvailable then
        return nil, "Damage Meter not available: " .. (failureReason or "unknown")
    end

    local DMT = Enum.DamageMeterType
    local columnMap = {
        [DMT.DamageDone]            = { DMT.Dps,                DMT.DamageDone,   DMT.Deaths, DMT.Interrupts },
        [DMT.Dps]                   = { DMT.Dps,                DMT.DamageDone,   DMT.Deaths, DMT.Interrupts },
        [DMT.HealingDone]           = { DMT.Hps,                DMT.HealingDone,  DMT.Deaths, DMT.Interrupts },
        [DMT.Hps]                   = { DMT.Hps,                DMT.HealingDone,  DMT.Deaths, DMT.Interrupts },
        [DMT.Deaths]                = { DMT.Deaths,             DMT.Dps,          DMT.DamageDone, DMT.Interrupts },
        [DMT.Interrupts]            = { DMT.Interrupts,         DMT.Dps,          DMT.DamageDone, DMT.Deaths },
        [DMT.Absorbs]               = { DMT.Absorbs,            DMT.Dps,          DMT.DamageDone, DMT.Deaths },
        [DMT.Dispels]               = { DMT.Dispels,            DMT.Dps,          DMT.DamageDone, DMT.Deaths },
        [DMT.DamageTaken]           = { DMT.DamageTaken,        DMT.Dps,          DMT.DamageDone, DMT.Deaths },
        [DMT.AvoidableDamageTaken]  = { DMT.AvoidableDamageTaken, DMT.Dps,        DMT.DamageDone, DMT.Deaths },
        [DMT.EnemyDamageTaken]      = { DMT.EnemyDamageTaken,   DMT.Dps,          DMT.DamageDone, DMT.Deaths },
    }
    local columns = columnMap[primaryMeterType] or columnMap[DMT.Dps]

    local meterNames = {
        [DMT.DamageDone] = "Damage",     [DMT.Dps] = "DPS",
        [DMT.HealingDone] = "Healing",   [DMT.Hps] = "HPS",
        [DMT.Absorbs] = "Absorbs",       [DMT.Interrupts] = "Interrupts",
        [DMT.Dispels] = "Dispels",       [DMT.DamageTaken] = "Dmg Taken",
        [DMT.AvoidableDamageTaken] = "Avoidable", [DMT.Deaths] = "Deaths",
        [DMT.EnemyDamageTaken] = "Enemy Dmg",
    }
    local sessionLabels = {
        [Enum.DamageMeterSessionType.Overall] = "Overall",
        [Enum.DamageMeterSessionType.Current] = "Current",
        [Enum.DamageMeterSessionType.Expired] = "Expired",
    }

    local rateMetrics = { [DMT.Dps] = true, [DMT.Hps] = true }
    local countMetrics = { [DMT.Deaths] = true, [DMT.Interrupts] = true, [DMT.Dispels] = true }

    -- Query all column meter types
    local sessionData = {}
    for _, mt in ipairs(columns) do
        if not sessionData[mt] then
            local ok, result = pcall(C_DamageMeter.GetCombatSessionFromType, sessionType, mt)
            if ok and result then sessionData[mt] = result end
        end
    end

    local primarySession = sessionData[columns[1]]
    if not primarySession or not primarySession.combatSources or #primarySession.combatSources == 0 then
        return nil, "No data available for " .. (sessionLabels[sessionType] or "this") .. " session."
    end

    -- Pre-count Deaths per GUID (each combatSource entry = one death event)
    local deathCounts = {}
    local deathSession = sessionData[DMT.Deaths]
    if deathSession and deathSession.combatSources then
        for _, source in ipairs(deathSession.combatSources) do
            local guid = source.sourceGUID
            if guid then
                deathCounts[guid] = (deathCounts[guid] or 0) + 1
            end
        end
    end

    -- Build player table keyed by GUID, preserving primary sort order
    local players = {}
    local playerOrder = {}
    for _, source in ipairs(primarySession.combatSources) do
        local guid = source.sourceGUID
        if guid and not players[guid] then
            players[guid] = {
                name = (source.name and source.name:match("^([^%-]+)")) or "Unknown",
                classFilename = source.classFilename or "",
                isLocalPlayer = source.isLocalPlayer,
                values = {},
            }
            if columns[1] == DMT.Deaths then
                players[guid].values[columns[1]] = {
                    total = deathCounts[guid] or 0,
                    perSec = 0,
                }
            else
                players[guid].values[columns[1]] = {
                    total = source.totalAmount,
                    perSec = source.amountPerSecond,
                }
            end
            table.insert(playerOrder, guid)
        end
    end

    -- Merge secondary columns by GUID
    for i = 2, #columns do
        local mt = columns[i]
        local data = sessionData[mt]
        if data and data.combatSources then
            if mt == DMT.Deaths then
                -- Deaths: use pre-counted occurrences, not totalAmount
                for _, source in ipairs(data.combatSources) do
                    local guid = source.sourceGUID
                    if guid and players[guid] and not players[guid].values[mt] then
                        players[guid].values[mt] = {
                            total = deathCounts[guid] or 0,
                            perSec = 0,
                        }
                    end
                end
            else
                for _, source in ipairs(data.combatSources) do
                    local guid = source.sourceGUID
                    if guid and players[guid] and not players[guid].values[mt] then
                        players[guid].values[mt] = {
                            total = source.totalAmount,
                            perSec = source.amountPerSecond,
                        }
                    end
                end
            end
        end
    end

    -- Duration
    local duration = primarySession.durationSeconds
    if not duration then
        local ok, dur = pcall(C_DamageMeter.GetSessionDurationSeconds, sessionType)
        if ok then duration = dur end
    end

    -- Helpers
    local function FormatNumber(n)
        if not n or n == 0 then return "0" end
        if n >= 1000000000 then return string.format("%.1fB", n / 1000000000)
        elseif n >= 1000000 then return string.format("%.1fM", n / 1000000)
        elseif n >= 1000 then return string.format("%.1fK", n / 1000)
        else return string.format("%.0f", n) end
    end

    local function FormatDuration(sec)
        if not sec or sec <= 0 then return "0s" end
        local m = math.floor(sec / 60)
        local s = math.floor(sec % 60)
        return m > 0 and string.format("%dm %02ds", m, s) or string.format("%ds", s)
    end

    local function GetDisplayValue(guid, mt)
        local v = players[guid] and players[guid].values[mt]
        if not v then return "-" end
        if rateMetrics[mt] then return FormatNumber(v.perSec)
        elseif countMetrics[mt] then return tostring(math.floor(v.total))
        else return FormatNumber(v.total) end
    end

    -- Column header names
    local columnNames = {}
    for _, mt in ipairs(columns) do
        table.insert(columnNames, meterNames[mt] or "?")
    end

    -- Instance info
    local instanceLabel = GetCurrentZoneLabel()

    return {
        players = players,
        playerOrder = playerOrder,
        columns = columns,
        columnNames = columnNames,
        sessionLabel = sessionLabels[sessionType] or "Unknown",
        duration = duration,
        instanceLabel = instanceLabel,
        startZoneLabel = dmResetZoneSnapshot,
        playerCount = #playerOrder,
        timestamp = date("%Y-%m-%d %H:%M"),
        FormatNumber = FormatNumber,
        FormatDuration = FormatDuration,
        GetDisplayValue = GetDisplayValue,
    }
end

--------------------------------------------------------------------------------
-- Export Button, Flyout Menu & Chat Export
--------------------------------------------------------------------------------

-- Active export menu (only one open at a time)
local activeExportMenu = nil

-- Active chat export state (for abort)
local activeChatExport = nil

local function CloseExportMenu()
    if activeExportMenu then
        activeExportMenu:Hide()
        activeExportMenu = nil
    end
end

local function AbortChatExport()
    if activeChatExport then
        activeChatExport._active = false
        activeChatExport = nil
    end
end

-- Validate and return available chat channels
local function GetAvailableChatChannels()
    local channels = {}
    -- SAY always available
    table.insert(channels, { key = "SAY", label = "Say" })
    -- PARTY when in group but not raid
    if IsInGroup() and not IsInRaid() then
        table.insert(channels, { key = "PARTY", label = "Party" })
    end
    -- RAID when in raid
    if IsInRaid() then
        table.insert(channels, { key = "RAID", label = "Raid" })
    end
    -- INSTANCE_CHAT when in instance group
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        table.insert(channels, { key = "INSTANCE_CHAT", label = "Instance" })
    end
    -- GUILD when in guild
    if IsInGuild() then
        table.insert(channels, { key = "GUILD", label = "Guild" })
    end
    return channels
end

local function IsChannelAvailable(channel)
    if channel == "SAY" then return true end
    if channel == "PARTY" then return IsInGroup() and not IsInRaid() end
    if channel == "RAID" then return IsInRaid() end
    if channel == "INSTANCE_CHAT" then return IsInGroup(LE_PARTY_CATEGORY_INSTANCE) end
    if channel == "GUILD" then return IsInGuild() end
    return false
end

-- Send damage meter data to chat with throttle
local function SendExportToChat(sessionWindow)
    if PlayerInCombat() then
        if addon.Print then addon:Print("Export not available during combat.") end
        return
    end

    local comp = addon.Components and addon.Components["damageMeter"]
    if not comp or not comp.db then return end
    local db = comp.db

    local channel = db.exportChatChannel or "PARTY"
    local lineCount = db.exportChatLineCount or 5

    -- Validate channel
    if not IsChannelAvailable(channel) then
        -- Fall back to SAY
        channel = "SAY"
    end

    -- Get data from the originating window
    local sessionType = sessionWindow.sessionType or Enum.DamageMeterSessionType.Overall
    local primaryMeterType = sessionWindow.damageMeterType or Enum.DamageMeterType.Dps

    local data, err = addon.GatherDamageMeterExportData(sessionType, primaryMeterType)
    if not data then
        if addon.Print then addon:Print(err or "No export data available.") end
        return
    end

    -- Build messages
    local messages = {}
    -- Header
    local headerName = data.columnNames[1] or "DPS"
    table.insert(messages, string.format("Scoot - %s (%s) [%s]:", headerName, data.sessionLabel, data.FormatDuration(data.duration)))

    -- Player lines (limited by lineCount)
    local count = math.min(lineCount, #data.playerOrder)
    for i = 1, count do
        local guid = data.playerOrder[i]
        local p = data.players[guid]
        local mt = data.columns[1]
        local val = data.GetDisplayValue(guid, mt)
        table.insert(messages, string.format("#%d. %s - %s", i, p.name, val))
    end

    -- Send all messages synchronously to preserve secure execution context
    -- (C_Timer.After breaks the hardware-event chain, causing ADDON_ACTION_BLOCKED)
    for _, msg in ipairs(messages) do
        SendChatMessage(msg, channel)
    end
end

-- Create the flyout menu for an export button
local function CreateExportMenu(exportBtn, sessionWindow)
    local st = getWindowState(sessionWindow)
    if st.exportMenu then return st.exportMenu end

    local menu = CreateFrame("Frame", nil, UIParent)
    menu:SetSize(200, 210)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetFrameLevel(200)
    menu:EnableMouse(true)
    menu:SetClampedToScreen(true)

    -- Dark background
    local bg = menu:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints()
    bg:SetColorTexture(0.06, 0.06, 0.08, 0.95)

    -- Thin border
    local borderColor = { 0.3, 0.3, 0.35, 0.8 }
    local bw = 1
    local bTop = menu:CreateTexture(nil, "BORDER")
    bTop:SetPoint("TOPLEFT") bTop:SetPoint("TOPRIGHT") bTop:SetHeight(bw)
    bTop:SetColorTexture(borderColor[1], borderColor[2], borderColor[3], borderColor[4])
    local bBot = menu:CreateTexture(nil, "BORDER")
    bBot:SetPoint("BOTTOMLEFT") bBot:SetPoint("BOTTOMRIGHT") bBot:SetHeight(bw)
    bBot:SetColorTexture(borderColor[1], borderColor[2], borderColor[3], borderColor[4])
    local bLeft = menu:CreateTexture(nil, "BORDER")
    bLeft:SetPoint("TOPLEFT", 0, -bw) bLeft:SetPoint("BOTTOMLEFT", 0, bw) bLeft:SetWidth(bw)
    bLeft:SetColorTexture(borderColor[1], borderColor[2], borderColor[3], borderColor[4])
    local bRight = menu:CreateTexture(nil, "BORDER")
    bRight:SetPoint("TOPRIGHT", 0, -bw) bRight:SetPoint("BOTTOMRIGHT", 0, bw) bRight:SetWidth(bw)
    bRight:SetColorTexture(borderColor[1], borderColor[2], borderColor[3], borderColor[4])

    local yOff = -8
    local defaultFont = select(1, _G.GameFontNormal:GetFont()) or "Fonts\\FRIZQT__.TTF"

    -- "Export to Window" row
    local windowBtn = CreateFrame("Button", nil, menu)
    windowBtn:SetSize(184, 24)
    windowBtn:SetPoint("TOP", menu, "TOP", 0, yOff)
    windowBtn:EnableMouse(true)
    windowBtn:RegisterForClicks("AnyUp")

    local windowBtnBg = windowBtn:CreateTexture(nil, "BACKGROUND", nil, -6)
    windowBtnBg:SetAllPoints()
    windowBtnBg:SetColorTexture(1, 1, 1, 0)

    local windowBtnText = windowBtn:CreateFontString(nil, "OVERLAY")
    windowBtnText:SetFont(defaultFont, 11, "")
    windowBtnText:SetPoint("LEFT", 8, 0)
    windowBtnText:SetText("Export to Window")
    windowBtnText:SetTextColor(1, 1, 1, 0.9)

    windowBtn:SetScript("OnEnter", function() windowBtnBg:SetColorTexture(1, 1, 1, 0.08) end)
    windowBtn:SetScript("OnLeave", function() windowBtnBg:SetColorTexture(1, 1, 1, 0) end)
    windowBtn:SetScript("OnClick", function()
        CloseExportMenu()
        if PlayerInCombat() then
            if addon.Print then addon:Print("Export not available during combat.") end
            return
        end
        local sessionType = sessionWindow.sessionType or Enum.DamageMeterSessionType.Overall
        local primaryMeterType = sessionWindow.damageMeterType or Enum.DamageMeterType.Dps
        local data, err = addon.GatherDamageMeterExportData(sessionType, primaryMeterType)
        if not data then
            if addon.Print then addon:Print(err or "No export data available.") end
            return
        end
        if addon.ShowHighScoreWindow then
            addon.ShowHighScoreWindow(data)
        end
    end)

    yOff = yOff - 28

    -- Divider
    local divider = menu:CreateTexture(nil, "ARTWORK")
    divider:SetSize(180, 1)
    divider:SetPoint("TOP", menu, "TOP", 0, yOff)
    divider:SetColorTexture(0.3, 0.3, 0.35, 0.5)

    yOff = yOff - 8

    -- "Export to Chat" label
    local chatLabel = menu:CreateFontString(nil, "OVERLAY")
    chatLabel:SetFont(defaultFont, 11, "")
    chatLabel:SetPoint("TOPLEFT", menu, "TOPLEFT", 16, yOff)
    chatLabel:SetText("Export to Chat")
    chatLabel:SetTextColor(0.7, 0.7, 0.7, 1)

    yOff = yOff - 20

    -- Channel dropdown button
    local channelBtn = CreateFrame("Button", nil, menu)
    channelBtn:SetSize(168, 22)
    channelBtn:SetPoint("TOP", menu, "TOP", 0, yOff)
    channelBtn:EnableMouse(true)
    channelBtn:RegisterForClicks("AnyUp")

    local channelBg = channelBtn:CreateTexture(nil, "BACKGROUND", nil, -6)
    channelBg:SetAllPoints()
    channelBg:SetColorTexture(0.1, 0.1, 0.12, 1)

    local channelText = channelBtn:CreateFontString(nil, "OVERLAY")
    channelText:SetFont(defaultFont, 10, "")
    channelText:SetPoint("LEFT", 8, 0)
    channelText:SetTextColor(1, 1, 1, 0.9)

    local channelArrow = channelBtn:CreateFontString(nil, "OVERLAY")
    channelArrow:SetFont(defaultFont, 10, "")
    channelArrow:SetPoint("RIGHT", -8, 0)
    channelArrow:SetText("v")
    channelArrow:SetTextColor(0.6, 0.6, 0.6, 1)

    -- Channel label names
    local channelLabels = {
        SAY = "Say", PARTY = "Party", RAID = "Raid",
        INSTANCE_CHAT = "Instance", GUILD = "Guild",
    }

    local function UpdateChannelText()
        local comp = addon.Components and addon.Components["damageMeter"]
        local ch = comp and comp.db and comp.db.exportChatChannel or "PARTY"
        channelText:SetText("Channel: " .. (channelLabels[ch] or ch))
    end

    channelBtn:SetScript("OnEnter", function() channelBg:SetColorTexture(0.15, 0.15, 0.18, 1) end)
    channelBtn:SetScript("OnLeave", function() channelBg:SetColorTexture(0.1, 0.1, 0.12, 1) end)
    channelBtn:SetScript("OnClick", function()
        -- Toggle: if submenu exists and shown, hide it; otherwise create/show
        if channelBtn._submenu and channelBtn._submenu:IsShown() then
            channelBtn._submenu:Hide()
            return
        end

        -- Create submenu once (lazy)
        if not channelBtn._submenu then
            local sub = CreateFrame("Frame", nil, menu)  -- child of menu for parent-chain walk
            sub:SetSize(168, 5 * 20 + 8)  -- 5 channels x 20px + padding
            sub:SetFrameStrata("FULLSCREEN_DIALOG")
            sub:SetFrameLevel(210)  -- above menu (200)
            sub:EnableMouse(true)

            -- Dark background
            local subBg = sub:CreateTexture(nil, "BACKGROUND", nil, -8)
            subBg:SetAllPoints()
            subBg:SetColorTexture(0.08, 0.08, 0.10, 0.98)

            -- Thin border (same style as parent menu)
            local bc = { 0.3, 0.3, 0.35, 0.8 }
            local sbw = 1
            local sbTop = sub:CreateTexture(nil, "BORDER")
            sbTop:SetPoint("TOPLEFT") sbTop:SetPoint("TOPRIGHT") sbTop:SetHeight(sbw)
            sbTop:SetColorTexture(bc[1], bc[2], bc[3], bc[4])
            local sbBot = sub:CreateTexture(nil, "BORDER")
            sbBot:SetPoint("BOTTOMLEFT") sbBot:SetPoint("BOTTOMRIGHT") sbBot:SetHeight(sbw)
            sbBot:SetColorTexture(bc[1], bc[2], bc[3], bc[4])
            local sbLeft = sub:CreateTexture(nil, "BORDER")
            sbLeft:SetPoint("TOPLEFT", 0, -sbw) sbLeft:SetPoint("BOTTOMLEFT", 0, sbw) sbLeft:SetWidth(sbw)
            sbLeft:SetColorTexture(bc[1], bc[2], bc[3], bc[4])
            local sbRight = sub:CreateTexture(nil, "BORDER")
            sbRight:SetPoint("TOPRIGHT", 0, -sbw) sbRight:SetPoint("BOTTOMRIGHT", 0, sbw) sbRight:SetWidth(sbw)
            sbRight:SetColorTexture(bc[1], bc[2], bc[3], bc[4])

            local allChannels = {
                { key = "SAY", label = "Say" },
                { key = "PARTY", label = "Party" },
                { key = "RAID", label = "Raid" },
                { key = "INSTANCE_CHAT", label = "Instance" },
                { key = "GUILD", label = "Guild" },
            }
            sub._rows = {}

            for idx, ch in ipairs(allChannels) do
                local row = CreateFrame("Button", nil, sub)
                row:SetSize(160, 20)
                row:SetPoint("TOPLEFT", sub, "TOPLEFT", 4, -(4 + (idx - 1) * 20))
                row:EnableMouse(true)
                row:RegisterForClicks("AnyUp")

                local rowBg = row:CreateTexture(nil, "BACKGROUND", nil, -6)
                rowBg:SetAllPoints()
                rowBg:SetColorTexture(1, 1, 1, 0)

                local rowText = row:CreateFontString(nil, "OVERLAY")
                rowText:SetFont(defaultFont, 10, "")
                rowText:SetPoint("LEFT", 6, 0)
                rowText:SetText(ch.label)

                -- Checkmark for selected channel
                local check = row:CreateFontString(nil, "OVERLAY")
                check:SetFont(defaultFont, 10, "")
                check:SetPoint("RIGHT", -6, 0)
                check:SetText("")

                row._key = ch.key
                row._text = rowText
                row._check = check
                row._bg = rowBg

                row:SetScript("OnEnter", function()
                    if row._available then
                        rowBg:SetColorTexture(1, 1, 1, 0.08)
                    end
                end)
                row:SetScript("OnLeave", function()
                    rowBg:SetColorTexture(1, 1, 1, 0)
                end)
                row:SetScript("OnClick", function()
                    if not row._available then return end
                    local comp = addon.Components and addon.Components["damageMeter"]
                    if comp and comp.db then
                        comp.db.exportChatChannel = ch.key
                    end
                    UpdateChannelText()
                    sub:Hide()
                end)

                sub._rows[idx] = row
            end

            -- Refresh function: update availability + checkmark
            function sub:Refresh()
                local avail = {}
                for _, c in ipairs(GetAvailableChatChannels()) do
                    avail[c.key] = true
                end
                local comp = addon.Components and addon.Components["damageMeter"]
                local current = comp and comp.db and comp.db.exportChatChannel or "PARTY"
                for _, row in ipairs(self._rows) do
                    local isAvail = avail[row._key] or false
                    row._available = isAvail
                    row._text:SetTextColor(1, 1, 1, isAvail and 0.9 or 0.3)
                    row._check:SetText(row._key == current and ">" or "")
                    row._check:SetTextColor(0.20, 0.90, 0.30, 1)
                end
            end

            channelBtn._submenu = sub
        end

        -- Position and show
        channelBtn._submenu:ClearAllPoints()
        channelBtn._submenu:SetPoint("TOPLEFT", channelBtn, "BOTTOMLEFT", 0, -2)
        channelBtn._submenu:Refresh()
        channelBtn._submenu:Show()
    end)

    yOff = yOff - 28

    -- Lines slider
    local sliderLabel = menu:CreateFontString(nil, "OVERLAY")
    sliderLabel:SetFont(defaultFont, 10, "")
    sliderLabel:SetPoint("TOPLEFT", menu, "TOPLEFT", 16, yOff)
    sliderLabel:SetTextColor(0.7, 0.7, 0.7, 1)

    local function UpdateSliderLabel()
        local comp = addon.Components and addon.Components["damageMeter"]
        local count = comp and comp.db and comp.db.exportChatLineCount or 5
        sliderLabel:SetText("Lines: " .. count)
    end

    yOff = yOff - 16

    local slider = CreateFrame("Slider", nil, menu, "OptionsSliderTemplate")
    slider:SetSize(168, 14)
    slider:SetPoint("TOP", menu, "TOP", 0, yOff)
    slider:SetMinMaxValues(1, 20)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    -- Hide default text elements
    if slider.Text then slider.Text:SetText("") end
    if slider.Low then slider.Low:SetText("") end
    if slider.High then slider.High:SetText("") end

    slider:SetScript("OnValueChanged", function(self, value)
        local comp = addon.Components and addon.Components["damageMeter"]
        if comp and comp.db then
            comp.db.exportChatLineCount = math.floor(value)
        end
        UpdateSliderLabel()
    end)

    yOff = yOff - 24

    -- Send button
    local sendBtn = CreateFrame("Button", nil, menu)
    sendBtn:SetSize(168, 24)
    sendBtn:SetPoint("TOP", menu, "TOP", 0, yOff)
    sendBtn:EnableMouse(true)
    sendBtn:RegisterForClicks("AnyUp")

    local sendBg = sendBtn:CreateTexture(nil, "BACKGROUND", nil, -6)
    sendBg:SetAllPoints()
    sendBg:SetColorTexture(0.15, 0.15, 0.18, 1)

    local sendText = sendBtn:CreateFontString(nil, "OVERLAY")
    sendText:SetFont(defaultFont, 11, "")
    sendText:SetPoint("CENTER")
    sendText:SetText("Send to Chat")
    sendText:SetTextColor(1, 1, 1, 0.9)

    sendBtn:SetScript("OnEnter", function() sendBg:SetColorTexture(0.2, 0.2, 0.24, 1) end)
    sendBtn:SetScript("OnLeave", function() sendBg:SetColorTexture(0.15, 0.15, 0.18, 1) end)
    sendBtn:SetScript("OnClick", function()
        CloseExportMenu()
        SendExportToChat(sessionWindow)
    end)

    -- Menu show/hide logic
    menu:SetScript("OnShow", function(self)
        UpdateChannelText()
        UpdateSliderLabel()
        local comp = addon.Components and addon.Components["damageMeter"]
        local count = comp and comp.db and comp.db.exportChatLineCount or 5
        slider:SetValue(count)

        -- Close on click-away via GLOBAL_MOUSE_DOWN
        self:RegisterEvent("GLOBAL_MOUSE_DOWN")
        self:RegisterEvent("PLAYER_REGEN_DISABLED")
    end)

    menu:SetScript("OnHide", function(self)
        self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
        self:UnregisterEvent("PLAYER_REGEN_DISABLED")
        if activeExportMenu == self then
            activeExportMenu = nil
        end
    end)

    menu:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_REGEN_DISABLED" then
            CloseExportMenu()
        elseif event == "GLOBAL_MOUSE_DOWN" then
            C_Timer.After(0.05, function()
                if not self:IsShown() then return end
                local foci = GetMouseFoci()
                local focus = foci and foci[1]
                if not focus then return end
                if focus == exportBtn then return end
                -- Walk parent chain: if focus is menu or any child of menu, stay open
                local f = focus
                while f do
                    if f == self then return end
                    f = f:GetParent()
                end
                CloseExportMenu()
            end)
        end
    end)

    menu:Hide()
    st.exportMenu = menu
    return menu
end

-- Create or retrieve the export button for a session window
local function GetOrCreateExportButton(sessionWindow)
    local st = getWindowState(sessionWindow)
    if st.exportButton then return st.exportButton end

    local sessionDropdown = sessionWindow.SessionDropdown
    if not sessionDropdown then return nil end

    -- Create UIParent-parented button (avoids taint)
    local btn = CreateFrame("Button", nil, UIParent)
    btn:SetSize(36, 36)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(100)
    btn:EnableMouse(true)
    btn:RegisterForClicks("AnyUp")

    -- Backdrop circle (copy atlas from SessionDropdown.Background)
    local backdrop = btn:CreateTexture(nil, "BACKGROUND", nil, -6)
    backdrop:SetSize(36, 36)
    backdrop:SetPoint("CENTER")
    if sessionDropdown.Background then
        local atlas = sessionDropdown.Background:GetAtlas()
        if atlas then
            backdrop:SetAtlas(atlas, false)
        else
            local tex = sessionDropdown.Background:GetTexture()
            if tex then
                backdrop:SetTexture(tex)
            end
        end
    end
    btn._backdrop = backdrop

    -- Horn icon
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(27, 27)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetAtlas("UI-EventPoi-Horn-big", false)
    btn._icon = icon

    -- Custom icon overlay (for overlay mode)
    local overlayIcon = btn:CreateTexture(nil, "OVERLAY", nil, 7)
    overlayIcon:SetSize(27, 27)
    overlayIcon:SetPoint("CENTER", 0, 1)
    overlayIcon:SetAtlas("UI-EventPoi-Horn-big", false)
    overlayIcon:Hide()
    btn._overlayIcon = overlayIcon

    -- Click handler: toggle flyout
    btn:SetScript("OnClick", function(self)
        if PlayerInCombat() then
            if addon.Print then addon:Print("Export not available during combat.") end
            return
        end
        local menu = CreateExportMenu(self, sessionWindow)
        if menu:IsShown() then
            CloseExportMenu()
        else
            CloseExportMenu() -- Close any other open menu
            menu:ClearAllPoints()
            menu:SetPoint("BOTTOM", self, "TOP", 0, 4)
            menu:Show()
            activeExportMenu = menu
        end
    end)

    btn:Hide() -- Start hidden; shown by ApplyExportButtonStyling
    st.exportButton = btn
    return btn
end

-- Position and style the export button
local function ApplyExportButtonStyling(sessionWindow, db)
    if not sessionWindow or not db then return end

    local enabled = db.exportEnabled
    local st = getWindowState(sessionWindow)

    if not enabled then
        -- Hide export button + menu if they exist
        if st.exportButton then st.exportButton:Hide() end
        if st.exportMenu then st.exportMenu:Hide() end
        return
    end

    if PlayerInCombat() then
        -- Hide during combat
        if st.exportButton then st.exportButton:Hide() end
        if st.exportMenu then st.exportMenu:Hide() end
        return
    end

    local btn = GetOrCreateExportButton(sessionWindow)
    if not btn then return end

    -- Position: anchor RIGHT of export button to LEFT of SessionDropdown with offset
    local sessionDropdown = sessionWindow.SessionDropdown
    if sessionDropdown then
        local xOffset = db.exportButtonXOffset or 0
        btn:ClearAllPoints()
        btn:SetPoint("RIGHT", sessionDropdown, "LEFT", -6 + xOffset, 0)
    end

    -- Determine styling mode
    local overlaysEnabled = db.buttonIconOverlaysEnabled
    local tintMode = db.buttonTintMode or "default"
    local r, g, b, a = 1, 1, 1, 1
    if tintMode == "custom" and db.buttonTint then
        local c = db.buttonTint
        r = c.r or c[1] or 1
        g = c.g or c[2] or 1
        b = c.b or c[3] or 1
        a = c.a or c[4] or 1
    end

    if overlaysEnabled then
        -- Custom icons mode: no backdrop, show overlay icon desaturated + tinted
        btn._backdrop:Hide()
        btn._icon:Hide()
        btn._overlayIcon:Show()
        pcall(btn._overlayIcon.SetDesaturated, btn._overlayIcon, true)
        if tintMode == "custom" then
            pcall(btn._overlayIcon.SetVertexColor, btn._overlayIcon, r, g, b, a)
        else
            pcall(btn._overlayIcon.SetVertexColor, btn._overlayIcon, 1, 1, 1, 1)
        end
    else
        -- Default mode: show backdrop + icon with tint
        btn._backdrop:Show()
        btn._icon:Show()
        btn._overlayIcon:Hide()
        if tintMode == "custom" then
            pcall(btn._backdrop.SetDesaturated, btn._backdrop, true)
            pcall(btn._backdrop.SetVertexColor, btn._backdrop, r, g, b, a)
            pcall(btn._icon.SetDesaturated, btn._icon, true)
            pcall(btn._icon.SetVertexColor, btn._icon, r, g, b, a)
        else
            pcall(btn._backdrop.SetDesaturated, btn._backdrop, false)
            pcall(btn._backdrop.SetVertexColor, btn._backdrop, 1, 1, 1, 1)
            -- Default horn icon: goldish-yellow tint
            pcall(btn._icon.SetDesaturated, btn._icon, false)
            pcall(btn._icon.SetVertexColor, btn._icon, 1, 0.82, 0, 1)
        end
    end

    btn:Show()
end

local function GetAllSessionWindows()
    local windows = {}

    -- Try numbered session windows (DamageMeterSessionWindow1, DamageMeterSessionWindow2, etc.)
    for i = 1, 10 do
        local windowName = "DamageMeterSessionWindow" .. i
        local window = _G[windowName]
        if window then
            table.insert(windows, window)
        end
    end

    -- Also check DamageMeter.sessionWindows array if it exists
    local dmFrame = _G.DamageMeter
    if dmFrame and dmFrame.sessionWindows then
        for _, window in ipairs(dmFrame.sessionWindows) do
            -- Avoid duplicates
            local found = false
            for _, existing in ipairs(windows) do
                if existing == window then
                    found = true
                    break
                end
            end
            if not found then
                table.insert(windows, window)
            end
        end
    end

    return windows
end

-- Iterate all visible entries in a session window's ScrollBox
local function ForEachVisibleEntry(sessionWindow, callback)
    if not sessionWindow then return end

    local scrollBox = sessionWindow.ScrollBox
    if not scrollBox then return end

    -- Method 1: ForEachFrame (standard ScrollBox API)
    if scrollBox.ForEachFrame then
        local ok, err = pcall(scrollBox.ForEachFrame, scrollBox, callback)
        if not ok and addon._debugDM then
            addon._debugDMLog = addon._debugDMLog or {}
            addon._debugDMLog[#addon._debugDMLog + 1] = "ForEachFrame error: " .. tostring(err)
        end
        return
    end

    -- Method 2: GetFrames (alternative API)
    if scrollBox.GetFrames then
        local ok, frames = pcall(scrollBox.GetFrames, scrollBox)
        if ok and frames then
            for _, frame in ipairs(frames) do
                pcall(callback, frame)
            end
        elseif not ok and addon._debugDM then
            addon._debugDMLog = addon._debugDMLog or {}
            addon._debugDMLog[#addon._debugDMLog + 1] = "GetFrames error: " .. tostring(frames)
        end
        return
    end

    -- Method 3: Iterate ScrollTarget children directly
    local scrollTarget = scrollBox.ScrollTarget
    if scrollTarget and scrollTarget.GetChildren then
        local children = { scrollTarget:GetChildren() }
        for _, child in ipairs(children) do
            if child and child.StatusBar then
                pcall(callback, child)
            end
        end
    elseif addon._debugDM then
        addon._debugDMLog = addon._debugDMLog or {}
        addon._debugDMLog[#addon._debugDMLog + 1] = "No iteration method found on ScrollBox"
    end
end

-- OPT-18: Bump generation and restyle all visible entries in one pass.
local function styleAllVisibleEntries(sessionWindow, db)
    dmStyleGeneration = dmStyleGeneration + 1
    ForEachVisibleEntry(sessionWindow, function(entryFrame)
        ApplySingleEntryStyle(entryFrame, db, sessionWindow)
    end)
end

-- Update all visible overlay data across all windows (combat-safe: bar fill + text only)
local function UpdateAllOverlayData(comp)
    if not comp or not comp.db then return end
    local windows = GetAllSessionWindows()
    for _, sessionWindow in ipairs(windows) do
        ForEachVisibleEntry(sessionWindow, function(entryFrame)
            local elSt = elementState[entryFrame]
            if elSt and elSt.entryOverlay and elSt.entryOverlay:IsShown() then
                UpdateEntryOverlayData(elSt.entryOverlay, entryFrame)
            else
                -- Entry needs overlay (new post-reset entry, or overlay hidden by reset cleanup)
                ApplySingleEntryStyle(entryFrame, comp.db, sessionWindow)
            end
        end)
        -- Also update LocalPlayerEntry overlay (only if entry is visible)
        local lpe = sessionWindow.LocalPlayerEntry
        if lpe then
            local ok, shown = pcall(lpe.IsShown, lpe)
            if ok and shown then
                local elSt = elementState[lpe]
                if elSt and elSt.entryOverlay and elSt.entryOverlay:IsShown() then
                    UpdateEntryOverlayData(elSt.entryOverlay, lpe)
                else
                    ApplySingleEntryStyle(lpe, comp.db, sessionWindow)
                end
            end
        end
    end
end

-- Get scroll signature for scroll change detection
local function GetScrollSignature()
    local windows = GetAllSessionWindows()
    for _, sessionWindow in ipairs(windows) do
        local sig = nil
        ForEachVisibleEntry(sessionWindow, function(entryFrame)
            if not sig then
                local nt = entryFrame.nameText
                if issecretvalue(nt) then nt = nil end
                if not nt then
                    nt = entryFrame.sourceName
                    if issecretvalue(nt) then nt = nil end
                end
                local style = entryFrame.style
                if issecretvalue(style) then style = nil end
                sig = (nt or "") .. "|" .. tostring(style or "")
            end
        end)
        if sig then return sig end
    end
    return ""
end

-- Main styling function
local function ApplyDamageMeterStyling(self)
    local dmFrame = _G.DamageMeter
    if not dmFrame then
        hideAllDMOverlays()
        return
    end

    -- Zero-Touch: if still on proxy DB, do nothing
    if self._ScootDBProxy and self.db == self._ScootDBProxy then
        hideAllDMOverlays()
        return
    end

    local db = self.db
    if type(db) ~= "table" then
        hideAllDMOverlays()
        return
    end

    local windows = GetAllSessionWindows()

    -- Combat-safe: defer window-level styling during combat
    -- No cleanup here: meters still visible, just can't restyle
    if PlayerInCombat() then
        return
    end

    -- Style all session windows and their entries
    for _, sessionWindow in ipairs(windows) do
        knownSessionWindows[sessionWindow] = true  -- track for cleanup

        -- Reset this window's UIParent-parented overlays before re-styling visible entries
        hideWindowOverlays(sessionWindow)

        -- Apply window styling
        ApplyWindowStyling(sessionWindow, db)

        -- Apply title bar styling (title text, buttons, backdrop)
        ApplyTitleStyling(sessionWindow, db)
        ApplyTimerStyling(sessionWindow, db)

        -- Apply button icon overlays (if enabled) - must come before button tint
        local overlaysHandledButtons = ApplyButtonIconOverlays(sessionWindow, db)

        -- Apply button tint styling (only affects Blizzard textures when overlays disabled)
        -- When overlays enabled, this only affects SessionName text color
        if not overlaysHandledButtons then
            ApplyButtonTintStyling(sessionWindow, db)
        else
            -- When overlays are enabled, still need to tint SessionName text
            local tintMode = db.buttonTintMode or "default"
            local sessionNameFS = sessionWindow.SessionDropdown and sessionWindow.SessionDropdown.SessionName
            if sessionNameFS and sessionNameFS.SetTextColor then
                if tintMode == "custom" and db.buttonTint then
                    local c = db.buttonTint
                    local r = c.r or c[1] or 1
                    local g = c.g or c[2] or 1
                    local b = c.b or c[3] or 1
                    local a = c.a or c[4] or 1
                    pcall(sessionNameFS.SetTextColor, sessionNameFS, r, g, b, a)
                else
                    pcall(sessionNameFS.SetTextColor, sessionNameFS, TITLE_DEFAULT_COLOR[1], TITLE_DEFAULT_COLOR[2], TITLE_DEFAULT_COLOR[3], TITLE_DEFAULT_COLOR[4])
                end
            end
        end

        ApplyHeaderBackdropStyling(sessionWindow, db)

        -- Apply export button styling
        ApplyExportButtonStyling(sessionWindow, db)

        -- OPT-18: Bump generation and style all visible entries in this window
        styleAllVisibleEntries(sessionWindow, db)

        -- Style LocalPlayerEntry (sticky player row at bottom when scrolled past own position)
        -- This entry is a sibling of ScrollBox, not a child, so ForEachVisibleEntry misses it
        -- Guard with visibility check: after data clear, entry still exists but is hidden;
        -- ApplySingleEntryStyle calls overlay:Show(), which would leave a stuck overlay
        local localPlayerEntry = sessionWindow.LocalPlayerEntry
        if localPlayerEntry then
            local ok, shown = pcall(localPlayerEntry.IsShown, localPlayerEntry)
            if ok and shown then
                ApplySingleEntryStyle(localPlayerEntry, db, sessionWindow)
            else
                -- Entry hidden/gone — hide its overlay if it exists
                local elSt = elementState[localPlayerEntry]
                if elSt and elSt.entryOverlay then
                    elSt.entryOverlay:Hide()
                end
            end
        end
    end
end

addon:RegisterComponentInitializer(function(self)
    local Component = addon.ComponentPrototype

    local damageMeter = Component:New({
        id = "damageMeter",
        name = "Damage Meter",
        frameName = "DamageMeter",
        settings = {
            -- Edit Mode-managed settings (11 total)
            -- Style dropdown: Default(0), Bordered(1), Thin(2)
            style = { type = "editmode", settingId = nil, default = 0, ui = { hidden = true } },
            -- Layout settings
            frameWidth = { type = "editmode", settingId = nil, default = 300, ui = { hidden = true } },
            frameHeight = { type = "editmode", settingId = nil, default = 200, ui = { hidden = true } },
            barHeight = { type = "editmode", settingId = nil, default = 20, ui = { hidden = true } },
            padding = { type = "editmode", settingId = nil, default = 4, ui = { hidden = true } },
            -- Transparency/Opacity settings
            opacity = { type = "editmode", settingId = nil, default = 100, ui = { hidden = true } },
            background = { type = "editmode", settingId = nil, default = 80, ui = { hidden = true } },
            -- Text size
            textSize = { type = "editmode", settingId = nil, default = 100, ui = { hidden = true } },
            -- Visibility dropdown: Always(0), InCombat(1), Hidden(2)
            visibility = { type = "editmode", settingId = nil, default = 0, ui = { hidden = true } },
            -- Checkboxes
            showSpecIcon = { type = "editmode", settingId = nil, default = true, ui = { hidden = true } },
            showClassColor = { type = "editmode", settingId = nil, default = true, ui = { hidden = true } },

            -- Addon-only settings (bar styling)
            barTexture = { type = "addon", default = "default", ui = { hidden = true } },
            -- Foreground color: mode ("default", "class", "custom") + tint for custom
            barForegroundColorMode = { type = "addon", default = "default", ui = { hidden = true } },
            barForegroundTint = { type = "addon", default = { r = 1, g = 0.8, b = 0, a = 1 }, ui = { hidden = true } },
            -- Background color: mode ("default", "custom") + tint for custom
            barBackgroundColorMode = { type = "addon", default = "default", ui = { hidden = true } },
            barBackgroundTint = { type = "addon", default = { r = 0.1, g = 0.1, b = 0.1, a = 0.8 }, ui = { hidden = true } },
            -- Legacy settings (kept for backwards compatibility)
            barForegroundColor = { type = "addon", default = { 1, 0.8, 0, 1 }, ui = { hidden = true } },
            barBackgroundColor = { type = "addon", default = { 0.1, 0.1, 0.1, 0.8 }, ui = { hidden = true } },

            -- Bar border settings
            barBorderStyle = { type = "addon", default = "default", ui = { hidden = true } },
            barBorderTintEnabled = { type = "addon", default = false, ui = { hidden = true } },
            barBorderTintColor = { type = "addon", default = { 1, 1, 1, 1 }, ui = { hidden = true } },
            barBorderThickness = { type = "addon", default = 1, ui = { hidden = true } },
            barBorderHiddenEdges = { type = "addon", default = {}, ui = { hidden = true } },

            -- Icon settings (matching Essential Cooldowns Border pattern)
            iconBorderEnable = { type = "addon", default = false, ui = { hidden = true } },
            iconBorderTintEnable = { type = "addon", default = false, ui = { hidden = true } },
            iconBorderTintColor = { type = "addon", default = { r = 1, g = 1, b = 1, a = 1 }, ui = { hidden = true } },
            iconBorderThickness = { type = "addon", default = 1, ui = { hidden = true } },
            iconBorderInsetH = { type = "addon", default = 0, ui = { hidden = true } },  -- Horizontal (left/right)
            iconBorderInsetV = { type = "addon", default = 2, ui = { hidden = true } },  -- Vertical (top/bottom) - default 2 for clipped icons

            -- JiberishIcons integration (class icons to replace spec icons)
            jiberishIconsEnabled = { type = "addon", default = false, ui = { hidden = true } },
            jiberishIconsStyle = { type = "addon", default = "fabled", ui = { hidden = true } },

            -- Text settings - Title (header/dropdown)
            -- Default color is Blizzard's GameFontNormalMed1 gold: r=1.0, g=0.82, b=0
            textTitle = { type = "addon", default = {
                fontFace = "FRIZQT__",
                fontStyle = "OUTLINE",
                scaleMultiplier = 1.0,
                colorMode = "default",
                color = { 1.0, 0.82, 0, 1 },
            }, ui = { hidden = true }},

            -- Text settings - Timer (session timer [00:05:23])
            -- Same defaults as textTitle (both inherit GameFontNormalMed1)
            textTimer = { type = "addon", default = {
                fontFace = "FRIZQT__",
                fontStyle = "OUTLINE",
                colorMode = "default",
                color = { 1.0, 0.82, 0, 1 },
            }, ui = { hidden = true }},

            -- Button tint (header dropdown arrows, settings icon, session name text)
            buttonTintMode = { type = "addon", default = "default", ui = { hidden = true }},
            buttonTint = { type = "addon", default = { r = 1, g = 0.82, b = 0, a = 1 }, ui = { hidden = true }},

            -- Button icon overlays (custom atlas-based icons for uniform styling)
            buttonIconOverlaysEnabled = { type = "addon", default = false, ui = { hidden = true }},

            -- Header backdrop settings
            headerBackdropShow = { type = "addon", default = true, ui = { hidden = true }},
            headerBackdropTint = { type = "addon", default = { r = 1, g = 1, b = 1, a = 1 }, ui = { hidden = true }},

            -- Enhanced title: show session type alongside meter type (e.g., "DPS (Current)")
            showSessionInTitle = { type = "addon", default = false, ui = { hidden = true }},

            -- Right-click title text to open meter type dropdown
            titleTextRightClickMeterType = { type = "addon", default = false, ui = { hidden = true }},

            -- Text settings - Names (player names on bars)
            textNames = { type = "addon", default = {
                fontFace = "FRIZQT__",
                fontStyle = "OUTLINE",
                fontSize = 12,
                color = { 1, 1, 1, 1 },
                colorMode = "default",
                scaleMultiplier = 1.0,
            }, ui = { hidden = true }},

            -- Text settings - Numbers (DPS/HPS values)
            textNumbers = { type = "addon", default = {
                fontFace = "FRIZQT__",
                fontStyle = "OUTLINE",
                fontSize = 12,
                color = { 1, 1, 1, 1 },
                colorMode = "default",
                scaleMultiplier = 1.0,
            }, ui = { hidden = true }},

            -- Window border settings
            windowShowBorder = { type = "addon", default = false, ui = { hidden = true } },
            windowBorderStyle = { type = "addon", default = "default", ui = { hidden = true } },
            windowBorderColor = { type = "addon", default = { 1, 1, 1, 1 }, ui = { hidden = true } },
            windowBorderThickness = { type = "addon", default = 1, ui = { hidden = true } },

            -- Window background settings
            windowCustomBackdrop = { type = "addon", default = false, ui = { hidden = true } },
            windowBackdropTexture = { type = "addon", default = "default", ui = { hidden = true } },
            windowBackdropColor = { type = "addon", default = { 0.1, 0.1, 0.1, 0.9 }, ui = { hidden = true } },

            -- Export settings
            exportEnabled = { type = "addon", default = false, ui = { hidden = true } },
            exportButtonXOffset = { type = "addon", default = 0, ui = { hidden = true } },
            exportChatChannel = { type = "addon", default = "PARTY", ui = { hidden = true } },
            exportChatLineCount = { type = "addon", default = 5, ui = { hidden = true } },
            highScoreFont = { type = "addon", default = "PRESS_START_2P", ui = { hidden = true } },

            -- Quality of Life settings
            autoResetData = { type = "addon", default = "off", ui = { hidden = true } },
            autoResetPrompt = { type = "addon", default = true, ui = { hidden = true } },
        },
        ApplyStyling = ApplyDamageMeterStyling,
        RefreshOpacity = function() end,  -- OPT-13: Opacity is Edit Mode-managed; no Scoot work needed
    })

    self:RegisterComponent(damageMeter)

    -- Zone snapshot: track where data started
    if C_DamageMeter and C_DamageMeter.ResetAllCombatSessions then
        hooksecurefunc(C_DamageMeter, "ResetAllCombatSessions", SnapshotResetZone)
    end
    SnapshotResetZone()

    -- Re-snapshot after PLAYER_ENTERING_WORLD so GetInstanceInfo() has difficulty info
    local snapshotRefreshFrame = CreateFrame("Frame")
    snapshotRefreshFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    snapshotRefreshFrame:SetScript("OnEvent", function(self, _, isInitialLogin, isReloadingUi)
        if isInitialLogin or isReloadingUi then
            SnapshotResetZone()
            self:UnregisterAllEvents()
        end
    end)

    -- Event-driven restyling (replaces Rule 11-violating hooksecurefunc on system frames)
    -- DamageMeter inherits EditModeDamageMeterSystemTemplate — hooks on its tree cause taint.
    -- These events fire when Blizzard refreshes the meter, matching the old hook triggers.
    local dmEventPending = false
    local dmResetPending = false
    local dmEventFrame = CreateFrame("Frame")
    dmEventFrame:RegisterEvent("DAMAGE_METER_COMBAT_SESSION_UPDATED")
    dmEventFrame:RegisterEvent("DAMAGE_METER_RESET")
    dmEventFrame:RegisterEvent("DAMAGE_METER_CURRENT_SESSION_UPDATED")
    dmEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    dmEventFrame:SetScript("OnEvent", function(_, event)
        local comp = addon.Components and addon.Components["damageMeter"]
        if not comp or not comp.db then return end
        if event == "DAMAGE_METER_RESET" then
            dmResetPending = true
        end
        if dmEventPending then return end
        dmEventPending = true
        C_Timer.After(0, function()
            dmEventPending = nil
            if dmResetPending then
                dmResetPending = false
                hideAllDMOverlays()
            end
            if PlayerInCombat() then
                -- Combat: data-only update (bar fill + text, no style changes)
                UpdateAllOverlayData(comp)
            else
                if comp and comp.ApplyStyling then
                    comp:ApplyStyling()
                end
            end
        end)
    end)

    -- Scroll detection ticker: detects ScrollBox content changes during scrolling
    -- Also tracks DamageMeter visibility to hide/show overlays on transitions
    local scrollSignature = ""
    local dmWasShown = false
    local scrollTicker = CreateFrame("Frame")
    scrollTicker:SetScript("OnUpdate", function(self, elapsed)
        self._elapsed = (self._elapsed or 0) + elapsed
        if self._elapsed < 0.3 then return end
        self._elapsed = 0
        local dmFrame = _G.DamageMeter
        local isShown = dmFrame and dmFrame:IsShown()
        if not isShown then
            if dmWasShown then
                dmWasShown = false
                hideAllDMOverlays()
            end
            return
        end
        if not dmWasShown then
            dmWasShown = true
            -- Frame just became visible — trigger full restyle
            local comp = addon.Components and addon.Components["damageMeter"]
            if comp and comp.ApplyStyling and not PlayerInCombat() then
                comp:ApplyStyling()
            end
            return
        end
        local comp = addon.Components and addon.Components["damageMeter"]
        if not comp or not comp.db then return end
        local newSig = GetScrollSignature()
        if issecretvalue(newSig) then return end
        if newSig ~= scrollSignature then
            scrollSignature = newSig
            if PlayerInCombat() then
                UpdateAllOverlayData(comp)
            else
                comp:ApplyStyling()
            end
        end
    end)

    -- Auto-reset data event handler
    local resetFrame = CreateFrame("Frame")
    resetFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    resetFrame:SetScript("OnEvent", function(_, event, isInitialLogin, isReloadingUi)
        if isInitialLogin or isReloadingUi then return end

        local comp = addon.Components and addon.Components["damageMeter"]
        if not comp or not comp.db then return end
        local mode = comp.db.autoResetData
        if mode ~= "instance" then return end

        local inInstance, instanceType = IsInInstance()
        if not inInstance then return end
        if instanceType ~= "party" and instanceType ~= "raid" and instanceType ~= "scenario" then return end

        if not C_DamageMeter or not C_DamageMeter.ResetAllCombatSessions then return end

        if comp.db.autoResetPrompt then
            if addon.Dialogs and addon.Dialogs.Show then
                addon.Dialogs:Show("SCOOT_DM_RESET_CONFIRM", {
                    onAccept = function()
                        C_DamageMeter.ResetAllCombatSessions()
                    end,
                })
            end
        else
            C_DamageMeter.ResetAllCombatSessions()
        end
    end)

    -- Debug: /scoot debug dm frames — overlay diagnostic info in copyable window
    addon.DebugDMFrames = function()
        local lines = {}
        local function push(s) lines[#lines + 1] = s end

        local windows = GetAllSessionWindows()
        push("Session windows found: " .. #windows)
        push("")
        for i, sw in ipairs(windows) do
            local ws = windowState[sw]
            local clipFrame = ws and ws.clipFrame
            local overlayCount = windowOverlays[sw] and #windowOverlays[sw] or 0
            push(string.format("Window %d: overlays=%d, clipFrame=%s", i, overlayCount, tostring(clipFrame ~= nil)))
            if clipFrame then
                local ok, cl = pcall(clipFrame.GetFrameLevel, clipFrame)
                local ok2, cs = pcall(clipFrame.GetFrameStrata, clipFrame)
                push(string.format("  ClipFrame: level=%s, strata=%s", ok and tostring(cl) or "?", ok2 and tostring(cs) or "?"))
            end
            local entryCount = 0
            ForEachVisibleEntry(sw, function(entry)
                entryCount = entryCount + 1
                local ok, el = pcall(entry.GetFrameLevel, entry)
                local ok2, es = pcall(entry.GetFrameStrata, entry)
                local elSt = elementState[entry]
                local ov = elSt and elSt.entryOverlay
                local ovLevel, ovStrata = "none", "none"
                if ov then
                    local ok3, ol = pcall(ov.GetFrameLevel, ov)
                    local ok4, os = pcall(ov.GetFrameStrata, ov)
                    ovLevel = ok3 and tostring(ol) or "?"
                    ovStrata = ok4 and tostring(os) or "?"
                end
                push(string.format("  Entry %d: level=%s strata=%s | Overlay: level=%s strata=%s shown=%s",
                    entryCount,
                    ok and tostring(el) or "?", ok2 and tostring(es) or "?",
                    ovLevel, ovStrata,
                    ov and tostring(ov:IsShown()) or "no overlay"))
            end)
            push(string.format("  Visible entries: %d", entryCount))
            push("")
        end

        -- Include buffered error log if debug tracing was on
        if addon._debugDMLog and #addon._debugDMLog > 0 then
            push("--- Debug Log (" .. #addon._debugDMLog .. " entries) ---")
            for _, msg in ipairs(addon._debugDMLog) do
                push(msg)
            end
        end

        if addon.DebugShowWindow then
            addon.DebugShowWindow("DM Frame Diagnostics", lines)
        end
    end

    -- Toggle DM debug mode
    addon.SetDMDebug = function(enabled)
        addon._debugDM = enabled
        if addon.Print then
            addon:Print("DM debug " .. (enabled and "enabled" or "disabled"))
        end
    end
end)
