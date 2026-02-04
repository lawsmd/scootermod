--------------------------------------------------------------------------------
-- ScooterMod Minimap Component
--
-- Provides cosmetic styling for the Minimap including:
-- - Shape customization (circle/square)
-- - Custom border overlay
-- - Zone text styling with PVP colors
-- - Clock display
-- - System data display (FPS/Latency)
--
-- All overlays are parented to UIParent and anchored to Minimap to avoid taint.
-- Zero-Touch: Does nothing until user explicitly configures settings.
--------------------------------------------------------------------------------

local addonName, addon = ...

-- Module-level state
local minimapOverlays = {}  -- Weak-keyed table for overlay frames
setmetatable(minimapOverlays, { __mode = "k" })

local clockTimer = nil
local systemDataTimer = nil

-- Constants
local PVP_COLORS = {
    sanctuary = {0.41, 0.8, 0.94, 1},  -- Light blue
    friendly = {0.1, 1, 0.1, 1},       -- Green
    hostile = {1, 0.1, 0.1, 1},        -- Red
    arena = {1, 0.1, 0.1, 1},          -- Red
    contested = {1, 0.7, 0, 1},        -- Orange
    combat = {1, 0.1, 0.1, 1},         -- Red
    normal = {1, 0.82, 0, 1},          -- Gold (default)
}

local ANCHOR_OPTIONS = {
    TOP = "Top",
    TOPRIGHT = "Top Right",
    RIGHT = "Right",
    BOTTOMRIGHT = "Bottom Right",
    BOTTOM = "Bottom",
    BOTTOMLEFT = "Bottom Left",
    LEFT = "Left",
    TOPLEFT = "Top Left",
    CENTER = "Center",
}

local ANCHOR_ORDER = { "TOP", "TOPRIGHT", "RIGHT", "BOTTOMRIGHT", "BOTTOM", "BOTTOMLEFT", "LEFT", "TOPLEFT", "CENTER" }

-- Position options include "dock" for Blizzard's default positioning
local POSITION_OPTIONS = {
    dock = "Default (Dock)",
    TOP = "Top",
    TOPRIGHT = "Top Right",
    RIGHT = "Right",
    BOTTOMRIGHT = "Bottom Right",
    BOTTOM = "Bottom",
    BOTTOMLEFT = "Bottom Left",
    LEFT = "Left",
    TOPLEFT = "Top Left",
    CENTER = "Center",
}

local POSITION_ORDER = { "dock", "TOP", "TOPRIGHT", "RIGHT", "BOTTOMRIGHT", "BOTTOM", "BOTTOMLEFT", "LEFT", "TOPLEFT", "CENTER" }

--------------------------------------------------------------------------------
-- Helper Functions
--------------------------------------------------------------------------------

local function getMinimapDB()
    local comp = addon.Components and addon.Components["minimapStyle"]
    if comp and comp.db then
        -- Check for proxy DB (Zero-Touch)
        if comp._ScootDBProxy and comp.db == comp._ScootDBProxy then
            return nil
        end
        return comp.db
    end
    return nil
end

local function getClassColor()
    local _, class = UnitClass("player")
    if class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] then
        local c = RAID_CLASS_COLORS[class]
        return c.r, c.g, c.b, 1
    end
    return 1, 1, 1, 1
end

local function ensureOverlayTable()
    local minimap = _G.Minimap
    if not minimap then return nil end
    if not minimapOverlays[minimap] then
        minimapOverlays[minimap] = {}
    end
    return minimapOverlays[minimap]
end

--------------------------------------------------------------------------------
-- Shape Application
--------------------------------------------------------------------------------

-- Track if we've ever applied square mode (to know when to restore)
local hasAppliedSquare = false

-- Circular mask texture (same as what HybridMinimap uses)
local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local SQUARE_MASK = "Interface\\BUTTONS\\WHITE8X8"

-- Refresh all LibDBIcon minimap button positions
local function RefreshMinimapButtonPositions()
    local LibDBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
    if LibDBIcon and LibDBIcon.objects then
        for name, button in pairs(LibDBIcon.objects) do
            local pos = button.db and button.db.minimapPos or button.minimapPos or 225
            LibDBIcon:Refresh(name)
        end
    end
end

