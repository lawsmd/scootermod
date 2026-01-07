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
    if not bar or not bar.ScooterPartyHealthFill then return end
    if not bar._ScootPartyOverlayActive then
        bar.ScooterPartyHealthFill:Hide()
        return
    end

    local overlay = bar.ScooterPartyHealthFill
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
    if not bar or not bar.ScooterPartyHealthFill or not cfg then return end

    local overlay = bar.ScooterPartyHealthFill
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
function PartyFrames.ensureHealthOverlay(bar, cfg)
    if not bar then return end

    local hasCustom = cfg and (
        (cfg.healthBarTexture and cfg.healthBarTexture ~= "default") or
        (cfg.healthBarColorMode and cfg.healthBarColorMode ~= "default")
    )

    bar._ScootPartyOverlayActive = hasCustom

    if not hasCustom then
        if bar.ScooterPartyHealthFill then
            bar.ScooterPartyHealthFill:Hide()
        end
        showBlizzardFill(bar)
        return
    end

    if not bar.ScooterPartyHealthFill then
        local overlay = bar:CreateTexture(nil, "OVERLAY", nil, 2)
        overlay:SetVertTile(false)
        overlay:SetHorizTile(false)
        overlay:SetTexCoord(0, 1, 0, 1)
        bar.ScooterPartyHealthFill = overlay

        if _G.hooksecurefunc and not bar._ScootPartyOverlayHooksInstalled then
            bar._ScootPartyOverlayHooksInstalled = true
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

    if not bar._ScootPartyTextureSwapHooked and _G.hooksecurefunc then
        bar._ScootPartyTextureSwapHooked = true
        _G.hooksecurefunc(bar, "SetStatusBarTexture", function(self)
            if self._ScootPartyOverlayActive then
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
    bar._ScootPartyOverlayActive = false
    if bar.ScooterPartyHealthFill then
        bar.ScooterPartyHealthFill:Hide()
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
                elseif bar.ScooterPartyHealthFill then
                    styleHealthOverlay(bar, cfg)
                    updateHealthOverlay(bar)
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

function PartyFrames.installHooks()
    if addon._PartyFrameHooksInstalled then return end
    addon._PartyFrameHooksInstalled = true

    -- Hook CompactUnitFrame_UpdateAll
    if _G.hooksecurefunc and _G.CompactUnitFrame_UpdateAll then
        _G.hooksecurefunc("CompactUnitFrame_UpdateAll", function(frame)
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
        if frame and frame.name and not frame.name._ScootPartyTextCounted then
            frame.name._ScootPartyTextCounted = true
            table.insert(partyFramesForText, frame)
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
    if not frame or not frame.ScooterPartyNameText or not cfg then return end

    local overlay = frame.ScooterPartyNameText
    local container = frame.ScooterPartyNameContainer or frame

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

    -- Apply text alignment
    pcall(overlay.SetJustifyH, overlay, Utils.getJustifyHFromAnchor(anchor))
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

    -- Keep the clipping container tall enough for the configured font size.
    -- If the container is created too early (before Blizzard sizes `frame.name`), it can end up 1px tall,
    -- which clips the overlay into a thin horizontal sliver.
    if container and container.SetHeight then
        local minH = math.max(12, (tonumber(fontSize) or 12) + 6)
        if overlay.GetStringHeight then
            local okSH, sh = pcall(overlay.GetStringHeight, overlay)
            if okSH and sh and sh > 0 and (sh + 2) > minH then
                minH = sh + 2
            end
        end
        pcall(container.SetHeight, container, minH)
    end

    -- Position within an addon-owned clipping container that matches Blizzard's original name anchors.
    overlay:ClearAllPoints()
    overlay:SetPoint(anchor, container, anchor, offsetX, offsetY)
end

-- Hide Blizzard's name FontString and install alpha-enforcement hook
local function hideBlizzardPartyNameText(frame)
    if not frame or not frame.name then return end
    local blizzName = frame.name

    blizzName._ScootHidden = true
    if blizzName.SetAlpha then
        pcall(blizzName.SetAlpha, blizzName, 0)
    end
    if blizzName.Hide then
        pcall(blizzName.Hide, blizzName)
    end

    -- Install alpha-enforcement hook (only once)
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

-- Show Blizzard's name FontString (for restore/cleanup)
local function showBlizzardPartyNameText(frame)
    if not frame or not frame.name then return end
    frame.name._ScootHidden = nil
    if frame.name.SetAlpha then
        pcall(frame.name.SetAlpha, frame.name, 1)
    end
    if frame.name.Show then
        pcall(frame.name.Show, frame.name)
    end
end

-- Create or update the party name text overlay for a specific frame
local function ensurePartyNameOverlay(frame, cfg)
    if not frame then return end

    local hasCustom = Utils.hasCustomTextSettings(cfg)
    frame._ScootPartyNameOverlayActive = hasCustom

    if not hasCustom then
        -- Disable overlay, show Blizzard's text
        if frame.ScooterPartyNameText then
            frame.ScooterPartyNameText:Hide()
        end
        showBlizzardPartyNameText(frame)
        return
    end

    -- Ensure an addon-owned clipping container that matches Blizzard's original name anchors.
    if not frame.ScooterPartyNameContainer then
        local container = CreateFrame("Frame", nil, frame)
        container:SetClipsChildren(true)

        local p1, r1, rp1, x1, y1 = nil, nil, nil, 0, 0
        local p2, r2, rp2, x2, y2 = nil, nil, nil, 0, 0
        if frame.name and frame.name.GetPoint then
            local ok1, ap1, ar1, arp1, ax1, ay1 = pcall(frame.name.GetPoint, frame.name, 1)
            if ok1 then
                p1, r1, rp1, x1, y1 = ap1, ar1, arp1, ax1, ay1
            end
            local ok2, ap2, ar2, arp2, ax2, ay2 = pcall(frame.name.GetPoint, frame.name, 2)
            if ok2 then
                p2, r2, rp2, x2, y2 = ap2, ar2, arp2, ax2, ay2
            end
        end

        container:ClearAllPoints()
        if p1 then
            container:SetPoint(p1, r1 or frame, rp1 or p1, tonumber(x1) or 0, tonumber(y1) or 0)
            if p2 then
                container:SetPoint(p2, r2 or frame, rp2 or p2, tonumber(x2) or 0, tonumber(y2) or 0)
            else
                container:SetPoint("RIGHT", frame, "RIGHT", -3, 0)
            end
        else
            container:SetPoint("LEFT", frame, "LEFT", 3, 0)
            container:SetPoint("RIGHT", frame, "RIGHT", -3, 0)
        end

        -- Critical: container must have height or it will clip everything.
        local fontSize = tonumber(cfg and cfg.size) or 12
        local h = math.max(12, fontSize + 6)
        if frame.name and frame.name.GetHeight then
            local okH, hh = pcall(frame.name.GetHeight, frame.name)
            if okH and hh and hh > h then
                h = hh
            end
        end
        if container.SetHeight then
            pcall(container.SetHeight, container, h)
        end

        frame.ScooterPartyNameContainer = container
    end

    -- Create overlay FontString if it doesn't exist
    if not frame.ScooterPartyNameText then
        local parentForText = frame.ScooterPartyNameContainer or frame
        local overlay = parentForText:CreateFontString(nil, "OVERLAY", nil)
        overlay:SetDrawLayer("OVERLAY", 7) -- High sublayer to ensure visibility
        frame.ScooterPartyNameText = overlay

        -- Install SetText hook on Blizzard's name FontString to mirror text
        if frame.name and not frame.name._ScootTextMirrorHooked and _G.hooksecurefunc then
            frame.name._ScootTextMirrorHooked = true
            frame.name._ScootTextMirrorOwner = frame
            _G.hooksecurefunc(frame.name, "SetText", function(self, text)
                local owner = self._ScootTextMirrorOwner
                if owner and owner.ScooterPartyNameText and owner._ScootPartyNameOverlayActive then
                    owner.ScooterPartyNameText:SetText(text or "")
                end
            end)
        end
    end

    -- Style the overlay and hide Blizzard's text
    stylePartyNameOverlay(frame, cfg)
    hideBlizzardPartyNameText(frame)

    -- Copy current text from Blizzard's FontString to our overlay
    if frame.name and frame.name.GetText then
        local currentText = frame.name:GetText()
        frame.ScooterPartyNameText:SetText(currentText or "")
    end

    frame.ScooterPartyNameText:Show()
end

-- Disable overlay and restore Blizzard's appearance for a frame
local function disablePartyNameOverlay(frame)
    if not frame then return end
    frame._ScootPartyNameOverlayActive = false
    if frame.ScooterPartyNameText then
        frame.ScooterPartyNameText:Hide()
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
                if not (InCombatLockdown and InCombatLockdown()) then
                    ensurePartyNameOverlay(frame, cfg)
                elseif frame.ScooterPartyNameText then
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
            if not frame or not frame.name or not Utils.isPartyFrame(frame) then return end

            local db = addon and addon.db and addon.db.profile
            local partyCfg = db and db.groupFrames and db.groupFrames.party or nil
            local cfg = partyCfg and partyCfg.textPlayerName or nil

            if Utils.hasCustomTextSettings(cfg) then
                if _G.C_Timer and _G.C_Timer.After then
                    _G.C_Timer.After(0, function()
                        if not frame then return end
                        if not frame.ScooterPartyNameText then
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
            if not unit or not frame or not frame.name or not Utils.isPartyFrame(frame) then return end

            local db = addon and addon.db and addon.db.profile
            local partyCfg = db and db.groupFrames and db.groupFrames.party or nil
            local cfg = partyCfg and partyCfg.textPlayerName or nil

            if Utils.hasCustomTextSettings(cfg) then
                if _G.C_Timer and _G.C_Timer.After then
                    _G.C_Timer.After(0, function()
                        if not frame then return end
                        if not frame.ScooterPartyNameText then
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
            if not frame or not frame.name or not Utils.isPartyFrame(frame) then return end

            local db = addon and addon.db and addon.db.profile
            local partyCfg = db and db.groupFrames and db.groupFrames.party or nil
            local cfg = partyCfg and partyCfg.textPlayerName or nil

            if Utils.hasCustomTextSettings(cfg) then
                if _G.C_Timer and _G.C_Timer.After then
                    _G.C_Timer.After(0, function()
                        if not frame then return end
                        if not frame.ScooterPartyNameText then
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

    if not fs._ScootOriginalPoint_PartyTitle then
        local point, relativeTo, relativePoint, x, y = fs:GetPoint(1)
        if point then
            fs._ScootOriginalPoint_PartyTitle = { point, relativeTo, relativePoint, x or 0, y or 0 }
        end
    end

    local isDefaultAnchor = (anchor == "TOPLEFT")
    local isZeroOffset = (offsetX == 0 and offsetY == 0)

    if isDefaultAnchor and isZeroOffset and fs._ScootOriginalPoint_PartyTitle then
        local orig = fs._ScootOriginalPoint_PartyTitle
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

    fs._ScootHidden = true
    if fs.SetAlpha then
        pcall(fs.SetAlpha, fs, 0)
    end
    if fs.Hide then
        pcall(fs.Hide, fs)
    end

    -- Install alpha-enforcement hook (only once)
    if not fs._ScootAlphaHooked and _G.hooksecurefunc then
        fs._ScootAlphaHooked = true
        _G.hooksecurefunc(fs, "SetAlpha", function(self, alpha)
            if alpha > 0 and self._ScootHidden then
                if _G.C_Timer and _G.C_Timer.After then
                    _G.C_Timer.After(0, function()
                        if self and self._ScootHidden then
                            self:SetAlpha(0)
                        end
                    end)
                end
            end
        end)
    end

    if not fs._ScootShowHooked and _G.hooksecurefunc then
        fs._ScootShowHooked = true
        _G.hooksecurefunc(fs, "Show", function(self)
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

-- Show Blizzard's party title FontString (for restore/cleanup)
local function showBlizzardPartyTitleText(titleButton)
    if not titleButton or not titleButton.GetFontString then return end
    local fs = titleButton:GetFontString()
    if not fs then return end
    fs._ScootHidden = nil
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
