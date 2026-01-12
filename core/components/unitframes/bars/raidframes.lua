--------------------------------------------------------------------------------
-- bars/raidframes.lua
-- Raid frame health bar and text styling
--
-- Applies styling to CompactRaidGroup*Member* and CompactRaidFrame* frames.
-- Uses combat-safe overlay patterns for persistence during combat.
--------------------------------------------------------------------------------

local addonName, addon = ...

-- Get modules
local Utils = addon.BarsUtils
local Combat = addon.BarsCombat

-- Create module namespace
addon.BarsRaidFrames = addon.BarsRaidFrames or {}
local RaidFrames = addon.BarsRaidFrames

--------------------------------------------------------------------------------
-- Raid Frame Detection
--------------------------------------------------------------------------------

function RaidFrames.isRaidFrame(frame)
    return Utils.isRaidFrame(frame)
end

function RaidFrames.isRaidHealthBar(frame)
    if not frame or not frame.healthBar then return false end
    return Utils.isRaidFrame(frame)
end

--------------------------------------------------------------------------------
-- Health Bar Collection
--------------------------------------------------------------------------------

local raidHealthBars = {}

function RaidFrames.collectHealthBars()
    raidHealthBars = {}
    -- Pattern 1: Group-based naming (CompactRaidGroup1Member1HealthBar, etc.)
    for group = 1, 8 do
        for member = 1, 5 do
            local frameName = "CompactRaidGroup" .. group .. "Member" .. member .. "HealthBar"
            local bar = _G[frameName]
            if bar then
                table.insert(raidHealthBars, bar)
            end
        end
    end
    -- Pattern 2: Combined naming (CompactRaidFrame1HealthBar, etc.)
    for i = 1, 40 do
        local frameName = "CompactRaidFrame" .. i .. "HealthBar"
        local bar = _G[frameName]
        if bar and not bar._ScootRaidBarCounted then
            bar._ScootRaidBarCounted = true
            table.insert(raidHealthBars, bar)
        end
    end
    return raidHealthBars
end

--------------------------------------------------------------------------------
-- Health Bar Styling
--------------------------------------------------------------------------------

function RaidFrames.applyToHealthBar(bar, cfg)
    if not bar then return end

    local texKey = cfg.healthBarTexture or "default"
    local colorMode = cfg.healthBarColorMode or "default"
    local tint = cfg.healthBarTint
    local bgTexKey = cfg.healthBarBackgroundTexture or "default"
    local bgColorMode = cfg.healthBarBackgroundColorMode or "default"
    local bgTint = cfg.healthBarBackgroundTint
    local bgOpacity = cfg.healthBarBackgroundOpacity or 50

    -- Apply foreground texture and color
    if addon._ApplyToStatusBar then
        addon._ApplyToStatusBar(bar, texKey, colorMode, tint, nil, "health", nil)
    end

    -- Apply background texture and color
    if addon._ApplyBackgroundToStatusBar then
        addon._ApplyBackgroundToStatusBar(bar, bgTexKey, bgColorMode, bgTint, bgOpacity, "Raid", "health")
    end
end

--------------------------------------------------------------------------------
-- Health Bar Overlay (Combat-Safe Persistence)
--------------------------------------------------------------------------------

-- Update overlay width based on health bar value
local function updateHealthOverlay(bar)
    if not bar or not bar.ScooterRaidHealthFill then return end
    if not bar._ScootRaidOverlayActive then
        bar.ScooterRaidHealthFill:Hide()
        return
    end

    local overlay = bar.ScooterRaidHealthFill
    local totalWidth = bar:GetWidth() or 0
    local minVal, maxVal = bar:GetMinMaxValues()
    local value = bar:GetValue() or minVal

    if not totalWidth or totalWidth <= 0 or not maxVal or maxVal <= minVal then
        overlay:Hide()
        return
    end

    local frac = (value - minVal) / (maxVal - minVal)
    if frac <= 0 then
        overlay:Hide()
        return
    end
    if frac > 1 then frac = 1 end

    overlay:Show()
    overlay:SetWidth(totalWidth * frac)
    overlay:ClearAllPoints()
    overlay:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    overlay:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
end

-- Style the overlay texture and color
local function styleHealthOverlay(bar, cfg)
    if not bar or not bar.ScooterRaidHealthFill or not cfg then return end

    local overlay = bar.ScooterRaidHealthFill
    local texKey = cfg.healthBarTexture or "default"
    local colorMode = cfg.healthBarColorMode or "default"
    local tint = cfg.healthBarTint

    local resolvedPath = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(texKey)

    if resolvedPath then
        overlay:SetTexture(resolvedPath)
    else
        local tex = bar:GetStatusBarTexture()
        local applied = false
        if tex then
            local okAtlas, atlasName = pcall(tex.GetAtlas, tex)
            if okAtlas and atlasName and atlasName ~= "" then
                if overlay.SetAtlas then
                    pcall(overlay.SetAtlas, overlay, atlasName, true)
                    applied = true
                end
            end
            if not applied then
                local okTex, texPath = pcall(tex.GetTexture, tex)
                if okTex and texPath then
                    if type(texPath) == "string" and texPath:match("^[A-Za-z]") and not texPath:match("\\") and not texPath:match("/") then
                        if overlay.SetAtlas then
                            pcall(overlay.SetAtlas, overlay, texPath, true)
                            applied = true
                        end
                    elseif type(texPath) == "number" or (type(texPath) == "string" and (texPath:match("\\") or texPath:match("/"))) then
                        pcall(overlay.SetTexture, overlay, texPath)
                        applied = true
                    end
                end
            end
        end
        if not applied then
            overlay:SetTexture("Interface\\Buttons\\WHITE8x8")
        end
    end

    local r, g, b, a = 1, 1, 1, 1
    if colorMode == "custom" and type(tint) == "table" then
        r, g, b, a = tint[1] or 1, tint[2] or 1, tint[3] or 1, tint[4] or 1
    elseif colorMode == "class" then
        r, g, b, a = 0, 1, 0, 1
    elseif colorMode == "texture" then
        r, g, b, a = 1, 1, 1, 1
    else
        local barR, barG, barB = bar:GetStatusBarColor()
        if barR then
            r, g, b = barR, barG, barB
        else
            r, g, b = 0, 1, 0
        end
    end
    overlay:SetVertexColor(r, g, b, a)
end