local function ApplyMinimapShape(db)
    local minimap = _G.Minimap
    if not minimap then return end

    local shapeChanged = false
    local newShape = db and db.mapShape or "default"

    if newShape == "square" then
        -- Apply square mask
        minimap:SetMaskTexture(SQUARE_MASK)
        hasAppliedSquare = true
        shapeChanged = true

        -- Hide circular compass border art
        if MinimapCompassTexture then
            MinimapCompassTexture:SetAlpha(0)
        end

        -- Override GetMinimapShape for addon compatibility
        _G.GetMinimapShape = function() return "SQUARE" end

        -- HybridMinimap compatibility (12.0+ dungeons/raids)
        if HybridMinimap then
            pcall(function()
                HybridMinimap.MapCanvas:SetUseMaskTexture(false)
                if HybridMinimap.CircleMask then
                    HybridMinimap.CircleMask:SetTexture(SQUARE_MASK)
                end
                HybridMinimap.MapCanvas:SetUseMaskTexture(true)
            end)
        end
    elseif hasAppliedSquare then
        -- Only restore if we previously applied square mode
        -- This maintains Zero-Touch for users who never changed the shape
        minimap:SetMaskTexture(CIRCLE_MASK)
        shapeChanged = true

        -- Restore circular compass border art
        if MinimapCompassTexture then
            MinimapCompassTexture:SetAlpha(1)
        end

        -- Restore GetMinimapShape for addon compatibility
        _G.GetMinimapShape = function() return "ROUND" end

        -- HybridMinimap compatibility - restore circular mask
        if HybridMinimap then
            pcall(function()
                HybridMinimap.MapCanvas:SetUseMaskTexture(false)
                if HybridMinimap.CircleMask then
                    HybridMinimap.CircleMask:SetTexture(CIRCLE_MASK)
                end
                HybridMinimap.MapCanvas:SetUseMaskTexture(true)
            end)
        end
    end

    -- Refresh minimap button positions after shape change
    if shapeChanged then
        C_Timer.After(0.1, RefreshMinimapButtonPositions)
    end
    -- If db is nil or mapShape is "default" and we never applied square,
    -- leave the minimap completely untouched (Zero-Touch principle)
end

--------------------------------------------------------------------------------
-- Blizzard Element Hiding (Zone Text, Clock)
--------------------------------------------------------------------------------

local blizzardZoneTextHidden = false
local blizzardClockHidden = false
local blizzardDockHidden = false
local zoneTextHookInstalled = false
local clockHookInstalled = false
local trackingBackgroundHookInstalled = false

local function HideBlizzardZoneText()
    -- Hide Blizzard's zone text button (the clickable text above minimap)
    if MinimapZoneTextButton then
        MinimapZoneTextButton:Hide()
        blizzardZoneTextHidden = true
        -- Hook to keep it hidden (only install once)
        if not zoneTextHookInstalled then
            zoneTextHookInstalled = true
            hooksecurefunc(MinimapZoneTextButton, "Show", function(self)
                local db = getMinimapDB()
                if db and (db.zoneTextHide or (db.zoneTextPosition and db.zoneTextPosition ~= "dock")) then
                    self:Hide()
                end
            end)
        end
    end

    -- Also hide the zone text in the MinimapCluster if accessible
    if MinimapCluster and MinimapCluster.ZoneTextButton then
        MinimapCluster.ZoneTextButton:Hide()
        blizzardZoneTextHidden = true
    end
end

local function ShowBlizzardZoneText()
    if not blizzardZoneTextHidden then return end
    blizzardZoneTextHidden = false

    -- Show Blizzard's zone text button
    if MinimapZoneTextButton then
        MinimapZoneTextButton:Show()
    end

    -- Also show the zone text in the MinimapCluster if accessible
    if MinimapCluster and MinimapCluster.ZoneTextButton then
        MinimapCluster.ZoneTextButton:Show()
    end
end

local function HideBlizzardClock()
    -- Hide Blizzard's clock button (only if it exists)
    if TimeManagerClockButton then
        TimeManagerClockButton:Hide()
        blizzardClockHidden = true
        -- Hook to keep it hidden (only install once)
        if not clockHookInstalled then
            clockHookInstalled = true
            hooksecurefunc(TimeManagerClockButton, "Show", function(self)
                local db = getMinimapDB()
                if db and (db.clockHide or (db.clockPosition and db.clockPosition ~= "dock")) then
                    self:Hide()
                end
            end)
        end
    end
    -- Note: If TimeManagerClockButton doesn't exist yet, the TimeManager ADDON_LOADED
    -- handler will call this again when Blizzard_TimeManager loads
end

local function ShowBlizzardClock()
    if not blizzardClockHidden then return end
    blizzardClockHidden = false

    -- Show Blizzard's clock button
    if TimeManagerClockButton then
        TimeManagerClockButton:Show()
    end
end

--------------------------------------------------------------------------------
-- Dock Visibility (BorderTop, Calendar, Tracking, Addon Compartment)
--------------------------------------------------------------------------------

