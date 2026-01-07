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
        local overlay = bar:CreateTexture(nil, "OVERLAY", nil, 2)
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

return RaidFrames