-- Hide Blizzard's fill texture
local function hideBlizzardFill(bar)
    if not bar then return end
    local blizzFill = bar:GetStatusBarTexture()
    if not blizzFill then return end

    blizzFill._ScootHidden = true
    blizzFill:SetAlpha(0)

    if not blizzFill._ScootAlphaHooked and _G.hooksecurefunc then
        blizzFill._ScootAlphaHooked = true
        _G.hooksecurefunc(blizzFill, "SetAlpha", function(self, alpha)
            if alpha > 0 and self._ScootHidden then
                if _G.C_Timer and _G.C_Timer.After then
                    _G.C_Timer.After(0, function()
                        if self._ScootHidden then
                            self:SetAlpha(0)
                        end
                    end)
                end
            end
        end)
    end
end

-- Show Blizzard's fill texture
local function showBlizzardFill(bar)
    if not bar then return end
    local blizzFill = bar:GetStatusBarTexture()
    if blizzFill then
        blizzFill._ScootHidden = nil
        blizzFill:SetAlpha(1)
    end
end

-- Create or update the health overlay
function RaidFrames.ensureHealthOverlay(bar, cfg)
    if not bar then return end

    local hasCustom = cfg and (
        (cfg.healthBarTexture and cfg.healthBarTexture ~= "default") or
        (cfg.healthBarColorMode and cfg.healthBarColorMode ~= "default")
    )

    bar._ScootRaidOverlayActive = hasCustom

    if not hasCustom then
        if bar.ScooterRaidHealthFill then
            bar.ScooterRaidHealthFill:Hide()
        end
        showBlizzardFill(bar)
        return
    end

    if not bar.ScooterRaidHealthFill then
        -- IMPORTANT: This overlay must NOT be parented to the StatusBar.
        -- WoW draws all parent frame layers first, then all child frame layers.
        -- If we parent to the health bar (child), our overlay can draw *above*
        -- CompactUnitFrame parent-layer elements like roleIcon (ARTWORK) and
        -- readyCheckIcon (OVERLAY), effectively hiding them.
        --
        -- Fix: parent the overlay to the CompactUnitFrame (the health bar's parent)
        -- and draw it in BORDER sublevel 7 so it stays above heal-prediction layers
        -- but below role/ready-check indicators.
        local unitFrame = (bar.GetParent and bar:GetParent()) or nil
        local overlayParent = unitFrame or bar
        local overlay = overlayParent:CreateTexture(nil, "BORDER", nil, 7)
        overlay:SetVertTile(false)
        overlay:SetHorizTile(false)
        overlay:SetTexCoord(0, 1, 0, 1)
        bar.ScooterRaidHealthFill = overlay

        if _G.hooksecurefunc and not bar._ScootRaidOverlayHooksInstalled then
            bar._ScootRaidOverlayHooksInstalled = true
            _G.hooksecurefunc(bar, "SetValue", function(self)
                updateHealthOverlay(self)
            end)
            _G.hooksecurefunc(bar, "SetMinMaxValues", function(self)
                updateHealthOverlay(self)
            end)
            if bar.HookScript then
                bar:HookScript("OnSizeChanged", function(self)
                    updateHealthOverlay(self)
                end)
            end
        end
    end

    if not bar._ScootRaidTextureSwapHooked and _G.hooksecurefunc then
        bar._ScootRaidTextureSwapHooked = true
        _G.hooksecurefunc(bar, "SetStatusBarTexture", function(self)
            if self._ScootRaidOverlayActive then
                if _G.C_Timer and _G.C_Timer.After then
                    _G.C_Timer.After(0, function()
                        hideBlizzardFill(self)
                    end)
                end
            end
        end)
    end

    styleHealthOverlay(bar, cfg)
    hideBlizzardFill(bar)
    updateHealthOverlay(bar)
end

function RaidFrames.disableHealthOverlay(bar)
    if not bar then return end
    bar._ScootRaidOverlayActive = false
    if bar.ScooterRaidHealthFill then
        bar.ScooterRaidHealthFill:Hide()
    end
    showBlizzardFill(bar)
end

--------------------------------------------------------------------------------
-- Text Overlay (Name Text)
--------------------------------------------------------------------------------

-- Styling and visibility for raid name overlays
function RaidFrames.styleNameOverlay(nameOverlay, cfg)
    if not nameOverlay or not cfg then return end

    -- Get text settings
    local textCfg = cfg.nameText or cfg
    local fontFace = textCfg.fontFace or "FRIZQT__"
    local size = textCfg.size or 12
    local style = textCfg.style or "OUTLINE"
    local color = textCfg.color or {1, 1, 1, 1}
    local anchor = textCfg.anchor or "TOPLEFT"
    local offset = textCfg.offset or {x = 0, y = 0}

    -- Resolve font path
    local fontPath = addon.Media and addon.Media.ResolveFontPath and addon.Media.ResolveFontPath(fontFace)
    if fontPath and nameOverlay.SetFont then
        pcall(nameOverlay.SetFont, nameOverlay, fontPath, size, style)
    end

    if nameOverlay.SetTextColor then
        pcall(nameOverlay.SetTextColor, nameOverlay, color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
    end

    if nameOverlay.SetJustifyH then
        pcall(nameOverlay.SetJustifyH, nameOverlay, Utils.getJustifyHFromAnchor(anchor))
    end
end

--------------------------------------------------------------------------------
-- Public API Functions
--------------------------------------------------------------------------------

-- Main entry point: Apply raid frame health bar styling from DB settings
function addon.ApplyRaidFrameHealthBarStyle()
    local db = addon and addon.db and addon.db.profile
    if not db then return end

    local groupFrames = rawget(db, "groupFrames")
    local cfg = groupFrames and rawget(groupFrames, "raid") or nil
    if not cfg then return end

    local hasCustom = (cfg.healthBarTexture and cfg.healthBarTexture ~= "default") or
                      (cfg.healthBarColorMode and cfg.healthBarColorMode ~= "default") or
                      (cfg.healthBarBackgroundTexture and cfg.healthBarBackgroundTexture ~= "default") or
                      (cfg.healthBarBackgroundColorMode and cfg.healthBarBackgroundColorMode ~= "default")
    if not hasCustom then return end

    if InCombatLockdown and InCombatLockdown() then
        Combat.queueRaidFrameReapply()
        return
    end

    RaidFrames.collectHealthBars()
    for _, bar in ipairs(raidHealthBars) do
        RaidFrames.applyToHealthBar(bar, cfg)
    end
    for _, bar in ipairs(raidHealthBars) do
        bar._ScootRaidBarCounted = nil
    end
end

-- Apply overlays to all raid health bars
function addon.ApplyRaidFrameHealthOverlays()
    local db = addon and addon.db and addon.db.profile
    if not db then return end

    local groupFrames = rawget(db, "groupFrames")
    local cfg = groupFrames and rawget(groupFrames, "raid") or nil

    local hasCustom = cfg and (
        (cfg.healthBarTexture and cfg.healthBarTexture ~= "default") or
        (cfg.healthBarColorMode and cfg.healthBarColorMode ~= "default")
    )

    -- Combined layout
    for i = 1, 40 do
        local bar = _G["CompactRaidFrame" .. i .. "HealthBar"]
        if bar then
            if hasCustom then
                if not (InCombatLockdown and InCombatLockdown()) then
                    RaidFrames.ensureHealthOverlay(bar, cfg)
                elseif bar.ScooterRaidHealthFill then
                    styleHealthOverlay(bar, cfg)
                    updateHealthOverlay(bar)
                end
            else
                RaidFrames.disableHealthOverlay(bar)
            end
        end
    end

    -- Group layout
    for group = 1, 8 do
        for member = 1, 5 do
            local bar = _G["CompactRaidGroup" .. group .. "Member" .. member .. "HealthBar"]
            if bar then
                if hasCustom then
                    if not (InCombatLockdown and InCombatLockdown()) then
                        RaidFrames.ensureHealthOverlay(bar, cfg)
                    elseif bar.ScooterRaidHealthFill then
                        styleHealthOverlay(bar, cfg)
                        updateHealthOverlay(bar)
                    end
                else
                    RaidFrames.disableHealthOverlay(bar)
                end
            end
        end
    end
end

-- Restore all raid health bars to stock appearance
function addon.RestoreRaidFrameHealthOverlays()
    -- Combined layout
    for i = 1, 40 do
        local bar = _G["CompactRaidFrame" .. i .. "HealthBar"]
        if bar then
            RaidFrames.disableHealthOverlay(bar)
        end
    end
    -- Group layout
    for group = 1, 8 do
        for member = 1, 5 do
            local bar = _G["CompactRaidGroup" .. group .. "Member" .. member .. "HealthBar"]
            if bar then
                RaidFrames.disableHealthOverlay(bar)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Hook Installation
--------------------------------------------------------------------------------

function RaidFrames.installHooks()
    if addon._RaidFrameHooksInstalled then return end
    addon._RaidFrameHooksInstalled = true

    -- Hook CompactUnitFrame_UpdateAll
    if _G.hooksecurefunc and _G.CompactUnitFrame_UpdateAll then
        _G.hooksecurefunc("CompactUnitFrame_UpdateAll", function(frame)
            if frame and frame.healthBar and Utils.isRaidFrame(frame) then
                local db = addon and addon.db and addon.db.profile
                if db and db.groupFrames and db.groupFrames.raid then
                    local cfg = db.groupFrames.raid
                    local hasCustom = (cfg.healthBarTexture and cfg.healthBarTexture ~= "default") or
                                      (cfg.healthBarColorMode and cfg.healthBarColorMode ~= "default") or
                                      (cfg.healthBarBackgroundTexture and cfg.healthBarBackgroundTexture ~= "default") or
                                      (cfg.healthBarBackgroundColorMode and cfg.healthBarBackgroundColorMode ~= "default")
                    if hasCustom then
                        local bar = frame.healthBar
                        local cfgRef = cfg
                        if _G.C_Timer and _G.C_Timer.After then
                            _G.C_Timer.After(0, function()
                                if InCombatLockdown and InCombatLockdown() then
                                    Combat.queueRaidFrameReapply()
                                    return
                                end
                                RaidFrames.applyToHealthBar(bar, cfgRef)
                            end)
                        else
                            if InCombatLockdown and InCombatLockdown() then
                                Combat.queueRaidFrameReapply()
                                return
                            end
                            RaidFrames.applyToHealthBar(bar, cfgRef)
                        end
                    end
                end
            end
        end)
    end

    -- Hook CompactUnitFrame_SetUnit
    if _G.hooksecurefunc and _G.CompactUnitFrame_SetUnit then
        _G.hooksecurefunc("CompactUnitFrame_SetUnit", function(frame, unit)
            if frame and frame.healthBar and unit and Utils.isRaidFrame(frame) then
                local db = addon and addon.db and addon.db.profile
                if db and db.groupFrames and db.groupFrames.raid then
                    local cfg = db.groupFrames.raid
                    local hasCustom = (cfg.healthBarTexture and cfg.healthBarTexture ~= "default") or
                                      (cfg.healthBarColorMode and cfg.healthBarColorMode ~= "default") or
                                      (cfg.healthBarBackgroundTexture and cfg.healthBarBackgroundTexture ~= "default") or
                                      (cfg.healthBarBackgroundColorMode and cfg.healthBarBackgroundColorMode ~= "default")
                    if hasCustom then
                        local bar = frame.healthBar
                        local cfgRef = cfg
                        if _G.C_Timer and _G.C_Timer.After then
                            _G.C_Timer.After(0, function()
                                if InCombatLockdown and InCombatLockdown() then
                                    Combat.queueRaidFrameReapply()
                                    return
                                end
                                RaidFrames.applyToHealthBar(bar, cfgRef)
                            end)
                        else
                            if InCombatLockdown and InCombatLockdown() then
                                Combat.queueRaidFrameReapply()
                                return
                            end
                            RaidFrames.applyToHealthBar(bar, cfgRef)
                        end
                    end
                end
            end
        end)
    end
end

-- Install hooks on load
RaidFrames.installHooks()

--------------------------------------------------------------------------------
-- Text Styling (Player Name)
--------------------------------------------------------------------------------
-- Applies font settings to raid frame name text elements.
-- Target: CompactRaidGroup*Member*Name (the name FontString on each raid unit frame)
--------------------------------------------------------------------------------

-- Apply text settings to a raid frame's name FontString
local function applyTextToRaidFrame(frame, cfg)
    if not frame or not cfg then return end

    -- Get the name FontString (frame.name is the standard CompactUnitFrame name element)
    local nameFS = frame.name
    if not nameFS then return end

    -- Resolve font face
    local fontFace = cfg.fontFace or "FRIZQT__"
    local resolvedFace
    if addon and addon.ResolveFontFace then
        resolvedFace = addon.ResolveFontFace(fontFace)
    else
        -- Fallback to GameFontNormal's font
        local defaultFont = _G.GameFontNormal and _G.GameFontNormal:GetFont()
        resolvedFace = defaultFont or "Fonts\\FRIZQT__.TTF"
    end

    -- Get settings with defaults
    local fontSize = tonumber(cfg.size) or 12
    local fontStyle = cfg.style or "OUTLINE"
    local color = cfg.color or { 1, 1, 1, 1 }
    local anchor = cfg.anchor or "TOPLEFT"
    local offsetX = cfg.offset and tonumber(cfg.offset.x) or 0
    local offsetY = cfg.offset and tonumber(cfg.offset.y) or 0

    -- Apply font (SetFont must be called before SetText)
    local success = pcall(nameFS.SetFont, nameFS, resolvedFace, fontSize, fontStyle)
    if not success then
        -- Fallback to default font on failure
        local fallback = _G.GameFontNormal and select(1, _G.GameFontNormal:GetFont())
        if fallback then
            pcall(nameFS.SetFont, nameFS, fallback, fontSize, fontStyle)
        end
    end

    -- Apply color
    if nameFS.SetTextColor then
        pcall(nameFS.SetTextColor, nameFS, color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
    end

    -- Apply text alignment based on anchor's horizontal component
    if nameFS.SetJustifyH then
        pcall(nameFS.SetJustifyH, nameFS, Utils.getJustifyHFromAnchor(anchor))
    end

    -- Capture baseline position on first application so we can restore later
    if not nameFS._ScootOriginalPoint then
        local point, relativeTo, relativePoint, x, y = nameFS:GetPoint(1)
        if point then
            nameFS._ScootOriginalPoint = { point, relativeTo, relativePoint, x or 0, y or 0 }
        end
    end

    -- Apply anchor-based positioning with offsets relative to selected anchor
    local isDefaultAnchor = (anchor == "TOPLEFT")
    local isZeroOffset = (offsetX == 0 and offsetY == 0)

    if isDefaultAnchor and isZeroOffset and nameFS._ScootOriginalPoint then
        -- Restore baseline (stock position) when user has reset to default
        local orig = nameFS._ScootOriginalPoint
        nameFS:ClearAllPoints()
        nameFS:SetPoint(orig[1], orig[2], orig[3], orig[4], orig[5])
        -- Also restore default text alignment
        if nameFS.SetJustifyH then
            pcall(nameFS.SetJustifyH, nameFS, "LEFT")
        end
    else
        -- Position the name FontString using the user-selected anchor, relative to the frame
        nameFS:ClearAllPoints()
        nameFS:SetPoint(anchor, frame, anchor, offsetX, offsetY)
    end
end

-- Collect all raid frame name FontStrings
local raidNameTexts = {}

local function collectRaidNameTexts()
    if wipe then
        wipe(raidNameTexts)
    else
        raidNameTexts = {}
    end

    -- Scan CompactRaidFrame1 through CompactRaidFrame40 (combined layout)
    for i = 1, 40 do
        local frame = _G["CompactRaidFrame" .. i]
        if frame and frame.name and not frame.name._ScootRaidTextCounted then
            frame.name._ScootRaidTextCounted = true
            table.insert(raidNameTexts, frame)
        end
    end

    -- Scan CompactRaidGroup1Member1 through CompactRaidGroup8Member5 (group layout)
    for group = 1, 8 do
        for member = 1, 5 do
            local frame = _G["CompactRaidGroup" .. group .. "Member" .. member]
            if frame and frame.name and not frame.name._ScootRaidTextCounted then
                frame.name._ScootRaidTextCounted = true
                table.insert(raidNameTexts, frame)
            end
        end
    end
end

-- Main entry point: Apply raid frame text styling from DB settings
function addon.ApplyRaidFrameTextStyle()
    local db = addon and addon.db and addon.db.profile
    if not db then return end

    -- Zero-Touch: only apply if user has configured raid text styling.
    local groupFrames = rawget(db, "groupFrames")
    local raidCfg = groupFrames and rawget(groupFrames, "raid") or nil
    local cfg = raidCfg and rawget(raidCfg, "textPlayerName") or nil
    if not cfg then
        return
    end

    -- Zero-Touch: if user hasn't actually changed anything from the defaults, do nothing.
    if not Utils.hasCustomTextSettings(cfg) then
        return
    end

    -- Deprecated: Raid Player Name styling is now driven by overlay FontStrings
    -- (see ApplyRaidFrameNameOverlays). We must avoid moving Blizzard's `frame.name`
    -- because the overlay clipping container copies its anchor geometry to preserve
    -- truncation. Touching `frame.name` here reintroduces leaking/incorrect clipping.
    if addon.ApplyRaidFrameNameOverlays then
        addon.ApplyRaidFrameNameOverlays()
    end
end

-- Install hooks to reapply text styling when raid frames update
local function installRaidFrameTextHooks()
    if addon._RaidFrameTextHooksInstalled then return end
    addon._RaidFrameTextHooksInstalled = true

    -- Deprecated: name styling hooks must not touch Blizzard's `frame.name`.
    -- Overlay system installs its own hooks (installRaidNameOverlayHooks()).
end

--------------------------------------------------------------------------------
-- Text Overlay (Name Text - Combat-Safe Persistence)
--------------------------------------------------------------------------------
-- Creates addon-owned FontString overlays on raid frames that visually replace
-- Blizzard's name text. These overlays can be styled during initial setup and
-- their text content can be updated during combat without taint because we only
-- manipulate our own FontStrings.
--
-- Pattern: Mirror text via SetText hook, style on setup, hide Blizzard's element.
--------------------------------------------------------------------------------

local function styleRaidNameOverlay(frame, cfg)
    if not frame or not frame.ScooterRaidNameText or not cfg then return end

    local overlay = frame.ScooterRaidNameText
    local container = frame.ScooterRaidNameContainer or frame

    local fontFace = cfg.fontFace or "FRIZQT__"
    local resolvedFace
    if addon and addon.ResolveFontFace then
        resolvedFace = addon.ResolveFontFace(fontFace)
    else
        local defaultFont = _G.GameFontNormal and _G.GameFontNormal:GetFont()
        resolvedFace = defaultFont or "Fonts\\FRIZQT__.TTF"
    end

    local fontSize = tonumber(cfg.size) or 12
    local fontStyle = cfg.style or "OUTLINE"
    local color = cfg.color or { 1, 1, 1, 1 }
    local anchor = cfg.anchor or "TOPLEFT"
    local offsetX = cfg.offset and tonumber(cfg.offset.x) or 0
    local offsetY = cfg.offset and tonumber(cfg.offset.y) or 0

    local success = pcall(overlay.SetFont, overlay, resolvedFace, fontSize, fontStyle)
    if not success then
        local fallback = _G.GameFontNormal and select(1, _G.GameFontNormal:GetFont())
        if fallback then
            pcall(overlay.SetFont, overlay, fallback, fontSize, fontStyle)
        end
    end

    pcall(overlay.SetTextColor, overlay, color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)

    -- Always use LEFT justify so truncation only happens on the right side.
    -- This ensures player names always show the beginning of the name.
    pcall(overlay.SetJustifyH, overlay, "LEFT")
    if overlay.SetJustifyV then
        pcall(overlay.SetJustifyV, overlay, "MIDDLE")
    end
    if overlay.SetWordWrap then
        pcall(overlay.SetWordWrap, overlay, false)
    end
    if overlay.SetNonSpaceWrap then
        pcall(overlay.SetNonSpaceWrap, overlay, false)
    end
    if overlay.SetMaxLines then
        pcall(overlay.SetMaxLines, overlay, 1)
    end

    -- Convert 9-way anchor to LEFT-based vertical anchor for proper right-side truncation.
    -- The anchor setting controls vertical position; text always starts from the left.
    local vertAnchor
    if anchor == "TOPLEFT" or anchor == "TOP" or anchor == "TOPRIGHT" then
        vertAnchor = "TOPLEFT"
    elseif anchor == "LEFT" or anchor == "CENTER" or anchor == "RIGHT" then
        vertAnchor = "LEFT"
    else -- BOTTOMLEFT, BOTTOM, BOTTOMRIGHT
        vertAnchor = "BOTTOMLEFT"
    end

    -- Calculate horizontal offset based on anchor's horizontal component.
    -- This provides approximate CENTER/RIGHT positioning while maintaining left-to-right text flow.
    local containerWidth = (container.GetWidth and container:GetWidth()) or 0
    local baseHOffset = 0
    if anchor == "TOP" or anchor == "CENTER" or anchor == "BOTTOM" then
        -- For CENTER, shift text toward the horizontal center
        baseHOffset = containerWidth * 0.25
    elseif anchor == "TOPRIGHT" or anchor == "RIGHT" or anchor == "BOTTOMRIGHT" then
        -- For RIGHT, shift text further toward the right edge
        baseHOffset = containerWidth * 0.5
    end

    -- Position within the full-frame clipping container using LEFT-based anchors.
    -- The baseHOffset shifts text horizontally based on alignment preference.
    overlay:ClearAllPoints()
    overlay:SetPoint(vertAnchor, container, vertAnchor, offsetX + baseHOffset, offsetY)
    -- NOTE: We intentionally do NOT set an explicit width on the overlay.
    -- The container's SetClipsChildren(true) will hard-clip the text at the
    -- right edge without adding Blizzard's "..." ellipsis.
end

local function hideBlizzardRaidNameText(frame)
    if not frame or not frame.name then return end
    local blizzName = frame.name

    blizzName._ScootHidden = true
    if blizzName.SetAlpha then
        pcall(blizzName.SetAlpha, blizzName, 0)
    end
    if blizzName.Hide then
        pcall(blizzName.Hide, blizzName)
    end

    if not blizzName._ScootAlphaHooked and _G.hooksecurefunc then
        blizzName._ScootAlphaHooked = true
        _G.hooksecurefunc(blizzName, "SetAlpha", function(self, alpha)
            if alpha > 0 and self._ScootHidden then
                if _G.C_Timer and _G.C_Timer.After then
                    _G.C_Timer.After(0, function()
                        if self._ScootHidden then
                            self:SetAlpha(0)
                        end
                    end)
                end
            end
        end)
    end

    if not blizzName._ScootShowHooked and _G.hooksecurefunc then
        blizzName._ScootShowHooked = true
        _G.hooksecurefunc(blizzName, "Show", function(self)
            if not self._ScootHidden then return end
            -- Kill visibility immediately (avoid flicker), then defer Hide to break chains.
            if self.SetAlpha then pcall(self.SetAlpha, self, 0) end
            if _G.C_Timer and _G.C_Timer.After then
                _G.C_Timer.After(0, function()
                    if self and self._ScootHidden then
                        if self.SetAlpha then pcall(self.SetAlpha, self, 0) end
                        if self.Hide then pcall(self.Hide, self) end
                    end
                end)
            else
                if self.SetAlpha then pcall(self.SetAlpha, self, 0) end
                if self.Hide then pcall(self.Hide, self) end
            end
        end)
    end
end

local function showBlizzardRaidNameText(frame)
    if not frame or not frame.name then return end
    frame.name._ScootHidden = nil
    if frame.name.SetAlpha then
        pcall(frame.name.SetAlpha, frame.name, 1)
    end
    if frame.name.Show then
        pcall(frame.name.Show, frame.name)
    end
end

local function ensureRaidNameOverlay(frame, cfg)
    if not frame then return end

    local hasCustom = Utils.hasCustomTextSettings(cfg)
    frame._ScootRaidNameOverlayActive = hasCustom

    if not hasCustom then
        if frame.ScooterRaidNameText then
            frame.ScooterRaidNameText:Hide()
        end
        showBlizzardRaidNameText(frame)
        return
    end

    -- Ensure an addon-owned clipping container that spans the FULL unit frame.
    -- This allows 9-way alignment to position text anywhere within the frame.
    if not frame.ScooterRaidNameContainer then
        local container = CreateFrame("Frame", nil, frame)
        container:SetClipsChildren(true)

        -- Span the entire unit frame with small padding for visual breathing room.
        container:ClearAllPoints()
        container:SetPoint("TOPLEFT", frame, "TOPLEFT", 3, -3)
        container:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 3)

        frame.ScooterRaidNameContainer = container
    end

    -- Create overlay FontString if it doesn't exist (as a child of the clipping container)
    if not frame.ScooterRaidNameText then
        local parentForText = frame.ScooterRaidNameContainer or frame
        local overlay = parentForText:CreateFontString(nil, "OVERLAY", nil)
        overlay:SetDrawLayer("OVERLAY", 7)
        frame.ScooterRaidNameText = overlay

        if frame.name and not frame.name._ScootTextMirrorHooked and _G.hooksecurefunc then
            frame.name._ScootTextMirrorHooked = true
            frame.name._ScootTextMirrorOwner = frame
            _G.hooksecurefunc(frame.name, "SetText", function(self, text)
                local owner = self._ScootTextMirrorOwner
                if owner and owner.ScooterRaidNameText and owner._ScootRaidNameOverlayActive then
                    owner.ScooterRaidNameText:SetText(text or "")
                end
            end)
        end
    end

    styleRaidNameOverlay(frame, cfg)
    hideBlizzardRaidNameText(frame)

    if frame.name and frame.name.GetText then
        local currentText = frame.name:GetText()
        frame.ScooterRaidNameText:SetText(currentText or "")
    end

    frame.ScooterRaidNameText:Show()
end

local function disableRaidNameOverlay(frame)
    if not frame then return end
    frame._ScootRaidNameOverlayActive = false
    if frame.ScooterRaidNameText then
        frame.ScooterRaidNameText:Hide()
    end
    showBlizzardRaidNameText(frame)
end

function addon.ApplyRaidFrameNameOverlays()
    local db = addon and addon.db and addon.db.profile
    if not db then return end

    local groupFrames = rawget(db, "groupFrames")
    local raidCfg = groupFrames and rawget(groupFrames, "raid") or nil
    local cfg = raidCfg and rawget(raidCfg, "textPlayerName") or nil

    local hasCustom = Utils.hasCustomTextSettings(cfg)

    -- Combined layout: CompactRaidFrame1..40
    for i = 1, 40 do
        local frame = _G["CompactRaidFrame" .. i]
        if frame and frame.name then
            if hasCustom then
                if not (InCombatLockdown and InCombatLockdown()) then
                    ensureRaidNameOverlay(frame, cfg)
                elseif frame.ScooterRaidNameText then
                    styleRaidNameOverlay(frame, cfg)
                end
            else
                disableRaidNameOverlay(frame)
            end
        end
    end

    -- Group layout: CompactRaidGroup1Member1..CompactRaidGroup8Member5
    for group = 1, 8 do
        for member = 1, 5 do
            local frame = _G["CompactRaidGroup" .. group .. "Member" .. member]
            if frame and frame.name then
                if hasCustom then
                    if not (InCombatLockdown and InCombatLockdown()) then
                        ensureRaidNameOverlay(frame, cfg)
                    elseif frame.ScooterRaidNameText then
                        styleRaidNameOverlay(frame, cfg)
                    end
                else
                    disableRaidNameOverlay(frame)
                end
            end
        end
    end
end

function addon.RestoreRaidFrameNameOverlays()
    for i = 1, 40 do
        local frame = _G["CompactRaidFrame" .. i]
        if frame then
            disableRaidNameOverlay(frame)
        end
    end
    for group = 1, 8 do
        for member = 1, 5 do
            local frame = _G["CompactRaidGroup" .. group .. "Member" .. member]
            if frame then
                disableRaidNameOverlay(frame)
            end
        end
    end
end

local function installRaidNameOverlayHooks()
    if addon._RaidNameOverlayHooksInstalled then return end
    addon._RaidNameOverlayHooksInstalled = true

    local function getCfg()
        local db = addon and addon.db and addon.db.profile
        local gf = db and rawget(db, "groupFrames") or nil
        local raidCfg = gf and rawget(gf, "raid") or nil
        return raidCfg and rawget(raidCfg, "textPlayerName") or nil
    end

    if _G.hooksecurefunc and _G.CompactUnitFrame_UpdateAll then
        _G.hooksecurefunc("CompactUnitFrame_UpdateAll", function(frame)
            if not (frame and frame.name and Utils.isRaidFrame(frame)) then return end
            local cfg = getCfg()
            if not Utils.hasCustomTextSettings(cfg) then return end

            local frameRef = frame
            local cfgRef = cfg
            if _G.C_Timer and _G.C_Timer.After then
                _G.C_Timer.After(0, function()
                    if not frameRef then return end
                    if InCombatLockdown and InCombatLockdown() then
                        Combat.queueRaidFrameReapply()
                        return
                    end
                    ensureRaidNameOverlay(frameRef, cfgRef)
                end)
            else
                if InCombatLockdown and InCombatLockdown() then
                    Combat.queueRaidFrameReapply()
                    return
                end
                ensureRaidNameOverlay(frameRef, cfgRef)
            end
        end)
    end

    if _G.hooksecurefunc and _G.CompactUnitFrame_SetUnit then
        _G.hooksecurefunc("CompactUnitFrame_SetUnit", function(frame, unit)
            if not unit then return end
            if not (frame and frame.name and Utils.isRaidFrame(frame)) then return end
            local cfg = getCfg()
            if not Utils.hasCustomTextSettings(cfg) then return end

            local frameRef = frame
            local cfgRef = cfg
            if _G.C_Timer and _G.C_Timer.After then
                _G.C_Timer.After(0, function()
                    if not frameRef then return end
                    if InCombatLockdown and InCombatLockdown() then
                        Combat.queueRaidFrameReapply()
                        return
                    end
                    ensureRaidNameOverlay(frameRef, cfgRef)
                end)
            else
                if InCombatLockdown and InCombatLockdown() then
                    Combat.queueRaidFrameReapply()
                    return
                end
                ensureRaidNameOverlay(frameRef, cfgRef)
            end
        end)
    end

    if _G.hooksecurefunc and _G.CompactUnitFrame_UpdateName then
        _G.hooksecurefunc("CompactUnitFrame_UpdateName", function(frame)
            if not (frame and frame.name and Utils.isRaidFrame(frame)) then return end
            local cfg = getCfg()
            if not Utils.hasCustomTextSettings(cfg) then return end

            local frameRef = frame
            local cfgRef = cfg
            if _G.C_Timer and _G.C_Timer.After then
                _G.C_Timer.After(0, function()
                    if not frameRef then return end
                    if InCombatLockdown and InCombatLockdown() then
                        Combat.queueRaidFrameReapply()
                        return
                    end
                    ensureRaidNameOverlay(frameRef, cfgRef)
                end)
            else
                if InCombatLockdown and InCombatLockdown() then
                    Combat.queueRaidFrameReapply()
                    return
                end
                ensureRaidNameOverlay(frameRef, cfgRef)
            end
        end)
    end
end

--------------------------------------------------------------------------------
-- Text Styling (Status Text)
--------------------------------------------------------------------------------
-- Applies the same 7 settings as Player Name to raid unit frame StatusText.
-- Targets:
--   - CompactRaidFrame1..40: frame.statusText (FontString, name "$parentStatusText")
--   - CompactRaidGroup1..8Member1..5: frame.statusText (FontString, name "$parentStatusText")
--------------------------------------------------------------------------------

local function applyTextToFontString_StatusText(fs, ownerFrame, cfg)
    if not fs or not ownerFrame or not cfg then return end

    -- Resolve font face
    local fontFace = cfg.fontFace or "FRIZQT__"
    local resolvedFace
    if addon and addon.ResolveFontFace then
        resolvedFace = addon.ResolveFontFace(fontFace)
    else
        local defaultFont = _G.GameFontNormal and _G.GameFontNormal:GetFont()
        resolvedFace = defaultFont or "Fonts\\FRIZQT__.TTF"
    end

    -- Get settings with defaults
    local fontSize = tonumber(cfg.size) or 12
    local fontStyle = cfg.style or "OUTLINE"
    local color = cfg.color or { 1, 1, 1, 1 }
    local anchor = cfg.anchor or "TOPLEFT"
    local offsetX = cfg.offset and tonumber(cfg.offset.x) or 0
    local offsetY = cfg.offset and tonumber(cfg.offset.y) or 0

    -- Apply font
    local success = pcall(fs.SetFont, fs, resolvedFace, fontSize, fontStyle)
    if not success then
        local fallback = _G.GameFontNormal and select(1, _G.GameFontNormal:GetFont())
        if fallback then
            pcall(fs.SetFont, fs, fallback, fontSize, fontStyle)
        end
    end

    -- Apply color + alignment
    if fs.SetTextColor then
        pcall(fs.SetTextColor, fs, color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
    end
    if fs.SetJustifyH then
        pcall(fs.SetJustifyH, fs, Utils.getJustifyHFromAnchor(anchor))
    end

    -- Capture baseline position on first application so we can restore later
    if not fs._ScootOriginalPoint_StatusText then
        local point, relativeTo, relativePoint, x, y = fs:GetPoint(1)
        if point then
            fs._ScootOriginalPoint_StatusText = { point, relativeTo, relativePoint, x or 0, y or 0 }
        end
    end

    local isDefaultAnchor = (anchor == "TOPLEFT")
    local isZeroOffset = (offsetX == 0 and offsetY == 0)

    if isDefaultAnchor and isZeroOffset and fs._ScootOriginalPoint_StatusText then
        -- Restore baseline (stock position) when user has reset to default
        local orig = fs._ScootOriginalPoint_StatusText
        fs:ClearAllPoints()
        fs:SetPoint(orig[1], orig[2], orig[3], orig[4], orig[5])
        if fs.SetJustifyH then
            pcall(fs.SetJustifyH, fs, "LEFT")
        end
    else
        -- Position the FontString using the user-selected anchor, relative to the owner frame
        fs:ClearAllPoints()
        fs:SetPoint(anchor, ownerFrame, anchor, offsetX, offsetY)
    end
end

local function applyStatusTextToRaidFrame(frame, cfg)
    if not frame or not cfg then return end
    local fs = frame.statusText
    if not fs then return end
    applyTextToFontString_StatusText(fs, frame, cfg)
end

function addon.ApplyRaidFrameStatusTextStyle()
    local db = addon and addon.db and addon.db.profile
    if not db then return end

    -- Zero-Touch: only apply if user has configured raid status text styling.
    local groupFrames = rawget(db, "groupFrames")
    local raidCfg = groupFrames and rawget(groupFrames, "raid") or nil
    local cfg = raidCfg and rawget(raidCfg, "textStatusText") or nil
    if not cfg then
        return
    end

    -- Zero-Touch: if user hasn't actually changed anything from the defaults, do nothing.
    if not Utils.hasCustomTextSettings(cfg) then
        return
    end

    if InCombatLockdown and InCombatLockdown() then
        Combat.queueRaidFrameReapply()
        return
    end

    -- Combined layout: CompactRaidFrame1..40
    for i = 1, 40 do
        local frame = _G["CompactRaidFrame" .. i]
        if frame and frame.statusText then
            applyStatusTextToRaidFrame(frame, cfg)
        end
    end

    -- Group layout: CompactRaidGroup1..8Member1..5
    for group = 1, 8 do
        for member = 1, 5 do
            local frame = _G["CompactRaidGroup" .. group .. "Member" .. member]
            if frame and frame.statusText then
                applyStatusTextToRaidFrame(frame, cfg)
            end
        end
    end
end

local function installRaidFrameStatusTextHooks()
    if addon._RaidFrameStatusTextHooksInstalled then return end
    addon._RaidFrameStatusTextHooksInstalled = true

    local function tryApply(frame)
        if not frame or not frame.statusText or not Utils.isRaidFrame(frame) then
            return
        end
        local db = addon and addon.db and addon.db.profile
        local cfg = db and db.groupFrames and db.groupFrames.raid and db.groupFrames.raid.textStatusText or nil
        if not cfg or not Utils.hasCustomTextSettings(cfg) then
            return
        end
        local frameRef = frame
        local cfgRef = cfg
        if _G.C_Timer and _G.C_Timer.After then
            _G.C_Timer.After(0, function()
                if InCombatLockdown and InCombatLockdown() then
                    Combat.queueRaidFrameReapply()
                    return
                end
                applyStatusTextToRaidFrame(frameRef, cfgRef)
            end)
        else
            if InCombatLockdown and InCombatLockdown() then
                Combat.queueRaidFrameReapply()
                return
            end
            applyStatusTextToRaidFrame(frameRef, cfgRef)
        end
    end

    if _G.hooksecurefunc then
        if _G.CompactUnitFrame_UpdateStatusText then
            _G.hooksecurefunc("CompactUnitFrame_UpdateStatusText", tryApply)
        end
        if _G.CompactUnitFrame_UpdateLayout then
            _G.hooksecurefunc("CompactUnitFrame_UpdateLayout", tryApply)
        end
        if _G.CompactUnitFrame_UpdateAll then
            _G.hooksecurefunc("CompactUnitFrame_UpdateAll", tryApply)
        end
        if _G.CompactUnitFrame_SetUnit then
            _G.hooksecurefunc("CompactUnitFrame_SetUnit", tryApply)
        end
    end
end

--------------------------------------------------------------------------------
-- Text Styling (Group Numbers / Group Titles)
--------------------------------------------------------------------------------
-- Applies the same 7 settings as Player Name to raid group title text.
-- Target: CompactRaidGroup1..8Title (Button, parentKey "title").
--------------------------------------------------------------------------------

local function applyTextToFontString_GroupTitle(fs, ownerFrame, cfg)
    if not fs or not ownerFrame or not cfg then return end

    local fontFace = cfg.fontFace or "FRIZQT__"
    local resolvedFace
    if addon and addon.ResolveFontFace then
        resolvedFace = addon.ResolveFontFace(fontFace)
    else
        local defaultFont = _G.GameFontNormal and _G.GameFontNormal:GetFont()
        resolvedFace = defaultFont or "Fonts\\FRIZQT__.TTF"
    end

    local fontSize = tonumber(cfg.size) or 12
    local fontStyle = cfg.style or "OUTLINE"
    local color = cfg.color or { 1, 1, 1, 1 }
    local anchor = cfg.anchor or "TOPLEFT"
    local offsetX = cfg.offset and tonumber(cfg.offset.x) or 0
    local offsetY = cfg.offset and tonumber(cfg.offset.y) or 0

    local success = pcall(fs.SetFont, fs, resolvedFace, fontSize, fontStyle)
    if not success then
        local fallback = _G.GameFontNormal and select(1, _G.GameFontNormal:GetFont())
        if fallback then
            pcall(fs.SetFont, fs, fallback, fontSize, fontStyle)
        end
    end

    if fs.SetTextColor then
        pcall(fs.SetTextColor, fs, color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
    end
    if fs.SetJustifyH then
        pcall(fs.SetJustifyH, fs, Utils.getJustifyHFromAnchor(anchor))
    end

    if not fs._ScootOriginalPoint_GroupTitle then
        local point, relativeTo, relativePoint, x, y = fs:GetPoint(1)
        if point then
            fs._ScootOriginalPoint_GroupTitle = { point, relativeTo, relativePoint, x or 0, y or 0 }
        end
    end

    local isDefaultAnchor = (anchor == "TOPLEFT")
    local isZeroOffset = (offsetX == 0 and offsetY == 0)

    if isDefaultAnchor and isZeroOffset and fs._ScootOriginalPoint_GroupTitle then
        local orig = fs._ScootOriginalPoint_GroupTitle
        fs:ClearAllPoints()
        fs:SetPoint(orig[1], orig[2], orig[3], orig[4], orig[5])
        if fs.SetJustifyH then
            pcall(fs.SetJustifyH, fs, "LEFT")
        end
    else
        fs:ClearAllPoints()
        fs:SetPoint(anchor, ownerFrame, anchor, offsetX, offsetY)
    end
end

local function applyGroupTitleToButton(titleButton, cfg)
    if not titleButton or not cfg then return end
    if not titleButton.GetFontString then return end
    local fs = titleButton:GetFontString()
    if not fs then return end
    applyTextToFontString_GroupTitle(fs, titleButton, cfg)
end

function addon.ApplyRaidFrameGroupTitlesStyle()
    local db = addon and addon.db and addon.db.profile
    if not db then return end

    -- Zero-Touch: only apply if user has configured raid group title styling.
    local groupFrames = rawget(db, "groupFrames")
    local raidCfg = groupFrames and rawget(groupFrames, "raid") or nil
    local cfg = raidCfg and rawget(raidCfg, "textGroupNumbers") or nil
    if not cfg then
        return
    end

    if not Utils.hasCustomTextSettings(cfg) then
        return
    end

    if InCombatLockdown and InCombatLockdown() then
        Combat.queueRaidFrameReapply()
        return
    end

    for group = 1, 8 do
        local groupFrame = _G["CompactRaidGroup" .. group]
        local titleButton = (groupFrame and groupFrame.title) or _G["CompactRaidGroup" .. group .. "Title"]
        if titleButton then
            applyGroupTitleToButton(titleButton, cfg)
        end
    end
end

local function installRaidFrameGroupTitleHooks()
    if addon._RaidFrameGroupTitleHooksInstalled then return end
    addon._RaidFrameGroupTitleHooksInstalled = true

    local function tryApplyTitle(groupFrame)
        if not groupFrame or not Utils.isCompactRaidGroupFrame(groupFrame) then
            return
        end
        local titleButton = groupFrame.title or _G[groupFrame:GetName() .. "Title"]
        if not titleButton then return end

        local db = addon and addon.db and addon.db.profile
        local cfg = db and db.groupFrames and db.groupFrames.raid and db.groupFrames.raid.textGroupNumbers or nil
        if not cfg or not Utils.hasCustomTextSettings(cfg) then
            return
        end

        local titleRef = titleButton
        local cfgRef = cfg
        if _G.C_Timer and _G.C_Timer.After then
            _G.C_Timer.After(0, function()
                if InCombatLockdown and InCombatLockdown() then
                    Combat.queueRaidFrameReapply()
                    return
                end
                applyGroupTitleToButton(titleRef, cfgRef)
            end)
        else
            if InCombatLockdown and InCombatLockdown() then
                Combat.queueRaidFrameReapply()
                return
            end
            applyGroupTitleToButton(titleRef, cfgRef)
        end
    end

    if _G.hooksecurefunc then
        if _G.CompactRaidGroup_UpdateLayout then
            _G.hooksecurefunc("CompactRaidGroup_UpdateLayout", tryApplyTitle)
        end
        if _G.CompactRaidGroup_InitializeForGroup then
            _G.hooksecurefunc("CompactRaidGroup_InitializeForGroup", function(groupFrame, groupIndex)
                tryApplyTitle(groupFrame)
            end)
        end
        if _G.CompactRaidGroup_UpdateUnits then
            _G.hooksecurefunc("CompactRaidGroup_UpdateUnits", tryApplyTitle)
        end
    end
end

--------------------------------------------------------------------------------
-- Text Hook Installation
--------------------------------------------------------------------------------

function RaidFrames.installTextHooks()
    installRaidFrameTextHooks()
    installRaidNameOverlayHooks()
    installRaidFrameStatusTextHooks()
    installRaidFrameGroupTitleHooks()
end

-- Install text hooks on load
RaidFrames.installTextHooks()

return RaidFrames