-- Helper to hide tracking elements and install hook
local function HideTrackingElements()
    if not MinimapCluster or not MinimapCluster.Tracking then return end

    if MinimapCluster.Tracking.Button then
        MinimapCluster.Tracking.Button:Hide()
    end
    if MinimapCluster.Tracking.Background then
        MinimapCluster.Tracking.Background:Hide()
        -- Hook to keep it hidden (only install once)
        if not trackingBackgroundHookInstalled then
            trackingBackgroundHookInstalled = true
            hooksecurefunc(MinimapCluster.Tracking.Background, "Show", function(self)
                local db = getMinimapDB()
                if db and db.dockHide then
                    self:Hide()
                end
            end)
        end
    end
end

local function ApplyDockVisibility(db)
    if not db then return end

    local hideDock = db.dockHide

    if hideDock then
        blizzardDockHidden = true
        -- Hide the dock bar (BorderTop contains zone text area)
        if MinimapCluster and MinimapCluster.BorderTop then
            MinimapCluster.BorderTop:Hide()
        end
        -- Hide calendar button
        if GameTimeFrame then
            GameTimeFrame:Hide()
        end
        -- Hide tracking button and background
        HideTrackingElements()
        -- Deferred check for tracking elements that may load late
        C_Timer.After(0.5, function()
            local currentDb = getMinimapDB()
            if currentDb and currentDb.dockHide then
                HideTrackingElements()
            end
        end)
        -- Hide addon compartment button
        if AddonCompartmentFrame then
            AddonCompartmentFrame:Hide()
        end
    elseif blizzardDockHidden then
        blizzardDockHidden = false
        -- Restore dock bar
        if MinimapCluster and MinimapCluster.BorderTop then
            MinimapCluster.BorderTop:Show()
        end
        -- Restore calendar button
        if GameTimeFrame then
            GameTimeFrame:Show()
        end
        -- Restore tracking button and background
        if MinimapCluster and MinimapCluster.Tracking then
            if MinimapCluster.Tracking.Button then
                MinimapCluster.Tracking.Button:Show()
            end
            if MinimapCluster.Tracking.Background then
                MinimapCluster.Tracking.Background:Show()
            end
        end
        -- Restore addon compartment button
        if AddonCompartmentFrame then
            AddonCompartmentFrame:Show()
        end
    end
end

--------------------------------------------------------------------------------
-- Border Overlay
--------------------------------------------------------------------------------

local function CreateBorderOverlay()
    local overlays = ensureOverlayTable()
    if not overlays then return nil end

    if overlays.border then
        return overlays.border
    end

    local minimap = _G.Minimap

    -- Create frame parented to UIParent to avoid taint
    local border = CreateFrame("Frame", nil, UIParent)
    border:SetFrameStrata("BACKGROUND")
    border:SetFrameLevel(1)

    -- Create edge textures
    border.edges = {}

    local function createEdge(name)
        local tex = border:CreateTexture(nil, "BACKGROUND")
        tex:SetColorTexture(0, 0, 0, 1)
        border.edges[name] = tex
        return tex
    end

    createEdge("top")
    createEdge("bottom")
    createEdge("left")
    createEdge("right")

    overlays.border = border
    return border
end

local function UpdateBorderOverlay(db)
    local overlays = ensureOverlayTable()
    if not overlays then return end

    local minimap = _G.Minimap
    if not minimap then return end

    -- Only show border when square shape AND borderEnabled
    local showBorder = db and db.mapShape == "square" and db.borderEnabled

    if not showBorder then
        if overlays.border then
            overlays.border:Hide()
        end
        return
    end

    local border = overlays.border or CreateBorderOverlay()
    if not border then return end

    local thickness = tonumber(db.borderThickness) or 2
    if thickness < 1 then thickness = 1 end
    if thickness > 8 then thickness = 8 end

    -- Get color
    local r, g, b, a = 0, 0, 0, 1
    if db.borderTintEnabled and db.borderColor then
        r = db.borderColor[1] or 0
        g = db.borderColor[2] or 0
        b = db.borderColor[3] or 0
        a = db.borderColor[4] or 1
    end

    -- Position border around minimap
    border:ClearAllPoints()
    border:SetPoint("TOPLEFT", minimap, "TOPLEFT", -thickness, thickness)
    border:SetPoint("BOTTOMRIGHT", minimap, "BOTTOMRIGHT", thickness, -thickness)

    -- Position and color edges
    local edges = border.edges

    -- Top edge
    edges.top:ClearAllPoints()
    edges.top:SetPoint("TOPLEFT", border, "TOPLEFT", 0, 0)
    edges.top:SetPoint("TOPRIGHT", border, "TOPRIGHT", 0, 0)
    edges.top:SetHeight(thickness)
    edges.top:SetColorTexture(r, g, b, a)

    -- Bottom edge
    edges.bottom:ClearAllPoints()
    edges.bottom:SetPoint("BOTTOMLEFT", border, "BOTTOMLEFT", 0, 0)
    edges.bottom:SetPoint("BOTTOMRIGHT", border, "BOTTOMRIGHT", 0, 0)
    edges.bottom:SetHeight(thickness)
    edges.bottom:SetColorTexture(r, g, b, a)

    -- Left edge
    edges.left:ClearAllPoints()
    edges.left:SetPoint("TOPLEFT", border, "TOPLEFT", 0, -thickness)
    edges.left:SetPoint("BOTTOMLEFT", border, "BOTTOMLEFT", 0, thickness)
    edges.left:SetWidth(thickness)
    edges.left:SetColorTexture(r, g, b, a)

    -- Right edge
    edges.right:ClearAllPoints()
    edges.right:SetPoint("TOPRIGHT", border, "TOPRIGHT", 0, -thickness)
    edges.right:SetPoint("BOTTOMRIGHT", border, "BOTTOMRIGHT", 0, thickness)
    edges.right:SetWidth(thickness)
    edges.right:SetColorTexture(r, g, b, a)

    border:Show()
