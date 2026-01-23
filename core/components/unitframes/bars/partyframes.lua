--------------------------------------------------------------------------------
-- bars/partyframes.lua
-- Party frame health bar and text styling
--
-- Applies styling to CompactPartyFrameMember[1-5] frames.
-- Uses combat-safe overlay patterns for persistence during combat.
--------------------------------------------------------------------------------

local addonName, addon = ...

-- Get modules
local Utils = addon.BarsUtils
local Combat = addon.BarsCombat

-- Create module namespace
addon.BarsPartyFrames = addon.BarsPartyFrames or {}
local PartyFrames = addon.BarsPartyFrames

--------------------------------------------------------------------------------
-- 12.0 TAINT PREVENTION: Lookup table for party frame state
--------------------------------------------------------------------------------
-- In 12.0, writing properties directly to CompactPartyFrameMember frames
-- (e.g., frame._ScootActive = true) can mark the entire frame as "addon-touched".
-- This causes ALL field accesses to return secret values in protected contexts
-- (like Edit Mode), breaking Blizzard's own code (frame.outOfRange becomes secret).
--
-- Solution: Store all ScooterMod state in a separate lookup table keyed by frame.
-- This avoids modifying Blizzard's frames while preserving our overlay functionality.
--------------------------------------------------------------------------------
local PartyFrameState = setmetatable({}, { __mode = "k" }) -- Weak keys for GC

local function getState(frame)
    if not frame then return nil end
    return PartyFrameState[frame]
end

local function ensureState(frame)
    if not frame then return nil end
    if not PartyFrameState[frame] then
        PartyFrameState[frame] = {}
    end
    return PartyFrameState[frame]
end

-- 12.0+: Some values can be "secret" and will hard-error on arithmetic/comparisons.
-- Treat those as unreadable and skip optional overlays rather than crashing.
local function safeNumber(v)
    local okNil, isNil = pcall(function() return v == nil end)
    if okNil and isNil then return nil end
    local n = v
    if type(n) ~= "number" then
        local ok, conv = pcall(tonumber, n)
        if ok and type(conv) == "number" then
            n = conv
        else
            return nil
        end
    end
    local ok = pcall(function() return n + 0 end)
    if not ok then
        return nil
    end
    return n
end

--------------------------------------------------------------------------------
-- Party Frame Detection
--------------------------------------------------------------------------------

function PartyFrames.isPartyFrame(frame)
    return Utils.isPartyFrame(frame)
end

function PartyFrames.isPartyHealthBar(frame)
    if not frame or not frame.healthBar then return false end
    return Utils.isPartyFrame(frame)
end

--------------------------------------------------------------------------------
-- Health Bar Collection
--------------------------------------------------------------------------------

local partyHealthBars = {}

function PartyFrames.collectHealthBars()
    partyHealthBars = {}
    for i = 1, 5 do
        local bar = _G["CompactPartyFrameMember" .. i .. "HealthBar"]
        if bar then
            table.insert(partyHealthBars, bar)
        end
    end
    return partyHealthBars
end

--------------------------------------------------------------------------------
-- Health Bar Styling
--------------------------------------------------------------------------------

function PartyFrames.applyToHealthBar(bar, cfg)
    if not bar or not cfg then return end

    local texKey = cfg.healthBarTexture or "default"
    local colorMode = cfg.healthBarColorMode or "default"
    local tint = cfg.healthBarTint
    local bgTexKey = cfg.healthBarBackgroundTexture or "default"
    local bgColorMode = cfg.healthBarBackgroundColorMode or "default"
    local bgTint = cfg.healthBarBackgroundTint
    local bgOpacity = cfg.healthBarBackgroundOpacity or 50

    if addon._ApplyToStatusBar then
        addon._ApplyToStatusBar(bar, texKey, colorMode, tint, nil, "health", nil)
    end

    if addon._ApplyBackgroundToStatusBar then
        addon._ApplyBackgroundToStatusBar(bar, bgTexKey, bgColorMode, bgTint, bgOpacity, "Party", "health")
    end
end

--------------------------------------------------------------------------------
-- Health Bar Overlay (Combat-Safe Persistence)
--------------------------------------------------------------------------------