end

--------------------------------------------------------------------------------
-- Zone Text Overlay
--------------------------------------------------------------------------------

local function CreateZoneTextOverlay()
    local overlays = ensureOverlayTable()
    if not overlays then return nil end

    if overlays.zoneText then
        return overlays.zoneText
    end

    local minimap = _G.Minimap

    -- Create frame parented to UIParent
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetHeight(20)
    frame:EnableMouse(false)

    local fontString = frame:CreateFontString(nil, "OVERLAY")
    fontString:SetPoint("CENTER", frame, "CENTER", 0, 0)
    fontString:SetJustifyH("CENTER")
    frame.fontString = fontString

    overlays.zoneText = frame
    return frame
end

local function UpdateZoneTextColor(fontString, db)
    if not fontString then return end

    local r, g, b, a = 1, 0.82, 0, 1  -- Default gold

    if db.zoneTextColorMode == "custom" and db.zoneTextCustomColor then
        r = db.zoneTextCustomColor[1] or 1
        g = db.zoneTextCustomColor[2] or 0.82
        b = db.zoneTextCustomColor[3] or 0
        a = db.zoneTextCustomColor[4] or 1
    else
        -- PVP type color
        local pvpType = C_PvP and C_PvP.GetZonePVPInfo() or GetZonePVPInfo()
        pvpType = pvpType or "normal"

        local color = PVP_COLORS[pvpType] or PVP_COLORS.normal
        r, g, b, a = color[1], color[2], color[3], color[4]
    end

    fontString:SetTextColor(r, g, b, a)
end

local function UpdateZoneText()
    local db = getMinimapDB()
    if not db then return end

    local overlays = ensureOverlayTable()
    if not overlays or not overlays.zoneText then return end

    local fontString = overlays.zoneText.fontString
    if not fontString then return end

    local text = GetMinimapZoneText() or ""
    fontString:SetText(text)
    UpdateZoneTextColor(fontString, db)
end

-- Apply font settings to Blizzard's zone text FontString
local function ApplyFontToBlizzardZoneText(db)
    if not db then return end

    -- Get the FontString - MinimapZoneText is the actual text element
    local fontString = _G.MinimapZoneText
    if not fontString then return end

    -- Apply font settings
    local fontFace = addon.ResolveFontFace and addon.ResolveFontFace(db.zoneTextFont or "FRIZQT__")
        or (select(1, _G.GameFontNormal:GetFont()))
    local fontSize = tonumber(db.zoneTextFontSize) or 12
    local fontStyle = db.zoneTextFontStyle or "OUTLINE"
    if fontStyle == "NONE" then fontStyle = "" end

    pcall(function()
        fontString:SetFont(fontFace, fontSize, fontStyle)
    end)

    -- Apply color
    UpdateZoneTextColor(fontString, db)
end

local function ApplyZoneTextStyle(db)
    local overlays = ensureOverlayTable()
    if not overlays then return end

    local minimap = _G.Minimap
    if not minimap then return end

    -- Hide our overlay if user chose to hide zone text
    if not db or db.zoneTextHide then
        if overlays.zoneText then
            overlays.zoneText:Hide()
        end
        -- When hiding, also hide Blizzard's if we're managing it
        if db then
            HideBlizzardZoneText()
        end
        return
    end

    -- Check position setting (support both old zoneTextAnchor and new zoneTextPosition)
    local position = db.zoneTextPosition or db.zoneTextAnchor or "dock"

    if position == "dock" then
        -- Show Blizzard's zone text (unless dock is hidden)
        if not db.dockHide then
            ShowBlizzardZoneText()
        end
        -- Apply our font/color settings to Blizzard's FontString
        ApplyFontToBlizzardZoneText(db)
        -- Hide our overlay
        if overlays.zoneText then
            overlays.zoneText:Hide()
        end
        return
    end

    -- Custom position: Hide Blizzard's zone text, show our overlay
    HideBlizzardZoneText()

    local frame = overlays.zoneText or CreateZoneTextOverlay()
    if not frame then return end

    local fontString = frame.fontString
    if not fontString then return end

    -- Apply font settings
    local fontFace = addon.ResolveFontFace and addon.ResolveFontFace(db.zoneTextFont or "FRIZQT__")
        or (select(1, _G.GameFontNormal:GetFont()))
    local fontSize = tonumber(db.zoneTextFontSize) or 12
    local fontStyle = db.zoneTextFontStyle or "OUTLINE"
    if fontStyle == "NONE" then fontStyle = "" end

    fontString:SetFont(fontFace, fontSize, fontStyle)

    -- Position using the custom anchor
    local offsetX = tonumber(db.zoneTextOffsetX) or 0
    local offsetY = tonumber(db.zoneTextOffsetY) or 0

    frame:ClearAllPoints()
    frame:SetPoint(position, minimap, position, offsetX, offsetY)
    frame:SetWidth(minimap:GetWidth() - 10)

    -- Update text and color
    local text = GetMinimapZoneText() or ""
    fontString:SetText(text)
    UpdateZoneTextColor(fontString, db)

    frame:Show()
end

--------------------------------------------------------------------------------
-- Clock Overlay
--------------------------------------------------------------------------------

local function CreateClockOverlay()
    local overlays = ensureOverlayTable()
    if not overlays then return nil end

    if overlays.clock then
        return overlays.clock
    end

    local minimap = _G.Minimap

    -- Create frame parented to UIParent
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetHeight(20)
    frame:EnableMouse(false)

    local fontString = frame:CreateFontString(nil, "OVERLAY")
    fontString:SetPoint("CENTER", frame, "CENTER", 0, 0)
    fontString:SetJustifyH("CENTER")
    frame.fontString = fontString

    overlays.clock = frame
    return frame
end

local function UpdateClockText()
    local db = getMinimapDB()
    if not db or db.clockHide then return end

    -- If position is "dock", we don't update our overlay (Blizzard handles it)
    local position = db.clockPosition or db.clockAnchor or "dock"
    if position == "dock" then return end

    local overlays = ensureOverlayTable()
    if not overlays or not overlays.clock then return end

    local fontString = overlays.clock.fontString
    if not fontString then return end

    local hour, minute
    if db.clockTimeSource == "server" then
        hour, minute = GetGameTime()
    else
        hour, minute = tonumber(date("%H")), tonumber(date("%M"))
    end

    local text
    if db.clockUse24Hour then
        text = string.format("%02d:%02d", hour, minute)
    else
        local suffix = hour >= 12 and "PM" or "AM"
        hour = hour % 12
        if hour == 0 then hour = 12 end
        text = string.format("%d:%02d %s", hour, minute, suffix)
    end

    fontString:SetText(text)

    -- Schedule next update
    if clockTimer then
        clockTimer:Cancel()
        clockTimer = nil
    end
    clockTimer = C_Timer.NewTimer(60, UpdateClockText)
end

-- Apply font/color settings to Blizzard's clock FontString
local function ApplyFontToBlizzardClock(db)
    if not db then return end

    -- Get the FontString - TimeManagerClockTicker is the actual text element
    local fontString = _G.TimeManagerClockTicker
    if not fontString and TimeManagerClockButton then
        fontString = TimeManagerClockButton.TimeManagerClockTicker
    end
    if not fontString then return end

    -- Apply font settings
    local fontFace = addon.ResolveFontFace and addon.ResolveFontFace(db.clockFont or "FRIZQT__")
        or (select(1, _G.GameFontNormal:GetFont()))
    local fontSize = tonumber(db.clockFontSize) or 12
    local fontStyle = db.clockFontStyle or "OUTLINE"
    if fontStyle == "NONE" then fontStyle = "" end

    pcall(function()
        fontString:SetFont(fontFace, fontSize, fontStyle)
    end)

    -- Apply color
    local r, g, b, a = 1, 1, 1, 1
    if db.clockColorMode == "class" then
        r, g, b, a = getClassColor()
    elseif db.clockColorMode == "custom" and db.clockCustomColor then
        r = db.clockCustomColor[1] or 1
        g = db.clockCustomColor[2] or 1
        b = db.clockCustomColor[3] or 1
        a = db.clockCustomColor[4] or 1
    end

    pcall(function()
        fontString:SetTextColor(r, g, b, a)
    end)
end