-- Update overlay width based on health bar value
local function updateHealthOverlay(bar)
    if not bar then return end
    local state = getState(bar)
    local overlay = state and state.healthOverlay or nil
    if not overlay then return end
    if not state or not state.overlayActive then
        overlay:Hide()
        return
    end
    -- 12.0+: These getters can surface Blizzard "secret value" errors. Best-effort only.
    local totalWidth = 0
    do
        -- Avoid StatusBar:GetWidth(); prefer StatusBarTexture width.
        local tex = (bar.GetStatusBarTexture and bar:GetStatusBarTexture()) or nil
        if tex and tex.GetWidth then
            local okW, w = pcall(tex.GetWidth, tex)
            totalWidth = safeNumber(okW and w) or 0
        end
    end
    local minVal, maxVal
    do
        local okMM, mn, mx = pcall(bar.GetMinMaxValues, bar)
        minVal = safeNumber(okMM and mn)
        maxVal = safeNumber(okMM and mx)
    end
    local value
    do
        local okV, v = pcall(bar.GetValue, bar)
        value = safeNumber(okV and v)
        if value == nil then value = minVal end
    end

    if not totalWidth or totalWidth <= 0 or minVal == nil or maxVal == nil or value == nil then
        overlay:Hide()
        return
    end
    if maxVal <= minVal then
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
    if not bar or not cfg then return end
    local state = getState(bar)
    local overlay = state and state.healthOverlay or nil
    if not overlay then return end
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

    local state = ensureState(blizzFill)
    if state then state.hidden = true end
    blizzFill:SetAlpha(0)

    local barState = getState(blizzFill)
    if barState and not barState.alphaHooked and _G.hooksecurefunc then
        barState.alphaHooked = true
        _G.hooksecurefunc(blizzFill, "SetAlpha", function(self, alpha)
            local st = getState(self)
            if alpha > 0 and st and st.hidden then
                if _G.C_Timer and _G.C_Timer.After then
                    _G.C_Timer.After(0, function()
                        local st2 = getState(self)
                        if st2 and st2.hidden then
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
        local state = getState(blizzFill)
        if state then state.hidden = nil end
        blizzFill:SetAlpha(1)
    end
end

-- Create or update the health overlay
function PartyFrames.ensureHealthOverlay(bar, cfg)
    if not bar then return end

    local hasCustom = cfg and (
        (cfg.healthBarTexture and cfg.healthBarTexture ~= "default") or
        (cfg.healthBarColorMode and cfg.healthBarColorMode ~= "default")
    )

    local state = ensureState(bar)
    if state then state.overlayActive = hasCustom end

    if not hasCustom then
        if state and state.healthOverlay then
            state.healthOverlay:Hide()
        end
        showBlizzardFill(bar)
        return
    end

    if state and not state.healthOverlay then
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
        state.healthOverlay = overlay

        local barState = ensureState(bar)
        if _G.hooksecurefunc and barState and not barState.overlayHooksInstalled then
            barState.overlayHooksInstalled = true
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

    local barState = ensureState(bar)
    if barState and not barState.textureSwapHooked and _G.hooksecurefunc then
        barState.textureSwapHooked = true
        _G.hooksecurefunc(bar, "SetStatusBarTexture", function(self)
            local st = getState(self)
            if st and st.overlayActive then
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

function PartyFrames.disableHealthOverlay(bar)
    if not bar then return end
    local state = getState(bar)
    if state then state.overlayActive = false end
    if state and state.healthOverlay then
        state.healthOverlay:Hide()
    end
    showBlizzardFill(bar)
end

--------------------------------------------------------------------------------
-- Public API Functions
--------------------------------------------------------------------------------

-- Main entry point: Apply party frame health bar styling from DB settings
function addon.ApplyPartyFrameHealthBarStyle()
    local db = addon and addon.db and addon.db.profile
    if not db then return end

    local groupFrames = rawget(db, "groupFrames")
    local cfg = groupFrames and rawget(groupFrames, "party") or nil
    if not cfg then return end

    local hasCustom = (cfg.healthBarTexture and cfg.healthBarTexture ~= "default") or
                      (cfg.healthBarColorMode and cfg.healthBarColorMode ~= "default") or
                      (cfg.healthBarBackgroundTexture and cfg.healthBarBackgroundTexture ~= "default") or
                      (cfg.healthBarBackgroundColorMode and cfg.healthBarBackgroundColorMode ~= "default")
    if not hasCustom then return end

    if InCombatLockdown and InCombatLockdown() then
        Combat.queuePartyFrameReapply()
        return
    end

    PartyFrames.collectHealthBars()
    for _, bar in ipairs(partyHealthBars) do
        PartyFrames.applyToHealthBar(bar, cfg)
    end
end

-- Apply overlays to all party health bars
function addon.ApplyPartyFrameHealthOverlays()
    local db = addon and addon.db and addon.db.profile
    if not db then return end

    local groupFrames = rawget(db, "groupFrames")
    local cfg = groupFrames and rawget(groupFrames, "party") or nil

    local hasCustom = cfg and (
        (cfg.healthBarTexture and cfg.healthBarTexture ~= "default") or
        (cfg.healthBarColorMode and cfg.healthBarColorMode ~= "default")
    )

    for i = 1, 5 do
        local bar = _G["CompactPartyFrameMember" .. i .. "HealthBar"]
        if bar then
            if hasCustom then
                if not (InCombatLockdown and InCombatLockdown()) then
                    PartyFrames.ensureHealthOverlay(bar, cfg)
                else
                    local state = getState(bar)
                    if state and state.healthOverlay then
                        styleHealthOverlay(bar, cfg)
                        updateHealthOverlay(bar)
                    end
                end
            else
                PartyFrames.disableHealthOverlay(bar)
            end
        end
    end
end

-- Restore all party health bars to stock appearance
function addon.RestorePartyFrameHealthOverlays()
    for i = 1, 5 do
        local bar = _G["CompactPartyFrameMember" .. i .. "HealthBar"]
        if bar then
            PartyFrames.disableHealthOverlay(bar)
        end
    end
end

--------------------------------------------------------------------------------
-- Hook Installation
--------------------------------------------------------------------------------

-- 12.0 EDIT MODE GUARD: Skip all CompactUnitFrame hooks when Edit Mode is active.
-- When ScooterMod triggers ApplyChanges (which bounces Edit Mode), Blizzard sets up
-- Arena/Party/Raid frames. If our hooks run during this flow (even just to check
-- frame type), the addon code in the execution context can cause UnitInRange() and
-- similar APIs to return secret values, breaking Blizzard's own code.
local function isEditModeActive()
    if addon and addon.EditMode and addon.EditMode.IsEditModeActiveOrOpening then
        return addon.EditMode.IsEditModeActiveOrOpening()
    end
    local mgr = _G.EditModeManagerFrame
    return mgr and (mgr.editModeActive or (mgr.IsShown and mgr:IsShown()))
end

function PartyFrames.installHooks()
    if addon._PartyFrameHooksInstalled then return end
    addon._PartyFrameHooksInstalled = true

    -- Hook CompactUnitFrame_UpdateAll
    if _G.hooksecurefunc and _G.CompactUnitFrame_UpdateAll then
        _G.hooksecurefunc("CompactUnitFrame_UpdateAll", function(frame)
            -- CRITICAL: Skip ALL processing when Edit Mode is active to avoid taint
            if isEditModeActive() then return end
            if frame and frame.healthBar and Utils.isPartyFrame(frame) then
                local db = addon and addon.db and addon.db.profile
                local cfg = db and db.groupFrames and db.groupFrames.party or nil
                if cfg then
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
                                    Combat.queuePartyFrameReapply()
                                    return
                                end
                                PartyFrames.applyToHealthBar(bar, cfgRef)
                            end)
                        else
                            if InCombatLockdown and InCombatLockdown() then
                                Combat.queuePartyFrameReapply()
                                return
                            end
                            PartyFrames.applyToHealthBar(bar, cfgRef)
                        end
                    end
                end
            end
        end)
    end

    -- Hook CompactUnitFrame_SetUnit
    if _G.hooksecurefunc and _G.CompactUnitFrame_SetUnit then
        _G.hooksecurefunc("CompactUnitFrame_SetUnit", function(frame, unit)
            -- CRITICAL: Skip ALL processing when Edit Mode is active to avoid taint
            if isEditModeActive() then return end
            if frame and frame.healthBar and unit and Utils.isPartyFrame(frame) then
                local db = addon and addon.db and addon.db.profile
                local cfg = db and db.groupFrames and db.groupFrames.party or nil
                if cfg then
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
                                    Combat.queuePartyFrameReapply()
                                    return
                                end
                                PartyFrames.applyToHealthBar(bar, cfgRef)
                            end)
                        else
                            if InCombatLockdown and InCombatLockdown() then
                                Combat.queuePartyFrameReapply()
                                return
                            end
                            PartyFrames.applyToHealthBar(bar, cfgRef)
                        end
                    end
                end
            end
        end)
    end
end

-- Install hooks on load
PartyFrames.installHooks()

--------------------------------------------------------------------------------
-- Text Styling (Player Name)
--------------------------------------------------------------------------------
-- Applies font settings to party frame name text elements.
-- Target: CompactPartyFrameMember[1-5].name (FontString with parentKey="name")
--------------------------------------------------------------------------------

local function applyTextToPartyFrame(frame, cfg)
    if not frame or not cfg then return end

    local nameFS = frame.name
    if not nameFS then return end

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

    local success = pcall(nameFS.SetFont, nameFS, resolvedFace, fontSize, fontStyle)
    if not success then
        local fallback = _G.GameFontNormal and select(1, _G.GameFontNormal:GetFont())
        if fallback then
            pcall(nameFS.SetFont, nameFS, fallback, fontSize, fontStyle)
        end
    end

    if nameFS.SetTextColor then
        pcall(nameFS.SetTextColor, nameFS, color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
    end

    -- Apply text alignment based on anchor's horizontal component
    if nameFS.SetJustifyH then
        pcall(nameFS.SetJustifyH, nameFS, Utils.getJustifyHFromAnchor(anchor))
    end

    -- Capture baseline position on first application so we can restore later
    local nameState = ensureState(nameFS)
    if nameState and not nameState.originalPoint then
        local point, relativeTo, relativePoint, x, y = nameFS:GetPoint(1)
        if point then
            nameState.originalPoint = { point, relativeTo, relativePoint, x or 0, y or 0 }
        end
    end

    -- Apply anchor-based positioning with offsets relative to selected anchor
    local isDefaultAnchor = (anchor == "TOPLEFT")
    local isZeroOffset = (offsetX == 0 and offsetY == 0)

    if isDefaultAnchor and isZeroOffset and nameState and nameState.originalPoint then
        -- Restore baseline (stock position) when user has reset to default
        local orig = nameState.originalPoint
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

    -- Preserve Blizzard's truncation/clipping behavior: explicitly constrain the name FontString width.
    -- Blizzard normally constrains this via a dual-anchor layout (TOPLEFT + TOPRIGHT). Our single-point
    -- anchor (for 9-way alignment) removes that implicit width, so we restore it with SetWidth.
    if nameFS.SetMaxLines then
        pcall(nameFS.SetMaxLines, nameFS, 1)
    end
    if frame.GetWidth and nameFS.SetWidth then
        local frameWidth = frame:GetWidth()
        local roleIconWidth = 0
        if frame.roleIcon and frame.roleIcon.GetWidth then
            roleIconWidth = frame.roleIcon:GetWidth() or 0
        end
        -- 3px right padding + (role icon area) + 3px left padding ~= 6px padding total, matching CUF defaults.
        local availableWidth = (frameWidth or 0) - (roleIconWidth or 0) - 6
        if availableWidth and availableWidth > 1 then
            pcall(nameFS.SetWidth, nameFS, availableWidth)
        else
            pcall(nameFS.SetWidth, nameFS, 1)
        end
    end
end

local partyFramesForText = {}
local function collectPartyFramesForText()
    if wipe then
        wipe(partyFramesForText)
    else
        partyFramesForText = {}
    end
    for i = 1, 5 do
        local frame = _G["CompactPartyFrameMember" .. i]
        if frame and frame.name then
            local nameState = getState(frame.name)
            if not nameState or not nameState.partyTextCounted then
                local st = ensureState(frame.name)
                if st then st.partyTextCounted = true end
                table.insert(partyFramesForText, frame)
            end
        end
    end
end

function addon.ApplyPartyFrameTextStyle()
    local db = addon and addon.db and addon.db.profile
    if not db then return end

    local groupFrames = rawget(db, "groupFrames")
    local partyCfg = groupFrames and rawget(groupFrames, "party") or nil
    local cfg = partyCfg and rawget(partyCfg, "textPlayerName") or nil
    if not cfg then
        return
    end

    if not Utils.hasCustomTextSettings(cfg) then
        return
    end

    -- Deprecated: Party Player Name styling is now driven by overlay FontStrings
    -- (see ApplyPartyFrameNameOverlays). Avoid touching Blizzard's `frame.name`
    -- so overlay clipping preserves stock truncation behavior.
    if addon.ApplyPartyFrameNameOverlays then
        addon.ApplyPartyFrameNameOverlays()
    end
end

local function installPartyFrameTextHooks()
    if addon._PartyFrameTextHooksInstalled then return end
    addon._PartyFrameTextHooksInstalled = true

    -- Deprecated: name styling hooks must not touch Blizzard's `frame.name`.
    -- Overlay system installs its own hooks (installPartyNameOverlayHooks()).
end

--------------------------------------------------------------------------------
-- Text Overlay (Name Text - Combat-Safe Persistence)
--------------------------------------------------------------------------------
-- Creates addon-owned FontString overlays on party frames that visually replace
-- Blizzard's name text. These overlays can be styled during initial setup and
-- their text content can be updated during combat without taint because we only
-- manipulate our own FontStrings.
--
-- Pattern: Mirror text via SetText hook, style on setup, hide Blizzard's element.
--------------------------------------------------------------------------------

-- Apply styling to the overlay FontString
local function stylePartyNameOverlay(frame, cfg)
    local state = getState(frame)
    if not frame or not state or not state.overlayText or not cfg then return end

    local overlay = state.overlayText
    local container = state.overlayContainer or frame

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

    -- Apply font
    local success = pcall(overlay.SetFont, overlay, resolvedFace, fontSize, fontStyle)
    if not success then
        local fallback = _G.GameFontNormal and select(1, _G.GameFontNormal:GetFont())
        if fallback then
            pcall(overlay.SetFont, overlay, fallback, fontSize, fontStyle)
        end
    end

    -- Apply color
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

-- Hide Blizzard's name FontString and install alpha-enforcement hook
local function hideBlizzardPartyNameText(frame)
    if not frame or not frame.name then return end
    local blizzName = frame.name

    local nameState = ensureState(blizzName)
    if nameState then nameState.hidden = true end
    if blizzName.SetAlpha then
        pcall(blizzName.SetAlpha, blizzName, 0)
    end
    if blizzName.Hide then
        pcall(blizzName.Hide, blizzName)
    end

    -- Install alpha-enforcement hook (only once)
    if nameState and not nameState.alphaHooked and _G.hooksecurefunc then
        nameState.alphaHooked = true
        _G.hooksecurefunc(blizzName, "SetAlpha", function(self, alpha)
            local st = getState(self)
            if alpha > 0 and st and st.hidden then
                if _G.C_Timer and _G.C_Timer.After then
                    _G.C_Timer.After(0, function()
                        local st2 = getState(self)
                        if st2 and st2.hidden then
                            self:SetAlpha(0)
                        end
                    end)
                end
            end
        end)
    end

    if nameState and not nameState.showHooked and _G.hooksecurefunc then
        nameState.showHooked = true
        _G.hooksecurefunc(blizzName, "Show", function(self)
            local st = getState(self)
            if not st or not st.hidden then return end
            -- Kill visibility immediately (avoid flicker), then defer Hide to break chains.
            if self.SetAlpha then pcall(self.SetAlpha, self, 0) end
            if _G.C_Timer and _G.C_Timer.After then
                _G.C_Timer.After(0, function()
                    local st2 = getState(self)
                    if self and st2 and st2.hidden then
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

-- Show Blizzard's name FontString (for restore/cleanup)
local function showBlizzardPartyNameText(frame)
    if not frame or not frame.name then return end
    local state = getState(frame)
    if state then state.nameHidden = nil end
    if frame.name.SetAlpha then
        pcall(frame.name.SetAlpha, frame.name, 1)
    end
    if frame.name.Show then
        pcall(frame.name.Show, frame.name)
    end
end

-- Create or update the party name text overlay for a specific frame
-- 12.0 TAINT FIX: Uses lookup table instead of writing to Blizzard frames
local function ensurePartyNameOverlay(frame, cfg)
    if not frame then return end

    local hasCustom = Utils.hasCustomTextSettings(cfg)
    local state = ensureState(frame)
    state.overlayActive = hasCustom

    if not hasCustom then
        -- Disable overlay, show Blizzard's text
        if state.overlayText then
            state.overlayText:Hide()
        end
        showBlizzardPartyNameText(frame)
        return
    end

    -- Ensure an addon-owned clipping container for name text.
    -- IMPORTANT: This container must span the full available unit-frame area so 9-way alignment
    -- (e.g., BOTTOM / BOTTOMRIGHT) can genuinely reach the bottom of the frame.
    if not state.overlayContainer then
        local container = CreateFrame("Frame", nil, frame)
        container:SetClipsChildren(true)

        container:ClearAllPoints()
        -- Small insets to match CUF's typical text padding and avoid touching frame edges.
        container:SetPoint("TOPLEFT", frame, "TOPLEFT", 3, -3)
        container:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 3)

        state.overlayContainer = container
    end

    -- Create overlay FontString if it doesn't exist
    if not state.overlayText then
        local parentForText = state.overlayContainer or frame
        local overlay = parentForText:CreateFontString(nil, "OVERLAY", nil)
        overlay:SetDrawLayer("OVERLAY", 7) -- High sublayer to ensure visibility
        state.overlayText = overlay

        -- Install SetText hook on Blizzard's name FontString to mirror text
        -- Store hook state in our lookup table, not on Blizzard's frame
        if frame.name and not state.textMirrorHooked and _G.hooksecurefunc then
            state.textMirrorHooked = true
            -- Capture state reference for the closure
            local frameState = state
            _G.hooksecurefunc(frame.name, "SetText", function(self, text)
                if frameState and frameState.overlayText and frameState.overlayActive then
                    frameState.overlayText:SetText(text or "")
                end
            end)
        end
    end

    -- Style the overlay and hide Blizzard's text
    stylePartyNameOverlay(frame, cfg)
    hideBlizzardPartyNameText(frame)

    -- Copy current text from Blizzard's FontString to our overlay
    -- Wrap in pcall as GetText() can return secrets in 12.0
    if frame.name and frame.name.GetText then
        local ok, currentText = pcall(frame.name.GetText, frame.name)
        if ok and currentText then
            state.overlayText:SetText(currentText)
        end
    end

    state.overlayText:Show()
end

-- Disable overlay and restore Blizzard's appearance for a frame
local function disablePartyNameOverlay(frame)
    if not frame then return end
    local state = getState(frame)
    if state then
        state.overlayActive = false
        if state.overlayText then
            state.overlayText:Hide()
        end
    end
    showBlizzardPartyNameText(frame)
end

-- Apply overlays to all party frames
function addon.ApplyPartyFrameNameOverlays()
    local db = addon and addon.db and addon.db.profile
    if not db then return end

    local groupFrames = rawget(db, "groupFrames")
    local partyCfg = groupFrames and rawget(groupFrames, "party") or nil
    local cfg = partyCfg and rawget(partyCfg, "textPlayerName") or nil

    local hasCustom = Utils.hasCustomTextSettings(cfg)

    for i = 1, 5 do
        local frame = _G["CompactPartyFrameMember" .. i]
        if frame then
            if hasCustom then
                -- Only create overlays out of combat (initial setup)
                local state = getState(frame)
                if not (InCombatLockdown and InCombatLockdown()) then
                    ensurePartyNameOverlay(frame, cfg)
                elseif state and state.overlayText then
                    -- Already have overlay, just update styling (safe during combat for our FontString)
                    stylePartyNameOverlay(frame, cfg)
                end
            else
                disablePartyNameOverlay(frame)
            end
        end
    end
end

-- Restore all party frames to stock appearance
function addon.RestorePartyFrameNameOverlays()
    for i = 1, 5 do
        local frame = _G["CompactPartyFrameMember" .. i]
        if frame then
            disablePartyNameOverlay(frame)
        end
    end
end

-- Install hooks that trigger overlay setup/updates via CompactUnitFrame events
local function installPartyNameOverlayHooks()
    if addon._PartyNameOverlayHooksInstalled then return end
    addon._PartyNameOverlayHooksInstalled = true

    -- Hook CompactUnitFrame_UpdateAll to set up overlays
    if _G.hooksecurefunc and _G.CompactUnitFrame_UpdateAll then
        _G.hooksecurefunc("CompactUnitFrame_UpdateAll", function(frame)
            -- CRITICAL: Skip ALL processing when Edit Mode is active to avoid taint
            if isEditModeActive() then return end
            if not frame or not frame.name or not Utils.isPartyFrame(frame) then return end

            local db = addon and addon.db and addon.db.profile
            local partyCfg = db and db.groupFrames and db.groupFrames.party or nil
            local cfg = partyCfg and partyCfg.textPlayerName or nil

            if Utils.hasCustomTextSettings(cfg) then
                if _G.C_Timer and _G.C_Timer.After then
                    _G.C_Timer.After(0, function()
                        if not frame then return end
                        local state = getState(frame)
                        if not state or not state.overlayText then
                            if InCombatLockdown and InCombatLockdown() then
                                Combat.queuePartyFrameReapply()
                                return
                            end
                        end
                        ensurePartyNameOverlay(frame, cfg)
                    end)
                end
            end
        end)
    end

    -- Hook CompactUnitFrame_SetUnit for unit assignment changes
    if _G.hooksecurefunc and _G.CompactUnitFrame_SetUnit then
        _G.hooksecurefunc("CompactUnitFrame_SetUnit", function(frame, unit)
            -- CRITICAL: Skip ALL processing when Edit Mode is active to avoid taint
            if isEditModeActive() then return end
            if not unit or not frame or not frame.name or not Utils.isPartyFrame(frame) then return end

            local db = addon and addon.db and addon.db.profile
            local partyCfg = db and db.groupFrames and db.groupFrames.party or nil
            local cfg = partyCfg and partyCfg.textPlayerName or nil

            if Utils.hasCustomTextSettings(cfg) then
                if _G.C_Timer and _G.C_Timer.After then
                    _G.C_Timer.After(0, function()
                        if not frame then return end
                        local state = getState(frame)
                        if not state or not state.overlayText then
                            if InCombatLockdown and InCombatLockdown() then
                                Combat.queuePartyFrameReapply()
                                return
                            end
                        end
                        ensurePartyNameOverlay(frame, cfg)
                    end)
                end
            end
        end)
    end

    -- Hook CompactUnitFrame_UpdateName for name text updates
    if _G.hooksecurefunc and _G.CompactUnitFrame_UpdateName then
        _G.hooksecurefunc("CompactUnitFrame_UpdateName", function(frame)
            -- CRITICAL: Skip ALL processing when Edit Mode is active to avoid taint
            if isEditModeActive() then return end
            if not frame or not frame.name or not Utils.isPartyFrame(frame) then return end

            local db = addon and addon.db and addon.db.profile
            local partyCfg = db and db.groupFrames and db.groupFrames.party or nil
            local cfg = partyCfg and partyCfg.textPlayerName or nil

            if Utils.hasCustomTextSettings(cfg) then
                if _G.C_Timer and _G.C_Timer.After then
                    _G.C_Timer.After(0, function()
                        if not frame then return end
                        local state = getState(frame)
                        if not state or not state.overlayText then
                            if InCombatLockdown and InCombatLockdown() then
                                Combat.queuePartyFrameReapply()
                                return
                            end
                        end
                        ensurePartyNameOverlay(frame, cfg)
                    end)
                end
            end
        end)
    end
end

--------------------------------------------------------------------------------
-- Text Styling (Party Title)
--------------------------------------------------------------------------------
-- Applies the same 7 settings as Party Frames > Text > Player Name to the party frame title text.
-- Target: CompactPartyFrame.title (Button from CompactRaidGroupTemplate: "$parentTitle", parentKey="title").
--------------------------------------------------------------------------------

local function applyTextToFontString_PartyTitle(fs, ownerFrame, cfg)
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

    local fsState = ensureState(fs)
    if fsState and not fsState.originalPointPartyTitle then
        local point, relativeTo, relativePoint, x, y = fs:GetPoint(1)
        if point then
            fsState.originalPointPartyTitle = { point, relativeTo, relativePoint, x or 0, y or 0 }
        end
    end

    local isDefaultAnchor = (anchor == "TOPLEFT")
    local isZeroOffset = (offsetX == 0 and offsetY == 0)

    if isDefaultAnchor and isZeroOffset and fsState and fsState.originalPointPartyTitle then
        local orig = fsState.originalPointPartyTitle
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

local function applyPartyTitle(titleButton, cfg)
    if not titleButton or not cfg then return end
    if not titleButton.GetFontString then return end
    local fs = titleButton:GetFontString()
    if not fs then return end
    if cfg.hide == true then
        -- Hide always wins; styling is irrelevant while hidden.
        -- The hide logic is handled by hideBlizzardPartyTitleText below.
        return
    end
    applyTextToFontString_PartyTitle(fs, titleButton, cfg)
end

-- Hide Blizzard's party title FontString and install alpha-enforcement hook
local function hideBlizzardPartyTitleText(titleButton)
    if not titleButton or not titleButton.GetFontString then return end
    local fs = titleButton:GetFontString()
    if not fs then return end

    local fsState = ensureState(fs)
    if fsState then fsState.hidden = true end
    if fs.SetAlpha then
        pcall(fs.SetAlpha, fs, 0)
    end
    if fs.Hide then
        pcall(fs.Hide, fs)
    end

    -- Install alpha-enforcement hook (only once)
    if fsState and not fsState.alphaHooked and _G.hooksecurefunc then
        fsState.alphaHooked = true
        _G.hooksecurefunc(fs, "SetAlpha", function(self, alpha)
            local st = getState(self)
            if alpha > 0 and st and st.hidden then
                if _G.C_Timer and _G.C_Timer.After then
                    _G.C_Timer.After(0, function()
                        local st2 = getState(self)
                        if self and st2 and st2.hidden then
                            self:SetAlpha(0)
                        end
                    end)
                end
            end
        end)
    end

    if fsState and not fsState.showHooked and _G.hooksecurefunc then
        fsState.showHooked = true
        _G.hooksecurefunc(fs, "Show", function(self)
            local st = getState(self)
            if not st or not st.hidden then return end
            -- Kill visibility immediately (avoid flicker), then defer Hide to break chains.
            if self.SetAlpha then pcall(self.SetAlpha, self, 0) end
            if _G.C_Timer and _G.C_Timer.After then
                _G.C_Timer.After(0, function()
                    local st2 = getState(self)
                    if self and st2 and st2.hidden then
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

-- Show Blizzard's party title FontString (for restore/cleanup)
local function showBlizzardPartyTitleText(titleButton)
    if not titleButton or not titleButton.GetFontString then return end
    local fs = titleButton:GetFontString()
    if not fs then return end
    local fsState = getState(fs)
    if fsState then fsState.hidden = nil end
    if fs.SetAlpha then
        pcall(fs.SetAlpha, fs, 1)
    end
    if fs.Show then
        pcall(fs.Show, fs)
    end
end

function addon.ApplyPartyFrameTitleStyle()
    local db = addon and addon.db and addon.db.profile
    if not db then return end

    local groupFrames = rawget(db, "groupFrames")
    local partyCfg = groupFrames and rawget(groupFrames, "party") or nil
    local cfg = partyCfg and rawget(partyCfg, "textPartyTitle") or nil
    if not cfg then
        return
    end

    -- If the user has asked to hide it, do that even if other style settings are default.
    if cfg.hide ~= true and not Utils.hasCustomTextSettings(cfg) then
        return
    end

    if InCombatLockdown and InCombatLockdown() then
        Combat.queuePartyFrameReapply()
        return
    end

    local partyFrame = _G.CompactPartyFrame
    local titleButton = partyFrame and partyFrame.title or _G.CompactPartyFrameTitle
    if titleButton then
        if cfg.hide == true then
            hideBlizzardPartyTitleText(titleButton)
        else
            showBlizzardPartyTitleText(titleButton)
            applyPartyTitle(titleButton, cfg)
        end
    end
end

local function installPartyTitleHooks()
    if addon._PartyFrameTitleHooksInstalled then return end
    addon._PartyFrameTitleHooksInstalled = true

    local function tryApply(groupFrame)
        if not groupFrame or not Utils.isCompactPartyFrame(groupFrame) then
            return
        end
        local db = addon and addon.db and addon.db.profile
        local cfg = db and db.groupFrames and db.groupFrames.party and db.groupFrames.party.textPartyTitle or nil
        if not cfg then
            return
        end
        if cfg.hide ~= true and not Utils.hasCustomTextSettings(cfg) then
            return
        end

        local titleButton = groupFrame.title or _G[groupFrame:GetName() .. "Title"]
        if not titleButton then return end

        local titleRef = titleButton
        local cfgRef = cfg
        if _G.C_Timer and _G.C_Timer.After then
            _G.C_Timer.After(0, function()
                if InCombatLockdown and InCombatLockdown() then
                    Combat.queuePartyFrameReapply()
                    return
                end
                if cfgRef.hide == true then
                    hideBlizzardPartyTitleText(titleRef)
                else
                    showBlizzardPartyTitleText(titleRef)
                    applyPartyTitle(titleRef, cfgRef)
                end
            end)
        else
            if InCombatLockdown and InCombatLockdown() then
                Combat.queuePartyFrameReapply()
                return
            end
            if cfgRef.hide == true then
                hideBlizzardPartyTitleText(titleRef)
            else
                showBlizzardPartyTitleText(titleRef)
                applyPartyTitle(titleRef, cfgRef)
            end
        end
    end

    if _G.hooksecurefunc then
        if _G.CompactRaidGroup_UpdateLayout then
            _G.hooksecurefunc("CompactRaidGroup_UpdateLayout", tryApply)
        end
        if _G.CompactRaidGroup_UpdateUnits then
            _G.hooksecurefunc("CompactRaidGroup_UpdateUnits", tryApply)
        end
        if _G.CompactRaidGroup_UpdateBorder then
            _G.hooksecurefunc("CompactRaidGroup_UpdateBorder", tryApply)
        end
    end
end

--------------------------------------------------------------------------------
-- Text Hook Installation
--------------------------------------------------------------------------------

function PartyFrames.installTextHooks()
    installPartyFrameTextHooks()
    installPartyNameOverlayHooks()
    installPartyTitleHooks()
end

-- Install text hooks on load
PartyFrames.installTextHooks()

return PartyFrames