local function ApplyClockStyle(db)
    local overlays = ensureOverlayTable()
    if not overlays then return end

    local minimap = _G.Minimap
    if not minimap then return end

    -- Cancel existing timer
    if clockTimer then
        clockTimer:Cancel()
        clockTimer = nil
    end

    -- Hide our overlay if user chose to hide clock
    if not db or db.clockHide then
        if overlays.clock then
            overlays.clock:Hide()
        end
        -- When hiding, also hide Blizzard's if we're managing it
        if db then
            HideBlizzardClock()
        end
        return
    end

    -- Check position setting (support both old clockAnchor and new clockPosition)
    local position = db.clockPosition or db.clockAnchor or "dock"

    if position == "dock" then
        -- Show Blizzard's clock (unless dock is hidden)
        if not db.dockHide then
            ShowBlizzardClock()
        end
        -- Apply our font/color settings to Blizzard's FontString
        ApplyFontToBlizzardClock(db)
        -- Hide our overlay
        if overlays.clock then
            overlays.clock:Hide()
        end
        return
    end

    -- Custom position: Hide Blizzard's clock, show our overlay
    HideBlizzardClock()

    local frame = overlays.clock or CreateClockOverlay()
    if not frame then return end

    local fontString = frame.fontString
    if not fontString then return end

    -- Apply font settings
    local fontFace = addon.ResolveFontFace and addon.ResolveFontFace(db.clockFont or "FRIZQT__")
        or (select(1, _G.GameFontNormal:GetFont()))
    local fontSize = tonumber(db.clockFontSize) or 12
    local fontStyle = db.clockFontStyle or "OUTLINE"
    if fontStyle == "NONE" then fontStyle = "" end

    fontString:SetFont(fontFace, fontSize, fontStyle)

    -- Apply color
    local r, g, b, a = 1, 1, 1, 1
    if db.clockColorMode == "class" then
        r, g, b, a = getClassColor()
    elseif db.clockColorMode == "custom" and db.clockCustomColor then
        r = db.clockCustomColor[1] or 1
        g = db.clockCustomColor[2] or 1
        b = db.clockCustomColor[3] or 1
        a = db.clockCustomColor[4] or 1
    end
    fontString:SetTextColor(r, g, b, a)

    -- Position using the custom anchor
    local offsetX = tonumber(db.clockOffsetX) or 0
    local offsetY = tonumber(db.clockOffsetY) or 0

    frame:ClearAllPoints()
    frame:SetPoint(position, minimap, position, offsetX, offsetY)
    frame:SetWidth(minimap:GetWidth())

    frame:Show()

    -- Start clock updates
    UpdateClockText()
end

--------------------------------------------------------------------------------
-- System Data Overlay (FPS/Latency)
--------------------------------------------------------------------------------

local function CreateSystemDataOverlay()
    local overlays = ensureOverlayTable()
    if not overlays then return nil end

    if overlays.systemData then
        return overlays.systemData
    end

    local minimap = _G.Minimap

    -- Create frame parented to UIParent
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetHeight(20)
    frame:EnableMouse(false)

    local fontString = frame:CreateFontString(nil, "OVERLAY")
    fontString:SetPoint("CENTER", frame, "CENTER", 0, 0)
    fontString:SetJustifyH("CENTER")
    frame.fontString = fontString

    overlays.systemData = frame
    return frame
end

local function UpdateSystemDataText()
    local db = getMinimapDB()
    if not db then return end

    -- Check if anything is enabled to show
    local showFPS = db.systemDataShowFPS
    local showLatency = db.systemDataShowLatency
    if not showFPS and not showLatency then return end

    local overlays = ensureOverlayTable()
    if not overlays or not overlays.systemData then return end

    local fontString = overlays.systemData.fontString
    if not fontString then return end

    local parts = {}

    if showFPS then
        local fps = math.floor(GetFramerate())
        table.insert(parts, string.format("%d FPS", fps))
    end

    if showLatency then
        local _, _, latencyHome, latencyWorld = GetNetStats()
        local latency = db.systemDataLatencySource == "world" and latencyWorld or latencyHome
        table.insert(parts, string.format("%d MS", latency or 0))
    end

    local text = table.concat(parts, " | ")
    fontString:SetText(text)

    -- Schedule next update (every 2 seconds)
    if systemDataTimer then
        systemDataTimer:Cancel()
        systemDataTimer = nil
    end
    systemDataTimer = C_Timer.NewTimer(2, UpdateSystemDataText)
end

local function ApplySystemDataStyle(db)
    local overlays = ensureOverlayTable()
    if not overlays then return end

    local minimap = _G.Minimap
    if not minimap then return end

    -- Cancel existing timer
    if systemDataTimer then
        systemDataTimer:Cancel()
        systemDataTimer = nil
    end

    -- Hide if neither FPS nor Latency is enabled
    local showFPS = db and db.systemDataShowFPS
    local showLatency = db and db.systemDataShowLatency

    if not db or (not showFPS and not showLatency) then
        if overlays.systemData then
            overlays.systemData:Hide()
        end
        return
    end

    local frame = overlays.systemData or CreateSystemDataOverlay()
    if not frame then return end

    local fontString = frame.fontString
    if not fontString then return end

    -- Apply font settings
    local fontFace = addon.ResolveFontFace and addon.ResolveFontFace(db.systemDataFont or "FRIZQT__")
        or (select(1, _G.GameFontNormal:GetFont()))
    local fontSize = tonumber(db.systemDataFontSize) or 11
    local fontStyle = db.systemDataFontStyle or "OUTLINE"
    if fontStyle == "NONE" then fontStyle = "" end

    fontString:SetFont(fontFace, fontSize, fontStyle)

    -- Apply color
    local r, g, b, a = 1, 1, 1, 1
    if db.systemDataColorMode == "class" then
        r, g, b, a = getClassColor()
    elseif db.systemDataColorMode == "custom" and db.systemDataCustomColor then
        r = db.systemDataCustomColor[1] or 1
        g = db.systemDataCustomColor[2] or 1
        b = db.systemDataCustomColor[3] or 1
        a = db.systemDataCustomColor[4] or 1
    end
    fontString:SetTextColor(r, g, b, a)

    -- Position
    local anchor = db.systemDataAnchor or "BOTTOM"
    local offsetX = tonumber(db.systemDataOffsetX) or 0
    local offsetY = tonumber(db.systemDataOffsetY) or -18

    frame:ClearAllPoints()
    frame:SetPoint(anchor, minimap, anchor, offsetX, offsetY)
    frame:SetWidth(minimap:GetWidth())

    frame:Show()

    -- Start updates
    UpdateSystemDataText()
end

--------------------------------------------------------------------------------
-- Event Handler for Zone Changes
--------------------------------------------------------------------------------

local zoneEventFrame = nil

local function EnsureZoneEventHandler()
    if zoneEventFrame then return end

    zoneEventFrame = CreateFrame("Frame")
    zoneEventFrame:RegisterEvent("ZONE_CHANGED")
    zoneEventFrame:RegisterEvent("ZONE_CHANGED_INDOORS")
    zoneEventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    zoneEventFrame:SetScript("OnEvent", function()
        UpdateZoneText()
    end)
end

--------------------------------------------------------------------------------
-- HybridMinimap Handler
--------------------------------------------------------------------------------

local addonLoadedFrame = nil

local function EnsureAddonLoadedHandler()
    if addonLoadedFrame then return end

    addonLoadedFrame = CreateFrame("Frame")
    addonLoadedFrame:RegisterEvent("ADDON_LOADED")
    addonLoadedFrame:SetScript("OnEvent", function(self, event, loadedAddon)
        if event ~= "ADDON_LOADED" then return end

        local db = getMinimapDB()
        if not db then return end

        if loadedAddon == "Blizzard_HybridMinimap" then
            ApplyMinimapShape(db)
        elseif loadedAddon == "Blizzard_TimeManager" then
            -- TimeManager just loaded - apply clock settings now that TimeManagerClockButton exists
            ApplyClockStyle(db)
        end
    end)
end

--------------------------------------------------------------------------------
-- Main Apply Styling Function
--------------------------------------------------------------------------------

local function ApplyMinimapStyling(self)
    local db = self.db

    -- Zero-Touch: Check for proxy DB (means no config)
    if self._ScootDBProxy and db == self._ScootDBProxy then
        return
    end

    if not db then return end

    -- Ensure event handlers are set up
    EnsureZoneEventHandler()
    EnsureAddonLoadedHandler()

    -- Apply shape
    ApplyMinimapShape(db)

    -- Apply border
    UpdateBorderOverlay(db)

    -- Apply dock visibility (must be before zone/clock to control BorderTop)
    ApplyDockVisibility(db)

    -- Apply zone text
    ApplyZoneTextStyle(db)

    -- Apply clock
    ApplyClockStyle(db)

    -- Apply system data
    ApplySystemDataStyle(db)
end

--------------------------------------------------------------------------------
-- Component Registration
--------------------------------------------------------------------------------

addon:RegisterComponentInitializer(function(self)
    local Component = addon.ComponentPrototype

    local minimapComponent = Component:New({
        id = "minimapStyle",
        name = "Minimap",
        frameName = "MinimapCluster",  -- Edit Mode-managed frame
        settings = {
            -- Map Style (Addon-only settings)
            -- Note: Map Size is read/written directly to Edit Mode, not stored in AceDB
            mapShape = { type = "addon", default = "default" },
            borderEnabled = { type = "addon", default = false },
            borderTintEnabled = { type = "addon", default = false },
            borderColor = { type = "addon", default = {0, 0, 0, 1} },
            borderThickness = { type = "addon", default = 2 },

            -- Dock
            dockHide = { type = "addon", default = false },

            -- Zone Text
            zoneTextHide = { type = "addon", default = false },
            zoneTextPosition = { type = "addon", default = "dock" },  -- "dock" shows Blizzard's, others show overlay
            zoneTextColorMode = { type = "addon", default = "pvp" },
            zoneTextCustomColor = { type = "addon", default = {1, 0.82, 0, 1} },
            zoneTextFont = { type = "addon", default = "FRIZQT__" },
            zoneTextFontSize = { type = "addon", default = 12 },
            zoneTextFontStyle = { type = "addon", default = "OUTLINE" },
            zoneTextAnchor = { type = "addon", default = "TOP" },  -- Legacy, kept for backwards compat
            zoneTextOffsetX = { type = "addon", default = 0 },
            zoneTextOffsetY = { type = "addon", default = 0 },

            -- Clock
            clockHide = { type = "addon", default = false },
            clockPosition = { type = "addon", default = "dock" },  -- "dock" shows Blizzard's, others show overlay
            clockTimeSource = { type = "addon", default = "local" },
            clockUse24Hour = { type = "addon", default = false },
            clockFont = { type = "addon", default = "FRIZQT__" },
            clockFontSize = { type = "addon", default = 12 },
            clockFontStyle = { type = "addon", default = "OUTLINE" },
            clockColorMode = { type = "addon", default = "default" },
            clockCustomColor = { type = "addon", default = {1, 1, 1, 1} },
            clockAnchor = { type = "addon", default = "BOTTOM" },  -- Legacy, kept for backwards compat
            clockOffsetX = { type = "addon", default = 0 },
            clockOffsetY = { type = "addon", default = 0 },

            -- System Data (visibility determined by showFPS/showLatency)
            systemDataShowFPS = { type = "addon", default = false },
            systemDataShowLatency = { type = "addon", default = false },
            systemDataLatencySource = { type = "addon", default = "home" },
            systemDataFont = { type = "addon", default = "FRIZQT__" },
            systemDataFontSize = { type = "addon", default = 11 },
            systemDataFontStyle = { type = "addon", default = "OUTLINE" },
            systemDataColorMode = { type = "addon", default = "default" },
            systemDataCustomColor = { type = "addon", default = {1, 1, 1, 1} },
            systemDataAnchor = { type = "addon", default = "BOTTOM" },
            systemDataOffsetX = { type = "addon", default = 0 },
            systemDataOffsetY = { type = "addon", default = -18 },
        },
        ApplyStyling = ApplyMinimapStyling,
    })

    self:RegisterComponent(minimapComponent)
end)

-- Export anchor/position options for UI
addon.MinimapAnchorOptions = ANCHOR_OPTIONS
addon.MinimapAnchorOrder = ANCHOR_ORDER
addon.MinimapPositionOptions = POSITION_OPTIONS
addon.MinimapPositionOrder = POSITION_ORDER

--------------------------------------------------------------------------------
-- Edit Mode Size Helpers (for UI)
--------------------------------------------------------------------------------

-- Read Edit Mode Map Size setting
function addon.getEditModeMinimapSize()
    local frame = _G.MinimapCluster
    local settingId = _G.Enum and _G.Enum.EditModeMinimapSetting and _G.Enum.EditModeMinimapSetting.Size
    if frame and settingId and addon and addon.EditMode and addon.EditMode.GetSetting then
        local v = addon.EditMode.GetSetting(frame, settingId)
        -- Edit Mode stores as 0-15 (index), which maps to 50-200% (raw)
        -- LibEditModeOverride should convert this, but handle both cases
        if v ~= nil then
            if v <= 15 then
                -- Index-based: convert to raw percent
                return 50 + (v * 10)
            else
                -- Already raw percent
                return math.max(50, math.min(200, v))
            end
        end
    end
    return 100
end

-- Write Edit Mode Map Size setting
function addon.setEditModeMinimapSize(value)
    local frame = _G.MinimapCluster
    local settingId = _G.Enum and _G.Enum.EditModeMinimapSetting and _G.Enum.EditModeMinimapSetting.Size
    if frame and settingId and addon and addon.EditMode and addon.EditMode.WriteSetting then
        -- Pass raw percent (50-200) - LibEditModeOverride handles index conversion
        local v = math.max(50, math.min(200, value or 100))
        v = math.floor(v / 10 + 0.5) * 10
        addon.EditMode.WriteSetting(frame, settingId, v, {
            suspendDuration = 0.25,
        })
    end
end
